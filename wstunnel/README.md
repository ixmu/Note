# wstunnel 安全部署文档

> 版本基准：**wstunnel v11.1.0**（Rust 版，已核对 = 上游 GitHub Releases 最新版）
> 部署形态：**服务端与客户端都跑 Podman 容器**（`ghcr.io/erebe/wstunnel`，rootless 用户单元）
> 首次整理 2026-11-22 · 审计修订 2026-11-28（同日六次跟进：服务端 → 容器、路径前缀改 `cdn-socket-stream`、客户端 → 容器、两端单元统一为 `container-wstunnel-{server,client}.service` 成对命名、配置目录统一到 `/etc/wstunnel`、客户端凭据直接写进 unit（不再用 `auth.txt`）、
> 真机跑通两个单元的生命周期与端到端转发并补齐私有 CA 信任配方（§7.10））
> 特点：自有域名 + SSL 证书（wss）+ 双重鉴权（路径前缀 + Basic）+ 目标 `host:port` 白名单
> 本文件原名 `wstunnel部署文档.md`，已重命名为 `README.md`，便于在 GitHub 上进入 `wstunnel/` 目录直接阅读。

## 0. 本目录文件与快速上手

| 文件 | 用途 | 落地路径 |
|---|---|---|
| `container-wstunnel-server.service` | 服务端 systemd unit（podman run 形态，rootless） | `~/.config/systemd/user/` |
| `container-wstunnel-client.service` | 客户端 systemd unit（podman run 形态，rootless） | `~/.config/systemd/user/` |
| `restrictions.yaml` | 服务端白名单授权 | `/etc/wstunnel/restrictions.yaml` |
| `README.md` | 本文档 | — |

两个单元都是 `podman generate systemd` 风格（`ExecStart=podman run …`、`Type=notify` + `--sdnotify=conmon`、`WantedBy=default.target`），命名成对（`container-wstunnel-server` / `container-wstunnel-client`），全部操作按当前用户执行，不需要 `sudo`（`/opt`、`/etc` 的写入属主除外）。

> ✅ 两个单元已在真机（Debian 13 + podman 5.4.2 + systemd 257）装起来跑通生命周期与端到端转发，实测记录与新增结论见 §7.10。
>
> 服务端单元原名 `container-wstunnel.service`，已 `git mv` 为 `container-wstunnel-server.service`（改名原因与代价见 §3.5、结论 #26–#27）。

```bash
# 部署前必须全局替换的 4 个占位值
#   tunnel.example.com  → 你的域名
#   cdn-socket-stream   → 路径前缀暗号
#   Wstunnel-2026       → Basic 密码（改动后同步 base64，见 §6.1）
#   podmanv6            → 服务端用的 podman 网络名（需预先创建，见 §3.2）
# 两条暗号都在客户端 unit 的 ExecStart 里（-P <前缀> 与 --http-upgrade-credentials <user:pass>），
# 服务端侧对应 restrictions.yaml 的 !PathPrefix / !Authorization，替换时要一一对上（§6.1、§6.2）
```

## 1. 架构总览

```
[客户端机器]                                  [wstunnel 服务器]                [目标服务]
 本地:2223  ──┐                          ┌── wss://[::]:55443 ─────┐
 本地:10001 ──┤   wss://域名:55443        │  Podman 容器 + TLS 证书  │
 本地:10000 ──┼─────────────────────────►│  双鉴权 + restrictions   ├──────────► 目标 host:port
 本地:8101  ──┤   (WebSocket over TLS)   │  白名单；证书/配置热加载 │
 本地:5002  ──┤                          └─────────────────────────┘
 本地:55689 ──┘
```

- 隧道的实际连接动作发生在**服务器侧**（含域名解析），客户端只负责把流量送进 wss 隧道。
- 反向隧道（`-R`）当前策略为**禁止**：`restrictions.yaml` 里没有声明 `!ReverseTunnel`，源码里未列出的类型一律拒绝。
- **鉴权模型要点（源码核实）**：客户端把「目标 host / port / 协议」打包成 JWT 放在 `Sec-WebSocket-Protocol: authorization.bearer.<jwt>` 里送给服务端，服务端用 `jsonwebtoken::dangerous::insecure_decode` **不验签**地解开。也就是说目标地址是客户端自己声明的，`restrictions.yaml` 是**唯一真正的强制点**——不要指望 JWT 本身起限制作用。

## 2. 参数清单

| 项目 | 值 | 备注 |
|---|---|---|
| 服务端口 | `55443/tcp` | 非标端口，需在防火墙放行 |
| 协议 | `wss://`（WebSocket over TLS） | 证书与端口无关，只对域名生效 |
| 路径前缀（暗号1） | `cdn-socket-stream` | 客户端单元里写死命令行 `-P cdn-socket-stream`（也有等价环境变量 `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX`，但**只写一个**且 `-P` 优先，理由见 §4.3 第 1 条、§7.9 #43）；线上请求路径固定为 `/{前缀}/events`；**两个入口都不给时默认前缀退回 `v1`，会被 restrictions 直接拒（400）** |
| Basic 账号（暗号2） | `wstunnel:Wstunnel-2026` | base64: `d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==`（已用 `printf … \| base64` 复核一致） |
| 配置根目录 | `/etc/wstunnel/`（**服务端专用**） | 证书 + `restrictions.yaml`；客户端不挂宿主机文件，凭据写在 unit 里（§4.1）。服务端历史版本用 `/opt/wstunnel`，已统一，迁移见 §3.1 |
| 证书文件 | `/etc/wstunnel/fullchain.pem` + `privkey.pem` | 容器内同路径（bind mount）；自动热加载 |
| 限制文件 | `/etc/wstunnel/restrictions.yaml` | 自动热加载，改完即生效 |
| 客户端凭据（暗号2） | 写在 `container-wstunnel-client.service` 的 `--http-upgrade-credentials` 里 | unit 必须 600；换密码要重启。文件方案（`/etc/wstunnel/auth.txt` + `--http-headers-file`）见 §4.1 |
| 运行镜像 | `ghcr.io/erebe/wstunnel` | 镜像内二进制 `/home/app/wstunnel`，`USER app`（非 root），内置 `ca-certificates` + `dumb-init` |
| mTLS 强化（可选） | `/etc/wstunnel/ca.pem` | 服务端 `--tls-client-ca-certs /etc/wstunnel/ca.pem` |

### 隧道映射表（6 条）

| 客户端本地端口 | 目标地址:端口 | 白名单方式 |
|---|---|---|
| 2223 | `gw.pyproxy.com:2222` | host 正则 |
| 10001 | `hk.rp.linkup.onl:10000` | host 正则 |
| 10000 | `43.134.70.211:9999` | cidr `/32` |
| 8101 | `proxy.momoproxy.com:8100` | host 正则 |
| 5002 | `us.rapidproxy.io:5001` | host 正则 |
| 55689 | `45.149.172.51:55688` | cidr `/32` |

> 白名单端口：`2222 / 5001 / 8100 / 9999 / 10000 / 55688`（与映射表一一对应）

## 3. 服务端部署（Podman 容器）

### 3.1 落地位置

| 内容 | 路径 | 权限建议 |
|---|---|---|
| 配置目录 | `/etc/wstunnel/` | 755，属主＝部署用户（原因见下方说明） |
| 证书链 | `/etc/wstunnel/fullchain.pem` | 644 |
| 私钥 | `/etc/wstunnel/privkey.pem` | 600（**必须让容器内 uid 读到，见 §3.3**） |
| 白名单 | `/etc/wstunnel/restrictions.yaml` | 640 |
| 客户端凭据 | `/etc/wstunnel/auth.txt` | 600（**仅文件方案需要**；本方案凭据写在 unit 里，见 §4.1） |
| 单元文件 | `~/.config/systemd/user/container-wstunnel-server.service` | 644 |
| 数据/运行目录 | `%t/containers`（`RequiresMountsFor`）、`%t/%n.ctr-id` | systemd 自动管理 |

目录属主说明：只读 bind mount 本身只要目录可**穿越**（`root:root` 755 就够，读文件看文件自身权限），但 `:z` 重标 SELinux 标签需要写权限、certbot deploy-hook 之后新建的文件也要能被部署用户覆盖 ⇒ 直接把目录交给部署用户最省事（§3.2）。
两端同机时目录共用：本方案客户端不挂这个目录，不受影响；若改回文件凭据方案（§4.1），客户端的只读挂载会把服务端 `privkey.pem` 一并带进客户端容器，要隔离就改成文件级挂载或用 `/etc/wstunnel/{server,client}/` 子目录。

从 `/opt/wstunnel` 迁移（约 5 秒断流，可与 §3.5 的 unit 改名合并成一次操作）：

```bash
sudo install -d -m755 -o "$(id -u)" -g "$(id -g)" /etc/wstunnel
sudo mv /opt/wstunnel/* /etc/wstunnel/
chmod 600 /etc/wstunnel/privkey.pem && chmod 640 /etc/wstunnel/restrictions.yaml
sed -i 's#/opt/wstunnel#/etc/wstunnel#g' ~/.config/systemd/user/container-wstunnel-server.service
systemctl --user daemon-reload && systemctl --user restart container-wstunnel-server
rmdir /opt/wstunnel 2>/dev/null                     # 掏空后再删，别 -rf
```

> 裸机二进制部署（不用容器）见 §3.6，本目录历史版本即为该形态。

### 3.2 部署命令

```bash
podman --version                                   # 建议 ≥ 4.x
podman network exists podmanv6 || podman network create --ipv6 podmanv6
podman pull ghcr.io/erebe/wstunnel:latest   # 单元里用的是 :latest；§3.4 建议两个单元一起固定成 :v11.1.0

# /etc 归 root 管：建目录时就把属主交给部署用户（rootless 容器读不到别人 600 的文件）
sudo install -d -m755 -o "$(id -u)" -g "$(id -g)" /etc/wstunnel
# 上传 fullchain.pem / privkey.pem / restrictions.yaml 到 /etc/wstunnel/ 后：
chmod 644 /etc/wstunnel/fullchain.pem
chmod 600 /etc/wstunnel/privkey.pem
chmod 640 /etc/wstunnel/restrictions.yaml
chown -R "$(id -u)":"$(id -g)" /etc/wstunnel        # 经 root 之手放进来的文件在这里补属主
sudo setsebool -P container_use_nfs 1 2>/dev/null   # 仅当 /etc/wstunnel 在 NFS 上；SELinux 标签见 §3.3

install -Dm644 container-wstunnel-server.service ~/.config/systemd/user/container-wstunnel-server.service
systemd-analyze --user verify ~/.config/systemd/user/container-wstunnel-server.service
systemctl --user daemon-reload
systemctl --user enable --now container-wstunnel-server.service
loginctl enable-linger "$USER"                     # 关键：不 linger 则重启后不会自启
podman logs --tail 50 wstunnel                     # 看到 listening on [::]:55443 即成功

# 防火墙（服务端本机）
sudo firewall-cmd --permanent --add-port=55443/tcp && sudo firewall-cmd --reload
# 或: sudo ufw allow 55443/tcp
```

### 3.3 卷与权限：容器化后最容易踩的坑

上游镜像 `Dockerfile` 里 `RUN useradd -ms /bin/bash app` + `USER app`，**容器内进程是 uid/gid 1000 的非 root 用户**，所以裸机方案里「root 读 600 私钥」的前提不成立：

| 现象 | 原因 | 处理（三选一） |
|---|---|---|
| `podman logs wstunnel` 出现 `Permission denied` 读 privkey/restrictions | 文件属主与容器内映射 uid 不对应 | ① 容器加 `--user 0:0`（rootless 下即部署者本人，600 私钥直接可读，**本方案采用**）② 卷加 `U` 选项：`-v /etc/wstunnel:/etc/wstunnel:ro,U`（podman ≥3.4，会把挂载目录 chown 给容器 uid——等于让它改你 `/etc` 下的属主）③ 手工把属主/属组调成容器映射 uid（部署用户 subuid 起点 + 1000，最脆） |
| rootful 运行时全部文件读不到 | `USER app`(1000) ≠ 文件属主，600 私钥不可读 | `chgrp 1000 /etc/wstunnel/privkey.pem && chmod 640 …`，或 `--user 0:0` |
| SELinux enforcing 下报 `Permission denied`（文件权限看起来没问题） | bind mount 缺少安全标签 | 卷尾加 `,z`（同机多容器共享标签）或 `,Z`（独占）：`-v /etc/wstunnel:/etc/wstunnel:ro,z`。**`/etc` 下默认标签是 `etc_t`，`:z` 会重标成 `container_file_t`；filetrans 规则又会让之后新建的文件拿回 `etc_t`** ⇒ 固化：`semanage fcontext -a -t container_file_t '/etc/wstunnel(/.*)?' && restorecon -RF /etc/wstunnel`（§7.6 #31，无 SELinux 环境未实测） |

另外两点与卷直接相关：

- **卷只读（本轮已落地）**：两个单元统一 `-v /etc/wstunnel:/etc/wstunnel:ro,z`。wstunnel 对证书与 restrictions 只需**读取**，热加载走 inotify，写发生在宿主机侧、同一个 inode，只读挂载照样收得到事件（**真机已实测**：向 `/etc/wstunnel/restrictions.yaml` 追加一条规则后服务端未重启即放行新目标，§7.10 #53；SELinux enforcing 分支仍未实测）；root 放进 `/etc` 的配置也不会被容器内进程改写。证书续期由宿主机侧 deploy-hook 写入（§5.2）。
- **镜像只有一个**：`server` 与 `client` 是同一镜像的两个子命令，两个单元的镜像引用必须逐字一致（差异只在结尾子命令，见 §4 开头对照表）。
- **`--network podmanv6` 必须已存在**，否则服务进入 restart loop；容器内解析公网域名走该网络的内置 DNS（aardvark-dns 转发宿主机 resolver）。宿主机 DNS 异常时给 wstunnel 追加 `--dns-resolver dns://223.5.5.5`（DoT 用 `dns+tls://8.8.8.8?sni=dns.google`）。

### 3.4 镜像与自动更新

- `--label io.containers.autoupdate=registry` 只有在 timer 真正跑起来时才生效：`systemctl --user list-timers | grep auto-update`，没有就 `systemctl --user enable --now podman-auto-update.timer`。手动触发/预览：`podman auto-update --dry-run`、`podman auto-update`。
- 更新会重建容器（`--rm` + `Restart=always` + `--replace` 负责收尾），`restrictions.yaml`、证书（以及文件方案下的 `auth.txt`）都在宿主机上，不会丢；代价是**所有隧道会瞬断一次**，建议放在更新窗口内执行。
- **`:latest` 与文档基准冲突**：本文按 v11.1.0 核对，而 `:latest` 会随上游发版漂移（大版本可能改参数名）。建议两个单元一起固定成 `ghcr.io/erebe/wstunnel:v11.1.0`（同一镜像的两个角色，见 §4 对照表），升级时显式改 tag（`ghcr.io` 上 `latest` 没有回滚锚点）。换 tag 一行搞定：`sed -i 's#wstunnel:latest#wstunnel:v11.1.0#' container-wstunnel-{server,client}.service`。
- `wss://[::]:55443` 已监听双栈；若将来启用 WebTransport（`wts://` 或 `--enable-webtransport`），`-p 55443:55443` 只映射 TCP，需补 `-p 55443:55443/udp`，并在防火墙放行 UDP。

### 3.5 单元里可以补的几行

```ini
[Unit]
# 服务端单元未设 StartLimit*，走 systemd 默认（10s 内 5 次即进 failed 状态）。
# 想让它在证书/网络异常期间持续自愈，加：
StartLimitIntervalSec=0
# 单元文件里没有 ExecReload；改配置靠热加载，换镜像靠 podman auto-update，
# 只有改启动参数时才需要 systemctl --user restart container-wstunnel-server

[Service]
# 真机实测：`systemctl --user stop` 之后 unit 落在 failed（Result=exit-code、ExecMainStatus=143）
# 而不是 inactive —— 镜像的 ENTRYPOINT 是 dumb-init，收到 SIGTERM 后转发给子进程并以 143 退出，
# 退出码原样传给 systemd（§7.10 #51）。想让"正常停止"显示成干净状态就加下面这行：
SuccessExitStatus=143
# 实测加上以后 stop → inactive / Result=success，且 Restart=always 不受影响（容器被 kill 仍自愈、
# NRestarts 照常递增）。若还想把 OOM/被 SIGKILL 也记成"正常"，写成 `SuccessExitStatus=143 137`，
# 代价是真异常退出也不再标 failed ⇒ 判活别只靠 is-active
```

日志排查用 `podman logs -f wstunnel`（容器 stdout）与 `journalctl --user -u container-wstunnel-server.service`（生命周期）。客户端单元已自带 `StartLimitIntervalSec=0` 与 `RestartSec=5`。

**unit 改名迁移**（`container-wstunnel.service` → `container-wstunnel-server.service`，约 5 秒断流）：

```bash
systemctl --user disable --now container-wstunnel.service    # 旧 unit 自己 stop/rm，此时 cidfile 还是旧路径
rm -f ~/.config/systemd/user/container-wstunnel.service \
      "$XDG_RUNTIME_DIR"/container-wstunnel.service.ctr-id   # 旧 cidfile 残留（%n 变了），留着也无害
podman ps -a --filter name=wstunnel                          # 确认没有无主容器；有就 podman rm -f wstunnel
install -Dm644 container-wstunnel-server.service ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now container-wstunnel-server.service
```

`--name wstunnel` 保持不变：`podman logs -f wstunnel`、`podmanv6` 上的网络别名都依赖它。若希望这个文件今后能被 `podman generate systemd --name wstunnel-server` 原样再生成，把 `--name` 一并改掉即可，此时上面的清理对象是老容器名 `wstunnel`。

### 3.6 裸机二进制备选（不使用容器时）

把 `ExecStart` 换成 `/usr/local/bin/wstunnel server --tls-certificate … --tls-private-key … --restrict-config … wss://0.0.0.0:55443`，并保留本目录早期版本的加固集：`LimitNOFILE=65535`、`RestartSec=5`、`StartLimitIntervalSec=0`、`NoNewPrivileges`、`ProtectSystem=strict`、`ProtectHome`、`PrivateTmp`、`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`。要点：

- `ProtectSystem=strict` 只禁**写**不禁**读**，证书与配置无需 `ReadWritePaths`；一旦写了 `ReadWritePaths=/some/dir` 而该目录不存在，服务会**直接启动失败**（用 `ReadWritePaths=!/some/dir` 前缀 `!` 表示可缺省）。
- 55443 是非特权端口，可 `User=wstunnel` 降权，但 `privkey.pem` 需改成该用户可读（640 + 属组）。
- 想更早地挡掉错误前缀，可加 `-r cdn-socket-stream`（与 restrictions 里的 `!PathPrefix` 叠加，双保险）。
- 只想按 `host:port` 粗粒度限制时，v11 也支持 `--restrict-to "gw.pyproxy.com:2222"`（可重复）；本方案统一走 `--restrict-config`。

### 3.7 restrictions.yaml 判定语义（已按 v11.1.0 源码核对）

- **白名单机制**：未命中任何规则 → **HTTP 400 Bad Request**（日志 `Rejecting connection with not allowed destination`）。旧文档写的 403 不准确。
- `match` 内是**逻辑与**：路径前缀、Authorization 头必须同时命中；`match` 不允许为空列表。
- `allow` 内是**逻辑或**：命中任一 `!Tunnel` 即放行；多条 restriction 之间按文件顺序取第一条命中的（所以每条的 `name` 建议写清用途，放行日志会打印它）。
- `port`、`protocol` **留空或不写 = 该维度完全不限制**（不是"禁止"）；`port` 支持范围 `"8080..8089"`，源码按字符串解析，建议统一加引号。
- **`host` 与 `cidr` 不会同时生效**：请求目标是域名时只看 `host` 正则；目标是字面 IP 时只看 `cidr`。⇒ 域名目标即使解析到 `127.0.0.1` 也能放行（残余风险见 §5.1）。
- 文件**保存即热加载**（bind mount 场景同样有效），调整端口/密码不需要重启服务或重建容器。
- **`!PathPrefix` 比对的不是完整 URL，而是升级 URI 的首段**（已按源码核对，下同）：
  - 客户端发起升级时 URI 固定拼成 `/{前缀}/events`（`src/tunnel/transport/websocket.rs:267`；http2 `transport/http2.rs:163`、WebTransport `transport/webtransport/client.rs:33` 同一格式）。本方案线上即 `GET /cdn-socket-stream/events`。
  - 服务端 `extract_path_prefix()`（`src/tunnel/server/utils.rs:71-82`）剥掉首斜杠后取**第一个 `/` 之前**的那一段作为待匹配串，并要求剩余部分以 `events` 结尾：`/cdn-socket-stream/events`、`/cdn-socket-stream/a/events`、`/cdn-socket-stream/a/b/events` 都提取到 `cdn-socket-stream`（上游单测 `utils.rs:606-631` 已覆盖）；`/cdn-socket-stream`、`/cdn-socket-stream/events/`、`/cdn-socket-streamevents` 一律 `BadUpgradeRequest` → **400**。
  - ⇒ 正则对象**不含 `/events`**，所以 `restrictions.yaml` 里的 `^cdn-socket-stream$` 全锚写法是正确且必要的；写成 `^cdn-socket-stream/events$` 永不命中。中间那段 `a/b` 可被客户端自由填充（CDN/反代路径改写时注意别把它吃掉）。
  - 匹配点在 `utils.rs:119`（`MatchConfig::PathPrefix(path) => path.is_match(path_prefix)`），正则用 Rust `regex` crate，默认非锚定搜索，靠 `^…$` 收紧。
- 服务端 `-r` / `--restrict-http-upgrade-path-prefix` 比对的是**剥离后的同一个首段**，且是**精确字符串相等**而非正则（`src/tunnel/server/server.rs:115`、`120-127`），命中失败同样回 400，日志 `Client requested upgrade path '<x>' does not match upgrade path restriction …`。它比 restrictions 更早短路，可当作第二道暗号校验。
- 客户端如改用 mTLS（`--tls-certificate`）且**没给** `-P`/`-e`，前缀会被自动改成客户端证书的 CN（`src/lib.rs:72-81`），此时 CN 必须等于 `cdn-socket-stream`，否则 restrictions 不命中。

## 4. 客户端部署（Podman 容器）

`container-wstunnel-client.service` 与服务端单元成对，同为 rootless 用户单元，**并且用的是同一个镜像** `ghcr.io/erebe/wstunnel`：两个角色只是 `podman run` 结尾的子命令不同（`server …` / `client …`）。镜像 `ENTRYPOINT` 是 `dumb-init`，所以命令里写在最前面的 `/home/app/wstunnel` 覆盖的是 `CMD` 而不是入口，两个单元都按这个写法。

| 同一镜像的两个角色 | 服务端 `container-wstunnel-server.service` | 客户端 `container-wstunnel-client.service` |
|---|---|---|
| 子命令 | `/home/app/wstunnel server …` | `/home/app/wstunnel client …` |
| 网络 | `--network podmanv6` + `-p 55443:55443` | `--network host`（6 条 `-L` 的监听直接落宿主机） |
| `/etc/wstunnel` | `fullchain.pem`、`privkey.pem`、`restrictions.yaml` | 用不到（凭据在 unit 里）；**例外**：服务端是自签/私有 CA 时要只读挂一个 `ca.pem`，见 §4.3 第 5 条 |
| 卷 | `-v /etc/wstunnel:/etc/wstunnel:ro,z` | 无挂载 ⇒ 不涉及 `,z` 标签 |
| `--user` | `0:0`（镜像默认 `app`/1000 读不到 600 私钥） | 沿用镜像默认 `app`(1000)，因为没有文件要读 |
| 暗号1 | 由 `restrictions.yaml` 的 `!PathPrefix` 判定（只校验，不代客户端决定前缀） | 命令行 `-P cdn-socket-stream`（§4.3 第 1 条） |
| TLS 信任 | 只需要能读到证书 | 只信**镜像内系统信任库**（`ca_reloader` 取 `rustls-native_certs`），上游无客户端自定义 CA 参数 ⇒ 私有 CA 必须挂进 `/etc/ssl/certs`（§4.3 第 5 条、§7.10 #47） |
| 镜像引用 | `ghcr.io/erebe/wstunnel:latest` | 同左，**两处必须同步**，换 tag 一起改 |

> 客户端单元初稿漏写了镜像名（`-v …:ro,z` 后直接跟 `/home/app/wstunnel client`），podman 会把 `/home/app/wstunnel` 当镜像解析并报 `no such image`；已修，见 §7.6 #28。

### 4.1 凭据放哪里：直接写进 unit（本方案）

单元里一行搞定，客户端机器不需要 `/etc/wstunnel` 目录：

```ini
--http-upgrade-credentials 'wstunnel:Wstunnel-2026' \
```

安装时给 unit 上 600（默认 `install -Dm644` 会把密码暴露给同机任何本地用户）：

```bash
install -Dm600 container-wstunnel-client.service ~/.config/systemd/user/container-wstunnel-client.service
```

两种放法的取舍（**上游没有 http-upgrade 凭据的环境变量**，v11.1.0 只有 `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX`、`WSTUNNEL_HTTP_PROXY_LOGIN/_PASSWORD` 等，所以凭据只能走命令行，无法用 `-e` 挪出 argv——暗号1 有 env 入口，本方案同样选了命令行，见 §4.3 与 §7.9 #43）：

| 维度 | 写进 unit（本方案） | 落盘 `auth.txt` + `--http-headers-file` |
|---|---|---|
| 部署复杂度 | 最低：只拷一个 unit 文件 | 要建目录、写文件、管属主与 SELinux 标签（§3.3 那四条全用得上） |
| 需要 `--user 0:0` / `,z` | 不需要 | 需要（600 文件 + rootless uid 映射） |
| 同机其他本地用户能否看到密码 | **能**：`ps -ef`、`/proc/<容器主进程>/cmdline`、`systemctl --user show -p ExecStart`、`podman inspect` 都是明文（600 的 unit 文件只挡直接读文件） | 不能（`auth.txt` 600 且不在 argv 里） |
| 换密码 | `daemon-reload` + `restart`，全隧道瞬断一次 | 改文件即可，**每请求重读**，不重启 |
| 备份/审计 | 一个文件即全部状态 | 状态分散在 unit 与 `/etc/wstunnel` 两处 |

要换回文件方案的完整写法（把 `--http-upgrade-credentials` 那行替掉，并补挂载与 `--user`）：

```bash
sudo mkdir -p /etc/wstunnel && sudo chown "$(id -u)":"$(id -g)" /etc/wstunnel
sudo install -m600 -o "$(id -u)" -g "$(id -g)" /dev/null /etc/wstunnel/auth.txt
printf 'Authorization: Basic d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==\n' | sudo tee /etc/wstunnel/auth.txt
```

```diff
+        --user 0:0 \
+        -v /etc/wstunnel:/etc/wstunnel:ro,z \
-        --http-upgrade-credentials 'wstunnel:Wstunnel-2026' \
+        --http-headers-file /etc/wstunnel/auth.txt \
```

### 4.2 部署命令

```bash
podman pull ghcr.io/erebe/wstunnel:latest   # 与服务端单元同一镜像引用（§3.4 建议两处一起固定 :v11.1.0）；单元带 --replace，首启也需镜像可用
install -Dm600 container-wstunnel-client.service ~/.config/systemd/user/container-wstunnel-client.service   # 600：暗号2 写在 unit 里（§4.1）
systemd-analyze --user verify ~/.config/systemd/user/container-wstunnel-client.service
systemctl --user daemon-reload
systemctl --user enable --now container-wstunnel-client.service
loginctl enable-linger "$USER"
podman logs --tail 50 wstunnel-client
ss -lntp | grep -E '2223|10000|10001|8101|5002|55689'   # 6 个本地端口已在宿主机监听
loginctl show-user "$USER" -p Linger                    # yes 才能保证重启后自启（§7.10 实测：默认 no）
# ⚠ 到这一步日志里只有 6 行 "Starting TCP server listening cnx on …"，**没有**"已连上服务端"的成功行：
#   客户端是按需建连，没有流量就不发起握手（§7.10 #48）。所以必须主动打一次流量再收工，例如：
nc -z 127.0.0.1 2223 && curl -sv https://tunnel.example.com:55443/cdn-socket-stream/events 2>&1 | tail -5
#   第二条用来确认 TLS 层：若服务端日志出现 received fatal alert: UnknownCA，按 §4.3 第 5 条配方 A 挂 CA
```

注意：**本机 10000 端口**会被占用（映射到 `43.134.70.211:9999`），部署前先确认无冲突；`--network host` 下这个监听直接出现在宿主机命名空间，`podman ps --port` 是看不到端口映射的。

### 4.3 容器化后的 5 个关键差异（务必逐条确认）

| # | 差异 | 不处理的后果 | 本单元做法 |
|---|---|---|---|
| 1 | `[Service]` 段的 `Environment=` **不会进入容器**，只有 `podman run -e` / `--env-file` / Quadlet `Environment=` 进得去 | 暗号1 若写成 unit 的 `Environment=`：前缀静默退回默认 `v1` → 服务端 restrictions 全拒，表现为"客户端在跑但所有隧道 400" | **本方案直接绕开这个坑**：暗号1 用命令行 `-P cdn-socket-stream`，完全不依赖环境变量。要用 env 形态就必须写 `-e`，且**不可与 `-P` 并存**（`-P` 静默覆盖 env） |
| 2 | `-L` 的 `0.0.0.0` 监听发生在容器 netns 内 | bridge 网络下端口只在容器里，宿主机/局域网都连不上 | `--network host`（6 个 `-L` 原样生效，省掉 6 行 `-p`）；用 bridge 则须逐条 `-p PORT:PORT`，且只支持 TCP |
| 3 | 镜像 `USER app`(1000) 经 rootless uid 映射后，读不到属主为你的 600 文件 | 挂进来的文件读不到 → crash loop（`podman logs` 见 Permission denied） | **本方案客户端不挂文件，暂时无关**；改回文件凭据或上 mTLS 时补 `--user 0:0`（服务端已带，§3.3） |
| 4 | SELinux 对 bind mount 需要安全标签 | 文件权限正常仍 `Permission denied` | 同上，只在有 `-v` 时才需要，届时卷尾加 `,z`（服务端已带） |
| 5 | **容器的 TLS 根只有镜像内的系统信任库**：`--tls-verify-certificate` 下，自签 / 私有 CA / 只有中间证书没带根的场景一律被拒，且**没有任何客户端参数能指定自定义 CA**（`--tls-client-ca-certs` 是服务端用的，`config.rs:379`；根 store 见 `protocols/tls/server.rs:116` + `tunnel/ca_reloader.rs:59-72`） | 真机实测症状最阴：服务端 `error while accepting TLS connection received fatal alert: UnknownCA`，客户端只在 INFO 里反复 `Doing TLS handshake` 按 0.6/0.8/1.6/3.2/6.4s 退避，`podman ps` 一直 healthy、`systemctl is-active` 一直 active（§7.10 #47、#48） | 把 CA 塞进系统信任目录（下面配方 A），或换 Public 签发的证书 / 不校验（配方 B/C） |

**私有 CA 的三种配法（实测只有 A 无副作用）**：

```bash
# 配方 A（推荐，真机验证有效）：单文件挂进系统信任目录
#   rustls-native-certs(0.8.5) 会把 /etc/ssl/certs 下的 *.pem/*.crt 一起收进根 store，
#   所以丢一个文件进去就行，不必重建镜像、也不必 --user（文件 644 即可，容器内 uid 1000 只读）
        -v /etc/wstunnel/ca.pem:/etc/ssl/certs/wstunnel-ca.pem:ro \
#   SELinux enforcing 下卷尾补 ,z（本项在 Debian 无 SELinux 环境实测，RedHat 系要自己验一遍）

# 配方 B（整体替换）：-e SSL_CERT_FILE=/etc/wstunnel/ca.pem —— 根 store 会变成"只信这一个 CA"，
#   日后若目标服务换成公网证书会静默不认；换 CA 文件后老进程最多 1 小时才重载（§7.10 #54），直接 restart 更快

# 配方 C（放弃校验）：去掉 --tls-verify-certificate —— 变成 NullVerifier，
#   暗号2 在 URL 明文串（TLS 内）里仍会送，但证书 pin 面消失；只有目标 IP 直连、无域名时才考虑
```

> 换 CA 之后：`systemctl --user restart container-wstunnel-client`。根 store 是**每小时整体重载**（`wstunnel-cli/src/main.rs:108` → `tunnel/ca_reloader.rs:22-38`，interval 缺省 3600s），别等它自己刷（§7.10 #54）。

环境变量与命令行参数在容器里**全部**要经 `-e` / `--env-file` / `ExecStart` 命令行传入（暗号2 也属于这一类，它没有对应环境变量，只能进 `ExecStart`，见 §4.1），见 §4.4 对照表；集中管理可用 `-v /etc/wstunnel/client.env:/etc/wstunnel/client.env:ro,z` 配 `--env-file /etc/wstunnel/client.env`。

### 4.4 环境变量对照表（客户端）

| 参数 | 环境变量 | 备注 |
|---|---|---|
| `-P` / `--http-upgrade-path-prefix` 路径前缀 | `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX` | **两个入口等价，只写一个**：本方案用命令行 `-P cdn-socket-stream`（少一条注入链路，理由见 §4.3 第 1 条 / §7.9 #43）。同时给时 `-P` 优先（clap 4.6 的 `env=` 仅在命令行缺省时取值，绑定见 `src/config.rs:154-161`）。默认 `v1`；若改用 env 形态，容器里必须 `podman run -e` 传（另见 §3.7 首段剥离规则） |
| `-p` http 代理 | `HTTP_PROXY` | 客户端在代理后面出网时用 |
| 代理账号/密码 | `WSTUNNEL_HTTP_PROXY_LOGIN` / `WSTUNNEL_HTTP_PROXY_PASSWORD` | 会覆盖 `-p` 里的账号 |
| `--log-lvl` 日志级别 | `RUST_LOG` | TRACE/DEBUG/INFO/WARN/ERROR/OFF；镜像内置 `INFO`，调试用 `-e RUST_LOG=DEBUG` |
| （服务端）`-r` 限制前缀 | `WSTUNNEL_RESTRICT_HTTP_UPGRADE_PATH_PREFIX` | 服务端侧，与 restrictions 叠加 |
| `--dns-resolver-prefer-ipv4` | `WSTUNNEL_DNS_PREFER_IPV4` | IPv6 异常时减少延迟 |
| `--no-color` | `NO_COLOR=1` | 日志去色 |
| `--nb-worker-threads` | `TOKIO_WORKER_THREADS` | 线程数 |
| 暗号2 `--http-upgrade-credentials`（`-H/--http-headers`、`--http-headers-file` 同理） | ❌ 无 | 只能进命令行 ⇒ 写进 unit 就会被 `ps` 看到，权衡与回退见 §4.1 |
| `-L` / `-R` / `--tls-verify-certificate` | ❌ 无 | 只能命令行 |

### 4.5 本地监听地址（开放到局域网/所有网卡）

`-L` 缺省只绑 **127.0.0.1**（仅本机可达）。要监听所有网卡就在 URL 里显式写 BIND 前缀（语法 `{tcp,udp}://[BIND:]PORT:HOST:PORT`）：

```
-L tcp://0.0.0.0:2223:gw.pyproxy.com:2222         # IPv4 全部网卡
-L tcp://[::]:2223:gw.pyproxy.com:2222            # IPv6 全部网卡
-L tcp://192.168.1.10:2223:gw.pyproxy.com:2222    # 只绑指定网卡（推荐）
```

**安全提醒**：TCP/UDP 隧道这些本地端口**本身没有任何鉴权**。本方案用 `--network host` + `0.0.0.0`，等于把 6 个无鉴权端口直接摊到宿主机所有网卡上，务必用防火墙兜住：

- 按来源网段白名单：`sudo firewall-cmd --add-rich-rule="rule family=ipv4 source address=192.168.0.0/24 port port=2223 protocol=tcp accept"`（注意先 remove 掉宽泛放行规则）；
- 或把 `-L` 的 BIND 改成具体内网网卡 IP；
- 需要动态端口时改用带账号密码的入口：`socks5://0.0.0.0:1212?login=xx&password=xx` 或 `http://0.0.0.0:1212?login=xx&password=xx`。

### 4.6 可选：改用 Quadlet（`.container` 文件）

`podman generate systemd` 属旧路径，podman ≥ 4.4 推荐 Quadlet（单元由 systemd generator 生成，参数更贴近 `podman run` 且升级更稳）。等价写法：

```ini
# ~/.config/containers/systemd/wstunnel-client.container
[Unit]
Description=wstunnel client (6 tunnels)
Wants=network-online.target
After=network-online.target

[Container]
# .container 文件同样要 600（Exec 行里有明文密码）；Image tag 与两个 unit 保持一致
Image=ghcr.io/erebe/wstunnel:latest
ContainerName=wstunnel-client
Network=host
AutoUpdate=registry
Label=io.containers.autoupdate=registry
# 不挂宿主机文件（凭据在 Exec 行里），故 Volume=/User= 两行都不需要
# 例外：自签/私有 CA 时要补 Volume=/etc/wstunnel/ca.pem:/etc/ssl/certs/wstunnel-ca.pem:ro（§4.3 第 5 条）
# 前缀同样走 -P，与两个 unit 一致。Quadlet 的 [Container] Environment= 确实会进容器，
# 但与 -P 并存时 -P 赢，别一半 env 一半 -P
Exec=/home/app/wstunnel client -P cdn-socket-stream --tls-verify-certificate --http-upgrade-credentials 'wstunnel:Wstunnel-2026' \
  -L tcp://0.0.0.0:2223:gw.pyproxy.com:2222 \
  -L tcp://0.0.0.0:10001:hk.rp.linkup.onl:10000 \
  -L tcp://0.0.0.0:10000:43.134.70.211:9999 \
  -L tcp://0.0.0.0:8101:proxy.momoproxy.com:8100 \
  -L tcp://0.0.0.0:5002:us.rapidproxy.io:5001 \
  -L tcp://0.0.0.0:55689:45.149.172.51:55688 \
  wss://tunnel.example.com:55443

[Service]
Restart=always
RestartSec=5
StartLimitIntervalSec=0
```

```bash
systemctl --user daemon-reload && systemctl --user start wstunnel-client.container
```

服务端同理用 `~/.config/containers/systemd/wstunnel-server.container`；注意 Quadlet 生成的单元名取文件基名，叫 `wstunnel-server.service` 而**不是** `container-wstunnel-server.service`，与上面的命名惯例不同，二选一即可（别同时存在）。键名与作用域（`User=`→`--user`、`Network=host`→`--network host`）按 `man podman-systemd.unit`；Quadlet 的 `[Install]`/自动 enable 行为随 podman 版本有差异，本仓库未在目标机实测（见 §7）。生成出来的单元同样把密码放进 argv，可见范围与 §4.1 表里那一行完全相同。

### 4.7 裸机二进制备选（不使用容器时）

用回早期的 `wstunnel-client.service`：`ExecStart=/usr/local/bin/wstunnel client -P cdn-socket-stream …`，与容器形态逐字一致。裸机下 `Environment=WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX=cdn-socket-stream` 同样有效（与 §4.3 第 1 条正好相反——容器里 `[Service] Environment=` 不进容器），但为了让两种形态写法统一，仍推荐 `-P`。加固集与注意事项同 §3.6：`LimitNOFILE=65535`、`RestartSec=5`、`StartLimitIntervalSec=0`、`ProtectSystem=strict` 等；`--http-upgrade-credentials` 写在命令行时，`chmod 600` 的 unit 只挡读文件、挡不住 `ps`（容器形态同理，见 §4.1）。

## 5. 验收测试

> 下面 ②③④⑥ 四条负例必须用**真的 client 进程**发起：裸 curl 到不了 restrictions 判定那一步（JWT 解析在前），只会一律返回 400，看不出白名单有没有生效（§7.10 #49）。没有裸二进制就用 ⑦ 的容器形态。

```bash
# ① 正确姿势 → 应成功
wstunnel client --tls-verify-certificate \
  --http-upgrade-credentials 'wstunnel:Wstunnel-2026' -P cdn-socket-stream \
  -L tcp://0.0.0.0:2223:gw.pyproxy.com:2222 wss://<域名>:55443

# ② 不带任何密钥（模拟恶意扫描）→ 应被拒
wstunnel client -L tcp://3333:127.0.0.1:22 wss://<域名>:55443

# ③ 有密钥但目标端口不在白名单 → 应被拒
wstunnel client --http-upgrade-credentials 'wstunnel:Wstunnel-2026' -P cdn-socket-stream \
  -L tcp://3333:127.0.0.1:3306 wss://<域名>:55443

# ④ 目标端口在白名单但主机不对（收紧白名单后新增的用例）→ 应被拒
wstunnel client --tls-verify-certificate \
  --http-upgrade-credentials 'wstunnel:Wstunnel-2026' -P cdn-socket-stream \
  -L tcp://3333:evil.example.com:2222 wss://<域名>:55443

# ⑤ 只看端口/TLS 是否通（curl 必然拿 400：它既没有 JWT 也没有正确的升级路径，
#    两条 curl 都返回 400，区别只在服务端日志——前者是 bad upgrade request（缺 /events 后缀），
#    后者才是走到鉴权阶段后因无 Sec-WebSocket-Protocol 里的 JWT 被拒，见 §3.7）
curl -sk -o /dev/null -w '%{http_code}\n' https://<域名>:55443/cdn-socket-stream
curl -sk -o /dev/null -w '%{http_code}\n' https://<域名>:55443/cdn-socket-stream/events

# ⑥ 前缀暗号是否真的生效 → 应被拒
wstunnel client --tls-verify-certificate \
  --http-upgrade-credentials 'wstunnel:Wstunnel-2026' -P wrong-prefix \
  -L tcp://3333:gw.pyproxy.com:2222 wss://<域名>:55443

# ⑦ 没有裸二进制时，直接用容器跑上面的手工用例（与单元同形态：暗号1 用 -P）
#    要试 env 形态就把 -P 换成 -e WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX=wrong-prefix（-P 与 -e 并存时 -P 赢）；
#    用 auth.txt 的话要补 -v /etc/wstunnel:/etc/wstunnel:ro,z + --user 0:0
podman run --rm -it --network host \
  ghcr.io/erebe/wstunnel:latest /home/app/wstunnel client -P wrong-prefix --tls-verify-certificate \
  --http-upgrade-credentials 'wstunnel:Wstunnel-2026' \
  -L tcp://3333:gw.pyproxy.com:2222 wss://<域名>:55443
```

①通、②③④⑥拒 = TLS + 双暗号 + `host:port` 白名单全部生效。判定顺序是「先剥离并校验升级路径 → 再解 JWT → 最后查 restrictions」（`server.rs:115` 提取路径 → `120-127` `-r` 精确比对 → `129` 解 JWT → `141-146` 查 restrictions），所以裸 `curl`（无 `Sec-WebSocket-Protocol`）拿不到"白名单已放行"的结论，白名单必须用真客户端测。

### 5.1 残余风险：域名解析不受 cidr 约束

`host` 命中的域名目标，其解析结果不受 `cidr` 限制（源码里域名分支只看 `host`）。若某白名单域名的 DNS 可控或发生 rebinding，隧道可能被指到 `127.0.0.1` / `169.254.169.254` 之类的内网地址。缓解：对可固定的目标改用 **IP + `cidr: x.x.x.x/32`** 写法，或在服务端 `/etc/hosts`、resolver 层锁定解析结果。

### 5.2 证书续期：bind mount 的是副本，不是 live 符号链接

`/etc/wstunnel` 里放的是**拷贝**，Let's Encrypt 续期只会更新 `/etc/letsencrypt/{live,archive}`，不会自动同步过来。二选一：

```bash
# 方案 1（推荐）：续期时重新拷贝，wstunnel 侦测到文件变化后热加载
sudo tee /etc/letsencrypt/renewal-hooks/deploy/wstunnel-copy.sh >/dev/null <<'EOF'
#!/bin/sh
set -eu
dom=tunnel.example.com
ow=$(stat -c '%U' /etc/wstunnel); gr=$(stat -c '%G' /etc/wstunnel)   # hook 以 root 跑，属主要跟随目录＝部署用户
install -m644 -o "$ow" -g "$gr" "/etc/letsencrypt/live/$dom/fullchain.pem" /etc/wstunnel/fullchain.pem
install -m600 -o "$ow" -g "$gr" "/etc/letsencrypt/live/$dom/privkey.pem" /etc/wstunnel/privkey.pem
chcon -t container_file_t /etc/wstunnel/*.pem 2>/dev/null || true   # SELinux：root 新建的文件会拿回 etc_t，见 §7.6 #31
EOF
sudo chmod 755 /etc/letsencrypt/renewal-hooks/deploy/wstunnel-copy.sh

# 方案 2：整树只读挂载，unit 里直接指向 live/（不能只挂 live/，
# 因为 live 下的符号链接是 ../../archive/<域名>/privkeyN.pem 的相对路径，缺 archive 会断）
#   -v /etc/letsencrypt:/etc/letsencrypt:ro,Z
#   --tls-certificate /etc/letsencrypt/live/tunnel.example.com/fullchain.pem
#   --tls-private-key /etc/letsencrypt/live/tunnel.example.com/privkey.pem
```

## 6. 日常运维

### 6.1 轮换密码

```bash
echo -n 'wstunnel:新密码' | base64                      # ① 生成新 base64
sed -i 's/d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==/<新串>/' \
  /etc/wstunnel/restrictions.yaml                       # ② 服务端：热加载，本方案仅 1 处引用
# ③ 客户端：改 unit 里的 --http-upgrade-credentials，然后
systemctl --user daemon-reload && systemctl --user restart container-wstunnel-client
#    （这是把凭据写进 unit 的代价：每次换密码全隧道瞬断一次。
#     用 --http-headers-file /etc/wstunnel/auth.txt 才免重启——文件每请求重读，见 §4.1）
```

注意：客户端有**两处**不热，且都在同一个 unit 文件里——命令行 `-P` 的前缀（进程启动时读入，见 §6.2）与 `--http-upgrade-credentials` 的暗号2（要 `daemon-reload` + `restart`）。改任一处的操作完全相同，不必区分形态。服务端侧的 `restrictions.yaml` 始终热加载。

### 6.2 改路径前缀暗号

必须三处一致，漏一处就是「客户端在跑但所有隧道被拒」：

```bash
grep -rn cdn-socket-stream restrictions.yaml container-wstunnel-client.service README.md
# 服务端：restrictions.yaml 的 !PathPrefix —— 保存即热加载
# 客户端：container-wstunnel-client.service 里 -P 的值 —— 必须重启（没有 -e，也别去翻 [Service] Environment=）
systemctl --user daemon-reload && systemctl --user restart container-wstunnel-client
# 如启用了 -r / --restrict-http-upgrade-path-prefix，也要一起改
```

每条新连接都会重走 upgrade + 鉴权，所以前后端切换之间会有秒级失败窗口，尽量一次性下发。

### 6.3 增删隧道端口

`restrictions.yaml` 加/删一条 `!Tunnel`（记得同时定好它的 `host` 或 `cidr`）→ 保存即生效；再更新客户端单元的 `-L` 列表并 `systemctl --user daemon-reload && systemctl --user restart container-wstunnel-client`。用 `--network host` 时新端口无需 `-p` 映射，但宿主机防火墙要一起放行。

### 6.4 自检命令

```bash
# 服务端
systemd-analyze --user verify ~/.config/systemd/user/container-wstunnel-server.service
# ⚠ --filter name= 是子串匹配：name=wstunnel 会连带命中 wstunnel-client，判"服务端容器是否存在"必须锚定
podman ps -a --filter name='^wstunnel$' --format '{{.Names}} {{.Status}} {{.Image}}'
podman logs --since 10m wstunnel | grep -E 'matched restriction|Rejecting|listening'
systemctl --user show container-wstunnel-server.service -p NRestarts -p Result -p ExecMainStatus -p ExecStart
# 客户端
systemd-analyze --user verify ~/.config/systemd/user/container-wstunnel-client.service
podman logs --since 10m wstunnel-client | grep -Ei 'Doing TLS handshake|error|panic'   # 正常态日志很安静，见 §7.10 #48
ss -lntp | grep -E '2223|10000|10001|8101|5002|55689'   # host 网络下监听在宿主机，属主进程显示 conmon 属正常
# 主动打一次流量（客户端按需建连，不打流量 = 什么都没验证，§7.10 #48）
nc -z 127.0.0.1 2223 && echo OK
systemctl --user show container-wstunnel-client.service -p NRestarts -p Result
# 两端共用
podman auto-update --dry-run
python3 -c "import yaml;yaml.safe_load(open('/etc/wstunnel/restrictions.yaml'))"   # 改完 YAML 先自检
loginctl show-user "$USER" -p Linger                                                # 重启后自启的前提，§3.2
journalctl --user -u container-wstunnel-{server,client}.service --since -1h -o cat | grep -Ei 'Stopping|Stopped|Started|Scheduled restart'
```

### 6.5 常见问题速查

| 现象 | 原因 | 处理 |
|---|---|---|
| 容器反复重建、日志显示读取失败 | 证书/私钥/白名单/凭据文件缺失、写了一半，或**容器读不到**（§3.3、§4.3） | 按属主/SELinux 标签处理后 `podman logs -f` 观察 |
| 客户端在跑但所有隧道都 400 | 前缀不匹配：`-P` 被删/拼错，或误用 unit 的 `Environment=`（不进容器）、又或 `-e` 被同处的 `-P` 静默覆盖，最终退回默认 `v1` | `podman inspect wstunnel-client --format '{{json .Config.Cmd}}'` 看实际 argv；§4.3 第 1 条 |
| 宿主机/局域网连不上客户端本地端口 | bridge 网络里端口只在容器内 | `--network host`，或补 `-p PORT:PORT`（仅 TCP） |
| `podman ps --port` 看不到端口 | `--network host` 无端口映射，属正常 | 用 `ss -lntp` 看宿主机监听 |
| 换密码后服务端一直 400 | 凭据写在 unit 里，只改文件/只 reload 不生效 | `systemctl --user daemon-reload && systemctl --user restart container-wstunnel-client`（§4.1/§6.1） |
| 同机用户从 `ps` 看到明文密码 | `--http-upgrade-credentials` 在容器主进程 argv 里，`chmod 600` 挡不住 | 改文件方案（`--http-headers-file` + `-v :ro,z` + `--user 0:0`），§4.1 有 diff |
| 改了前缀仍不生效 | 前缀在进程启动时读入，改 `-e` 需重建容器 | §6.2 |
| `podman logs` 空、unit 进入 failed | 网络名不存在、端口被占、镜像未拉取、触发 systemd 限流 | `podman network exists …`；`ss -lntp \| grep 55443`；`podman pull …:v11.1.0`；`StartLimitIntervalSec=0` |
| 服务器重启后服务没起来 | rootless 用户单元未开机启动 | `loginctl enable-linger "$USER"` |
| 客户端证书报错 | 忘加 `--tls-verify-certificate`，或证书链不完整 | 用 fullchain（含中间证书）并显式开启校验；镜像已内置 `ca-certificates` |
| **服务端日志 `received fatal alert: UnknownCA`**，客户端一直 `Doing TLS handshake` 后退避 | 客户端容器只信镜像内系统信任库，服务端是自签/私有 CA（真机实测：容器 healthy、unit active，一条隧道都不通） | §4.3 第 5 条配方 A：`-v /etc/wstunnel/ca.pem:/etc/ssl/certs/wstunnel-ca.pem:ro`（§7.10 #47） |
| 客户端 `active` + 容器 healthy，但没人能用 | 按需建连 ⇒ 启动日志只有 6 行 `listening cnx`，看不到"是否连上服务端" | 按 §6.4 主动打一次流量；服务端应出现 `Tunnel accepted due to matched restriction: <规则名>`（§7.10 #48） |
| `systemctl --user stop` 后 unit 显示 `failed`（`Result=exit-code`、`ExecMainStatus=143`） | 镜像 `ENTRYPOINT=dumb-init` 收到 SIGTERM 以 143 退出，退出码原样传播；容器与 cidfile 其实都清理干净了 | 无害；想显示 `inactive` 就加 `SuccessExitStatus=143`（§3.5、§7.10 #51） |
| 换/加 CA 后客户端迟迟不认 | 系统根 store 每小时整体重载（`main.rs:108` → `ca_reloader.rs:22-38`） | `systemctl --user restart container-wstunnel-client`，别等自刷（§7.10 #54） |
| 域名隧道不通、IP 隧道正常 | 容器/宿主机解析不了目标域名 | wstunnel 追加 `--dns-resolver dns://223.5.5.5`（DoT 用 `dns+tls://8.8.8.8?sni=dns.google`） |
| 客户端起不来，address already in use | 宿主机本地端口冲突（重点查 10000） | 换本地端口或停占用服务 |
| 隧道频繁断开重连 | 中间设备回收空闲连接 | 调小 `--websocket-ping-frequency`（默认 30s，可设 15s） |
| 续期后仍是旧证书 | `/etc/wstunnel` 是副本，deploy-hook 未配置 | §5.2 |
| 扫描器不停连 | 只拦到 HTTP 层，属正常 | 55443 非标端口 + 双暗号 + host 白名单已足够；要更强可上 mTLS |
| 裸机单元启动即失败并提示挂载错误 | `ReadWritePaths` 指向不存在的目录 | 建目录或用 `ReadWritePaths=!/path`（仅 §3.6/§4.7 场景） |
| 上了 `wts://` 后 10s 超时 | QUIC 需要 UDP 端到端可达 | `--enable-webtransport` + `-p 55443:55443/udp` + 放行 UDP；`--http-proxy`、`--tls-sni-disable`、`--tls-ech-enable` 与 WebTransport 不兼容 |

### 6.6 安全升级路线

| 级别 | 手段 | 配置 |
|---|---|---|
| 当前 | TLS + 路径前缀 + Basic + `host:port` 白名单 | 本文档方案 |
| 更高 | mTLS 双向证书 | 服务端 `--tls-client-ca-certs /etc/wstunnel/ca.pem`，客户端 `--tls-certificate/--tls-private-key`（无证书者在握手期即被拒；注意 mTLS 下升级前缀默认取证书 CN，需与 `-P`/`!PathPrefix` 对齐） |
| 隔离 | 容器侧继续收紧 | 服务端卷 `:ro,Z`、镜像 tag 固定、必要时加 `--security-opt=no-new-privileges`、`--cap-drop=ALL` |

## 7. 审计与同步记录

### 7.1 首轮审计（2026-11-28，配置与文档）

已核实的基准：上游 `erebe/wstunnel` 仓库 README、`restrictions.yaml` 示例、`src/restrictions/{types,mod}.rs`、`src/tunnel/server/{utils,server}.rs`、`src/tunnel/transport/jwt.rs`、`Dockerfile`，以及 Releases API 返回的 `tag_name = v11.1.0`（= 本方案版本基准）。

| # | 级别 | 发现 | 处理 |
|---|---|---|---|
| 1 | 中 | 旧 `restrictions.yaml` 仅锁端口，`host: ^.*$` + `cidr 0/0` ⇒ 拿到双暗号即可把 6 个端口转去任意主机（SSRF 面） | 按映射表拆成 6 条 `!Tunnel`，域名走 `host` 正则、字面 IP 走 `/32` cidr；保留"宽松回退"注释块 |
| 2 | 中 | 文档称默认拒绝返回 403；源码 `bad_request()` 实为 **400** | 已更正（§3.7、§5） |
| 3 | 中 | 未说明 `port`/`protocol` 留空 = 不限制，误删即全放开 | 已在 §3.7 显式写明 |
| 4 | 中 | 未说明域名目标只看 `host`、`cidr` 不参与（rebinding 残余风险） | 已新增 §5.1 |
| 5 | 低 | 文档称客户端 unit `chmod 600` 可防泄密，实际 `ps` 仍能看到密码 | §4.1 已更正（改用凭据落盘） |
| 6 | 低 | `-P` 缺省值 `v1`（旧文档未提），漏配会被 restrictions 拒 | 参数清单 + 速查表补充 |
| 7 | 低 | 裸机 unit 无资源/安全约束，root 裸跑、无 fd 上限、重启限流缺失 | `LimitNOFILE`、`RestartSec=5`、`StartLimitIntervalSec=0`、`ProtectSystem=strict` 等（现存于 §3.6/§4.7） |
| 8 | 低 | `--dns-resolver`、`-r`、`--websocket-ping-frequency` 只在速查表出现，unit 中无入口 | 以注释形式给出 |
| 9 | 信息 | v11 已支持 WebTransport（`wts://`）、`--restrict-to` 简化白名单、`--http-headers-file` 每请求重读 | 文档补记 |
| 10 | 已核对无误 | base64 值、`--tls-verify-certificate` 为无值开关、`--http-headers-file` 优先级、socks5 带 `login/password`、ping 默认 30s、`WSTUNNEL_*` 环境变量名、mTLS 参数名 | 保持原描述 |

### 7.2 同步远端改动（2026-11-28，`d8573e7`：服务端 → Podman）

| # | 级别 | 发现 | 建议 |
|---|---|---|---|
| 11 | **高** | 镜像 `USER app`（uid 1000）而非 root，文档原要求的 `privkey.pem` 600 属主 root ⇒ 容器可能读不到私钥/白名单 | 卷 `:ro,U`、或容器 `--user 0:0`、或按容器映射 uid 调整属组（§3.3） |
| 12 | 中 | `-v /opt/wstunnel:/opt/wstunnel:rw`（当时的路径）：SELinux enforcing 下缺标签会被拒；且 wstunnel 无需写权限 | 改 `:ro` 并按需加 `,z`/`,Z`（§3.3；现已按 `:ro,z` 落地并迁到 `/etc/wstunnel`，见 #30） |
| 13 | 中 | `:latest` + `autoupdate=registry` 让服务端版本脱离 v11.1.0 基准；autoupdate 还需 timer 才生效 | 固定 `:v11.1.0`；`systemctl --user enable --now podman-auto-update.timer`（§3.4） |
| 14 | 中 | `/opt/wstunnel`（现 `/etc/wstunnel`）里的证书是副本，续期不会自动同步 ⇒ "续期无需重启"依赖文件真的被刷新 | deploy-hook 或整树只读挂 `/etc/letsencrypt`（§5.2） |
| 15 | 低 | rootless 用户单元未开 linger 时机器重启后不自启 | `loginctl enable-linger "$USER"`（§3.2） |
| 16 | 低 | 单元未设 `StartLimit*`，走默认 10s/5 次即 failed | 需持续自愈则加 `StartLimitIntervalSec=0`（§3.5） |
| 17 | 低 | `-p 55443:55443` 只映射 TCP，日后 WebTransport 表现为握手 10s 超时 | 需要时补 `-p 55443:55443/udp`（§3.4） |
| 18 | 已核对无误 | `/home/app/wstunnel` 路径、`ENTRYPOINT=dumb-init`（命令行首参不会被覆盖）、`Type=notify` + `--sdnotify=conmon` + `NotifyAccess=all`、`PODMAN_SYSTEMD_UNIT=%n`、`--cgroups=no-conmon`、`wss://[::]` 双栈监听 | 保持不动 |

### 7.3 改动记录：暗号与客户端容器化（2026-11-28）

- 路径前缀暗号 `my-secret-path` → **`cdn-socket-stream`**：`restrictions.yaml` 的 `!PathPrefix`、客户端单元、本文档全部同步，已 `grep -r my-secret-path` 确认除本条记录外无残留。
- **客户端也容器化**：新增 `container-wstunnel-client.service`，删除被取代的裸机 `wstunnel-client.service`（加固要点移入 §4.7）；§4 全章按容器形态重写。
- **单元文件成对命名**：`container-wstunnel.service` → `container-wstunnel-server.service`（用 `git mv`，历史保留），与客户端单元对齐；服务端单元内 `Description=` 同步，全文 11 处引用（§0 清单、§3.1/§3.2/§3.5、§6.4、§8）一并更新，改名对运行时的影响与迁移步骤见 §3.5 与结论 #26–#27。

### 7.4 客户端容器化新增结论

| # | 级别 | 发现 | 处理 |
|---|---|---|---|
| 19 | **高** | `[Service]` 段 `Environment=WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX=…`（旧裸机写法）在 `ExecStart=podman run` 形态下**不会进入容器**，前缀会静默退回默认 `v1`，症状是"客户端健康、所有隧道 400" | 当时改为 `podman run -e`（这条结论本身仍成立：env 形态只有 `-e`/`--env-file`/Quadlet `Environment=` 有效）；现已进一步改成命令行 `-P`，整类消掉该坑，见 §7.9 #43 |
| 20 | **高** | `-L tcp://0.0.0.0:PORT` 在 bridge 网络下只绑容器 netns，宿主机与局域网都访问不到这 6 个端口 | `--network host`（本方案），或 bridge + 6 条 `-p`（仅 TCP）；`podman ps --port` 在 host 模式下看不到端口，改查 `ss -lntp` |
| 21 | 中 | `--network host` + `0.0.0.0` + 隧道端口本身无鉴权 ⇒ 6 个开放代理端口直接摊到宿主机全部网卡 | §4.5 要求防火墙按源网段白名单或改绑具体网卡 IP |
| 22 | 中 | 镜像 `USER app` + rootless uid 映射 ⇒ 600 的 `auth.txt` 读不到；SELinux 还需标签 | `--user 0:0` + 卷 `,z`（§4.3 第 3、4 条）。**该前提现已不成立**：凭据改写入 unit 后客户端不再挂文件，见 §7.7 #35 |
| 23 | 低 | 前缀是启动时读取的进程环境，改 `-e` 必须重建容器；`auth.txt` 与 `restrictions.yaml` 才是热路径 | §6.1、§6.2 标出"哪几处不用重启" |
| 24 | 低 | `--replace` + `--rm` + `Restart=always` 组合下，镜像自动更新会瞬断全部隧道；`--pull` 默认策略为 `missing`，单元内首启需镜像已就绪 | §3.4、§4.2 部署前先 `podman pull` |
| 25 | 信息 | `podman generate systemd` 已被 Quadlet（`.container`）取代为推荐路径 | §4.6 给出等价 Quadlet 写法 |

### 7.5 改动记录：单元成对命名（2026-11-28）

| # | 级别 | 发现 | 处理 |
|---|---|---|---|
| 26 | 中 | `--cidfile=%t/%n.ctr-id` 的 `%n` 取 unit 名 ⇒ 只换文件名会让旧 unit 的 `ExecStop`/`ExecStopPost` 找不到 cidfile；若新旧两个 unit 同时 enabled，`--replace` 会互相抢 `wstunnel` 这个容器名，表现为"服务 active 但容器被反复替换" | 按 §3.5 顺序迁移：先 `disable --now` 旧 unit → 清旧 cidfile → 确认无无主容器 → 再装新 unit |
| 27 | 低 | `container-<容器名>.service` 是 `podman generate systemd --name <容器名>` 的固定产物名；本方案服务端 unit 叫 `…-server.service` 而容器名仍是 `wstunnel`，两者不再机械对应（客户端 `…-client.service` / `--name wstunnel-client` 是对应的） | 可读性与成对命名优先，保持现名；需要生成器可复现时把 `--name` 改成 `wstunnel-server`（§3.5） |

### 7.6 改动记录：配置目录统一到 `/etc/wstunnel` + 同镜像双子命令（2026-11-28）

| # | 级别 | 发现 | 处理 |
|---|---|---|---|
| 28 | **高** | 客户端单元 `ExecStart` 漏写镜像名：`-v …:ro,z` 之后直接跟 `/home/app/wstunnel client`，podman 会把 `/home/app/wstunnel` 当镜像解析（`no such image` / 误拉取），容器起不来 | 补 `ghcr.io/erebe/wstunnel:latest`。`client` 与 `server` 本就是同一镜像的两个子命令，两个单元的镜像引用要逐字一致（§4） |
| 29 | 中 | 服务端配置从 `/opt/wstunnel` 迁到 `/etc/wstunnel`：`/etc` 默认属主 root，rootless 容器读不到属主为别人的 600 私钥；只读 bind mount 虽只需目录可穿越，但 `:z` 重标签与后续覆盖写都要属主权限 | §3.1/§3.2 用 `sudo install -d -o $(id -u) -g $(id -g) /etc/wstunnel` 建目录 + 上传后 `chown -R`；配 `--user 0:0`（容器内 root 即部署者本人，非宿主机 root） |
| 30 | 中 | 服务端单元原 `-v …:rw` 且无 `--user`：容器内 uid 1000 读 600 私钥不稳，容器还能改写配置目录 | 已改 `-v /etc/wstunnel:/etc/wstunnel:ro,z` + `--user 0:0`，与客户端单元写法对齐；`:ro` 不影响证书/白名单热加载（写发生在宿主机侧、同一 inode） |
| 31 | 中 | SELinux：`:z` 把 `/etc/wstunnel` 从 `etc_t` 重标为 `container_file_t`，而 filetrans 规则让**之后新建**的文件（certbot deploy-hook 写入）重新继承 `etc_t` ⇒ 续期后容器可能反而被拒 | `semanage fcontext -a -t container_file_t '/etc/wstunnel(/.*)?' && restorecon -RF /etc/wstunnel`，或像 §5.2 那样在 hook 末尾显式 `chcon`。本仓库无 SELinux 环境，**未实测** |
| 32 | 低 | 两端同机部署时共用一个 `/etc/wstunnel`，客户端只读挂载连带看到服务端私钥 | 改文件级 bind mount 或 `/etc/wstunnel/{server,client}/` 子目录；本方案默认两端异机（§3.1） |
| 33 | 中 | §5 用例 ⑦ 初稿在容器里读 `/etc/wstunnel/auth.txt` 却没挂 `-v`（镜像内没有这个路径），也没有 `--user 0:0`，照抄必然失败 —— 与 §4.3 讲的是同一批坑 | 已补 `-v /etc/wstunnel:/etc/wstunnel:ro,z` 与 `--user 0:0`，镜像引用与两个单元一致 |
| 34 | 信息 | 同镜像双子命令的连带影响：换 tag 要改两处；`podman pull` 与 `io.containers.autoupdate=registry` 只管一个镜像；`--user 0:0`/`,z`/`:ro` 三项处理对两端完全相同，可复用同一段说明 | §4 对照表；§3.4 的固定 tag 建议改为「两个单元一起改」 |

### 7.7 改动记录：暗号2 直接写入 systemd unit（2026-11-28）

| # | 级别 | 发现 | 处理 |
|---|---|---|---|
| 35 | 中 | 客户端改用 `--http-upgrade-credentials` 后不再读宿主机文件 ⇒ `-v /etc/wstunnel:/etc/wstunnel:ro,z` 与 `--user 0:0` 都成冗余，客户端单元去掉挂载后连 SELinux/uid 映射两组坑一起消失 | 客户端单元删掉 `-v`/`--user`，容器按镜像默认 `app`(1000) 运行；`/etc/wstunnel` 变成服务端专用目录（§2、§4 对照表已同步） |
| 36 | **高** | 凭据进 `ExecStart` 即进容器主进程 argv：`ps -ef`、`/proc/<pid>/cmdline`、`systemctl --user show -p ExecStart`、`podman inspect` 全部明文可见，`chmod 600` 的 unit 只挡直接读文件（当初 #5 的结论在此形态下重新成立） | 安装改 `install -Dm600`（默认 644 会让同机用户直接读到文件）；同机多用户场景 §4.1 给回退 diff |
| 37 | 中 | 上游 v11.1.0 **没有** http-upgrade 凭据的环境变量（只有 `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX`、`WSTUNNEL_HTTP_PROXY_LOGIN/_PASSWORD`、`WSTUNNEL_DNS_PREFER_IPV4`、`WSTUNNEL_RESTRICT_HTTP_UPGRADE_PATH_PREFIX`、`RUST_LOG` 等），凭据无法用 `-e` 挪出 argv | §4.4 对照表加一行标出这个缺口，避免以后白折腾 |
| 38 | 中 | 写在 unit 里的凭据失去热加载：`--http-headers-file` 是「每请求重读」，命令行值是启动时读入 ⇒ 换密码必须 `daemon-reload` + `restart`，全隧道瞬断一次 | §6.1 步骤③改写，并在 §6.5 加两条速查 |
| 39 | 信息 | 换来的收益：客户端状态收敛成一个 600 的 unit 文件，无需目录、属主、SELinux 标签与挂载顺序；裸机与容器两种形态写法一致 | 保留文件方案的全部要点（§3.3、§4.1 diff），随时可切回 |

### 7.8 源码取证：`!PathPrefix` 与客户端 `-P` 的关系（2026-11-28）

结论先行：**服务端 `restrictions.yaml` 里的 `!PathPrefix` 只负责"校验"，不会反向告知客户端该发什么前缀**；客户端仍必须自己把前缀设成 `cdn-socket-stream`，当时本方案已通过 `-e WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX` 等价传入，**命令行因此不需要再写 `-P`**（两者是同一配置的两条入口，同时出现时 `-P` 优先）。紧随其后的 §7.9 记录了反向决定：为少一条注入链路，改回显式 `-P` 并删掉 `-e`；正因为 `-P` 优先，两处**不可**并存。

| # | 级别 | 发现（基准 v11.1.0 源码） | 处理 |
|---|---|---|---|
| 40 | 中 | 客户端 `-P` 与 `-e` 都不给时前缀取默认常量 `v1`（`src/config.rs:9` `DEFAULT_CLIENT_UPGRADE_PATH_PREFIX = "v1"`，`src/config.rs:154-161` 绑定 `-P/--http-upgrade-path-prefix`），发出的升级 URI 为 `/v1/events`，提取出的首段 `v1` 不命中 `^cdn-socket-stream$` → **HTTP 400**，症状是"容器健康、进程不退出、所有隧道全 400" | §2、§4.3 第 1 条、§6.5 已写明；unit 内注释显式说明 `-e` 与 `-P` 等价，避免有人误以为服务端配了前缀客户端就可省 |
| 41 | 信息 | `!PathPrefix` 正则的匹配对象是 `extract_path_prefix()` 剥离后的**首段**，不含 `/events` 后缀；`/x/events`、`/x/a/events`、`/x/a/b/events` 都提取为 `x`，缺 `events` 结尾直接 `BadUpgradeRequest`（`utils.rs:71-82` + 上游单测 `utils.rs:606-631`） | §3.7 新增"首段剥离"小节（含 file:line），`restrictions.yaml` 头注释同步线上请求路径与锚点写法说明 |
| 42 | 信息 | `-r/--restrict-http-upgrade-path-prefix` 与 restrictions 之外的另一处前缀校验：比对同一首段，**精确相等**、非正则，且在 JWT 解析之前短路（`server.rs:115`、`120-127`）；另外 mTLS 下未显式给前缀时会自动采用客户端证书 CN（`lib.rs:72-81`） | §3.6/§3.7/§6.6 已有 `-r` 与 mTLS 提示，本轮补齐语义差异与 file:line |

### 7.9 决策变更：暗号1 由环境变量 `-e` 改为命令行 `-P`（2026-11-28）

采纳「`-P` 方案更稳妥」。客户端单元的 `-e WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX=cdn-socket-stream` 已删除，改为 `client` 子命令后紧跟 `-P cdn-socket-stream`；两条暗号因此在**同一处、同一形态**（都在 `ExecStart` 里）。

| 维度 | 命令行 `-P`（现方案） | 环境变量 `-e`（旧方案） |
|---|---|---|
| 注入链路 | 只有 `ExecStart` 一条 | `[Service] Environment=`（无效）→ 必须 `-e`/`--env-file`/Quadlet `Environment=`，多一层可写错的地方 |
| 与手工验收、裸机写法 | 逐字一致，照抄命令不会漏参 | §5 用例、§4.7 裸机要各写一种形态 |
| 可核对性 | `systemctl cat`、`podman inspect --format '{{json .Config.Cmd}}'`、`cat /proc/<pid>/cmdline` 三处都是同一串 | 需查 `.Config.Env`，与命令行形态混用时容易看错地方 |
| 暴露面 | argv 明文，`ps` 可见 | 进程环境，`/proc/<pid>/environ` 仅同 uid/root 可读 |
| 静默失效风险 | 若日后又加了 `-e`，**`-P` 会赢**，env 值静默无效 | 若误写成 unit 的 `Environment=`，值静默不进容器 → 退回 `v1` |
| 结论 | ✅ 前缀敏感度低于密码，且暗号2 早已在 argv（#36），换 `-P` 不新增实际暴露面 | 保留为可选入口，不推荐与本方案并存 |

| # | 级别 | 发现 / 连带影响 | 处理 |
|---|---|---|---|
| 43 | 中 | 决策变更本体：暗号1 改由 `-P` 提供，`-e` 删除。#19 那个「`[Service] Environment=` 不进容器」的坑由「记住要用 `-e`」变成「压根不用环境变量」，属于消类而非缓解 | 客户端 unit、§2、§4 对照表、§4.3 第 1 条、§4.4、§4.6、§4.7、§5 ⑦、§6.1、§6.2、§6.5 全量同步 |
| 44 | 中 | 新引入的反向风险：`-P` 优先于 env，若两处并存则 env 静默无效；反过来只查 `.Config.Env` 会误判「前缀没生效」 | unit 注释与 §4.4 明确「只写一个、不可并存」；§6.5 400 那行给出 `podman inspect … .Config.Cmd` 的实际 argv 复核法 |
| 45 | 低 | §4.6 Quadlet 示例原本用 `[Container] Environment=`（该写法在 Quadlet 里确实进容器，与 unit 的 `[Service] Environment=` 不同），与 unit 形态不一致会造成两套抄写模板漂移 | 示例改为 `Exec=/home/app/wstunnel client -P cdn-socket-stream …`，并注明两种入口在本方案里二选一 |
| 46 | 信息 | 简化收益：§6.1（换密码）与 §6.2（换前缀）在客户端侧的操作步骤完全合并为「改 unit → `daemon-reload` → `restart`」，不再区分「一个热一个不热」；§5 用例 ⑦ 与单元 `ExecStart` 同形态，复制即用 | 文档相应段落合并改写；历史条目 #19、§7.8 保留原结论并加指向，不改写历史 |

### 7.10 真实环境实测（2026-11-28，两个单元的生命周期 + 端到端转发）

同一台真机把服务端和客户端两个单元都装起来跑通（本机即仓库所在机器，正好是 rootless podman + systemd 用户实例的完整环境；测试痕迹已全部回滚，仓库外无残留）。

| 项目 | 实测值 |
|---|---|
| 发行版 / 内核 | Debian 13 trixie · `6.12.118+deb13-amd64` |
| systemd / podman | `257 (257.13-1~deb13u1)` / `5.4.2`（overlay + crun） |
| 运行形态 | rootless：`systemd --user`（uid 0）+ 手工建的 `podmanv6`（`--ipv6`，网关 10.89.0.1） |
| 镜像 | `ghcr.io/erebe/wstunnel:latest` → `wstunnel-cli 11.1.0`、`Created=2026-10-19`、`sha256:8efb2b5b6f03…`（与本文版本基准一致） |
| 证书 | 自签 CA + 该 CA 签的服务端证书（SAN `tunnel.example.com`），`/etc/hosts` 把域名指到 127.0.0.1 |
| 数据面 | 宿主机 `python3 -m http.server 18081` 当临时目标，客户端加一条 `-L tcp://0.0.0.0:18080:198.247.1.119:18081`，`restrictions.yaml` 追加对应 `!Tunnel`（`cidr 198.247.1.119/32` + `port "18081"`） |

**结果**：31 项断言里 28 项直接通过，2 项是"期望 `inactive` 实际 `failed`"——这是产品行为不是缺陷（#51），1 项是验收脚本自身误报（#55）。

| 维度 | 检查内容 | 结果 |
|---|---|---|
| 语法 | 两个 unit 原样 `install` 后 `systemd-analyze --user verify` | ✅ 零告警（此前在无 systemd 的容器里跑时还会报二进制/man 缺失，真机上连这两条都没有） |
| 启动 | `systemctl --user enable --now` ×2 | ✅ 双双 `active`；`Type=notify` + `--sdnotify=conmon` 生效，无 start-limit、`NRestarts=0`；`default.target.wants/` 两个符号链接就位 |
| 端口 | 服务端 `-p 55443:55443`；客户端 `--network host` 的 6 条 `-L` | ✅ 55443 已发布；6 个监听直接落宿主机（`podman ps --port` 为空、`ss` 属主显示 `conmon`，都是正常现象，#55） |
| 鉴权负例 | 无凭据 / 前缀错 / 目标主机不在白名单 / 目标端口不在白名单 / 密码错（5 组，真客户端发起） | ✅ 一律 `Rejecting connection with not allowed destination: RemoteAddr{…}` |
| 判定顺序 | 裸 curl `/cdn-socket-stream`、`/whatever`、`/cdn-socket-stream/events`、`/cdn-socket-stream/a/b/events`、`/v1/events` | ✅ 缺 `events` 后缀 → `bad upgrade request`；有后缀 → `error while decoding jwt`（JWT 在 restrictions 之前），§3.7 结论成立，同时说明**白名单没法只靠 curl 验**（#49） |
| 白名单放行 | 正例打通 | ✅ 服务端 `Tunnel accepted due to matched restriction: auth-tunnels`，`curl 127.0.0.1:18080` 返回 200 / 3719 字节 |
| 热加载 | 改 `/etc/wstunnel/restrictions.yaml`（只读 bind mount）不重启服务端 | ✅ 新规则立即生效 ⇒ `:ro` + inotify 的组合成立（关闭 #30 的"未实测"；SELinux 分支仍未测，#53） |
| 停止 | `systemctl --user stop` ×2 | ⚠ 容器和 `%t/%n.ctr-id` 都被 `ExecStop`/`ExecStopPost` 清干净（重复 stop 幂等），但 unit 落 `failed/exit-code`、`ExecMainStatus=143`（#51） |
| 自愈 | `kill -TERM` / `podman kill -s KILL` 容器主进程 | ✅ `Restart=always` + `RestartSec=5` 生效：`NRestarts` +1、~10s 内回 `active`、隧道自动重建 |
| 卡死 | `SIGSTOP` 容器主进程后 stop | ✅ `podman stop -t 10` 到点 SIGKILL（`ExecMainStatus=137`），`ExecStopPost` 仍清干净，`TimeoutStopSec=70` 未被触达，unit 不挂死 |
| 独立性 | 只停服务端 | ✅ 客户端容器与 6 个 `-L` 监听不受影响；服务端回来后首个探测（≤2s）就恢复 200 |
| `-P` vs `-e` | 三组对照：只给 `-e` / `-P` 对 + `-e` 错 / `-P` 错 + `-e` 对 | ✅ 命令行 `-P` 赢（#44 与 §7.9 的"未在真二进制上验证"正式关闭） |
| 开机自启 | enable 链路四要素 | ✅ `default.target.wants` 符号链接 + 依赖树含两单元 + `user@0.service` active + `Linger`（实测前正是 `no`，恰好复现 §3.2 那个坑；`enable-linger` 后变 `yes`） |

**新增结论（#47 起）**

| # | 级别 | 发现 | 处理 |
|---|---|---|---|
| 47 | **高** | 客户端容器的 TLS 根只有**镜像内系统信任库**，`--tls-verify-certificate` 遇自签/私有 CA 直接握手失败，且**上游没有客户端侧自定义 CA 参数**。真机症状是静默失败：服务端 `error while accepting TLS connection received fatal alert: UnknownCA`，客户端 INFO 里只有反复的 `Doing TLS handshake` + 0.6/0.8/1.6/3.2/6.4s 指数退避，`systemctl is-active` 与 `podman ps` 全程正常 | 客户端单元加一行 `-v /etc/wstunnel/ca.pem:/etc/ssl/certs/wstunnel-ca.pem:ro`（配方与三种取舍见 §4.3 第 5 条），unit 注释与 §6.5 同步 |
| 48 | **高** | 客户端**按需建连**：单元起来后日志只有 6 行 `Starting TCP server listening cnx on 0.0.0.0:<port>`，没有任何"已连上服务端"的成功行；首次流量到来才发起 wss 握手 | 部署收工前必须主动打一次流量：§4.2 补了 `nc -z` + `curl` 两步、§6.4 补了服务端 `matched restriction` 的回查。这条与 #47 叠加是最坏组合——两侧指标全绿、实际一条隧道都没通过 |
| 49 | 中 | 白名单**不能用裸 curl 单独验证**：JWT 解析（`server.rs:129`）早于 restrictions 判定（`server.rs:141`），任何 curl 都在 400 处就结束；4 条路径探测只证明了 §3.7 的判定顺序 | §5 的 5 组负例改成"用真客户端发起"，§6.4 给出可复制命令 |
| 50 | 信息 | `-P` 优先于 `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX` 在真二进制上三组对照通过 | #44、§7.9 的"推导"升级为"实测" |
| 51 | 中 | `systemctl --user stop` 后 unit 是 `failed`（`Result=exit-code`、`ExecMainStatus=143`）而非 `inactive`：`ENTRYPOINT=dumb-init` 打印 `Child exited with status 143` 并把退出码原样交给 systemd | §3.5 增补 `SuccessExitStatus=143`（真机验证：加完 stop → `inactive`/`success`，`Restart=always` 照常自愈）。运维判活别只看 `is-active`，配合 `-p Result -p ExecMainStatus` 一起看（§6.4） |
| 52 | 信息 | `ExecStop`/`ExecStopPost` 靠 `--cidfile=%t/%n.ctr-id` 精确定位本单元容器：两单元互不牵连（容器名分别 `wstunnel`/`wstunnel-client`），单停一侧另一个不受影响，重复 stop 幂等（`--ignore` 生效） | 与 §3.5 的 unit 改名迁移互相印证：`%n` 变了旧 cidfile 成孤儿，需手工清 |
| 53 | 中 | 只读 bind mount 上的 inotify 热加载在 Debian 13 + podman 5.4.2 上实测有效（追加规则 → 未重启即放行）；**SELinux enforcing 分支仍未实测**，#31 的 `semanage fcontext` 固化照做 | §3.3 该项从"未实测"改为"已实测 + SELinux 例外" |
| 54 | 信息 | 系统 CA 是**进程内快照 + 每小时整体重载**：`wstunnel-cli/src/main.rs:108` 调 `SystemCaReloader::start(None)`，`tunnel/ca_reloader.rs:22-38` 的 interval 缺省 3600s；根 store 组装在 `protocols/tls/server.rs:116` + `tunnel/ca_reloader.rs:59-72`（`rustls-native-certs 0.8.5`） | §4.3 第 5 条写明"换 CA 直接 restart 客户端"，不要等自刷；§6.5 加一行速查 |
| 55 | 低 | 验收脚本自身的两个坑：① `podman ps --filter name=wstunnel` 是**子串**匹配，连带命中 `wstunnel-client`，用它判"服务端容器已清干净"必然误报（要 `--filter name='^wstunnel$'`）② rootless + `--network host` 下 `ss -lntp` 的属主进程显示 `conmon` 而不是 `wstunnel`，`podman ps` 也没有 `.NetworkMode` 字段可看 | §6.4 命令改用锚定正则并注明看监听的正确姿势 |

**实测过的"未实测"清单**（原列表在 §7.9 之后）：真实握手与端到端转发、`Type=notify` + `--sdnotify=conmon` 的实际时序、`--network host` 下的 6 条 `-L` 监听、只读 bind mount 上的 inotify 热加载、`-P` 与环境变量的优先级、`install -Dm600` 后 `systemctl --user show -p ExecStart` 的可见范围（确认：明文可见，#36 成立）、`ExecStop`/`ExecStopPost` 与 cidfile 清理、`Restart=always`/`RestartSec=5`/`TimeoutStopSec=70` 三级停止与自愈、`loginctl enable-linger` 的效果、两个单元各自的 `systemd-analyze verify`。

**仍未实测**：整机重启后的自启（四要素齐备，但本机是本次会话的宿主，`systemctl --user isolate default.target` 与 `loginctl terminate-user root` 都会把会话本身停掉，实测过依赖树确认 `session-60.scope` 不在 `default.target` 内 ⇒ 会自杀，留到上线时确认）；SELinux enforcing 下的 `,z`/`:Z` 与 filetrans 继承（#31）；`podman auto-update` + 固定 `:v11.1.0` 的重建流程；WebTransport（`wts://`，需要 UDP）；`SSL_CERT_FILE`/`SSL_CERT_DIR` 形态（本轮用的是"往 `/etc/ssl/certs/` 里塞一个 pem"这条已验证路径）；Quadlet 形态（§4.6）。

**本轮之前已完成的静态验证**（原「未在本机验证的项」段落末尾的内容，原样搬到这里保留）：`systemd-analyze verify` 通过 `container-wstunnel-server.service` 与 `container-wstunnel-client.service` 两个单元（当时仅报二进制与 `man:podman-generate-systemd(1)` 缺失，属环境因素，真机上已连这两条都不报）；`restrictions.yaml` 经 PyYAML（含 `!Tag` 自定义标签）解析确认结构正确、6 条规则与映射表一一对应；`printf 'wstunnel:Wstunnel-2026' | base64` 与配置中的串逐字节一致。历史条目（#19、#30、#31、#44 以及 §7.8/§7.9 的推导）保留当时原文与推导过程、只加指向不改写历史；§5 全量用例仍建议上线时在真实目标侧再跑一遍。


## 8. 附件（本目录）

| 文件 | 用途 |
|---|---|
| `restrictions.yaml` | 服务端限制/鉴权配置 → `/etc/wstunnel/restrictions.yaml` |
| `container-wstunnel-server.service` | 服务端 Podman 单元 → `~/.config/systemd/user/` |
| `container-wstunnel-client.service` | 客户端 Podman 单元 → `~/.config/systemd/user/` |

> 部署前记得全局替换：`tunnel.example.com`（你的域名）、`cdn-socket-stream`（路径前缀暗号）、`Wstunnel-2026`（密码，换后同步 base64）、`podmanv6`（服务端 podman 网络名）。

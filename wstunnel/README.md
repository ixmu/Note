# wstunnel 安全部署文档

> 版本基准：**wstunnel v11.1.0**（Rust 版，已核对 = 上游 GitHub Releases 最新版）
> 服务端形态：**Podman 容器**（`ghcr.io/erebe/wstunnel`）· 客户端形态：裸二进制 + systemd
> 首次整理 2026-11-22 · 审计修订 2026-11-28（同日跟进远端改动：`wstunnel.service` → `container-wstunnel.service`、路径前缀改为 `cdn-socket-stream`）
> 特点：自有域名 + SSL 证书（wss）+ 双重鉴权（路径前缀 + Basic）+ 目标 `host:port` 白名单
> 本文件原名 `wstunnel部署文档.md`，已重命名为 `README.md`，便于在 GitHub 上进入 `wstunnel/` 目录直接阅读。

## 0. 本目录文件与快速上手

| 文件 | 用途 | 落地路径 |
|---|---|---|
| `container-wstunnel.service` | 服务端 systemd unit（podman run 形态，rootless） | `~/.config/systemd/user/` |
| `wstunnel-client.service` | 客户端 systemd unit | `/etc/systemd/system/` |
| `restrictions.yaml` | 服务端白名单授权 | `/opt/wstunnel/restrictions.yaml` |
| `README.md` | 本文档 | — |

```bash
# 部署前必须全局替换的 4 个占位值
#   tunnel.example.com  → 你的域名
#   cdn-socket-stream   → 路径前缀暗号
#   Wstunnel-2026       → Basic 密码（改动后同步 restrictions.yaml 里的 base64，见 §6.1）
#   podmanv6            → 你的 podman 网络名（需预先创建，见 §3.2）
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
| 路径前缀（暗号1） | `cdn-socket-stream` | 客户端 `-P` / `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX`；**不设时默认前缀是 `v1`，会被 restrictions 直接拒** |
| Basic 账号（暗号2） | `wstunnel:Wstunnel-2026` | base64: `d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==`（已用 `printf … \| base64` 复核一致） |
| 证书文件 | `/opt/wstunnel/fullchain.pem` + `privkey.pem` | 容器内同路径（bind mount）；自动热加载 |
| 限制文件 | `/opt/wstunnel/restrictions.yaml` | 自动热加载，改完即生效 |
| 运行镜像 | `ghcr.io/erebe/wstunnel` | 镜像内二进制 `/home/app/wstunnel`，`USER app`（非 root） |
| mTLS 强化（可选） | `/opt/wstunnel/ca.pem` | 服务端 `--tls-client-ca-certs /opt/wstunnel/ca.pem` |

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

`container-wstunnel.service` 是 `podman generate systemd` 形态的单元（`ExecStart=podman run …`、`Type=notify` + `--sdnotify=conmon`、`WantedBy=default.target`）。以 `default.target` + `%t/containers` 判断为 **rootless 用户级单元**，全部操作按当前用户执行，不需要 `sudo`。

### 3.1 落地位置

| 内容 | 路径 | 权限建议 |
|---|---|---|
| 证书链 | `/opt/wstunnel/fullchain.pem` | 644 |
| 私钥 | `/opt/wstunnel/privkey.pem` | 600（**必须让容器内 uid 读到，见 §3.3**） |
| 白名单 | `/opt/wstunnel/restrictions.yaml` | 640（同上） |
| 单元文件 | `~/.config/systemd/user/container-wstunnel.service` | 644 |
| 数据/运行目录 | `%t/containers`（`RequiresMountsFor`）、`%t/%n.ctr-id` | systemd 自动管理 |

> 裸机二进制部署（不用容器）见 §3.6，本目录历史版本即为该形态。

### 3.2 部署命令

```bash
podman --version                                   # 建议 ≥ 4.x
podman network exists podmanv6 || podman network create --ipv6 podmanv6

mkdir -p /opt/wstunnel
# 上传 fullchain.pem / privkey.pem / restrictions.yaml 到 /opt/wstunnel/ 后：
chmod 644 /opt/wstunnel/fullchain.pem
chmod 600 /opt/wstunnel/privkey.pem
chmod 640 /opt/wstunnel/restrictions.yaml
chown -R "$(id -u)":"$(id -g)" /opt/wstunnel       # rootless：属主就是部署者本人
sudo setsebool -P container_use_nfs 1 2>/dev/null   # 仅当 /opt/wstunnel 在 NFS 上；SELinux 见 §3.3

install -Dm644 container-wstunnel.service ~/.config/systemd/user/container-wstunnel.service
systemd-analyze --user verify ~/.config/systemd/user/container-wstunnel.service
systemctl --user daemon-reload
systemctl --user enable --now container-wstunnel.service
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
| `podman logs wstunnel` 出现 `Permission denied` 读 privkey/restrictions | 文件属主与容器内映射 uid 不对应 | ① 卷加 `U` 选项：`-v /opt/wstunnel:/opt/wstunnel:ro,U`（podman ≥3.4，自动把挂载目录 chown 给容器 uid）② 容器加 `--user 0:0`（rootless 下即部署者本人，600 私钥直接可读）③ 手工把属主/属组调成容器映射 uid |
| rootful 运行时全部文件读不到 | `USER app`(1000) ≠ 文件属主 root，600 私钥不可读 | `chgrp 1000 /opt/wstunnel/privkey.pem && chmod 640 …`，或 `--user 0:0` |
| SELinux enforcing 下报 `Permission denied`（文件权限看起来没问题） | bind mount 缺少安全标签 | 卷尾加 `:z`（同机多容器共享标签）或 `:Z`（独占）：`-v /opt/wstunnel:/opt/wstunnel:ro,Z`；用 `getenforce` 确认是否需要 |

另外两点与卷直接相关：

- **`:rw` → `:ro`**：wstunnel 对证书与 restrictions 只需**读取**（热加载走 inotify，只读挂载同样能收到变更事件），建议改 `:ro` 收紧；证书续期由宿主机侧的 deploy-hook 写入（见 §5.2）。
- **`--network podmanv6` 必须已存在**，否则服务进入 restart loop；容器内解析公网域名走该网络的内置 DNS（aardvark-dns 转发宿主机 resolver）。宿主机 DNS 异常时给 wstunnel 追加 `--dns-resolver dns://223.5.5.5`（DoT 用 `dns+tls://8.8.8.8?sni=dns.google`）。

### 3.4 镜像与自动更新

- `--label io.containers.autoupdate=registry` 只有在 timer 真正跑起来时才生效：`systemctl --user list-timers | grep auto-update`，没有就 `systemctl --user enable --now podman-auto-update.timer`。手动触发/预览：`podman auto-update --dry-run`、`podman auto-update`。
- 更新后容器会被重建，`restrictions.yaml` 与证书在宿主机上，不会丢。
- **`:latest` 与文档基准冲突**：本文按 v11.1.0 核对，而 `:latest` 会随上游发版漂移（大版本可能改参数名）。建议固定 `ghcr.io/erebe/wstunnel:v11.1.0`，升级时显式改 tag（`ghcr.io` 上 `latest` 无回滚锚点）。
- `wss://[::]:55443` 已监听双栈；若将来启用 WebTransport（`wts://` 或 `--enable-webtransport`），`-p 55443:55443` 只映射 TCP，需补 `-p 55443:55443/udp`，并在防火墙放行 UDP。

### 3.5 单元里可以补的几行

```ini
[Unit]
# 该文件未设 StartLimit*，走 systemd 默认（10s 内 5 次即进 failed 状态）。
# 想让它在证书/网络异常期间持续自愈，加：
StartLimitIntervalSec=0
# 单元文件里没有 ExecReload；改配置靠热加载，换镜像靠 podman auto-update，
# 只有改启动参数时才需要 systemctl --user restart container-wstunnel
```

日志排查用 `podman logs -f wstunnel`（容器 stdout）与 `journalctl --user -u container-wstunnel.service`（生命周期）。

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

## 4. 客户端部署

### 4.1 方式 A（简单）：单文件 systemd unit

使用本目录 `wstunnel-client.service`：

```bash
# unit 里已含全部 6 条 -L 隧道；密码写在 ExecStart 中
chmod 600 /etc/systemd/system/wstunnel-client.service
systemd-analyze verify /etc/systemd/system/wstunnel-client.service
systemctl daemon-reload
systemctl enable --now wstunnel-client
journalctl -u wstunnel-client -f
ss -lntp | grep -E '2223|10000|10001|8101|5002|55689'   # 确认 6 个本地端口已监听
```

注意：**本机 10000 端口**会被占用（映射到 `43.134.70.211:9999`），部署前先确认无冲突。

> ⚠ 更正旧版说法：`chmod 600` 只挡住别人读 unit 文件，**密码仍会出现在进程命令行**，任何本机用户 `ps auxww` 或 `systemctl show -p ExecStart` 都能看到。多用户机器请用 §4.2。

### 4.2 方式 B：凭据落盘（多用户机器防 `ps` 泄密）

```bash
# /etc/wstunnel/auth.txt —— 每请求重读，可热换密码
# 内容一行:  Authorization: Basic d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==
chmod 600 /etc/wstunnel/auth.txt
```

unit 中把 `--http-upgrade-credentials ...` 换成 `--http-headers-file /etc/wstunnel/auth.txt`（二者勿同时使用，**文件优先**，上游原话 "It overrides http_headers specified from command line"）。

进阶（systemd ≥ 247）：`LoadCredential=auth:/etc/wstunnel/auth.txt` 让 systemd 把凭据拷进仅 root 可见的 tmpfs（路径由 `$CREDENTIALS_DIRECTORY` / 说明符 `%d` 给出）。因为 `ExecStart=` 不做 shell 变量展开，稳妥写法是套一层 shell：

```ini
ExecStart=/bin/sh -c 'exec /usr/local/bin/wstunnel client \
  --tls-verify-certificate --http-headers-file "$CREDENTIALS_DIRECTORY/auth.txt" \
  -L tcp://0.0.0.0:2223:gw.pyproxy.com:2222 wss://tunnel.example.com:55443'
```

（较新 systemd 也支持直接在 `ExecStart=` 里用 `%d/auth.txt` 代替 `$CREDENTIALS_DIRECTORY`，此写法未在本机实测，见 §7 未验证项。）

### 4.3 环境变量对照表（客户端）

| 参数 | 环境变量 | 备注 |
|---|---|---|
| `-P` 路径前缀 | `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX` | 默认 `v1`；unit 用 `Environment=` 写入 |
| `-p` http 代理 | `HTTP_PROXY` | 客户端在代理后面出网时用 |
| 代理账号/密码 | `WSTUNNEL_HTTP_PROXY_LOGIN` / `WSTUNNEL_HTTP_PROXY_PASSWORD` | 会覆盖 `-p` 里的账号 |
| `--log-lvl` 日志级别 | `RUST_LOG` | TRACE/DEBUG/INFO/WARN/ERROR/OFF，默认 INFO |
| （服务端）`-r` 限制前缀 | `WSTUNNEL_RESTRICT_HTTP_UPGRADE_PATH_PREFIX` | 服务端侧，与 restrictions 叠加 |
| `--dns-resolver-prefer-ipv4` | `WSTUNNEL_DNS_PREFER_IPV4` | IPv6 异常时减少延迟 |
| `--no-color` | `NO_COLOR=1` | 日志去色 |
| `--nb-worker-threads` | `TOKIO_WORKER_THREADS` | 线程数 |
| `--http-upgrade-credentials` | ❌ 无 | 只能命令行或 auth.txt |
| `-L` / `-R` / `--tls-verify-certificate` | ❌ 无 | 只能命令行 |

容器形态的镜像 `ENV RUST_LOG=INFO` 已内置，需要 DEBUG 时在 unit 里加 `Environment=RUST_LOG=DEBUG`（`Environment=PODMAN_SYSTEMD_UNIT=%n` 那行下面）。

### 4.4 本地监听地址（开放到局域网/所有网卡）

`-L` 缺省只绑 **127.0.0.1**（仅本机可达）。要监听所有网卡就在 URL 里显式写 BIND 前缀（语法 `{tcp,udp}://[BIND:]PORT:HOST:PORT`）：

```
-L tcp://0.0.0.0:2223:gw.pyproxy.com:2222         # IPv4 全部网卡
-L tcp://[::]:2223:gw.pyproxy.com:2222            # IPv6 全部网卡
-L tcp://192.168.1.10:2223:gw.pyproxy.com:2222    # 只绑指定网卡（推荐）
```

**安全提醒**：TCP/UDP 隧道这些本地端口**本身没有任何鉴权**，开到 `0.0.0.0` 后能连到端口的任何机器都能借隧道访问目标服务。建议：

- 只绑内网网卡 IP（如上第三行写法）；
- 或防火墙按来源网段白名单：`firewall-cmd --add-rich-rule="rule family=ipv4 source address=192.168.0.0/24 port port=2223 protocol=tcp accept"`（注意先 remove 掉宽泛放行规则）；
- 动态端口场景改用带账号密码的入口：`socks5://0.0.0.0:1212?login=xx&password=xx` 或 `http://0.0.0.0:1212?login=xx&password=xx`。

## 5. 验收测试

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

# ⑤ 只看端口/TLS 是否通（注意：curl 无 JWT，必然被拒，返回 400 属正常）
curl -sk -o /dev/null -w '%{http_code}\n' https://<域名>:55443/cdn-socket-stream

# ⑥ 前缀暗号是否真的生效 → 应被拒
wstunnel client --tls-verify-certificate \
  --http-upgrade-credentials 'wstunnel:Wstunnel-2026' -P wrong-prefix \
  -L tcp://3333:gw.pyproxy.com:2222 wss://<域名>:55443
```

①通、②③④⑥拒 = TLS + 双暗号 + `host:port` 白名单全部生效。判定顺序是先解 JWT 再查 restrictions，所以裸 `curl`（无 `Sec-WebSocket-Protocol`）拿不到"白名单已放行"的结论，白名单必须用真客户端测。

### 5.1 残余风险：域名解析不受 cidr 约束

`host` 命中的域名目标，其解析结果不受 `cidr` 限制（源码里域名分支只看 `host`）。若某白名单域名的 DNS 可控或发生 rebinding，隧道可能被指到 `127.0.0.1` / `169.254.169.254` 之类的内网地址。缓解：对可固定的目标改用 **IP + `cidr: x.x.x.x/32`** 写法，或在服务端 `/etc/hosts`、resolver 层锁定解析结果。

### 5.2 证书续期：bind mount 的是副本，不是 live 符号链接

`/opt/wstunnel` 里放的是**拷贝**，Let's Encrypt 续期只会更新 `/etc/letsencrypt/{live,archive}`，不会自动同步过来。二选一：

```bash
# 方案 1（推荐）：续期时重新拷贝，wstunnel 侦测到文件变化后热加载
sudo tee /etc/letsencrypt/renewal-hooks/deploy/wstunnel-copy.sh >/dev/null <<'EOF'
#!/bin/sh
set -eu
dom=tunnel.example.com
install -m644 "/etc/letsencrypt/live/$dom/fullchain.pem" /opt/wstunnel/fullchain.pem
install -m640 -o root -g 1000 "/etc/letsencrypt/live/$dom/privkey.pem" /opt/wstunnel/privkey.pem
EOF
sudo chmod 755 /etc/letsencrypt/renewal-hooks/deploy/wstunnel-copy.sh

# 方案 2：整树只读挂载，unit 里直接指向 live/（不能只挂 live/，
# 因为 live 下的符号链接是 ../../archive/<域名>/privkeyN.pem 的相对路径，缺 archive 会断）
#   -v /etc/letsencrypt:/etc/letsencrypt:ro,Z
#   --tls-certificate /etc/letsencrypt/live/tunnel.example.com/fullchain.pem
#   --tls-private-key /etc/letsencrypt/live/tunnel.example.com/privkey.pem
```

## 6. 日常运维

### 6.1 轮换密码（3 步，不断线）

```bash
echo -n 'wstunnel:新密码' | base64                      # ① 生成新 base64
sed -i 's/d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==/<新串>/' \
  /opt/wstunnel/restrictions.yaml                       # ② 更新服务端（热加载；本方案仅 1 处引用）
# ③ 更新客户端 unit 或 auth.txt 后: systemctl daemon-reload && systemctl restart wstunnel-client
```

### 6.2 改路径前缀暗号

必须三处一致，漏一处就是「客户端连得上但所有隧道被拒」：

```bash
grep -rn cdn-socket-stream restrictions.yaml wstunnel-client.service README.md   # 本仓库内 3 处
# 服务端：restrictions.yaml 的 !PathPrefix（热加载，无需重启容器）
# 客户端：wstunnel-client.service 的 WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX（需 daemon-reload + restart）
# 如启用了裸机 -r / 容器里加 -r，也要一起改
```

### 6.3 增删隧道端口

`restrictions.yaml` 加/删一条 `!Tunnel`（记得同时定好它的 `host` 或 `cidr`）→ 保存即生效；再更新客户端 unit 的 `-L` 列表并 `systemctl daemon-reload && systemctl restart wstunnel-client`。

### 6.4 自检命令

```bash
systemd-analyze --user verify ~/.config/systemd/user/container-wstunnel.service
podman ps --filter name=wstunnel --format '{{.Names}} {{.Status}} {{.Image}}'
podman logs --since 10m wstunnel | grep -E 'accepted due to|Rejecting|listening'
systemctl --user show container-wstunnel.service -p NRestarts -p ExecStart
journalctl --user -u container-wstunnel.service --since -10m
python3 -c "import yaml;yaml.safe_load(open('/opt/wstunnel/restrictions.yaml'))"   # 改完 YAML 先语法自检
```

### 6.5 常见问题速查

| 现象 | 原因 | 处理 |
|---|---|---|
| 容器反复重建、日志显示读取失败 | 证书/私钥/限制文件缺失、写了一半，或**容器读不到**（见 §3.3） | 补齐文件并处理属主/SELinux 标签；`podman logs -f wstunnel` 观察 |
| `podman logs` 空、unit 进入 failed | `podmanv6` 网络不存在、端口被占、镜像拉取失败 | `podman network exists podmanv6`；`ss -lntp \| grep 55443`；`podman pull ghcr.io/erebe/wstunnel:v11.1.0` |
| 服务器重启后服务没起来 | rootless 用户单元未开机启动 | `loginctl enable-linger "$USER"` |
| 客户端证书报错 | 忘加 `--tls-verify-certificate`，或证书链不完整 | 用 fullchain（含中间证书）并显式开启校验；客户端用内置根证书库校验 |
| 域名隧道不通、IP 隧道正常 | 容器/宿主机解析不了目标域名 | wstunnel 追加 `--dns-resolver dns://223.5.5.5`（DoT 用 `dns+tls://8.8.8.8?sni=dns.google`） |
| 客户端起不来，address already in use | 本地端口冲突（重点查 10000） | 换本地端口或停占用服务 |
| 端口只能本机访问 | `-L` 缺省绑 `127.0.0.1` | BIND 前缀加 `0.0.0.0:`，见 §4.4 |
| 隧道频繁断开重连 | 中间设备回收空闲连接 | 调小 `--websocket-ping-frequency`（默认 30s，可设 15s） |
| 加了 `-P` 仍被拒 | 前缀不匹配，或一侧漏配（缺省是 `v1`） | 三处必须一致：客户端 `-P`、`restrictions.yaml` 的 `!PathPrefix`、（如启用）服务端 `-r`，见 §6.2 |
| 续期后仍是旧证书 | `/opt/wstunnel` 是副本，deploy-hook 未配置 | 见 §5.2 |
| 扫描器不停连 | 只拦到 HTTP 层，属正常 | 55443 非标端口 + 双暗号 + host 白名单已足够；要更强可上 mTLS |
| 裸机单元启动即失败并提示挂载错误 | `ReadWritePaths` 指向不存在的目录 | 建目录或用 `ReadWritePaths=!/path`（仅 §3.6 场景） |
| 上了 `wts://` 后 10s 超时 | QUIC 需要 UDP 端到端可达 | 服务端 `--enable-webtransport` + `-p 55443:55443/udp` + 防火墙放行 UDP；`--http-proxy`、`--tls-sni-disable`、`--tls-ech-enable` 与 WebTransport 不兼容 |

### 6.6 安全升级路线

| 级别 | 手段 | 配置 |
|---|---|---|
| 当前 | TLS + 路径前缀 + Basic + `host:port` 白名单 | 本文档方案 |
| 更高 | mTLS 双向证书 | 服务端 `--tls-client-ca-certs /opt/wstunnel/ca.pem`，客户端 `--tls-certificate/--tls-private-key`（无证书者在握手期即被拒；注意 mTLS 下升级前缀默认取证书 CN，需与 `-P`/`!PathPrefix` 对齐） |

## 7. 审计与同步记录

### 7.1 首轮审计（2026-11-28，配置与文档）

已核实的基准：上游 `erebe/wstunnel` 仓库 README、`restrictions.yaml` 示例、`src/restrictions/{types,mod}.rs`、`src/tunnel/server/{utils,server}.rs`、`src/tunnel/transport/jwt.rs`，以及 Releases API 返回的 `tag_name = v11.1.0`（= 本方案版本基准）。

| # | 级别 | 发现 | 处理 |
|---|---|---|---|
| 1 | 中 | 旧 `restrictions.yaml` 仅锁端口，`host: ^.*$` + `cidr 0/0` ⇒ 拿到双暗号即可把 6 个端口转去任意主机（SSRF 面） | 按映射表拆成 6 条 `!Tunnel`，域名走 `host` 正则、字面 IP 走 `/32` cidr；保留"宽松回退"注释块 |
| 2 | 中 | 文档称默认拒绝返回 403；源码 `bad_request()` 实为 **400** | 已更正（§3.7、§5） |
| 3 | 中 | 未说明 `port`/`protocol` 留空 = 不限制，误删即全放开 | 已在 §3.7 显式写明 |
| 4 | 中 | 未说明域名目标只看 `host`、`cidr` 不参与（rebinding 残余风险） | 已新增 §5.1 |
| 5 | 低 | 文档称客户端 unit `chmod 600` 可防泄密，实际 `ps` 仍能看到密码 | §4.1 已更正并指向 §4.2 |
| 6 | 低 | `-P` 缺省值 `v1`（旧文档未提），漏配会被 restrictions 拒 | 参数清单 + 速查表补充 |
| 7 | 低 | 客户端 unit 无资源/安全约束，以 root 裸跑、无 fd 上限、重启限流缺失 | 加 `LimitNOFILE`、`RestartSec=5`、`StartLimitIntervalSec=0` 与 `ProtectSystem=strict` 等加固集，并给出可选降权注释 |
| 8 | 低 | `--dns-resolver`、`-r`、`--websocket-ping-frequency` 等只在速查表出现，unit 中无可取消注释的入口 | 在 unit 内以注释形式给出 |
| 9 | 信息 | v11 已支持 WebTransport（`wts://`）、`--restrict-to` 简化白名单、`--http-headers-file` 每请求重读 | 文档补记 |
| 10 | 已核对无误 | base64 值、`--tls-verify-certificate` 为无值开关、`--http-headers-file` 优先级、socks5 带 `login/password`、ping 默认 30s、`WSTUNNEL_*` 环境变量名、mTLS 参数名 | 保持原描述 |

### 7.2 同步远端改动（2026-11-28，`d8573e7`）

远端把 `wstunnel.service` 替换为 `container-wstunnel.service`（Podman 版），本文档已跟随重写：§0、§3、§5、§6 全部按容器形态改写，首轮审计针对裸机 unit 的加固建议移入 §3.6 保留。新增的容器侧结论（均以上游 `Dockerfile` 为据）：

| # | 级别 | 发现 | 建议 |
|---|---|---|---|
| 11 | **高** | 镜像 `USER app`（uid 1000）而非 root，文档原要求的 `privkey.pem` 600 属主 root ⇒ 容器可能读不到私钥/白名单 | 卷用 `:ro,U`、或容器 `--user 0:0`、或按容器映射 uid 调整属组（§3.3） |
| 12 | 中 | `-v /opt/wstunnel:/opt/wstunnel:rw`：SELinux enforcing 下缺安全标签会被拒；且 wstunnel 无需写权限 | 改 `:ro` 并按需加 `:Z`/`:z`（§3.3） |
| 13 | 中 | `:latest` + `autoupdate=registry` 会让服务端版本脱离本文的 v11.1.0 基准；且 autoupdate 需 timer 才生效 | tag 固定 `:v11.1.0`；`systemctl --user enable --now podman-auto-update.timer`（§3.4） |
| 14 | 中 | `/opt/wstunnel` 里的证书是副本，续期不会自动同步 ⇒ "续期无需重启"依赖文件真的被刷新 | 配 deploy-hook 或整树只读挂 `/etc/letsencrypt`（§5.2） |
| 15 | 低 | rootless 用户单元未开 linger 时，机器重启后不自启 | `loginctl enable-linger "$USER"`（§3.2） |
| 16 | 低 | 单元未设 `StartLimit*`，走默认 10s/5 次即 failed，证书或网络短暂异常会停在一处不动 | 需持续自愈则加 `StartLimitIntervalSec=0`（§3.5） |
| 17 | 低 | `-p 55443:55443` 只映射 TCP，日后启用 WebTransport 时 UDP 缺失会表现为握手 10s 超时 | 需要时补 `-p 55443:55443/udp`（§3.4） |
| 18 | 已核对无误 | `/home/app/wstunnel` 路径、`ENTRYPOINT` 是 `dumb-init`（命令行首参不会被覆盖）、`Type=notify` + `--sdnotify=conmon` + `NotifyAccess=all` 组合、`PODMAN_SYSTEMD_UNIT=%n`、`--cgroups=no-conmon`（`podman generate systemd` 正常输出）、`wss://[::]` 双栈监听 | 保持不动 |

### 7.3 本轮改动（2026-11-28）

- 路径前缀暗号：`my-secret-path` → **`cdn-socket-stream`**，共 3 个文件同步（`restrictions.yaml` 的 `!PathPrefix`、`wstunnel-client.service` 的 `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX`、本文档 §0/§2/§3.6/§5/§6.2），已 `grep -r my-secret-path` 确认无残留。
- 文档随远端 `d8573e7` 重写服务端章节，并新增 §5.2 证书续期、§6.2 改前缀流程。

**未在本机验证的项**（本仓库所在容器无 podman/systemd 运行实例、无 `wstunnel` 二进制）：真实握手与转发、podman 卷权限与 SELinux 标签行为、`podman auto-update` 重建流程、`%d` 说明符写法。上线前按 §5 全量跑一遍。已完成的本地验证：`systemd-analyze verify` 通过两个 unit（仅提示二进制缺失）；`restrictions.yaml` 经 PyYAML（含 `!Tag` 自定义标签）解析确认结构正确、6 条规则与映射表一一对应；`printf 'wstunnel:Wstunnel-2026' | base64` 与配置文件中的串逐字节一致。

## 8. 附件（本目录）

| 文件 | 用途 |
|---|---|
| `restrictions.yaml` | 服务端限制/鉴权配置 → `/opt/wstunnel/restrictions.yaml` |
| `container-wstunnel.service` | 服务端 Podman systemd 单元 → `~/.config/systemd/user/` |
| `wstunnel-client.service` | 客户端 systemd unit → `/etc/systemd/system/` |

> 部署前记得全局替换：`tunnel.example.com`（你的域名）、`cdn-socket-stream`（路径前缀暗号）、`Wstunnel-2026`（密码，换后同步 base64）、`podmanv6`（podman 网络名）。

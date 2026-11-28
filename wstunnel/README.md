# wstunnel 安全部署文档

> 版本基准：**wstunnel v11.1.0**（Rust 版，已核对 = 上游 GitHub Releases 最新版）· 首次整理 2026-11-22 · 审计修订 2026-11-28
> 特点：自有域名 + SSL 证书（wss）+ 双重鉴权（路径前缀 + Basic）+ 目标 `host:port` 白名单
> 本文件原名 `wstunnel部署文档.md`，已重命名为 `README.md`，便于在 GitHub 上进入 `wstunnel/` 目录直接阅读。

## 0. 本目录文件与快速上手

| 文件 | 用途 | 落地路径 |
|---|---|---|
| `wstunnel.service` | 服务端 systemd unit | `/etc/systemd/system/` |
| `wstunnel-client.service` | 客户端 systemd unit | `/etc/systemd/system/` |
| `restrictions.yaml` | 服务端白名单授权 | `/opt/wstunnel/restrictions.yaml` |
| `README.md` | 本文档 | — |

```bash
# 部署前必须全局替换的 3 个占位值
#   tunnel.example.com  → 你的域名
#   my-secret-path      → 路径前缀暗号
#   Wstunnel-2026       → Basic 密码（改动后同步 restrictions.yaml 里的 base64，见 §6.1）
```

## 1. 架构总览

```
[客户端机器]                                  [wstunnel 服务器]                [目标服务]
 本地:2223  ──┐                          ┌── wss://0.0.0.0:55443 ──┐
 本地:10001 ──┤   wss://域名:55443        │  TLS证书 + 双鉴权        │
 本地:10000 ──┼─────────────────────────►│  restrictions.yaml 白名单├──────────► 目标 host:port
 本地:8101  ──┤   (WebSocket over TLS)   │  证书/配置热加载         │
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
| 路径前缀（暗号1） | `my-secret-path` | 客户端 `-P` / `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX`；**不设时默认前缀是 `v1`，会被 restrictions 直接拒** |
| Basic 账号（暗号2） | `wstunnel:Wstunnel-2026` | base64: `d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==`（已用 `printf … \| base64` 复核一致） |
| 证书文件 | `/opt/wstunnel/fullchain.pem` + `privkey.pem` | 自动热加载，续期无需重启 |
| 限制文件 | `/opt/wstunnel/restrictions.yaml` | 自动热加载，改完即生效 |
| mTLS 强化（可选） | `/opt/wstunnel/ca.pem` | 服务端 `--tls-client-ca-certs ca.pem` |

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

## 3. 服务端部署

### 3.1 文件清单

| 路径 | 来源文件 | 权限建议 |
|---|---|---|
| `/opt/wstunnel/fullchain.pem` | Let's Encrypt（含中间证书） | 644 |
| `/opt/wstunnel/privkey.pem` | 同上 | **600** |
| `/opt/wstunnel/restrictions.yaml` | 本目录 `restrictions.yaml` | 640 |
| `/usr/local/bin/wstunnel` | [GitHub Releases](https://github.com/erebe/wstunnel/releases) | 755 |
| `/etc/systemd/system/wstunnel.service` | 本目录 `wstunnel.service` | 644 |

### 3.2 部署命令

```bash
mkdir -p /opt/wstunnel
# 上传证书、私钥、restrictions.yaml 到 /opt/wstunnel/ 后：
chmod 600 /opt/wstunnel/privkey.pem
chmod 640 /opt/wstunnel/restrictions.yaml

systemd-analyze verify /etc/systemd/system/wstunnel.service   # 先做 unit 自检
systemctl daemon-reload
systemctl enable --now wstunnel.service   # enable 别忘：开机自启
journalctl -u wstunnel -f                 # 看到 listening on 0.0.0.0:55443 即成功

# 防火墙
firewall-cmd --permanent --add-port=55443/tcp && firewall-cmd --reload
# 或: ufw allow 55443/tcp
```

unit 里已带 `ProtectSystem=strict` 等加固项：`/opt`、`/etc` 会挂成**只读**，但读证书/读配置不受影响（热加载走 inotify），所以不需要 `ReadWritePaths`。若将来 wstunnel 要写文件，必须显式声明，且路径不存在会让服务起不来（用 `ReadWritePaths=!/path` 前缀 `!` 表示可缺省）。

### 3.3 restrictions.yaml 判定语义（已按 v11.1.0 源码核对）

- **白名单机制**：未命中任何规则 → **HTTP 400 Bad Request**（日志 `Rejecting connection with not allowed destination`）。旧文档写的 403 不准确。
- `match` 内是**逻辑与**：路径前缀、Authorization 头必须同时命中；`match` 不允许为空列表。
- `allow` 内是**逻辑或**：命中任一 `!Tunnel` 即放行；多条 restriction 之间按文件顺序取第一条命中的（所以每条的 `name` 建议写清用途，放行日志会打印它）。
- `port`、`protocol` **留空或不写 = 该维度完全不限制**（不是"禁止"）；`port` 支持范围 `"8080..8089"`，源码按字符串解析，建议统一加引号。
- **`host` 与 `cidr` 不会同时生效**：请求目标是域名时只看 `host` 正则；目标是字面 IP 时只看 `cidr`。⇒ 域名目标即使解析到 `127.0.0.1` 也能放行（残余风险见 §5.1）。
- 文件**保存即热加载**，调整端口/密码不需要重启服务。
- 只想按 `host:port` 粗粒度限制、不用配置文件时，v11 也支持 `--restrict-to "gw.pyproxy.com:2222"`（可重复），它与 `--restrict-config` 属于两套并行入口，本方案统一用 `--restrict-config`。

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
ExecStart=/bin/sh -c 'exec /usr/local/bin/wstunnel client   --tls-verify-certificate --http-headers-file "$CREDENTIALS_DIRECTORY/auth.txt"   -L tcp://0.0.0.0:2223:gw.pyproxy.com:2222 wss://tunnel.example.com:55443'
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
  --http-upgrade-credentials 'wstunnel:Wstunnel-2026' -P my-secret-path \
  -L tcp://0.0.0.0:2223:gw.pyproxy.com:2222 wss://<域名>:55443

# ② 不带任何密钥（模拟恶意扫描）→ 应被拒
wstunnel client -L tcp://3333:127.0.0.1:22 wss://<域名>:55443

# ③ 有密钥但目标端口不在白名单 → 应被拒
wstunnel client --http-upgrade-credentials 'wstunnel:Wstunnel-2026' -P my-secret-path \
  -L tcp://3333:127.0.0.1:3306 wss://<域名>:55443

# ④ 目标端口在白名单但主机不对（本次收紧后新增的用例）→ 应被拒
wstunnel client --tls-verify-certificate \
  --http-upgrade-credentials 'wstunnel:Wstunnel-2026' -P my-secret-path \
  -L tcp://3333:evil.example.com:2222 wss://<域名>:55443

# ⑤ 只看端口/TLS 是否通（注意：curl 无 JWT，必然被拒，返回 400 属正常）
curl -sk -o /dev/null -w '%{http_code}\n' https://<域名>:55443/my-secret-path
```

①通、②③④拒 = TLS + 双暗号 + `host:port` 白名单全部生效。判定顺序是先解 JWT 再查 restrictions，所以裸 `curl`（无 `Sec-WebSocket-Protocol`）拿不到"白名单已放行"的结论，白名单必须用真客户端测。

### 5.1 残余风险：域名解析不受 cidr 约束

`host` 命中的域名目标，其解析结果不受 `cidr` 限制（源码里域名分支只看 `host`）。若某白名单域名的 DNS 可控或发生 rebinding，隧道可能被指到 `127.0.0.1` / `169.254.169.254` 之类的内网地址。缓解：对可固定的目标改用 **IP + `cidr: x.x.x.x/32`** 写法，或在服务端 `/etc/hosts`、resolver 层锁定解析结果。

## 6. 日常运维

### 6.1 轮换密码（3 步，不断线）

```bash
echo -n 'wstunnel:新密码' | base64                      # ① 生成新 base64
sed -i 's/d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==/<新串>/' \
  /opt/wstunnel/restrictions.yaml                       # ② 更新服务端（热加载，注意本次收紧后有 1 处引用）
# ③ 更新客户端 unit 或 auth.txt 后: systemctl daemon-reload && systemctl restart wstunnel-client
```

### 6.2 增删隧道端口

`restrictions.yaml` 加/删一条 `!Tunnel`（记得同时定好它的 `host` 或 `cidr`）→ 保存即生效；再更新客户端 unit 的 `-L` 列表并 `systemctl daemon-reload && systemctl restart wstunnel-client`。

### 6.3 unit 与配置的快速自检

```bash
systemd-analyze verify /etc/systemd/system/wstunnel.service       # 只应抱怨二进制缺失
wstunnel --version                                                # 与文档基准 v11.1.0 对齐
systemctl show wstunnel -p NRestarts -p ExecStart                  # 看重启计数与生效命令行
journalctl -u wstunnel --since -10m | grep -E 'accepted due to|Rejecting'
python3 -c "import yaml,sys;yaml.safe_load(open('/opt/wstunnel/restrictions.yaml'))" 2>&1 | head -3
```

### 6.4 常见问题速查

| 现象 | 原因 | 处理 |
|---|---|---|
| 服务反复重启、日志显示读取失败 | 证书/私钥/限制文件缺失或写了一半 | 补齐文件后自动恢复（unit 用 `StartLimitIntervalSec=0` 无限重试）；想改成"失败即停并告警"见 unit 注释 |
| 客户端证书报错 | 忘加 `--tls-verify-certificate`，或证书链不完整 | 用 fullchain（含中间证书）并显式开启校验；客户端用内置根证书库校验 |
| 域名隧道不通、IP 隧道正常 | 服务器解析不了目标域名 | 服务端加 `--dns-resolver dns://223.5.5.5`（DoT 用 `dns+tls://8.8.8.8?sni=dns.google`） |
| 客户端起不来，address already in use | 本地端口冲突（重点查 10000） | 换本地端口或停占用服务 |
| 端口只能本机访问 | `-L` 缺省绑 `127.0.0.1` | BIND 前缀加 `0.0.0.0:`，见 §4.4 |
| 隧道频繁断开重连 | 中间设备回收空闲连接 | 调小 `--websocket-ping-frequency`（默认 30s，可设 15s） |
| 加了 `-P` 仍被拒 | 前缀不匹配，或一侧漏配（缺省是 `v1`） | 三处必须一致：客户端 `-P`、`restrictions.yaml` 的 `!PathPrefix`、（如启用）服务端 `-r` |
| 扫描器不停连 | 只拦到 HTTP 层，属正常 | 55443 非标端口 + 双暗号 + host 白名单已足够；要更强可上 mTLS |
| 服务启动即失败并提示挂载相关错误 | `ReadWritePaths` 指向不存在的目录 | 建目录或改用 `ReadWritePaths=!/path` |
| 上了 `wts://` 后 10s 超时 | QUIC 需要 UDP 端到端可达 | 服务端 `--enable-webtransport`（或 `wts://`）+ 防火墙/容器同时放行 UDP/55443；注意 `--http-proxy`、`--tls-sni-disable`、`--tls-ech-enable` 与 WebTransport 不兼容 |

### 6.5 安全升级路线

| 级别 | 手段 | 配置 |
|---|---|---|
| 当前 | TLS + 路径前缀 + Basic + `host:port` 白名单 | 本文档方案 |
| 更高 | mTLS 双向证书 | 服务端 `--tls-client-ca-certs ca.pem`，客户端 `--tls-certificate/--tls-private-key`（无证书者在握手期即被拒；注意 mTLS 下升级前缀默认取证书 CN，需与 `-P`/`!PathPrefix` 对齐） |

## 7. 本次审计结论（2026-11-28）

已核实的基准：上游 `erebe/wstunnel` 仓库 README、`restrictions.yaml` 示例、`src/restrictions/{types,mod}.rs`、`src/tunnel/server/{utils,server}.rs`、`src/tunnel/transport/jwt.rs`，以及 Releases API 返回的 `tag_name = v11.1.0`（= 本方案版本基准）。

| # | 级别 | 发现 | 处理 |
|---|---|---|---|
| 1 | 中 | 旧 `restrictions.yaml` 仅锁端口，`host: ^.*$` + `cidr 0/0` ⇒ 拿到双暗号即可把 6 个端口转去任意主机（SSRF 面） | 按映射表拆成 6 条 `!Tunnel`，域名走 `host` 正则、字面 IP 走 `/32` cidr；保留"宽松回退"注释块 |
| 2 | 中 | 文档称默认拒绝返回 403；源码 `bad_request()` 实为 **400** | 已更正（§3.3、§5） |
| 3 | 中 | 未说明 `port`/`protocol` 留空 = 不限制，误删即全放开 | 已在 §3.3 显式写明 |
| 4 | 中 | 未说明域名目标只看 `host`、`cidr` 不参与（rebinding 残余风险） | 已新增 §5.1 |
| 5 | 低 | 文档称客户端 unit `chmod 600` 可防泄密，实际 `ps` 仍能看到密码 | §4.1 已更正并指向 §4.2 |
| 6 | 低 | `-P` 缺省值 `v1`（旧文档未提），漏配会被 restrictions 拒 | 参数清单 + 速查表补充 |
| 7 | 低 | 两个 unit 无资源/安全约束，以 root 裸跑、无 fd 上限、重启限流缺失 | 加 `LimitNOFILE=65535`、`RestartSec=5`、`StartLimitIntervalSec=0`（自愈）与 `ProtectSystem=strict` 等加固集，并给出可选降权注释 |
| 8 | 低 | `--dns-resolver`、`-r`、`--websocket-ping-frequency` 等只在速查表出现，unit 中无可取消注释的入口 | 在两个 unit 内以注释形式给出，避免引入非必需的 223.5.5.5 依赖 |
| 9 | 信息 | v11 已支持 WebTransport（`wts://`）、`--restrict-to` 简化白名单、`--http-headers-file` 每请求重读 | 文档补记 |
| 10 | 已核对无误 | base64 值、`--tls-verify-certificate` 为无值开关、`--http-headers-file` 优先级、socks5 带 `login/password`、ping 默认 30s、`WSTUNNEL_*` 环境变量名、mTLS 参数名 | 保持原描述 |

**未在本机验证的项**（容器内无 `wstunnel` 二进制、无 systemd 运行实例）：真实握手与转发行为、`ProtectSystem=strict` 下服务端读证书的实际表现、限流策略。上线前请按 §5 全量跑一遍。已完成的本地验证：`systemd-analyze verify` 两个 unit 通过（仅提示 `/usr/local/bin/wstunnel` 缺失）；`restrictions.yaml` 经 PyYAML（含 `!Tag` 自定义标签）解析确认结构正确、6 条规则与映射表一一对应。

## 8. 附件（本目录）

| 文件 | 用途 |
|---|---|
| `restrictions.yaml` | 服务端限制/鉴权配置 → `/opt/wstunnel/restrictions.yaml` |
| `wstunnel.service` | 服务端 systemd unit → `/etc/systemd/system/` |
| `wstunnel-client.service` | 客户端 systemd unit → `/etc/systemd/system/` |

> 部署前记得全局替换：`tunnel.example.com`（你的域名）、`my-secret-path`（路径前缀暗号）、`Wstunnel-2026`（密码，换后同步 base64）。

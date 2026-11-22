# wstunnel 安全部署文档

> 版本基准：wstunnel v11.1.0（Rust 版）· 整理日期：2026-11-22
> 特点：自有域名 + SSL 证书（wss）+ 双重鉴权（路径前缀 + Basic）+ 目标端口白名单

---

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
- 反向隧道（`-R`）当前策略为**禁止**。

## 2. 参数清单

| 项目 | 值 | 备注 |
|---|---|---|
| 服务端口 | `55443/tcp` | 非标端口，需在防火墙放行 |
| 协议 | `wss://`（WebSocket over TLS） | 证书与端口无关，只对域名生效 |
| 路径前缀（暗号1） | `my-secret-path` | 客户端 `-P` 或环境变量 |
| Basic 账号（暗号2） | `wstunnel:Wstunnel-2026` | base64: `d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==` |
| 证书文件 | `/opt/wstunnel/fullchain.pem` + `privkey.pem` | 自动热加载，续期无需重启 |
| 限制文件 | `/opt/wstunnel/restrictions.yaml` | 自动热加载，改完即生效 |

### 隧道映射表（6 条）

| 客户端本地端口 | 目标地址:端口 | 目标端口在白名单 |
|---|---|---|
| 2223 | gw.pyproxy.com:2222 | ✅ |
| 10001 | hk.rp.linkup.onl:10000 | ✅ |
| 10000 | 43.134.70.211:9999 | ✅ |
| 8101 | proxy.momoproxy.com:8100 | ✅ |
| 5002 | us.rapidproxy.io:5001 | ✅ |
| 55689 | 45.149.172.51:55688 | ✅ |

> 白名单端口：`2222 / 5001 / 8100 / 9999 / 10000 / 55688`（与映射表一一对应）

## 3. 服务端部署

### 3.1 文件清单

| 路径 | 来源文件 | 权限建议 |
|---|---|---|
| `/opt/wstunnel/fullchain.pem` | 自签或 Let's Encrypt | 644 |
| `/opt/wstunnel/privkey.pem` | 同上 | **600** |
| `/opt/wstunnel/restrictions.yaml` | 附带的 `restrictions.yaml` | 640 |
| `/usr/local/bin/wstunnel` | [GitHub Releases](https://github.com/erebe/wstunnel/releases) | 755 |
| `/etc/systemd/system/wstunnel.service` | 附带的 `wstunnel.service` | 644 |

### 3.2 部署命令

```bash
mkdir -p /opt/wstunnel
# 上传证书、私钥、restrictions.yaml 到 /opt/wstunnel/ 后：
chmod 600 /opt/wstunnel/privkey.pem
chmod 640 /opt/wstunnel/restrictions.yaml

systemctl daemon-reload
systemctl enable --now wstunnel.service   # enable 别忘：开机自启
journalctl -u wstunnel -f                 # 看到 listening on 0.0.0.0:55443 即成功

# 防火墙
firewall-cmd --permanent --add-port=55443/tcp && firewall-cmd --reload
# 或: ufw allow 55443/tcp
```

### 3.3 restrictions.yaml 语义要点

- **白名单机制**：加载后一切未命中规则的请求默认拒绝（403）。
- `match` 内为**逻辑与**：路径前缀、Authorization 头必须同时命中。
- `allow` 内为**逻辑或**：任一规则放行即通过；`port` 支持范围写法如 `8080..8089`。
- 文件**保存即热加载**，调整端口/密码不需要重启服务。

## 4. 客户端部署

### 4.1 方式 A（推荐）：单文件 systemd unit

使用附带的 `wstunnel-client.service`：

```bash
# unit 里已含全部 6 条 -L 隧道；密码写在 ExecStart 中
chmod 600 /etc/systemd/system/wstunnel-client.service   # 防止非 root 读取
systemctl daemon-reload
systemctl enable --now wstunnel-client
journalctl -u wstunnel-client -f
ss -lntp | grep -E '2223|10000|10001|8101|5002|55689'   # 确认 6 个本地端口已监听
```

注意：**本机 10000 端口**会被占用（映射到 43.134.70.211:9999），部署前先确认无冲突。

### 4.2 方式 B：凭据落盘（多用户机器防 `ps` 泄密）

```bash
# /etc/wstunnel/auth.txt —— 每请求重读，热换密码
# 内容: Authorization: Basic d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==
chmod 600 /etc/wstunnel/auth.txt
```

unit 中把 `--http-upgrade-credentials ...` 换成 `--http-headers-file /etc/wstunnel/auth.txt`（二者勿同时使用，文件优先）。

进阶（Debian 12 / systemd 252+）：用 `LoadCredential=auth:/etc/wstunnel/auth.txt` + `${CREDENTIALS_DIRECTORY}/auth`，凭据文件会被复制进仅 root 可见的 tmpfs。

### 4.3 环境变量对照表（客户端可用）

| 参数 | 环境变量 | 备注 |
|---|---|---|
| `-P` 路径前缀 | `WSTUNNEL_HTTP_UPGRADE_PATH_PREFIX` | unit 中用 `Environment=` 写入 |
| `-p` http 代理 | `HTTP_PROXY` | 客户端在代理后面出网时用 |
| 代理账号/密码 | `WSTUNNEL_HTTP_PROXY_LOGIN` / `..._PASSWORD` | |
| 日志级别 | `RUST_LOG` | INFO/DEBUG/TRACE |
| `--http-upgrade-credentials` | ❌ 无 | 只能写命令行或 auth.txt |
| `-L` / `-R` / `--tls-verify-certificate` | ❌ 无 | 只能写命令行 |

### 4.4 本地监听地址（开放到局域网/所有网卡）

客户端 `-L` 缺省只绑 **127.0.0.1**（仅本机可达）。监听所有网卡在 URL 中显式加 BIND 前缀（语法 `{tcp,udp}://[BIND:]PORT:HOST:PORT`）：

```
-L tcp://0.0.0.0:2223:gw.pyproxy.com:2222         # IPv4 全部网卡
-L tcp://[::]:2223:gw.pyproxy.com:2222            # IPv6 全部网卡
-L tcp://192.168.1.10:2223:gw.pyproxy.com:2222    # 只绑指定网卡（推荐）
```

**安全提醒**：TCP/UDP 隧道这些本地端口**本身没有任何鉴权**，开到 0.0.0.0 后能连到端口的任何机器都能借隧道访问目标服务。建议：

- 防火墙按来源网段白名单：`firewall-cmd --add-rich-rule="rule family=ipv4 source address=192.168.0.0/24 port port=2223 protocol=tcp accept"`（注意先 remove 掉宽泛放行规则）
- 或只绑内网网卡 IP（如上第三行写法）
- 动态端口的场景可改用 `socks5://0.0.0.0:1212?login=xx&password=xx`（带账号密码）
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
```

①通、②③拒 = 三重防线全部生效。

## 6. 日常运维

### 6.1 轮换密码（3 步，不断线）

```bash
echo -n 'wstunnel:新密码' | base64                      # ① 生成新 base64
sed -i 's/d3N0dW5uZWw6V3N0dW5uZWwtMjAyNg==/<新串>/' \
  /opt/wstunnel/restrictions.yaml                       # ② 更新服务端（热加载）
# ③ 更新客户端 unit 或 auth.txt 后: systemctl daemon-reload && systemctl restart wstunnel-client
```

### 6.2 增删隧道端口

改 `restrictions.yaml` 的 `port:` 列表 → 保存即生效；同时更新客户端 unit 的 `-L` 列表并重启客户端。

### 6.3 常见问题速查

| 现象 | 原因 | 处理 |
|---|---|---|
| 服务反复 ABRT 重启、日志显示读取失败 | 证书/私钥/限制文件缺失或写了一半 | 补齐文件后自动恢复（`systemctl show wstunnel -p NRestarts` 观察计数是否停涨） |
| 客户端证书报错 | 忘记加 `--tls-verify-certificate` 或证书链不完整 | 用 fullchain（含中间证书），并显式开启校验 |
| 域名隧道不通、IP 隧道正常 | 服务器解析不了目标域名 | 服务端加 `--dns-resolver dns://223.5.5.5` |
| 客户端起不来，address already in use | 本地端口冲突（重点查 10000） | 换本地端口或停占用服务 |
| 端口只能本机访问 | `-L` 缺省绑 127.0.0.1 | BIND 前缀加 `0.0.0.0:`，见 4.4 |
| 隧道频繁断开重连 | 中间设备回收空闲连接 | 调小 `--websocket-ping-frequency`（默认 30s，可设 15s） |
| 恶意连接一直试 | 只拦到 HTTP 层，属正常 | 55443 非标端口 + 双暗号已足够；要更强可上 mTLS |

### 6.4 安全升级路线（可选）

| 级别 | 手段 | 配置 |
|---|---|---|
| 当前 | TLS + 路径前缀 + Basic + 端口白名单 | 本文档方案 |
| 更高 | mTLS 双向证书 | 服务端 `--tls-client-ca-certs ca.pem`，客户端 `--tls-certificate/--tls-private-key`（无证书者在握手期即被拒） |

## 7. 附件（本目录）

| 文件 | 用途 |
|---|---|
| `restrictions.yaml` | 服务端限制/鉴权配置 → `/opt/wstunnel/restrictions.yaml` |
| `wstunnel.service` | 服务端 systemd unit → `/etc/systemd/system/` |
| `wstunnel-client.service` | 客户端 systemd unit → `/etc/systemd/system/` |

> 部署前记得全局替换：`tunnel.example.com`（你的域名）、`my-secret-path`（路径前缀暗号）、`Wstunnel-2026`（密码，换后同步 base64）。
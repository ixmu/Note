# dnsmgr SSL 证书自动下载脚本(单文件 / 模块化 / 先校验后触发 / 按需下载 v2.9)

一个自包含的 shell 脚本: 从 **聚合DNS管理系统(dnsmgr)** 开放接口自动下载 SSL 证书,**先校验再写盘**,平铺保存为
`域名.crt.pem` / `域名.key.pem`,下载后的附加动作(部署、重载、告警、通知…)全部拆成**可插拔模块**,
并预置一个 **custom_cmd 模块**用于「证书下载校验通过后执行自定义命令」。需要多行逻辑时,脚本里还专门划了一块
**「自定义模块区」**(搜索标记 `BEGIN USER CODE`): 里面固定只有**一个**名为 `user` 的自定义模块,它的两个钩子
(`post_download` / `final`)**都只在证书下载完成并通过校验之后才执行**,直接往函数体里填代码就生效,
**不用改 `MODULES`,也不加载任何外部文件**。
配置直接写在脚本顶部的「配置区」,**没有外部 .conf 文件**,复制一个文件即可部署,适合放进 crontab 长期运行。
支持**按需下载**: 设了 `RENEW_DAYS`(或命令行 `-r`)之后,脚本只看**本地已保存的那张证书**还能用多久,剩余天数不低于阈值
就直接跳过该订单(不请求接口、不校验、不触发任何模块钩子);本地没有这张证书时必定下载。临时想强制换证用 `-f`。

- 接口文档: <https://www.showdoc.com.cn/dnsmgr/11558692653755647>
- 服务地址: <https://pki.ixmu.net>
- 文件: `dnsmgr-cert.sh`(单文件,约 1173 行,无外部脚本/配置)

## 一、接口要点(脚本已按文档实现)

| 项目 | 内容 |
| --- | --- |
| 请求地址 | `POST /api/cert/order` |
| 业务参数 | `id` —— SSL 证书订单 ID(int) |
| 公共参数 | `uid`(int)、`timestamp`(10 位秒时间戳)、`sign`(签名) |
| 签名规则 | `sign = md5(uid + timestamp + key)`,直接拼接后取 MD5 并转小写 |
| 数据格式 | 请求 `application/x-www-form-urlencoded`,返回 JSON(UTF-8) |
| 返回字段 | `code`(0 成功)、`msg`、`data.id`、`data.crt`(PEM 证书)、`data.key`(PEM 私钥)、`data.issuetime`、`data.expiretime`、`data.domains[]`(另有 `data.pfx`,仅 Windows/IIS 使用,本脚本不解码保存) |

> 调用前需在 dnsmgr 后台「用户管理」中打开 API 接口并查看 API 接口密钥(key)。

## 二、快速开始

```bash
# 1. 上传并赋权(Windows 上编辑过的话先执行 dos2unix dnsmgr-cert.sh)
sudo cp dnsmgr-cert.sh /usr/local/bin/dnsmgr-cert.sh
sudo chmod 755 /usr/local/bin/dnsmgr-cert.sh

# 2. 只改顶部「配置区」: API_UID / API_KEY / CERT_IDS / OUT_DIR
sudo vi /usr/local/bin/dnsmgr-cert.sh

# 3. 自检(打印配置摘要 + 签名样例,并试下载第一个订单)
sudo /usr/local/bin/dnsmgr-cert.sh check

# 4. 正式下载
sudo /usr/local/bin/dnsmgr-cert.sh

# 5. 每天跑一次又不想天天换证: 本地证书剩余 >= 15 天时直接跳过(不请求接口)
sudo /usr/local/bin/dnsmgr-cert.sh -r 15
```

## 三、配置区(全部在脚本顶部,可用同名环境变量覆盖)

配置统一写成 `VAR="${VAR:-默认值}"`: **平时改冒号后的默认值即可**;需要临时换参数时,同名环境变量优先,
便于同一份脚本管多个账号 / 多台机器(也方便 CI 注入密钥)。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `API_BASE` | `https://pki.ixmu.net` | 接口地址,结尾不带 `/` |
| `API_UID` | `1` | 用户 ID(后台「用户管理」查看),必须纯数字 |
| `API_KEY` | 占位中文 | **必填**,API 接口密钥;仍是占位值时脚本直接报错 |
| `CERT_IDS` | `27` | SSL 证书订单 ID,多个用英文逗号分隔 |
| `OUT_DIR` | `/etc/ssl/dnsmgr` | 证书保存目录,所有文件平铺于此(cron 里请用绝对路径) |
| `WARN_DAYS` | `15` | 剩余有效期不足该天数时输出 WARN(必须数字) |
| `RENEW_DAYS` | `0` | **按需下载阈值(必须数字)**: 本地这张证书剩余有效期**小于**该天数才下载并校验;`0` = 不判断,每次都下载(与 v2.8 行为一致) |
| `FORCE_DOWNLOAD` | `0` | 1=忽略 `RENEW_DAYS` 本次强制下载(`check` 子命令内部自动按 1 处理) |
| `HTTP_TIMEOUT` | `30` | 单次请求超时秒数(必须数字) |
| `HTTP_RETRIES` | `3` | curl 重试次数(必须数字) |
| `CURL_INSECURE` | `0` | 1=跳过 HTTPS 校验(仅自签测试环境) |
| `LOG_FILE` | `/var/log/dnsmgr-cert.log` | 追加写入的日志;留空则只输出到 stdout |
| `MODULES` | `custom_cmd reload` | **启用的内置模块列表(空格分隔,按书写顺序执行)** |
| `USER_MODULE` | `1` | 1=执行脚本「自定义模块区」里的 `user` 模块(**仅在证书下载完成并通过校验后执行**);0=关闭(照常下载、校验、保存,只跳过你写的代码) |
| `CUSTOM_CMD` | 空 | 模块 `custom_cmd`: 要执行的自定义命令 |
| `CUSTOM_CMD_ON_CHANGE_ONLY` | `1` | 1=仅证书有更新时执行;0=每次下载后都执行 |
| `CUSTOM_CMD_SHELL` | `bash` | 执行 `CUSTOM_CMD` / `RELOAD_CMD` / `NOTIFY_CMD` 的解释器 |
| `RELOAD_CMD` | 空 | 模块 `reload`: 本轮有更新时执行一次的重载命令 |
| `NOTIFY_CMD` | 空 | 模块 `notify`: 临期告警命令(告警文本走 stdin) |

> 命令类配置(`CUSTOM_CMD`/`RELOAD_CMD`/`NOTIFY_CMD`)建议用**单引号直接赋值**,命令里的 `$CERT_FILE`
> 等变量由脚本在执行时才展开,可读性最好且不用多层转义;配置区里的示例行都写在「兜底行」之前,
> 取消注释即生效,不取消则取兜底行的空默认值。也可用 `--cmd` / `--reload` / `--notify` 临时传入。
> 兼容旧写法: 设置了 `DEPLOY_CMD` 而 `CUSTOM_CMD` 为空时自动视为 `CUSTOM_CMD`;旧参数 `-n` 仍可用(已无实际作用)。

## 四、保存结构、按需下载与写盘前校验(平铺,多张证书互不覆盖)

```
/etc/ssl/dnsmgr/
├── ixnic.net.crt.pem           # 证书(含证书链),权限 644
├── ixnic.net.key.pem           # 私钥,权限 600
├── ixnic.net.info.txt          # order_id / domains / issuetime / expiretime / 更新时间
├── mail.ixnic.net.crt.pem      # 另一个订单的证书,同目录共存
├── mail.ixnic.net.key.pem
├── wild.ixnic.net.crt.pem      # 泛域名订单 *.ixnic.net(泛域名用 wild. 前缀,不会覆盖主域名文件)
├── wild.ixnic.net.key.pem
└── *.bak                       # 覆盖前的上一版本自动备份
```

- 文件名用证书**首个域名**(接口 `domains` 数组第一项,取不到则用证书 subject 的 CN;
  泛域名 `*.example.com` 取 `wild.example.com`;都取不到时退回 `cert-<订单ID>`)。
- 内容**无变化不覆盖文件**(先写临时文件再 `cmp` 比对),因此不会误触发自定义命令/服务重载。
- `.bak` 与 `.info.txt` 均以同一域名为前缀,互不冲突。

### 按需下载(只看本地证书剩余有效期:`RENEW_DAYS` / `-r` / `-f`)

设了 `RENEW_DAYS=N`(或命令行 `-r N`)之后,每个订单在**请求接口之前**先看**本地这张证书**还能用多久:

| 本地证书情况 | 本次行为 |
| --- | --- |
| 剩余天数 `>= N` | **跳过该订单**: 不请求接口、不校验、不覆盖文件、不触发任何下载后的模块钩子(`post_download` / `on_change` / `final` 都不会跑);日志 `订单 <ID> 跳过下载: 本地证书 <域名> 剩余 <X> 天(>= 阈值 <N> 天)`,若剩余同时不足 `WARN_DAYS` 再补一条 WARN |
| 剩余天数 `< N`(含已过期) | 照常下载 → 校验 → 写盘 → 触发模块钩子 |
| 本地没有这张证书(首次运行 / 换过 `OUT_DIR` / `.crt.pem` 被手工删过) | **必定照常下载**,日志写明「本地没有已保存的证书记录」或「本地证书文件不存在」,所以上线第一次不会因跳过而漏证 |
| 读不出本地证书的到期时间(证书损坏且 `expiretime` 也异常) | WARN 后照常下载 —— 宁多下一次,不误跳过 |

- 判定依据只有本地文件: 先用 `openssl x509 -enddate` 读 `域名.crt.pem`,读不到再退回同订单 `.info.txt` 里的 `expiretime`。
- `RENEW_DAYS=0`(默认)= 不做按需判断,**每次都下载并校验,行为与 v2.8 完全一致**。
- 临时强制换证: `dnsmgr-cert.sh -f`(=`--force`);`check` 子命令始终会真实下载并校验一次,自检不受阈值影响。
- 收尾会统计: `按需下载: 本轮跳过 <N> 个订单(本地证书剩余天数还够用),需要强制下载请用 -f`;跳过时本轮没有证书通过校验,`final` 阶段自然跳过。
- 每天跑一次的 cron 建议设 15~30 天: 既能在续签后第一时间取回新证书,又不会天天刷接口和文件。

### 写盘前校验(校验通过才覆盖文件,才触发下载后的模块)

每张证书从接口拿到手后,**先校验,再决定要不要覆盖现有文件**:

| # | 校验项 | 依赖 | 不通过时 |
| --- | --- | --- | --- |
| 1 | PEM 结构: `data.crt` 含 `-----BEGIN CERTIFICATE-----`,`data.key` 含 `-----BEGIN ... PRIVATE KEY-----` | 无(永远执行) | 本订单判失败,不覆盖 |
| 2 | X.509 能否解析(`openssl x509 -noout`) | `openssl` | 同上 |
| 3 | 是否已过期(`openssl x509 -checkend 0`) | `openssl` | 同上 |
| 4 | 私钥与证书是否配成一对(两侧公钥的 SHA-256 指纹比对) | `openssl` | 同上;私钥类型取不出公钥时只 WARN 并跳过该项 |

- 校验失败的完整行为: 打印 `证书校验失败: <原因>` 与 `订单 <ID> 证书校验未通过,本次不覆盖现有证书文件`;
  现有 `.crt.pem` / `.key.pem` / `.bak` **一律保持原样**,`custom_cmd`、`on_change`、`user` 模块等下载后的动作
  **全部不执行**,该订单退出码为 1(其余订单继续处理)。
- 只提示不算失败: 新证书的 `notAfter` 早于现存文件中的证书时输出 WARN,防止接口回传旧证书把新证书覆盖回去。
- 未安装 `openssl` 时降级: 只做第 1 项 PEM 结构检查(WARN 说明其余三项已跳过),照样保存,不阻塞续期。

## 五、模块化机制(核心设计)

一个「模块」= 一组按约定命名的函数 **`module_<模块名>_<阶段>()`**;模块名可以含下划线(如 `custom_cmd`)。
**内置模块**(custom_cmd / reload / notify)启不启用由配置区 `MODULES` 决定,列表顺序即执行顺序;
**自定义模块只有一个,固定叫 `user`**,写在本脚本的「自定义模块区」里,默认始终执行(排在每个阶段最后),
可用配置项 `USER_MODULE=0` 整体关闭。未启用的模块函数即使定义存在也不会被调用。
**`post_download` / `on_change` / `final` 一律在证书下载完成并通过校验之后才触发**,模块里可以放心部署文件、
重载服务;这也正是 `user` 模块只准备了两个「下载后」钩子的原因(`init` / `pre_download` 发生在校验之前)。

| 阶段 | 触发时机 | 典型用途 |
| --- | --- | --- |
| `init` | 脚本启动、解析完模块列表后,每个模块一次 | 校验本模块所需参数、准备环境 |
| `pre_download` | 每个订单请求接口**前** | 注入参数、预处理;返回非 0 可中止该订单 |
| `post_download` | 该订单证书**下载完成、校验通过并保存后**(不论内容是否有变化) | 部署、分发、执行自定义命令 |
| `on_change` | 校验通过且证书文件**实际发生更新**后 | 只在换证时干活(推送、备份、审计) |
| `final` | 全部订单处理结束后一次(**本轮至少有一张证书校验通过并保存**) | 统一重载服务、汇总通知、清理临时文件 |

> 校验不通过(不是 PEM / 无法解析 / 已过期 / 私钥不匹配)的订单直接判为失败: 既不覆盖文件,也不执行上述三个
> 阶段的钩子;若本轮所有订单都没通过校验,`final` 同样不执行,日志提示「本轮没有下载完成并通过校验的证书,
> 跳过 final 阶段」。

模块可读取的上下文变量(脚本在每次调用钩子前 `export`):

| 变量 | 含义 |
| --- | --- |
| `CERT_ID` | 本次处理的 SSL 证书订单 ID |
| `CERT_DOMAIN` | 证书首个域名(已做安全字符过滤,也用作文件名前缀) |
| `CERT_DIR` | 保存目录(即 `OUT_DIR`) |
| `CERT_FILE` / `KEY_FILE` | `域名.crt.pem` / `域名.key.pem` 绝对路径 |
| `CERT_ISSUE` / `CERT_EXPIRE` | 接口返回的签发 / 到期时间 |
| `CERT_CHANGED` | 1=本次证书内容有更新,0=无变化 |
| `CERT_VERIFIED` | 1=本张证书已下载完成并通过写盘前校验(见「四」);下载后各阶段的钩子里恒为 1,`CUSTOM_CMD` 等命令串里也可直接引用 |
| `MODULE_PHASE` | 当前阶段名 |

### 内置模块

**1) `custom_cmd`(预置,阶段 `post_download`)—— 证书下载、校验通过并保存之后执行自定义命令**

```bash
MODULES="custom_cmd reload"
CUSTOM_CMD='cp -f "$CERT_FILE" "$KEY_FILE" "/etc/nginx/ssl/$CERT_DOMAIN/"'
CUSTOM_CMD_ON_CHANGE_ONLY=1     # 1=仅证书有更新时执行(默认); 0=每次下载后都执行
CUSTOM_CMD_SHELL=bash
```

```bash
# HAProxy: cert+key 合并成一个 pem
CUSTOM_CMD='cat "$CERT_FILE" "$KEY_FILE" > "/etc/haproxy/certs/$CERT_DOMAIN.pem" && chmod 600 "/etc/haproxy/certs/$CERT_DOMAIN.pem"'
# 宝塔面板
CUSTOM_CMD='cp -f "$CERT_FILE" "$KEY_FILE" "/www/server/panel/vhost/cert/$CERT_DOMAIN/"'
# 分发到其它机器
CUSTOM_CMD='scp -q "$CERT_FILE" "$KEY_FILE" root@10.0.0.8:/etc/nginx/ssl/'
# 记录事件 / 调用面板 API
CUSTOM_CMD='echo "$(date "+%F %T") 证书更新: $CERT_DOMAIN" >> /var/log/cert-event.log'
```

**2) `reload`(内置,阶段 `final`)—— 本轮任意证书有更新时,统一执行一次重载命令**

```bash
RELOAD_CMD='nginx -t && systemctl reload nginx'
```

与 `custom_cmd` 的区别: `reload` 一轮只跑一次(用临时标记文件判断「本轮是否有更新」),多域名场景更高效;
`custom_cmd` 是每个订单各执行一次。

**3) `notify`(内置,阶段 `post_download`)—— 剩余有效期不足 `WARN_DAYS` 天时告警(默认未启用)**

```bash
MODULES="custom_cmd reload notify"
NOTIFY_CMD='mail -s "dnsmgr证书到期提醒" admin@example.com'          # 告警文本从标准输入读入
# NOTIFY_CMD='curl -s -X POST --data-binary @- https://push.example.com/send?token=xxx'
```

`./dnsmgr-cert.sh modules` 可随时查看模块清单、支持的阶段以及是否已启用。

### 加自己的代码(脚本里的「自定义模块区」= 唯一的自定义模块 `user`)

搜索标记 `BEGIN USER CODE` 就能定位这块区域(位于内置模块之后、基础工具之前)。区外归脚本,区内完全归你。
区里已写好**两个钩子**,它们**都只在证书下载完成并通过校验之后**才被调用,填代码即可:

```bash
#---------- 自定义代码从这里开始 ----------

# 钩子1 每张证书下载、校验通过并保存之后(每个订单各一次)
module_user_post_download() {
    [ "$CERT_CHANGED" = "1" ] || return 0        # 只在证书真的换过时执行
    for h in 10.0.0.8 10.0.0.9; do
        scp -q "$CERT_FILE" "$KEY_FILE" "root@$h:/etc/nginx/ssl/" || return 1
    done
}

# 钩子2 全部订单处理结束之后(一轮一次;本轮至少有一张证书校验通过才会到这里)
module_user_final() {
    have_changes || return 0                     # 本轮没有任何证书更新就直接跳过
    systemctl reload nginx
}

#----------- 自定义代码到这里结束 ----------
```

- **校验通过是前提**: 接口返回的证书已过期 / 无法解析 / 与私钥不匹配时,两个钩子都不会被调用,现有证书也不会被覆盖。
- 区内可直接调用脚本提供的判定函数: `have_verified`(本轮有证书校验通过并保存)、`have_changes`(本轮有证书文件被更新)。
- **不需要改 `MODULES`**: `user` 模块默认始终执行,并且固定排在每个阶段的最后(custom_cmd、reload 之后)。
- 不想让它跑(比如临时只更新文件): 配置区把 `USER_MODULE` 设为 `0`,或环境变量 `USER_MODULE=0` 传入(照常下载校验保存,只跳过你的代码)。
- 逻辑要复用就在同一块区域里再写普通函数给钩子调用,**不必再开第二个模块**。
- 想要更早的动作可在区内自加 `module_user_init` / `module_user_pre_download`,但它们发生在**下载与校验之前**,
  只适合参数检查、准备工作,与「下载完成并校验通过后」的语义相反。
- 区内直接书写普通语句时,它们在启动阶段(配置与命令行参数解析完、下载开始前)执行一次。
- **没有 `MODULE_DIR`,也不 source 外部文件**,部署与迁移永远只拷一个脚本。
- `./dnsmgr-cert.sh modules` 里 `user` 那一组行会显示「[已启用] 自定义模块 校验通过后执行(见本脚本自定义模块区)」。

> 钩子返回非 0: `init` 阶段只提示;`pre_download` 中止当前订单;`post_download` / `on_change` / `final`
> 记录 ERROR 并让整体退出码非 0,便于 cron 邮件/监控发现(`user` 的两个钩子属于后一类)。

## 六、子命令与选项

| 子命令 | 说明 |
| --- | --- |
| `download`(默认) | 下载 `CERT_IDS` / `-i` 指定的全部证书,每张先校验再写盘,并按 `MODULES` 执行各阶段钩子;设了 `RENEW_DAYS` 时先做按需判定,本地证书够用则整个订单跳过 |
| `check` | 检查依赖与配置(打印配置摘要、签名样例、校验深度、下载策略),并试下载校验第一个订单(**始终强制下载一次**) |
| `modules` | 列出内置模块与自定义模块 `user`、支持的阶段、执行时机与启用状态 |
| `list` | 尝试 `POST /api/cert/list` 打印订单列表(文档未收录该接口,失败属正常) |

| 选项 | 说明 |
| --- | --- |
| `-o, --out DIR` | 覆盖证书保存目录 |
| `-i, --cert-id ID` | 追加证书订单 ID(与配置区 `CERT_IDS` 合并去重),可重复 |
| `-m, --modules LIST` | 覆盖启用的**内置**模块列表,如 `-m 'custom_cmd'`;`-m ''` = 不跑内置模块(自定义模块 `user` 仍会执行) |
| `--cmd CMD` | 覆盖 `CUSTOM_CMD` |
| `--reload CMD` | 覆盖 `RELOAD_CMD` |
| `--notify CMD` | 覆盖 `NOTIFY_CMD` |
| `--log FILE` | 覆盖 `LOG_FILE` |
| `-r, --renew-days N` | 按需下载阈值: 本地证书剩余有效期不足 N 天才下载并校验(覆盖配置区 `RENEW_DAYS`),也支持 `--renew-days=N` |
| `-f, --force` | 忽略按需下载阈值,本次强制下载并校验 |
| `-n, --no-subdir` | 兼容保留(已无作用,证书一律平铺) |
| `-q, --quiet` | 只输出 WARN/ERROR |
| `-h, --help` / `-v, --version` | 帮助 / 版本 |

## 七、定时任务

```cron
# 每天 03:30 下载证书(脚本自带锁文件,不会并发重复执行)
30 3 * * * /usr/local/bin/dnsmgr-cert.sh

# 推荐: 每天 03:30 检查一次,但本地证书剩余还不低于 15 天就不请求接口(省调用,也不反复刷文件)
30 3 * * * /usr/local/bin/dnsmgr-cert.sh -r 15

# 只想让 cron 邮件收到告警: 过滤 WARN/ERROR
30 3 * * * /usr/local/bin/dnsmgr-cert.sh 2>&1 | grep -E 'WARN|ERROR' | mail -s 'dnsmgr 证书任务' admin@example.com

# 不改脚本、纯命令行的一次性用法
API_UID=1 API_KEY=xxxx /usr/local/bin/dnsmgr-cert.sh -i 27 -m custom_cmd \
    --cmd 'systemctl reload nginx'
```

## 八、nginx 站点配置示例

```nginx
server {
    listen 443 ssl http2;
    server_name ixnic.net;
    ssl_certificate     /etc/ssl/dnsmgr/ixnic.net.crt.pem;
    ssl_certificate_key /etc/ssl/dnsmgr/ixnic.net.key.pem;
}
```

## 九、依赖与说明

- 必需依赖: `bash`、`curl`、`awk`、`md5sum`(coreutils,缺失时自动改用 `md5` 或 `openssl`)。**不需要 jq。**
- 可选依赖: `openssl` —— **它决定证书校验的深度**: 装了才会做 X.509 解析、有效期、私钥匹配三项校验(见「四、写盘前校验」),并能用证书 `notAfter` 精确计算剩余天数。没装也能用: 校验降级为只做 PEM 结构检查(WARN 提示),剩余天数改用接口返回的 `expiretime` 计算。
- JSON 解析为脚本内置 awk 实现(`\"`、`\n`、`\\` 等转义自动还原),不依赖外部 JSON 工具。
- 脚本用 `set -u; set -o pipefail`(不用 `set -e`): 单个订单失败只影响该订单,便于批量续期;整体退出码非 0。
- 不保存 PFX:Linux 下 nginx / haproxy / apache / caddy 直接使用 PEM 证书 + 私钥即可,接口返回的 `data.pfx` 字段本脚本忽略,因此也不再依赖 `base64` 解码。
  偶尔要给别人一份 PFX(Windows / IIS)时,用预设的 custom_cmd 模块现场生成即可: `CUSTOM_CMD='openssl pkcs12 -export -inkey "$KEY_FILE" -in "$CERT_FILE" -out "/tmp/$CERT_DOMAIN.pfx" -passout pass:'`
- 锁文件 `${TMPDIR:-/tmp}/.dnsmgr-cert.lock`(记录 PID,进程不存在时视为过期自动清理)。
- 剩余天数优先用 `openssl` 读取证书 `notAfter`,没有 `openssl` 时改用接口返回的 `expiretime` 计算(精度到「天」)。**按需下载(`RENEW_DAYS`)的判断用的就是同一个函数**,因此本地证书读不出日期时会自动退回 `.info.txt` 里的 `expiretime`,两者都不行才放弃判断并照常下载。

## 十、退出码与常见问题

| 码 | 含义 |
| --- | --- |
| 0 | 全部订单处理成功(证书可能无变化,也可能只执行了模块) |
| 1 | 依赖/配置缺失、接口或写盘失败、**证书写盘前校验未通过(保留原证书不覆盖)**、模块或重载/自定义命令失败、部分订单失败 |

| 现象 | 处理 |
| --- | --- |
| `接口返回失败 code=...` | 核对后台是否开启 API 接口、`API_UID`/`API_KEY` 是否正确、证书订单 `id` 是否存在 |
| `证书校验失败: ...` | 接口返回的证书不完整、已过期或私钥与证书不匹配。脚本会**保留原有证书文件不覆盖**,也不执行下载后的模块;多见于订单尚未续签或该订单的证书与私钥不配套,续签该订单后再跑 |
| 证书下载了但模块没执行 | 校验通过是前提: 先看日志里有没有 `证书校验失败` / `跳过 final 阶段`,再核对 `MODULES` 与 `CUSTOM_CMD` 是否为空 |
| `API_KEY 还是默认占位值` | 编辑配置区填入真实密钥,或用环境变量 `API_KEY=xxx` 传入 |
| `已有实例正在运行` | 上一次任务未结束;确认无残留进程后删除锁文件 |
| 自定义命令没执行 | 确认 `MODULES` 含 `custom_cmd`、`CUSTOM_CMD` 非空;若证书无更新且 `CUSTOM_CMD_ON_CHANGE_ONLY=1` 则本次会跳过(可临时设为 0) |
| 每天跑一次,怕频繁请求接口 / 反复刷文件 | 设 `RENEW_DAYS=15` 或 cron 里加 `-r 15`: 本地证书剩余天数够用就直接跳过,连接口都不请求 |
| 明明设了 `-r` 却还是每次都下载 | 只有**本地已保存的这张证书**参与判断: 首次运行、`OUT_DIR` 指错、`.crt.pem` 被手工删过、`.info.txt` 丢失都会导致照常下载,日志里会写明原因 |
| 续签后想立刻拿到新证书 | `dnsmgr-cert.sh -f` 强制下载并校验一次(等价于临时把阈值设为 0) |
| 只想下载不做其它动作 | `USER_MODULE=0 ./dnsmgr-cert.sh -m ''`(内置模块与自定义模块都不跑) |
| 泛域名证书文件名 | `*.ixnic.net` 保存为 `wild.ixnic.net.crt.pem`,与同目录下主域名订单的 `ixnic.net.crt.pem` 互不覆盖(`*` 不是 Windows 合法文件名字符,故用 `wild.` 前缀代替) |
| Windows 编辑后无法运行 | `dos2unix dnsmgr-cert.sh` 或 `sed -i 's/\r$//' dnsmgr-cert.sh` |

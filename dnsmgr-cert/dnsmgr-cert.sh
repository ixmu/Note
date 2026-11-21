#!/usr/bin/env bash
#=====================================================================
# dnsmgr-cert.sh -- dnsmgr(聚合DNS管理系统) SSL 证书自动下载脚本(单文件 / 模块化版)
#
#   接口文档 : https://www.showdoc.com.cn/dnsmgr/11558692653755647
#   服务地址 : https://ssl.explame.com  (示例站点)
#   请求方式 : POST /api/cert/order    业务参数: id=SSL证书订单ID
#   公共参数 : uid / timestamp(10位秒时间戳) / sign
#   签名规则 : sign = md5(uid + timestamp + key)  拼接后MD5并转小写
#   返回字段 : data.crt(PEM证书) data.key(PEM私钥)   data.pfx 仅 Windows/IIS 使用,本脚本不保存
#              data.issuetime data.expiretime data.domains[]
#
# 脚本功能:
#   1. 自动生成签名并调用接口下载证书,配置写在本文件顶部"配置区",无外部配置文件
#   2. 平铺保存到 OUT_DIR: 域名.crt.pem / 域名.key.pem,内容有变化才覆盖(保留 .bak)
#      泛域名订单 *.example.com 保存为 wild.example.com.crt.pem,不会与主域名订单互相覆盖
#   3. 每张证书先校验(PEM 结构 / X.509 能否解析 / 是否已过期 / 私钥与证书是否匹配),
#      校验通过才覆盖文件并触发下载后的动作; 校验失败则本订单记为失败,现有证书原样保留
#   4. 按需下载(可选): 设了 RENEW_DAYS 之后,本地这张证书剩余有效期还够用就不下载新证书,
#      不请求接口也不校验(只判断 OUT_DIR 下该订单已保存的证书文件; 本地没有则一定下载),
#      剩余天数小于阈值时才下载并校验; 命令行 -r 指定阈值, -f 强制下载
#   5. 下载后的附加操作全部模块化(MODULES): custom_cmd(证书下载校验通过后执行自定义命令)、
#      reload(本轮有更新时统一重载)、notify(临期告警); 需要多行动作就自己再写一个
#      module_<模块名>_<阶段>() 函数并加进 MODULES,同样只有这一个脚本
#   6. 剩余有效期不足 WARN_DAYS 天输出 WARN 日志,便于 cron 邮件或监控告警
#   7. 只依赖 bash + curl + awk + md5sum(缺失时改用 openssl),无需 jq
#
# 模块机制(详见 README):
#   内置模块 = 一组约定命名的函数 module_<模块名>_<阶段>() ,阶段可选:
#     init          脚本启动时,做模块自身参数检查/准备
#     pre_download  每个订单请求接口前
#     post_download 证书下载完成并通过校验、保存之后(内容有变化 CERT_CHANGED=1)
#     on_change     证书文件实际发生更新之后(同样在校验通过之后)
#     final         全部订单处理结束后一次(本轮至少有一张证书校验通过并保存时才执行)
#   启用哪些模块由配置区 MODULES 决定: custom_cmd(下载后执行自定义命令)、
#   reload(有更新时重载服务)、notify(临期告警)。三者的下载后钩子都只在
#   "证书下载完成并通过校验"之后才会被调用,所以可以放心部署与重载。
#   要加自己的动作: 在本文件里另写 module_<模块名>_<阶段>() 函数并加进 MODULES 即可;
#   全程只有这一个脚本,不需要 MODULE_DIR,也不需要额外引入/source 外部文件。
#
# 使用:
#   1) 编辑本文件"配置区": API_UID / API_KEY / CERT_IDS / OUT_DIR / CUSTOM_CMD ...
#   2) chmod 755 dnsmgr-cert.sh
#   3) ./dnsmgr-cert.sh modules    # 查看有哪些模块及其阶段
#   4) ./dnsmgr-cert.sh check      # 自检(签名样例 + 试下载第一个订单)
#   5) ./dnsmgr-cert.sh            # 正式下载
#      每天跑一次建议加 -r 15: 本地证书剩余 >= 15 天时不再重复下载(见配置区 RENEW_DAYS)
#   6) crontab -e 添加: 30 3 * * * /usr/local/bin/dnsmgr-cert.sh
#      30 3 * * * /usr/local/bin/dnsmgr-cert.sh -r 15 >> /var/log/dnsmgr-cert.log 2>&1
#
# 服务器部署与定时任务(cron):
#   部署: 本文件放到 /usr/local/bin/dnsmgr-cert.sh 并 chmod 755
#         (Windows 上编辑过先执行 dos2unix); 先手动 check 自检一次再挂 cron;
#         证书目录 OUT_DIR 不存在时脚本自己 mkdir -p(权限跟随 umask,一般 755),
#         证书 644 / 私钥 600,用 root 跑最省事;想让普通用户跑就把 OUT_DIR 指到该用户可写目录。
#   crontab -e(脚本自带锁文件,上一轮没跑完时本轮直接跳过,不需要额外 flock):
#         30 3 * * * /usr/local/bin/dnsmgr-cert.sh -r 15 >> /var/log/dnsmgr-cert.log 2>&1
#   /etc/cron.d/dnsmgr-cert 的写法多一个"用户"字段(适合 root 统一部署,卸载时直接删文件):
#         30 3 * * * root /usr/local/bin/dnsmgr-cert.sh -r 15 >> /var/log/dnsmgr-cert.log 2>&1
#   cron 环境要点(踩坑基本都在这里):
#     - 脚本与命令一律绝对路径(含 CUSTOM_CMD / RELOAD_CMD 里的可执行文件);
#     - cron 默认 PATH=/usr/bin:/bin,需要时在 crontab 顶部加一行 PATH=/usr/local/bin:/usr/bin:/bin;
#     - cron 不启动登录 shell,不读 /etc/profile 和 ~/.bashrc,在那里 export 的 API_UID/API_KEY
#       不生效: 要覆盖配置区就在 cron 行里内联传(API_KEY=xxxx /usr/local/bin/dnsmgr-cert.sh -r 15),
#       或直接改本文件"配置区"默认值(systemd 服务可用 EnvironmentFile 传);
#     - cron 把百分号当特殊字符,命令里的百分号(如 date +%F)必须转义,否则该行之后的内容会被截断;
#     - cron 的 HOME 可能为空,自定义命令里不要用 ~ 开头的路径;
#     - 触发时间按系统本地时区(与 date 一致),服务器是 UTC 又想按北京时间跑就先核对 timedatectl;
#     - MAILTO 留空则 cron 不发信;只想收到异常就在 cron 里配 MAILTO 并给脚本加 -q(只输出 WARN/ERROR);
#     - 接口有频控时把固定分钟换成范围/步进(如 23-59/7 3 * * *)来错开时间。
#   日志: 默认追加写 LOG_FILE=/var/log/dnsmgr-cert.log,建议配 logrotate(见 README);
#         把 LOG_FILE 置空则只输出到标准输出,完全交给 cron 重定向或 systemd journal。
#   换证后的服务重载统一交给内置 reload 模块(RELOAD_CMD)处理,
#   不要再往 crontab 里单加一条 systemctl reload,否则证书没更新时也会白白重载。
#=====================================================================

#=====================================================================
# ---------------------------- 配 置 区 ----------------------------
# 全部写成 ${环境变量名:-默认值} : 直接改冒号后的默认值即可,同名环境变量优先。
#=====================================================================
API_BASE="${API_BASE:-https://ssl.explame.com}"   # 接口地址(示例站点,替换成你自己的 dnsmgr 地址),结尾不要带 /
API_UID="${API_UID:-1}"                        # 用户ID:后台"用户管理"中查看
API_KEY="${API_KEY:-请填写你的API接口密钥}"      # API密钥:后台打开API接口后查看(必填)
CERT_IDS="${CERT_IDS:-27}"                     # SSL证书订单ID,多个用英文逗号分隔,如 27 或 27,28

OUT_DIR="${OUT_DIR:-/etc/ssl/dnsmgr}"          # 证书保存目录(cron 环境请用绝对路径)
WARN_DAYS="${WARN_DAYS:-15}"                   # 距到期不足该天数时输出 WARN 日志
# 按需下载阈值: 本地已保存的这张证书剩余有效期还不低于 RENEW_DAYS 天时,本订单直接跳过
#   (不请求接口/不校验/不覆盖文件/不触发模块); 剩余天数小于该值才下载新证书并校验。
#   判定只看本地证书文件: 优先用 openssl 读它的到期时间,读不到就退回同订单 .info.txt 里的 expiretime;
#   本地没有这张证书(首次运行 / 换过 OUT_DIR / 手工删过文件)或读不出有效期时一律照常下载,
#   所以上线第一次必定下载,不会因为"跳过"而漏掉证书; 要临时强制下载用 -f(--force)。
#   默认 0 = 不做按需判断,每次都下载并校验(和旧版行为一致); 每天跑一次的 cron 建议设 15 或 30。
RENEW_DAYS="${RENEW_DAYS:-0}"                       # 本地证书剩余不足该天数才下载(0=每次都下载)
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-0}"               # 1=忽略上面的阈值强制下载(check 子命令自动按 1 处理)

HTTP_TIMEOUT="${HTTP_TIMEOUT:-30}"             # 单次请求超时秒数
HTTP_RETRIES="${HTTP_RETRIES:-3}"              # 请求失败重试次数
CURL_INSECURE="${CURL_INSECURE:-0}"            # 1=跳过HTTPS证书校验(仅自签测试环境)

# 追加写入的日志文件,留空表示只输出到标准输出(交给 cron 重定向)
LOG_FILE="${LOG_FILE:-/var/log/dnsmgr-cert.log}"

# 启用的模块(空格分隔,按书写顺序执行)。内置: custom_cmd reload notify
# 下载后的自定义操作用 custom_cmd(填 CUSTOM_CMD 或命令行 --cmd),不再另设自定义模块区
MODULES="${MODULES:-custom_cmd reload}"

#---- 模块 custom_cmd 的参数: 证书下载后执行自定义命令(部署/分发/通知等) ----
# 命令中可直接使用上下文变量(由脚本在执行该命令时展开):
#   CERT_ID CERT_DOMAIN CERT_DIR CERT_FILE KEY_FILE
#   CERT_ISSUE CERT_EXPIRE CERT_CHANGED CERT_VERIFIED MODULE_PHASE
# 命令类配置建议用单引号直接赋值($ 变量不会在此刻展开,可读性最好且免去多层转义);
# 示例写在下面"兜底行"之前,取消注释即生效;不取消注释则取兜底行的空默认值。
# 示例(取消注释任意一条):
# CUSTOM_CMD='cat "$CERT_FILE" "$KEY_FILE" > "/etc/haproxy/certs/$CERT_DOMAIN.pem"'
# CUSTOM_CMD='cp -f "$CERT_FILE" "$KEY_FILE" "/www/server/panel/vhost/cert/$CERT_DOMAIN/"'
# CUSTOM_CMD='scp -q "$CERT_FILE" "$KEY_FILE" root@10.0.0.8:/etc/nginx/ssl/'
# CUSTOM_CMD='echo "证书已更新: $CERT_DOMAIN" >> /var/log/cert-event.log'
CUSTOM_CMD="${CUSTOM_CMD:-}"
CUSTOM_CMD_ON_CHANGE_ONLY="${CUSTOM_CMD_ON_CHANGE_ONLY:-1}"  # 1=仅证书有更新时执行 0=每次下载后都执行
CUSTOM_CMD_SHELL="${CUSTOM_CMD_SHELL:-bash}"                # 执行下面三类命令用的解释器

#---- 模块 reload 的参数: 全部订单处理完且本轮有证书更新时重载服务(只执行一次) ----
# RELOAD_CMD='nginx -t && systemctl reload nginx'
# RELOAD_CMD='systemctl reload haproxy'
RELOAD_CMD="${RELOAD_CMD:-}"

#---- 模块 notify 的参数: 剩余有效期不足 WARN_DAYS 天时告警(告警文本经标准输入传给命令) ----
# NOTIFY_CMD='mail -s "dnsmgr证书到期提醒" admin@example.com'
# NOTIFY_CMD='curl -s -X POST --data-binary @- https://push.example.com/send?token=xxx'
NOTIFY_CMD="${NOTIFY_CMD:-}"
#=====================================================================
# -------------------------- 以下无需修改 --------------------------
#=====================================================================
set -u
set -o pipefail

PROG=${0##*/}
VERSION="3.0"
API_KEY_PLACEHOLDER="请填写你的API接口密钥"
PHASES="init pre_download post_download on_change final"

#-------- 内部变量 --------
QUIET=0
ACTION="download"
ORDER_LIST=""          # 空格分隔的订单ID(去重后)
CHANGED_FLAG=""        # 标记"本轮有证书更新"的临时文件(子进程也可写)
VERIFIED_FLAG=""       # 标记"本轮有证书下载完成并通过校验"的临时文件
SKIP_FLAG=""           # 记录"因本地证书剩余天数够用而跳过下载"的订单(收尾统计用)
RESP_CODE=""
RESP_BODY=""
LOCK=""
RC=0
# 传给模块的上下文(每个订单处理过程中刷新)
CERT_ID=""
CERT_DOMAIN=""
CERT_DIR=""
CERT_FILE=""
KEY_FILE=""
CERT_ISSUE=""
CERT_EXPIRE=""
CERT_CHANGED=0
CERT_VERIFIED=0
MODULE_PHASE=""

have() { command -v "$1" >/dev/null 2>&1; }

# 数字型配置校验(避免把带空格/符号的值写进配置区后行为异常)
num_or_die() {
    case $2 in
        ""|*[!0-9]*) die "配置项 $1 必须是数字,当前值: [$2]" ;;
    esac
}

log() {
    level=$1; shift
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    if [ "$level" != "INFO" ] || [ "$QUIET" -eq 0 ]; then
        echo "$line"
    fi
    if [ -n "$LOG_FILE" ]; then
        logdir=${LOG_FILE%/*}
        if [ "$logdir" != "$LOG_FILE" ]; then
            mkdir -p "$logdir" 2>/dev/null
        fi
        # 用代码块包住重定向: 目录不存在/无权限时连 bash 自身的报错一起丢弃
        { echo "$line" >>"$LOG_FILE"; } 2>/dev/null
    fi
    return 0
}
info()  { log INFO  "$@"; }
warn()  { log WARN  "$@"; }
error() { log ERROR "$@"; }
die()   { log ERROR "$@"; exit 1; }

# 日志文件可写性自检: 不可写只提醒一次,不影响证书下载
check_log_writable() {
    [ -n "$LOG_FILE" ] || return 0
    logdir=${LOG_FILE%/*}
    if [ "$logdir" = "$LOG_FILE" ]; then
        logdir=.
    fi
    if [ ! -d "$logdir" ]; then
        warn "日志目录不存在且无法创建: $logdir ,本次仅输出到标准输出"
    elif [ ! -w "$logdir" ] || { [ -e "$LOG_FILE" ] && [ ! -w "$LOG_FILE" ]; }; then
        warn "日志文件不可写: $LOG_FILE ,本次仅输出到标准输出"
    fi
    return 0
}

add_order() {
    case " $ORDER_LIST " in
        *" $1 "*) : ;;
        *) ORDER_LIST="$ORDER_LIST $1" ;;
    esac
}

usage() {
    cat <<USAGE
$PROG v$VERSION -- dnsmgr SSL 证书自动下载(单文件 / 模块化版)

用法: $PROG [子命令] [选项]

子命令:
  download        下载并校验证书(默认子命令)
  check           检查依赖、配置、签名,并试下载校验第一个订单
  modules         列出可用模块、支持的阶段与启用状态
  list            尝试列出证书订单ID(该接口未收录于文档,失败属正常)

选项:
  -o, --out DIR        覆盖配置区的证书保存目录    [当前: $OUT_DIR]
  -i, --cert-id ID     追加指定SSL证书订单ID,可重复使用
  -m, --modules LIST   覆盖启用模块列表,如 -m 'custom_cmd reload'
      --cmd CMD        覆盖模块 custom_cmd 的自定义命令
      --reload CMD     覆盖模块 reload 的重载命令
      --notify CMD     覆盖模块 notify 的告警命令
      --log FILE       覆盖配置区的日志文件
  -r, --renew-days N   按需下载: 本地证书剩余有效期不足 N 天才下载并校验,否则跳过该订单
                       只看本地已保存的证书,本地没有该订单证书时一定下载; 0=每次都下载
                       每天跑一次的 cron 建议设 15 或 30   [当前: $RENEW_DAYS]
  -f, --force          忽略按需下载阈值,本次强制下载并校验
  -n, --no-subdir      兼容保留(忽略): 证书一律平铺保存在 OUT_DIR 下
                       文件名: 域名.crt.pem / 域名.key.pem
                       泛域名 *.域名 保存为 wild.域名.crt.pem
  -q, --quiet          只输出警告和错误
  -h, --help           显示本帮助
  -v, --version        显示版本

模块机制:
  内置模块 = 一组约定命名的函数 module_<模块名>_<阶段>() ,阶段: $PHASES
  内置模块启用列表: MODULES (当前: ${MODULES:-空})
  扩展动作: 需要多行逻辑就在本脚本里另写 module_<模块名>_<阶段>() 函数,
            并把模块名加进 MODULES(或命令行 -m),同样不需要外部文件
  证书校验: PEM结构 / X.509 解析 / 未过期 / 私钥与证书匹配(后三项需安装 openssl)
            校验不通过不会覆盖现有证书文件,也不会触发下载后的模块
  按需下载: 设了 RENEW_DAYS(或 -r N) 时,本地证书剩余天数不低于阈值就跳过该订单,
            既不请求接口也不校验; 想强制下载用 -f。check 子命令始终会真实下载校验一次
  模块可读取的上下文变量: CERT_ID CERT_DOMAIN CERT_DIR CERT_FILE KEY_FILE
                          CERT_ISSUE CERT_EXPIRE CERT_CHANGED CERT_VERIFIED MODULE_PHASE

配置方式:
  1) 直接编辑脚本顶部"配置区"的默认值(推荐,单文件部署)
  2) 或用同名环境变量临时覆盖:
      API_BASE API_UID API_KEY CERT_IDS OUT_DIR WARN_DAYS RENEW_DAYS FORCE_DOWNLOAD HTTP_TIMEOUT
      HTTP_RETRIES CURL_INSECURE LOG_FILE MODULES
      CUSTOM_CMD CUSTOM_CMD_ON_CHANGE_ONLY CUSTOM_CMD_SHELL RELOAD_CMD NOTIFY_CMD

定时任务(服务器部署):
  放到 /usr/local/bin 并 chmod 755,先手动 check 自检,再 crontab -e 挂上(锁文件已防并发):
    30 3 * * * /usr/local/bin/$PROG -r 15 >> /var/log/dnsmgr-cert.log 2>&1
  /etc/cron.d 写法多一个用户字段:
    30 3 * * * root /usr/local/bin/$PROG -r 15 >> /var/log/dnsmgr-cert.log 2>&1
  要点: 一律绝对路径; cron 默认 PATH 只有 /usr/bin:/bin,需要时在 crontab 顶部加 PATH=;
        cron 不读 profile/bashrc,覆盖配置请在 cron 行里内联传变量或直接改配置区;
        cron 里的百分号是特殊字符,命令中如 date +%F 必须转义; HOME 可能为空,别用 ~ 路径;
        按系统本地时区触发; MAILTO 留空不发信,只想收告警就加 -q; 详见本脚本头部注释与 README

示例:
  ./$PROG modules
  ./$PROG check
  ./$PROG -i 27 -o /etc/ssl/dnsmgr -m 'custom_cmd reload' --reload 'systemctl reload nginx'
  ./$PROG -m custom_cmd --cmd 'cp -f "\$CERT_FILE" "\$KEY_FILE" /etc/nginx/ssl/'
  ./$PROG -r 15           # 本地证书剩余 >= 15 天就跳过下载(适合每日 cron)
  ./$PROG -f              # 忽略阈值,强制重新下载并校验一次
  API_UID=1 API_KEY=xxxx ./$PROG
USAGE
}

#-------- 命令行选项(在配置区之后解析,可覆盖配置区取值) --------
while [ $# -gt 0 ]; do
    case $1 in
        -o|--out)     [ $# -ge 2 ] || die "选项 $1 缺少参数"; OUT_DIR=$2; shift 2 ;;
        --out=*)      OUT_DIR=${1#*=}; shift ;;
        -i|--cert-id) [ $# -ge 2 ] || die "选项 $1 缺少参数"; add_order "$2"; shift 2 ;;
        --cert-id=*)  add_order "${1#*=}"; shift ;;
        -m|--modules) [ $# -ge 2 ] || die "选项 $1 缺少参数"; MODULES=$2; shift 2 ;;
        --modules=*)  MODULES=${1#*=}; shift ;;
        --cmd|--deploy)  [ $# -ge 2 ] || die "选项 $1 缺少参数"; CUSTOM_CMD=$2; shift 2 ;;
        --reload)     [ $# -ge 2 ] || die "选项 $1 缺少参数"; RELOAD_CMD=$2; shift 2 ;;
        --notify)     [ $# -ge 2 ] || die "选项 $1 缺少参数"; NOTIFY_CMD=$2; shift 2 ;;
        --log)        [ $# -ge 2 ] || die "选项 $1 缺少参数"; LOG_FILE=$2; shift 2 ;;
        -r|--renew-days) [ $# -ge 2 ] || die "选项 $1 缺少参数"; RENEW_DAYS=$2; shift 2 ;;
        --renew-days=*) RENEW_DAYS=${1#*=}; shift ;;
        -f|--force)     FORCE_DOWNLOAD=1; shift ;;
        -n|--no-subdir) shift ;;   # 兼容旧参数,现在只有平铺一种布局
        -q|--quiet)   QUIET=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        -v|--version) echo "$PROG $VERSION"; exit 0 ;;
        download|check|modules|list) ACTION=$1; shift ;;
        *) die "未知参数: $1  (使用 -h 查看帮助)" ;;
    esac
done

# 兼容旧版配置名: DEPLOY_CMD 视为 CUSTOM_CMD
if [ -n "${DEPLOY_CMD:-}" ] && [ -z "$CUSTOM_CMD" ]; then
    CUSTOM_CMD=$DEPLOY_CMD
fi

# 合并配置区 / 环境变量里的 CERT_IDS(支持逗号或空格分隔)
if [ -n "$CERT_IDS" ]; then
    for _id in $(printf '%s' "$CERT_IDS" | tr ',' ' '); do
        add_order "$_id"
    done
fi
ORDER_LIST=$(printf '%s' "$ORDER_LIST" | sed 's/^ *//; s/  */ /g; s/ $//')

require_tools() {
    have curl || die "未找到 curl,请先安装: apt install curl / yum install curl"
    have awk  || die "未找到 awk(用于解析接口返回的 JSON)"
    if ! have md5sum && ! have md5 && ! have openssl; then
        die "未找到 md5 计算工具,请安装 coreutils 或 openssl"
    fi
    if [ -z "$API_UID" ]; then die "请在脚本配置区填写 API_UID(用户ID)"; fi
    case $API_UID in
        *[!0-9]*) die "API_UID 必须是纯数字(当前值: $API_UID)" ;;
    esac
    num_or_die "WARN_DAYS(剩余天数)" "$WARN_DAYS"
    num_or_die "RENEW_DAYS(按需下载天数)" "$RENEW_DAYS"
    num_or_die "HTTP_TIMEOUT(超时秒数)" "$HTTP_TIMEOUT"
    num_or_die "HTTP_RETRIES(重试次数)" "$HTTP_RETRIES"
    if [ -z "$API_KEY" ]; then
        die "请在脚本配置区填写 API_KEY(API接口密钥),或先用 ./$PROG -h 查看说明"
    fi
    if [ "$API_KEY" = "$API_KEY_PLACEHOLDER" ]; then
        die "API_KEY 还是默认占位值,请编辑本脚本顶部配置区填写真实密钥"
    fi
}

require_orders() {
    if [ -z "$ORDER_LIST" ]; then
        die "未指定 SSL 证书订单ID: 请在配置区设置 CERT_IDS,或使用 -i <ID> 参数"
    fi
}

#================ 模块化钩子框架 ================
export_cert_env() {
    export CERT_ID CERT_DOMAIN CERT_DIR CERT_FILE KEY_FILE
    export CERT_ISSUE CERT_EXPIRE CERT_CHANGED CERT_VERIFIED MODULE_PHASE
}

module_exists() {
    _m=$1
    for _p in $PHASES; do
        if declare -F "module_${_m}_${_p}" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

init_modules() {
    _ok=""
    for _m in $MODULES; do
        if ! module_exists "$_m"; then
            if [ "$_m" = "user" ]; then
                warn "模块 user(自定义模块区)已在 v3.0 移除: 下载后的动作请改用 custom_cmd,多行逻辑可自行定义 module_<模块名>_<阶段>"
            else
                warn "模块 $_m 不存在(未找到 module_${_m}_* 函数),已忽略"
            fi
            continue
        fi
        _ok="$_ok $_m"
        if declare -F "module_${_m}_init" >/dev/null 2>&1; then
            MODULE_PHASE="init"
            export_cert_env
            "module_${_m}_init"
            if [ $? -ne 0 ]; then
                warn "模块 $_m 初始化返回非0(功能可能不完整)"
            fi
        fi
    done
    MODULES=$(printf '%s' "$_ok" | sed 's/^ *//')
    if [ -n "$MODULES" ]; then
        info "已启用模块: $MODULES"
    else
        info "未启用任何模块,只下载并保存证书"
    fi
}

# run_modules <阶段名>   按 MODULES 顺序执行该阶段的钩子
run_modules() {
    _phase=$1
    for _m in $MODULES; do
        _fn="module_${_m}_${_phase}"
        if declare -F "$_fn" >/dev/null 2>&1; then
            MODULE_PHASE="$_phase"
            export_cert_env
            "$_fn"
            if [ $? -ne 0 ]; then
                error "模块 $_m 的 $_phase 钩子执行失败"
                return 1
            fi
        fi
    done
    return 0
}

have_changes() {
    [ -n "$CHANGED_FLAG" ] && [ -s "$CHANGED_FLAG" ]
}

mark_changed() {
    # 追加而不是清空,便于判断"本轮是否发生过更新"
    if [ -n "$CHANGED_FLAG" ]; then
        echo changed >>"$CHANGED_FLAG"
    fi
}

mark_verified() {
    # 记录"本张证书已下载完成并通过校验": final 阶段与各模块钩子据此判断
    if [ -n "$VERIFIED_FLAG" ]; then
        echo ok >>"$VERIFIED_FLAG"
    fi
}

have_verified() {
    [ -n "$VERIFIED_FLAG" ] && [ -s "$VERIFIED_FLAG" ]
}

mark_skipped() {
    # 记录"本订单按按需下载规则跳过": 只用于收尾统计,不影响 final 阶段的判断
    if [ -n "$SKIP_FLAG" ]; then
        echo skip >>"$SKIP_FLAG"
    fi
}

skipped_count() {
    if [ -n "$SKIP_FLAG" ] && [ -s "$SKIP_FLAG" ]; then
        wc -l <"$SKIP_FLAG" | tr -d ' '
    else
        printf '0'
    fi
}

#================ 内置模块 ================
# 配置类提示: check 子命令里按 WARN 强调,平时运行只给 INFO,避免 cron 日志噪音
cfg_hint() {
    if [ "$ACTION" = "check" ]; then
        warn "$@"
    else
        info "$@"
    fi
}

# 模块: custom_cmd (预设) -- 证书下载保存后执行自定义命令,常用于部署/分发/触发面板接口
module_custom_cmd_init() {
    if [ -z "$CUSTOM_CMD" ]; then
        cfg_hint "模块 custom_cmd 已启用但 CUSTOM_CMD 为空,不会执行任何命令(在配置区填写,或用 -m 去掉该模块)"
    fi
}

module_custom_cmd_post_download() {
    if [ -z "$CUSTOM_CMD" ]; then
        return 0
    fi
    if [ "$CUSTOM_CMD_ON_CHANGE_ONLY" = "1" ] && [ "$CERT_CHANGED" != "1" ]; then
        info "模块 custom_cmd : 证书内容无变化,跳过自定义命令"
        return 0
    fi
    info "模块 custom_cmd : 执行自定义命令 [$CERT_DOMAIN] -> $CUSTOM_CMD"
    "${CUSTOM_CMD_SHELL:-bash}" -c "$CUSTOM_CMD"
    if [ $? -ne 0 ]; then
        return 1
    fi
    info "模块 custom_cmd : 自定义命令执行完成"
    return 0
}

# 模块: reload -- 全部订单处理完且本轮有证书更新时重载服务(只执行一次)
module_reload_init() {
    if [ -z "$RELOAD_CMD" ]; then
        cfg_hint "模块 reload 已启用但 RELOAD_CMD 为空,证书更新后不会重载服务(在配置区填写,或用 -m 去掉该模块)"
    fi
}

module_reload_final() {
    [ -n "$RELOAD_CMD" ] || return 0
    if ! have_changes; then
        info "模块 reload : 证书无变化,跳过重载"
        return 0
    fi
    info "模块 reload : 执行重载命令 -> $RELOAD_CMD"
    "${CUSTOM_CMD_SHELL:-bash}" -c "$RELOAD_CMD"
    if [ $? -ne 0 ]; then
        return 1
    fi
    return 0
}

# 模块: notify -- 证书即将到期时执行告警命令(告警文本通过标准输入传给命令)
module_notify_init() {
    if [ -z "$NOTIFY_CMD" ]; then
        cfg_hint "模块 notify 已启用但 NOTIFY_CMD 为空,到期提醒不会外发(在配置区填写,或用 -m 去掉该模块)"
    fi
}

module_notify_post_download() {
    [ -n "$NOTIFY_CMD" ] || return 0
    days=$(remaining_days "$CERT_FILE" "$CERT_EXPIRE")
    if [ -z "$days" ]; then
        return 0
    fi
    if [ "$days" -le "$WARN_DAYS" ]; then
        printf 'dnsmgr证书告警: 域名 %s(订单 %s) 剩余 %s 天,到期时间 %s\n' \
            "$CERT_DOMAIN" "$CERT_ID" "$days" "${CERT_EXPIRE:-未知}" \
            | "${CUSTOM_CMD_SHELL:-bash}" -c "$NOTIFY_CMD"
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    return 0
}

#================ 基础工具 ================
md5_hex() {
    in=$1
    if have md5sum; then
        printf '%s' "$in" | md5sum | awk '{print $1}'
    elif have md5; then
        printf '%s' "$in" | md5 -q
    else
        printf '%s' "$in" | openssl dgst -md5 -r | awk '{print $1}'
    fi
}

urlencode() {
    s=$1
    out=""
    i=0
    while [ "$i" -lt ${#s} ]; do
        c=${s:$i:1}
        case $c in
            [a-zA-Z0-9._~-]) out="$out$c" ;;
            *) out="$out$(printf '%%%02X' "'$c")" ;;
        esac
        i=$((i + 1))
    done
    printf '%s' "$out"
}

# 取 JSON 中第一个匹配的字符串字段值(数据来自标准输入),自动还原 \" \n \\ 等转义
json_str() {
    awk -v key="\"$1\"" '
        BEGIN { started = 0; out = "" }
        {
            line = $0 "\n"
            if (started == 0) {
                p = index(line, key)
                if (p == 0) next
                rest = substr(line, p + length(key))
                sub(/^[ \t]*:[ \t]*/, "", rest)
                if (substr(rest, 1, 1) != "\"") next
                line = substr(rest, 2)
                started = 1
            }
            n = length(line); i = 1
            while (i <= n) {
                ch = substr(line, i, 1)
                if (ch == "\\") {
                    nx = substr(line, i + 1, 1)
                    if (nx == "n")        out = out "\n"
                    else if (nx == "t")   out = out "\t"
                    else if (nx == "r")   { }
                    else if (nx == "\"")  out = out "\""
                    else if (nx == "\\")  out = out "\\"
                    else if (nx == "/")   out = out "/"
                    else if (nx == "u")   i = i + 4
                    i = i + 2
                    continue
                }
                if (ch == "\"") { printf "%s", out; exit 0 }
                if (ch != "\n") out = out ch
                i++
            }
        }
    '
}

# 取 JSON 中第一个匹配的数字字段值
json_num() {
    grep -o "\"$1\"[ \t]*:[ \t]*-\{0,1\}[0-9]\{1,\}" | head -n 1 | grep -o -- '-\{0,1\}[0-9]\{1,\}$'
}

# 取 JSON 数组字段中的第一个字符串(用于 domains)
json_first_item() {
    sed -n "s/.*\"$1\"[ \t]*:[ \t]*\[\([^]]*\)\].*/\1/p" | head -n 1 \
        | sed -n 's/^[^"]*"\([^"]*\)".*/\1/p'
}

#================ 接口调用 ================
# api_post <path> [额外表单参数]
api_post() {
    path=$1
    extra=${2:-}
    url="${API_BASE%/}${path}"
    ts=$(date +%s)
    sign=$(md5_hex "${API_UID}${ts}${API_KEY}")
    body="uid=$(urlencode "$API_UID")&timestamp=${ts}&sign=${sign}"
    if [ -n "$extra" ]; then
        body="${body}&${extra}"
    fi

    tmp=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert.XXXXXX") || die "无法创建临时文件"
    set -- -sS --max-time "$HTTP_TIMEOUT" --connect-timeout 10 \
           --retry "$HTTP_RETRIES" --retry-delay 2 \
           -H 'Content-Type: application/x-www-form-urlencoded' \
           --data "$body" -o "$tmp" -w '%{http_code}'
    if [ "$CURL_INSECURE" = "1" ]; then
        set -- "$@" -k
    fi
    if ! http=$(curl "$@" "$url"); then
        rm -f "$tmp"
        die "请求接口失败: $url (网络不通 / DNS 解析失败 / 超时)"
    fi
    RESP_CODE=$http
    RESP_BODY=$(cat "$tmp")
    rm -f "$tmp"

    if [ "$RESP_CODE" != "200" ]; then
        die "HTTP $RESP_CODE <- $url ,响应: $(printf '%.300s' "$RESP_BODY")"
    fi
}

# 校验接口业务返回码(文档: code=0 成功,其他失败)
api_ok() {
    code=$(printf '%s' "$RESP_BODY" | json_num code)
    if [ "$code" != "0" ]; then
        msg=$(printf '%s' "$RESP_BODY" | json_str msg)
        if [ -z "$msg" ]; then
            msg=$(printf '%.300s' "$RESP_BODY")
        fi
        die "接口返回失败 code=${code:-非JSON} msg=${msg} (请核对 uid / API密钥 / 证书订单ID)"
    fi
}

# write_file <文件> <内容> <权限>   返回 0=已更新  1=内容无变化
write_file() {
    target=$1
    content=$2
    mode=$3
    tmp=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert.XXXXXX") || die "无法创建临时文件"
    printf '%s\n' "$content" | tr -d '\r' >"$tmp"
    if [ -f "$target" ] && cmp -s "$target" "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mkdir -p "${target%/*}" 2>/dev/null
    if [ -f "$target" ]; then
        cp -p "$target" "$target.bak" 2>/dev/null
    fi
    cat "$tmp" >"$target" || { rm -f "$tmp"; die "写入文件失败: $target"; }
    rm -f "$tmp"
    chmod "$mode" "$target" 2>/dev/null
    return 0
}

sanitize() {
    # 泛域名 *.example.com 保存为 wild.example.com.crt.pem,避免和主域名订单同名互相覆盖
    printf '%s' "$1" | sed 's/^\*\./wild./' | tr -c 'A-Za-z0-9._-' '-' | sed 's/^[-.]*//; s/[-.]*$//'
}

# 计算证书剩余天数: 优先用 openssl 读证书,读不到则退回接口返回的 expiretime
# 参数: <证书文件> [到期时间]; 无法计算时不输出任何内容
remaining_days() {
    cert=$1
    exp=${2:-}
    endstr=""
    if have openssl; then
        endstr=$(openssl x509 -noout -enddate -in "$cert" 2>/dev/null | sed 's/^notAfter=//')
    fi
    if [ -z "$endstr" ]; then
        endstr=$exp
    fi
    if [ -z "$endstr" ]; then
        return 0
    fi
    endepoch=$(date -d "$endstr" +%s 2>/dev/null)
    if [ -z "$endepoch" ]; then
        endepoch=$(date -j -u -f '%b %e %T %Y %Z' "$endstr" +%s 2>/dev/null)
    fi
    if [ -z "$endepoch" ]; then
        endepoch=$(date -j -u -f '%Y-%m-%d %T' "$endstr" +%s 2>/dev/null)
    fi
    if [ -z "$endepoch" ]; then
        return 0
    fi
    echo $(( (endepoch - $(date +%s)) / 86400 ))
}

#================ 证书校验 ================
# 只有校验通过的证书才会写盘,也才会触发下载后的模块钩子
# verify_cert_payload <证书PEM> <私钥PEM(可为空)> <接口返回的到期时间> <目标证书文件>
# 返回: 0=校验通过  1=校验失败(已打印具体原因,调用方只需放弃本次覆盖)
pem_epoch() {
    # 把 "notAfter=Feb  1 00:00:00 2027 GMT" 转成秒时间戳,失败返回空
    _s=${1#notAfter=}
    _e=$(date -d "$_s" +%s 2>/dev/null)
    if [ -z "$_e" ]; then
        _e=$(date -j -u -f '%b %e %T %Y %Z' "$_s" +%s 2>/dev/null)
    fi
    printf '%s' "$_e"
}

pub_fp() {
    # 公钥指纹,用于判断证书与私钥是否配成一对
    openssl sha256 2>/dev/null | awk '{print $NF}'
}

verify_cert_payload() {
    _crt=$1
    _key=$2
    _exp=$3
    _target=$4

    # 1) PEM 结构检查(不依赖 openssl,永远执行; 用 case 做包含匹配,避免管道与 pipefail 的干扰)
    case $_crt in
        *"-----BEGIN CERTIFICATE-----"*) : ;;
        *) error "证书校验失败: data.crt 不是 PEM 证书(缺少 BEGIN CERTIFICATE 行)"; return 1 ;;
    esac
    if [ -n "$_key" ]; then
        case $_key in
            *"-----BEGIN"*"PRIVATE KEY-----"*) : ;;
            *) error "证书校验失败: data.key 不是 PEM 私钥(缺少 PRIVATE KEY 行)"; return 1 ;;
        esac
    fi

    if ! have openssl; then
        warn "未安装 openssl,本次只做 PEM 结构检查(X.509 解析/有效期/密钥匹配已跳过)"
        return 0
    fi

    _tmpc=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert.XXXXXX") || return 0
    _tmpk=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert.XXXXXX") || { rm -f "$_tmpc"; return 0; }
    printf '%s\n' "$_crt" | tr -d '\r' >"$_tmpc"

    # 2) X.509 是否能解析(内容被截断/不是证书都在这里拦住)
    if ! openssl x509 -in "$_tmpc" -noout >/dev/null 2>&1; then
        error "证书校验失败: openssl 无法解析该证书(内容不完整或不是 X.509 证书)"
        rm -f "$_tmpc" "$_tmpk"
        return 1
    fi

    # 3) 是否已经过期(拿已过期的证书覆盖现有文件最容易出事故)
    if ! openssl x509 -in "$_tmpc" -noout -checkend 0 >/dev/null 2>&1; then
        error "证书校验失败: 接口返回的证书已过期(到期时间 ${_exp:-未知}),不覆盖现有证书"
        rm -f "$_tmpc" "$_tmpk"
        return 1
    fi

    # 4) 私钥与证书是否匹配
    if [ -n "$_key" ]; then
        printf '%s\n' "$_key" | tr -d '\r' >"$_tmpk"
        _cpub=$(openssl x509 -in "$_tmpc" -noout -pubkey 2>/dev/null | pub_fp)
        _kpub=$(openssl pkey -pubout -in "$_tmpk" 2>/dev/null | pub_fp)
        if [ -z "$_kpub" ]; then
            _kpub=$(openssl rsa -pubout -in "$_tmpk" 2>/dev/null | pub_fp)
        fi
        if [ -n "$_cpub" ] && [ -n "$_kpub" ]; then
            if [ "$_cpub" != "$_kpub" ]; then
                error "证书校验失败: 私钥与证书不匹配,不覆盖现有证书"
                rm -f "$_tmpc" "$_tmpk"
                return 1
            fi
        else
            warn "私钥类型无法用 openssl 取出公钥,已跳过证书与私钥匹配校验"
        fi
    fi

    # 5) 新证书到期时间早于现存文件中的证书: 只提示(防止订单回传旧证书把新证书覆盖回去)
    if [ -n "$_target" ] && [ -f "$_target" ]; then
        _oldend=$(openssl x509 -in "$_target" -noout -enddate 2>/dev/null)
        _newend=$(openssl x509 -in "$_tmpc" -noout -enddate 2>/dev/null)
        if [ -n "$_oldend" ] && [ -n "$_newend" ]; then
            _oe=$(pem_epoch "$_oldend")
            _ne=$(pem_epoch "$_newend")
            if [ -n "$_oe" ] && [ -n "$_ne" ] && [ "$_ne" -lt "$_oe" ]; then
                warn "接口返回证书的到期时间(${_newend#notAfter=})早于现存证书(${_oldend#notAfter=}),请确认该订单是否已续签"
            fi
        fi
    fi

    rm -f "$_tmpc" "$_tmpk"
    info "证书校验通过: PEM 结构完整,X.509 解析正常,尚未过期"
    return 0
}

#================ 按需下载(本地证书有效期判定) ================
# 设了 RENEW_DAYS(>0) 之后,先看本地这张证书还能用多久: 剩余天数不低于阈值就跳过本次下载,
# 不请求接口/不校验/不覆盖文件/不触发模块钩子; 剩余天数小于阈值,或本地根本没有这张证书,就照常下载。
local_info_of() {
    # local_info_of <订单ID>  输出该订单在 OUT_DIR 下已保存的 .info.txt 路径; 找不到返回 1
    _loid=$1
    for _lf in "$OUT_DIR"/*.info.txt; do
        [ -f "$_lf" ] || continue
        if grep -q "^order_id=$_loid$" "$_lf" 2>/dev/null; then
            printf '%s' "$_lf"
            return 0
        fi
    done
    return 1
}

info_field() {
    # info_field <info文件> <键名>  输出该键的值(同名取第一行); 该文件由本脚本自己写入,每行一个键
    _if=$1
    _ik=$2
    while IFS= read -r _ln || [ -n "$_ln" ]; do
        case $_ln in
            "${_ik}="*) printf '%s' "${_ln#*=}"; break ;;
        esac
    done <"$_if"
}

should_skip_order() {
    # should_skip_order <订单ID>  返回 0=本地证书还够用,本次跳过下载; 1=照常下载并校验
    _soid=$1
    if [ "$RENEW_DAYS" -le 0 ] || [ "$FORCE_DOWNLOAD" = "1" ]; then
        return 1
    fi
    _linfo=$(local_info_of "$_soid")
    if [ -z "$_linfo" ]; then
        info "订单 $_soid 本地没有已保存的证书记录,本次照常下载"
        return 1
    fi
    _lcert=$(info_field "$_linfo" cert_file)
    _lexp=$(info_field "$_linfo" expiretime)
    _ldom=$(info_field "$_linfo" domains)
    if [ -z "$_lcert" ] || [ ! -f "$_lcert" ]; then
        info "订单 $_soid 本地证书文件不存在(${_lcert:-未记录}),本次照常下载"
        return 1
    fi
    _ldays=$(remaining_days "$_lcert" "$_lexp")
    if [ -z "$_ldays" ]; then
        warn "订单 $_soid 读不出本地证书的到期时间,无法按需判断,本次照常下载"
        return 1
    fi
    if [ "$_ldays" -lt "$RENEW_DAYS" ]; then
        info "订单 $_soid 本地证书只剩 $_ldays 天(< 阈值 $RENEW_DAYS 天),本次下载新证书并校验"
        return 1
    fi
    CERT_DOMAIN=$(sanitize "$_ldom")
    [ -n "$CERT_DOMAIN" ] || CERT_DOMAIN="cert-$_soid"
    info "订单 $_soid 跳过下载: 本地证书 $CERT_DOMAIN 剩余 $_ldays 天(>= 阈值 $RENEW_DAYS 天)"
    if [ "$_ldays" -le "$WARN_DAYS" ]; then
        warn "证书 $CERT_DOMAIN 剩余 $_ldays 天(到期 ${_lexp:-未知}),请及时续签"
    fi
    mark_skipped
    return 0
}

#================ 下载并保存一个证书订单 ================
fetch_one() {
    oid=$1
    CERT_ID=$oid
    CERT_DOMAIN=""
    CERT_DIR=""
    CERT_FILE=""
    KEY_FILE=""
    CERT_ISSUE=""
    CERT_EXPIRE=""
    CERT_CHANGED=0
    CERT_VERIFIED=0
    info "开始获取 SSL 证书订单 id=$oid"

    #--- 按需下载: 本地证书剩余天数够用就直接返回(不请求接口/不校验/不触发模块钩子) ---
    if should_skip_order "$oid"; then
        return 0
    fi

    export_cert_env
    run_modules pre_download || die "订单 $oid 在 pre_download 阶段被模块中止"
    api_post "/api/cert/order" "id=$(urlencode "$oid")"
    api_ok

    crt=$(printf '%s' "$RESP_BODY" | json_str crt)
    key=$(printf '%s' "$RESP_BODY" | json_str key)
    issue=$(printf '%s' "$RESP_BODY" | json_str issuetime)
    expire=$(printf '%s' "$RESP_BODY" | json_str expiretime)
    domain=$(printf '%s' "$RESP_BODY" | json_first_item domains)

    if [ -z "$crt" ]; then
        die "订单 $oid 返回内容中没有证书(crt),响应: $(printf '%.300s' "$RESP_BODY")"
    fi
    if [ -z "$key" ]; then
        warn "订单 $oid 未返回私钥(key),本次只保存证书"
    fi
    if [ -z "$domain" ] && have openssl; then
        domain=$(printf '%s\n' "$crt" | openssl x509 -noout -subject 2>/dev/null \
                 | sed -n 's/.*CN *= *\([^,/" ]*\).*/\1/p')
    fi
    name=$(sanitize "${domain:-cert-$oid}")
    if [ -z "$name" ]; then
        name="cert-$oid"
    fi
    #--- 平铺保存: OUT_DIR/域名.crt.pem / 域名.key.pem ---
    dir="$OUT_DIR"
    certfile="$dir/$name.crt.pem"
    keyfile="$dir/$name.key.pem"
    infofile="$dir/$name.info.txt"
    mkdir -p "$dir" || die "无法创建目录: $dir"

    #--- 校验先行: 不通过就不覆盖现有证书,也不触发下载后的模块钩子 ---
    verify_cert_payload "$crt" "$key" "$expire" "$certfile" \
        || die "订单 $oid 证书校验未通过,本次不覆盖现有证书文件"

    changed=0
    if write_file "$certfile" "$crt" 644; then
        changed=1; info "已更新: $certfile"
    else
        info "未变化: $certfile"
    fi
    if [ -n "$key" ]; then
        if write_file "$keyfile" "$key" 600; then
            changed=1; info "已更新: $keyfile"
        else
            info "未变化: $keyfile"
        fi
    fi

    {
        echo "order_id=$oid"
        echo "domains=${domain:-}"
        echo "issuetime=${issue:-}"
        echo "expiretime=${expire:-}"
        echo "cert_file=$certfile"
        echo "key_file=$keyfile"
        echo "updated_at=$(date '+%Y-%m-%d %H:%M:%S')"
    } >"$infofile" 2>/dev/null

    # 刷新模块上下文(到这里证书已下载、已校验通过并已保存)
    CERT_DOMAIN=$name
    CERT_DIR=$dir
    CERT_FILE=$certfile
    KEY_FILE=$keyfile
    CERT_ISSUE=$issue
    CERT_EXPIRE=$expire
    CERT_CHANGED=$changed
    CERT_VERIFIED=1
    export_cert_env
    mark_verified
    if [ "$changed" = "1" ]; then
        mark_changed
        run_modules on_change || die "订单 $oid 的 on_change 阶段模块执行失败"
    fi
    run_modules post_download || die "订单 $oid 的 post_download 阶段模块执行失败"

    days=$(remaining_days "$CERT_FILE" "$CERT_EXPIRE")
    if [ -n "$days" ]; then
        if [ "$days" -le "$WARN_DAYS" ]; then
            warn "证书 $name 剩余 ${days} 天(到期 ${expire:-未知}),请及时续签"
        else
            info "证书 $name 剩余 ${days} 天(到期 ${expire:-未知})"
        fi
    else
        info "订单 $oid 保存完成(到期 ${expire:-未知})"
    fi
}

#---------------- 防并发锁 ----------------
acquire_lock() {
    LOCK="${TMPDIR:-/tmp}/.dnsmgr-cert.lock"
    if [ -e "$LOCK" ]; then
        oldpid=$(cat "$LOCK" 2>/dev/null)
        if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
            die "已有实例正在运行(pid=$oldpid),本次跳过"
        fi
    fi
    printf '%s\n' "$$" >"$LOCK" || die "无法写入锁文件: $LOCK"
    trap 'rm -f "$LOCK"' EXIT INT TERM
}

#================ 子命令 ================
do_download() {
    require_tools
    check_log_writable
    require_orders
    mkdir -p "$OUT_DIR" || die "无法创建保存目录: $OUT_DIR"
    acquire_lock
    CHANGED_FLAG=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert-changed.XXXXXX")
    VERIFIED_FLAG=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert-ok.XXXXXX")
    SKIP_FLAG=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert-skip.XXXXXX")
    init_modules
    case $OUT_DIR in
        /*) : ;;
        *)  warn "OUT_DIR 是相对路径($OUT_DIR),cron 中建议改为绝对路径" ;;
    esac
    for oid in $ORDER_LIST; do
        ( fetch_one "$oid" )
        if [ $? -ne 0 ]; then
            error "订单 $oid 处理失败,继续处理其余订单"
            RC=1
        fi
    done
    if have_verified; then
        run_modules final || RC=1
    else
        info "本轮没有下载完成并通过校验的证书,跳过 final 阶段"
    fi
    _sk=$(skipped_count)
    if [ "$_sk" -gt 0 ]; then
        info "按需下载: 本轮跳过 $_sk 个订单(本地证书剩余天数还够用),需要强制下载请用 -f"
    fi
    rm -f "$CHANGED_FLAG" "$VERIFIED_FLAG" "$SKIP_FLAG"
    if [ "$RC" -eq 0 ]; then
        info "全部证书处理完成"
    else
        error "处理完成,但存在失败项"
    fi
    return "$RC"
}

do_check() {
    require_tools
    check_log_writable
    info "接口地址  : $API_BASE"
    info "用户 UID  : $API_UID"
    info "证书保存  : $OUT_DIR (平铺: 域名.crt.pem / 域名.key.pem; 泛域名保存为 wild.域名.crt.pem)"
    info "证书订单  : ${ORDER_LIST:-未配置}"
    ts=$(date +%s)
    sign=$(md5_hex "${API_UID}${ts}${API_KEY}")
    info "签名样例  : md5(${API_UID}${ts}<API密钥>) = $sign"
    if have openssl; then
        info "证书校验  : 已安装 openssl,将校验 X.509 结构、有效期与私钥匹配"
    else
        warn "证书校验  : 未安装 openssl,只校验 PEM 结构(建议安装 openssl 以获得完整校验)"
    fi
    if [ "$RENEW_DAYS" -gt 0 ]; then
        info "下载策略  : 按需下载(本地证书剩余不足 $RENEW_DAYS 天才下载; 自检本次会强制下载一次)"
    else
        info "下载策略  : 每次都下载并校验(设 RENEW_DAYS>0 可改为按需下载,适合每日 cron)"
    fi
    if [ -z "$ORDER_LIST" ]; then
        die "请在配置区填写 CERT_IDS(SSL证书订单ID),或使用 -i <ID>"
    fi
    acquire_lock
    CHANGED_FLAG=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert-changed.XXXXXX")
    VERIFIED_FLAG=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert-ok.XXXXXX")
    SKIP_FLAG=$(mktemp "${TMPDIR:-/tmp}/dnsmgr-cert-skip.XXXXXX")
    init_modules
    set -- $ORDER_LIST
    FORCE_DOWNLOAD=1   # check 是自检: 忽略按需下载阈值,强制真实下载并校验一次
    fetch_one "$1"
    st=$?
    if [ "$st" -eq 0 ] && have_verified; then
        run_modules final || st=1
    fi
    rm -f "$CHANGED_FLAG" "$VERIFIED_FLAG" "$SKIP_FLAG"
    return "$st"
}

do_modules() {
    _en=$(printf '%s' "$MODULES" | sed 's/^ *//; s/  */ /g; s/ $//')
    echo "$PROG v$VERSION 可用模块 (当前启用: ${_en:-无})"
    echo
    printf "%-10s %-12s %s\n" "模块" "阶段" "[状态] 执行时机 / 说明"
    for _fn in $(declare -F | awk '{print $3}' | grep '^module_' | sort); do
        _rest=${_fn#module_}
        _m="" _p=""
        # 模块名可以包含下划线,所以用已知阶段名做后缀匹配来反推模块名
        for _phase in $PHASES; do
            case $_rest in
                *_${_phase}) _m=${_rest%_${_phase}}; _p=$_phase; break ;;
            esac
        done
        [ -n "$_m" ] || continue
        _state="未启用"
        case " $MODULES " in
            *" $_m "*) _state="已启用" ;;
        esac
        case $_p in
            init)          _when="初始化检查" ;;
            pre_download)  _when="请求接口前" ;;
            post_download) _when="下载校验后" ;;
            on_change)     _when="证书有更新时" ;;
            final)         _when="全部完成后" ;;
            *)             _when="未登记阶段" ;;
        esac
        case $_m in
            custom_cmd) _tip="预设模块 下载后执行 CUSTOM_CMD" ;;
            reload)     _tip="内置模块 有更新时执行 RELOAD_CMD" ;;
            notify)     _tip="内置模块 临期时执行 NOTIFY_CMD" ;;
            *)          _tip="自写模块 在本脚本写 module_<模块名>_<阶段>() 并加进 MODULES" ;;
        esac
        printf "%-12s %-14s [%s] %s - %s\n" "$_m" "$_p" "$_state" "$_when" "$_tip"
    done
    echo
    echo "模块可读取的上下文变量: CERT_ID CERT_DOMAIN CERT_DIR CERT_FILE KEY_FILE"
    echo "                        CERT_ISSUE CERT_EXPIRE CERT_CHANGED CERT_VERIFIED MODULE_PHASE"
    echo "扩展动作: 在本脚本里另写 module_<模块名>_<阶段>() 函数并加进 MODULES 即可生效,"
    echo "          原「自定义模块区」(user 模块 / USER_MODULE)已在 v3.0 移除,单条动作用 custom_cmd;"
    echo "          post_download / on_change / final 都在证书下载完成并通过校验之后才触发。"
}

do_list() {
    require_tools
    acquire_lock
    api_post "/api/cert/list" ""
    api_ok
    info "证书订单列表(该接口未收录在文档中,结果仅供参考):"
    if have python3; then
        printf '%s\n' "$RESP_BODY" | python3 -m json.tool
        if [ $? -ne 0 ]; then
            printf '%s\n' "$RESP_BODY"
        fi
    else
        printf '%s\n' "$RESP_BODY"
    fi
}

case $ACTION in
    check)   do_check ;;
    modules) do_modules ;;
    list)    do_list ;;
    *)       do_download ;;
esac
exit $?

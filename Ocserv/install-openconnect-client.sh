#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="openconnect-client"
CONFIG_DIR="/etc/openconnect-client"
CONFIG_FILE="${CONFIG_DIR}/client.conf"
PASSWORD_FILE="${CONFIG_DIR}/client.password"
RUNNER="/usr/local/sbin/openconnect-client-run"
CTL="/usr/local/sbin/openconnect-client"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

DEFAULT_SERVER="itg6.ixnic.net:2443"
DEFAULT_USERNAME="cmcc"
DEFAULT_PROTOCOL="anyconnect"

info() {
    printf '\033[1;32m[INFO]\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

die() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ ${EUID} -eq 0 ]] || die "请使用 root 权限运行：sudo $0 ${1:-install}"
}

install_client() {
    local server username protocol password servercert answer

    info "开始安装 OpenConnect 客户端……"

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y openconnect vpnc-scripts ca-certificates

    read -r -p "服务器地址 [${DEFAULT_SERVER}]: " server
    server="${server:-$DEFAULT_SERVER}"

    read -r -p "用户名 [${DEFAULT_USERNAME}]: " username
    username="${username:-$DEFAULT_USERNAME}"

    read -r -p "协议 [${DEFAULT_PROTOCOL}]: " protocol
    protocol="${protocol:-$DEFAULT_PROTOCOL}"

    while true; do
        read -r -s -p "请输入 VPN 密码: " password
        printf '\n'

        [[ -n "$password" ]] || {
            warn "密码不能为空"
            continue
        }

        read -r -s -p "请再次输入 VPN 密码: " password_confirm
        printf '\n'

        if [[ "$password" == "$password_confirm" ]]; then
            break
        fi

        warn "两次输入的密码不一致，请重新输入"
    done

    printf '\n'
    info "可选：固定服务器证书可以防止证书被替换。"
    info "格式示例：pin-sha256:AbCdEf..."
    read -r -p "服务器证书指纹，留空则不设置: " servercert

    install -d -m 700 "$CONFIG_DIR"

    {
        printf 'SERVER=%q\n' "$server"
        printf 'USERNAME=%q\n' "$username"
        printf 'PROTOCOL=%q\n' "$protocol"
        printf 'SERVERCERT=%q\n' "$servercert"
        printf 'PASSWORD_FILE=%q\n' "$PASSWORD_FILE"
        printf 'VPN_SCRIPT=%q\n' "/usr/share/vpnc-scripts/vpnc-script"
        printf 'RECONNECT_TIMEOUT=%q\n' "30"
    } > "$CONFIG_FILE"

    printf '%s\n' "$password" > "$PASSWORD_FILE"

    chown root:root "$CONFIG_FILE" "$PASSWORD_FILE"
    chmod 600 "$CONFIG_FILE" "$PASSWORD_FILE"

    unset password password_confirm

    cat > "$RUNNER" <<'RUNNER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="/etc/openconnect-client/client.conf"

log() {
    printf '[openconnect-client] %s\n' "$*"
}

die() {
    log "错误：$*"
    exit 1
}

[[ ${EUID} -eq 0 ]] || die "必须以 root 身份运行"
[[ -r "$CONFIG_FILE" ]] || die "配置文件不存在：${CONFIG_FILE}"

# 该文件仅允许 root 读取。
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${SERVER:?未配置 SERVER}"
: "${USERNAME:?未配置 USERNAME}"
: "${PROTOCOL:=anyconnect}"
: "${PASSWORD_FILE:=/etc/openconnect-client/client.password}"
: "${VPN_SCRIPT:=/usr/share/vpnc-scripts/vpnc-script}"
: "${RECONNECT_TIMEOUT:=30}"
: "${SERVERCERT:=}"

command -v openconnect >/dev/null 2>&1 ||
    die "未安装 openconnect"

[[ -r "$PASSWORD_FILE" ]] ||
    die "密码文件不存在或不可读：${PASSWORD_FILE}"

[[ -x "$VPN_SCRIPT" ]] ||
    die "vpnc-script 不存在或不可执行：${VPN_SCRIPT}"

args=(
    "--protocol=${PROTOCOL}"
    "--user=${USERNAME}"
    "--passwd-on-stdin"
    "--reconnect-timeout=${RECONNECT_TIMEOUT}"
    "--script=${VPN_SCRIPT}"
    "--syslog"
)

if [[ -n "$SERVERCERT" ]]; then
    args+=("--servercert=${SERVERCERT}")
fi

log "正在连接服务器 ${SERVER}"

# 不使用 --background，让 systemd 直接监控实际 OpenConnect 进程。
exec openconnect "${args[@]}" "$SERVER" < "$PASSWORD_FILE"
RUNNER_EOF

    chmod 750 "$RUNNER"
    chown root:root "$RUNNER"

    cat > "$CTL" <<'CTL_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="openconnect-client.service"

usage() {
    cat <<EOF
用法：$(basename "$0") {start|stop|restart|status|logs|enable|disable}

  start      启动 VPN
  stop       停止 VPN
  restart    重启 VPN
  status     查看状态
  logs       实时查看日志
  enable     设置开机启动并立即启动
  disable    取消开机启动并停止
EOF
}

case "${1:-}" in
    start)
        systemctl start "$SERVICE"
        ;;
    stop)
        systemctl stop "$SERVICE"
        ;;
    restart)
        systemctl restart "$SERVICE"
        ;;
    status)
        systemctl status "$SERVICE" --no-pager
        ;;
    logs)
        journalctl -u "$SERVICE" -f
        ;;
    enable)
        systemctl enable --now "$SERVICE"
        ;;
    disable)
        systemctl disable --now "$SERVICE"
        ;;
    *)
        usage
        exit 2
        ;;
esac
CTL_EOF

    chmod 755 "$CTL"
    chown root:root "$CTL"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=OpenConnect VPN Client
Documentation=man:openconnect(8)
Wants=network-online.target
After=network-online.target nss-lookup.target
ConditionPathExists=${CONFIG_FILE}
ConditionPathExists=${PASSWORD_FILE}

[Service]
Type=simple
ExecStart=${RUNNER}
Restart=always
RestartSec=10
TimeoutStartSec=60
TimeoutStopSec=20
KillSignal=SIGTERM

# 基本安全限制
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SERVICE_FILE"
    chown root:root "$SERVICE_FILE"

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"

    read -r -p "是否立即启动 VPN？[Y/n]: " answer
    case "${answer:-Y}" in
        [Nn]*)
            info "安装完成，暂未启动"
            ;;
        *)
            systemctl restart "$SERVICE_NAME"

            sleep 2
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                info "OpenConnect 服务已启动"
            else
                warn "服务启动失败，请检查日志："
                systemctl status "$SERVICE_NAME" --no-pager || true
                journalctl -u "$SERVICE_NAME" -n 30 --no-pager || true
                exit 1
            fi
            ;;
    esac

    print_usage
}

uninstall_client() {
    local answer

    warn "即将删除 OpenConnect 客户端服务及本地认证配置。"
    read -r -p "确定继续吗？输入 YES 确认: " answer

    [[ "$answer" == "YES" ]] || {
        info "已取消卸载"
        return 0
    }

    systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true

    rm -f "$SERVICE_FILE"
    rm -f "$RUNNER"
    rm -f "$CTL"
    rm -rf "$CONFIG_DIR"

    systemctl daemon-reload
    systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true

    info "OpenConnect 客户端配置已删除"
    info "openconnect 和 vpnc-scripts 软件包未被卸载"
}

print_usage() {
    cat <<EOF

安装完成。

常用命令：

  openconnect-client status
  openconnect-client start
  openconnect-client stop
  openconnect-client restart
  openconnect-client logs

systemd 命令：

  systemctl status ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -f

配置文件：

  ${CONFIG_FILE}
  ${PASSWORD_FILE}

重新配置：

  sudo $0 install

卸载：

  sudo $0 uninstall
EOF
}

show_status() {
    if [[ -f "$SERVICE_FILE" ]]; then
        systemctl status "$SERVICE_NAME" --no-pager
    else
        die "尚未安装 OpenConnect 客户端"
    fi
}

main() {
    require_root "${1:-install}"

    case "${1:-install}" in
        install)
            install_client
            ;;
        uninstall)
            uninstall_client
            ;;
        status)
            show_status
            ;;
        *)
            cat <<EOF
用法：sudo $0 [install|uninstall|status]

  install     安装或重新配置
  uninstall   删除服务及认证配置
  status      查看服务状态
EOF
            exit 2
            ;;
    esac
}

main "$@"
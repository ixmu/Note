#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
# OpenConnect Debian VPN Gateway Installer
# ============================================================

SERVICE_NAME="openconnect-gateway"
SERVICE_UNIT="${SERVICE_NAME}.service"

CONFIG_DIR="/etc/openconnect-gateway"
CONFIG_FILE="${CONFIG_DIR}/client.conf"
PASSWORD_FILE="${CONFIG_DIR}/client.password"

RUNNER="/usr/local/sbin/openconnect-gateway-run"
CONTROL="/usr/local/sbin/openconnect-gateway"
FIREWALL_HELPER="/usr/local/libexec/openconnect-gateway-firewall"
VPN_SCRIPT_WRAPPER="/usr/local/libexec/openconnect-gateway-vpnc-script"

SERVICE_FILE="/etc/systemd/system/${SERVICE_UNIT}"
SYSCTL_FILE="/etc/sysctl.d/90-openconnect-gateway.conf"

RUNTIME_DIR="/run/openconnect-gateway"
INTERFACE_STATE_FILE="${RUNTIME_DIR}/vpn-interface"

ORIGINAL_VPN_SCRIPT="/usr/share/vpnc-scripts/vpnc-script"

DEFAULT_PROTOCOL="anyconnect"
DEFAULT_LAN_SUBNET="192.168.1.0/24"
DEFAULT_VPN_INTERFACE="tun0"
DEFAULT_RECONNECT_TIMEOUT="30"

# ------------------------------------------------------------
# 公共函数
# ------------------------------------------------------------

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
    if [[ ${EUID} -ne 0 ]]; then
        die "请使用 root 权限运行：sudo $0 ${1:-install}"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

validate_ipv4_cidr() {
    local cidr="$1"
    local address prefix
    local -a octets
    local octet

    [[ "$cidr" == */* ]] || return 1

    address="${cidr%/*}"
    prefix="${cidr#*/}"

    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 )) || return 1

    IFS='.' read -r -a octets <<< "$address"
    [[ ${#octets[@]} -eq 4 ]] || return 1

    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
    done
}

validate_interface_name() {
    local interface="$1"

    [[ "$interface" =~ ^[a-zA-Z0-9_.:-]{1,15}$ ]]
}

prompt_required() {
    local prompt="$1"
    local value

    while true; do
        read -r -p "$prompt" value

        if [[ -n "$value" ]]; then
            printf '%s\n' "$value"
            return 0
        fi

        warn "该项不能为空"
    done
}

prompt_password() {
    local password password_confirm

    while true; do
        read -r -s -p "VPN 密码: " password
        printf '\n'

        [[ -n "$password" ]] || {
            warn "密码不能为空"
            continue
        }

        read -r -s -p "再次输入 VPN 密码: " password_confirm
        printf '\n'

        if [[ "$password" == "$password_confirm" ]]; then
            printf '%s' "$password"
            return 0
        fi

        warn "两次输入的密码不一致，请重新输入"
    done
}

# ------------------------------------------------------------
# 安装依赖
# ------------------------------------------------------------

install_packages() {
    info "更新 Debian 软件包索引……"

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    info "安装 OpenConnect、iptables 和 vpnc-scripts……"

    apt-get install -y \
        openconnect \
        vpnc-scripts \
        iptables \
        iproute2 \
        ca-certificates

    command_exists openconnect ||
        die "OpenConnect 安装失败"

    command_exists iptables ||
        die "iptables 安装失败"

    [[ -x "$ORIGINAL_VPN_SCRIPT" ]] ||
        die "找不到 vpnc-script：${ORIGINAL_VPN_SCRIPT}"
}

# ------------------------------------------------------------
# 写入配置
# ------------------------------------------------------------

write_config() {
    local server="$1"
    local username="$2"
    local protocol="$3"
    local lan_subnet="$4"
    local vpn_interface="$5"
    local servercert="$6"
    local password="$7"

    install -d -m 700 -o root -g root "$CONFIG_DIR"

    {
        printf 'SERVER=%q\n' "$server"
        printf 'USERNAME=%q\n' "$username"
        printf 'PROTOCOL=%q\n' "$protocol"
        printf 'LAN_SUBNET=%q\n' "$lan_subnet"
        printf 'VPN_INTERFACE=%q\n' "$vpn_interface"
        printf 'SERVERCERT=%q\n' "$servercert"
        printf 'PASSWORD_FILE=%q\n' "$PASSWORD_FILE"
        printf 'RECONNECT_TIMEOUT=%q\n' "$DEFAULT_RECONNECT_TIMEOUT"
        printf 'ORIGINAL_VPN_SCRIPT=%q\n' "$ORIGINAL_VPN_SCRIPT"
    } > "$CONFIG_FILE"

    printf '%s\n' "$password" > "$PASSWORD_FILE"

    chown root:root "$CONFIG_FILE" "$PASSWORD_FILE"
    chmod 600 "$CONFIG_FILE" "$PASSWORD_FILE"
}

# ------------------------------------------------------------
# 开启 IPv4 转发
# ------------------------------------------------------------

install_sysctl_config() {
    info "启用 IPv4 数据包转发……"

    cat > "$SYSCTL_FILE" <<'EOF'
# OpenConnect VPN gateway
net.ipv4.ip_forward = 1
EOF

    chown root:root "$SYSCTL_FILE"
    chmod 644 "$SYSCTL_FILE"

    sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

# ------------------------------------------------------------
# 防火墙管理脚本
# ------------------------------------------------------------

install_firewall_helper() {
    install -d -m 755 -o root -g root /usr/local/libexec

    cat > "$FIREWALL_HELPER" <<'FIREWALL_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

CONFIG_FILE="/etc/openconnect-gateway/client.conf"
RUNTIME_DIR="/run/openconnect-gateway"
INTERFACE_STATE_FILE="${RUNTIME_DIR}/vpn-interface"

log() {
    logger -t openconnect-gateway-firewall -- "$*"
    printf '[openconnect-firewall] %s\n' "$*" >&2
}

die() {
    log "错误：$*"
    exit 1
}

[[ ${EUID} -eq 0 ]] ||
    die "必须以 root 身份运行"

[[ -r "$CONFIG_FILE" ]] ||
    die "配置文件不存在：${CONFIG_FILE}"

# 配置文件由安装程序生成且仅允许 root 读取。
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${LAN_SUBNET:?未配置 LAN_SUBNET}"
: "${VPN_INTERFACE:=tun0}"

IPTABLES="$(command -v iptables || true)"

[[ -n "$IPTABLES" ]] ||
    die "找不到 iptables"

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"

ipt() {
    "$IPTABLES" -w 10 "$@"
}

rule_exists() {
    local table="$1"
    shift

    ipt -t "$table" -C "$@" >/dev/null 2>&1
}

insert_rule() {
    local table="$1"
    shift

    if ! rule_exists "$table" "$@"; then
        ipt -t "$table" -I "$@"
    fi
}

append_rule() {
    local table="$1"
    shift

    if ! rule_exists "$table" "$@"; then
        ipt -t "$table" -A "$@"
    fi
}

delete_rule() {
    local table="$1"
    shift

    while rule_exists "$table" "$@"; do
        ipt -t "$table" -D "$@" || break
    done
}

get_interface() {
    local requested="${1:-}"

    if [[ -n "$requested" ]]; then
        printf '%s\n' "$requested"
    elif [[ -r "$INTERFACE_STATE_FILE" ]]; then
        cat "$INTERFACE_STATE_FILE"
    else
        printf '%s\n' "$VPN_INTERFACE"
    fi
}

add_rules() {
    local interface

    interface="$(get_interface "${1:-}")"

    [[ -n "$interface" ]] ||
        die "无法确定 VPN 接口"

    printf '%s\n' "$interface" > "$INTERFACE_STATE_FILE"
    chmod 600 "$INTERFACE_STATE_FILE"

    # 确保内核转发已开启。
    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    log "添加转发规则：LAN=${LAN_SUBNET}，VPN=${interface}"

    # LAN 客户端通过 VPN 出口时执行源地址转换。
    append_rule nat \
        POSTROUTING \
        -s "$LAN_SUBNET" \
        -o "$interface" \
        -m comment \
        --comment "openconnect-gateway-nat" \
        -j MASQUERADE

    # 放行局域网到 VPN 的新连接及后续流量。
    insert_rule filter \
        FORWARD \
        -s "$LAN_SUBNET" \
        -o "$interface" \
        -m comment \
        --comment "openconnect-gateway-forward-out" \
        -j ACCEPT

    # 只允许 VPN 返回已建立或相关的连接。
    insert_rule filter \
        FORWARD \
        -i "$interface" \
        -d "$LAN_SUBNET" \
        -m conntrack \
        --ctstate ESTABLISHED,RELATED \
        -m comment \
        --comment "openconnect-gateway-forward-in" \
        -j ACCEPT

    # 避免 VPN MTU 较小时出现网页部分加载失败等问题。
    insert_rule mangle \
        FORWARD \
        -s "$LAN_SUBNET" \
        -o "$interface" \
        -p tcp \
        --tcp-flags SYN,RST SYN \
        -m comment \
        --comment "openconnect-gateway-tcpmss" \
        -j TCPMSS \
        --clamp-mss-to-pmtu

    log "iptables 规则添加完成"
}

delete_rules_for_interface() {
    local interface="$1"

    [[ -n "$interface" ]] || return 0

    log "删除接口 ${interface} 的转发规则"

    delete_rule mangle \
        FORWARD \
        -s "$LAN_SUBNET" \
        -o "$interface" \
        -p tcp \
        --tcp-flags SYN,RST SYN \
        -m comment \
        --comment "openconnect-gateway-tcpmss" \
        -j TCPMSS \
        --clamp-mss-to-pmtu

    delete_rule filter \
        FORWARD \
        -i "$interface" \
        -d "$LAN_SUBNET" \
        -m conntrack \
        --ctstate ESTABLISHED,RELATED \
        -m comment \
        --comment "openconnect-gateway-forward-in" \
        -j ACCEPT

    delete_rule filter \
        FORWARD \
        -s "$LAN_SUBNET" \
        -o "$interface" \
        -m comment \
        --comment "openconnect-gateway-forward-out" \
        -j ACCEPT

    delete_rule nat \
        POSTROUTING \
        -s "$LAN_SUBNET" \
        -o "$interface" \
        -m comment \
        --comment "openconnect-gateway-nat" \
        -j MASQUERADE
}

delete_rules() {
    local requested="${1:-}"
    local interface

    interface="$(get_interface "$requested")"
    delete_rules_for_interface "$interface"

    # 如果保存的接口和配置接口不同，也清理配置接口的旧规则。
    if [[ "$interface" != "$VPN_INTERFACE" ]]; then
        delete_rules_for_interface "$VPN_INTERFACE"
    fi

    rm -f "$INTERFACE_STATE_FILE"
    log "iptables 规则清理完成"
}

show_rules() {
    printf '%s\n' "IPv4 forwarding:"
    sysctl net.ipv4.ip_forward

    printf '\n%s\n' "NAT rules:"
    ipt -t nat -S POSTROUTING |
        grep -F "openconnect-gateway-" || true

    printf '\n%s\n' "FORWARD rules:"
    ipt -t filter -S FORWARD |
        grep -F "openconnect-gateway-" || true

    printf '\n%s\n' "Mangle rules:"
    ipt -t mangle -S FORWARD |
        grep -F "openconnect-gateway-" || true
}

case "${1:-}" in
    add)
        add_rules "${2:-}"
        ;;
    delete|del|remove)
        delete_rules "${2:-}"
        ;;
    status)
        show_rules
        ;;
    *)
        cat >&2 <<EOF
用法：$(basename "$0") {add [VPN接口]|delete [VPN接口]|status}
EOF
        exit 2
        ;;
esac
FIREWALL_EOF

    chown root:root "$FIREWALL_HELPER"
    chmod 750 "$FIREWALL_HELPER"
}

# ------------------------------------------------------------
# vpnc-script 包装器
# ------------------------------------------------------------

install_vpnc_wrapper() {
    cat > "$VPN_SCRIPT_WRAPPER" <<'VPN_WRAPPER_EOF'
#!/usr/bin/env bash
set -u

CONFIG_FILE="/etc/openconnect-gateway/client.conf"
FIREWALL_HELPER="/usr/local/libexec/openconnect-gateway-firewall"
DEFAULT_VPN_SCRIPT="/usr/share/vpnc-scripts/vpnc-script"

log() {
    logger -t openconnect-gateway-vpnc -- "$*"
    printf '[openconnect-vpnc] %s\n' "$*" >&2
}

if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

ORIGINAL_VPN_SCRIPT="${ORIGINAL_VPN_SCRIPT:-$DEFAULT_VPN_SCRIPT}"
VPN_INTERFACE="${VPN_INTERFACE:-tun0}"

if [[ ! -x "$ORIGINAL_VPN_SCRIPT" ]]; then
    log "找不到原始 vpnc-script：${ORIGINAL_VPN_SCRIPT}"
    exit 1
fi

# OpenConnect/vpnc-script 通常通过 TUNDEV 传递真实接口名称。
vpn_device="${TUNDEV:-$VPN_INTERFACE}"

case "${reason:-unknown}" in
    connect|reconnect)
        # 先创建接口、地址和路由。
        "$ORIGINAL_VPN_SCRIPT" "$@"
        result=$?

        if (( result == 0 )); then
            "$FIREWALL_HELPER" add "$vpn_device" || {
                log "添加防火墙规则失败"
                exit 1
            }
        fi

        exit "$result"
        ;;

    disconnect)
        # 在接口被官方脚本删除前清理规则。
        "$FIREWALL_HELPER" delete "$vpn_device" || true
        exec "$ORIGINAL_VPN_SCRIPT" "$@"
        ;;

    *)
        exec "$ORIGINAL_VPN_SCRIPT" "$@"
        ;;
esac
VPN_WRAPPER_EOF

    chown root:root "$VPN_SCRIPT_WRAPPER"
    chmod 750 "$VPN_SCRIPT_WRAPPER"
}

# ------------------------------------------------------------
# OpenConnect 执行脚本
# ------------------------------------------------------------

install_runner() {
    cat > "$RUNNER" <<'RUNNER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

CONFIG_FILE="/etc/openconnect-gateway/client.conf"
PASSWORD_FILE_DEFAULT="/etc/openconnect-gateway/client.password"
VPN_SCRIPT_WRAPPER="/usr/local/libexec/openconnect-gateway-vpnc-script"

log() {
    logger -t openconnect-gateway -- "$*"
    printf '[openconnect-gateway] %s\n' "$*"
}

die() {
    log "错误：$*"
    exit 1
}

[[ ${EUID} -eq 0 ]] ||
    die "必须以 root 身份运行"

[[ -r "$CONFIG_FILE" ]] ||
    die "配置文件不存在：${CONFIG_FILE}"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${SERVER:?未配置 SERVER}"
: "${USERNAME:?未配置 USERNAME}"
: "${PROTOCOL:=anyconnect}"
: "${PASSWORD_FILE:=$PASSWORD_FILE_DEFAULT}"
: "${RECONNECT_TIMEOUT:=30}"
: "${SERVERCERT:=}"

command -v openconnect >/dev/null 2>&1 ||
    die "未安装 OpenConnect"

[[ -r "$PASSWORD_FILE" ]] ||
    die "密码文件不存在或不可读：${PASSWORD_FILE}"

[[ -x "$VPN_SCRIPT_WRAPPER" ]] ||
    die "VPN 生命周期脚本不可执行：${VPN_SCRIPT_WRAPPER}"

args=(
    "--protocol=${PROTOCOL}"
    "--user=${USERNAME}"
    "--passwd-on-stdin"
    "--reconnect-timeout=${RECONNECT_TIMEOUT}"
    "--script=${VPN_SCRIPT_WRAPPER}"
    "--syslog"
)

if [[ -n "$SERVERCERT" ]]; then
    args+=("--servercert=${SERVERCERT}")
fi

log "正在连接 VPN 服务器 ${SERVER}"

# 保持前台运行，让 systemd 直接监控 OpenConnect。
exec openconnect "${args[@]}" "$SERVER" < "$PASSWORD_FILE"
RUNNER_EOF

    chown root:root "$RUNNER"
    chmod 750 "$RUNNER"
}

# ------------------------------------------------------------
# systemd 服务
# ------------------------------------------------------------

install_systemd_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=OpenConnect VPN Gateway
Documentation=man:openconnect(8)
Wants=network-online.target
After=network-online.target nss-lookup.target
ConditionPathExists=${CONFIG_FILE}
ConditionPathExists=${PASSWORD_FILE}

[Service]
Type=simple
ExecStartPre=${FIREWALL_HELPER} delete
ExecStart=${RUNNER}
ExecStopPost=${FIREWALL_HELPER} delete
Restart=always
RestartSec=10
TimeoutStartSec=90
TimeoutStopSec=30
KillSignal=SIGTERM

NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

    chown root:root "$SERVICE_FILE"
    chmod 644 "$SERVICE_FILE"

    systemctl daemon-reload
}

# ------------------------------------------------------------
# 控制命令
# ------------------------------------------------------------

install_control_command() {
    cat > "$CONTROL" <<'CONTROL_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="openconnect-gateway.service"
FIREWALL_HELPER="/usr/local/libexec/openconnect-gateway-firewall"
CONFIG_FILE="/etc/openconnect-gateway/client.conf"
PASSWORD_FILE="/etc/openconnect-gateway/client.password"

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        printf '请使用 sudo 运行该命令\n' >&2
        exit 1
    fi
}

usage() {
    cat <<EOF
用法：$(basename "$0") COMMAND

命令：
  start       启动 VPN
  stop        停止 VPN
  restart     重启 VPN
  status      查看 VPN 和防火墙状态
  logs        实时查看日志
  enable      设置开机启动并立即启动
  disable     停止并取消开机启动
  firewall    查看 NAT 和 FORWARD 规则
  config      查看配置文件（不显示密码）
  test        检查 IP 转发、接口和规则
EOF
}

require_root

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
        systemctl status "$SERVICE" --no-pager || true
        printf '\n'
        "$FIREWALL_HELPER" status
        ;;

    logs)
        exec journalctl -u "$SERVICE" -f
        ;;

    enable)
        systemctl enable --now "$SERVICE"
        ;;

    disable)
        systemctl disable --now "$SERVICE"
        ;;

    firewall)
        "$FIREWALL_HELPER" status
        ;;

    config)
        if [[ -r "$CONFIG_FILE" ]]; then
            cat "$CONFIG_FILE"
        else
            printf '配置文件不存在：%s\n' "$CONFIG_FILE" >&2
            exit 1
        fi
        ;;

    test)
        printf '%s\n' "===== 服务状态 ====="
        systemctl is-active "$SERVICE" || true

        printf '\n%s\n' "===== IPv4 转发 ====="
        sysctl net.ipv4.ip_forward

        printf '\n%s\n' "===== 网络接口 ====="
        ip -brief address

        printf '\n%s\n' "===== 路由表 ====="
        ip -4 route

        printf '\n%s\n' "===== OpenConnect 防火墙规则 ====="
        "$FIREWALL_HELPER" status
        ;;

    *)
        usage
        exit 2
        ;;
esac
CONTROL_EOF

    chown root:root "$CONTROL"
    chmod 755 "$CONTROL"
}

# ------------------------------------------------------------
# 安装流程
# ------------------------------------------------------------

install_gateway() {
    local server username protocol
    local lan_subnet vpn_interface
    local servercert password answer

    info "OpenConnect Debian VPN 网关安装程序"
    printf '\n'

    install_packages

    # 重新安装时先停止旧服务。
    if systemctl list-unit-files "$SERVICE_UNIT" \
        --no-legend 2>/dev/null | grep -q "^${SERVICE_UNIT}"; then
        info "停止现有 OpenConnect 服务……"
        systemctl stop "$SERVICE_UNIT" 2>/dev/null || true
    fi

    printf '\n'
    server="$(prompt_required "VPN 服务器地址，例如 vpn.example.com:443: ")"

    read -r -p "VPN 用户名: " username
    while [[ -z "$username" ]]; do
        warn "用户名不能为空"
        read -r -p "VPN 用户名: " username
    done

    read -r -p "VPN 协议 [${DEFAULT_PROTOCOL}]: " protocol
    protocol="${protocol:-$DEFAULT_PROTOCOL}"

    while true; do
        read -r -p "局域网网段 [${DEFAULT_LAN_SUBNET}]: " lan_subnet
        lan_subnet="${lan_subnet:-$DEFAULT_LAN_SUBNET}"

        if validate_ipv4_cidr "$lan_subnet"; then
            break
        fi

        warn "无效的 IPv4 CIDR，例如：192.168.1.0/24"
    done

    while true; do
        read -r -p "默认 VPN 接口 [${DEFAULT_VPN_INTERFACE}]: " vpn_interface
        vpn_interface="${vpn_interface:-$DEFAULT_VPN_INTERFACE}"

        if validate_interface_name "$vpn_interface"; then
            break
        fi

        warn "无效的网络接口名称"
    done

    printf '\n'
    info "可选：配置服务器证书指纹可防止连接到错误服务器。"
    info "示例：pin-sha256:BASE64_HASH"
    read -r -p "服务器证书指纹（留空不设置）: " servercert

    printf '\n'
    password="$(prompt_password)"
    printf '\n'

    write_config \
        "$server" \
        "$username" \
        "$protocol" \
        "$lan_subnet" \
        "$vpn_interface" \
        "$servercert" \
        "$password"

    unset password

    install_sysctl_config
    install_firewall_helper
    install_vpnc_wrapper
    install_runner
    install_control_command
    install_systemd_service

    systemctl enable "$SERVICE_UNIT"

    printf '\n'
    read -r -p "是否立即启动 VPN？[Y/n]: " answer

    case "${answer:-Y}" in
        [Nn]*)
            info "安装完成，服务暂未启动"
            ;;
        *)
            info "正在启动 OpenConnect VPN……"

            if systemctl restart "$SERVICE_UNIT"; then
                sleep 3
            fi

            if systemctl is-active --quiet "$SERVICE_UNIT"; then
                info "OpenConnect VPN 服务已启动"
            else
                warn "VPN 服务未能正常启动"
                systemctl status "$SERVICE_UNIT" --no-pager || true
                journalctl -u "$SERVICE_UNIT" -n 50 --no-pager || true
                return 1
            fi
            ;;
    esac

    cat <<EOF

============================================================
安装完成
============================================================

配置文件：
  ${CONFIG_FILE}

密码文件：
  ${PASSWORD_FILE}

常用命令：
  sudo openconnect-gateway status
  sudo openconnect-gateway start
  sudo openconnect-gateway stop
  sudo openconnect-gateway restart
  sudo openconnect-gateway logs
  sudo openconnect-gateway firewall
  sudo openconnect-gateway test

systemd 命令：
  sudo systemctl status ${SERVICE_UNIT}
  sudo journalctl -u ${SERVICE_UNIT} -f

卸载：
  sudo $0 uninstall

局域网网段：
  ${lan_subnet}

重要：
局域网设备必须将本机设置为默认网关，或者为需要通过
VPN 访问的目标网段添加一条指向本机 LAN 地址的静态路由。
EOF
}

# ------------------------------------------------------------
# 卸载流程
# ------------------------------------------------------------

uninstall_gateway() {
    local answer

    warn "即将停止服务并删除 OpenConnect 网关配置。"
    warn "VPN 密码文件也会被删除。"

    read -r -p "输入 YES 确认卸载: " answer

    if [[ "$answer" != "YES" ]]; then
        info "已取消卸载"
        return 0
    fi

    info "停止并禁用服务……"

    systemctl disable --now "$SERVICE_UNIT" 2>/dev/null || true

    if [[ -x "$FIREWALL_HELPER" && -r "$CONFIG_FILE" ]]; then
        "$FIREWALL_HELPER" delete 2>/dev/null || true
    fi

    rm -f "$SERVICE_FILE"
    rm -f "$RUNNER"
    rm -f "$CONTROL"
    rm -f "$FIREWALL_HELPER"
    rm -f "$VPN_SCRIPT_WRAPPER"
    rm -f "$SYSCTL_FILE"
    rm -rf "$CONFIG_DIR"
    rm -rf "$RUNTIME_DIR"

    systemctl daemon-reload
    systemctl reset-failed "$SERVICE_UNIT" 2>/dev/null || true

    # 不主动关闭 ip_forward，避免影响其他路由或容器服务。
    info "卸载完成"
    info "openconnect、iptables 和 vpnc-scripts 软件包未被删除"
    info "net.ipv4.ip_forward 当前值未被强制修改"
}

show_status() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        die "OpenConnect 网关尚未安装"
    fi

    systemctl status "$SERVICE_UNIT" --no-pager || true

    if [[ -x "$FIREWALL_HELPER" ]]; then
        printf '\n'
        "$FIREWALL_HELPER" status
    fi
}

print_usage() {
    cat <<EOF
用法：
  sudo $0 install
  sudo $0 uninstall
  sudo $0 status

命令：
  install      安装或重新配置 OpenConnect VPN 网关
  uninstall    删除服务、认证信息及 iptables 规则
  status       查看服务和防火墙状态
EOF
}

main() {
    require_root

    case "${1:-install}" in
        install)
            install_gateway
            ;;
        uninstall)
            uninstall_gateway
            ;;
        status)
            show_status
            ;;
        help|-h|--help)
            print_usage
            ;;
        *)
            print_usage
            exit 2
            ;;
    esac
}

main "$@"
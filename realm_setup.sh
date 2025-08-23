#!/bin/bash
# Realm 中继服务自动化安装脚本
# 版本: 1.0
# 作者: 基于 ixmu.net 内容编写
# 描述: 自动安装、配置和管理 Realm 中继服务

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置变量
REALM_VERSION="2.9.2"
INSTALL_DIR="/etc/realm"
SERVICE_FILE="/etc/systemd/system/realm.service"
CONFIG_FILE="$INSTALL_DIR/config.toml"

# 输出函数
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本必须以 root 权限运行"
        exit 1
    fi
}

# 检查系统架构
check_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            REALM_ARCH="x86_64-unknown-linux-gnu"
            ;;
        aarch64|arm64)
            REALM_ARCH="aarch64-unknown-linux-gnu"
            ;;
        *)
            error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    info "系统架构: $ARCH"
}

# 安装依赖
install_dependencies() {
    step "安装必要依赖..."
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y wget tar
    elif command -v yum &> /dev/null; then
        yum install -y wget tar
    elif command -v dnf &> /dev/null; then
        dnf install -y wget tar
    else
        warn "无法识别包管理器，请手动安装 wget 和 tar"
    fi
}

# 下载并安装 Realm
install_realm() {
    step "下载 Realm v$REALM_VERSION..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # 下载 Realm
    DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/v$REALM_VERSION/realm-$REALM_ARCH.tar.gz"
    info "下载地址: $DOWNLOAD_URL"
    
    if ! wget -O realm.tar.gz "$DOWNLOAD_URL"; then
        error "下载失败"
        exit 1
    fi
    
    # 解压安装
    tar -zxvf realm.tar.gz
    chmod +x realm
    rm -f realm.tar.gz
    
    info "Realm 安装完成"
}

# 创建配置文件
create_config() {
    step "创建配置文件..."
    
    cat > "$CONFIG_FILE" << 'EOF'
[network]
no_tcp = false
use_udp = false

# 服务器端配置 (国外服务器)
[[endpoints]]
listen = "[::]:10443"
remote = "1.1.1.1:443"
listen_transport = "ws;host=your-domain.com;path=/path"

# 客户端配置 (国内服务器)
# [[endpoints]]
# listen = "[::]:10443"
# remote = "your-server-ip:10443"
# remote_transport = "ws;host=your-domain.com;path=/path"
EOF

    warn "请编辑 $CONFIG_FILE 修改配置"
    warn "服务器端需要取消注释第一组 [[endpoints]]"
    warn "客户端需要取消注释第二组 [[endpoints]] 并修改 remote 地址"
}

# 创建 systemd 服务
create_systemd_service() {
    step "创建 systemd 服务..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=realm - Simple, high performance relay service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/realm -c $CONFIG_FILE
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd
    systemctl daemon-reload
    info "systemd 服务创建完成"
}

# 配置防火墙
setup_firewall() {
    step "配置防火墙..."
    
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow 10443/tcp
        info "UFW 已开放端口 10443"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=10443/tcp
        firewall-cmd --reload
        info "FirewallD 已开放端口 10443"
    else
        warn "请手动确保端口 10443 已开放"
    fi
}

# 启动服务
start_service() {
    step "启动 Realm 服务..."
    
    systemctl enable realm
    systemctl start realm
    
    sleep 2
    
    if systemctl is-active --quiet realm

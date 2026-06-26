#!/bin/bash
# Realm 中继服务自动化安装脚本
# 描述: 自动安装、配置和管理 Realm 中继服务

set -e

# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

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

# 1. 检查 root 权限
if [[ $EUID -ne 0 ]]; then error "此脚本必须以 root 权限运行"; exit 1; fi

# 2. 检查系统架构 (修正：增加对 musl 架构的支持判断)
ARCH=$(uname -m)
case $ARCH in
    x86_64)   REALM_ARCH="x86_64-unknown-linux-gnu" ;;
    aarch64)  REALM_ARCH="aarch64-unknown-linux-gnu" ;;
    *)        error "不支持的架构: $ARCH"; exit 1 ;;
esac
info "系统架构: $ARCH"

# 3. 安装依赖
step "安装必要依赖..."
if command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y wget tar
elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
    (command -v dnf &> /dev/null && dnf install -y wget tar) || yum install -y wget tar
fi

# 4. 下载并安装 Realm
step "下载 Realm v$REALM_VERSION..."
mkdir -p "$INSTALL_DIR"
DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/v$REALM_VERSION/realm-$REALM_ARCH.tar.gz"
wget -O "$INSTALL_DIR/realm.tar.gz" "$DOWNLOAD_URL"
cd "$INSTALL_DIR"
tar -zxvf realm.tar.gz
rm -f realm.tar.gz
chmod +x realm
info "Realm 安装完成"

# 5. 创建配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    step "创建默认配置文件..."
    cat > "$CONFIG_FILE" << 'EOF'
[network]
no_tcp = false
use_udp = true

[[endpoints]]
listen = "[::]:10443"
remote = "127.0.0.1:443"
EOF
    warn "配置文件已创建于 $CONFIG_FILE，请按需修改。"
fi

# 6. 创建 systemd 服务
step "创建 systemd 服务..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=realm - Simple, high performance relay service
After=network-online.target

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

systemctl daemon-reload

# 7. 配置防火墙
step "配置防火墙..."
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    ufw allow 10443/tcp && ufw allow 10443/udp
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=10443/tcp
    firewall-cmd --permanent --add-port=10443/udp
    firewall-cmd --reload
fi

# 8. 启动服务与状态验证
step "启动 Realm 服务..."
systemctl enable --now realm
sleep 2

if systemctl is-active --quiet realm; then
    info "=========================================="
    info "Realm 服务已成功启动！"
    info "配置文件路径: $CONFIG_FILE"
    info "查看日志: journalctl -u realm -f"
    info "=========================================="
else
    error "Realm 启动失败，请检查配置或手动运行 $INSTALL_DIR/realm -c $CONFIG_FILE 查看错误。"
    exit 1
fi

#!/bin/bash
set -e

# --- 默认参数设置 ---
PASSWORD="MoeClub"     # Alpine 临时 root 密码 (-p)
TARGET="13"            # 重装目标系统版本 (-d)
TPASSWORD="MoeClub"    # 重装后系统的 root 密码 (--password)
PORT="22"              # SSH 端口 (--port)

# --- 帮助信息 ---
usage() {
    cat << EOF
用法: bash $0 [选项]

选项:
  -p <密码>        Alpine 临时系统密码 (默认: MoeClub)
  -d <版本>        重装目标系统版本 (默认: 13)
  --pwd <密码>     新系统最终密码 (默认: MoeClub)
  --port <端口>    SSH 服务端口 (默认: 22)
  -h, --help       显示此帮助信息

示例:
  bash $0 -p TempPass123 -d 12 --pwd MyRootPass888 --port 2222
EOF
    exit 0
}

# --- 解析命令行参数 ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p)
            PASSWORD="$2"
            shift 2
            ;;
        -d)
            TARGET="$2"
            shift 2
            ;;
        --pwd|--password)
            TPASSWORD="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "错误: 未知参数 $1"
            usage
            ;;
    esac
done

# --- 自动检测系统架构 (仅支持 arm64 和 amd64) ---
RAW_ARCH=$(uname -m)
case "$RAW_ARCH" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "错误: 当前系统架构 (${RAW_ARCH}) 不受支持，仅支持 amd64 与

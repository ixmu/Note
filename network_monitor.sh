#!/bin/bash

# 网络监控脚本 - 单文件版
# 功能：检测IPv4/IPv6网络，异常时重启网络，支持定时任务设置

LOG_FILE="/var/log/network_monitor.log"
SCRIPT_PATH="$(realpath "$0")"

# 显示使用帮助
show_help() {
    echo "网络监控脚本 - Debian 12"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -c, --cron      设置定时任务（每5分钟运行）"
    echo "  -t, --test      测试网络连接"
    echo "  -r, --run       运行一次网络检测"
    echo "  -s, --status    显示当前状态"
    echo "  -h, --help      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --cron       设置定时监控"
    echo "  $0 --test       测试网络功能"
    echo "  $0 --run        手动运行检测"
}

# 记录日志
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | sudo tee -a "$LOG_FILE" > /dev/null
}

# 检测IPv4连接
check_ipv4() {
    if ping -c 2 -W 2 8.8.8.8 > /dev/null 2>&1 || ping -c 2 -W 2 1.1.1.1 > /dev/null 2>&1; then
        log_message "IPv4网络正常"
        return 0
    else
        log_message "IPv4网络异常"
        return 1
    fi
}

# 检测IPv6连接
check_ipv6() {
    if command -v ping6 > /dev/null 2>&1; then
        if ping6 -c 2 -W 2 2001:4860:4860::8888 > /dev/null 2>&1 || ping6 -c 2 -W 2 2606:4700:4700::1111 > /dev/null 2>&1; then
            log_message "IPv6网络正常"
            return 0
        else
            log_message "IPv6网络异常"
            return 1
        fi
    else
        log_message "系统不支持IPv6检测"
        return 0  # 不支持IPv6不算异常
    fi
}

# 重启网络服务
restart_network() {
    log_message "正在重启网络服务..."
    
    if command -v systemctl > /dev/null 2>&1; then
        sudo systemctl restart networking 2>/dev/null || sudo systemctl restart NetworkManager 2>/dev/null
    elif command -v service > /dev/null 2>&1; then
        sudo service networking restart 2>/dev/null || sudo service network-manager restart 2>/dev/null
    else
        sudo /etc/init.d/networking restart 2>/dev/null
    fi
    
    log_message "网络服务重启完成"
    sleep 3  # 给网络服务一些时间恢复
}

# 设置定时任务
setup_cron() {
    local cron_job="*/5 * * * * $SCRIPT_PATH --run"
    
    log_message "正在设置定时任务..."
    
    # 移除旧的定时任务（如果存在）
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    
    # 添加新的定时任务
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    
    log_message "定时任务设置完成：每5分钟运行一次"
    echo "定时任务已设置：每5分钟自动检测网络"
    crontab -l | grep "$SCRIPT_PATH"
}

# 测试网络功能
test_network() {
    echo "=== 网络功能测试 ==="
    echo ""
    
    echo "1. IPv4测试:"
    if ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; then
        echo "   ✓ 8.8.8.8 可达"
    else
        echo "   ✗ 8.8.8.8 不可达"
    fi
    
    if ping -c 1 -W 1 1.1.1.1 > /dev/null 2>&1; then
        echo "   ✓ 1.1.1.1 可达"
    else
        echo "   ✗ 1.1.1.1 不可达"
    fi
    
    echo ""
    echo "2. IPv6测试:"
    if command -v ping6 > /dev/null 2>&1; then
        if ping6 -c 1 -W 1 2001:4860:4860::8888 > /dev/null 2>&1; then
            echo "   ✓ IPv6 Google DNS 可达"
        else
            echo "   ✗ IPv6 Google DNS 不可达"
        fi
    else
        echo "   ℹ ping6 命令不可用，跳过IPv6测试"
    fi
    
    echo ""
    echo "3. 脚本测试:"
    run_detection "test"
    
    echo ""
    echo "=== 测试完成 ==="
}

# 运行网络检测
run_detection() {
    local mode="${1:-normal}"
    
    if [ "$mode" != "test" ]; then
        log_message "开始网络检测"
    fi
    
    local ipv4_ok=0
    local ipv6_ok=0
    
    # 检测IPv4
    if check_ipv4; then
        ipv4_ok=1
    fi
    
    # 检测IPv6
    if check_ipv6; then
        ipv6_ok=1
    fi
    
    # 如果任一网络异常，重启网络
    if [ $ipv4_ok -eq 0 ] || [ $ipv6_ok -eq 0 ]; then
        if [ "$mode" != "test" ]; then
            log_message "检测到网络异常，准备重启网络"
            restart_network
        else
            echo "   ✗ 网络异常检测（测试模式不重启）"
        fi
    else
        if [ "$mode" != "test" ]; then
            log_message "网络连接正常"
        else
            echo "   ✓ 网络连接正常"
        fi
    fi
    
    if [ "$mode" != "test" ]; then
        log_message "网络检测完成"
    fi
}

# 显示状态
show_status() {
    echo "网络监控脚本状态"
    echo "================="
    echo ""
    echo "脚本路径: $SCRIPT_PATH"
    echo "日志文件: $LOG_FILE"
    echo ""
    
    echo "定时任务状态:"
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        echo "  ✓ 已启用（每5分钟运行）"
        crontab -l | grep "$SCRIPT_PATH"
    else
        echo "  ✗ 未启用"
    fi
    
    echo ""
    echo "日志状态:"
    if [ -f "$LOG_FILE" ]; then
        echo "  ✓ 日志文件存在"
        echo "  最后记录:"
        tail -3 "$LOG_FILE" 2>/dev/null || echo "  需要sudo权限查看日志"
    else
        echo "  ✗ 日志文件不存在"
    fi
}

# 主函数
main() {
    case "${1:-}" in
        -c|--cron)
            setup_cron
            ;;
        -t|--test)
            test_network
            ;;
        -r|--run)
            run_detection
            ;;
        -s|--status)
            show_status
            ;;
        -h|--help|"")
            show_help
            ;;
        *)
            echo "错误: 未知选项 '$1'"
            show_help
            exit 1
            ;;
    esac
}

# 确保日志目录存在
sudo mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
sudo touch "$LOG_FILE" 2>/dev/null || true

# 执行主函数
main "$@"

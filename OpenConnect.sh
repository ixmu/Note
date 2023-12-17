#!/bin/sh
# echo "@reboot root /root/OpenConnect.sh >>/dev/null 2>&1 &" >/etc/crontab
# OpenConnect服务器地址和认证信息
server="your_server_address"
username="your_username"
password="your_password"

# NAT规则相关信息
nat_subnet="10.0.0.0/24"
nat_interface="tun0"

# 连接检测间隔（以秒为单位）
check_interval=60

# 检查OpenConnect连接状态的函数
check_connection() {
    if ! pgrep -x "openconnect" >/dev/null; then
        echo "OpenConnect未运行，重新连接..."
        connect
    fi
}

# 检查NAT规则是否存在并添加规则
check_nat_rule() {
    if ! iptables -t nat -C POSTROUTING -s "$nat_subnet" -o "$nat_interface" -j MASQUERADE >/dev/null 2>&1; then
        echo "NAT规则不存在，添加规则..."
        iptables -t nat -A POSTROUTING -s "$nat_subnet" -o "$nat_interface" -j MASQUERADE
        echo "NAT规则已添加"
    fi
}

# 运行OpenConnect连接命令
connect() {
    echo "连接到OpenConnect服务器..."
    echo "$password" | openconnect -b "$server" --user="$username" --passwd-on-stdin
    if [ $? -eq 0 ]; then
        echo "连接成功"
    else
        echo "连接失败"
    fi
}

# 主循环
while true; do
    check_connection
    check_nat_rule
    sleep "$check_interval"
done

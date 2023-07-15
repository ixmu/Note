#!/bin/bash

#生成断网自动重启脚本
cat > /opt/network_monitor.sh<< EOF
#!/bin/bash
while true; do
    if ping -c 1 google.com &> /dev/null; then
        echo "网络连接正常"
    else
        echo "网络连接失败，执行重启操作..."
        reboot
    fi
    sleep 60
done
EOF
chmod +x /opt/network_monitor.sh

# 检查 /etc/crontab 文件是否包含指定的行
if grep -q "@reboot root /opt/network_monitor.sh >>/dev/null 2>&1 &" /etc/crontab; then
    echo "已存在相应的行，跳过操作。"
else
    # 在文件末尾追加指定的内容
    echo "@reboot root /opt/network_monitor.sh >>/dev/null 2>&1 &" | sudo tee -a /etc/crontab > /dev/null
    echo "已成功追加内容到 /etc/crontab 文件。"
fi

# 提示用户按任意键重启
read -p "按下任意键后将执行系统重启操作。请确保您已保存并关闭所有未保存的工作。按下任意键继续..."

# 执行系统重启
sudo reboot
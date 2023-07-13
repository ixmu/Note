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

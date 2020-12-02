#!/bin/bash

#检测用户
[ $EUID -ne 0 ] && echo "Error:This script must be run as root!" && exit 1
#设置ssh端口为22
[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?Port .*/Port 22/g" /etc/ssh/sshd_config;
#允许root登录
[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config;
#禁止密码认证
[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/g" /etc/ssh/sshd_config;
#启用公钥认证
[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g" /etc/ssh/sshd_config;
#设置公钥位置
[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?AuthorizedKeysFile.*/AuthorizedKeysFile \.ssh\/authorized_keys \.ssh\/authorized_keys2/g" /etc/ssh/sshd_config;
#远程下载公钥
[ -d /root/.ssh/ ] && curl -Lso- https://cdn.jsdelivr.net/gh/ixmu/Note/ssh/PubkeyAuthentication > /root/.ssh/authorized_keys
#目录不存在则创建
[ ! -d /root/.ssh/ ] && mkdir /root/.ssh/ && curl -Lso- https://cdn.jsdelivr.net/gh/ixmu/Note/ssh/PubkeyAuthentication > /root/.ssh/authorized_keys
#重启ssh服务
systemctl restart sshd




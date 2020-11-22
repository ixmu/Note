#!/bin/bash
[ $EUID -ne 0 ] && echo "Error:This script must be run as root!" && exit 1
#[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?Port .*/Port 22/g" /etc/ssh/sshd_config;
#[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config;
#[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config;

[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g" /etc/ssh/sshd_config;
[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?AuthorizedKeysFile.*/AuthorizedKeysFile \.ssh\/authorized_keys \.ssh\/authorized_keys2/g" /etc/ssh/sshd_config;

[ -d /root/.ssh/ ] && curl -Lso- https://cdn.jsdelivr.net/gh/ixmu/Note/ssh/PubkeyAuthentication > /root/.ssh/authorized_keys
[ ! -d /root/.ssh/ ] && mkdir /root/.ssh/ && curl -Lso- https://cdn.jsdelivr.net/gh/ixmu/Note/ssh/PubkeyAuthentication > /root/.ssh/authorized_keys

server ssh restart




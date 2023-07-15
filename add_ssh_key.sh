#!/bin/bash
# curl -sSL https://raw.githubusercontent.com/ixmu/Note/master/add_ssh_key.sh |bash
# SSH 公钥内容
ssh_public_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIVVbZkwvMkPxQJsWdQYulS3iFn+tJaWDRw6CTD0i6NZWpfOY+biZlOvwJq4qcEAn5tAHcxXEBhnTtEc/+0y+YvjRx20OBsl6Z2bSabuZ3jGZ1q812mNXAA5f+6S1hHoPgrRDpYhQr2FW6du3wxZDpcgjxoljFYIRpSIHvixlJa1TTKrDLDkRZG4sdjz6K+Cat59qP99dyfU2ym2pH6UPaqSwtGT36VDPo61zB/dxjeYalKmqQGa70SqxJsEn+/DSEht8c/hdRNlE0UpagRxrjTtZ446C5sBlF7uEUPdbAV0EdRXRlhGRYJcKc+VOJvnROTvwJztLf6NGFh2n9H6hB root@iZwz9avyv2945ilt432lffZ"

# 将 SSH 公钥添加到授权密钥文件
mkdir -p ~/.ssh && echo "${ssh_public_key}" >> ~/.ssh/authorized_keys

# 设置权限
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys

# 修改 SSHD 配置文件
sudo sed -i 's/#PubkeyAuthentication/PubkeyAuthentication/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication/PasswordAuthentication no/' /etc/ssh/sshd_config

# 重启 SSH 服务
sudo systemctl restart sshd

echo "SSH 公钥已成功添加到授权密钥文件，并修改了 SSHD 配置。"

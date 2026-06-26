#!/bin/bash

# ==========================================
# 1. 在下方配置你的公钥列表 (每行一个)
# ==========================================
keys=(
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIVVbZkwvMkPxQJsWdQYulS3iFn+tJaWDRw6CTD0i6NZWpfOY+biZlOvwJq4qcEAn5tAHcxXEBhnTtEc/+0y+YvjRx20OBsl6Z2bSabuZ3jGZ1q812mNXAA5f+6S1hHoPgrRDpYhQr2FW6du3wxZDpcgjxoljFYIRpSIHvixlJa1TTKrDLDkRZG4sdjz6K+Cat59qP99dyfU2ym2pH6UPaqSwtGT36VDPo61zB/dxjeYalKmqQGa70SqxJsEn+/DSEht8c/hdRNlE0UpagRxrjTtZ446C5sBlF7uEUPdbAV0EdRXRlhGRYJcKc+VOJvnROTvwJztLf6NGFh2n9H6hB root@iZwz9avyv2945ilt432lffZ"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGb5qLL+txob4mVgaEq6fR1xXQQG3KT81cJpuYrVnO3w pengxp1996@hotmail.com"
)

# ==========================================
# 2. 执行安装逻辑
# ==========================================

# 确保 .ssh 目录存在并设置正确权限
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 循环遍历数组，将公钥写入文件
for key in "${keys[@]}"; do
    # 检查密钥是否已经存在，防止重复写入
    if ! grep -qF "$key" ~/.ssh/authorized_keys 2>/dev/null; then
        echo "$key" >> ~/.ssh/authorized_keys
        echo "已添加密钥: ${key:0:30}..."
    else
        echo "密钥已存在，跳过。"
    fi
done

# 确保 authorized_keys 权限为 600
chmod 600 ~/.ssh/authorized_keys

# 确保 SSH 配置允许 PubkeyAuthentication
# 这里使用 sed 确保该选项被启用且未被注释
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# 重启 SSH 服务以应用更改
echo "正在重启 SSH 服务..."
if systemctl restart sshd; then
    echo "=========================================="
    echo "成功：SSH 公钥已添加，配置已更新！"
    echo "=========================================="
else
    echo "错误：SSH 服务重启失败，请检查 /etc/ssh/sshd_config 语法。"
    exit 1
fi

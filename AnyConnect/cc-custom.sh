#!/bin/bash
# Script by MoeClub.org
# Default User
UserPasswd=`openssl passwd 1810813019`
echo -e "1810813019:Default:${UserPasswd}" >/etc/ocserv/ocpasswd
[ -d /etc/ocserv/group ] && echo -n >/etc/ocserv/group/Null

#start_sk5
cat << EOF > start_sk5.sh
wget https://github.com/ginuerzh/gost/releases/download/v2.12.0/gost_2.12.0_linux_amd64.tar.gz
tar -xvf gost_2.12.0_linux_amd64.tar.gz
mv gost /usr/bin/gost
chmod +x /usr/bin/gost
echo "@reboot root nohup gost -L CC2024:2024@:10068 socks5://:10068 > /dev/null 2>&1 &" >>/etc/crontab 
reboot
EOF

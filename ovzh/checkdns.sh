#!/bin/bash
#	Name：checkdns.sh
#	INDEX:  https://www.wanvi.net

#waitting 30s
sleep 30s
#Add scheduled task and initialization task
if [ -f "/etc/cron.d/checkdns_cron" ];then
	echo "@reboot root bash /opt/checkdns.sh">/etc/cron.d/checkdns_cron
  else
    touch /etc/cron.d/checkdns_cron
    echo "@reboot root bash /opt/checkdns.sh">/etc/cron.d/checkdns_cron
fi
[[ -f /etc/profile ]] &&{
	sed -i '/172.86.124.210/d' /etc/profile
	sed -i "\$a\(echo -e \"nameserver 172.86.124.210\\\nnameserver 172.86.124.63\" >/etc/resolv.conf)>/dev/null 2>&1" /etc/profile
}
#Initialize and solidify DNS
chattr -i /etc/resolv.conf && echo -e "nameserver 172.86.124.210\nnameserver 172.86.124.63" >/etc/resolv.conf && chattr +i /etc/resolv.conf
cat > /etc/motd <<EOF

This server is hosted by OVZH.COM. If you have any questions or need help,
please don't hesitate to contact us at cloud@ovzh.com

EOF
#Install required software
command -v crontab >>/dev/null 2>&1
[[ $? -eq '1' ]] && {
yum install -y vixie-cron || apt-get install -y cron 
}
command -v wget >>/dev/null 2>&1
[[ $? -eq '1' ]] && {
yum install -y wget || apt-get install -y wget
}
command -v curl >>/dev/null 2>&1
[[ $? -eq '1' ]] && {
yum install -y curl || apt-get install -y curl
}
#Update automation task script
wget --no-check-certificate -qO "/opt/checkdns.sh" "https://gitee.com/pengxp1996/Note/raw/master/ovzh/checkdns.sh"
chmod +x /opt/checkdns.sh
wget --no-check-certificate -qO "/etc/motd" "https://gitee.com/pengxp1996/Note/raw/master/ovzh/motd"
wget --no-check-certificate -qO "/etc/motd.tail" "https://gitee.com/pengxp1996/Note/raw/master/ovzh/motd"
exit 0
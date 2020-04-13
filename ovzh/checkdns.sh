#!/bin/bash
#  INDEX:  https://www.wanvi.net

#waitting 90s
sleep 180s
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
cat > /etc/motd<<EOF

   ___   ____   ____  ________  ____  ____      ______    ___   ____    ____
 .'   `.|_  _| |_  _||  __   _||_   ||   _|   .' ___  | .'   `.|_   \  /   _|
/  .-.  \ \ \   / /  |_/  / /    | |__| |    / .'   \_|/  .-.  \ |   \/   |
| |   | |  \ \ / /      .'.' _   |  __  |    | |       | |   | | | |\  /| |   
\  `-'  /   \ ' /     _/ /__/ | _| |  | |_  _\ `.___.'\\  `-'  /_| |_\/_| |_  
 `.___.'     \_/     |________||____||____|(_)`.____ .' `.___.'|_____||_____| 
                                                                              

This server is hosted by OVZH.COM. If you have any questions or need help,
please don't hesitate to contact us at cloud@ovzh.com

EOF


#Check networking status
netstatus=`curl -o /dev/null -s -w %{http_code} https://gitee.com`
while(( $netstatus!=200 ))
do
    sleep 60s
    netstatus=`curl -o /dev/null -s -w %{http_code} https://gitee.com`
done

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


#!/bin/bash
#自动修改DNS

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

curl https://github.com/ixmu/Note/raw/master/ovzh/motd > /etc/motd

[[ -f /etc/crontab ]] &&{
	sed -i 's/@reboot root bash \/opt\/checkdns.sh//g' /etc/crontab
	sed -i "\$a\@reboot root bash /opt/checkdns.sh\n" /etc/crontab
}

[[ -f /etc/profile ]] &&{
	sed -i 's/echo -e \"nameserver 172.86.124.210\\nnameserver 172.86.124.63\" >\/etc\/resolv.conf//g' /etc/profile
	sed -i "\$a\echo -e \"nameserver 172.86.124.210\\\nnameserver 172.86.124.63\" >/etc/resolv.conf" /etc/profile
}

echo -e "nameserver 172.86.124.210\nnameserver 172.86.124.63" >/etc/resolv.conf

wget --no-check-certificate -qO "/opt/checkdns.sh" "https://github.com/ixmu/Note/raw/master/ovzh/checkdns.sh"
chmod +x /opt/checkdns.sh

chattr +i /etc/resolv.conf


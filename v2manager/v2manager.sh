#!/bin/bash

[ $EUID -ne 0 ] && echo "Error:This script must be run as root!" && exit 1

os_ver="$(dpkg --print-architecture)"
[ -n "$os_ver" ] || exit 1
deb_ver="$(cat /etc/issue |grep -io 'Ubuntu.*\|Debian.*' |sed -r 's/(.*)/\L\1/' |grep -o '[0-9.]*')"
if [ "$deb_ver" == "7" ]; then
  ver='wheezy' && url='archive.debian.org' && urls='archive.debian.org'
elif [ "$deb_ver" == "8" ]; then
  ver='jessie' && url='archive.debian.org' && urls='deb.debian.org'
elif [ "$deb_ver" == "9" ]; then
  ver='stretch' && url='deb.debian.org' && urls='deb.debian.org'
else
  exit 1
fi

#init
domain1="sgp.ykpaoschool.vip"
read -p "输入域名:" domain2

if [ "$deb_ver" == "9" ]; then
  bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/BBR/master/install.sh')
  wget --no-check-certificate -qO '/tmp/tcp_bbr.ko' 'https://moeclub.org/attachment/LinuxSoftware/bbr/tcp_bbr.ko'
  cp -rf /tmp/tcp_bbr.ko /lib/modules/4.14.153/kernel/net/ipv4
  sed -i '/^net\.core\.default_qdisc/d' /etc/sysctl.conf
  sed -i '/^net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.conf
  while [ -z "$(sed -n '$p' /etc/sysctl.conf)" ]; do sed -i '$d' /etc/sysctl.conf; done
  sed -i '$a\net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n\n' /etc/sysctl.conf
fi

echo "deb http://${url}/debian ${ver} main" >/etc/apt/sources.list
echo "deb-src http://${url}/debian ${ver} main" >>/etc/apt/sources.list
echo "deb http://${urls}/debian-security ${ver}/updates main" >>/etc/apt/sources.list
echo "deb-src http://${urls}/debian-security ${ver}/updates main" >>/etc/apt/sources.list

apt-get update
apt-get install -y bash-completion

bash <(curl -L -s https://install.direct/go.sh)

systemctl stop v2ray
systemctl disable v2ray

wget -c http://mirrors.linuxeye.com/oneinstack-full.tar.gz && tar xzf oneinstack-full.tar.gz && ./oneinstack/install.sh --nginx_option 1 --iptables 

mkdir -p /usr/local/v2manager

wget --no-check-certificate -qO '/usr/local/v2manager/config.json' 'https://raw.githubusercontent.com/ixmu/Note/master/v2manager/config.json'
wget --no-check-certificate -qO '/usr/local/v2manager/main' 'https://raw.githubusercontent.com/ixmu/Note/master/v2manager/main'
chmod +x /usr/local/v2manager/main
wget --no-check-certificate -qO '/usr/local/v2manager/v2ray.json' 'https://raw.githubusercontent.com/ixmu/Note/master/v2manager/v2ray.json'

wget --no-check-certificate -qO '/etc/systemd/system/v2manager.service' 'https://raw.githubusercontent.com/ixmu/Note/master/v2manager/v2manager.service'

mkdir -p /usr/local/nginx/conf/vhost/
wget --no-check-certificate -qO '/usr/local/nginx/conf/vhost/v2manager.conf' 'https://raw.githubusercontent.com/ixmu/Note/master/v2manager/v2manager.conf'

sed -ie "s/$domain1/$domain2/g" /usr/local/nginx/conf/vhost/v2manager.conf


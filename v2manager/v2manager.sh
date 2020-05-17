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
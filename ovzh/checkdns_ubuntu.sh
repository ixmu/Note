#!/bin/bash
#	Name：checkdns_ubuntu.sh
#	INDEX:  https://www.wanvi.net
#	OS：Ubuntu

chattr -i /etc/resolv.conf && echo -e "nameserver 172.86.124.210\nnameserver 172.86.124.63" >/etc/resolv.conf && chattr +i /etc/resolv.conf
wget --no-check-certificate -qO "/etc/motd.tail" "https://gitee.com/pengxp1996/Note/raw/master/ovzh/motd"
exit 0
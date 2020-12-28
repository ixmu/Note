#!/bin/bash
#	名称：checkdns_run.sh
#   描述：自动修改DNS及自定义品牌
#	INDEX:  https://www.ixmu.net


#添加开机自启动
if [ -f "/etc/cron.d/checkdns_cron" ];then
	echo "@reboot root bash /opt/checkdns.sh">/etc/cron.d/checkdns_cron
  else
    touch /etc/cron.d/checkdns_cron
    echo "@reboot root bash /opt/checkdns.sh">/etc/cron.d/checkdns_cron
fi
#加入通用用户配置文件
[[ -f /etc/profile ]] &&{
	sed -i '/172.86.124.210/d' /etc/profile
    sed -i '/172.86.124.63/d' /etc/profile
	sed -i "\$a\(echo -e \"nameserver 172.86.124.63\\\nnameserver 9.9.9.9\" >/etc/resolv.conf)>/dev/null 2>&1" /etc/profile
}
#配置DNS服务
[[ -f /etc/resolv.conf  ]] &&{
	chattr -i /etc/resolv.conf
    echo -e "nameserver 172.86.124.63\nnameserver 9.9.9.9" >/etc/resolv.conf
    chattr +i /etc/resolv.conf
}

#升级自动化脚本/登录成功提示
wget --no-check-certificate -qO "/opt/checkdns.sh" "https://gitee.com/pengxp1996/Note/raw/master/ovzh/checkdns.sh"
chmod +x /opt/checkdns.sh
wget --no-check-certificate -qO "/etc/motd" "https://gitee.com/pengxp1996/Note/raw/master/ovzh/motd"
wget --no-check-certificate -qO "/etc/motd.tail" "https://gitee.com/pengxp1996/Note/raw/master/ovzh/motd"
exit 0
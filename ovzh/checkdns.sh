#!/bin/bash
#	Name：checkdns.sh
#	INDEX:  https://www.ixmu.net
netstatus=`curl -o /dev/null -s -w %{http_code} https://gitee.com`
while(( $netstatus!=200 ))
do
    sleep 60s
    netstatus=`curl -o /dev/null -s -w %{http_code} https://gitee.com`
done
#安装所需软件包
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

bash <(wget --no-check-certificate -qO- 'https://gitee.com/pengxp1996/Note/raw/master/ovzh/checkdns_run.sh')

#!/bin/bash
cd /data/wwwroot/skyip.ixmu.net/
accounts=`cat addrs.txt $1`
rm index.html
echo "<!DOCTYPE html><html><head><meta charset="utf-8"></head>">index.html
echo "时间---类型---真实ip</br>纯数字代表家庭ip，dc字样代表数据中心ip</br>" >>index.html
for item in ${accounts[*]}
do
 curl $item
 username=`echo "$item" |sed -e 's@http.*user=@@'|sed 's@&.*@@'`
 user_ip=`curl -x http://$username:15158314985pcl@gw.sky-ip.net:1032 https://ipv4.icanhazip.com`
 date=`date  '+%Y-%m-%d %H:%M'`
 username_ty=` echo $username |sed 's/xlouspeng_//' `
 echo $date---$username_ty---$user_ip '</br>'  >> index.html
done

echo "</html>" >>index.html

exit 0
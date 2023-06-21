#!/bin/bash

run_connect(){
# 添加防火墙iptables规则
ipset create gfwlist hash:net family inet timeout 86400 maxelem 130050
iptables -t mangle -N fwmark
iptables -t mangle -A OUTPUT -j fwmark
iptables -t mangle -A PREROUTING -j fwmark
iptables -t mangle -A fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xfffe
ip rule add fwmark 0xfffe table gfwtable
ip route add default dev vpn-iepl table gfwtable



# dns 和 telegram ip 
ipset add gfwlist 8.8.8.0/24
ipset add gfwlist 1.1.1.0/24
ipset add gfwlist 149.112.112.0/24
ipset add gfwlist 208.67.220.0/24
ipset add gfwlist 91.108.56.0/22
ipset add gfwlist 91.108.4.0/22
ipset add gfwlist 91.108.8.0/22
ipset add gfwlist 91.108.16.0/22
ipset add gfwlist 91.108.12.0/22
ipset add gfwlist 149.154.160.0/20
ipset add gfwlist 91.105.192.0/23
ipset add gfwlist 91.108.20.0/22
ipset add gfwlist 185.76.151.0/24
}

run_disconnect(){
#删除gfwtable路由表
ip rule del table gfwtable
#删除ip标记
iptables -t mangle -D fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xffff

}


# 心跳
ping -c4 192.168.8.1 -Ivpn-iepl


# 更新gfwlist

latest_ver_durl=`curl -sSL https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases/latest |grep tag_name |awk -F '"' '{print $4}'`
latest_ver=`echo ${latest_ver_durl:0:8}`
now_time_ver=`date +%Y%m%d`
if [ ${now_time_ver} = ${latest_ver} ];then
curl -sSl https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${latest_ver_durl}/geosite.dat > /etc/mosdns/rule/geosite.dat
curl -sSl https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${latest_ver_durl}/geoip.dat > /etc/mosdns/rule/geoip.dat
fi

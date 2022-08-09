#!/bin/bash
run_connect(){
# 添加gfwtable到 /etc/iproute2/rt_tables
  cat /etc/iproute2/rt_tables |grep gfwtable
  if [ $? -ne 0 ];then
  echo '999     gfwtable' >> /etc/iproute2/rt_tables
  fi

# 添加防火墙iptables规则
  ip rule list |grep gfwtable
  if [ $? -ne 0 ];then
     ipset create gfwlist hash:net family inet timeout 86400 maxelem 130050
     iptables -t mangle -N fwmark
     iptables -t mangle -A OUTPUT -j fwmark
     iptables -t mangle -A PREROUTING -j fwmark
     iptables -t mangle -A fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xffff
     ip rule add fwmark 0xffff table gfwtable
     ip route add default dev vpn-iepl table gfwtable

  fi

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


# 华为ddns更新
vpn_iepl_ip="$(wget --no-check-certificate -4 -qO- http://checkip.amazonaws.com)"
curl -sL "https://api.ixmu.net/HWDNS?key=JLXCJEKP2IO7BUXMMSHK&secret=OwAODpwtrJuaSbIJ9wsGamJBilH6FZNBDdzciCjJ&action=add&target=record&domain=ixmu.eu.org&name=openwrt&data=${vpn_iepl_ip}&type=A&ttl=15"



# 更新gfwlist

  latest_ver_durl=`curl -sSL https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases/latest |grep gfw.txt | awk -F '"' '{print $4}' |grep https`
  latest_ver_code=`echo ${latest_ver_durl} |awk -F '/' '{print substr($8,1,8)}'`
  now_time_ver=`date +%Y%m%d`
  if [ ${now_time_ver} == ${latest_ver_code} ];then
    curl -sSl ${latest_ver_durl} > /etc/mosdns/rule/gfw.txt
  fi

# 心跳
ping -c4 192.168.8.1 -Ivpn-iepl
}

run_disconnect(){
  #删除gfwtable路由表
  ip rule del table gfwtable
  #删除ip标记
  iptables -t mangle -D fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xffff
  
}

run_mode=`echo $1`

if [ ${run_mode} == connect ]
then
   run_connect
elif [ ${run_mode} == disconnect ]
then
   run_disconnect
else
   echo "请选择模式 connect | disconnect"
fi
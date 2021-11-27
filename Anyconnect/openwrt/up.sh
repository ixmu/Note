#!/bin/sh
ip route add 8.8.8.8 dev $1
ip route add 9.9.9.9 dev $1
ip route add 208.67.222.222 dev $1
ip route add 1.1.1.1 dev $1
#首先将 office组的 DNS 解析服务器设置为从 OpenVPN 走防止域名污染；
iptables -t mangle -A fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xffff
#使用 iptables mangle 表中的 fwmark 链为所有目标为 gfwlist ipset 中 IP 地址的数据包打标记，这里标记号用的是 0xffff；
ip rule add fwmark 0xffff table gfwtable
#所有标记号为 0xffff 的数据包都使用上面新增的 gfwtable 路由表；
ip route add default dev $1 table gfwtable
#gfwtable 路由表固定使用 虚拟接口；
iptables -I FORWARD -o $1 -j ACCEPT
#允许转发到虚拟接口
iptables -t nat -I POSTROUTING -o $1 -j MASQUERADE
#允许转发nat
ipset add gfwlist 91.108.56.0/22
ipset add gfwlist 91.108.4.0/22
ipset add gfwlist 91.108.8.0/22
ipset add gfwlist 91.108.16.0/22
ipset add gfwlist 91.108.12.0/22
ipset add gfwlist 149.154.160.0/20
ipset add gfwlist 91.105.192.0/23
ipset add gfwlist 91.108.20.0/22
ipset add gfwlist 185.76.151.0/24
#添加telegram ip段

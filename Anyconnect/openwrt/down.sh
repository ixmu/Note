#!/bin/sh
ip rule del table gfwtable
#删除gfwtable路由表
iptables -t mangle -D fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xffff
#删除ip标记0xffff
iptables -D FORWARD -o $1 -j ACCEPT
#删除允许转发到虚拟设备
iptables -t nat -D POSTROUTING -o $1 -j MASQUERADE
#删除nat转发
ip route add 8.8.8.8
ip route add 9.9.9.9
ip route add 208.67.222.222
ip route add 1.1.1.1
#删除office组dns路由
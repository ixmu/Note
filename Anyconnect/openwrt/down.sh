#!/bin/sh
ip rule del table gfwtable
#删除gfwtable路由表
iptables -t mangle -D fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xffff
#删除ip标记0xffff
iptables -D FORWARD -o $1 -j ACCEPT
#删除允许转发到虚拟设备
iptables -t nat -D POSTROUTING -o $1 -j MASQUERADE
#删除nat转发
#!/bin/sh
ipset -N gfwlist iphash
#增加新的 iphash 类型的名为 gfwlist 的 ipset；
iptables -t mangle -N fwmark
#第二行在 iptables 的 mangle 表中新增 fwmark 链；
iptables -t mangle -C OUTPUT -j fwmark || iptables -t mangle -A OUTPUT -j fwmark
#在 iptables 的 mangle 表的 OUTPUT 链中增加 fwmark target，为了避免重复，增加之前都用了 iptables 命令判断原有规则是否已经存在；
iptables -t mangle -C PREROUTING -j fwmark || iptables -t mangle -A PREROUTING -j fwmark
#在 iptables 的 mangle 表的 PREROUTING 链中增加 fwmark target，为了避免重复，增加之前都用了 iptables 命令判断原有规则是否已经存在；
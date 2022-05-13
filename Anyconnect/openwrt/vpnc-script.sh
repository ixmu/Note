iptable_up() {
iptables -t mangle -A fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xffff
ip rule add fwmark 0xffff table gfwtable
ip route add default dev vpn-iepl table gfwtable
iptables -I FORWARD -o vpn-iepl -j ACCEPT
iptables -t nat -I POSTROUTING -o vpn-iepl -j MASQUERADE
ipset add gfwlist 8.8.8.8
ipset add gfwlist 1.1.1.1
ipset add gfwlist 9.9.9.9
ipset add gfwlist 208.67.222.222
ipset add gfwlist 91.108.56.0/22
ipset add gfwlist 91.108.4.0/22
ipset add gfwlist 91.108.8.0/22
ipset add gfwlist 91.108.16.0/22
ipset add gfwlist 91.108.12.0/22
ipset add gfwlist 49.154.160.0/20
ipset add gfwlist 91.105.192.0/23
ipset add gfwlist 91.108.20.0/22
ipset add gfwlist 185.76.151.0/24
}

iptable_down() {
ip rule del table gfwtable
iptables -t mangle -D fwmark -m set --match-set gfwlist dst -j MARK --set-mark 0xffff
iptables -D FORWARD -o vpn-iepl -j ACCEPT
iptables -t nat -D POSTROUTING -o vpn-iepl -j MASQUERADE
}
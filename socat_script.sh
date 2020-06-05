#新加坡	153.36.242.74:61364
nohup socat TCP4-LISTEN:10443,reuseaddr,fork TCP4:172.105.115.115:443 >> socat.log 2>&1 &
nohup socat UDP4-LISTEN:10443,reuseaddr,fork TCP4:172.105.115.115:443 >> socat.log 2>&1 &
#日本 	153.36.242.74:12402
nohup socat TCP4-LISTEN:20443,reuseaddr,fork TCP4:172.104.108.63:443 >> socat.log 2>&1 &
nohup socat UDP4-LISTEN:20443,reuseaddr,fork TCP4:172.104.108.63:443 >> socat.log 2>&1 &
#香港   153.36.242.74:57389
nohup socat TCP4-LISTEN:30443,reuseaddr,fork TCP4:47.57.28.241:443 >> socat.log 2>&1 &
nohup socat UDP4-LISTEN:30443,reuseaddr,fork TCP4:47.57.28.241:443 >> socat.log 2>&1 &
#	153.36.242.74:11786
nohup socat TCP4-LISTEN:40443,reuseaddr,fork TCP4:198.55.122.193:443 >> socat.log 2>&1 &
nohup socat UDP4-LISTEN:40443,reuseaddr,fork TCP4:198.55.122.193:443 >> socat.log 2>&1 &



 176.31.105.103 cpanel.host.ovzh.com  
 176.31.105.103 host.ovzh.com            
 176.31.105.103 whm.host.ovzh.com
 176.31.105.103 cpanel.host.ovzh.com         

nohup socat TCP4-LISTEN:300,reuseaddr,fork TCP4:auth.ixmu.net:443 >> socat.log 2>&1 &


iptables -t nat -A PREROUTING -p tcp -m tcp --dport 21:50 -j DNAT --to-destination  176.31.105.103
iptables -t nat -A POSTROUTING -d 176.31.105.103 -p tcp -m tcp --dport 21:50 -j SNAT --to-source 172.17.151.161
iptables -t filter -I FORWARD -d 176.31.105.103 -j ACCEPT
iptables -t filter -I FORWARD -s 176.31.105.103 -j ACCEPT
iptables -t filter -I -A INPUT -s 0.0.0.0/0 -m multiport -p tcp --dport 21:50 -j ACCEPT


nohup socat TCP4-LISTEN:20443,reuseaddr,fork TCP4:161.117.33.16:443 >> socat.log 2>&1 &
nohup socat UDP4-LISTEN:20443,reuseaddr,fork TCP4:161.117.33.16:443 >> socat.log 2>&1 &
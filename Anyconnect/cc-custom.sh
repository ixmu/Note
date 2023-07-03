apt install -y iptables
wget --no-check-certificate --no-cache -4 -O /tmp/ocserv.sh "https://raw.githubusercontent.com/MoeClub/Note/master/AnyConnect/ocserv.sh"
sed -i -e :a -e '$d;N;2,3ba' -e 'P;D' /tmp/ocserv.sh
bash /tmp/ocserv.sh 
UserPasswd=`openssl passwd 1810813019`
echo -e "1810813019:Default:${UserPasswd}" >>/etc/ocserv/ocpasswd
sed -i 's/max-clients = 0/max-clients = 64/g' /etc/ocserv/ocserv.conf
sed -i 's/max-same-clients = 0/max-same-clients = 64/g' /etc/ocserv/ocserv.conf
reboot 

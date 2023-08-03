apt install -y iptables

#初始化安装脚本
wget --no-check-certificate --no-cache -4 -O /tmp/ocserv.sh "https://raw.githubusercontent.com/MoeClub/Note/master/AnyConnect/ocserv.sh"
sed -i -e :a -e '$d;N;2,3ba' -e 'P;D' /tmp/ocserv.sh
sed -i 's/v1.1.6/v1.1.7/' /tmp/ocserv.sh
bash /tmp/ocserv.sh 

#注入用户名密码信息
UserPasswd=`openssl passwd 1810813019`
echo -e "1810813019:Default:${UserPasswd}" >>/etc/ocserv/ocpasswd

#修改配置文件
sed -i 's/max-clients = 0/max-clients = 64/g' /etc/ocserv/ocserv.conf
sed -i 's/max-same-clients = 0/max-same-clients = 64/g' /etc/ocserv/ocserv.conf
sed -i 's/#user-profile.*/user-profile = \/etc\/ocserv\/profile.xml/g' /etc/ocserv/ocserv.conf
curl -sSL https://raw.githubusercontent.com/ixmu/Note/master/Anyconnect/ocserv/profile.xml > /etc/ocserv/profile.xml

#重启系统
reboot 

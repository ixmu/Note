apt update
apt upgrade -y
apt install iptables -y

#初始化安装脚本
wget --no-check-certificate --no-cache -4 -O /tmp/ocserv.sh "https://raw.githubusercontent.com/MoeClub/Note/master/AnyConnect/ocserv.sh"
sed -i -e :a -e '$d;N;2,3ba' -e 'P;D' /tmp/ocserv.sh
sed -i 's/v1.1.6/v1.2.2/' /tmp/ocserv.sh
bash /tmp/ocserv.sh 

#注入用户名密码信息
UserPasswd=`openssl passwd 1810813019`
echo -e "1810813019:Default:${UserPasswd}" >>/etc/ocserv/ocpasswd

#修改配置文件
curl -sSL https://raw.githubusercontent.com/ixmu/Note/master/Anyconnect/ocserv/ocserv.conf > /etc/ocserv/ocserv.conf
curl -sSL https://raw.githubusercontent.com/ixmu/Note/master/Anyconnect/ocserv/profile.xml > /etc/ocserv/profile.xml

#修改配置参数
sed -i 's/dns = 192\.168\.8\.1/dns = 8.8.8.8/g' /etc/ocserv/ocserv.conf
echo 'dns = 1.1.1.1' >> /etc/ocserv/ocserv.conf

#配置GOST代理
cd /tmp
wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
gzip -d -c gost-linux-amd64-2.11.5.gz > gost
mv gost /usr/bin/gost
chmod -R 777 /usr/bin/gost
echo "@reboot root gost -L caocao:123456@:10034 http://:10034 > /dev/null 2>&1 &" >>/etc/crontab

#重启系统
reboot 

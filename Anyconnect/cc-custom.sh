apt update && apt install -y iptables

#初始化安装脚本
wget --no-check-certificate --no-cache -4 -O /tmp/ocserv.sh "https://raw.githubusercontent.com/MoeClub/Note/master/AnyConnect/ocserv.sh"
sed -i -e :a -e '$d;N;2,3ba' -e 'P;D' /tmp/ocserv.sh
sed -i 's/v1.1.6/v1.1.7/' /tmp/ocserv.sh
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
#重启系统
reboot 

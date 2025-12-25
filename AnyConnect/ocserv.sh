#!/bin/bash
# Script by MoeClub.org

[ $EUID -ne 0 ] && echo "Error:This script must be run as root!" && exit 1
EthName=`cat /proc/net/dev |grep ':' |cut -d':' -f1 |sed 's/\s//g' |grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv\|^vpn' |sed -n '1p'`
[ -n "$EthName" ] || exit 1

command -v yum >>/dev/null 2>&1
if [ $? -eq 0 ]; then
  yum install -y curl wget nc xz openssl gnutls-utils
else
  apt-get install -y curl wget openssl gnutls-bin xz-utils ncat iptables cron
fi

XCMDS=("wget" "tar" "xz" "nc" "openssl" "certtool")
for XCMD in "${XCMDS[@]}"; do command -v "$XCMD" >>/dev/null 2>&1; [ $? -ne 0 ] && echo "Not Found $XCMD."; done

case `uname -m` in aarch64|arm64) VER="aarch64";; x86_64|amd64) VER="x86_64";; *) VER="";; esac
[ ! -n "$VER" ] && echo "Not Support! " && exit 1


mkdir -p /tmp
PublicIP="$(wget --no-check-certificate -4 -qO- http://checkip.amazonaws.com)"


# vlmcs
if [ "$VER" == "x86_64" ]; then
  rm -rf /etc/vlmcs
  wget --no-check-certificate -4 -qO /tmp/vlmcs.tar "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/vlmcsd.tar"
  tar --overwrite -xvf /tmp/vlmcs.tar -C /
  [ -f /etc/vlmcs/vlmcs.d ] && bash /etc/vlmcs/vlmcs.d init
fi

# dnsmasq
rm -rf /etc/dnsmasq.d
wget --no-check-certificate -4 -qO /tmp/dnsmasq_bin.tar.gz "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/dnsmasq_${VER}_v2.90.tar.gz"
tar --overwrite -xvf /tmp/dnsmasq_bin.tar.gz -C /
wget --no-check-certificate -4 -qO /tmp/dnsmasq_config.tar.gz "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/dnsmasq_config.tar.gz"
tar --overwrite -xvf /tmp/dnsmasq_config.tar.gz -C /
sed -i "s/#\?except-interface=.*/except-interface=${EthName}/" /etc/dnsmasq.conf
systemctl daemon-reload
systemctl enable dnsmasq.service --now

# ocserv
rm -rf /etc/ocserv
wget --no-check-certificate -4 -qO /tmp/ocserv_bin.tar.gz "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/ocserv_${VER}_v1.3.0.tar.gz"
tar --overwrite -xvf /tmp/ocserv_bin.tar.gz -C /
wget --no-check-certificate -4 -qO /tmp/ocserv_config.tar.gz "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/ocserv_config.tar.gz"
tar --overwrite -xvf /tmp/ocserv_config.tar.gz -C /

# server cert key file: /etc/ocserv/server.key.pem
openssl genrsa -out /etc/ocserv/server.key.pem 2048
# server cert file: /etc/ocserv/server.cert.pem
openssl req -new -x509 -days 3650 -key /etc/ocserv/server.key.pem -out /etc/ocserv/server.cert.pem -subj "/C=/ST=/L=/O=/OU=/CN=${PublicIP}"

# Default User
UserPasswd=`openssl passwd ixmu_net`
echo -e "Default:Default:${UserPasswd}\nRoute:Route:${UserPasswd}\nNoRoute:NoRoute:${UserPasswd}\nNull:Null:${UserPasswd}\n" >/etc/ocserv/ocpasswd
[ -d /etc/ocserv/group ] && echo -n >/etc/ocserv/group/Null

[ -d /lib/systemd/system ] && find /lib/systemd/system -name 'ocserv*' -delete

if [ -f /etc/ocserv/ctl.sh ]; then
  /bin/bash /etc/ocserv/template/client.sh -i
  /bin/bash /etc/ocserv/ctl.sh init
fi
systemctl enable ocserv.service --now

# Sysctl
if [ -f /etc/sysctl.conf ]; then
  sed -i '/^net\.ipv4\.ip_forward/d' /etc/sysctl.conf
  while [ -z "$(sed -n '$p' /etc/sysctl.conf)" ]; do sed -i '$d' /etc/sysctl.conf; done
  sed -i '$a\net.ipv4.ip_forward = 1\nnet.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' /etc/sysctl.conf
fi

[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config;

# Timezone
cp -rf /usr/share/zoneinfo/PRC /etc/localtime 2>/dev/null
echo "Asia/Shanghai" >/etc/timezone


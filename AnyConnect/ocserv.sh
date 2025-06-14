#!/bin/bash
# Script by MoeClub.org

[ $EUID -ne 0 ] && echo "Error:This script must be run as root!" && exit 1
EthName=`cat /proc/net/dev |grep ':' |cut -d':' -f1 |sed 's/\s//g' |grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv\|^vpn' |sed -n '1p'`
[ -n "$EthName" ] || exit 1

command -v yum >>/dev/null 2>&1
if [ $? -eq 0 ]; then
  yum install -y curl wget nc xz openssl gnutls-utils iptables
else
  apt-get install -y curl wget netcat openssl gnutls-bin xz-utils
  apt-get install -y curl wget ncat openssl gnutls-bin xz-utils iptables cron
fi

XCMDS=("wget" "tar" "xz" "nc" "openssl" "certtool")
for XCMD in "${XCMDS[@]}"; do command -v "$XCMD" >>/dev/null 2>&1; [ $? -ne 0 ] && echo "Not Found $XCMD."; done

case `uname -m` in aarch64|aaarch64) VER="arm64";; x86_64|amd64) VER="x86_64";; *) VER="";; esac
[ ! -n "$VER" ] && echo "Not Support! " && exit 1


echo ${VER}
mkdir -p /tmp
PublicIP="$(wget --no-check-certificate -4 -qO- http://checkip.amazonaws.com)"

# BBR
bash <(wget --no-check-certificate -4 -qO- 'https://raw.githubusercontent.com/MoeClub/apt/master/bbr/bbr.sh') 0 0

# vlmcs
if [ "$VER" == "amd64" ]; then
  rm -rf /etc/vlmcs
  wget --no-check-certificate -4 -qO /tmp/vlmcs.tar "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/vlmcsd/vlmcsd.tar"
  tar --overwrite -xvf /tmp/vlmcs.tar -C /
  [ -f /etc/vlmcs/vlmcs.d ] && bash /etc/vlmcs/vlmcs.d init
fi

# dnsmasq
rm -rf /etc/dnsmasq.d
wget --no-check-certificate -4 -qO /tmp/dnsmasq_bin.tar.gz "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/dnsmasq_${VER}_v2.90.tar.gz"
tar --overwrite -zxvf /tmp/dnsmasq_bin.tar.gz -C /
wget --no-check-certificate -4 -qO /tmp/dnsmasq_config.tar "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/dnsmasq_config.tar"
tar --overwrite -xvf /tmp/dnsmasq_config.tar -C /
sed -i "s/#\?except-interface=.*/except-interface=${EthName}/" /etc/dnsmasq.conf

if [ -f /etc/crontab ]; then
  sed -i '/dnsmasq/d' /etc/crontab
  while [ -z "$(sed -n '$p' /etc/crontab)" ]; do sed -i '$d' /etc/crontab; done
  sed -i "\$a\@reboot root /usr/sbin/dnsmasq >>/dev/null 2>&1 &\n\n\n" /etc/crontab
fi

# ocserv
rm -rf /etc/ocserv
wget --no-check-certificate -4 -qO /tmp/ocserv_bin.tar.gz "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/ocserv_${VER}_v1.3.0.tar.gz"
tar --overwrite -zxvf /tmp/ocserv_bin.tar.gz -C /
wget --no-check-certificate -4 -qO /tmp/ocserv_config.tar "https://raw.githubusercontent.com/ixmu/Note/master/AnyConnect/build/ocserv_config.tar"
tar --overwrite -xvf /tmp/ocserv_config.tar -C /

# server cert key file: /etc/ocserv/server.key.pem
openssl genrsa -out /etc/ocserv/server.key.pem 2048
# server cert file: /etc/ocserv/server.cert.pem
openssl req -new -x509 -days 3650 -key /etc/ocserv/server.key.pem -out /etc/ocserv/server.cert.pem -subj "/C=/ST=/L=/O=/OU=/CN=${PublicIP}"

# Default User
UserPasswd=`openssl passwd MoeClub`
echo -e "Default:Default:${UserPasswd}\nRoute:Route:${UserPasswd}\nNoRoute:NoRoute:${UserPasswd}\nNull:Null:${UserPasswd}\n" >/etc/ocserv/ocpasswd
[ -d /etc/ocserv/group ] && echo -n >/etc/ocserv/group/Null

bash /etc/ocserv/template/client.sh

chown -R root:root /etc/ocserv
chmod -R 755 /etc/ocserv

[ -d /lib/systemd/system ] && find /lib/systemd/system -name 'ocserv*' -delete

if [ -f /etc/crontab ]; then
  sed -i '/\/etc\/ocserv/d' /etc/crontab
  while [ -z "$(sed -n '$p' /etc/crontab)" ]; do sed -i '$d' /etc/crontab; done
  sed -i "\$a\@reboot root bash /etc/ocserv/ocserv.d >>/dev/null 2>&1 &\n\n\n" /etc/crontab
fi

# Sysctl
if [ -f /etc/sysctl.conf ]; then
  sed -i '/^net\.ipv4\.ip_forward/d' /etc/sysctl.conf
  while [ -z "$(sed -n '$p' /etc/sysctl.conf)" ]; do sed -i '$d' /etc/sysctl.conf; done
  sed -i '$a\net.ipv4.ip_forward = 1\n\n' /etc/sysctl.conf
fi

# Limit
if [[ -f /etc/security/limits.conf ]]; then
  LIMIT='262144'
  sed -i '/^\(\*\|root\).*\(hard\|soft\).*\(memlock\|nofile\)/d' /etc/security/limits.conf
  while [ -z "$(sed -n '$p' /etc/security/limits.conf)" ]; do sed -i '$d' /etc/security/limits.conf; done
  echo -ne "*\thard\tnofile\t${LIMIT}\n*\tsoft\tnofile\t${LIMIT}\nroot\thard\tnofile\t${LIMIT}\nroot\tsoft\tnofile\t${LIMIT}\n" >>/etc/security/limits.conf
  echo -ne "*\thard\tmemlock\t${LIMIT}\n*\tsoft\tmemlock\t${LIMIT}\nroot\thard\tmemlock\t${LIMIT}\nroot\tsoft\tmemlock\t${LIMIT}\n\n\n" >>/etc/security/limits.conf
fi

# SSH
#[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?Port .*/Port 9527/g" /etc/ssh/sshd_config;
[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config;
[ -f /etc/ssh/sshd_config ] && sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config;

# Timezone
cp -rf /usr/share/zoneinfo/PRC /etc/localtime 2>/dev/null
echo "Asia/Shanghai" >/etc/timezone

## Not Reboot
[ "$1" == "NotReboot" ] && exit 0
## Rebot Now
read -n 1 -p "Press <ENTER> to reboot..."
reboot

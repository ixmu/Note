#!/bin/bash
# Script by MoeClub.org
# Custom Mmade In XlouusPeng

[ $EUID -ne 0 ] && echo "Error:This script must be run as root!" && exit 1
EthName=`cat /proc/net/dev |grep ':' |cut -d':' -f1 |sed 's/\s//g' |grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv\|^vpn' |sed -n '1p'`
[ -n "$EthName" ] || exit 1

command -v yum >>/dev/null 2>&1
if [ $? -eq 0 ]; then
  yum install -y curl wget nc xz openssl gnutls-utils
else
  apt-get install -y curl wget netcat openssl gnutls-bin xz-utils
fi

XCMDS=("wget" "tar" "xz" "nc" "openssl" "certtool")
for XCMD in "${XCMDS[@]}"; do command -v "$XCMD" >>/dev/null 2>&1; [ $? -ne 0 ] && echo "Not Found $XCMD."; done

osVer="$(dpkg --print-architecture 2>/dev/null)"
if [ -n "$osVer" -a "$osVer" == "amd64" ]; then
  debVer="$(cat /etc/issue |grep -io 'Debian.*' |sed -r 's/(.*)/\L\1/' |grep -o '[0-9.]*')"
  if [ "$debVer" == "9" ]; then
    #Install BBr for Debian9
    echo "Download: linux-image-4.14.153_4.14.153-1_amd64.deb"
    wget --no-check-certificate -qO '/tmp/linux-image-4.14.153_4.14.153-1_amd64.deb' 'https://download.fastgit.org/MoeClub/BBR/releases/download/all/linux-image-4.14.153_4.14.153-1_amd64.deb'
    dpkg -i '/tmp/linux-image-4.14.153_4.14.153-1_amd64.deb'
    [ $? -eq 0 ] || exit 1 

    sed -i '/net\.core\.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.conf
    while [ -z "$(sed -n '$p' /etc/sysctl.conf)" ]; do sed -i '$d' /etc/sysctl.conf; done
    sed -i '$a\net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n\n' /etc/sysctl.conf

    item="linux-image-4.14.153"
    while true; do
      List_Kernel="$(dpkg -l |grep 'linux-image\|linux-modules\|linux-generic\|linux-headers' |grep -v "${item}")"
       Num_Kernel="$(echo "$List_Kernel" |sed '/^$/d' |wc -l)"
       [ "$Num_Kernel" -eq "0" ] && break
       for kernel in `echo "$List_Kernel" |awk '{print $2}'`
       do
       if [ -f "/var/lib/dpkg/info/${kernel}.prerm" ]; then
        sed -i 's/linux-check-removal/#linux-check-removal/' "/var/lib/dpkg/info/${kernel}.prerm"
        sed -i 's/uname -r/echo purge/' "/var/lib/dpkg/info/${kernel}.prerm"
       fi
      dpkg --force-depends --purge "$kernel"
    done
    done
    apt-get autoremove -y
     [ -d /lib/modules/4.14.153/kernel/net/ipv4 ] && cd /lib/modules/4.14.153/kernel/net/ipv4 || exit 1

    echo 'Download: tcp_bbr.ko'
    wget --no-check-certificate -qO "tcp_bbr.ko" "https://raw.githubusercontent.com/MoeClub/apt/master/bbr/v${ver}/tcp_bbr.ko"

    echo 'Setting: limits.conf'
    [ -f /etc/security/limits.conf ] && LIMIT='262144' && sed -i '/^\(\*\|root\)[[:space:]]*\(hard\|soft\)[[:space:]]*\(nofile\|memlock\)/d' /etc/security/limits.conf && echo -ne "*\thard\tmemlock\t${LIMIT}\n*\tsoft\tmemlock\t${LIMIT}\nroot\thard\tmemlock\t${LIMIT}\nroot\tsoft\tmemlock\t${LIMIT}\n*\thard\tnofile\t${LIMIT}\n*\tsoft\tnofile\t${LIMIT}\nroot\thard\tnofile\t${LIMIT}\nroot\tsoft\tnofile\t${LIMIT}\n\n" >>/etc/security/limits.conf

    echo 'Setting: sysctl.conf'
    cat >/etc/sysctl.conf<<EOF
# This line below add by user.

fs.file-max = 104857600
fs.nr_open = 1048576
vm.overcommit_memory = 1
net.ipv4.ip_forward = 1
net.core.somaxconn = 4096
net.core.optmem_max = 262144
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_mem = 262144 6291456 8388608
net.ipv4.tcp_rmem = 16384 262144 8388608
net.ipv4.tcp_wmem = 8192 262144 8388608
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 4
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 24
net.ipv4.tcp_keepalive_intvl = 32
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_time = 900
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 8
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_slow_start_after_idle = 0
# net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

EOF

  fi
fi


mkdir -p /tmp
PublicIP="$(wget --no-check-certificate -4 -qO- http://checkip.amazonaws.com)"

# vlmcs
rm -rf /etc/vlmcs
wget --no-check-certificate -4 -qO /tmp/vlmcs.tar 'https://raw.githubusercontent.com/MoeClub/Note/master/AnyConnect/vlmcsd/vlmcsd.tar'
tar --overwrite -xvf /tmp/vlmcs.tar -C /
[ -f /etc/vlmcs/vlmcs.d ] && bash /etc/vlmcs/vlmcs.d init

# dnsmasq
rm -rf /etc/dnsmasq.d
wget --no-check-certificate -4 -qO /tmp/dnsmasq.tar 'https://raw.githubusercontent.com/MoeClub/Note/master/AnyConnect/build/dnsmasq_v2.82.tar'
tar --overwrite -xvf /tmp/dnsmasq.tar -C /
sed -i "s/#\?except-interface=.*/except-interface=${EthName}/" /etc/dnsmasq.conf

if [ -f /etc/crontab ]; then
  sed -i '/dnsmasq/d' /etc/crontab
  while [ -z "$(sed -n '$p' /etc/crontab)" ]; do sed -i '$d' /etc/crontab; done
  sed -i "\$a\@reboot root /usr/sbin/dnsmasq >>/dev/null 2>&1 &\n\n\n" /etc/crontab
fi

# ocserv
rm -rf /etc/ocserv
wget --no-check-certificate -4 -qO /tmp/ocserv.tar 'https://cdn.jsdelivr.net/gh/ixmu/Note@master/Anyconnect/build/ocserv_v1.1.1.tar'
tar --overwrite -xvf /tmp/ocserv.tar -C /

# server cert key file: /etc/ocserv/server.key.pem
openssl genrsa -out /etc/ocserv/server.key.pem 2048
# server cert file: /etc/ocserv/server.cert.pem
openssl req -new -x509 -days 3650 -key /etc/ocserv/server.key.pem -out /etc/ocserv/server.cert.pem -subj "/C=/ST=/L=/O=/OU=/CN=${PublicIP}"

# Default User
UserPasswd=`openssl passwd MoeClub`
echo -e "Default:Default:${UserPasswd}\nRoute:Route:${UserPasswd}\nNoRoute:NoRoute:${UserPasswd}\n" >/etc/ocserv/ocpasswd

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

#Ocserv Configuration
[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/^#\?user-profile.*/user-profile \= \/etc\/ocserv\/profile\.xml/g" /etc/ocserv/ocserv.conf;
[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/^#\?output-buffer.*/output-buffer \= 64/g" /etc/ocserv/ocserv.conf;
[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/max-clients.*/max-clients \= 256/g" /etc/ocserv/ocserv.conf;
[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/max-same-clients.*/max-same-clients \= 3/g" /etc/ocserv/ocserv.conf;
wget --no-check-certificate -4 -qO /etc/ocserv/profile.xml 'https://cdn.jsdelivr.net/gh/ixmu/Note@master/Anyconnect/ocserv/profile.xml'
wget --no-check-certificate -4 -qO /etc/ocserv/ca.cert.pem 'https://www.ixmu.net/project/ocserv/ca.cert.pem'
wget --no-check-certificate -4 -qO /etc/ocserv/server.key.pem 'https://www.ixmu.net/project/ocserv/server.key.pem'
wget --no-check-certificate -4 -qO /etc/ocserv/server.cert.pem 'https://www.ixmu.net/project/ocserv/server.cert.pem'

# Dnsmasq Configuration
[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/192\.168\.8/192\.168\.7/g" /etc/ocserv/ocserv.conf;
[ -f /etc/dnsmasq.conf ] && sed -i "s/192\.168\.8/192\.168\.7/g" /etc/dnsmasq.conf;
[ -f /etc/dnsmasq.conf ] && sed -i "s/server\=8\.8\.4\.4\#53/server\=120\.79\.152\.1\#10053/g" /etc/dnsmasq.conf;
[ -f /etc/dnsmasq.conf ] && sed -i "s/server\=8\.8\.8\.8\#53/server\=39\.105\.8\.165\#10053/g" /etc/dnsmasq.conf;

# Timezone
cp -f /usr/share/zoneinfo/PRC /etc/localtime
echo "Asia/Shanghai" >/etc/timezone

read -n 1 -p "Press <ENTER> to reboot..."
## Rebot Now
reboot

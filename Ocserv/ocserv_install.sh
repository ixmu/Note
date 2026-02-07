#!/bin/bash

DSNMASQ_VERSION="2.90"
OCSERV_VERSION="1.4.0"

[ $EUID -ne 0 ] && echo "Error:This script must be run as root!" && exit 1
EthName=`cat /proc/net/dev |grep ':' |cut -d':' -f1 |sed 's/\s//g' |grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv\|^vpn' |sed -n '1p'`
[ -n "$EthName" ] || exit 1

if command -v yum >/dev/null 2>&1; then
    yum install -y curl wget nc xz openssl gnutls-utils iptables-services cronie
elif command -v apt >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl wget openssl gnutls-bin xz-utils ncat iptables iptables-persistent cron
elif command -v apk >/dev/null 2>&1; then
    apk update
    apt-get install -y curl wget openssl gnutls-utils xz nmap-ncat iptables dcron
else
    echo "Shell Script Not Support OS."
    exit 1
fi

XCMDS=("wget" "tar" "xz" "nc" "openssl" "certtool")
for XCMD in "${XCMDS[@]}"; do command -v "$XCMD" >>/dev/null 2>&1; [ $? -ne 0 ] && echo "Not Found $XCMD."; done

case `uname -m` in aarch64|arm64) Arch="arm64";; x86_64|amd64) Arch="amd64";; *) Arch="";; esac
[ ! -n "$Arch" ] && echo "Arch Not Support! " && exit 1


mkdir -p /tmp
PublicIP="$(wget --no-check-certificate -4 -qO- http://checkip.amazonaws.com)"


# vlmcs
if [ "$Arch" == "amd64" ]; then
  rm -rf /etc/vlmcs
  wget --no-check-certificate -4 -qO /usr/sbin/vlmcsdmulti "https://raw.githubusercontent.com/ixmu/Note/refs/heads/master/Ocserv/build/vlmcsdmulti_${Arch}"
  chmod +x /usr/sbin/vlmcsdmulti
  curl -o /etc/systemd/system/vlmcsd.service https://raw.githubusercontent.com/ixmu/Note/master/Ocserv/build/vlmcsd.service
  systemctl daemon-reload
  systemctl enable vlmcsd.service --now >>/dev/null 2>&1
fi

# dnsmasq
rm -rf /etc/dnsmasq.d
wget --no-check-certificate -4 -qO /tmp/dnsmasq_bin.tar.xz "https://github.com/ixmu/dnsmasq-static/releases/download/v${DSNMASQ_VERSION}/dnsmasq-linux-${Arch}.tar.xz"
tar --overwrite -xvf /tmp/dnsmasq_bin.tar.xz -C /usr/local/
wget --no-check-certificate -4 -qO /tmp/dnsmasq_config.tar.gz "https://raw.githubusercontent.com/ixmu/Note/master/Ocserv/build/dnsmasq_config.tar.gz"
tar --overwrite -xvf /tmp/dnsmasq_config.tar.gz -C /
sed -i "s/#\?except-interface=.*/except-interface=${EthName}/" /etc/dnsmasq.conf
curl -o /etc/systemd/system/dnsmasq.service https://raw.githubusercontent.com/ixmu/Note/master/Ocserv/build/dnsmasq.service
systemctl daemon-reload
systemctl enable dnsmasq.service --now >>/dev/null 2>&1

# ocserv
rm -rf /etc/ocserv
wget --no-check-certificate -4 -qO /tmp/ocserv_bin.tar.xz "https://github.com/ixmu/openconnect-server-static/releases/download/v${OCSERV_VERSION}/openconnect-server-linux-${Arch}.tar.xz"
tar --overwrite -xvf /tmp/ocserv_bin.tar.xz -C /usr/local/
wget --no-check-certificate -4 -qO /tmp/ocserv_config.tar.gz "https://raw.githubusercontent.com/ixmu/Note/master/Ocserv/build/ocserv_config.tar.gz"
tar --overwrite -xvf /tmp/ocserv_config.tar.gz -C /
curl -o /etc/systemd/system/ocserv.service https://raw.githubusercontent.com/ixmu/Note/master/Ocserv/build/ocserv.service
[ ! -e /usr/sbin/ocserv ] && ln -s /usr/local/sbin/ocserv /usr/sbin/ocserv
systemctl daemon-reload


[ -d /lib/systemd/system ] && find /lib/systemd/system -name 'ocserv*' -delete

if [ -f /etc/ocserv/ctl.sh ]; then
  /bin/bash /etc/ocserv/template/client.sh -i
  /bin/bash /etc/ocserv/ctl.sh init
fi

# bbr
bash <(wget --no-check-certificate --no-cache -4 -qO- "https://raw.githubusercontent.com/ixmu/Note/refs/heads/master/Ocserv/build/bbr.sh")
# init
bash <(wget --no-check-certificate --no-cache -4 -qO- "https://raw.githubusercontent.com/ixmu/Note/refs/heads/master/Ocserv/build/init.sh")
# dnsmasq china option
curl -sSL https://github.com/felixonmars/dnsmasq-china-list/raw/refs/heads/master/accelerated-domains.china.conf | sed 's/114.114.114.114/223.5.5.5#53/' >/etc/dnsmasq.d/accelerated-domains.china.conf
# Timezone
cp -rf /usr/share/zoneinfo/PRC /etc/localtime 2>/dev/null
echo "Asia/Shanghai" >/etc/timezone

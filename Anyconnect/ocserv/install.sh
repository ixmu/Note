#!/bin/bash
# Script by Ixmu.Net

#定义参数
OCSERV_VERSION="1.0.0"
ifname=`cat /proc/net/dev |grep ":" |cut -d":" -f1| sed "s/[[:space:]]//g" |grep -v '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv' |head -n1`
PublicIP="$(wget --no-check-certificate -qO- http://checkip.amazonaws.com)"

#检测Root账户
[ $EUID -ne 0 ] && echo "Error:This script must be run as root!" && exit 1
#为Debian9安装BBR
if [ "$deb_ver" == "9" ]; then
  bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/BBR/master/install.sh')
  wget --no-check-certificate -qO '/tmp/tcp_bbr.ko' 'https://moeclub.org/attachment/LinuxSoftware/bbr/tcp_bbr.ko'
  cp -rf /tmp/tcp_bbr.ko /lib/modules/4.14.153/kernel/net/ipv4
  sed -i '/^net\.core\.default_qdisc/d' /etc/sysctl.conf
  sed -i '/^net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.conf
  while [ -z "$(sed -n '$p' /etc/sysctl.conf)" ]; do sed -i '$d' /etc/sysctl.conf; done
  sed -i '$a\net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n\n' /etc/sysctl.conf
fi
#安装依赖
apt-get update
apt-get install -y unzip p7zip-full gawk curl dnsmasq nload dnsutils iftop netcat 
apt-get install -y dbus init-system-helpers libc6 libev4  libgssapi-krb5-2 libhttp-parser2.1 liblz4-1 libnl-3-200 libnl-route-3-200 liboath0 libopts25 libpcl1 libprotobuf-c1 libsystemd0 libtalloc2 gnutls-bin ssl-cert 
apt-get install -y ethtool
apt-get install build-essential pkg-config libgnutls28-dev libreadline-dev libseccomp-dev libwrap0-dev libnl-nf-3-dev liblz4-dev  libev-dev gcc
#检测并配置iftop
command -v iftop >>/dev/null 2>&1
[[ $? -eq '0' ]] && {
cat >/root/.iftoprc<<EOF
interface: ${ifname}
dns-resolution: no
port-resolution: no
show-bars: yes
port-display: on
link-local: no
use-bytes: yes
sort: 2s
line-display: one-line-sent
show-totals: yes
log-scale: yes
EOF
}
# 配置Sysctl.conf
sed -i '/^net\.ipv4\.ip_forward/d' /etc/sysctl.conf
while [ -z "$(sed -n '$p' /etc/sysctl.conf)" ]; do sed -i '$d' /etc/sysctl.conf; done
sed -i '$a\net.ipv4.ip_forward = 1\n\n' /etc/sysctl.conf

# 配置 Limit
if [[ -f /etc/security/limits.conf ]]; then
  LIMIT='262144'
  sed -i '/^\(\*\|root\).*\(hard\|soft\).*\(memlock\|nofile\)/d' /etc/security/limits.conf
  while [ -z "$(sed -n '$p' /etc/security/limits.conf)" ]; do sed -i '$d' /etc/security/limits.conf; done
  echo -ne "*\thard\tnofile\t${LIMIT}\n*\tsoft\tnofile\t${LIMIT}\nroot\thard\tnofile\t${LIMIT}\nroot\tsoft\tnofile\t${LIMIT}\n" >>/etc/security/limits.conf
  echo -ne "*\thard\tmemlock\t${LIMIT}\n*\tsoft\tmemlock\t${LIMIT}\nroot\thard\tmemlock\t${LIMIT}\nroot\tsoft\tmemlock\t${LIMIT}\n\n\n" >>/etc/security/limits.conf
fi
# 设置时区
cp -f /usr/share/zoneinfo/PRC /etc/localtime
echo "Asia/Shanghai" >/etc/timezone
#安装ocserv
cd /root/
wget --no-check-certificate ftp://ftp.infradead.org/pub/ocserv/ocserv-${OCSERV_VERSION}.tar.xz
tar xvf ocserv-${OCSERV_VERSION}.tar.xz
cd ocserv-${OCSERV_VERSION}
./configure && make && make check

cp ./src/occtl/occtl /usr/bin/occtl
cp ./src/ocpasswd/ocpasswd /usr/bin/ocpasswd
cp ./src/ocserv-fw /usr/bin/ocserv-fw
cp ./src/ocserv /usr/sbin/ocserv

cat >/etc/init.d/ocserv <<EOF
#! /bin/sh
### BEGIN INIT INFO
# Provides:             ocserv
# Required-Start:       $all
# Required-Stop:        $all
# Default-Start:        2 3 4 5
# Default-Stop:         0 1 6
# Short-Description:    OpenConnect SSL VPN server
# Description:          secure, small, fast and configurable OpenConnect SSL VPN server
### END INIT INFO
set -e

NAME=ocserv
DESC="OpenConnect SSL VPN server"

DAEMON=/usr/sbin/ocserv
DAEMON_CONFIG=/etc/${NAME}/${NAME}.conf
DAEMON_PIDFILE=/var/run/${NAME}.pid
DAEMON_ARGS="--pid-file $DAEMON_PIDFILE --config $DAEMON_CONFIG"

test -x $DAEMON || exit 0

umask 022

. /lib/lsb/init-functions

export PATH="${PATH:+$PATH:}/usr/sbin:/sbin"

daemon_start()
{
    if [ ! -s "$DAEMON_CONFIG" ]; then
        log_failure_msg "please create ${DAEMON_CONFIG}, not starting..."
        log_end_msg 1
        exit 0
    fi
    log_daemon_msg "Starting $DESC" "$NAME" || true
    if start-stop-daemon --start --quiet --oknodo --pidfile $DAEMON_PIDFILE --exec $DAEMON -- $DAEMON_ARGS ; then
        log_end_msg 0 || true
    else
        log_end_msg 1 || true
    fi
}

case "$1" in
  start)
    daemon_start
    ;;
  stop)
    log_daemon_msg "Stopping $DESC" "$NAME" || true
    if start-stop-daemon --stop --quiet --oknodo --pidfile $DAEMON_PIDFILE; then
            log_end_msg 0 || true
        else
            log_end_msg 1 || true
        fi
        ;;

  reload|force-reload)
        log_daemon_msg "Reloading $DESC" "$NAME" || true
        if start-stop-daemon --stop --signal 1 --quiet --oknodo --pidfile $DAEMON_PIDFILE --exec $DAEMON; then
            log_end_msg 0 || true
        else
            log_end_msg 1 || true
        fi
        ;;

  restart)
        log_daemon_msg "Restarting $DESC" "$NAME" || true
        start-stop-daemon --stop --quiet --oknodo --retry 30 --pidfile $DAEMON_PIDFILE
        daemon_start
        ;;

  try-restart)
        log_daemon_msg "Restarting $DESC" "$NAME" || true
        RET=0
        start-stop-daemon --stop --quiet --retry 30 --pidfile $DAEMON_PIDFILE || RET="$?"
        case $RET in
            0)
                # old daemon stopped
                daemon_start
                ;;
            1)
                # daemon not running
                log_progress_msg "(not running)" || true
                log_end_msg 0 || true
                ;;
            *)
                # failed to stop
                log_progress_msg "(failed to stop)" || true
                log_end_msg 1 || true
                ;;
        esac
        ;;

  status)
        status_of_proc -p $DAEMON_PIDFILE $DAEMON $NAME && exit 0 || exit $?
        ;;

  *)
        log_action_msg "Usage: /etc/init.d/$NAME {start|stop|reload|force-reload|restart|try-restart|status}" || true
        exit 1
esac

exit 0
EOF

#配置DNSMASQ
[[ -f /etc/dnsmasq.conf ]] && {
cat >/etc/dnsmasq.conf<<EOF
except-interface=${ifname}
conf-dir=/etc/dnsmasq.d,*.conf
dhcp-range=172.16.100.2,172.16.100.254,255.255.255.0,24h
dhcp-option-force=option:router,172.16.100.1
dhcp-option-force=option:dns-server,172.16.100.1
dhcp-option-force=option:netbios-ns,172.16.100.1
listen-address=127.0.0.1,172.16.100.1
domain-needed
bind-dynamic
all-servers
bogus-priv
no-negcache
no-resolv
no-hosts
no-poll
cache-size=10000
server=208.67.220.220#5353
EOF
}
systemctl enable ocserv
systemctl enable dnsmasq

[[ -f /etc/ocserv/group/NoRoute ]] && sed -i 's/^no-route = .*\/255.255.255.255/no-route = '${PublicIP}'\/255.255.255.255/' /etc/ocserv/group/NoRoute
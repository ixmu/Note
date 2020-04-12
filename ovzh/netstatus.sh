#!/bin/bash
netstatus=`curl -o /dev/null -s -w %{http_code} https://gitee.com`
while(( $netstatus!=200 ))
do
    sleep 60s
    netstatus=`curl -o /dev/null -s -w %{http_code} https://gitee.com`
done
command -v wget >>/dev/null 2>&1
[[ $? -eq '1' ]] && {
yum install -y wget || apt-get install -y wget
}
bash <(wget --no-check-certificate -qO- 'https://gitee.com/pengxp1996/Note/raw/master/ovzh/checkdns.sh')


grep -rn "resizedisk.sh" *

Debian

sleep 180s
command -v wget >>/dev/null 2>&1
[[ $? -eq '1' ]] && {
yum install -y wget || apt-get install -y wget
}
bash <(wget --no-check-certificate -qO- 'https://gitee.com/pengxp1996/Note/raw/master/ovzh/checkdns.sh')

扩容磁盘

cat >resizedisk.sh<<EOF
#!/bin/sh
/usr/sbin/resize2fs /dev/vda1
rm -rf /etc/cron.d/resizedisk
rm -rf /resizedisk.sh
EOF

cat >/etc/cron.d/resizedisk_cron <<EOF
@reboot root bash /resizedisk.sh
EOF

chmod +x resizedisk.sh

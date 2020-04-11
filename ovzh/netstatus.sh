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
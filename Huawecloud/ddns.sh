#!/bin/bash
    key="JLXCJEK" #AccessKey
    secret="OwAODpwtrJuaSbIJ9" #AccessSecret
    action="add" # 操作方式 [add|del|list]  
    target="record" # 操作目标  [domain|record]  
    domain="chinatelecom.com" #操作域名
    name="gz-gd-cn" #操作的子域名
    type="A" #记录类型 [A|AAAA|TXT|MX|CNAME...]
    ttl="15" #默认 15

while true
do
    date="$(wget --no-check-certificate -4 -qO- http://checkip.amazonaws.com)" #获取公网ip
    curl "https://api.moeclub.org/HWDNS/?key=${key}&secret=${secret}&action=${action}&target=${target}&domain=${domain}&name=${name}&data=${date}&type=${type}&ttl=${ttl}"
    sleep 300 # sleep for 5 minutes
done
#!/bin/bash
echo "Hello World !"


bash /root/oneinstack/backup.sh 


date1=`date +%Y%m%d_%H`
date2=`date +%Y-%m-%d`
date3=`date -I -d "-45 day"`

rclone copy /data/backup/Web_www.423down.com_${date1}.tgz GoogleDrive:/423down_backup/${date2}/ -v
rclone copy /data/backup/DB_423down_${date1}.tgz GoogleDrive:/423down_backup/${date2}/ -v
rclone purge GoogleDrive:/423down_backup/${date3}

rclone lsf GoogleDrive:/423down_backup/2021-03-21  > /opt/bk.txt
sed -i 's/^/新增文件     &/g' /opt/bk.txt
sed -i 's/$/&\<br\>/g' /opt/bk.txt
echo "删除${date3}的备份文件（默认保留15份）" >> /opt/bk.txt

account='pengjinpwu@163.com'
password='NRSHBKZJKNLQHTSU'
to=172201424@qq.com
subject=`date +%Y-%m-%d_%H`自动化备份结果
content=`cat /opt/bk.txt`
sendemail -f $account -t $to -s smtp.163.com -u $subject -o message-content-type=html -o message-charset=utf8 -xu $account -xp $password -m $content



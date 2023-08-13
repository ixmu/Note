#!/usr/bin/env bash

Backup_Home="/home/backup/$(date +"%Y-%m-%d")"
Old_Backup_Home="/home/backup/$(date -d -15day +"%Y-%m-%d")"

MySQL_Dump="/usr/bin/mysqldump"
######~Set Directory you want to backup~######
Backup_Dir="/home/wwwroot"
Backup_domain=("domain1 "domain2")

######~Set MySQL Database you want to backup~######
Backup_Database=("database1" "database2")

######~Set MySQL UserName and password~######
MYSQL_Host='Mysql server address'
MYSQL_UserName='mysql username'
MYSQL_PassWord='mysql password'

######~Enable Ftp Backup~######
Enable_FTP=1
# 0: enable; 1: disable
######~Set FTP Information~######
FTP_Host='1.2.3.4'
FTP_Username='vpser.net'
FTP_Password='yourftppassword'
FTP_Dir="backup"

######~Enable ossutil Backup~######
Ossutil_Bin='/usr/sbin/ossutil'
Ossutil_config='/home/wwwroot/api.ixmu.net/ossutil/ossutil.config'
Ossutil_name='natural64'
Enable_ossutil=1
# 0: enable; 1: disable

#Values Setting END!

TodayWWWBackup=web-*.tar.gz
TodayDBBackup=db-*.sql
OldWWWBackup=web-*.tar.gz
OldDBBackup=db-*.sql

Backup_Website()
{
    Backup_Path=$1
    Dir_Name=`echo ${Backup_Path##*/}`
    Pre_Dir=`echo ${Backup_Path}|sed 's/'${Dir_Name}'//g'`
    tar zcf ${Backup_Home}/web-${Dir_Name}.tar.gz -C ${Pre_Dir} ${Dir_Name}
}
Backup_Sql()
{
    ${MySQL_Dump} -h$MYSQL_Host -u$MYSQL_UserName -p$MYSQL_PassWord $1 > ${Backup_Home}/db-$1.sql
}

if [ ! -f ${MySQL_Dump} ]; then  
    echo "mysqldump command not found.please check your setting."
    exit 1
fi

if [ ! -d ${Backup_Home} ]; then  
    mkdir -p ${Backup_Home}
fi

if [ ${Enable_FTP} = 0 ]; then
    type lftp >/dev/null 2>&1 || { echo >&2 "lftp command not found. Install: centos:yum install lftp,debian/ubuntu:apt-get install lftp."; }
fi

echo "Backup website files..."
for dd in ${Backup_domain[@]};do
    Backup_Website ${Backup_Dir}/${dd}
done

echo "Backup Databases..."
for db in ${Backup_Database[@]};do
    Backup_Sql ${db}
done

echo "Delete old backup files..."
rm -f ${Old_Backup_Home}

if [ ${Enable_FTP} = 0 ]; then
    echo "Uploading backup files to ftp..."
    cd ${Backup_Home}
    lftp ${FTP_Host} -u ${FTP_Username},${FTP_Password} << EOF
cd ${FTP_Dir}
mrm ${OldWWWBackup}
mrm ${OldDBBackup}
mput ${TodayWWWBackup}
mput ${TodayDBBackup}
bye
EOF
echo "complete."
fi

if [ ${Enable_ossutil} = 0 ]; then
    echo "Uploading backup files to AliyunOSS..."
    ${Ossutil_Bin} --config-file ${Ossutil_config} cp -r ${Backup_Home}/ oss://${Ossutil_name}/$(date +"%Y-%m-%d")/
    ${Ossutil_Bin} --config-file ${Ossutil_config} rm -rf oss://${Ossutil_name}/$(date -d -15day +"%Y-%m-%d")
    echo "complete."
fi

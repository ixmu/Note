#!/bin/bash


Backup_Home="/home/backup/"
MySQL_Dump="/usr/local/mariadb/bin/mysqldump"
######~Set Directory you want to backup~######
Backup_Dir=("备份目录1" "备份目录2")

######~Set MySQL Database you want to backup~######
Backup_Database=("备份数据库1" "备份数据库2" "wanvi_MyV2Ray")

######~Set MySQL UserName and password~######
MYSQL_UserName='Mysql_USERNAME'
MYSQL_PassWord='Mysql_PASSWD'

TodayWWWBackup=www-*-$(date +"%Y%m%d").tar.gz
TodayDBBackup=db-*-$(date +"%Y%m%d").sql
OldWWWBackup=www-*-$(date -d -15day +"%Y%m%d").tar.gz
OldDBBackup=db-*-$(date -d -15day +"%Y%m%d").sql

Backup_Dir()
{
    Backup_Path=$1
    Dir_Name=`echo ${Backup_Path##*/}`
    Pre_Dir=`echo ${Backup_Path}|sed 's/'${Dir_Name}'//g'`
    tar zcf ${Backup_Home}$(date +"%Y-%m-%d")/www-${Dir_Name}-$(date +"%Y%m%d").tar.gz -C ${Pre_Dir} ${Dir_Name}
}
Backup_Sql()
{
    ${MySQL_Dump} -u$MYSQL_UserName -p$MYSQL_PassWord $1 > ${Backup_Home}$(date +"%Y-%m-%d")/db-$1-$(date +"%Y%m%d").sql
}

if [ ! -f ${MySQL_Dump} ]; then  
    echo "mysqldump command not found.please check your setting."
    exit 1
fi

if [ ! -d ${Backup_Home}$(date +"%Y-%m-%d")/ ];then
  mkdir -p ${Backup_Home}$(date +"%Y-%m-%d")/
fi


echo "Backup website files..."
for dd in ${Backup_Dir[@]};do
    Backup_Dir ${dd}
done

echo "Backup Databases..."
for db in ${Backup_Database[@]};do
    Backup_Sql ${db}
done

echo "Upload files and databases to OSS..."
/usr/local/bin/ossutil cp -rf ${Backup_Home}$(date +"%Y-%m-%d") oss://natural64/$(date +"%Y-%m-%d")

echo "Delete old backup files stored locally..."
rm -rf ${Backup_Home}$(date -d -15day +"%Y-%m-%d")/

echo "Delete old oss backup files"
/usr/local/bin/ossutil rm -rf oss://natural64/$(date -d -60day +"%Y-%m-%d")


echo "complete."

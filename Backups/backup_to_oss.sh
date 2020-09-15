#!/bin/bash

# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

#  Mariadb/Mysql 数据库安装目录
db_install_dir=/usr/local/mariadb

#  备份存储临时目录
backup_dir=/home/backup

#  网站所在目录
wwwroot_dir=/home/wwwroot

#   Mariadb/Mysql ROOT密码
dbrootpwd=Vf58ujvprK2t0ghP

#   OSS bucket 请提前完成oss配置
oss_bucket=natural64


website_name=www.wanvi.net,shop.wanvi.net
db_name=wanvi_wordpress,wanvi_whmcs



[ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}


BK_DB() {
DBname=$1
LogFile=${backup_dir}/db.log
DumpFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H).sql
NewFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H).tgz
OldFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz

[ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}

DB_tmp=`${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "show databases\G" | grep ${DBname}`
[ -z "${DB_tmp}" ] && { echo "[${DBname}] not exist" >> ${LogFile} ;  exit 1 ; }

if [ -n "`ls ${OldFile} 2>/dev/null`" ]; then
  rm -f ${OldFile}
  echo "[${OldFile}] Delete Old File Success" >> ${LogFile}
else
  echo "[${OldFile}] Delete Old Backup File" >> ${LogFile}
fi

if [ -e "${NewFile}" ]; then
  echo "[${NewFile}] The Backup File is exists, Can't Backup" >> ${LogFile}
else
  ${db_install_dir}/bin/mysqldump -uroot -p${dbrootpwd} --databases ${DBname} > ${DumpFile}
  pushd ${backup_dir} > /dev/null
  tar czf ${NewFile} ${DumpFile##*/} >> ${LogFile} 2>&1
  echo "[${NewFile}] Backup success ">> ${LogFile}
  rm -f ${DumpFile}
  popd > /dev/null
fi
}
DB_OSS_BK() {
  for D in `echo ${db_name} | tr ',' ' '`
  do
    BK_DB ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
    /usr/local/bin/ossutil cp -f ${backup_dir}/${DB_FILE} oss://${oss_bucket}/`date +%F`/${DB_FILE}
    if [ $? -eq 0 ]; then
      /usr/local/bin/ossutil rm -rf oss://${oss_bucket}/`date +%F --date="${expired_days} days ago"`/
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${backup_dir}/${DB_FILE}
    fi
  done
}




WEB_OSS_BK() {
  for W in `echo $website_name | tr ',' ' '`
  do
    [ ! -e "${wwwroot_dir}/${WebSite}" ] && { echo "[${wwwroot_dir}/${WebSite}] not exist"; break; }
    PUSH_FILE="${backup_dir}/Web_${W}_$(date +%Y%m%d_%H).tgz"
    if [ ! -e "${PUSH_FILE}" ]; then
      pushd ${wwwroot_dir} > /dev/null
      tar czf ${PUSH_FILE} ./$W
      popd > /dev/null
    fi
    /usr/local/bin/ossutil cp -f ${PUSH_FILE} oss://${oss_bucket}/`date +%F`/${PUSH_FILE##*/}
    if [ $? -eq 0 ]; then
      /usr/local/bin/ossutil rm -rf oss://${oss_bucket}/`date +%F --date="${expired_days} days ago"`/
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${PUSH_FILE}
    fi
  done
}



DB_OSS_BK

WEB_OSS_BK


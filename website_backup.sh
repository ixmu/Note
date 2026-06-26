#!/usr/bin/env bash

# 基础设置
set -e
DATE_TODAY=$(date +"%Y-%m-%d")
DATE_OLD=$(date -d -15day +"%Y-%m-%d")
BACKUP_ROOT="/home/backup"
Backup_Home="${BACKUP_ROOT}/${DATE_TODAY}"
Old_Backup_Home="${BACKUP_ROOT}/${DATE_OLD}"

# --- 配置区 ---
MySQL_Dump="/usr/bin/mysqldump"
Backup_Dir="/home/wwwroot"
Backup_domain=("domain1" "domain2")
Backup_Database=("database1" "database2")

MYSQL_Host='localhost'
MYSQL_UserName='root'
MYSQL_PassWord='password'

Enable_FTP=1  # 0: enable; 1: disable
FTP_Host='1.2.3.4'; FTP_Username='user'; FTP_Password='pass'; FTP_Dir="backup"

Enable_ossutil=1 # 0: enable; 1: disable
Ossutil_Bin='/usr/sbin/ossutil'
Ossutil_config_dir='/root/.ossutilconfig' # 建议使用完整绝对路径
Ossutil_name='your_bucket_name'
oss_endpoint='oss-cn-hangzhou.aliyuncs.com'
oss_accessKeyID='your_id'
oss_accessKeySecret='your_secret'

# --- 核心函数 ---
Backup_Website() {
    local dir_path=$1
    local dir_name=$(basename "$dir_path")
    local pre_dir=$(dirname "$dir_path")
    echo "Backing up website: $dir_name"
    tar zcf "${Backup_Home}/web-${dir_name}.tar.gz" -C "$pre_dir" "$dir_name"
}

Backup_Sql() {
    local db_name=$1
    echo "Backing up database: $db_name"
    ${MySQL_Dump} -h"$MYSQL_Host" -u"$MYSQL_UserName" -p"$MYSQL_PassWord" "$db_name" > "${Backup_Home}/db-${db_name}.sql"
}

# --- 执行流程 ---
# 检查环境
[[ -f ${MySQL_Dump} ]] || { echo "mysqldump not found"; exit 1; }
mkdir -p "${Backup_Home}"

# 执行备份
for dd in "${Backup_domain[@]}"; do Backup_Website "${Backup_Dir}/${dd}"; done
for db in "${Backup_Database[@]}"; do Backup_Sql "${db}"; done

# 清理本地过期数据
if [[ -d "${Old_Backup_Home}" ]]; then
    echo "Deleting old local backup: ${Old_Backup_Home}"
    rm -rf "${Old_Backup_Home}"
fi

# FTP 上传
if [[ ${Enable_FTP} -eq 0 ]]; then
    echo "Uploading to FTP..."
    lftp -u "${FTP_Username},${FTP_Password}" "${FTP_Host}" << EOF
cd ${FTP_Dir}
rm -rf ${DATE_OLD}
mkdir ${DATE_TODAY}
cd ${DATE_TODAY}
mput ${Backup_Home}/*
bye
EOF
fi

# OSS 上传
if [[ ${Enable_ossutil} -eq 0 ]]; then
    echo "Uploading to Aliyun OSS..."
    # 确保配置文件存在
    if [[ ! -f "${Ossutil_config_dir}" ]]; then
        cat > "${Ossutil_config_dir}" << EOF
[Credentials]
language=CH
endpoint=${oss_endpoint}
accessKeyID=${oss_accessKeyID}
accessKeySecret=${oss_accessKeySecret}
EOF
    fi
    
    ${Ossutil_Bin} --config-file "${Ossutil_config_dir}" cp -r "${Backup_Home}/" "oss://${Ossutil_name}/${DATE_TODAY}/"
    ${Ossutil_Bin} --config-file "${Ossutil_config_dir}" rm -rf "oss://${Ossutil_name}/${DATE_OLD}/"
fi

echo "All tasks completed successfully."

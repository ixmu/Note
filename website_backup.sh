#!/usr/bin/env bash

# ==========================================
# 自动化备份脚本 - 支持本地/OSS/COS
# ==========================================

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
MYSQL_PassWord='your_password'

# 阿里云 OSS 配置
Enable_ossutil=1 # 0: enable; 1: disable
Ossutil_Bin='/usr/sbin/ossutil'
Ossutil_config='/root/.ossutilconfig'
Oss_Bucket='oss://your-bucket-name'

# 腾讯云 COS 配置
Enable_cos=1 # 0: enable; 1: disable
Cos_Bucket='your-bucket-name' # coscmd 默认从配置文件读取

# --- 函数区 ---
Backup_Website() {
    local dir_path=$1
    local dir_name=$(basename "$dir_path")
    local pre_dir=$(dirname "$dir_path")
    echo "正在备份网站: $dir_name"
    tar zcf "${Backup_Home}/web-${dir_name}.tar.gz" -C "$pre_dir" "$dir_name"
}

Backup_Sql() {
    local db_name=$1
    echo "正在备份数据库: $db_name"
    ${MySQL_Dump} -h"$MYSQL_Host" -u"$MYSQL_UserName" -p"$MYSQL_PassWord" "$db_name" > "${Backup_Home}/db-${db_name}.sql"
}

# --- 执行流程 ---
# 1. 环境准备
[[ -f ${MySQL_Dump} ]] || { echo "错误: mysqldump 未找到"; exit 1; }
mkdir -p "${Backup_Home}"

# 2. 开始备份
for dd in "${Backup_domain[@]}"; do Backup_Website "${Backup_Dir}/${dd}"; done
for db in "${Backup_Database[@]}"; do Backup_Sql "${db}"; done

# 3. 本地过期清理
if [[ -d "${Old_Backup_Home}" ]]; then
    rm -rf "${Old_Backup_Home}"
fi

# 4. 异地上传逻辑
# 阿里云 OSS
if [[ ${Enable_ossutil} -eq 0 ]]; then
    echo "正在上传到阿里云 OSS..."
    ${Ossutil_Bin} --config-file "${Ossutil_config}" cp -r "${Backup_Home}/" "${Oss_Bucket}/${DATE_TODAY}/"
    ${Ossutil_Bin} --config-file "${Ossutil_config}" rm -rf "${Oss_Bucket}/${DATE_OLD}/"
fi

# 腾讯云 COS
if [[ ${Enable_cos} -eq 0 ]]; then
    echo "正在上传到腾讯云 COS..."
    # 使用 coscmd，需提前完成 coscmd config 配置
    coscmd upload -r "${Backup_Home}/" "${DATE_TODAY}/"
    coscmd delete -r "${DATE_OLD}/"
fi

echo "=========================================="
echo "备份任务于 $(date) 全部完成"
echo "=========================================="

#备份到谷歌云盘
DB_GOOGLE_DRIVE_BK() {
  for D in `echo ${db_name} | tr ',' ' '`
  do
    ./db_bk.sh ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
        echo "数据库 ${D} 打包完成"

    /usr/bin/rclone copy ${backup_dir}/${DB_FILE} GoogleDrive://`date +%F`/
      echo "数据库 ${D} 打包上传完成"
    if [ $? -eq 0 ]; then
      /usr/bin/rclone purge GoogleDrive://`date +%F --date="${expired_days} days ago"`/
      echo "数据库 ${D} ${expired_days}天前的备份文件（如果存在）删除完成"
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${backup_dir}/${DB_FILE}
    fi
  done
}
WEB_GOOGLE_DRIVE_BK() {
  for W in `echo ${website_name} | tr ',' ' '`
  do
    [ ! -e "${wwwroot_dir}/${WebSite}" ] && { echo "[${wwwroot_dir}/${WebSite}] not exist"; break; }
    PUSH_FILE="${backup_dir}/Web_${W}_$(date +%Y%m%d_%H).tgz"
    if [ ! -e "${PUSH_FILE}" ]; then
      pushd ${wwwroot_dir} > /dev/null
      tar czf ${PUSH_FILE} ./$W
      popd > /dev/null
    fi
        echo "站点 $W 打包完成"
    /usr/bin/rclone copy  ${PUSH_FILE} GoogleDrive://`date +%F`/
        echo "站点 $W 打包上传完成"
    if [ $? -eq 0 ]; then
      /usr/bin/rclone purge GoogleDrive://`date +%F --date="${expired_days} days ago"`/
          echo "站点 $W ${expired_days}天前的备份文件（如果存在删除完成"
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${PUSH_FILE}
    fi
  done
}
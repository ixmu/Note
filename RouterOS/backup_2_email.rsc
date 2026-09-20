# SMTP服务器
:local SMTPServer "smtp.139.com"
# SMTP端口
:local SMTPPort "465"
# 收件邮箱
:local SendEmailTo "gzixmu@edu.cn"
# 发件邮箱
:local Sender "adminis@139.com"
# 发件邮箱密码
:local pwd "5ae998"
#邮件主题
:local Themes "RouteOS-Backup-"
# SMTP解析ip
:local SMTPIP [:resolve $SMTPServer]
# 配置邮件服务
/tool e-mail set server=$SMTPIP port=$SMTPPort tls=yes from=$Sender user=$Sender password=$pwd
# 获取系统日期
:local date [/system clock get date]
#获取系统时间
:local time [/system clock get time]
#获取系统版本信息
:local ROSVersion [/system resource get version]
# 获取主机名
:local RouterName [/system identity get name]
# 导出配置文件
/export file="config.rsc"
# 导出备份文件
/system backup save dont-encrypt=yes name="config"
#暂停收敛
:delay 2s
# 发送邮件
/tool e-mail send to=$SendEmailTo tls=yes from=$Sender subject=("RouteOS 备份") body=("设备名称: ".$RouterName."\n版本信息: ".$ROSVersion."\n备份时间".$date."-".$time) file=("config.rsc","config.backup")
# 暂停收敛
:delay 2s
# 移除配置文件
/file remove "config.rsc"
# 暂停收敛
:delay 2s
#移除备份文件
/file remove "config.backup"
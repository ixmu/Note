####Markdown在线编辑器

http://www.mdeditor.com/

####利用jsDeliver加速GitHub静态文件
```shell
$ https://cdn.jsdelivr.net/gh/你的用户名/你的仓库名@发布的版本号/文件路径
# 栗子：
$ https://cdn.jsdelivr.net/gh/ixmu/Note@1.0/ssh/PubkeyAuthentication # 加载1.0版本

# 注意： 如果不加  @发布的版本号  默认加载最新版本
# 栗子：
$ https://cdn.jsdelivr.net/gh/ixmu/Note/ssh/PubkeyAuthentication # 加载最新版本
```
####快速添加PubkeyAuthentication登录
```shell
bash <(curl -Lso- https://cdn.jsdelivr.net/gh/ixmu/Note/ssh/PubkeyAuthentication.sh)
```
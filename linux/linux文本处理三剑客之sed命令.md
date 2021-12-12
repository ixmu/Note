# linux文本处理三剑客之sed命令

sed被翻译为流编辑器（Stream Editor），主要用于处理、编辑文本文件，linux下可以利用sed命令自动编辑一个或多个文件，以简化对文件的反复操作和编辑，默认情况下不编辑源文件（添加-i参数的情况除外）。

```shell
Usage: sed [OPTION]... {script-only-if-no-other-script} [input-file]...

  -n, --quiet, --silent
                 suppress automatic printing of pattern space
  -e script, --expression=script
                 add the script to the commands to be executed
  -f script-file, --file=script-file
                 add the contents of script-file to the commands to be executed
  --follow-symlinks
                 follow symlinks when processing in place
  -i[SUFFIX], --in-place[=SUFFIX]
                 edit files in place (makes backup if SUFFIX supplied)
  -l N, --line-length=N
                 specify the desired line-wrap length for the `l' command
  --posix
                 disable all GNU extensions.
  -E, -r, --regexp-extended
                 use extended regular expressions in the script
                 (for portability use POSIX -E).
  -s, --separate
                 consider files as separate rather than as a single,
                 continuous long stream.
      --sandbox
                 operate in sandbox mode.
  -u, --unbuffered
                 load minimal amounts of data from the input files and flush
                 the output buffers more often
  -z, --null-data
                 separate lines by NUL characters
      --help     display this help and exit
      --version  output version information and exit

If no -e, --expression, -f, or --file option is given, then the first
non-option argument is taken as the sed script to interpret.  All
remaining arguments are names of input files; if no input files are
specified, then the standard input is read.

GNU sed home page: <http://www.gnu.org/software/sed/>.
General help using GNU software: <http://www.gnu.org/gethelp/>.
```

### 语法

```shell
sed [-hnV][-e<script>][-f<script文件>][文本文件]
```

### 参数说明

```shell
-n或--quiet或--silent 仅显示script处理后的结果。
--e<script>或--expression=<script> 以选项中指定的script来处理输入的文本文件。
-f<script文件>或--file=<script文件> 以选项中指定的script文件来处理输入的文本文件。
--follow-symlinks保持文件软连接特性，不自动转换为普通文件。
-l N, --line-length=N该选项指定l指令可以输出的行长度，l指令用于输出非打印字符。
--posix禁用sed扩展。
-E, -r, --regexp-extended使用正则表达式。
-u, --unbuffered从输入文件读取最少的数据，更频繁的刷新输出。
-z, --null-data定义分隔符，默认为n。
-i处理内容替换源文件的内容。
--help获取帮助信息。
--version打印版本信息。
```

### **操作说明**

```shell
a ：新增， a 的后面可以接字串，而这些字串会在新的一行出现(目前的下一行)～
c ：替换， c 的后面可以接字串，这些字串可以替换 n1,n2 之间的行！
d ：删除，因为是删除啊，所以 d 后面通常不接任何咚咚；
i ：插入， i 的后面可以接字串，而这些字串会在新的一行出现(目前的上一行)；
p ：打印，亦即将某个选择的数据印出。通常 p 会与参数 sed -n 一起运行～
s ：替换，可以直接进行替换的工作哩！通常这个 s 的操作可以搭配正规表示法！例如 1,20s/old/new/g 就是啦！
```

### 实例

在testfile文件的第四行后添加一行，内容为newLine，并将结果输出到标准输出，在命令行提示符下输入如下命令：
```shell
root@debian:~# cat testfile #打印testfile文件的内容
HELLO LINUX!  
Linux is a free unix-type opterating system.  
This is a linux testfile!  
Linux test 
root@debian:~# sed -e 4a\newline testfile #添加内容在第4行后
HELLO LINUX!  
Linux is a free unix-type opterating system.  
This is a linux testfile!  
Linux test 
newline
```

默认情况下newline这一行并没有写入到原始文件testfile中

#### 以行为单位的新增/删除

将 /etc/passwd 的内容列出并且列印行号，同时，请将第 2~5 行删除！

```shell
[root@www ~]# nl /etc/passwd | sed '2,5d'
1 root:x:0:0:root:/root:/bin/bash
6 sync:x:5:0:sync:/sbin:/bin/sync
7 shutdown:x:6:0:shutdown:/sbin:/sbin/shutdown
.....(后面省略).....
```

sed 的操作为 '2,5d' ，那个 d 就是删除！因为 2-5 行给他删除了，所以显示的数据就没有 2-5 行。

原本应该是要下达 sed -e 才对，没有 -e 也行啦！同时也要注意的是， sed 后面接的操作，请务必以 ' ' 两个单引号括住喔！

只要删除第 2 行

```shell
nl /etc/passwd | sed '2d' 
```

要删除第 3 到最后一行

```shell
nl /etc/passwd | sed '3,$d' 
# $符号表示最后一行
```

在第二行后添加一行，内容为：drink tea?

```shell
[root@www ~]# nl /etc/passwd | sed '2a drink tea'
1 root:x:0:0:root:/root:/bin/bash
2 bin:x:1:1:bin:/bin:/sbin/nologin
drink tea
3 daemon:x:2:2:daemon:/sbin:/sbin/nologin
.....(后面省略).....
```

那如果是要在第二行前插入1行，内容为：drink tea

```shell
nl /etc/passwd | sed '2i drink tea' 
```

如果是要增加两行以上，在第二行后面加入两行字，例如 **Drink tea or .....** 与 **drink beer?**

```shell
[root@www ~]# nl /etc/passwd | sed '2a Drink tea or ......\
> drink beer ?'
1 root:x:0:0:root:/root:/bin/bash
2 bin:x:1:1:bin:/bin:/sbin/nologin
Drink tea or ......
drink beer ?
3 daemon:x:2:2:daemon:/sbin:/sbin/nologin
.....(后面省略).....
```

每一行之间都必须要以反斜杠『 \ 』来进行新行的添加喔！所以，上面的例子中，我们可以发现在第一行的最后面就有 \ 存在。

#### 以行为单位的替换并打印

将第2-5行的内容替换成为『No 2-5 number』呢？

```shell
[root@www ~]# nl /etc/passwd | sed '2,5c No 2-5 number'
1 root:x:0:0:root:/root:/bin/bash
No 2-5 number
6 sync:x:5:0:sync:/sbin:/bin/sync
.....(后面省略).....
```

通过这个方法我们就能够将数据整行取代了！

仅列出 /etc/passwd 文件内的第 5-7 行

```shell
[root@www ~]# nl /etc/passwd | sed -n '5,7p'
5 lp:x:4:7:lp:/var/spool/lpd:/sbin/nologin
6 sync:x:5:0:sync:/sbin:/bin/sync
7 shutdown:x:6:0:shutdown:/sbin:/sbin/shutdown
```

可以通过这个 sed 的以行为单位的显示功能， 就能够将某一个文件内的某些行号选择出来显示。

#### 数据的搜寻并打印

搜索 /etc/passwd有root关键字的行

```shell
nl /etc/passwd | sed '/root/p'
1  root:x:0:0:root:/root:/bin/bash
1  root:x:0:0:root:/root:/bin/bash
2  daemon:x:1:1:daemon:/usr/sbin:/bin/sh
3  bin:x:2:2:bin:/bin:/bin/sh
4  sys:x:3:3:sys:/dev:/bin/sh
5  sync:x:4:65534:sync:/bin:/bin/sync
....下面忽略 
```

如果root找到，除了输出所有行，还会输出匹配行。

使用-n的时候将只打印包含模板的行。

```shell
nl /etc/passwd | sed -n '/root/p'
1  root:x:0:0:root:/root:/bin/bash
```

#### 数据的查找并删除

删除/etc/passwd所有包含root的行，其他行输出

```shell
nl /etc/passwd | sed  '/root/d'
2  daemon:x:1:1:daemon:/usr/sbin:/bin/sh
3  bin:x:2:2:bin:/bin:/bin/sh
....下面忽略
#第一行的匹配root已经删除了
```

#### 数据的查找并执行命令

搜索/etc/passwd,找到root对应的行，执行后面花括号中的一组命令，每个命令之间用分号分隔，这里把bash替换为blueshell，再输出这行：

```shell
nl /etc/passwd | sed -n '/root/{s/bash/blueshell/;p;q}'    
1  root:x:0:0:root:/root:/bin/blueshell
```

最后的q是退出。

#### 数据的查找并替换

除了整行的处理模式之外， sed 还可以用行为单位进行部分数据的搜寻并取代。基本上 sed 的搜寻与替代的与 vi 相当的类似！他有点像这样：

```shell
sed 's/要被取代的字串/新的字串/g'
```

先观察原始信息，利用 /sbin/ifconfig 查询 IP

```shell
[root@www ~]# /sbin/ifconfig eth0
eth0 Link encap:Ethernet HWaddr 00:90:CC:A6:34:84
inet addr:192.168.1.100 Bcast:192.168.1.255 Mask:255.255.255.0
inet6 addr: fe80::290:ccff:fea6:3484/64 Scope:Link
UP BROADCAST RUNNING MULTICAST MTU:1500 Metric:1
.....(以下省略).....
```

本机的ip是192.168.1.100。

将 IP 前面的部分予以删除

```shell
[root@www ~]# /sbin/ifconfig eth0 | grep 'inet addr' | sed 's/^.*addr://g'
192.168.1.100 Bcast:192.168.1.255 Mask:255.255.255.0
```

接下来则是删除后续的部分，亦即： 192.168.1.100 Bcast:192.168.1.255 Mask:255.255.255.0

将 IP 后面的部分予以删除

```shell
[root@www ~]# /sbin/ifconfig eth0 | grep 'inet addr' | sed 's/^.*addr://g' | sed 's/Bcast.*$//g'
192.168.1.100
```

#### 多点编辑

一条sed命令，删除/etc/passwd第三行到末尾的数据，并把bash替换为blueshell

```shell
nl /etc/passwd | sed -e '3,$d' -e 's/bash/blueshell/'
1  root:x:0:0:root:/root:/bin/blueshell
2  daemon:x:1:1:daemon:/usr/sbin:/bin/sh
```

-e表示多点编辑，第一个编辑命令删除/etc/passwd第三行到末尾的数据，第二条命令搜索bash替换为blueshell。

#### 直接修改文件内容(危险操作)

sed 可以直接修改文件的内容，不必使用管道命令或数据流定向！ 不过，由于这个操作会直接修改到原始的文件，所以请你千万不要随便拿系统配置来测试！ 我们还是使用文件 regular_express.txt 文件来测试看看吧！

regular_express.txt 文件内容如下：

```shell
[root@www ~]# cat regular_express.txt 
runoob.
google.
taobao.
facebook.
zhihu-
weibo-
```

利用 sed 将 regular_express.txt 内每一行结尾若为 . 则换成 !

```shell
[root@www ~]# sed -i 's/\.$/\!/g' regular_express.txt
[root@www ~]# cat regular_express.txt 
runoob!
google!
taobao!
facebook!
zhihu-
weibo-
```

利用 sed 直接在 regular_express.txt 最后一行加入 **# This is a test**:

```shell
[root@www ~]# sed -i '$a # This is a test' regular_express.txt
[root@www ~]# cat regular_express.txt 
runoob!
google!
taobao!
facebook!
zhihu-
weibo-
# This is a test
```

由于 $ 代表的是最后一行，而 a 的操作是新增，因此该文件最后新增 **# This is a test**！

sed 的 **-i** 选项可以直接修改文件内容，这功能非常有帮助！举例来说，如果你有一个 100 万行的文件，你要在第 100 行加某些文字，此时使用 vim 可能会疯掉！因为文件太大了！那怎办？就利用 sed 啊！透过 sed 直接修改/取代的功能，你甚至不需要使用 vim 去修订！

### 笔记

```shell
sed -e 4a\newline testfile
```

a 操作是在匹配的行之后追加字符串，追加的字符串中可以包含换行符（实现追加多行的情况）。

追加一行的话前后都不需要添加换行符 **\n**，只有追加多行时在行与行之间才需要添加换行符

例如：

在第4行之后添加一行：

```
sed -e '4 a newline' testfile
```

在第4行之后追加2行：

```
sed -e '4 a newline\nnewline2' testfile
```

在第4行之后追加3行(2 行文字和 1 行空行)

```
sed -e '4 a newline\nnewline2\n' testfile
```

在第4行之后追加1行空行：

```
#错误：sed -e '4 a \n' testfile
sed -e '4 a \ ' testfile 实际上
```

实际上是插入了一个含有一个空格的行，插入一个完全为空的空行没有找到方法（不过应该没有这个需求吧，都要插入行了插入空行干嘛呢？）

添加空行：

```shell
# 可以添加一个完全为空的空行
sed '4 a \\'

# 可以添加两个完全为空的空行
sed '4 a \\n'
```
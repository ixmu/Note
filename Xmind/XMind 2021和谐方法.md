# 2021.5.8：果核提供的思路

## 1、环境配置

安装Node.js：http://nodejs.cn/download/

安装asar：

- Windows：npm install -g asar
- macos：sudo npm install -g asar


## 2、拆包

- Windows：asar extract C:\Program Files\XMind\resources\app.asar C:\Users\zhou\Desktop\app
- macOS：asar extract /Applications/XMind.app/Contents/Resources/app.asar /Users/zhou/Desktop/app

## 3、修改

【删除的内容，果核要求保密】

## 4、封包


- Windows：asar pack C:\Users\zhou\Desktop\app C:\Users\zhou\Desktop\app.asar
- macOS：asar pack /Users/zhou/Desktop/app /Users/zhou/Desktop/app.asar

---

# 2021.7.15：Windows上出现了新的破解方法

新建批处理，放到XMind目录里发到桌面运行，来解锁XMind2021大客户版：

```
@echo off
set VANA_LICENSE_TO="XMind Cracker"
set VANA_LICENSE_MODE=true
start "" "%~dp0\XMind.exe"
```
---

# Windows上也可以按下面的步骤操作：

![](https://tva1.sinaimg.cn/large/008i3skNly1gsk596djzyj30yq0u0jt0.jpg)

![](https://tva1.sinaimg.cn/large/008i3skNly1gsk5965xplj60ts0xetbd02.jpg)

![](https://tva1.sinaimg.cn/large/008i3skNly1gsk595vhqpj30v20u077k.jpg)

![](https://tva1.sinaimg.cn/large/008i3skNly1gskau1vho3j312q0bmab0.jpg)

![](https://tva1.sinaimg.cn/large/008i3skNly1gsk595exphj312c0bc0ti.jpg)

![](https://tva1.sinaimg.cn/large/008i3skNly1gsk5955p3qj31bj0u040l.jpg)

注册表保存的位置为：


```
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment]
"VANA_LICENSE_MODE"="true"
"VANA_LICENSE_TO"="胡萝卜周"
```
但经过测试，直接导入注册表好像不会激活，还是需要手动添加环境变量项目。

---

# Windows上还能这样修改

（来源：https://bbs.pediy.com/thread-266182.htm）

在main.js开头加上两行代码：

```
process.env.VANA_LICENSE_MODE = "true";
process.env.VANA_LICENSE_TO = "注册名称";
```
经测试，在Windows上成功了，macOS上不行，会崩溃。另外，大客户版貌似取消了自动更新功能，也就是说可以不用修改更新网址了。
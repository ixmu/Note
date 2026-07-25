@echo off
:: 自动请求管理员权限
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo 正在请求管理员权限...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"

:MENU
cls
echo ===================================================
echo               Windows TTL 修改/还原工具
echo ===================================================
echo.
echo   [1] 一键修改 TTL 为 65  (绕过热点检测/抵消1次转发)
echo   [2] 一键修改 TTL 为 129 (针对原生 Windows 加 1)
echo   [3] 一键移除自定义 TTL  (恢复系统默认)
echo   [0] 退出
echo   https://github.com/cyborg-one/nfqttl
echo.
echo ===================================================
set /p choice=请输入数字序号后按回车: 

if "%choice%"=="1" goto SET_65
if "%choice%"=="2" goto SET_129
if "%choice%"=="3" goto REMOVE_TTL
if "%choice%"=="0" goto END
goto MENU

:SET_65
echo.
echo 正在将 DefaultTTL 设置为 65 (十进制)...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "DefaultTTL" /t REG_DWORD /d 65 /f >nul
if %errorlevel% equ 0 (
    echo [成功] TTL 已成功设置为 65！
) else (
    echo [失败] 修改失败，请确保以管理员身份运行。
)
pause
goto MENU

:SET_129
echo.
echo 正在将 DefaultTTL 设置为 129 (十进制)...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "DefaultTTL" /t REG_DWORD /d 129 /f >nul
if %errorlevel% equ 0 (
    echo [成功] TTL 已成功设置为 129！
) else (
    echo [失败] 修改失败，请确保以管理员身份运行。
)
pause
goto MENU

:REMOVE_TTL
echo.
echo 正在移除 DefaultTTL 注册表项，恢复系统默认...
reg delete "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "DefaultTTL" /f >nul 2>&1
if %errorlevel% equ 0 (
    echo [成功] 已彻底移除 DefaultTTL，恢复系统初始状态！
) else (
    echo [提示] 未找到自定义 DefaultTTL 项或已恢复默认。
)
pause
goto MENU

:END
exit
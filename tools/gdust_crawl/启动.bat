@echo off
chcp 65001 >nul
cd /d "%~dp0"

rem 优先用 pythonw（不弹黑色控制台窗口）
where pythonw >nul 2>&1
if %errorlevel%==0 (
    start "" pythonw "gui.py"
    exit /b
)

rem 退而求其次用 python（会带一个控制台窗口）
where python >nul 2>&1
if %errorlevel%==0 (
    echo 未找到 pythonw，改用 python 启动（会多一个控制台窗口，属正常）
    python "gui.py"
    pause
    exit /b
)

echo.
echo  ============================================
echo   没有找到 Python
echo  ============================================
echo.
echo  这个工具需要 Python 3.10 或更高版本。
echo.
echo  安装方法：
echo    1. 打开 https://www.python.org/downloads/
echo    2. 下载 Windows 安装包并运行
echo    3. 安装第一页务必勾选 "Add python.exe to PATH"
echo    4. 装完后重新双击本文件
echo.
pause

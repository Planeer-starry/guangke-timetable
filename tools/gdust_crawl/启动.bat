@echo off
rem Launcher for the GDUST timetable crawler GUI.
rem Keep this file PURE ASCII: cmd.exe reads .bat as ANSI (GBK on Chinese
rem Windows), so a UTF-8 file containing Chinese would be mojibake and the
rem script would fail to parse. All Chinese UI lives in gui.py instead.

cd /d "%~dp0"

where pythonw >nul 2>&1
if %errorlevel%==0 (
    start "" pythonw "gui.py"
    exit /b
)

where python >nul 2>&1
if %errorlevel%==0 (
    python "gui.py"
    pause
    exit /b
)

echo.
echo   Python not found.
echo.
echo   This tool needs Python 3.10 or newer.
echo.
echo   Install:
echo     1. Open https://www.python.org/downloads/
echo     2. Download the Windows installer and run it
echo     3. IMPORTANT: check "Add python.exe to PATH" on the first page
echo     4. Then double-click this file again
echo.
pause

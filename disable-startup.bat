@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Please run this script as Administrator!
    pause
    exit /b
)

set "TASK_NAME=WindowsSystemDeepCleaner"

schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1

echo.
echo ========================================================
echo [SUCCESS] Auto-cleaner task successfully disabled.
echo ========================================================
pause
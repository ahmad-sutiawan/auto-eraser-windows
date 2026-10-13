@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Please run this script as Administrator!
    pause
    exit /b
)

set "SCRIPT_PATH=%~dp0cleaner.ps1"
set "TASK_NAME=WindowsSystemDeepCleaner"

schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1

schtasks /create /tn "%TASK_NAME%" /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%SCRIPT_PATH%\"" /sc ONSTART /ru "SYSTEM" /f

if %errorLevel% equ 0 (
    echo.
    echo ========================================================
    echo [SUCCESS] Auto-cleaner task successfully enabled.
    echo ========================================================
) else (
    echo.
    echo [ERROR] Failed to register task scheduler.
)
pause
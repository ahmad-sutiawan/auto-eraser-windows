@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

net session >nul 2>&1
if errorlevel 1 goto :elevate

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleaner.ps1" -Action Disable
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%

:elevate
echo Requesting administrator permission...
set "ELEVATE_BAT=%~f0"
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath ($env:SystemRoot + '\System32\cmd.exe') -ArgumentList '/c', ('""' + $env:ELEVATE_BAT + '""') -Verb RunAs"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" exit /b 0

echo.
echo [ERROR] Administrator permission was not granted.
echo.
pause
exit /b 1

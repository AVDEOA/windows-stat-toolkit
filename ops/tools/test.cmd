@echo off
setlocal
cd /d "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\app\src\Validate-Toolkit.ps1"
exit /b %ERRORLEVEL%

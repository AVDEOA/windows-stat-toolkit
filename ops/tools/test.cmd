@echo off
setlocal
cd /d "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\app\src\Validate-Toolkit.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%
dotnet build ".\app\desktop\WindowsStatToolkit.Desktop\WindowsStatToolkit.Desktop.csproj"
exit /b %ERRORLEVEL%

@echo off
setlocal
cd /d "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\app\src\Validate-Toolkit.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%
dotnet publish ".\app\desktop\WindowsStatToolkit.Desktop\WindowsStatToolkit.Desktop.csproj" -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true -o ".\artifacts\desktop-publish"
exit /b %ERRORLEVEL%

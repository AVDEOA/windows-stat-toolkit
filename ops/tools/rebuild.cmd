@echo off
setlocal
cd /d "%~dp0\..\.."
set "TARGET=.\artifacts\runtime-src"
if exist "%TARGET%" rmdir /s /q "%TARGET%"
mkdir "%TARGET%" || exit /b %ERRORLEVEL%
robocopy ".\app\src" "%TARGET%" /E /XD bin obj artifacts /XF *.log >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 exit /b %RC%
echo rebuild OK: %TARGET%

@echo off
setlocal
cd /d "%~dp0\..\.."
set "TARGET=.\artifacts\runtime-src"
set "DESKTOP_TARGET=.\artifacts\runtime-desktop-src"
if exist "%TARGET%" rmdir /s /q "%TARGET%"
if exist "%DESKTOP_TARGET%" rmdir /s /q "%DESKTOP_TARGET%"
mkdir "%TARGET%" || exit /b %ERRORLEVEL%
mkdir "%DESKTOP_TARGET%" || exit /b %ERRORLEVEL%
robocopy ".\app\src" "%TARGET%" /E /XD bin obj artifacts state /XF *.log >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 exit /b %RC%
robocopy ".\app\desktop\WindowsStatToolkit.Desktop" "%DESKTOP_TARGET%" /E /XD bin obj .vs >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 exit /b %RC%
echo rebuild OK: %TARGET% and %DESKTOP_TARGET%

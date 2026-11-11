@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\save_diagnostics.ps1"
set "CODE=%ERRORLEVEL%"
echo.
pause
exit /b %CODE%

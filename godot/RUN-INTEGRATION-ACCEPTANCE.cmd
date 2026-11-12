@echo off
setlocal
cd /d "%~dp0"
set "MODE=quick"
if /I "%~1"=="all" set "MODE=all"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_integration_acceptance.ps1" -Mode "%MODE%"
set "CODE=%ERRORLEVEL%"
echo Reports: "%~dp0logs\integration-acceptance"
pause
exit /b %CODE%

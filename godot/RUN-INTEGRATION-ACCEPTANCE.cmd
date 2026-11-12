@echo off
setlocal
cd /d "%~dp0"
set "MODE=quick"
if /I "%~1"=="all" set "MODE=all"
if not defined GODOT_SMOKE_TIMEOUT set "GODOT_SMOKE_TIMEOUT=90"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_integration_acceptance.ps1" -Mode "%MODE%" -TimeoutSeconds %GODOT_SMOKE_TIMEOUT%
set "CODE=%ERRORLEVEL%"
echo Reports: "%~dp0logs\integration-acceptance"
pause
exit /b %CODE%

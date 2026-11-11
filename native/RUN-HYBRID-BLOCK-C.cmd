@echo off
setlocal
cd /d "%~dp0"
if not exist "target\debug\genesis_server.exe" (
  echo First run VERIFY-AI-BLOCK-BC.cmd and fix any compile errors.
  pause
  exit /b 1
)
set "BIND_ADDR=127.0.0.1:18081"
set "DATA_DIR=%~dp0priv\galaxy\data"
set "DATABASE_PATH=%~dp0ai-block-c-hybrid.db"
set "LIVING_SECTOR_UI_DIR=%~dp0observer"
set "LIVING_SECTOR_GALAXY=1"
set "LIVING_SECTOR_STRATEGY_MODE=execute"
set "LIVING_SECTOR_PLANNER=hybrid"
set "LIVING_SECTOR_PLANNER_SHADOW=1"
set "WORLD_SPEED=16"
echo HYBRID is experimental. Isolated database: ai-block-c-hybrid.db
start "Living Sector Hybrid test" /D "%~dp0" "target\debug\genesis_server.exe"
powershell -NoProfile -Command "$ready=$false;for($i=0;$i -lt 45;$i++){try{Invoke-WebRequest 'http://127.0.0.1:18081/api/health' -UseBasicParsing -TimeoutSec 2|Out-Null;$ready=$true;break}catch{};Start-Sleep -Seconds 1};if($ready){Start-Process 'http://127.0.0.1:18081/observer'}else{Write-Host 'Server not ready: check the server console.'}"
endlocal

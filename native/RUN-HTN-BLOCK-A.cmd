@echo off
setlocal
cd /d "%~dp0"
if not exist "target\debug\genesis_server.exe" (
  echo First run VERIFY-AI-BLOCK-A.cmd, which compiles this exact source.
  pause
  exit /b 1
)
set "BIND_ADDR=127.0.0.1:18080"
set "DATA_DIR=%~dp0priv\galaxy\data"
set "DATABASE_PATH=%~dp0ai-block-a-htn.db"
set "LIVING_SECTOR_UI_DIR=%~dp0observer"
set "LIVING_SECTOR_GALAXY=1"
set "LIVING_SECTOR_STRATEGY_MODE=execute"
set "LIVING_SECTOR_PLANNER=htn"
set "WORLD_SPEED=16"
echo Starting OPT-IN HTN on an isolated local test database.
echo The normal Living Sector save is NOT used.
echo Visit http://127.0.0.1:18080/observer
start "Living Sector HTN test - close window when finished" /D "%~dp0" "target\debug\genesis_server.exe"
powershell -NoProfile -Command "$ready=$false;for($i=0;$i -lt 45;$i++){try{Invoke-WebRequest 'http://127.0.0.1:18080/api/health' -UseBasicParsing -TimeoutSec 2|Out-Null;$ready=$true;break}catch{};Start-Sleep -Seconds 1};if($ready){Start-Process 'http://127.0.0.1:18080/observer'}else{Write-Host 'Server did not start. See its console.'}"
endlocal

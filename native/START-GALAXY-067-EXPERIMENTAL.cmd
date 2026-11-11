@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if not exist "%~dp0Genesis-Server.exe" (
  echo ERROR: Genesis-Server.exe is missing. Extract the complete experimental ZIP.
  pause
  exit /b 1
)
if not exist "%~dp0priv\galaxy\data\factions.json" (
  echo ERROR: Galaxy world data is missing. Extract the complete experimental ZIP.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=New-Object Net.Sockets.TcpClient;try{$t.Connect('127.0.0.1',18067);exit 1}catch{exit 0}finally{$t.Dispose()}"
if errorlevel 1 (
  echo ERROR: Port 18067 is occupied. Close the previous experimental server.
  pause
  exit /b 1
)
set "BIND_ADDR=127.0.0.1:18067"
set "DATABASE_PATH=%~dp0galaxy-067-experimental.db"
set "DATA_DIR=%~dp0priv\galaxy\data"
set "LIVING_SECTOR_UI_DIR=%~dp0observer"
set "LIVING_SECTOR_GALAXY=1"
set "LIVING_SECTOR_STRATEGY_MODE=execute"
set "WORLD_SPEED=16"
set "LIVING_SECTOR_PLANNER="
echo Living Sector 0.6.7 EXPERIMENTAL - 8 systems, 3 factions, baseline AI.
echo This is an isolated save: galaxy-067-experimental.db
echo No old game databases will be opened. No GitHub Actions required.
start "Living Sector Experimental 067" /D "%~dp0" "%~dp0Genesis-Server.exe"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false;for($i=0;$i -lt 90;$i++){try{$r=Invoke-WebRequest 'http://127.0.0.1:18067/api/health' -UseBasicParsing -TimeoutSec 2;if($r.StatusCode -eq 200){$ok=$true;break}}catch{};Start-Sleep -Milliseconds 500};if($ok){Start-Process 'http://127.0.0.1:18067/observer/'}else{Write-Host 'ERROR: Native server did not start. Read the other console.';exit 1}"
if errorlevel 1 pause
endlocal

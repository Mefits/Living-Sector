@echo off
setlocal
cd /d "%~dp0"

if not exist "%~dp0Living-Sector.exe" (
  echo Living-Sector.exe is missing. Extract Genesis into the existing Windows Observer folder.
  pause
  exit /b 1
)
if not exist "%~dp0priv\genesis\data\factions.json" (
  echo Missing Genesis data files. Extract the ZIP preserving its folders.
  pause
  exit /b 1
)
rem Never attach Genesis to an already-running large-world server.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri 'http://127.0.0.1:8080/api/health' -UseBasicParsing -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 (
  echo Another Living Sector simulator is already listening on port 8080.
  echo Close its console with Ctrl+C, then start Genesis again.
  pause
  exit /b 1
)

rem A separate database preserves the old 284-ship stress-test world.
set "BIND_ADDR=127.0.0.1:8080"
set "DATA_DIR=%~dp0priv\genesis\data"
set "DATABASE_PATH=%~dp0genesis-logistics-v1.db"
set "LIVING_SECTOR_UI_DIR=%~dp0observer"
set "WORLD_SPEED=1.0"

echo Genesis small-world preview: 1 system, 1 faction, 3 ships.
echo Database: genesis-logistics-v1.db (older genesis.db and sim.db remain untouched).
start "Living Sector - Genesis" /D "%~dp0" "%~dp0Living-Sector.exe" --headless

rem Wait for headless server readiness, then pause before opening the UI.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ready=$false; for($i=0;$i -lt 75;$i++){try{$r=Invoke-WebRequest -Uri 'http://127.0.0.1:8080/api/health' -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -eq 200){$ready=$true;break}}catch{}; Start-Sleep -Seconds 1}; if(-not $ready){Write-Host 'Genesis failed to start. Check the simulator window.';exit 1}; try{Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/sim/pause' -Method Post -ContentType 'application/json' -Body '{}' | Out-Null}catch{Write-Host 'Could not pause simulation automatically.'}; Start-Process 'http://127.0.0.1:8080/observer'"
if errorlevel 1 pause
endlocal

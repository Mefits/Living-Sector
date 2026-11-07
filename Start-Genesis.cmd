@echo off
setlocal
cd /d "%~dp0"

rem Genesis Core uses the ORIGINAL ECS/AI/economy/SQLite server as a standalone
rem executable. It does NOT require the Bevy 3D executable or its game assets.
if not exist "%~dp0Genesis-Server.exe" (
  echo Genesis-Server.exe is missing. Extract the full Genesis Core ZIP.
  pause
  exit /b 1
)
if not exist "%~dp0priv\genesis\data\factions.json" (
  echo Missing Genesis world data. Extract the ZIP preserving folders.
  pause
  exit /b 1
)
if not exist "%~dp0priv\genesis\data\tuning.json" (
  echo Missing world rules. This build must disable free ship respawns.
  pause
  exit /b 1
)
if not exist "%~dp0observer\index.html" (
  echo Missing 2D Observer interface.
  pause
  exit /b 1
)

rem One server per port. Never reuse the main simulator's running process.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri 'http://127.0.0.1:8080/api/health' -UseBasicParsing -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 (
  echo A Living Sector server already uses port 8080.
  echo Close its console before launching this world.
  pause
  exit /b 1
)

set "BIND_ADDR=127.0.0.1:8080"
set "DATA_DIR=%~dp0priv\genesis\data"
set "DATABASE_PATH=%~dp0genesis-mining-pilot-v1.db"
set "LIVING_SECTOR_UI_DIR=%~dp0observer"
set "WORLD_SPEED=1.0"
set "LIVING_SECTOR_STRATEGY_MODE=execute"

echo Living Sector MINING PILOT: paid farms, 3 native ice miners, Observer V5.
echo Database: genesis-mining-pilot-v1.db. Older saves remain untouched.
echo Use Ctrl+C in the Genesis Server console for a graceful save.
start "Living Sector - Genesis Core" /D "%~dp0" "%~dp0Genesis-Server.exe"

rem Unified integration: economy F1-F4, V5 UI and fixes are active. Ship mining and true station modules remain future features.
rem Pause for inspection only after the HTTP endpoint becomes ready.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ready=$false; for($i=0;$i -lt 75;$i++){try{$r=Invoke-WebRequest -Uri 'http://127.0.0.1:8080/api/health' -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -eq 200){$ready=$true;break}}catch{}; Start-Sleep -Seconds 1}; if(-not $ready){Write-Host 'Server did not start. Check Genesis Server window.';exit 1}; try{Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/sim/pause' -Method Post -ContentType 'application/json' -Body '{}' | Out-Null}catch{Write-Host 'Could not pause automatically.'}; Start-Process 'http://127.0.0.1:8080/observer'"
if errorlevel 1 pause
endlocal

@echo off
setlocal
cd /d "%~dp0"
if not exist Genesis-Server.exe (
 echo Extract the complete archive first. Genesis-Server.exe is missing.
 pause
 exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest 'http://127.0.0.1:8080/api/health' -UseBasicParsing -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 (
 echo Port 8080 is already in use. Close the previous server console first.
 pause
 exit /b 1
)
set "BIND_ADDR=127.0.0.1:8080"
set "DATA_DIR=%~dp0priv\galaxy\data"
set "DATABASE_PATH=%~dp0living-galaxy-02.db"
set "LIVING_SECTOR_UI_DIR=%~dp0observer"
set "WORLD_SPEED=16"
set "LIVING_SECTOR_STRATEGY_MODE=execute"
set "LIVING_SECTOR_GALAXY=1"
echo Living Sector - Living Galaxy 0.2
echo Three autonomous factions. Speed x16. No installation required.
echo The saved galaxy resumes automatically. Ctrl+C in server console saves and exits.
start "Living Sector Galaxy" /D "%~dp0" "%~dp0Genesis-Server.exe"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ready=$false; for($i=0;$i -lt 60;$i++){try{$r=Invoke-WebRequest 'http://127.0.0.1:8080/api/health' -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -eq 200){$ready=$true;break}}catch{}; Start-Sleep -Seconds 1}; if($ready){Start-Process 'http://127.0.0.1:8080/observer'}else{Write-Host 'Server did not start. Read the server console.';exit 1}"
if errorlevel 1 pause
endlocal

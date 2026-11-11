@echo off
setlocal EnableExtensions
cd /d "%~dp0"
REM Real Genesis gameplay with the experimental hybrid on a SEPARATE database.
REM Existing Galaxy saves, data files and source worlds are never overwritten.
set "PORT=18081"
set "DATABASE_PATH=%~dp0ai-hybrid-gameplay.db"
set "DATA_DIR=%~dp0priv\galaxy\data"
set "LABEL=Hybrid in the native Galaxy"
if /I "%~1"=="water" (
  set "PORT=18082"
  set "DATABASE_PATH=%~dp0ai-hybrid-water-gameplay.db"
  set "DATA_DIR=%~dp0ai-water-fixture"
  set "LABEL=Hybrid water chain in the native Galaxy"
  if not exist "ai-water-fixture\worlds\sol.json" (
    if exist "ai-water-fixture" (
      echo Partial fixture exists. Refusing to change it: ai-water-fixture
      pause
      exit /b 1
    )
    where py >nul 2>nul
    if not errorlevel 1 (
      py -3 scripts\make_ai_water_chain_fixture.py --output "ai-water-fixture"
    ) else (
      where python >nul 2>nul
      if errorlevel 1 (
        echo Python is required once to prepare the isolated water scenario.
        pause
        exit /b 1
      )
      python scripts\make_ai_water_chain_fixture.py --output "ai-water-fixture"
    )
    if errorlevel 1 (
      echo Initial fixture failed. The native source scenario was not modified.
      pause
      exit /b 1
    )
  )
)
where cargo >nul 2>nul
if errorlevel 1 (
  echo Rust/Cargo is required for a fresh hybrid build.
  pause
  exit /b 1
)
echo Compiling CURRENT sources. First run may take several minutes.
cargo build -p sim_server --bin genesis_server
if errorlevel 1 (
  echo BUILD FAILED. Do not interpret old binaries as the current AI.
  pause
  exit /b 1
)
powershell -NoProfile -Command "$t=New-Object System.Net.Sockets.TcpClient;try{$t.Connect('127.0.0.1',%PORT%);exit 1}catch{exit 0}finally{$t.Dispose()}"
if errorlevel 1 (
  echo Port %PORT% is occupied. Close the earlier test server before launching.
  pause
  exit /b 1
)
set "BIND_ADDR=127.0.0.1:%PORT%"
set "LIVING_SECTOR_UI_DIR=%~dp0observer"
set "LIVING_SECTOR_GALAXY=1"
set "LIVING_SECTOR_STRATEGY_MODE=execute"
set "LIVING_SECTOR_PLANNER=hybrid"
set "LIVING_SECTOR_PLANNER_SHADOW=0"
set "LIVING_SECTOR_PLANNER_COMPARE=0"
set "WORLD_SPEED=16"
echo.
echo %LABEL%
echo Data: %DATA_DIR%
echo Save: %DATABASE_PATH%
echo Hybrid is opt-in and does NOT replace your original save.
echo The SERVER CONSOLE must remain open while playing.
start "Living Sector Hybrid Gameplay" /D "%~dp0" "%~dp0target\debug\genesis_server.exe"
powershell -NoProfile -Command "$ready=$false;for($i=0;$i -lt 60;$i++){try{$r=Invoke-WebRequest 'http://127.0.0.1:%PORT%/api/health' -UseBasicParsing -TimeoutSec 2;if($r.StatusCode -eq 200){$ready=$true;break}}catch{};Start-Sleep -Seconds 1};if($ready){Start-Process 'http://127.0.0.1:%PORT%/observer';Write-Host 'Open the Inspector on the Galaxy page to view native AI receipts.'}else{Write-Host 'New server did not become ready. Check its console.';exit 1}"
if errorlevel 1 pause
endlocal

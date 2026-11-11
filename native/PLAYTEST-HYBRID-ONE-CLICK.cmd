@echo off
setlocal EnableExtensions
cd /d "%~dp0"
REM The one controlled PLAYTEST. One fresh native server and one isolated save.
REM Does not touch your main Galaxy data or existing saved games.
set "RUN=ai-gameplay-run-%RANDOM%-%RANDOM%"
mkdir "%RUN%" || exit /b 1
set "OUT=AI-HYBRID-PLAYTEST-RESULTS.zip"
where cargo >nul 2>nul
if errorlevel 1 (
  echo FAILED: Rust/Cargo not installed > "%RUN%\RESULT.txt"
  goto package
)
where py >nul 2>nul
if not errorlevel 1 (
  set "PY=py -3"
  goto python_ready
)
where python >nul 2>nul
if errorlevel 1 (
  echo FAILED: Python not installed > "%RUN%\RESULT.txt"
  goto package
)
set "PY=python"
:python_ready
echo.
echo [1/4] Checking the current hybrid planning code ...
cargo test -p sim_core strategy::planning > "%RUN%\planning.log" 2>&1
if errorlevel 1 (
  echo FAILED: Rust planning tests. See planning.log. > "%RUN%\RESULT.txt"
  goto package
)
echo [2/4] Building the CURRENT Genesis server ...
cargo build -p sim_server --bin genesis_server > "%RUN%\build.log" 2>&1
if errorlevel 1 (
  echo FAILED: current Rust source did not build. See build.log. > "%RUN%\RESULT.txt"
  goto package
)
echo [3/4] Preparing native water-chain initial scenario ...
%PY% scripts\make_ai_water_chain_fixture.py --output "%RUN%\fixture" > "%RUN%\fixture.log" 2>&1
if errorlevel 1 (
  echo FAILED: cannot prepare an independent native scenario. > "%RUN%\RESULT.txt"
  goto package
)
echo [4/4] Running hybrid Genesis and opening Observer for TWO minutes ...
echo Look at Terran faction ^> hybrid AI. Browser/game server will close automatically.
%PY% scripts\ai_runtime_audit.py --root . --binary target\debug\genesis_server.exe --data-dir "%RUN%\fixture" --modes hybrid --seconds 120 --interval 0.75 --output "%RUN%\runs" --open-observer > "%RUN%\runtime.log" 2>&1
if errorlevel 1 (
  echo FAILED or INCONCLUSIVE: server execution had an error. See runtime.log. > "%RUN%\RESULT.txt"
  goto package
)
%PY% scripts\ai_playtest_verdict.py --summary "%RUN%\runs\summary.json" --output "%RUN%\VERDICT.txt" >> "%RUN%\runtime.log" 2>&1
if errorlevel 1 (
  echo FAILED: evidence report missing or malformed. > "%RUN%\RESULT.txt"
  goto package
)
echo COMPILED and RAN. Read VERDICT.txt: PROVEN, PARTIAL or INCONCLUSIVE. > "%RUN%\RESULT.txt"
:package
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\package-ai-audit.ps1" -ResultDir "%RUN%" -ZipFile "%OUT%"
echo.
if exist "%RUN%\RESULT.txt" type "%RUN%\RESULT.txt"
if exist "%RUN%\VERDICT.txt" type "%RUN%\VERDICT.txt"
echo.
echo Send %OUT% to ChatGPT. Large SQLite game saves are deliberately excluded.
pause
endlocal

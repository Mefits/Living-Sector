@echo off
setlocal EnableExtensions
cd /d "%~dp0"
REM ONE combined checkpoint for B+C+D+E+F+G. Avoids user savegames.
REM Goal: prove actual paid delivery AND native recipe output, not just a green API.
set "LOGDIR=ai-block-g-results-%RANDOM%"
mkdir "%LOGDIR%" || exit /b 1
where cargo >nul 2>nul
if errorlevel 1 (
  echo BLOCKED: Cargo is not installed. > "%LOGDIR%\RESULT.txt"
  goto package
)
rustc --version > "%LOGDIR%\toolchain.txt" 2>&1
cargo --version >> "%LOGDIR%\toolchain.txt" 2>&1
call :run check "cargo check -p sim_core -p sim_server -p sim_db"
if errorlevel 1 goto package
call :run planning "cargo test --locked -p sim_core strategy::planning"
if errorlevel 1 goto package
call :run coordination "cargo test --locked -p sim_core strategy::coordination"
if errorlevel 1 goto package
call :run station "cargo test --locked -p sim_core strategy::station"
if errorlevel 1 goto package
call :run workforce "cargo test --locked -p sim_core agents::facility::workforce"
if errorlevel 1 goto package
call :run server_build "cargo build --locked -p sim_server --bin genesis_server"
if errorlevel 1 goto package
where py >nul 2>nul
if not errorlevel 1 (
  set "PY=py -3"
  goto python_found
)
where python >nul 2>nul
if not errorlevel 1 (
  set "PY=python"
  goto python_found
)
echo INCONCLUSIVE: Cargo succeeded but Python unavailable; native runtime proof NOT RUN. > "%LOGDIR%\RESULT.txt"
goto package
:python_found
call :run python_unit "%PY% -m unittest discover -s scripts -p test_ai_*.py"
if errorlevel 1 goto package
call :run fixture "%PY% scripts\make_ai_water_chain_fixture.py --output %LOGDIR%\native-fixture"
if errorlevel 1 goto package
call :run runtime "%PY% scripts\ai_runtime_audit.py --root . --binary target\debug\genesis_server.exe --data-dir %LOGDIR%\native-fixture --modes hybrid --seconds 60 --interval 0.6 --output %LOGDIR%\runs"
if errorlevel 1 goto package
REM Runtime health and a completed native chain are SEPARATE results.
REM Inspect runs\summary.json -> confirmed_multistep_recipe_chains. Zero = INCONCLUSIVE.
echo COMPILED: Rust, unit tests and new server run passed. Check runs\summary.json: a complete native water chain is proven ONLY if confirmed_multistep_recipe_chains is at least 1. > "%LOGDIR%\RESULT.txt"
goto package
:run
echo Running %~1 ...
%ComSpec% /d /c "%~2" > "%LOGDIR%\%~1.log" 2>&1
if errorlevel 1 (
  echo FAILED at %~1 - see %LOGDIR%\%~1.log > "%LOGDIR%\RESULT.txt"
  exit /b 1
)
echo OK %~1
exit /b 0
:package
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\package-ai-audit.ps1" -ResultDir "%LOGDIR%" -ZipFile "AI-BLOCK-G-RESULTS.zip"
echo Send AI-BLOCK-G-RESULTS.zip to ChatGPT when requested.
pause
if exist "%LOGDIR%\RESULT.txt" findstr /b "COMPILED" "%LOGDIR%\RESULT.txt" >nul
if errorlevel 1 exit /b 1
exit /b 0

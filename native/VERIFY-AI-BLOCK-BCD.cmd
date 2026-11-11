@echo off
setlocal EnableExtensions
cd /d "%~dp0"
REM Single checkpoint for B+C+D. Run ONCE after the whole combined block.
REM Never touches the user's original world.db or other saved games.
set "LOGDIR=ai-block-bcd-results"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
where cargo >nul 2>nul
if errorlevel 1 (
  echo BLOCKED: Cargo is missing. > "%LOGDIR%\RESULT.txt"
  goto package_fail
)
rustc --version > "%LOGDIR%\toolchain.txt" 2>&1
cargo --version >> "%LOGDIR%\toolchain.txt" 2>&1
call :step check "cargo check -p sim_core -p sim_server -p sim_db"
if errorlevel 1 goto package_fail
call :step planning "cargo test --locked -p sim_core strategy::planning"
if errorlevel 1 goto package_fail
call :step coordination "cargo test --locked -p sim_core strategy::coordination"
if errorlevel 1 goto package_fail
call :step station "cargo test --locked -p sim_core strategy::station"
if errorlevel 1 goto package_fail
call :step server_build "cargo build --locked -p sim_server --bin genesis_server"
if errorlevel 1 goto package_fail
call :step fixture_htn_goap_beam "cargo run --locked -q -p sim_core --example compare_ai_native -- tests\ai_block_b_fixture.json"
if errorlevel 1 goto package_fail
call :step fixture_hybrid "cargo run --locked -q -p sim_core --example compare_ai_hybrid -- tests\ai_block_b_fixture.json"
if errorlevel 1 goto package_fail
REM Python is OPTIONAL: no demand to install additional developer tools.
where py >nul 2>nul
if not errorlevel 1 (
  set "PY=py -3"
  goto have_python
)
where python >nul 2>nul
if not errorlevel 1 (
  set "PY=python"
  goto have_python
)
echo INCONCLUSIVE: Python absent. Rust checks passed, but native runtime audit was not performed. > "%LOGDIR%\runtime_audit_result.txt"
goto finish
:have_python
call :step runtime_audit_unit "%PY% -m unittest discover -s scripts -p test_ai_runtime_audit.py"
if errorlevel 1 goto package_fail
REM No world data edits. Three fresh, independent SQLite databases and random loopback ports.
call :step runtime_audit "%PY% scripts\ai_runtime_audit.py --root . --binary target\debug\genesis_server.exe --modes baseline,htn,hybrid --seconds 18 --interval 0.6 --output %LOGDIR%\runs"
if errorlevel 1 goto package_fail
:finish
echo PASSED: compiler, unit tests and server build; examine runtime JSON for actual AI outcomes. > "%LOGDIR%\RESULT.txt"
goto package_success
:step
echo Running %~1 ...
%ComSpec% /d /c "%~2" > "%LOGDIR%\%~1.log" 2>&1
if errorlevel 1 (
  echo FAILED at %~1. See %LOGDIR%\%~1.log > "%LOGDIR%\RESULT.txt"
  echo FAILED: %~1
  exit /b 1
)
echo PASS %~1
exit /b 0
:package_fail
if not exist "%LOGDIR%\RESULT.txt" echo FAIL. See the logged command. > "%LOGDIR%\RESULT.txt"
:package_success
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\package-ai-audit.ps1" -ResultDir "%LOGDIR%" -ZipFile "AI-BLOCK-BCD-RESULTS.zip"
echo Send AI-BLOCK-BCD-RESULTS.zip to ChatGPT when convenient.
pause
if exist "%LOGDIR%\RESULT.txt" findstr /b "PASSED" "%LOGDIR%\RESULT.txt" >nul
if errorlevel 1 exit /b 1
exit /b 0

@echo off
setlocal
cd /d "%~dp0"
if not exist "ai-block-a-results" mkdir "ai-block-a-results"
where cargo >nul 2>nul
if errorlevel 1 (
  echo BLOCKED: Rust/Cargo is not installed. > "ai-block-a-results\RESULT.txt"
  echo Install Rust before running this verification.
  pause
  exit /b 127
)
rustc --version > "ai-block-a-results\toolchain.txt" 2>&1
cargo --version >> "ai-block-a-results\toolchain.txt" 2>&1
REM First resolve upstream htn =0.2.1 in the local Cargo.lock.
call :step check "cargo check -p sim_core -p sim_server -p sim_db"
if errorlevel 1 goto failed
call :step planning "cargo test --locked -p sim_core strategy::planning"
if errorlevel 1 goto failed
call :step coordination "cargo test --locked -p sim_core strategy::coordination"
if errorlevel 1 goto failed
call :step station "cargo test --locked -p sim_core strategy::station"
if errorlevel 1 goto failed
call :step server_build "cargo build --locked -p sim_server --bin genesis_server"
if errorlevel 1 goto failed
echo PASSED: Block A compiled and targeted tests completed. Runtime behavior must still be tested on the NEW executable. > "ai-block-a-results\RESULT.txt"
echo PASSED. Packaging logs, code fingerprint and Cargo.lock...
powershell -NoProfile -Command "Compress-Archive -Path 'ai-block-a-results','Cargo.lock' -DestinationPath 'AI-BLOCK-A-RESULTS.zip' -Force"
if exist "AI-BLOCK-A-RESULTS.zip" echo Send AI-BLOCK-A-RESULTS.zip to ChatGPT.
pause
exit /b 0
:step
echo Running %~1 ...
%ComSpec% /d /c "%~2" > "ai-block-a-results\%~1.log" 2>&1
if errorlevel 1 (
  echo FAIL at %~1 > "ai-block-a-results\RESULT.txt"
  echo FAIL at %~1; see ai-block-a-results\%~1.log
  exit /b 1
)
echo PASS %~1
exit /b 0
:failed
echo Block A verification stopped. No successful runtime integration is claimed.
pause
exit /b 1

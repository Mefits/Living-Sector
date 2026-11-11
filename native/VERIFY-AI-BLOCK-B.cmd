@echo off
setlocal
cd /d "%~dp0"
if not exist "ai-block-b-results" mkdir "ai-block-b-results"
where cargo >nul 2>nul
if errorlevel 1 (
  echo BLOCKED: Cargo missing. > "ai-block-b-results\RESULT.txt"
  echo Rust is not installed or cargo is not in PATH.
  pause
  exit /b 127
)
rustc --version > "ai-block-b-results\toolchain.txt" 2>&1
cargo --version >> "ai-block-b-results\toolchain.txt" 2>&1
REM The initial check resolves pinned Telic 0.1.0 into Cargo.lock.
call :step check "cargo check -p sim_core -p sim_server -p sim_db"
if errorlevel 1 goto failed
call :step planning "cargo test --locked -p sim_core strategy::planning"
if errorlevel 1 goto failed
call :step coordination "cargo test --locked -p sim_core strategy::coordination"
if errorlevel 1 goto failed
call :step server_build "cargo build --locked -p sim_server --bin genesis_server"
if errorlevel 1 goto failed
call :step native_compare "cargo run --locked -q -p sim_core --example compare_ai_native -- tests\ai_block_b_fixture.json"
if errorlevel 1 goto failed
REM A successful comparison run is a pure fixture test, NOT a native galaxy execution test.
echo PASSED: Block B compiles, selected tests and pure same-snapshot comparison pass. Live runtime remains UNTESTED. > "ai-block-b-results\RESULT.txt"
powershell -NoProfile -Command "Compress-Archive -Path 'ai-block-b-results','Cargo.lock' -DestinationPath 'AI-BLOCK-B-RESULTS.zip' -Force"
if exist "AI-BLOCK-B-RESULTS.zip" echo Send AI-BLOCK-B-RESULTS.zip to ChatGPT.
pause
exit /b 0
:step
echo Running %~1 ...
%ComSpec% /d /c "%~2" > "ai-block-b-results\%~1.log" 2>&1
if errorlevel 1 (
  echo FAIL at %~1 > "ai-block-b-results\RESULT.txt"
  echo FAIL at %~1; see ai-block-b-results\%~1.log
  exit /b 1
)
echo PASS %~1
exit /b 0
:failed
echo Verification stopped. Send the existing ai-block-b-results folder.
powershell -NoProfile -Command "Compress-Archive -Path 'ai-block-b-results','Cargo.lock' -DestinationPath 'AI-BLOCK-B-RESULTS.zip' -Force"
pause
exit /b 1

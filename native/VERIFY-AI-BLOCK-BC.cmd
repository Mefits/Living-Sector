@echo off
setlocal
cd /d "%~dp0"
if not exist "ai-block-bc-results" mkdir "ai-block-bc-results"
where cargo >nul 2>nul
if errorlevel 1 (
  echo BLOCKED: Rust/Cargo missing. > "ai-block-bc-results\RESULT.txt"
  pause
  exit /b 127
)
rustc --version > "ai-block-bc-results\toolchain.txt" 2>&1
cargo --version >> "ai-block-bc-results\toolchain.txt" 2>&1
REM First check updates Cargo.lock with pinned Telic 0.1.0 (Block B was not checked).
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
call :step compare_B "cargo run --locked -q -p sim_core --example compare_ai_native -- tests\ai_block_b_fixture.json"
if errorlevel 1 goto failed
call :step compare_C "cargo run --locked -q -p sim_core --example compare_ai_hybrid -- tests\ai_block_b_fixture.json"
if errorlevel 1 goto failed
call :step runtime_smoke "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-hybrid-runtime.ps1"
if errorlevel 1 goto failed
echo PASSED: Blocks B+C compiled, selected tests, fixture comparisons and new server API smoke passed. Native paid delivery still NOT proved. > "ai-block-bc-results\RESULT.txt"
powershell -NoProfile -Command "Compress-Archive -Path 'ai-block-bc-results','Cargo.lock' -DestinationPath 'AI-BLOCK-BC-RESULTS.zip' -Force"
echo Ready. Send AI-BLOCK-BC-RESULTS.zip to ChatGPT.
pause
exit /b 0
:step
echo Running %~1 ...
%ComSpec% /d /c "%~2" > "ai-block-bc-results\%~1.log" 2>&1
if errorlevel 1 (
  echo FAIL at %~1 > "ai-block-bc-results\RESULT.txt"
  echo FAIL at %~1. Send logs.
  exit /b 1
)
echo PASS %~1
exit /b 0
:failed
powershell -NoProfile -Command "Compress-Archive -Path 'ai-block-bc-results','Cargo.lock' -DestinationPath 'AI-BLOCK-BC-RESULTS.zip' -Force"
echo One block failed: send AI-BLOCK-BC-RESULTS.zip, no need to rerun repeatedly.
pause
exit /b 1

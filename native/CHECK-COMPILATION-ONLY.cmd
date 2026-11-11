@echo off
setlocal
cd /d "%~dp0"
echo Checking Rust compilation only; no runtime scenarios or long tests.
cargo check -p sim_core -p sim_server -p sim_db
if errorlevel 1 (
  echo.
  echo FAILED: send the last error lines to ChatGPT.
  pause
  exit /b 1
)
echo.
echo PASSED: Compilation check. Full runtime behavior is still unverified.
pause

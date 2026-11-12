@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo LIVING SECTOR GODOT - local P0 + P1 checks; no Rust, no paid CI
set "GODOT_BIN="
if defined GODOT_EXE if exist "%GODOT_EXE%" set "GODOT_BIN=%GODOT_EXE%"
if not defined GODOT_BIN if exist "%~dp0Godot.exe" set "GODOT_BIN=%~dp0Godot.exe"
if not defined GODOT_BIN (
  for %%N in (godot.exe godot4.exe) do (
    if not defined GODOT_BIN for %%Q in (%%~$PATH:N) do if not "%%~Q"=="" set "GODOT_BIN=%%~Q"
  )
)
if not defined GODOT_BIN (
  echo ERROR: Godot 4 Standard not found. Place Godot.exe here or set GODOT_EXE.
  pause
  exit /b 2
)
if not exist "%~dp0logs" mkdir "%~dp0logs"
echo.
echo [1/3] Checking exact frozen seed, 8 systems / 3 factions...
"%GODOT_BIN%" --headless --path "%~dp0" --script res://tests/p0_seed_check.gd --log-file "%~dp0logs\p0-seed-smoke.log"
if errorlevel 1 goto failed
echo.
echo [2/3] Checking native time/orbit formulas and safe P1 save-load...
"%GODOT_BIN%" --headless --path "%~dp0" --script res://tests/p1_tick_save_check.gd --log-file "%~dp0logs\p1-tick-save-smoke.log"
if errorlevel 1 goto failed
echo.
echo [3/3] Checking P1 seed boundaries, copy isolation and control validation...
"%GODOT_BIN%" --headless --path "%~dp0" --script res://tests/p1_audit_check.gd --log-file "%~dp0logs\\p1-audit-smoke.log"
if errorlevel 1 goto failed
echo.
echo P0_SEED_PASS + P1_PARITY_PASS + P1_AUDIT_PASS: local checks succeeded.
echo Try UPDATE_AND_PLAY.cmd to view real orbit angles.
pause
exit /b 0
:failed
echo.
echo LOCAL GODOT SMOKE FAILED. Run SAVE_DIAGNOSTICS.cmd and attach the ZIP.
echo Logs: %~dp0logs
pause
exit /b 1

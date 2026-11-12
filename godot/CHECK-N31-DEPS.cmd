@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "GODOT_BIN="
if defined GODOT_EXE if exist "%GODOT_EXE%" set "GODOT_BIN=%GODOT_EXE%"
if not defined GODOT_BIN if exist "%CD%\Godot.exe" set "GODOT_BIN=%CD%\Godot.exe"
if not defined GODOT_BIN (
  echo ERROR: Place Godot.exe next to project.godot, or set GODOT_EXE.
  pause
  exit /b 2
)
set "LOGDIR=%CD%\logs\integration"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set /a FAILED=0
echo Checking N31 dependencies using "%GODOT_BIN%"
call :check scripts/sim/ship_catalog.gd ship_catalog
call :check scripts/sim/ship_state.gd ship_state
call :check scripts/sim/economy/credit_ledger.gd credit_ledger
call :check scripts/sim/economy/contract_board.gd contract_board
call :check scripts/sim/economy/contract_command_runner.gd contract_command_runner
echo.
echo Dependency check failures: %FAILED%
echo Logs: "%LOGDIR%\n31-dep-*-console.txt"
pause
exit /b %FAILED%

:check
set "REL=%~1"
set "NAME=%~2"
set "OUT=%LOGDIR%\n31-dep-%NAME%-console.txt"
echo.
echo Checking %REL%
if not exist "%CD%\%REL:/=\%" (
  echo MISSING: %REL%
  > "%OUT%" echo MISSING: %REL%
  set /a FAILED+=1
  exit /b 0
)
"%GODOT_BIN%" --headless --path "%CD%" --check-only --script "res://%REL%" > "%OUT%" 2>&1
set "HAS_ERROR=0"
if errorlevel 1 set "HAS_ERROR=1"
findstr /I /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"Failed to load script" "%OUT%" >nul 2>&1
if not errorlevel 1 set "HAS_ERROR=1"
if "%HAS_ERROR%"=="1" (
  echo FAIL: %REL%
  type "%OUT%"
  set /a FAILED+=1
) else (
  echo PASS: %REL%
)
exit /b 0

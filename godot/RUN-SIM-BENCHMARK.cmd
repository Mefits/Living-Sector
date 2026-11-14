@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "GODOT=%GODOT_EXE%"
if not defined GODOT (
  where godot.exe >nul 2>nul && set "GODOT=godot.exe"
)
if not defined GODOT (
  where godot4.exe >nul 2>nul && set "GODOT=godot4.exe"
)
if not defined GODOT (
  echo [SIM_BENCH] Godot executable not found.
  echo Specify the path to your portable Godot console executable:
  echo   set "GODOT_EXE=C:\Tools\Godot_v4.x_win64_console.exe"
  exit /b 2
)
if "%~1"=="" (
  "%GODOT%" --headless --path "%CD%" --script res://experiments/simulation_architecture/benchmark.gd -- --plants=100 --ships=20 --years=1 --seed=42
) else (
  "%GODOT%" --headless --path "%CD%" --script res://experiments/simulation_architecture/benchmark.gd -- %*
)
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
  echo [SIM_BENCH] FAIL. See errors above.
  exit /b %CODE%
)
echo [SIM_BENCH] PASS. Open experiments\simulation_architecture\results\latest.json
exit /b 0

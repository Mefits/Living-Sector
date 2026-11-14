@echo off
setlocal EnableExtensions
rem Living Sector experimental headless benchmark.
rem Always pause and keep a log: Explorer otherwise closes a failed .cmd instantly.
cd /d "%~dp0"
set "BASE=%CD%"
set "RESULT_DIR=%BASE%\experiments\simulation_architecture\results"
set "LOG=%RESULT_DIR%\last-run.log"
set "CODE=1"
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%" >nul 2>&1
if not exist "%RESULT_DIR%" (
  echo [SIM_BENCH] Cannot create results directory:
  echo   %RESULT_DIR%
  goto :finish
)

> "%LOG%" echo Living Sector Simulation Architecture Benchmark
>>"%LOG%" echo Working directory: %BASE%
>>"%LOG%" echo Expected branch: experiment/simulation-architecture-20261114
>>"%LOG%" echo.

echo.
echo =============================================================
echo   LIVING SECTOR - SIMULATION ARCHITECTURE BENCHMARK
echo =============================================================
echo.
echo Working folder: %BASE%
echo Log file: %LOG%
echo.

if not exist "%BASE%\experiments\simulation_architecture\benchmark.gd" (
  echo [SIM_BENCH] The experiment script is missing.
  >>"%LOG%" echo [SIM_BENCH] The experiment script is missing.
  echo Check out branch: experiment/simulation-architecture-20261114
  goto :show_log
)

rem First prefer explicit GODOT_EXE. If absent, try PATH and common
rem portable Godot locations (the console executable is preferred).
set "GODOT=%GODOT_EXE%"
if defined GODOT (
  if not exist "%GODOT%" (
    echo [SIM_BENCH] GODOT_EXE points to a missing file:
    echo   %GODOT%
    >>"%LOG%" echo [SIM_BENCH] GODOT_EXE does not exist: %GODOT%
    set "GODOT="
  )
)
if not defined GODOT (
  for %%E in (godot.exe godot4.exe godot_console.exe godot4_console.exe) do (
    if not defined GODOT (
      where %%E >nul 2>&1
      if not errorlevel 1 set "GODOT=%%E"
    )
  )
)
if not defined GODOT (
  for %%F in (
    "%BASE%\Godot*console*.exe"
    "%BASE%\..\Godot*console*.exe"
    "%USERPROFILE%\Downloads\Godot*console*.exe"
    "%USERPROFILE%\Desktop\Godot*console*.exe"
    "%BASE%\Godot*.exe"
    "%BASE%\..\Godot*.exe"
    "%USERPROFILE%\Downloads\Godot*.exe"
    "%USERPROFILE%\Desktop\Godot*.exe"
  ) do (
    if not defined GODOT (
      if exist "%%~fF" set "GODOT=%%~fF"
    )
  )
)
if not defined GODOT (
  echo [SIM_BENCH] Godot was not found automatically.
  echo The portable Godot exe may be inside an extracted folder.
  echo.
  set /p "GODOT=Paste full path to Godot .exe, or press Enter to cancel: "
)
rem Accept Windows "Copy as path" input with surrounding quotes.
if defined GODOT set "GODOT=%GODOT:"=%"
if defined GODOT if not exist "%GODOT%" (
  echo [SIM_BENCH] The selected Godot executable was not found:
  echo   %GODOT%
  >>"%LOG%" echo [SIM_BENCH] Invalid selected Godot executable: %GODOT%
  set "GODOT="
)
if not defined GODOT (
  echo [SIM_BENCH] No executable selected.
  >>"%LOG%" echo [SIM_BENCH] Godot executable not found.
  goto :show_log
)

echo Using Godot: %GODOT%
>>"%LOG%" echo Godot command: %GODOT%
echo.
echo Running three scheduler variants; results will be compared.
echo.

if "%~1"=="" (
  "%GODOT%" --headless --path "%BASE%" --script res://experiments/simulation_architecture/benchmark.gd -- --plants=100 --ships=20 --years=1 --seed=42 >>"%LOG%" 2>&1
) else (
  "%GODOT%" --headless --path "%BASE%" --script res://experiments/simulation_architecture/benchmark.gd -- %* >>"%LOG%" 2>&1
)
set "CODE=%ERRORLEVEL%"

:show_log
echo.
echo -------------------- OUTPUT --------------------
type "%LOG%"
echo ------------------------------------------------
echo.
if "%CODE%"=="0" (
  echo [SIM_BENCH] PASS. Open:
  echo   experiments\simulation_architecture\results\latest.json
) else (
  echo [SIM_BENCH] FAILED or could not start. Exit code: %CODE%
  echo Copy the contents of last-run.log if you want me to diagnose it.
)
:finish
echo.
echo Press any key to close this window.
pause >nul
exit /b %CODE%

@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "BASE=%CD%"
set "RESULT_DIR=%BASE%\experiments\simulation_architecture\results"
set "CODE=2"

echo.
echo ===============================================================
echo   LIVING SECTOR - REAL N73 / N9 SCHEDULER STRESS TEST
echo ===============================================================
echo.
echo BRANCH: experiment/simulation-architecture-20261114
echo OUTPUT: %RESULT_DIR%\stress.json
echo         %RESULT_DIR%\stress.csv
echo         %RESULT_DIR%\stress.log
echo.

if not exist "%BASE%\experiments\simulation_architecture\stress.gd" (
  echo [ERROR] stress.gd is missing. Switch to experiment branch and Pull origin.
  goto :finish
)
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%" >nul 2>&1

set "GODOT=%GODOT_EXE%"
if not defined GODOT if exist "%BASE%\Godot.exe" set "GODOT=%BASE%\Godot.exe"
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
    if not defined GODOT if exist "%%~fF" set "GODOT=%%~fF"
  )
)
if not defined GODOT (
  echo Godot executable not found. Paste full path to your Godot executable.
  set /p "GODOT=Godot exe path: "
)
if defined GODOT set "GODOT=%GODOT:"=%"
if not defined GODOT (
  echo [ERROR] No Godot executable selected.
  goto :finish
)
if not exist "%GODOT%" (
  where "%GODOT%" >nul 2>&1
  if errorlevel 1 (
    echo [ERROR] Godot executable not found: %GODOT%
    goto :finish
  )
)

echo Godot: %GODOT%
echo.
echo Measures ALL three algorithms using identical physical stock and cargo.
echo If any semantic state differs the run STOPS with FAIL.
echo Progress is printed below and stored in stress.log.
echo For optional profiles run this .cmd from CMD with:
echo   RUN-SIM-STRESS.cmd --profile=quick --seeds=1 --repeats=1
echo   RUN-SIM-STRESS.cmd --profile=extreme --seeds=2 --repeats=3
echo.
if "%~1"=="" (
  "%GODOT%" --headless --path "%BASE%" --script res://experiments/simulation_architecture/stress.gd -- --profile=stress --seeds=2 --repeats=3
) else (
  "%GODOT%" --headless --path "%BASE%" --script res://experiments/simulation_architecture/stress.gd -- %*
)
set "CODE=%ERRORLEVEL%"
echo.
if "%CODE%"=="0" (
  echo [SIM_STRESS] PASS.
  echo Report: %RESULT_DIR%\stress.json
  echo Summary: %RESULT_DIR%\stress.csv
) else (
  echo [SIM_STRESS] FAIL / interrupted / script error. Exit code: %CODE%
  echo Send stress.log and stress.json from:
  echo %RESULT_DIR%
)
:finish
echo.
echo Press any key to close.
pause >nul
exit /b %CODE%

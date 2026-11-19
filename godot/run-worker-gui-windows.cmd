@echo off
setlocal
REM Living Sector E: opt-in SINGLE authoritative N158 worker.
REM This starts the real game scene, not the Godot editor or a benchmark.
REM No changes to the ordinary launch or original user save.
set "GODOT_EXE=%~1"

if not defined GODOT_EXE if exist "D:\PROGRAMS\Godot_v4.7.2-stable_win64.exe\Godot.exe" set "GODOT_EXE=D:\PROGRAMS\Godot_v4.7.2-stable_win64.exe\Godot.exe"
if not defined GODOT_EXE if exist "D:\PROGRAMS\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=D:\PROGRAMS\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_EXE for /f "delims=" %%G in ('where godot.exe 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%G"

if not defined GODOT_EXE goto missing
if not exist "%GODOT_EXE%" goto missing

REM Windows argument parsing treats a trailing backslash before a quote as an
REM escaped quote; trim the final slash of %%~dp0 to avoid swallowing "--".
set "GODOT_PROJECT=%~dp0"
set "GODOT_PROJECT=%GODOT_PROJECT:~0,-1%"
set "LS_N158_WORKER_GUI=1"
echo.
echo Living Sector - EXPERIMENTAL N158 WORKER GUI
echo Godot: "%GODOT_EXE%"
echo Project: "%GODOT_PROJECT%"
echo Worker save slot: galaxy-067-p2-worker-experimental.json
echo Normal save slot remains untouched.
echo.
"%GODOT_EXE%" --path "%GODOT_PROJECT%" -- --p2-worker-gui
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Godot finished with error code %EXITCODE%.
pause
exit /b %EXITCODE%

:missing
echo Godot 4.7.2 executable not found automatically.
echo Drag Godot.exe onto this .cmd file, or run:
echo   run-worker-gui-windows.cmd "D:\path\to\Godot.exe"
pause
exit /b 1

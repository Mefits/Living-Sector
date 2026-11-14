@echo off
setlocal
rem Usage: run-autonomy.cmd "C:\Path\Godot_v4.7.2-stable_win64.exe" [ticks]
rem No player orders, no artificial goods, no modified starting seed.
set "GODOT_BIN=%~1"
if "%GODOT_BIN%"=="" set "GODOT_BIN=godot"
set "LS_AUTONOMY_TICKS=%~2"
if "%LS_AUTONOMY_TICKS%"=="" set "LS_AUTONOMY_TICKS=420"
set "PROJECT=%~dp0..\.."
set "LS_AUTONOMY_REPORT=%PROJECT%\logs\autonomy\report.json"
"%GODOT_BIN%" --headless --path "%PROJECT%" --script res://tests/p2_autonomous_world_observer_check.gd
set "RESULT=%errorlevel%"
echo Report: %LS_AUTONOMY_REPORT%
exit /b %RESULT%

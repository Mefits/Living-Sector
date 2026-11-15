@echo off
setlocal
rem Usage: run-gut.cmd "C:\Path\to\Godot_v4.7.2-stable_win64.exe"
rem If argument omitted, godot must be in PATH.
set "GODOT_BIN=%~1"
if "%GODOT_BIN%"=="" set "GODOT_BIN=godot"
set "PROJECT=%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-gut.ps1" -ProjectDir "%PROJECT%"
if errorlevel 1 exit /b 1
"%GODOT_BIN%" --headless --path "%PROJECT%" --editor --import --quit
if errorlevel 1 exit /b 1
"%GODOT_BIN%" --headless --path "%PROJECT%" --script res://addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gexit
exit /b %errorlevel%

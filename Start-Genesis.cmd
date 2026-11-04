@echo off
setlocal
cd /d "%~dp0"
"%~dp0Genesis-Clean.exe"
if errorlevel 1 pause

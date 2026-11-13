@echo off
setlocal
cd /d "%~dp0"
set "ENGINE=%GODOT_EXE%"
if not defined ENGINE (
    set "ENGINE=godot"
    where godot >nul 2>nul
    if errorlevel 1 set "ENGINE=godot4"
    where godot4 >nul 2>nul
    if errorlevel 1 (
        echo Godot 4 not found in PATH.
        echo Set GODOT_EXE to the full path to your Godot Console executable.
        echo Example: set "GODOT_EXE=C:\Tools\Godot_v4.x-stable_win64_console.exe"
        pause
        exit /b 2
    )
)
echo Living Sector P2 / N158 -- real paid production acceptance
"%ENGINE%" --headless --path "%~dp0" --script res://tests/p2_n158_live_production_check.gd
set "CODE=%ERRORLEVEL%"
if %CODE% NEQ 0 (
    echo P2 N158 acceptance FAILED, exit code %CODE%.
) else (
    echo P2 N158 acceptance PASSED.
)
pause
exit /b %CODE%

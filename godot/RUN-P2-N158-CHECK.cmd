@echo off
setlocal
cd /d "%~dp0"
set "ENGINE=%GODOT_EXE%"
if not defined ENGINE (
    where godot >nul 2>nul
    if errorlevel 1 (
        where godot4 >nul 2>nul
        if errorlevel 1 (
            echo Godot 4 not found in PATH.
            echo Set GODOT_EXE to the full path to your Godot Console executable.
            pause
            exit /b 2
        )
        set "ENGINE=godot4"
    ) else (
        set "ENGINE=godot"
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

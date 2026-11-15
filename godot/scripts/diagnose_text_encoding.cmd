@echo off
setlocal
title Living Sector - Godot text encoding diagnostic
echo Reading Godot source files; no source files will be changed.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose_text_encoding.ps1"
echo.
echo Press any key to close. The report is also in your TEMP folder.
pause >nul
endlocal

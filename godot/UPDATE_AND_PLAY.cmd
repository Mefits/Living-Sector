@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "PORT_BRANCH=feature/godot-p0-world-inspector-and-audit"
echo.
echo LIVING SECTOR - GODOT P0 (no Rust compilation / no paid CI)
echo.
for %%P in ("%~dp0..") do set "REPO_ROOT=%%~fP"
if exist "%REPO_ROOT%\.git" (
  where git.exe >nul 2>nul
  if errorlevel 1 goto git_missing
  for /f "delims=" %%B in ('git -C "%REPO_ROOT%" branch --show-current 2^>nul') do set "CURRENT_BRANCH=%%B"
  if /I not "%CURRENT_BRANCH%"=="%PORT_BRANCH%" (
    echo Current Git branch: %CURRENT_BRANCH%.
    echo Not switching branches automatically. Current files will be launched.
    echo To get this port's updates, check out %PORT_BRANCH% manually.
    goto launch
  )
  for /f "delims=" %%L in ('git -C "%REPO_ROOT%" status --porcelain 2^>nul') do set "DIRTY=1"
  if defined DIRTY (
    echo Local uncommitted files found. Skipping update to protect your work.
    goto launch
  )
  echo Checking for fast-forward Git updates...
  git -C "%REPO_ROOT%" pull --ff-only origin "%PORT_BRANCH%"
  if errorlevel 1 (
    echo Git update failed. Your existing files were NOT replaced.
    echo Launching the current local version.
  )
  goto launch
)
:git_missing
echo Git was not found. Launching the existing checkout.
:launch
set "GODOT_BIN="
if defined GODOT_EXE if exist "%GODOT_EXE%" set "GODOT_BIN=%GODOT_EXE%"
if not defined GODOT_BIN if exist "%~dp0Godot.exe" set "GODOT_BIN=%~dp0Godot.exe"
if not defined GODOT_BIN if exist "%~dp0..\Godot.exe" set "GODOT_BIN=%~dp0..\Godot.exe"
if not defined GODOT_BIN (
  for %%N in (godot.exe godot4.exe) do (
    if not defined GODOT_BIN for %%Q in (%%~$PATH:N) do if not "%%~Q"=="" set "GODOT_BIN=%%~Q"
  )
)
if not defined GODOT_BIN (
  echo ERROR: Godot 4 is not found.
  echo Download the STANDARD (not .NET) Godot 4 executable from https://godotengine.org/download/windows/
  echo Place it as Godot.exe next to this CMD or set the GODOT_EXE environment variable.
  echo The source project itself does not need Rust.
  pause
  exit /b 2
)
if not exist "%~dp0logs" mkdir "%~dp0logs"
echo Launching %GODOT_BIN%
echo Log: %~dp0logs\godot-p0.log
"%GODOT_BIN%" --path "%~dp0" --log-file "%~dp0logs\godot-p0.log"
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" echo Godot ended with code %CODE%. Run SAVE_DIAGNOSTICS.cmd.
echo.
pause
exit /b %CODE%

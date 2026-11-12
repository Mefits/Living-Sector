@echo off
setlocal EnableExtensions
set "PROJECT=%~dp0godot"
if not exist "%PROJECT%\project.godot" (
  echo ERROR: This launcher must be in the full Living-Sector repository root, next to the godot folder.
  pause
  exit /b 2
)
pushd "%PROJECT%"
if errorlevel 1 (
  echo ERROR: Cannot open the Godot project directory.
  pause
  exit /b 2
)
set "PROJECT=%CD%"
set "GODOT_BIN="
if defined GODOT_EXE if exist "%GODOT_EXE%" set "GODOT_BIN=%GODOT_EXE%"
if not defined GODOT_BIN if exist "%PROJECT%\Godot.exe" set "GODOT_BIN=%PROJECT%\Godot.exe"
if not defined GODOT_BIN if exist "%~dp0Godot.exe" set "GODOT_BIN=%~dp0Godot.exe"
if not defined GODOT_BIN (
  for %%N in (godot.exe godot4.exe) do (
    if not defined GODOT_BIN for %%P in (%%~$PATH:N) do if not "%%~P"=="" set "GODOT_BIN=%%~P"
  )
)
if not defined GODOT_BIN (
  echo.
  echo Godot was not found.
  echo Copy your EXISTING Godot 4.7.2 Standard executable to:
  echo   %PROJECT%\Godot.exe
  echo No other files need to be copied.
  echo.
  pause
  popd
  exit /b 2
)
set "LOGDIR=%PROJECT%\logs\startup"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo Living Sector Godot 4.7 preview
echo Game folder: %PROJECT%
"%GODOT_BIN%" --version > "%LOGDIR%\godot-version.txt" 2>&1
type "%LOGDIR%\godot-version.txt"
echo.
echo Importing project once, then launching the game...
"%GODOT_BIN%" --headless --editor --path "%PROJECT%" --quit --log-file "%LOGDIR%\import.log" > "%LOGDIR%\import-console.txt" 2>&1
set "IMPORT_FAILED=0"
if errorlevel 1 set "IMPORT_FAILED=1"
findstr /I /C:"SCRIPT ERROR:" /C:"Parse Error:" /C:"Failed to load script" "%LOGDIR%\import-console.txt" >nul 2>&1
if not errorlevel 1 set "IMPORT_FAILED=1"
if "%IMPORT_FAILED%"=="1" (
  echo.
  echo ERROR: The Godot project could not be imported successfully.
  echo Please do not run individual tests or apply more patches.
  echo Send the single file shown below:
  echo   %LOGDIR%\import-console.txt
  echo.
  type "%LOGDIR%\import-console.txt"
  pause
  popd
  exit /b 1
)
echo Import OK. Starting Living Sector...
"%GODOT_BIN%" --path "%PROJECT%" --log-file "%LOGDIR%\game.log" > "%LOGDIR%\game-console.txt" 2>&1
set "GAME_EXIT=%ERRORLEVEL%"
if not "%GAME_EXIT%"=="0" (
  echo.
  echo Godot exited with an error. Send startup logs from:
  echo   %LOGDIR%
  echo.
  type "%LOGDIR%\game-console.txt"
  pause
)
popd
exit /b %GAME_EXIT%

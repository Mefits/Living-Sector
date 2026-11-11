@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo.
echo Living Sector 0.6.7 - LOCAL, FREE Windows build and one live game check
echo Source: integration/galaxy-067-unified-playtest (PR 83)
echo No GitHub Actions or paid cloud CI.
echo.
if not exist "Cargo.toml" (
  echo ERROR: This launcher requires the COMPLETE native source folder.
  echo Download the source ZIP from PR 83, extract it, and retry.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\playtest-galaxy-067-local.ps1"
set "CODE=%ERRORLEVEL%"
echo.
if "%CODE%"=="0" (
  echo LOCAL PLAYTEST PASSED. See local-playtest-results for the playable ZIP.
) else (
  echo LOCAL PLAYTEST FAILED OR INCONCLUSIVE.
  echo Send the newest small result ZIP from local-playtest-results to ChatGPT.
)
pause
exit /b %CODE%

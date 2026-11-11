@echo off
setlocal
cd /d "%~dp0"
set "BIND_ADDR=127.0.0.1:8080"

if not exist "%~dp0Living-Sector.exe" (
  echo Living-Sector.exe not found next to this launcher.
  echo Extract the entire GitHub Actions ZIP first.
  pause
  exit /b 1
)

echo Starting the existing Rust simulation (headless)...
echo Its separate console window can be closed with Ctrl+C.
start "Living Sector - Simulator" /D "%~dp0" "%~dp0Living-Sector.exe" --headless

echo Checking http://127.0.0.1:8080/api/health ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false; for($i=0;$i -lt 90;$i++){try{$r=Invoke-WebRequest -Uri 'http://127.0.0.1:8080/api/health' -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -eq 200){$ok=$true;break}}catch{};Start-Sleep -Seconds 1};if($ok){Start-Process 'http://127.0.0.1:8080/observer'}else{Write-Host 'Engine not responding; read the simulator console for details.';exit 1}"
if errorlevel 1 pause
endlocal

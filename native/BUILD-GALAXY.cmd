@echo off
setlocal
cd /d "%~dp0"
cargo build -p sim_server --bin genesis_server --release
if errorlevel 1 exit /b 1
copy /Y target\release\genesis_server.exe Genesis-Server.exe
endlocal

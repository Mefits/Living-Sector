@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "GODOT_BIN="
if defined GODOT_EXE if exist "%GODOT_EXE%" set "GODOT_BIN=%GODOT_EXE%"
if not defined GODOT_BIN if exist "%~dp0Godot.exe" set "GODOT_BIN=%~dp0Godot.exe"
if not defined GODOT_BIN if exist "%~dp0..\Godot.exe" set "GODOT_BIN=%~dp0..\Godot.exe"
if not defined GODOT_BIN (
  for %%N in (godot.exe godot4.exe) do (
    if not defined GODOT_BIN for %%P in (%%~$PATH:N) do if not "%%~P"=="" set "GODOT_BIN=%%~P"
  )
)
if not defined GODOT_BIN (
  echo ERROR: Godot 4 Standard not found. Put Godot.exe in the godot folder or set GODOT_EXE.
  echo Official download: https://godotengine.org/download/windows/
  pause
  exit /b 2
)
set "LOGDIR=%~dp0logs\integration"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "SUMMARY=%LOGDIR%\summary.txt"
set /a TOTAL=0
set /a FAILED=0
set "MODE=QUICK"
set "TESTS=p0_seed_check.gd p1_tick_save_check.gd p1_audit_check.gd n2_calendar_check.gd n3_events_check.gd n4_registry_routes_check.gd n5_native_recipes_check.gd n6_paid_production_check.gd n8_integration_check.gd n23_production_tick_check.gd n31_contract_command_runner_check.gd"
if /I "%~1"=="all" (
  set "MODE=ALL"
  set "TESTS=n10_market_check.gd n11_ledger_check.gd n12_population_check.gd n13_ship_catalog_check.gd n14_transit_check.gd n15_cargo_check.gd n17_construction_check.gd n18_station_admin_check.gd n19_faction_head_check.gd n20_observer_check.gd n21_docking_check.gd n22_ship_batch_check.gd n23_production_tick_check.gd n24_diagnostic_check.gd n25_order_settlement_smoke.gd n26_contract_delivery_check.gd n27_contract_gate_check.gd n28_ledger_audit_check.gd n29_docked_cargo_check.gd n2_calendar_check.gd n30_contract_cargo_audit_check.gd n31_contract_command_runner_check.gd n3_events_check.gd n4_registry_routes_check.gd n5_native_recipes_check.gd n6_paid_production_check.gd n7_needs_production_check.gd n8_integration_check.gd n9_inventory_check.gd p0_seed_check.gd p1_audit_check.gd p1_tick_save_check.gd"
)
> "%SUMMARY%" echo LIVING SECTOR GODOT N32 INTEGRATION SMOKE - %MODE%
>> "%SUMMARY%" echo Source: integration/godot-foundation-smoke-20261112
>> "%SUMMARY%" echo Runtime execution is mandatory for VERIFIED. Do not count untouched components as verified.
echo.
echo LIVING SECTOR - Godot integration smoke %MODE%
echo Log folder: %LOGDIR%
echo [Project import] Parsing the unified project in headless editor...
"%GODOT_BIN%" --headless --editor --path "%~dp0" --quit --log-file "%LOGDIR%\project-import.log"
if errorlevel 1 (
  set /a FAILED+=1
  >> "%SUMMARY%" echo FAIL project import/parse
  echo FAILED project import; individual tests will still run for diagnostics.
) else (
  >> "%SUMMARY%" echo PASS project import/parse
)
for %%T in (%TESTS%) do call :run_one %%T
echo.
echo %TOTAL% tests executed, %FAILED% failures including project import.
>> "%SUMMARY%" echo TOTAL tests=%TOTAL%; failures_including_import=%FAILED%
if not "%FAILED%"=="0" (
  echo FAILED. Run SAVE_DIAGNOSTICS.cmd and send the resulting ZIP plus logs\integration\summary.txt.
  echo See: %SUMMARY%
  pause
  exit /b 1
)
echo ALL SELECTED GODOT TESTS PASSED. This is NOT full gameplay/parity verification.
echo Summary: %SUMMARY%
pause
exit /b 0
:run_one
set /a TOTAL+=1
echo [Test %TOTAL%] %~1
"%GODOT_BIN%" --headless --path "%~dp0" --script "res://tests/%~1" --log-file "%LOGDIR%\%~n1.log"
if errorlevel 1 (
  set /a FAILED+=1
  >> "%SUMMARY%" echo FAIL %~1
  echo FAIL %~1
) else (
  >> "%SUMMARY%" echo PASS %~1
)
exit /b 0

# Short, isolated Windows STARTUP smoke of the newly compiled hybrid server.
# Not a campaign-quality or native-execution-success test.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$root = (Get-Location).Path
$folder = Join-Path $root 'ai-block-bc-results'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$binary = Join-Path $root 'target\debug\genesis_server.exe'
if (-not (Test-Path $binary)) { throw 'New binary missing; cargo build must finish first' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$env:BIND_ADDR = '127.0.0.1:18082'
$env:DATA_DIR = Join-Path $root 'priv\galaxy\data'
$env:DATABASE_PATH = Join-Path $folder ("hybrid-test-$stamp.db")
$env:LIVING_SECTOR_UI_DIR = Join-Path $root 'observer'
$env:LIVING_SECTOR_GALAXY = '1'
$env:LIVING_SECTOR_STRATEGY_MODE = 'execute'
$env:LIVING_SECTOR_PLANNER = 'hybrid'
$env:LIVING_SECTOR_PLANNER_SHADOW = '1'
$env:WORLD_SPEED = '16'
$stdout = Join-Path $folder 'runtime-server-stdout.log'
$stderr = Join-Path $folder 'runtime-server-stderr.log'
$health = 'http://127.0.0.1:18082/api/health'
$strategy = 'http://127.0.0.1:18082/api/strategy'
$process = $null
try {
  $process = Start-Process -FilePath $binary -WorkingDirectory $root -PassThru -NoNewWindow `
      -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $response = $null
  for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 1
    if ($process.HasExited) { throw "New server exited before ready: $($process.ExitCode)" }
    try { $response = Invoke-WebRequest -Uri $health -UseBasicParsing -TimeoutSec 2; break }
    catch { }
  }
  if ($null -eq $response -or $response.StatusCode -ne 200) { throw 'Hybrid runtime health did not become ready' }
  $response.Content | Out-File -Encoding utf8 (Join-Path $folder 'runtime-health.json')
  $api = Invoke-WebRequest -Uri $strategy -UseBasicParsing -TimeoutSec 10
  if ($api.StatusCode -ne 200) { throw "Strategy API returned $($api.StatusCode)" }
  $api.Content | Out-File -Encoding utf8 (Join-Path $folder 'runtime-strategy.json')
  # This verifies startup and API only. A valid native paid receipt requires a
  # separate controlled scenario and cannot be inferred from HTTP status 200.
  'PASSED: newly built hybrid server starts and serves health/strategy. No claim of successful hybrid delivery.' `
      | Out-File -Encoding utf8 (Join-Path $folder 'runtime-summary.txt')
} finally {
  if ($null -ne $process) {
    try { if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction Stop } } catch { }
  }
}

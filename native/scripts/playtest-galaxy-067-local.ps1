# Galaxy 0.6.7 combined PR #83: free Windows build and ONE real game smoke.
# Built-in PowerShell only. No Python, paid GitHub Actions, or player-save reuse.
param([switch]$NoBootstrap,[switch]$SkipPackage)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
$out=Join-Path $root ('local-playtest-results\run-'+$stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null
$reportPath=Join-Path $out 'RESULT.json'
$checks=New-Object 'System.Collections.Generic.List[string]'
$summary=[ordered]@{
  status='failed';source='PR83 integration/galaxy-067-unified-playtest'
  free_local_test=$true;checks=$checks;live_world_tested=$false
  binary_built=$false;sqlite_check='not_checked'
}
$proc=$null;$base=''
$tempDb=Join-Path $env:TEMP ('ls-galaxy067-'+$stamp)

function Check([bool]$pass,[string]$message) {
  if(-not $pass){throw ('CHECK FAILED: '+$message)}
  [void]$checks.Add($message)
  Write-Host ('  PASS: '+$message) -ForegroundColor Green
}
function Get-Json([string]$path) {
  $r=Invoke-WebRequest -Uri ($base+$path) -UseBasicParsing -TimeoutSec 4
  if($r.StatusCode -ne 200){throw ('HTTP '+$r.StatusCode+' '+$path)}
  return ConvertFrom-Json -InputObject $r.Content
}
function Post-Json([string]$path,[object]$data) {
  $payload=ConvertTo-Json -InputObject $data -Depth 8 -Compress
  $r=Invoke-WebRequest -Uri ($base+$path) -Method POST -ContentType 'application/json' -Body $payload -UseBasicParsing -TimeoutSec 5
  return [pscustomobject]@{code=[int]$r.StatusCode;body=(ConvertFrom-Json -InputObject $r.Content)}
}
function Observe([string]$label,[int]$seconds,[scriptblock]$test) {
  $until=[DateTime]::UtcNow.AddSeconds($seconds);$errorText=''
  while([DateTime]::UtcNow -lt $until){
    if($null -ne $proc){
      $proc.Refresh()
      if($proc.HasExited){throw "Server exited during $label ($($proc.ExitCode))"}
    }
    try {
      $v=& $test
      if($null -ne $v -and $v -ne $false){return $v}
    }catch{$errorText=$_.Exception.Message}
    Start-Sleep -Milliseconds 250
  }
  throw ("TIMEOUT: "+$label+" "+$errorText)
}
function Find-Cargo {
  $existing=Get-Command cargo.exe -ErrorAction SilentlyContinue
  if($existing){return $existing.Source}
  $local=Join-Path $root '.local-galaxy-rust-tools\cargo\bin\cargo.exe'
  if(Test-Path $local){
    $env:CARGO_HOME=Join-Path $root '.local-galaxy-rust-tools\cargo'
    $env:RUSTUP_HOME=Join-Path $root '.local-galaxy-rust-tools\rustup'
    return $local
  }
  if($NoBootstrap){throw 'Cargo is missing, and automatic local setup was disabled.'}
  Write-Host 'Rust was not found. A FREE local toolchain can be downloaded to this project.'
  Write-Host 'No GitHub Actions. MSVC C++ Build Tools / Windows SDK may also be needed.'
  $answer=Read-Host 'Download free Rust into .local-galaxy-rust-tools? [y/N]'
  if($answer -notmatch '^(y|yes)$'){throw 'Cancelled compiler download.'}
  $toolroot=Join-Path $root '.local-galaxy-rust-tools'
  New-Item -ItemType Directory -Force -Path $toolroot | Out-Null
  $env:CARGO_HOME=Join-Path $toolroot 'cargo'
  $env:RUSTUP_HOME=Join-Path $toolroot 'rustup'
  $env:RUSTUP_INIT_SKIP_PATH_CHECK='yes'
  $installer=Join-Path $toolroot 'rustup-init.exe'
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' -OutFile $installer -UseBasicParsing
  & $installer '-y' '--no-modify-path' '--profile' 'minimal' '--default-toolchain' 'stable'
  if($LASTEXITCODE -ne 0 -or -not (Test-Path $local)){throw 'Rust bootstrap failed. Check toolchain and Windows SDK.'}
  return $local
}
function Check-SQLiteHeader([string]$path) {
  # Header only, NOT a PRAGMA integrity check.
  if(-not (Test-Path $path)){return 'missing'}
  $file=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  try {
    $buf=New-Object byte[] 16
    if($file.Read($buf,0,16) -ne 16){return 'too_short'}
    if([Text.Encoding]::ASCII.GetString($buf) -ne ('SQLite format 3'+[char]0)){return 'bad_header'}
    return 'header_ok_only'
  }finally{$file.Dispose()}
}
try{
  Set-Location $root
  Write-Host ('Result folder: '+$out)
  foreach($item in @('Cargo.toml','Cargo.lock','priv\galaxy\data\factions.json','crates\sim_core\src\strategy\long_term.rs','crates\sim_core\src\strategy\production_chain.rs','observer\governance-economy.html')){
    if(-not(Test-Path (Join-Path $root $item))){throw ('Complete PR83 native sources required: '+$item)}
  }
  Check $true 'unified PR83 source files exist'
  $cargo=Find-Cargo
  Write-Host '[1/3] Building CURRENT native Windows server...' -ForegroundColor Cyan
  $buildOut=Join-Path $out 'build.stdout.log';$buildErr=Join-Path $out 'build.stderr.log'
  $args=@{FilePath=$cargo;ArgumentList=@('build','--locked','-p','sim_server','--bin','genesis_server');WorkingDirectory=$root;Wait=$true;PassThru=$true;NoNewWindow=$true;RedirectStandardOutput=$buildOut;RedirectStandardError=$buildErr}
  $build=Start-Process @args
  if($build.ExitCode -ne 0){
    if(Test-Path $buildErr){Get-Content $buildErr -Tail 18 | Write-Host}
    throw ('Native Rust build failed with code '+$build.ExitCode+'. See build.stderr.log.')
  }
  $binary=Join-Path $root 'target\debug\genesis_server.exe'
  Check (Test-Path $binary) 'current native Genesis server compiled'
  $summary.binary_built=$true
  $summary.binary_sha256=(Get-FileHash $binary -Algorithm SHA256).Hash

  Write-Host '[2/3] Running ONE live, fresh 8-system Galaxy...' -ForegroundColor Cyan
  New-Item -ItemType Directory -Force -Path $tempDb | Out-Null
  $db=Join-Path $tempDb 'galaxy.db'
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
  $base="http://127.0.0.1:$port"
  $env:BIND_ADDR="127.0.0.1:$port"
  $env:DATABASE_PATH=$db
  $env:DATA_DIR=Join-Path $root 'priv\galaxy\data'
  $env:LIVING_SECTOR_UI_DIR=Join-Path $root 'observer'
  $env:LIVING_SECTOR_GALAXY='1'
  $env:LIVING_SECTOR_STRATEGY_MODE='execute'
  $env:WORLD_SPEED='1'
  $env:RUST_LOG='sim_server=warn,sim_core=warn'
  Remove-Item Env:LIVING_SECTOR_PLANNER -ErrorAction SilentlyContinue
  $serverOut=Join-Path $out 'server.stdout.log';$serverErr=Join-Path $out 'server.stderr.log'
  $launch=@{FilePath=$binary;WorkingDirectory=$root;PassThru=$true;WindowStyle='Hidden';RedirectStandardOutput=$serverOut;RedirectStandardError=$serverErr}
  $proc=Start-Process @launch
  $start=Observe 'native Galaxy startup' 55 {
    $s=Get-Json '/api/strategy'
    if($s.commanders -and @($s.factions).Count -ge 3){return $s}
  }
  Check ($start.schema_version -eq 1 -and $start.mode -eq 'execute') 'real strategy API is executing'
  Check ($null -ne $start.production_objectives) 'persistent Director objectives in live API'
  $world=Get-Json '/api/report';$health=Get-Json '/api/health'
  $ids=@($start.factions | ForEach-Object {$_.faction_id} | Sort-Object)
  Check (($ids -join ',') -eq 'ceti-freeholds,pirates,terran-authority') 'three real Galaxy factions'
  Check (@($world.systems).Count -eq 8) 'eight Galaxy systems'
  $summary.initial_tick=$health.tick
  foreach($asset in @(
    @('/observer/',''),
    @('/observer/governance-economy.html','production_objectives'),
    @('/observer/governance-approvals.html','policyStatus'),
    @('/observer/governance-charter.html',''),
    @('/observer/app.js','map-primitives.js'),
    @('/observer/map-primitives.js','export function'),
    @('/observer/transport.js','export async function getJSON')
  )){
    $html=Invoke-WebRequest -Uri ($base+$asset[0]) -UseBasicParsing -TimeoutSec 4
    if($html.StatusCode -ne 200 -or ($asset[1] -and -not $html.Content.Contains($asset[1]))){throw ('Observer HTTP failed: '+$asset[0])}
    if($asset[0].EndsWith('.js') -and $html.Headers['Content-Type'] -notmatch 'javascript'){throw ('Wrong JS MIME: '+$asset[0])}
  }
  Check $true 'all Observer and policy screens actually served by Rust'
  $speed=Post-Json '/api/sim/speed' @{ticks_per_second=30;world_speed=1}
  Check ($speed.code -eq 200) 'bounded game speed set'
  $post=Post-Json '/api/player/economic-mandate' @{faction_id='terran-authority';location='earth-station';commodity='water';kind='supply';min_stock=1200;mode='hold';budget_ceiling_cr=30000;treasury_floor_cr=10000}
  Check ($post.code -eq 202 -and $post.body.status -eq 'queued') 'real player HOLD command queued'
  $applied=Observe 'Director applied the hold policy' 35 {
    $s=Get-Json '/api/strategy'
    $m=$s.economic_mandates.'terran-authority'
    if($m -and $m.mode -eq 'hold'){return $s}
  }
  Check ($applied.economic_mandates.'terran-authority'.spent_cr -eq 0) 'HOLD does not spend its mandate'
  $evaluated=Observe 'native head evaluated HOLD' 45 {
    $s=Get-Json '/api/strategy'
    $f=@($s.factions | Where-Object {$_.faction_id -eq 'terran-authority'}) | Select-Object -First 1
    $p=@($f.head.policy_impacts | Where-Object {$_.department -eq 'economy' -and $_.status -eq 'hold'}) | Select-Object -First 1
    if($s.snapshot_tick -gt $start.snapshot_tick -and $p){return $s}
  }
  $f=@($evaluated.factions | Where-Object {$_.faction_id -eq 'terran-authority'}) | Select-Object -First 1
  $impact=@($f.head.policy_impacts | Where-Object {$_.department -eq 'economy'}) | Select-Object -First 1
  Check ($impact.status -eq 'hold' -and $impact.selected -eq $false) 'Head respected HOLD in an actual decision'
  Check ($null -ne $f.head.goal_reviews) 'Head real alternatives are visible'
  foreach($fac in @($evaluated.factions)){
    if($fac.construction -and $fac.construction.execution_chain){
      Check (@($fac.construction.execution_chain.steps).Count -eq 5) 'physical construction has five stages'
    }
  }
  $summary.live_world_tested=$true
  $summary.end_tick=$evaluated.snapshot_tick
  $summary.policy_impact=$impact.status
  $summary.head_choice=$f.head.selected_option
  Write-Host '[3/3] Checking fresh SQLite and packaging tested experimental game...' -ForegroundColor Cyan
  $proc.Refresh()
  if(-not $proc.HasExited){Stop-Process -Id $proc.Id -Force}
  $proc=$null
  Start-Sleep -Milliseconds 500
  $summary.sqlite_check=Check-SQLiteHeader $db
  Check ($summary.sqlite_check -eq 'header_ok_only') 'fresh SQLite header (NOT full PRAGMA integrity)'
  if(-not $SkipPackage){
    $bundle=Join-Path $out 'Living-Sector-Galaxy-067-Experimental'
    New-Item -ItemType Directory -Force -Path $bundle | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'priv\galaxy') | Out-Null
    Copy-Item $binary (Join-Path $bundle 'Genesis-Server.exe')
    Copy-Item (Join-Path $root 'observer') (Join-Path $bundle 'observer') -Recurse
    Copy-Item (Join-Path $root 'priv\galaxy\data') (Join-Path $bundle 'priv\galaxy\data') -Recurse
    Copy-Item (Join-Path $root 'START-GALAXY-067-EXPERIMENTAL.cmd') (Join-Path $bundle 'START-GALAXY.cmd')
    $gameZip=Join-Path $out 'Living-Sector-Galaxy-067-Win64.zip'
    Compress-Archive -LiteralPath $bundle -DestinationPath $gameZip -Force
    $summary.game_archive=$gameZip
    Check (Test-Path $gameZip) 'playable isolated Windows ZIP created'
  }
  $summary.status='passed'
  Write-Host 'PASS: one real combined Galaxy playtest completed.' -ForegroundColor Green
}catch{
  $summary.status='failed';$summary.error=$_.Exception.Message
  Write-Host ('FAILED: '+$_.Exception.Message) -ForegroundColor Red
}finally{
  if($proc){
    try{$proc.Refresh();if(-not $proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}}catch{}
  }
  $summary.checks=@($checks)
  [IO.File]::WriteAllText($reportPath,((ConvertTo-Json -InputObject $summary -Depth 12)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
  $diagnostics=Join-Path $out 'Living-Sector-Galaxy-067-DIAGNOSTICS.zip'
  $files=@($reportPath)
  foreach($name in @('build.stdout.log','build.stderr.log','server.stdout.log','server.stderr.log')){
    $path=Join-Path $out $name
    if(Test-Path $path){$files+=$path}
  }
  try{Compress-Archive -LiteralPath $files -DestinationPath $diagnostics -Force}catch{Write-Host 'Could not ZIP logs; individual files were retained.'}
  Write-Host ('Result: '+$reportPath)
  Write-Host ('Small report ZIP to share: '+$diagnostics)
  if($summary.game_archive){Write-Host ('Verified game ZIP: '+$summary.game_archive)}
}
if($summary.status -ne 'passed'){exit 1}
exit 0

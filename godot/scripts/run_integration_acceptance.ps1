param([ValidateSet('quick','all')][string]$Mode='quick')
$ErrorActionPreference='Stop'
$project=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testdir=Join-Path $project 'tests'
$logdir=Join-Path $project 'logs\integration-acceptance'
New-Item -ItemType Directory -Path $logdir -Force | Out-Null
$quick=@('p0_seed_check.gd','p1_tick_save_check.gd','p1_audit_check.gd','n2_calendar_check.gd','n3_events_check.gd','n4_registry_routes_check.gd','n5_native_recipes_check.gd','n6_paid_production_check.gd','n8_integration_check.gd','n23_production_tick_check.gd','n31_contract_command_runner_check.gd')
$results=New-Object System.Collections.ArrayList
function Record([string]$name,[string]$status,[int]$code,[string]$details) {
  [void]$results.Add([pscustomobject]@{name=$name;status=$status;exit_code=$code;details=$details})
  Write-Host "$status $name $details"
}
function Report {
  $failed=@($results | Where-Object {$_.status -ne 'PASS'}).Count
  $status=if($failed -eq 0 -and $results.Count -gt 0){'PASS'}else{'FAIL'}
  $report=[ordered]@{schema_version=1;status=$status;mode=$Mode;executed=$results.Count;failed=$failed;scope='Isolated Godot scripts and project import; not full gameplay or Rust parity';results=@($results.ToArray())}
  $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $logdir 'summary.json') -Encoding UTF8
  @("Status: $status","Executed: $($results.Count)","Failed: $failed") + @($results | ForEach-Object {"$($_.status) $($_.name) exit=$($_.exit_code) $($_.details)"}) | Set-Content (Join-Path $logdir 'summary.txt') -Encoding UTF8
  return $failed
}
$godot=''
foreach($candidate in @($env:GODOT_EXE,(Join-Path $project 'Godot.exe'),(Join-Path $project '..\Godot.exe'))) {
  if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {$godot=(Resolve-Path -LiteralPath $candidate).Path;break}
}
if(-not $godot) {
  foreach($name in @('godot.exe','godot4.exe','godot')) {
    $cmd=Get-Command $name -ErrorAction SilentlyContinue
    if($cmd){$godot=$cmd.Source;break}
  }
}
if(-not $godot) {Record 'runtime' 'FAIL' 2 'Godot executable missing';[void](Report);exit 2}
$tests=if($Mode -eq 'all') {
  @(Get-ChildItem -LiteralPath $testdir -Filter '*_check.gd' -File | ForEach-Object {$_.Name}) + @(Get-ChildItem -LiteralPath $testdir -Filter '*_smoke.gd' -File | ForEach-Object {$_.Name})
} else {$quick}
$tests=@($tests | Sort-Object -Unique)
if($tests.Count -eq 0){Record 'discovery' 'FAIL' 3 'No tests';[void](Report);exit 3}
foreach($test in $quick) {
  if(-not (Test-Path -LiteralPath (Join-Path $testdir $test) -PathType Leaf)) {Record $test 'FAIL' 4 'Required test missing'}
}
function Run([string]$name,[string[]]$arguments) {
  $stdout=Join-Path $logdir ($name+'.stdout.txt')
  $stderr=Join-Path $logdir ($name+'.stderr.txt')
  $log=Join-Path $logdir ($name+'.log')
  try {
    $p=Start-Process -FilePath $godot -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $errors=@()
    foreach($file in @($stdout,$stderr,$log)) {
      if(Test-Path -LiteralPath $file) {$errors+=@(Select-String -Path $file -Pattern '(?i)(SCRIPT ERROR|PARSE ERROR|ERROR:|_FAIL\b)' -ErrorAction SilentlyContinue)}
    }
    if($p.ExitCode -ne 0 -or $errors.Count -gt 0) {Record $name 'FAIL' $p.ExitCode "error_markers=$($errors.Count)"}
    else {Record $name 'PASS' 0 'exit=0, no error markers'}
  } catch {Record $name 'FAIL' 5 $_.Exception.Message}
}
$importlog=Join-Path $logdir 'project-import.log'
Run 'project-import' @('--headless','--editor','--path',('"' + $project + '"'),'--quit','--log-file',('"' + $importlog + '"'))
foreach($test in $tests) {
  if(-not (Test-Path -LiteralPath (Join-Path $testdir $test) -PathType Leaf)){continue}
  $name=[IO.Path]::GetFileNameWithoutExtension($test)
  $log=Join-Path $logdir ($name+'.log')
  Run $name @('--headless','--path',('"' + $project + '"'),'--script',('res://tests/'+$test),'--log-file',('"' + $log + '"'))
}
$fail=Report
if($fail -gt 0){exit 1}
exit 0

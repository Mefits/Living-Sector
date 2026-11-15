# Living Sector P2: open the full Git clone in Godot for local F5 playtests.
# Usage (from anywhere): powershell -ExecutionPolicy Bypass -File godot/scripts/p2_local_f5.ps1
# Optional: -GodotExe 'C:\Tools\Godot_v4.7.2-stable_win64.exe' -Smoke
[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [switch]$Smoke,
    [switch]$NoEditor
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$projectDir = Join-Path $repo 'godot'
$projectFile = Join-Path $projectDir 'project.godot'
$required = @(
    $projectFile,
    (Join-Path $repo 'native\priv\galaxy\data\factions.json'),
    (Join-Path $repo 'native\priv\galaxy\data\worlds\sol.json')
)
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Missing full-clone Galaxy file: $file. Open a complete Living-Sector clone, not a standalone godot folder."
    }
}
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $currentBranch = (& $git.Source -C $repo branch --show-current 2>$null)
    if ($LASTEXITCODE -eq 0 -and $currentBranch -ne 'integration/godot-phase2-unified-20261113') {
        Write-Warning "Current branch is '$currentBranch'; P2 integration is integration/godot-phase2-unified-20261113."
    }
}
if (-not $GodotExe) {
    $cmd = Get-Command godot, godot.exe, Godot_v4.7.2-stable_win64.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $GodotExe = $cmd.Source }
}
if (-not $GodotExe) {
    throw 'Godot not found in PATH. Pass -GodotExe with the path to Godot 4.7.2 Standard (GDScript).'
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    $cmd = Get-Command $GodotExe -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Godot executable not found: $GodotExe" }
    $GodotExe = $cmd.Source
}
$versionText = (& $GodotExe --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Cannot query Godot version: $versionText" }
if ($versionText -notmatch '^4\.7\.2([\.\-]|$)') {
    throw "Expected Godot 4.7.2, got '$versionText'. Avoid testing with a different engine version."
}
Write-Host "Living Sector P2 | $versionText | $projectDir"
if ($Smoke) {
    $checks = @(
        @('--headless', '--path', $projectDir, '--editor', '--import', '--quit'),
        @('--headless', '--path', $projectDir, '--script', 'res://tests/p2_unified_script_compile_check.gd'),
        @('--headless', '--path', $projectDir, '--script', 'res://tests/p2_n158_live_production_check.gd'),
        @('--headless', '--path', $projectDir, '--', '--p2-boot-check')
    )
    foreach ($arguments in $checks) {
        Write-Host ("Running: " + ($arguments -join ' '))
        & $GodotExe @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Godot local check failed (exit $LASTEXITCODE): $($arguments -join ' ')"
        }
    }
    Write-Host 'Local P2 checks passed on this working tree (not a Windows export test).'
}
if (-not $NoEditor) {
    Write-Host 'Opening Godot Editor. Press F5 there to play. No GitHub Actions or export is triggered.'
    Start-Process -FilePath $GodotExe -ArgumentList @('--editor', '--path', ('"' + $projectDir + '"')) -WorkingDirectory $projectDir
}

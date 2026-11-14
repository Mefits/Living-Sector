# Living Sector P2: open the full-clone Godot project without Actions/EXE export.
# Usage from any directory:
#   powershell -ExecutionPolicy Bypass -File .\godot\scripts\p2_local_open.ps1
#   powershell -ExecutionPolicy Bypass -File .\godot\scripts\p2_local_open.ps1 -GodotExe "D:\\Tools\\Godot_v4.7.2-stable_win64.exe"
#   powershell -ExecutionPolicy Bypass -File .\godot\scripts\p2_local_open.ps1 -CheckOnly
[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [switch]$CheckOnly,
    [switch]$WaitForEditor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

# Derive the repository root from the script location, not the caller's cwd.
$repo = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$project = Join-Path $repo "godot"
$projectFile = Join-Path $project "project.godot"
$required = @(
    $projectFile,
    (Join-Path $repo "native\priv\galaxy\data\factions.json"),
    (Join-Path $repo "native\priv\galaxy\data\worlds\sol.json"),
    (Join-Path $project "scripts\main.gd")
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) {
    Fail ("Incomplete Living Sector clone. Open the repository root in GitHub Desktop, not a copied godot folder.`nMissing:`n" + ($missing -join "`n"))
}

# Git is optional for opening Godot, but a detached/wrong branch is an easy
# source of misleading tests. Never switch branches or pull automatically.
$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $git) {
    $branch = (& $git.Source -C $repo branch --show-current 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $branch = [string]$branch
        if ($branch.Trim() -ne "integration/godot-phase2-unified-20261113") {
            Write-Warning "Current Git branch is '$branch', not integration/godot-phase2-unified-20261113. No branch changes were made."
        }
    }
}

Write-Host "Living Sector full clone: $repo"
Write-Host "Godot project: $projectFile"
Write-Host "Galaxy seed: OK"

if ($CheckOnly) {
    Write-Host "Preflight PASS. No editor launched, no CI triggered."
    exit 0
}

# Explicit executable wins. Otherwise use an installed Godot on PATH or a
# portable Standard build placed next to this repository. Do not download
# binaries, use GitHub Actions, or silently choose a Mono build.
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $cmd = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd) {
        $GodotExe = $cmd.Source
    } else {
        $candidates = @(Get-ChildItem -LiteralPath (Split-Path $repo -Parent) -Filter "Godot*win64*.exe" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "mono|dotnet|console" })
        if ($candidates.Count -eq 1) {
            $GodotExe = $candidates[0].FullName
        } else {
            Fail "Godot executable not found. Pass -GodotExe with the full path to Godot 4.7.2 Standard (portable)."
        }
    }
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    $cmd = Get-Command $GodotExe -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { Fail "Godot executable not found: $GodotExe" }
    $GodotExe = $cmd.Source
}

# Display version without claiming that a different version is supported.
$versionOutput = & $GodotExe --version 2>&1
if ($LASTEXITCODE -ne 0) { Fail "Could not run Godot --version: $versionOutput" }
$version = ([string]($versionOutput | Select-Object -First 1)).Trim()
Write-Host "Godot: $version"
if ($version -notmatch "^4\.7\.2([. -]|$)") {
    Write-Warning "Project checkpoint expects Godot 4.7.2. Current version differs; results may not be comparable."
}

Write-Host "Opening editor. Wait for import, then press F5. This does NOT export a Windows EXE."
$arguments = @("--editor", "--path", ('"' + $project + '"'))
$process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -PassThru -WorkingDirectory $project
if ($WaitForEditor) {
    $process.WaitForExit()
    exit $process.ExitCode
}
Write-Host ("Editor process started (PID {0})." -f $process.Id)

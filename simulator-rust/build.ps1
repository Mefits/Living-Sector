<#
.SYNOPSIS
  Windows build helpers for the Bevy client. Mirror of the Mac/Linux
  Makefile, just the targets that make sense on a Windows host.

.EXAMPLE
  .\build.ps1 build-win
  .\build.ps1 package-win
  .\build.ps1 publish-win
  .\build.ps1 publish-win -Version 1.2.3
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'help', 'build', 'run', 'verify',
        'build-win', 'package-win',
        'publish-win', 'butler-status',
        'clean'
    )]
    [string]$Target = 'help',

    [string]$Bin       = 'client_bevy',
    [string]$Cargo     = 'cargo',
    [string]$Version,
    [string]$ItchUser  = 'kalcode',
    [string]$ItchGame  = 'the-space-project'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# ------- Paths -------

$AppName    = 'The Space Project'
$AssetsSrc  = 'crates/client_bevy/assets'
$DistDir    = 'dist'
$WinDirRel  = "windows/$AppName"
$WinDir     = Join-Path $DistDir $WinDirRel
$TargetWin  = 'x86_64-pc-windows-msvc'

# Resolve VERSION from workspace Cargo.toml unless overridden.
# Source of truth is [workspace.package] version — keeps the binary
# (env!CARGO_PKG_VERSION) and the butler --userversion in lockstep.
if (-not $Version) {
    $cargoToml = Join-Path $PSScriptRoot 'Cargo.toml'
    $match = Select-String -Path $cargoToml `
                           -Pattern '^version\s*=\s*"([^"]+)"' `
                           -List | Select-Object -First 1
    if ($match) { $Version = $match.Matches[0].Groups[1].Value }
    else        { $Version = 'dev' }
}

$WinZipName = "$AppName-$Version.zip"
$WinZip     = Join-Path $DistDir "windows/$WinZipName"
$ItchTarget = "$ItchUser/$ItchGame"

# ------- Helpers -------

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host $msg }

function Invoke-Native([string]$exe, [string[]]$argv) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) {
        throw "$exe exited with code $LASTEXITCODE"
    }
}

function Ensure-RustupTarget([string]$triple) {
    $installed = & rustup target list --installed
    if ($installed -notcontains $triple) {
        Step "rustup target add $triple"
        Invoke-Native rustup @('target', 'add', $triple)
    }
}

# ------- Targets -------

function Invoke-Help {
@"
spaceproject build helpers (Windows)

Usage:  .\build.ps1 <target> [-Version X.Y.Z] [-Bin name]
                              [-ItchUser u] [-ItchGame g]

Native:
  build              Release build of $Bin for the host (Windows)
  run                Debug run of $Bin
  verify             scripts/verify.sh --strict (requires git-bash)

Windows binary + package:
  build-win          $TargetWin
  package-win        $WinDir\ + $WinZip

itch.io publishing (butler):
  publish-win        butler push $WinZip $ItchTarget`:windows --userversion $Version
  butler-status      butler status $ItchTarget

Maintenance:
  clean              Remove target\ and $DistDir\

Resolved version: $Version
"@ | Write-Host
}

function Invoke-Build {
    Step "$Cargo build --release -p $Bin"
    Invoke-Native $Cargo @('build', '--release', '-p', $Bin)
    Info ""
    Info "binary at: target\release\$Bin.exe"
    Info "(assets/ are read from $AssetsSrc at runtime via Cargo path"
    Info " for development; package-win bundles them next to the binary.)"
}

function Invoke-Run {
    Invoke-Native $Cargo @('run', '-p', $Bin)
}

function Invoke-Verify {
    if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
        throw 'verify needs bash on PATH (install Git for Windows).'
    }
    Invoke-Native bash @('scripts/verify.sh', '--strict')
}

function Invoke-BuildWin {
    Ensure-RustupTarget $TargetWin
    Step "$Cargo build --release -p $Bin --target $TargetWin"
    Invoke-Native $Cargo @('build', '--release', '-p', $Bin, '--target', $TargetWin)
    Info "==> target\$TargetWin\release\$Bin.exe"
}

function Invoke-PackageWin {
    Invoke-BuildWin

    if (Test-Path $WinDir) { Remove-Item $WinDir -Recurse -Force }
    New-Item -ItemType Directory -Path $WinDir -Force | Out-Null

    $exeSrc = Join-Path "target\$TargetWin\release" "$Bin.exe"
    $exeDst = Join-Path $WinDir "$Bin.exe"
    Copy-Item $exeSrc $exeDst

    $assetsDst = Join-Path $WinDir 'assets'
    Copy-Item $AssetsSrc $assetsDst -Recurse

    if (Test-Path $WinZip) { Remove-Item $WinZip -Force }

    # Zip with $AppName at archive root (matches `cd dist/windows && zip -r`).
    Push-Location (Join-Path $DistDir 'windows')
    try {
        Compress-Archive -Path $AppName -DestinationPath $WinZipName -Force
    } finally {
        Pop-Location
    }

    Info ""
    Info "==> $WinDir\"
    Info "==> $WinZip"
}

function Invoke-PublishWin {
    Invoke-PackageWin
    $channel = "$($ItchTarget):windows"
    Step "butler push $WinZip $channel --userversion $Version"
    Invoke-Native butler @('push', $WinZip, $channel, '--userversion', $Version)
}

function Invoke-ButlerStatus {
    Invoke-Native butler @('status', $ItchTarget)
}

function Invoke-Clean {
    if (Test-Path 'target') { Remove-Item 'target' -Recurse -Force }
    if (Test-Path $DistDir) { Remove-Item $DistDir -Recurse -Force }
    Info "==> cleaned target\ and $DistDir\"
}

# ------- Dispatch -------

switch ($Target) {
    'help'           { Invoke-Help }
    'build'          { Invoke-Build }
    'run'            { Invoke-Run }
    'verify'         { Invoke-Verify }
    'build-win'      { Invoke-BuildWin }
    'package-win'    { Invoke-PackageWin }
    'publish-win'    { Invoke-PublishWin }
    'butler-status'  { Invoke-ButlerStatus }
    'clean'          { Invoke-Clean }
}

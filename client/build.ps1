#!/usr/bin/env pwsh
# build.ps1 — Windows build helper for Space Simulator Client.
#
# Native PowerShell equivalent of the Windows-relevant Makefile targets
# (the Makefile is macOS-first and expects a Unix shell + GNU make).
# Run from client/.
#
# Targets:
#   help             Print usage
#   sim              Build Rust sim (release) -> ./simulator.exe
#   sim-debug        Build Rust sim (debug)   -> ./simulator.exe
#   clean-sim        Remove ./simulator.exe
#   dev              Launch Godot editor
#   export-win       Export Godot Windows .exe into build/
#   post-export-win  Copy ./simulator.exe alongside the exported .exe
#   build-win        sim + export-win + post-export-win
#   clean            Wipe build/
#
# Overrides (flag or env var):
#   -GodotPath  / $env:GODOT           (default: godot)
#   -CargoPath  / $env:CARGO           (default: cargo)
#   -SimSrc     / $env:SIMULATOR_SRC   (default: ../simulator-rust)
#   -CargoTarget                       Rust target triple; default = host
#   -ExePath                           Path the Godot preset exports to
#                                      (default: build/Space Simulator Client.exe)
#
# Examples:
#   ./build.ps1 sim
#   ./build.ps1 build-win
#   ./build.ps1 build-win -GodotPath 'C:\Godot\godot.exe'

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Target = 'help',
    [string]$GodotPath,
    [string]$CargoPath,
    [string]$SimSrc,
    [string]$CargoTarget,
    [string]$ExePath
)

$ErrorActionPreference = 'Stop'

# Default resolution: flag > env var > fallback.
if (-not $GodotPath)   { $GodotPath   = if ($env:GODOT)         { $env:GODOT }         else { 'godot' } }
if (-not $CargoPath)   { $CargoPath   = if ($env:CARGO)         { $env:CARGO }         else { 'cargo' } }
if (-not $SimSrc)      { $SimSrc      = if ($env:SIMULATOR_SRC) { $env:SIMULATOR_SRC } else { '../simulator-rust' } }
if (-not $CargoTarget) { $CargoTarget = if ($env:CARGO_TARGET)  { $env:CARGO_TARGET }  else { '' } }

$ClientDir    = $PSScriptRoot
$SimulatorBin = 'simulator'
$SimulatorDst = Join-Path $ClientDir "$SimulatorBin.exe"
$BuildDir     = Join-Path $ClientDir 'build'
$AppName      = 'Space Simulator Client'
if (-not $ExePath) { $ExePath = Join-Path $BuildDir "$AppName.exe" }

# Resolve $SimSrc against the script dir so it works regardless of the
# caller's CWD. Users expect `./build.ps1 sim` to work from anywhere.
if (-not [System.IO.Path]::IsPathRooted($SimSrc)) {
    $SimSrc = [System.IO.Path]::GetFullPath((Join-Path $ClientDir $SimSrc))
}

function Step([string]$msg) {
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Invoke-CargoBuild {
    param([switch]$Release)

    $manifest = Join-Path $SimSrc 'Cargo.toml'
    $argsList = @('build', '--manifest-path', $manifest)
    if ($Release)     { $argsList += '--release' }
    if ($CargoTarget) { $argsList += @('--target', $CargoTarget) }

    Step "$CargoPath $($argsList -join ' ')"
    & $CargoPath @argsList
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed (exit $LASTEXITCODE)" }
}

function Copy-SimulatorArtifact {
    param(
        [Parameter(Mandatory)][ValidateSet('debug','release')][string]$Profile
    )

    $targetRoot = Join-Path $SimSrc 'target'
    $targetDir  = if ($CargoTarget) {
        Join-Path (Join-Path $targetRoot $CargoTarget) $Profile
    } else {
        Join-Path $targetRoot $Profile
    }
    $built = Join-Path $targetDir "$SimulatorBin.exe"

    if (-not (Test-Path -LiteralPath $built -PathType Leaf)) {
        throw "cargo succeeded but $built not found"
    }

    Step "$built -> $SimulatorDst"
    Copy-Item -LiteralPath $built -Destination $SimulatorDst -Force
}

function Target-Help {
    @"
Usage: ./build.ps1 <target> [-GodotPath ...] [-CargoPath ...] [-SimSrc ...] [-CargoTarget ...] [-ExePath ...]

Targets:
  sim              Build the Rust sim (release) via $SimSrc and copy the binary to $SimulatorDst
  sim-debug        As sim but a debug build (fast compile)
  clean-sim        Remove $SimulatorDst
  dev              Launch Godot editor ($GodotPath)
  export-win       Export Windows .exe to $ExePath
  post-export-win  Copy $SimulatorDst alongside the exported .exe
  build-win        sim + export-win + post-export-win
  clean            Wipe $BuildDir
  help             Print this text
"@ | Write-Host
}

function Target-Sim      { Invoke-CargoBuild -Release; Copy-SimulatorArtifact -Profile 'release' }
function Target-SimDebug { Invoke-CargoBuild;          Copy-SimulatorArtifact -Profile 'debug' }

function Target-CleanSim {
    if (Test-Path -LiteralPath $SimulatorDst) {
        Step "rm $SimulatorDst"
        Remove-Item -LiteralPath $SimulatorDst -Force
    }
}

function Target-Dev {
    Step "$GodotPath --editor --path $ClientDir"
    & $GodotPath --editor --path $ClientDir
    if ($LASTEXITCODE -ne 0) { throw "godot editor failed (exit $LASTEXITCODE)" }
}

function Target-ExportWin {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    Step "export-win -> $ExePath"
    # Godot's Windows launcher is GUI-subsystem: `& godot ...` returns before
    # the export actually finishes, racing the post-export .exe check.
    # Start-Process waits properly, but its -ArgumentList joins elements with
    # spaces without quoting — "Windows Desktop" and the spaced exe path would
    # get split into extra args. ProcessStartInfo.ArgumentList escapes each
    # argument individually, so we use it directly.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $GodotPath
    $psi.UseShellExecute = $false
    # Godot locates project.godot via CWD. PowerShell's Set-Location doesn't
    # update .NET's Environment.CurrentDirectory, so set it explicitly here.
    $psi.WorkingDirectory = $ClientDir
    $psi.ArgumentList.Add('--headless')
    $psi.ArgumentList.Add('--path')
    $psi.ArgumentList.Add($ClientDir)
    $psi.ArgumentList.Add('--export-release')
    $psi.ArgumentList.Add('Windows Desktop')
    $psi.ArgumentList.Add($ExePath)
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "godot export failed (exit $($proc.ExitCode))" }
}

function Target-PostExportWin {
    # Godot's Windows export lays the game out as <name>.exe + <name>.pck
    # in a single folder; the sim binary just needs to live beside them.
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
        throw "no .exe at $ExePath (run export-win first)"
    }
    if (-not (Test-Path -LiteralPath $SimulatorDst -PathType Leaf)) {
        throw "simulator binary not found at $SimulatorDst (run sim first)"
    }

    $exeDir = Split-Path -Parent -Path (Resolve-Path -LiteralPath $ExePath).ProviderPath
    $dst    = Join-Path $exeDir "$SimulatorBin.exe"
    Step "$SimulatorDst -> $dst"
    Copy-Item -LiteralPath $SimulatorDst -Destination $dst -Force
}

function Target-BuildWin {
    Target-Sim
    Target-ExportWin
    Target-PostExportWin
    Step "build-win complete: $ExePath"
}

function Target-Clean {
    if (Test-Path -LiteralPath $BuildDir) {
        Step "rm -rf $BuildDir"
        Remove-Item -LiteralPath $BuildDir -Recurse -Force
    }
}

switch ($Target.ToLower()) {
    'help'            { Target-Help }
    'sim'             { Target-Sim }
    'sim-debug'       { Target-SimDebug }
    'clean-sim'       { Target-CleanSim }
    'dev'             { Target-Dev }
    'export-win'      { Target-ExportWin }
    'post-export-win' { Target-PostExportWin }
    'build-win'       { Target-BuildWin }
    'clean'           { Target-Clean }
    default {
        Write-Error "unknown target: $Target (use './build.ps1 help')"
        exit 1
    }
}

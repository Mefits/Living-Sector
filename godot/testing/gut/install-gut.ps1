# Living Sector — reproducible GUT 9.7.1 for Godot 4.7.2.
# This intentionally installs only the upstream addons/gut directory,
# not the upstream demo/tests/docs, and does not modify project.godot.
# MIT license remains in addons/gut/LICENSE.md.
[CmdletBinding()]
param(
    [string]$ProjectDir = "",
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$commit = "aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605"
$version = "9.7.1"
if (-not $ProjectDir) {
    $ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
$project = (Resolve-Path $ProjectDir).Path
if (-not (Test-Path (Join-Path $project "project.godot"))) {
    throw "ProjectDir must contain Living Sector's godot/project.godot"
}
$destination = Join-Path $project "addons\gut"
if ((Test-Path (Join-Path $destination "plugin.cfg")) -and -not $Force) {
    $existing = Get-Content (Join-Path $destination "plugin.cfg") -Raw
    if ($existing -match 'version="9\.7\.1"') {
        Write-Host "GUT 9.7.1 already installed at $destination"
        exit 0
    }
    throw "Another GUT version is installed. Review it; use -Force to replace."
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("living-sector-gut-" + [Guid]::NewGuid().ToString("N"))
$zip = Join-Path $tmp "gut.zip"
$expanded = Join-Path $tmp "extract"
try {
    New-Item -ItemType Directory -Force -Path $tmp, $expanded | Out-Null
    $uri = "https://codeload.github.com/bitwes/Gut/zip/$commit"
    Invoke-WebRequest -Uri $uri -OutFile $zip -MaximumRedirection 5
    Expand-Archive -Path $zip -DestinationPath $expanded
    $cfg = Get-ChildItem $expanded -Recurse -File -Filter plugin.cfg |
        Where-Object { $_.FullName -match '[\\/]addons[\\/]gut[\\/]plugin\.cfg$' } |
        Select-Object -First 1
    if (-not $cfg) { throw "The upstream archive does not contain addons/gut/plugin.cfg" }
    $text = Get-Content $cfg.FullName -Raw
    if ($text -notmatch 'version="9\.7\.1"') {
        throw "Unexpected upstream version; refusing to install"
    }
    if ((Test-Path $destination) -and -not $Force) {
        throw "GUT destination already exists; use -Force to replace"
    }
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if (Test-Path $destination) { Remove-Item -Recurse -Force $destination }
    Copy-Item -Path (Split-Path -Parent $cfg.FullName) -Destination $destination -Recurse
    if (-not (Test-Path (Join-Path $destination "gut_cmdln.gd"))) {
        throw "GUT CLI entry missing after installation"
    }
    Write-Host "Installed official GUT $version ($commit) to $destination"
    Write-Host "Run headless: godot --headless --path $project --script res://addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gexit"
    Write-Host "In editor enable Project > Project Settings > Plugins > Gut (optional for CLI)"
} finally {
    if (Test-Path $tmp) { Remove-Item -Path $tmp -Recurse -Force }
}

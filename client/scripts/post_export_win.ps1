# post_export_win.ps1 — copy the bundled Rust simulator binary
# alongside an exported Godot Windows .exe. Godot's Windows export
# lays the game out as <name>.exe + <name>.pck in a single folder,
# so the sim binary just needs to live in that same folder.
#
# Used by the Makefile's `post-export-win` target; safe standalone.
#
# Usage (pwsh / powershell):
#   ./post_export_win.ps1 -Exe <path-to-exe> [-Sim <path-to-simulator.exe>]
#
# The simulator binary is placed alongside the .exe — that matches
# the first non-override lookup path in server_manager.gd (Windows
# doesn't do .app bundles, so Contents/Resources/ isn't in play).

param(
    [Parameter(Mandatory = $true)]
    [string]$Exe,
    [string]$Sim = "./simulator.exe"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
    Write-Error "no .exe at $Exe"
    exit 1
}
if (-not (Test-Path -LiteralPath $Sim -PathType Leaf)) {
    Write-Error "simulator binary not found at $Sim. Run 'make sim-win' first."
    exit 1
}

$ExeDir = Split-Path -Parent -Path (Resolve-Path -LiteralPath $Exe).ProviderPath
$Dst    = Join-Path $ExeDir "simulator.exe"

Write-Host "==> $Sim -> $Dst"
Copy-Item -LiteralPath $Sim -Destination $Dst -Force

Write-Host "==> done."

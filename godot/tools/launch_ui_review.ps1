param(
    [string]$GodotExe = "",
    [switch]$SmokeOnly,
    [switch]$SkipSmoke
)
$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$found = $null
$candidates = @(
    $GodotExe,
    "D:\PROGRAMS\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
    "D:\PROGRAMS\Godot_v4.7.2-stable_win64.exe\Godot.exe"
)
foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $found = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if (-not $found) {
    $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { $found = $command.Source }
}
if (-not $found) {
    throw "Godot 4.7.2 executable not found. Use -GodotExe 'D:\path\Godot.exe'."
}
Write-Host "Living Sector UI review | project: $project"
Write-Host "Godot: $found"
if (-not $SkipSmoke) {
    $checks = @(
        @{ Path = "res://tests/p2_figma_ui_theme_check.gd"; Pass = "FIGMA_V1_NATIVE_THEME_PASS" },
        @{ Path = "res://tests/p2_strategy_ui_layout_scene_check.gd"; Pass = "SYSTEMBALANCE_FIGMA_LAYOUT_SCENE_PASS" }
    )
    foreach ($check in $checks) {
        Write-Host "Checking $($check.Path)..."
        # Capture logs so Godot parse errors cannot look like a successful test.
        $log = @(& $found --headless --path $project --script $check.Path 2>&1)
        $code = $LASTEXITCODE
        $log | ForEach-Object { Write-Host $_ }
        $output = $log -join "`n"
        if ($code -ne 0 -or -not $output.Contains($check.Pass)) {
            throw "UI smoke check failed: $($check.Path) (exit $code). Copy the console output to ChatGPT."
        }
    }
}
if ($SmokeOnly) {
    Write-Host "Smoke checks finished. No graphical game launched."
    exit 0
}
Write-Host "Launching Living Sector GUI..."
& $found --path $project
exit $LASTEXITCODE

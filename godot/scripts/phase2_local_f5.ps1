# Living Sector P2 — local Godot editor bootstrap (Windows PowerShell 5.1+).
# From a FULL GitHub Desktop clone: powershell -ExecutionPolicy Bypass -File .\godot\scripts\phase2_local_f5.ps1
# Optional: -GodotExe "C:\Tools\Godot_v4.7.2-stable_win64.exe" -Run
[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [switch]$Run,
    [switch]$Check
)
$ErrorActionPreference = "Stop"
function Stop-P2([string]$message) {
    Write-Host ("P2: " + $message) -ForegroundColor Red
    exit 1
}
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$projectDir = Join-Path $repo "godot"
$project = Join-Path $projectDir "project.godot"
if (-not (Test-Path -LiteralPath $project -PathType Leaf)) {
    Stop-P2 "Не найден godot/project.godot. Запускайте скрипт из полного клона."
}
$required = @(
    "native\priv\galaxy\data\factions.json",
    "native\priv\galaxy\data\worlds\sol.json"
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $relative) -PathType Leaf)) {
        Stop-P2 ("Отсутствует " + $relative + ". Нужен полный GitHub clone, не отдельная папка godot.")
    }
}
$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $git) {
    $current = (& $git.Source -C $repo branch --show-current 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -eq 0 -and $current -ne "integration/godot-phase2-unified-20261113") {
        Write-Warning ("Текущая ветка: " + $current + ". Для P2 нужна integration/godot-phase2-unified-20261113.")
    }
}
if (-not $GodotExe) {
    foreach ($commandName in @("godot", "godot.exe", "Godot_v4.7.2-stable_win64.exe")) {
        $candidate = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $candidate) { $GodotExe = $candidate.Source; break }
    }
}
if (-not $GodotExe) {
    # Portable Godot may be unpacked anywhere: only look in predictable
    # local directories; never download or execute an untrusted binary.
    foreach ($folder in @($repo, (Join-Path $repo "tools"), (Join-Path $repo "godot"))) {
        $candidate = Get-ChildItem -LiteralPath $folder -File -Filter "Godot*4.7.2*win64*.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "console" } | Select-Object -First 1
        if ($null -ne $candidate) { $GodotExe = $candidate.FullName; break }
    }
}
if (-not $GodotExe -or -not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    Stop-P2 "Не найден Godot 4.7.2. Укажите -GodotExe 'C:\путь\Godot_v4.7.2-stable_win64.exe'."
}
Write-Host ("P2 project: " + $project)
Write-Host ("Godot: " + $GodotExe)
if ($Check) {
    Write-Host "Проверка импорта ресурсов (локально, без GitHub Actions)..."
    & $GodotExe --headless --path $projectDir --editor --import --quit
    if ($LASTEXITCODE -ne 0) { Stop-P2 ("Godot import failed: " + $LASTEXITCODE) }
    Write-Host "Проверка GDScript..."
    & $GodotExe --headless --path $projectDir --script res://tests/p2_unified_script_compile_check.gd
    if ($LASTEXITCODE -ne 0) { Stop-P2 ("GDScript check failed: " + $LASTEXITCODE) }
}
if ($Run) {
    Write-Host "Запуск текущей игры..."
    & $GodotExe --path $projectDir
    exit $LASTEXITCODE
}
Write-Host "Открываю редактор Godot. После импорта нажмите F5."
& $GodotExe --editor --path $projectDir
exit $LASTEXITCODE

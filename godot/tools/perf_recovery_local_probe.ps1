# ARCHIVED RECOVERY PROFILER; canonical branch is integration/perf-astra-5-workers-20261116.
# Default CandidateCommit is historical baseline dd1f859, NOT current five-worker HEAD.
# To test current optimizations pass -CandidateCommit <exact current canonical SHA>.
# Living Sector performance recovery: run on Windows, never uses GitHub Actions.
# Launch from any branch. Uses a detached git worktree and pinned commit,
# so it NEVER switches or modifies feature/SystemBalance.
param(
    [string]$GodotExe = "D:\PROGRAMS\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
    [string]$CandidateCommit = "dd1f859462900473598410d1d32d7daf6618db9f",
    [string]$OutputDir = (Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "LivingSectorPerf"),
    [int]$LimitMinutes = 10,
    [string]$RepoRoot = "",
    [switch]$KeepSnapshots
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot executable not found: $GodotExe. Supply -GodotExe with the correct path."
}
$git = (Get-Command git -ErrorAction Stop).Source
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = $PSScriptRoot }
$repoRoot = (& $git -C $RepoRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or !$repoRoot) { throw "Run this script from a Git working tree." }
$prefix = $CandidateCommit.Substring(0, [Math]::Min(12, $CandidateCommit.Length))
$runDir = Join-Path $OutputDir ("probe-" + $prefix + "-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
# Keep logs outside OneDrive / redirected Documents. Validate physical creation
# both up front and immediately before using shell redirection.
$runDir = [System.IO.Path]::GetFullPath($runDir)
[System.IO.Directory]::CreateDirectory($runDir) | Out-Null
if (!(Test-Path -LiteralPath $runDir -PathType Container)) {
    throw "Log directory is unavailable: $runDir. Supply -OutputDir under local disk."
}
$worktree = Join-Path $env:TEMP ("ls-perf-" + $prefix + "-" + $PID)
$madeWorktree = $false
$oldProfile = [Environment]::GetEnvironmentVariable("LS_PROFILE_NATIVE_PHASES", "Process")
$oldTrace = [Environment]::GetEnvironmentVariable("LS_PROFILE_SHIP_TRACE", "Process")
try {
    # Fetch only when the pinned SHA is absent locally. This does not touch the
    # checkout, staged changes, or HEAD of the current user working branch.
    & $git -C $repoRoot cat-file -e "${CandidateCommit}^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Fetching recovery branch object (no checkout or merge)..."
        & $git -C $repoRoot fetch --no-tags origin integration/perf-astra-5-workers-20261116
        if ($LASTEXITCODE -ne 0) { throw "Cannot fetch recovery commit." }
        & $git -C $repoRoot cat-file -e "${CandidateCommit}^{commit}"
        if ($LASTEXITCODE -ne 0) { throw "Pinned commit $CandidateCommit is not available." }
    }
    & $git -C $repoRoot worktree add --detach $worktree $CandidateCommit
    if ($LASTEXITCODE -ne 0) { throw "Cannot create isolated worktree." }
    $madeWorktree = $true
    $godotProject = Join-Path $worktree "godot"
    $actualSha = (& $git -C $worktree rev-parse HEAD).Trim()
    if ($actualSha -ne $CandidateCommit) { throw "Unexpected checkout SHA: $actualSha" }

    [Environment]::SetEnvironmentVariable("LS_PROFILE_NATIVE_PHASES", "1", "Process")
    [Environment]::SetEnvironmentVariable("LS_PROFILE_SHIP_TRACE", "0", "Process")
    Write-Host "Pinned test commit: $actualSha"
    Write-Host "Output: $runDir"

    # Godot import first; fail on script parse errors. No cloud CI.
    [System.IO.Directory]::CreateDirectory($runDir) | Out-Null
    if (!(Test-Path -LiteralPath $runDir -PathType Container)) {
        throw "Log directory disappeared before Godot import: $runDir"
    }
    $importLog = Join-Path $runDir "import.log"
    & $GodotExe --headless --path $godotProject --editor --import --quit *> $importLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -Path $importLog -Pattern "SCRIPT ERROR:|Parse Error:" -Quiet)) {
        throw "Godot import/parse failed: $importLog"
    }
    [System.IO.Directory]::CreateDirectory($runDir) | Out-Null
    $rawLog = Join-Path $runDir "late-growth.log"
    $proc = Start-Process -FilePath $GodotExe -ArgumentList @(
        "--headless", "--path", ('"' + $godotProject + '"'),
        "--script", "res://tests/p2_late_growth_capture.gd"
    ) -RedirectStandardOutput $rawLog -RedirectStandardError (Join-Path $runDir "late-growth.stderr.log") -PassThru
    try {
        Wait-Process -Id $proc.Id -Timeout ([Math]::Max(1, $LimitMinutes) * 60) -ErrorAction Stop
    } catch {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "Probe exceeded $LimitMinutes minutes; see $rawLog"
    }
    $proc.Refresh()
    if ($proc.ExitCode -ne 0) {
        throw "Godot profiler exit code $($proc.ExitCode); see $rawLog"
    }
    $lines = Get-Content -LiteralPath $rawLog
    $rows = @()
    foreach ($line in $lines) {
        if ($line -match "P2_PERF_E_LATE_TICK_WINDOW\s+(\{.*\})") {
            $rows += ($Matches[1] | ConvertFrom-Json)
        }
    }
    if ($rows.Count -eq 0) { throw "No valid paid-tick profile window. See $rawLog" }
    $last = $rows[-1]
    $summary = [ordered]@{
        commit = $actualSha
        godot = $GodotExe
        machine = $env:COMPUTERNAME
        collected_at = (Get-Date).ToString("o")
        profile_enabled = $true
        stop_tick = $last.tick
        windows = $rows
        note = "Window observations only; reaching 900/2000 is not guaranteed."
    }
    $summaryPath = Join-Path $runDir "perf-summary.json"
    $summary | ConvertTo-Json -Depth 16 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Host "PERF_LOCAL_PROFILE_DONE stop_tick=$($last.tick) output=$summaryPath"
    $windowBrief = (($rows | ForEach-Object { $_.tick.ToString() + "=" + $_.window_average_ms + "ms" }) -join ", ")
    Write-Host "Windows: $windowBrief"
    if ($KeepSnapshots) {
        $snapDir = Join-Path $godotProject "logs/late-growth"
        if (Test-Path $snapDir) {
            Copy-Item -Path $snapDir -Destination (Join-Path $runDir "snapshots") -Recurse
        }
    }
} finally {
    [Environment]::SetEnvironmentVariable("LS_PROFILE_NATIVE_PHASES", $oldProfile, "Process")
    [Environment]::SetEnvironmentVariable("LS_PROFILE_SHIP_TRACE", $oldTrace, "Process")
    if ($madeWorktree) {
        & $git -C $repoRoot worktree remove --force $worktree | Out-Null
    }
}

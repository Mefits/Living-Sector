# Local, opt-in diagnostic export. Does not export saves, credentials or game data.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logs = Join-Path $root 'logs'
$integration = Join-Path $logs 'integration'
$dest = Join-Path $root ('diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
$tmp = Join-Path $env:TEMP ('living-sector-godot-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $tmp -ItemType Directory -Force | Out-Null

try {
    $present = @()
    # Legacy P0/P1 smoke logs (when present).
    foreach ($name in @('godot-p0.log', 'p0-seed-smoke.log', 'p1-tick-save-smoke.log')) {
        $log = Join-Path $logs $name
        if (Test-Path -LiteralPath $log -PathType Leaf) {
            Copy-Item -LiteralPath $log -Destination (Join-Path $tmp $name)
            $present += $name
        }
    }
    # N32 integration smoke writes project-import.log, per-test .log files,
    # and summary.txt to logs/integration, not directly to logs.
    if (Test-Path -LiteralPath $integration -PathType Container) {
        $selected = @(Get-ChildItem -LiteralPath $integration -File | Where-Object {
            $_.Extension -eq '.log' -or $_.Name -eq 'summary.txt'
        })
        if ($selected.Count -gt 0) {
            $target = Join-Path $tmp 'integration'
            New-Item -Path $target -ItemType Directory -Force | Out-Null
            foreach ($file in $selected) {
                Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $target $file.Name)
                $present += ('integration/' + $file.Name)
            }
        }
    }
    if ($present.Count -eq 0) {
        throw ('No diagnostic logs found under ' + $logs + '. Run RUN-INTEGRATION-SMOKE.cmd first.')
    }

    $sha = 'unknown'
    $branch = 'unknown (ZIP without .git)'
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    $repoRoot = (Resolve-Path (Join-Path $root '..')).Path
    if ($git -and (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
        $readSha = & $git.Source -C $repoRoot rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { $sha = "$readSha".Trim() }
        $readBranch = & $git.Source -C $repoRoot branch --show-current 2>$null
        if ($LASTEXITCODE -eq 0 -and "$readBranch".Trim()) { $branch = "$readBranch".Trim() }
    }
    $sourceHint = 'unknown'
    $summary = Join-Path $integration 'summary.txt'
    if (Test-Path -LiteralPath $summary -PathType Leaf) {
        $match = Select-String -LiteralPath $summary -Pattern '^Source:\s*(.+)$' | Select-Object -First 1
        if ($match) { $sourceHint = $match.Matches[0].Groups[1].Value.Trim() }
    }
    $meta = [ordered]@{
        project = 'Living Sector Godot port'
        local_branch = $branch
        summary_source_hint = $sourceHint
        source_commit = $sha
        exported_at_utc = [DateTime]::UtcNow.ToString('o')
        included_logs = $present
        note = 'Only selected Godot diagnostics logs; no saves/credentials.'
    }
    [IO.File]::WriteAllText((Join-Path $tmp 'manifest.json'),
        (ConvertTo-Json $meta -Depth 5), ([Text.UTF8Encoding]::new($false)))
    Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $dest -Force
    Write-Host ('Diagnostics ZIP created: ' + $dest) -ForegroundColor Green
    Write-Host ('Included files: ' + $present.Count)
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

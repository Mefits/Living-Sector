# Local, opt-in diagnostic export; no user saves or tokens/credentials.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dest = Join-Path $root ('diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
$tmp = Join-Path $env:TEMP ('living-sector-godot-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $tmp -ItemType Directory -Force | Out-Null
try {
    $names = @('godot-p0.log', 'p0-seed-smoke.log', 'p1-tick-save-smoke.log')
    $present = @()
    foreach ($name in $names) {
        $log = Join-Path (Join-Path $root 'logs') $name
        if (Test-Path $log) {
            Copy-Item -LiteralPath $log -Destination (Join-Path $tmp $name)
            $present += $name
        }
    }
    $meta = [ordered]@{
        project = 'Living Sector Godot port'
        branch = 'feature/godot-p1-ticks-orbits-saves'
        exported_at_utc = [DateTime]::UtcNow.ToString('o')
        source_commit = 'unknown'
        included_logs = $present
        note = 'Only three known local Godot log filenames and source commit; no worlds/saves/credentials.'
    }
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        $repoRoot = (Resolve-Path (Join-Path $root '..')).Path
        if (Test-Path (Join-Path $repoRoot '.git')) {
            $sha = & $git.Source -C $repoRoot rev-parse HEAD 2>$null
            if ($LASTEXITCODE -eq 0) { $meta.source_commit = "$sha".Trim() }
        }
    }
    [IO.File]::WriteAllText((Join-Path $tmp 'manifest.json'),
        (ConvertTo-Json $meta -Depth 5), ([Text.UTF8Encoding]::new($false)))
    Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $dest -Force
    Write-Host ('Diagnostics ZIP created: ' + $dest) -ForegroundColor Green
    Write-Host 'You can attach this small ZIP in ChatGPT.'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

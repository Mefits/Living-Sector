# Living Sector - read-only diagnosis for Godot 4.7.2 Unexpected NUL.
# Run via diagnose_text_encoding.cmd after GitHub Desktop Pull.
# Checks ONLY text resource files in this complete Godot project.
# Never changes or deletes game files or editor caches.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$reportPath = Join-Path $env:TEMP 'livingsector-godot-encoding-report.txt'
$extensions = @('.gd', '.tscn', '.tres', '.godot', '.cfg', '.gdshader', '.shader', '.json', '.theme')
$decoder = New-Object System.Text.UTF8Encoding($false, $true)
$report = New-Object 'System.Collections.Generic.List[string]'
$problems = 0
$scanned = 0
$report.Add('Living Sector Godot source encoding diagnostic')
$report.Add(('Project: ' + $projectRoot))
$report.Add(('Run at: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$report.Add('No files were modified.')
$report.Add('')

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot'))) {
    Write-Host 'ERROR: cannot locate godot/project.godot next to this script.' -ForegroundColor Red
    exit 2
}

Get-ChildItem -LiteralPath $projectRoot -File -Recurse -Force | Where-Object {
    $extensions -contains $_.Extension.ToLowerInvariant() -and
    $_.FullName -notmatch '[\\/](\.godot|\.git)[\\/]'
} | ForEach-Object {
    $file = $_
    $scanned++
    $reason = New-Object 'System.Collections.Generic.List[string]'
    try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $zeros = 0
        foreach ($byte in $bytes) {
            if ($byte -eq 0) { $zeros++ }
        }
        if ($zeros -gt 0) {
            $reason.Add(('NUL bytes: ' + $zeros))
        }
        if ($bytes.Length -ge 2) {
            if (($bytes[0] -eq 0xff -and $bytes[1] -eq 0xfe) -or
                ($bytes[0] -eq 0xfe -and $bytes[1] -eq 0xff)) {
                $reason.Add('UTF-16 BOM: Godot expects UTF-8 text resources')
            }
        }
        try {
            $decoded = $decoder.GetString($bytes)
            if ($decoded.Contains([char]0xfffd)) {
                $reason.Add('Contains Unicode replacement character U+FFFD')
            }
        } catch [System.Text.DecoderFallbackException] {
            $reason.Add('Invalid UTF-8 bytes')
        }
    } catch {
        $reason.Add(('Could not read: ' + $_.Exception.Message))
    }
    if ($reason.Count -gt 0) {
        $problems++
        $relative = $file.FullName.Substring($projectRoot.Length).TrimStart('\', '/')
        $report.Add(('SUSPECT: ' + $relative))
        foreach ($why in $reason) { $report.Add(('  ' + $why)) }
        $report.Add('')
    }
}

$report.Add(('Scanned text resources: ' + $scanned))
$report.Add(('Suspect source files: ' + $problems))
$report.Add('')
if ($problems -eq 0) {
    $report.Add('All tracked/local source text files checked have no NUL and are valid UTF-8.')
    $report.Add('If Godot still reports NUL after reopening, close the editor and')
    $report.Add('rename the GENERATED godot/.godot directory to .godot-old, then reopen.')
    $report.Add('Do NOT rename/delete godot/project.godot or the native source tree.')
} else {
    $report.Add('Do NOT edit files blindly. Share these SUSPECT paths with the developer.')
}

[System.IO.File]::WriteAllLines($reportPath, $report.ToArray(), [System.Text.UTF8Encoding]::new($false))
$report | ForEach-Object {
    if ($_.StartsWith('SUSPECT: ')) { Write-Host $_ -ForegroundColor Red }
    else { Write-Host $_ }
}
Write-Host ''
Write-Host ('Report saved: ' + $reportPath) -ForegroundColor Cyan
if ($problems -gt 0) { exit 1 }
exit 0

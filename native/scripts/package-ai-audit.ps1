param([string]$ResultDir = 'ai-block-bcd-results', [string]$ZipFile = 'AI-BLOCK-BCD-RESULTS.zip')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $root $ResultDir
$temp = Join-Path $root 'ai-block-bcd-pack-only'
if (Test-Path $temp) {Remove-Item $temp -Recurse -Force}
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
  Get-ChildItem -Path $source -Recurse -File | ForEach-Object {
    if ($_.Name -match '\.(db|db-wal|db-shm)$') { return }
    $relative = $_.FullName.Substring($source.Length).TrimStart('\','/')
    $destination = Join-Path $temp $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item $_.FullName $destination
  }
  Copy-Item (Join-Path $root 'Cargo.lock') (Join-Path $temp 'Cargo.lock') -ErrorAction SilentlyContinue
  $dest = Join-Path $root $ZipFile
  if (Test-Path $dest) {Remove-Item $dest -Force}
  Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $dest -Force
  Write-Host "Result package: $dest"
} finally {
  Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

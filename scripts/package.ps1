$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TocPath = Join-Path $RepoRoot 'CleanTree\CleanTree.toc'
$AddonPath = Join-Path $RepoRoot 'CleanTree'
$DistPath = Join-Path $RepoRoot 'dist'

$VersionLine = Get-Content $TocPath | Where-Object { $_ -match '^## Version:\s*(.+)$' } | Select-Object -First 1
if (-not $VersionLine) {
    throw 'Could not find ## Version in CleanTree.toc'
}

$Version = ([regex]::Match($VersionLine, '^## Version:\s*(.+)$')).Groups[1].Value.Trim()
$ZipPath = Join-Path $DistPath "CleanTree-v$Version.zip"

New-Item -ItemType Directory -Force -Path $DistPath | Out-Null
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Compress-Archive -Path $AddonPath -DestinationPath $ZipPath -CompressionLevel Optimal
Write-Host "Created: $ZipPath"

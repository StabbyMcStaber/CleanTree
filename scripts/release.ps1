# CleanTree one-command release helper (Windows PowerShell 5.1+)
# Usage: powershell -ExecutionPolicy Bypass -File .\scripts\release.ps1 -Version 1.2.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,
    [string]$NotesFile,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE): $($Arguments -join ' ')" }
}
foreach ($command in @('git','gh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Install $command and ensure it is on PATH." }
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
    Invoke-Checked 'gh' @('auth','status')
    $top = (& git rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0 -or ([IO.Path]::GetFullPath($top).TrimEnd('\','/') -ne [IO.Path]::GetFullPath($root).TrimEnd('\','/'))) {
        throw 'Run this script from the CleanTree Git checkout.'
    }
    $currentBranch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'main') { throw 'Switch to main before releasing.' }
    if ((& git status --porcelain)) { throw 'Working tree is dirty. Commit/stash your changes before releasing.' }
    Invoke-Checked 'git' @('fetch','origin','main','--tags')
    $localHead = (& git rev-parse HEAD).Trim()
    $remoteHead = (& git rev-parse refs/remotes/origin/main).Trim()
    if ($localHead -ne $remoteHead) { throw 'Local main differs from origin/main. Run git pull --ff-only, then retry.' }
    $tag = "v$Version"
    & git rev-parse --verify --quiet "refs/tags/$tag" *> $null
    if ($LASTEXITCODE -eq 0) { throw "Tag $tag already exists locally." }
    & git ls-remote --exit-code --tags origin "refs/tags/$tag" *> $null
    if ($LASTEXITCODE -eq 0) { throw "Tag $tag already exists on origin." }
    if ($LASTEXITCODE -ne 2) { throw 'Could not verify remote tag availability.' }
    $toc = Join-Path $root 'CleanTree\CleanTree.toc'
    $tocContent = [IO.File]::ReadAllText($toc)
    if ($tocContent -notmatch '(?m)^## Version:\s*([^\r\n]+)') { throw 'Missing version field in CleanTree.toc.' }
    $priorVersion = $Matches[1].Trim()
    $pattern = '(?m)^(## Version:\s*)[^\r\n]+'
    # Replace using a match evaluator to avoid special replacement-string characters.
    $updated = [regex]::Replace($tocContent,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $m.Groups[1].Value + $Version},1)
    $noteDir = Join-Path $root '.github\release-notes'
    $notePath = Join-Path $noteDir "$tag.md"
    if (Test-Path $notePath) { throw "Release notes already exist: $notePath" }
    if ($NotesFile) {
        $sourceNotes = (Resolve-Path $NotesFile).Path
        $notes = [IO.File]::ReadAllText($sourceNotes)
    } else {
        $notes = "# CleanTree $tag`r`n`r`n## Changes`r`n`r`n- Describe what changed in this release.`r`n`r`n## Requirements`r`n`r`n- World of Warcraft 3.3.5a on Project Ebonhold`r`n- EbonAPI 2.1.0+`r`n"
    }
    if ([string]::IsNullOrWhiteSpace($notes)) { throw 'Release notes cannot be empty.' }
    Write-Host "Preparing CleanTree $tag (currently $priorVersion)" -ForegroundColor Cyan
    Write-Host "Release notes preview:`n$notes"
    if (-not $Yes) {
        $ok = Read-Host "Commit version/notes, push main, tag and publish $tag via GitHub Actions? Type RELEASE"
        if ($ok -cne 'RELEASE') { Write-Host 'Canceled. No changes made.'; return }
    }
    New-Item -ItemType Directory -Force -Path $noteDir | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($toc,$updated,$utf8)
    [IO.File]::WriteAllText($notePath,$notes,$utf8)
    Invoke-Checked 'git' @('add','--','CleanTree/CleanTree.toc',".github/release-notes/$tag.md")
    Invoke-Checked 'git' @('commit','-m',"Release CleanTree $tag")
    Invoke-Checked 'git' @('push','origin','main')
    Invoke-Checked 'git' @('tag','-a',$tag,'-m',"CleanTree $tag")
    Invoke-Checked 'git' @('push','origin',$tag)
    Write-Host "Tag pushed. GitHub Actions will package and publish $tag." -ForegroundColor Green
    Write-Host "Watch: https://github.com/StabbyMcStaber/CleanTree/actions/workflows/release.yml"
    Write-Host "Release: https://github.com/StabbyMcStaber/CleanTree/releases/tag/$tag"
} finally { Pop-Location }

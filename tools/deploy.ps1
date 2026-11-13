# Build an addon of the monorepo, then install it into WoW Forever and record a GitHub deployment.
#   pwsh tools/deploy.ps1 Pedibus            build + install + deployment on "pedibus-local-test"
#   pwsh tools/deploy.ps1 Pedibus -Demo      same, with demo/Demo.lua loaded first (fake group)
#   pwsh tools/deploy.ps1 Pedibus -Version 1.4.0 -OutDir dist    build only (release workflow)
# The build copies the files listed in the TOC (+ Bindings.xml) and injects ## Version:
# a local build and a release build differ only by that line.
param(
    [Parameter(Mandatory)][string]$Addon,
    [string]$Version,
    [string]$OutDir,
    [switch]$Demo,
    [string]$AddOnsDir = 'F:\Wow\World of Warcraft\_forever_\Interface\AddOns'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$src = Join-Path $root "addons/$Addon"
$tocPath = Join-Path $src "$Addon.toc"
if (-not (Test-Path $tocPath)) { throw "No TOC at $tocPath" }
$slug = $Addon.ToLower()

if (-not $Version) {
    # Local build: last tag of this addon + commit, e.g. 1.3.1+dev.672ac48 (.dirty if uncommitted changes).
    $tag = git -C $root describe --tags --abbrev=0 --match "$slug/v*" 2>$null
    $base = if ($tag) { $tag -replace '^.*/v', '' } else { '0.0.0' }
    $dirty = if (git -C $root status --porcelain) { '.dirty' } else { '' }
    $Version = "$base+dev.$(git -C $root rev-parse --short HEAD)$dirty"
}

# Build into <OutDir>/<Addon>, or a temp folder for a local install.
$stageRoot = if ($OutDir) { $OutDir } else { Join-Path ([IO.Path]::GetTempPath()) "wow-addons-build" }
$stage = Join-Path $stageRoot $Addon
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory $stage | Out-Null

$toc = (Get-Content $tocPath -Raw) -replace "`r", ''
$files = $toc -split "`n" | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() -replace '\\', '/' }
if (Test-Path (Join-Path $src 'Bindings.xml')) { $files += 'Bindings.xml' }
if ($Demo) {
    $files += 'demo/Demo.lua'
    $first = ($toc -split "`n" | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } | Select-Object -First 1)
    $toc = $toc -replace "(?m)^$([regex]::Escape($first))$", "demo\Demo.lua`n$first"
    $toc = $toc -replace '(?m)^(## Title: .*)$', '$1 |cffff9a1a(DEMO)|r'
}
foreach ($f in $files) {
    $to = Join-Path $stage $f
    New-Item -ItemType Directory (Split-Path $to) -Force | Out-Null
    Copy-Item (Join-Path $src $f) $to
}
if ($toc -notmatch '(?m)^## Version: @project-version@$') { throw "$Addon.toc must contain '## Version: @project-version@'" }
$toc = $toc -replace '(?m)^## Version: @project-version@$', "## Version: $Version"
[IO.File]::WriteAllText((Join-Path $stage "$Addon.toc"), $toc)
Write-Host "Built $Addon $Version -> $stage"
if ($OutDir) { return }

# Install: replace AddOns/<Addon> only.
$dest = Join-Path $AddOnsDir $Addon
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Copy-Item $stage $dest -Recurse
Write-Host "Installed $Addon $Version -> $dest"

# GitHub deployment on <addon>-local-test, if this commit is on GitHub.
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) { $gh = 'C:\Program Files\GitHub CLI\gh.exe' }
$sha = git -C $root rev-parse HEAD
git -C $root fetch -q origin
if (-not (git -C $root branch -r --contains $sha)) {
    Write-Warning "Commit $($sha.Substring(0,7)) is not pushed: GitHub deployment not recorded."
    return
}
Push-Location $root
try {
    $body = @{ ref = $sha; environment = "$slug-local-test"; description = $Version; auto_merge = $false
               required_contexts = @(); payload = @{ version = $Version; demo = [bool]$Demo } } | ConvertTo-Json
    $id = $body | & $gh api repos/{owner}/{repo}/deployments --input - --jq '.id'
    if ($LASTEXITCODE) { throw "GitHub deployment failed" }
    & $gh api "repos/{owner}/{repo}/deployments/$id/statuses" -f state=success -f description=$Version --silent
    Write-Host "GitHub deployment $id recorded on $slug-local-test"
} finally { Pop-Location }

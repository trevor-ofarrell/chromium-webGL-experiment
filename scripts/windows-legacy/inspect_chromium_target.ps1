[CmdletBinding()]
param(
  [string]$SrcDir = "src"
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root $SrcDir

if (-not (Test-Path $Src)) {
  throw "Chromium checkout not found at $Src"
}

$RootBuild = Join-Path $Src "BUILD.gn"
if (Test-Path $RootBuild) {
  Write-Host "content_shell references in src/BUILD.gn:"
  Select-String -Path $RootBuild -Pattern "//content/shell:content_shell" -Context 0,1
} else {
  Write-Host "src/BUILD.gn is not present yet."
}

$ContentShellBuild = Join-Path $Src "content\shell\BUILD.gn"
if (Test-Path $ContentShellBuild) {
  Write-Host ""
  Write-Host "content/shell target declarations:"
  Select-String -Path $ContentShellBuild -Pattern "content_shell|executable|source_set|group" -Context 0,2 | Select-Object -First 60
} else {
  Write-Host ""
  Write-Host "content/shell/BUILD.gn is not present yet. Resume gclient sync."
}

$CandidateFiles = @(
  "content\shell\app",
  "content\shell\browser",
  "content\shell\common"
)

foreach ($Path in $CandidateFiles) {
  $Full = Join-Path $Src $Path
  if (Test-Path $Full) {
    Write-Host ""
    Write-Host $Path
    Get-ChildItem $Full -Force | Select-Object Name, Mode
  }
}

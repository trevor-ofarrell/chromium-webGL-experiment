[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$RevisionFile = Join-Path $Root ".chromium_revision"
$PinRefreshManifest = Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json"
$SourceInvestigationDoc = Join-Path $Root "docs\source_investigation.md"
$OriginalRevision = (Get-Content -LiteralPath $RevisionFile -Raw).Trim()
$OriginalPinRefreshHash = if (Test-Path -LiteralPath $PinRefreshManifest) {
  (Get-FileHash -Algorithm SHA256 -LiteralPath $PinRefreshManifest).Hash
} else {
  ""
}
$OriginalSourceInvestigationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceInvestigationDoc).Hash
$DryRunRevision = "0123456789abcdef0123456789abcdef01234567"

$Output = & (Join-Path $Root "scripts\refresh_chromium_pin.ps1") `
  -Revision $DryRunRevision `
  -SkipSync `
  -SkipGnGen `
  -DryRun *>&1

$Text = ($Output | ForEach-Object { [string]$_ }) -join "`n"
$AfterRevision = (Get-Content -LiteralPath $RevisionFile -Raw).Trim()
$AfterPinRefreshHash = if (Test-Path -LiteralPath $PinRefreshManifest) {
  (Get-FileHash -Algorithm SHA256 -LiteralPath $PinRefreshManifest).Hash
} else {
  ""
}
$AfterSourceInvestigationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceInvestigationDoc).Hash

if ($AfterRevision -ne $OriginalRevision) {
  throw "refresh_chromium_pin.ps1 -DryRun modified .chromium_revision."
}
if ($AfterPinRefreshHash -ne $OriginalPinRefreshHash) {
  throw "refresh_chromium_pin.ps1 -DryRun modified chromium-pin-refresh.json."
}
if ($AfterSourceInvestigationHash -ne $OriginalSourceInvestigationHash) {
  throw "refresh_chromium_pin.ps1 -DryRun modified docs\source_investigation.md."
}

foreach ($Pattern in @(
    "Target Chromium revision: $DryRunRevision",
    "fetch Chromium revision",
    "checkout Chromium revision",
    "update \.chromium_revision",
    "sync Chromium dependencies",
    "Skipped by -SkipSync",
    "GN generation",
    "Skipped by -SkipGnGen",
    "record Chromium pin refresh provenance",
    "write prebuild environment manifest",
    "check viewer patch applies",
    "restamp source investigation verification"
  )) {
  if ($Text -notmatch $Pattern) {
    throw "Dry-run output did not include expected pattern: $Pattern`n$Text"
  }
}

Write-Host "Chromium pin refresh dry-run is non-mutating and includes expected handoff and source-map restamp steps."

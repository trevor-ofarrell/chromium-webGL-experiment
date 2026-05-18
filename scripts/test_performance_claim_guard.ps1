[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\performance-claim-guard"
$PendingOutput = Join-Path $TempDir "performance-claim-pending.md"
$CleanOutput = Join-Path $TempDir "performance-claim-clean.md"
$ClaimDoc = Join-Path $TempDir "claim.md"

function Assert-Matches {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )

  if ($Text -notmatch $Pattern) {
    throw "Missing $Description. Pattern: $Pattern"
  }
}

if (Test-Path -LiteralPath $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$OldDocs = $env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS
$OldAllowOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
$OldSkip = $env:THREE_BROWSER_SKIP_PERFORMANCE_CLAIM_GUARD_TEST

try {
  $AuditText = Get-Content -LiteralPath (Join-Path $Root "scripts\audit_artifacts.ps1") -Raw
  Assert-Matches $AuditText "function Add-PerformanceClaimGuardRow" "performance claim audit row"
  Assert-Matches $AuditText "function Get-PrematurePerformanceClaimHits" "performance claim scanner"
  Assert-Matches $AuditText "Official comparison manifest missing or incomplete; performance claims would be premature" "premature-claim pending wording"
  Assert-Matches $AuditText "THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1" "test docs override guard"

  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS = $ClaimDoc
  $env:THREE_BROWSER_SKIP_PERFORMANCE_CLAIM_GUARD_TEST = "1"

  @"
# Synthetic Claim

The fork is 20% faster than stock Chromium in the WebGL2 draw-call benchmark.
"@ | Set-Content -LiteralPath $ClaimDoc -Encoding UTF8
  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -DocumentationOnly -Output $PendingOutput *>&1
  $PendingChecklist = Get-Content -LiteralPath $PendingOutput -Raw
  Assert-Matches $PendingChecklist "Documentation \| Premature performance claims \| pending" "pending premature claim row"
  Assert-Matches $PendingChecklist "20% faster than stock Chromium" "detected synthetic claim"

  @"
# Synthetic Guarded Claim

Before claiming the fork is 20% faster than stock Chromium, run the official same-revision comparison.
"@ | Set-Content -LiteralPath $ClaimDoc -Encoding UTF8
  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -DocumentationOnly -Output $CleanOutput *>&1
  $CleanChecklist = Get-Content -LiteralPath $CleanOutput -Raw
  Assert-Matches $CleanChecklist "Documentation \| Premature performance claims \| done" "clean guarded claim row"
  if ($CleanChecklist -match "Documentation \| Premature performance claims \| pending") {
    throw "Performance claim guard rejected guarded pending-language documentation."
  }
} finally {
  if ($null -eq $OldDocs) {
    Remove-Item Env:\THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS = $OldDocs
  }
  if ($null -eq $OldAllowOverrides) {
    Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowOverrides
  }
  if ($null -eq $OldSkip) {
    Remove-Item Env:\THREE_BROWSER_SKIP_PERFORMANCE_CLAIM_GUARD_TEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_SKIP_PERFORMANCE_CLAIM_GUARD_TEST = $OldSkip
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Performance claim guard rejects unguarded stock/fork performance wins until official same-revision evidence exists."

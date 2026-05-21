[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\documentation-completion-audit"
$GapOutput = Join-Path $TempDir "documentation-completion-gap.md"
$FinalOutput = Join-Path $TempDir "documentation-completion-final.md"

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

$OldSkip = $env:THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST
$OldAllowOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
$OldOfficialManifest = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
$OldTrustedManifest = $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST

try {
  $AuditText = Get-Content -LiteralPath (Join-Path $Root "scripts\audit_artifacts.ps1") -Raw
  Assert-Matches $AuditText "function Add-DocumentationFinalizationRow" "documentation finalization audit function"
  Assert-Matches $AuditText "official comparison manifest missing" "official evidence gap detection"
  Assert-Matches $AuditText "trusted experiment matrix manifest missing" "trusted evidence gap detection"
  Assert-Matches $AuditText "one-hour stock/fork stability evidence incomplete" "stability evidence gap detection"
  Assert-Matches $AuditText "pending/blocker documentation language present" "pending documentation language detection"

  $env:THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST = "1"
  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = Join-Path $TempDir "missing-official-manifest.json"
  $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = Join-Path $TempDir "missing-trusted-manifest.json"

  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -DocumentationOnly -Output $GapOutput *>&1
  $GapChecklist = Get-Content -LiteralPath $GapOutput -Raw
  Assert-Matches $GapChecklist "Documentation \| Final documentation evidence \| pending" "pending final documentation row when evidence is missing"
  Assert-Matches $GapChecklist "final documentation evidence is incomplete" "final documentation evidence wording"
  Assert-Matches $GapChecklist "official comparison manifest missing" "missing official manifest evidence"
  Assert-Matches $GapChecklist "trusted experiment matrix manifest missing" "missing trusted manifest evidence"

  Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
  Remove-Item Env:\THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST -ErrorAction SilentlyContinue
  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -DocumentationOnly -Output $FinalOutput *>&1
  $FinalChecklist = Get-Content -LiteralPath $FinalOutput -Raw
  Assert-Matches $FinalChecklist "Documentation \| Final documentation evidence \| done" "done final documentation row with completed evidence"
  if ($FinalChecklist -match "Documentation \| Final documentation evidence \| pending") {
    throw "Documentation finalization still reports pending with completed evidence."
  }
} finally {
  if ($null -eq $OldSkip) {
    Remove-Item Env:\THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST = $OldSkip
  }
  if ($null -eq $OldAllowOverrides) {
    Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowOverrides
  }
  if ($null -eq $OldOfficialManifest) {
    Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OldOfficialManifest
  }
  if ($null -eq $OldTrustedManifest) {
    Remove-Item Env:\THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $OldTrustedManifest
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Documentation completion audit rejects missing evidence and accepts the completed final documentation evidence set."

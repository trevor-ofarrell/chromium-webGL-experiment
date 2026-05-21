[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\removed-subsystems-completion-audit"
$Output = Join-Path $TempDir "removed-subsystems-completion-audit.md"
$MissingOutput = Join-Path $TempDir "removed-subsystems-missing-evidence-audit.md"

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

try {
  $AuditText = Get-Content -LiteralPath (Join-Path $Root "scripts\audit_artifacts.ps1") -Raw
  Assert-Matches $AuditText "function Add-RemovedSubsystemFinalRegisterRow" "removed-subsystem final-register audit function"
  Assert-Matches $AuditText "official comparison manifest missing" "official evidence gap detection"
  Assert-Matches $AuditText "trusted experiment matrix manifest missing" "trusted evidence gap detection"
  Assert-Matches $AuditText "pending subsystem/future-decision language present" "pending-language detection"

  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $Output -OptimizationOnly *>&1
  $Checklist = Get-Content -LiteralPath $Output -Raw
  Assert-Matches $Checklist "Optimization documentation \| Removed subsystem final decision register \| done" "completed removed-subsystem final-register row"
  Assert-Matches $Checklist "no pending-only language" "completed final-register evidence wording"

  $PreviousAllowOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
  $PreviousOfficialManifest = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
  $PreviousTrustedManifest = $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST
  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = Join-Path $TempDir "missing-official-manifest.json"
  $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = Join-Path $TempDir "missing-trusted-manifest.json"
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $MissingOutput -OptimizationOnly *>&1
  } finally {
    if ($null -eq $PreviousAllowOverrides) {
      Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $PreviousAllowOverrides
    }
    if ($null -eq $PreviousOfficialManifest) {
      Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $PreviousOfficialManifest
    }
    if ($null -eq $PreviousTrustedManifest) {
      Remove-Item Env:\THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $PreviousTrustedManifest
    }
  }
  $MissingChecklist = Get-Content -LiteralPath $MissingOutput -Raw
  Assert-Matches $MissingChecklist "Optimization documentation \| Removed subsystem final decision register \| pending" "evidence-gap removed-subsystem final-register row"
  Assert-Matches $MissingChecklist "official comparison manifest missing" "missing official manifest evidence"
  Assert-Matches $MissingChecklist "trusted experiment matrix manifest missing" "missing trusted manifest evidence"
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Removed-subsystem completion audit accepts final registers with completed evidence and rejects missing official/trusted evidence."

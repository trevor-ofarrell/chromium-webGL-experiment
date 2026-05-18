[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\removed-subsystems-completion-audit"
$Output = Join-Path $TempDir "removed-subsystems-completion-audit.md"

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
  Assert-Matches $Checklist "Optimization documentation \| Removed subsystem final decision register \| pending" "pending removed-subsystem final-register row"
  Assert-Matches $Checklist "final removed/disabled subsystem evidence is incomplete" "final evidence gap wording"
  Assert-Matches $Checklist "official comparison manifest missing" "missing official manifest evidence"
  Assert-Matches $Checklist "trusted experiment matrix manifest missing" "missing trusted manifest evidence"
  Assert-Matches $Checklist "pending subsystem/future-decision language present" "pending subsystem language evidence"
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Removed-subsystem completion audit keeps draft subsystem registers pending until official and trusted evidence exists."

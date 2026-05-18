[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\documentation-completion-audit"
$Output = Join-Path $TempDir "documentation-completion-audit.md"

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
  Assert-Matches $AuditText "function Add-DocumentationFinalizationRow" "documentation finalization audit function"
  Assert-Matches $AuditText "official comparison manifest missing" "official evidence gap detection"
  Assert-Matches $AuditText "trusted experiment matrix manifest missing" "trusted evidence gap detection"
  Assert-Matches $AuditText "one-hour stock/fork stability evidence incomplete" "stability evidence gap detection"
  Assert-Matches $AuditText "pending/blocker documentation language present" "pending documentation language detection"

  $PreviousSkip = $env:THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST
  $env:THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST = "1"
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -DocumentationOnly -Output $Output *>&1
  } finally {
    if ($null -eq $PreviousSkip) {
      Remove-Item Env:\THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST = $PreviousSkip
    }
  }

  $Checklist = Get-Content -LiteralPath $Output -Raw
  Assert-Matches $Checklist "Documentation \| Final documentation evidence \| pending" "pending final documentation row"
  Assert-Matches $Checklist "final documentation evidence is incomplete" "final documentation evidence wording"
  Assert-Matches $Checklist "official comparison manifest missing" "missing official manifest evidence"
  Assert-Matches $Checklist "trusted experiment matrix manifest missing" "missing trusted manifest evidence"
  Assert-Matches $Checklist "one-hour stock/fork stability evidence incomplete" "missing stability evidence"
  Assert-Matches $Checklist "pending/blocker documentation language present" "pending documentation wording evidence"
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Documentation completion audit keeps final docs pending until official, trusted, stability, and measured-result evidence exists."

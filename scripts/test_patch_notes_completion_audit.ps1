[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\patch-notes-completion-audit"
$Output = Join-Path $TempDir "patch-notes-completion-audit.md"

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
  Assert-Matches $AuditText "function Add-PatchNotesRow" "patch notes semantic audit function"
  Assert-Matches $AuditText "official comparison manifest missing" "official evidence gap detection"
  Assert-Matches $AuditText "trusted experiment matrix manifest missing" "trusted evidence gap detection"
  Assert-Matches $AuditText "draft-only language present" "draft-language detection"

  $PreviousSkip = $env:THREE_BROWSER_SKIP_PATCH_NOTES_COMPLETION_AUDIT_TEST
  $env:THREE_BROWSER_SKIP_PATCH_NOTES_COMPLETION_AUDIT_TEST = "1"
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $Output -PatchStateOnly *>&1
  } finally {
    if ($null -eq $PreviousSkip) {
      Remove-Item Env:\THREE_BROWSER_SKIP_PATCH_NOTES_COMPLETION_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_PATCH_NOTES_COMPLETION_AUDIT_TEST = $PreviousSkip
    }
  }

  $Checklist = Get-Content -LiteralPath $Output -Raw
  Assert-Matches $Checklist "Fork patch \| Patch notes \| pending" "pending patch notes row"
  Assert-Matches $Checklist "final patch-series evidence is incomplete" "final evidence gap wording"
  Assert-Matches $Checklist "official comparison manifest missing" "missing official manifest evidence"
  Assert-Matches $Checklist "trusted experiment matrix manifest missing" "missing trusted manifest evidence"
  Assert-Matches $Checklist "draft-only language present" "draft language evidence"
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Patch notes completion audit keeps draft patch notes pending until official and trusted evidence exists."

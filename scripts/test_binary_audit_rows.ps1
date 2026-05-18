[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$AuditPath = Join-Path $Root "scripts\audit_artifacts.ps1"
$AuditText = Get-Content -LiteralPath $AuditPath -Raw

function Assert-Matches {
  param(
    [string]$Pattern,
    [string]$Description
  )

  if ($AuditText -notmatch $Pattern) {
    throw "Binary artifact audit is missing $Description. Pattern: $Pattern"
  }
}

function Assert-NotMatches {
  param(
    [string]$Pattern,
    [string]$Description
  )

  if ($AuditText -match $Pattern) {
    throw "Binary artifact audit still contains $Description. Pattern: $Pattern"
  }
}

Assert-Matches 'function\s+Add-BinaryFileRow' "the dedicated binary row helper"
Assert-Matches '\.Length\s+-gt\s+0' "a positive file-size check"
Assert-Matches 'Get-FileHashString\s+\$PathValue' "SHA-256 evidence for accepted binaries"
Assert-Matches 'not a non-empty executable file' "a rejection message for empty or invalid binary files"
Assert-Matches 'Add-BinaryFileRow\s+"Build"\s+"Stock baseline content_shell binary"\s+"src\\out\\ReleaseBaseline\\content_shell\.exe"' "strict stock binary audit row wiring"
Assert-Matches 'Add-BinaryFileRow\s+"Build"\s+"Fork default content_shell binary"\s+"src\\out\\ReleaseViewerDefault\\content_shell\.exe"' "strict fork binary audit row wiring"
Assert-NotMatches 'Add-FileRow\s+"Build"\s+"Stock baseline content_shell binary"' "the old stock binary existence-only row"
Assert-NotMatches 'Add-FileRow\s+"Build"\s+"Fork default content_shell binary"' "the old fork binary existence-only row"

Write-Host "Binary artifact audit rows require non-empty executable files with SHA-256 evidence."

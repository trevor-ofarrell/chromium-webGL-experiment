[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\source-investigation-revision-guard"
$TempDoc = Join-Path $TempDir "source_investigation_stale.md"

if (Test-Path -LiteralPath $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$OldDocOverride = $env:THREE_BROWSER_TEST_SOURCE_INVESTIGATION_DOC
$OldAllowOverride = $env:THREE_BROWSER_ALLOW_TEST_SOURCE_INVESTIGATION_DOC

try {
  $CurrentDoc = Get-Content -LiteralPath (Join-Path $Root "docs\source_investigation.md") -Raw
  $RevisionFile = Join-Path $Root ".chromium_revision"
  $ExpectedRevision = (Get-Content -LiteralPath $RevisionFile -Raw).Trim()
  if ($ExpectedRevision -notmatch "^[0-9a-f]{40}$") {
    throw ".chromium_revision does not contain a 40-character Chromium revision."
  }

  $StaleRevision = "0000000000000000000000000000000000000000"
  if ($ExpectedRevision -eq $StaleRevision) {
    $StaleRevision = "1111111111111111111111111111111111111111"
  }

  $StaleDoc = $CurrentDoc -replace [regex]::Escape($ExpectedRevision), $StaleRevision
  Set-Content -LiteralPath $TempDoc -Value $StaleDoc -Encoding UTF8

  $env:THREE_BROWSER_TEST_SOURCE_INVESTIGATION_DOC = $TempDoc
  $env:THREE_BROWSER_ALLOW_TEST_SOURCE_INVESTIGATION_DOC = "1"

  $FailedAsExpected = $false
  $FailureText = ""
  try {
    $null = & (Join-Path $Root "scripts\test_source_investigation_paths.ps1") *>&1
  } catch {
    $FailedAsExpected = $true
    $FailureText = $_.Exception.Message
  }

  if (-not $FailedAsExpected) {
    throw "Source investigation path test accepted a stale documented verification revision."
  }
  if ($FailureText -notmatch "verification revision is stale") {
    throw "Source investigation path test failed for the wrong reason: $FailureText"
  }
} finally {
  if ($null -eq $OldDocOverride) {
    Remove-Item Env:\THREE_BROWSER_TEST_SOURCE_INVESTIGATION_DOC -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_SOURCE_INVESTIGATION_DOC = $OldDocOverride
  }
  if ($null -eq $OldAllowOverride) {
    Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_SOURCE_INVESTIGATION_DOC -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_ALLOW_TEST_SOURCE_INVESTIGATION_DOC = $OldAllowOverride
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Source investigation revision guard rejects stale documented Chromium verification revisions."

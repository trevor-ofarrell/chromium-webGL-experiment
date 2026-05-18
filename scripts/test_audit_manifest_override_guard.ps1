[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Audit = Join-Path $Root "scripts\audit_artifacts.ps1"
$TempDir = Join-Path $Root "benchmarks\tmp\manifest-override-guard"
$TempOutput = Join-Path $TempDir "checklist.md"
$FakeOfficialManifest = Join-Path $TempDir "official-comparison-manifest.json"
$FakeWebGlReport = Join-Path $TempDir "official-webgl2-comparison.md"
$FakeWebGpuReport = Join-Path $TempDir "official-webgpu-comparison.md"
$FakeRemovedSubsystemsDoc = Join-Path $TempDir "removed-subsystems.md"
$FakePerformanceClaimDoc = Join-Path $TempDir "performance-claim.md"

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$OldOfficialManifestPath = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
$OldWebGlReportPath = $env:THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT
$OldWebGpuReportPath = $env:THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT
$OldRemovedSubsystemsDoc = $env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC
$OldPerformanceClaimDocs = $env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS
$OldAllowManifestOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES

try {
  Set-Content -LiteralPath $FakeOfficialManifest -Value "{}" -Encoding UTF8
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $FakeOfficialManifest
  Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue

  $FailedAsExpected = $false
  $FailureText = ""
  try {
    $null = & $Audit -Output $TempOutput *>&1
  } catch {
    $FailedAsExpected = $true
    $FailureText = $_.Exception.Message
  }
  if (-not $FailedAsExpected) {
    throw "Artifact audit accepted a test official manifest path override without THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
  }
  if ($FailureText -notmatch "THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1") {
    throw "Artifact audit reported the wrong failure for an ungated official manifest override: $FailureText"
  }

  Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
  Set-Content -LiteralPath $FakeWebGlReport -Value "# fake report" -Encoding UTF8
  Set-Content -LiteralPath $FakeWebGpuReport -Value "# fake report" -Encoding UTF8
  $env:THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT = $FakeWebGlReport
  $env:THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT = $FakeWebGpuReport
  Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue

  $FailedAsExpected = $false
  $FailureText = ""
  try {
    $null = & $Audit -ReportStateOnly -Output $TempOutput *>&1
  } catch {
    $FailedAsExpected = $true
    $FailureText = $_.Exception.Message
  }
  if (-not $FailedAsExpected) {
    throw "Artifact audit accepted test official report path overrides without THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
  }
  if ($FailureText -notmatch "THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT and THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT require THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1") {
    throw "Artifact audit reported the wrong failure for ungated official report overrides: $FailureText"
  }

  Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT -ErrorAction SilentlyContinue
  Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT -ErrorAction SilentlyContinue
  Set-Content -LiteralPath $FakeRemovedSubsystemsDoc -Value "# fake removed subsystem register" -Encoding UTF8
  $env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC = $FakeRemovedSubsystemsDoc
  Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue

  $FailedAsExpected = $false
  $FailureText = ""
  try {
    $null = & $Audit -OptimizationOnly -Output $TempOutput *>&1
  } catch {
    $FailedAsExpected = $true
    $FailureText = $_.Exception.Message
  }
  if (-not $FailedAsExpected) {
    throw "Artifact audit accepted a test removed-subsystem doc override without THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
  }
  if ($FailureText -notmatch "THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1") {
    throw "Artifact audit reported the wrong failure for an ungated removed-subsystem doc override: $FailureText"
  }

  Remove-Item Env:\THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC -ErrorAction SilentlyContinue
  Set-Content -LiteralPath $FakePerformanceClaimDoc -Value "# fake performance claim docs" -Encoding UTF8
  $env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS = $FakePerformanceClaimDoc
  Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue

  $FailedAsExpected = $false
  $FailureText = ""
  try {
    $null = & $Audit -DocumentationOnly -Output $TempOutput *>&1
  } catch {
    $FailedAsExpected = $true
    $FailureText = $_.Exception.Message
  }
  if (-not $FailedAsExpected) {
    throw "Artifact audit accepted test performance-claim doc overrides without THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
  }
  if ($FailureText -notmatch "THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1") {
    throw "Artifact audit reported the wrong failure for ungated performance-claim doc overrides: $FailureText"
  }
} finally {
  if ($null -eq $OldOfficialManifestPath) {
    Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OldOfficialManifestPath
  }
  if ($null -eq $OldWebGlReportPath) {
    Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT = $OldWebGlReportPath
  }
  if ($null -eq $OldWebGpuReportPath) {
    Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT = $OldWebGpuReportPath
  }
  if ($null -eq $OldRemovedSubsystemsDoc) {
    Remove-Item Env:\THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC = $OldRemovedSubsystemsDoc
  }
  if ($null -eq $OldPerformanceClaimDocs) {
    Remove-Item Env:\THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS = $OldPerformanceClaimDocs
  }
  if ($null -eq $OldAllowManifestOverrides) {
    Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowManifestOverrides
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Artifact audit rejects test manifest, report, removed-subsystem doc, and performance-claim doc path overrides unless the explicit test override gate is enabled."

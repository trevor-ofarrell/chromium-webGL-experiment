[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\speedup-gate-suite-promotion"
$OfficialManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$SuitePromotionManifestPath = Join-Path $TempDir "suite-promotion-plan.json"
$InputListPath = Join-Path $TempDir "suite-promotion-inputs.txt"
$AnalysisJsonPath = Join-Path $TempDir "suite-promotion-analysis.json"
$AuditOutput = Join-Path $TempDir "audit.md"

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

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Value
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $PathValue -Encoding ASCII
}

function Invoke-Audit {
  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -ManifestAuditOnly -Output $AuditOutput *>&1
  return Get-Content -LiteralPath $AuditOutput -Raw
}

$OldAllowOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
$OldOfficialManifest = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
$OldSuitePromotionManifest = $env:THREE_BROWSER_TEST_SUITE_PROMOTION_PLAN_MANIFEST

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  $ChromiumRevision = (Get-Content -LiteralPath (Join-Path $Root ".chromium_revision") -Raw).Trim()
  $ForkRevision = "$ChromiumRevision+viewerpatch-test"
  $GeneratedAt = (Get-Date).ToUniversalTime().ToString("o")
  $RawBaseline = Join-Path $TempDir "baseline-webgl2.json"
  $RawFork = Join-Path $TempDir "fork-webgl2.json"
  Write-Json $RawBaseline ([pscustomobject]@{})
  Write-Json $RawFork ([pscustomobject]@{})
  Set-Content -LiteralPath $InputListPath -Encoding ASCII -Value @($RawBaseline, $RawFork)

  & node (Join-Path $Root "scripts\analyze_candidates.mjs") --fileList $InputListPath --json $AnalysisJsonPath --quiet
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate suite-promotion analyzer digest fixture."
  }
  $InputDigest = [string]((Get-Content -LiteralPath $AnalysisJsonPath -Raw | ConvertFrom-Json).input_file_digest)

  Write-Json $OfficialManifestPath ([pscustomobject]@{
      generated_at = $GeneratedAt
      dry_run = $false
      phase = "completed"
      chromium_revision = $ChromiumRevision
      fork_revision = $ForkRevision
      options = [pscustomobject]@{
        include_webgpu = $true
        duration = 30
        warmup = 5
        complexity = 2
      }
      result_files = [pscustomobject]@{
        baseline_webgl2 = @()
        fork_default_webgl2 = @()
        aggressive_webgl2 = @()
        baseline_webgpu = @()
        fork_default_webgpu = @()
        aggressive_webgpu = @()
      }
    })

  Write-Json $SuitePromotionManifestPath ([pscustomobject]@{
      generated_at = $GeneratedAt
      dry_run = $false
      phase = "completed"
      chromium_revision = $ChromiumRevision
      fork_revision = $ForkRevision
      options = [pscustomobject]@{
        duration = 30
        warmup = 5
        complexity = 2
      }
      generated_input_list = $InputListPath
      generated_input_count = 2
      analysis = [pscustomobject]@{
        json = $AnalysisJsonPath
        expected_input_file_digest = $InputDigest
        expected_chromium_revision = $ChromiumRevision
        expected_fork_revision = $ForkRevision
      }
    })

  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OfficialManifestPath
  $env:THREE_BROWSER_TEST_SUITE_PROMOTION_PLAN_MANIFEST = $SuitePromotionManifestPath

  $Audit = Invoke-Audit
  Assert-Matches $Audit "Official performance \| Required WebGL2/WebGPU speedup claim gate \| pending" "pending speedup gate row"
  Assert-Matches $Audit "Included 2 comparable suite-promotion result files" "suite-promotion result inclusion in speedup gate"

  $MismatchedPromotion = Get-Content -LiteralPath $SuitePromotionManifestPath -Raw | ConvertFrom-Json
  $MismatchedPromotion.options.complexity = 1
  Write-Json $SuitePromotionManifestPath $MismatchedPromotion
  $MismatchedAudit = Invoke-Audit
  Assert-Matches $MismatchedAudit "Suite-promotion candidate files not included" "suite-promotion exclusion detail for mismatched complexity"
  Assert-Matches $MismatchedAudit "complexity mismatch" "suite-promotion complexity mismatch rejection"

  Write-Host "Final speedup gate includes completed, digest-verified suite-promotion analyzer inputs and rejects mismatched complexity."
} finally {
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
  if ($null -eq $OldSuitePromotionManifest) {
    Remove-Item Env:\THREE_BROWSER_TEST_SUITE_PROMOTION_PLAN_MANIFEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_SUITE_PROMOTION_PLAN_MANIFEST = $OldSuitePromotionManifest
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

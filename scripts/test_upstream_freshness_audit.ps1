[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\upstream-freshness-audit-test"

function Assert-UnderDirectory {
  param(
    [string]$PathValue,
    [string]$Parent
  )

  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if (-not $FullPath.StartsWith($FullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside expected directory. path=$FullPath parent=$FullParent"
  }
}

function Invoke-FreshnessAudit {
  param(
    [string]$Name,
    [string]$ObservedHead,
    [object]$PinRefresh = $null,
    [object]$OfficialManifest = $null,
    [switch]$ClearObservedHead
  )

  $ManifestRel = "benchmarks\tmp\upstream-freshness-audit-test\$Name-manifest.json"
  $AuditRel = "benchmarks\tmp\upstream-freshness-audit-test\$Name-audit.md"
  $OfficialManifestRel = "benchmarks\tmp\upstream-freshness-audit-test\$Name-official-comparison-manifest.json"
  $OldObservedHead = $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION
  $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION = $ObservedHead
  try {
    $null = & (Join-Path $Root "scripts\write_environment_manifest.ps1") -Output $ManifestRel *>&1
  } finally {
    if ($null -eq $OldObservedHead) {
      Remove-Item "Env:\THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION" -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION = $OldObservedHead
    }
  }

  $ManifestPath = Join-Path $Root $ManifestRel
  $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  if ($null -eq $PinRefresh) {
    $PinRefresh = [pscustomobject]@{
      path = "benchmarks\reports\chromium-pin-refresh.json"
      exists = $false
      target_revision = $null
      previous_revision = $null
      selected_from_upstream_head = $false
      selected_at = $null
      source = $null
      generated_at = $null
      target_matches_expected = $false
    }
  }
  $Manifest.chromium.pin_refresh = $PinRefresh
  if ($ClearObservedHead) {
    $Manifest.chromium.upstream_head_revision = ""
    $Manifest.chromium.upstream_head_matches_expected = $false
  }
  $Manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

  if ($null -ne $OfficialManifest) {
    $OfficialManifestPath = Join-Path $Root $OfficialManifestRel
    $OfficialManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OfficialManifestPath -Encoding UTF8
  }

  $OldAllowManifestOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
  $OldOfficialManifest = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OfficialManifestRel

  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") `
      -Output $AuditRel `
      -EnvironmentManifest $ManifestRel `
      -BuildStateOnly *>&1
  } finally {
    if ($null -eq $OldAllowManifestOverrides) {
      Remove-Item "Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES" -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowManifestOverrides
    }
    if ($null -eq $OldOfficialManifest) {
      Remove-Item "Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST" -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OldOfficialManifest
    }
  }

  return Get-Content -LiteralPath (Join-Path $Root $AuditRel) -Raw
}

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  $ExpectedRevision = (Get-Content (Join-Path $Root ".chromium_revision") -Raw).Trim()
  $ExpectedForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ExpectedRevision -Root $Root
  $StaleRevision = "1111111111111111111111111111111111111111"
  if ($StaleRevision -eq $ExpectedRevision) {
    $StaleRevision = "2222222222222222222222222222222222222222"
  }

  $FreshAudit = Invoke-FreshnessAudit "fresh" $ExpectedRevision
  if ($FreshAudit -notmatch "\| Build \| Observed upstream Chromium HEAD freshness \| done \|") {
    throw "Fresh manifest did not produce a done upstream freshness row."
  }
  if ($FreshAudit -notmatch "\| Build \| Chromium pin refresh provenance \| pending \|") {
    throw "Fresh manifest without refresh provenance did not keep the pin refresh provenance row pending."
  }
  if ($FreshAudit -notmatch "pin matches observed upstream HEAD") {
    throw "Fresh manifest did not explain that the pin matches observed upstream HEAD."
  }

  $StaleAudit = Invoke-FreshnessAudit "stale" $StaleRevision
  if ($StaleAudit -notmatch "\| Build \| Observed upstream Chromium HEAD freshness \| pending \|") {
    throw "Stale manifest did not produce a pending upstream freshness row."
  }
  if ($StaleAudit -notmatch "observed_upstream_head=$StaleRevision") {
    throw "Stale manifest did not report the observed upstream head revision."
  }

  $RefreshProvenance = [pscustomobject]@{
    path = "benchmarks\reports\chromium-pin-refresh.json"
    exists = $true
    target_revision = $ExpectedRevision
    previous_revision = $StaleRevision
    selected_from_upstream_head = $true
    selected_at = "2026-05-18T00:00:00.0000000Z"
    source = "origin HEAD"
    generated_at = "2026-05-18T00:00:01.0000000Z"
    target_matches_expected = $true
  }
  $DriftAfterRefreshAudit = Invoke-FreshnessAudit "drift-after-refresh" $StaleRevision $RefreshProvenance
  if ($DriftAfterRefreshAudit -notmatch "\| Build \| Chromium pin refresh provenance \| done \|") {
    throw "Manifest with upstream-head refresh provenance did not produce a done pin refresh provenance row."
  }
  if ($DriftAfterRefreshAudit -notmatch "\| Build \| Observed upstream Chromium HEAD freshness \| pending \|") {
    throw "Manifest with upstream-head refresh provenance and post-refresh drift did not keep upstream freshness pending before official evidence exists."
  }
  if ($DriftAfterRefreshAudit -notmatch "before completed official stock/fork evidence exists") {
    throw "Manifest with upstream-head refresh provenance and post-refresh drift did not explain that official stock/fork evidence is still required."
  }

  $CompletedOfficialManifest = [pscustomobject]@{
    generated_at = "2026-05-18T00:00:02.0000000Z"
    dry_run = $false
    phase = "completed"
    chromium_revision = $ExpectedRevision
    fork_revision = $ExpectedForkRevision
  }
  $DriftAfterOfficialAudit = Invoke-FreshnessAudit "drift-after-official" $StaleRevision $RefreshProvenance $CompletedOfficialManifest
  if ($DriftAfterOfficialAudit -notmatch "\| Build \| Observed upstream Chromium HEAD freshness \| done \|") {
    throw "Manifest with post-refresh drift and completed official evidence did not produce a done upstream freshness row."
  }
  if ($DriftAfterOfficialAudit -notmatch "completed for refreshed pin") {
    throw "Manifest with post-refresh drift and completed official evidence did not report that official evidence was generated for the refreshed pin."
  }

  $UnobservedAfterRefreshAudit = Invoke-FreshnessAudit "unobserved-after-refresh" $ExpectedRevision $RefreshProvenance -ClearObservedHead
  if ($UnobservedAfterRefreshAudit -notmatch "\| Build \| Observed upstream Chromium HEAD freshness \| pending \|") {
    throw "Manifest with refresh provenance and unavailable upstream probe did not keep upstream freshness pending before official evidence exists."
  }
  if ($UnobservedAfterRefreshAudit -notmatch "current upstream HEAD probe was unavailable") {
    throw "Manifest with unavailable upstream probe did not explain that refresh provenance was used."
  }
  if ($UnobservedAfterRefreshAudit -notmatch "before completed official stock/fork evidence exists") {
    throw "Manifest with unavailable upstream probe did not explain that official stock/fork evidence is still required."
  }

  $UnobservedAfterOfficialAudit = Invoke-FreshnessAudit "unobserved-after-official" $ExpectedRevision $RefreshProvenance $CompletedOfficialManifest -ClearObservedHead
  if ($UnobservedAfterOfficialAudit -notmatch "\| Build \| Observed upstream Chromium HEAD freshness \| done \|") {
    throw "Manifest with unavailable upstream probe and completed official evidence did not produce a done upstream freshness row."
  }
  if ($UnobservedAfterOfficialAudit -notmatch "completed for refreshed pin") {
    throw "Manifest with unavailable upstream probe and completed official evidence did not report that official evidence was generated for the refreshed pin."
  }

  Write-Host "Artifact audit distinguishes fresh, stale, post-refresh-drift without official evidence, post-refresh-drift with official evidence, post-refresh-unobserved without official evidence, and post-refresh-unobserved with official evidence manifests."
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\documentation-completion-audit"
$GapOutput = Join-Path $TempDir "documentation-completion-gap.md"
$FinalOutput = Join-Path $TempDir "documentation-completion-final.md"
$FinalDocsRoot = Join-Path $TempDir "final-docs"
$FinalBaselineStabilityPath = Join-Path $Root "benchmarks\raw\baseline-content-shell-long-stability-doc-final-test.json"
$FinalForkStabilityPath = Join-Path $Root "benchmarks\raw\fork-viewer-default-long-stability-doc-final-test.json"
$MetricSource = Join-Path $Root "benchmarks\raw\smoke-installed-chrome-v18-renderer-resource-counters-instancing-webgl2.json"

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

function Write-TestFile {
  param(
    [string]$PathValue,
    [string]$Text
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  Set-Content -LiteralPath $PathValue -Value $Text -Encoding ASCII
  return $PathValue
}

function Set-JsonProperty {
  param(
    [object]$Target,
    [string]$Name,
    [AllowNull()][object]$Value
  )

  $Target | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Value
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PathValue -Encoding ASCII
}

function Write-FinalDocumentationFixture {
  $RequiredDocs = @(
    "README.md",
    "docs\architecture.md",
    "docs\build.md",
    "docs\benchmark_methodology.md",
    "docs\optimization_log.md",
    "docs\removed_subsystems.md",
    "docs\known_limitations.md",
    "docs\future_work.md",
    "docs\rebase_strategy.md",
    "docs\source_investigation.md",
    "docs\completion_audit.md",
    "docs\requirement_traceability.md",
    "docs\trusted_content_flags.md",
    "docs\stability_behavior.md",
    "docs\webgpu_scene_coverage.md"
  )

  foreach ($Doc in $RequiredDocs) {
    $null = Write-TestFile (Join-Path $FinalDocsRoot $Doc) "# Final Evidence`n`nMeasured final evidence recorded for $Doc."
  }
}

function New-FinalStabilityResult {
  param(
    [string]$Variant,
    [string]$Browser,
    [string]$BuildArgsHash,
    [bool]$ViewerMode,
    [bool]$ViewerBlockExternalNavigation,
    [bool]$ViewerTrustedContent,
    [AllowNull()][string]$ForkRevision
  )

  $PinRefresh = Get-Content (Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json") -Raw | ConvertFrom-Json
  $Result = Get-Content $MetricSource -Raw | ConvertFrom-Json
  $Result.measured_seconds = 3600
  $Result.warmup_seconds = 30
  Set-JsonProperty $Result "complexity" 2
  $Result.renderer_type = "webgl2"
  $Result.scene_name = "instancing"
  $Result.benchmark_variant = $Variant
  $Result.browser_is_from_checkout = $true
  $Result.chromium_revision = (Get-Content (Join-Path $Root ".chromium_revision") -Raw).Trim()
  $Result.build_args_hash = $BuildArgsHash
  Set-JsonProperty $Result "generated_at" ([DateTime]::Parse($PinRefresh.selected_at).AddMinutes(1).ToUniversalTime().ToString("o"))
  Set-JsonProperty $Result "fork_revision" $ForkRevision
  Set-JsonProperty $Result "browser_executable" $Browser
  Set-JsonProperty $Result "browser_flags" @("--disable-software-rasterizer")
  $Result.process_rss_delta_mb = 0
  $Result.renderer_memory_geometries_delta = 0
  $Result.renderer_memory_textures_delta = 0
  $Result.renderer_programs_delta = 0
  $Result.package_size_mb = 120
  Set-JsonProperty $Result "viewer_mode" $ViewerMode
  Set-JsonProperty $Result "viewer_block_external_navigation" $ViewerBlockExternalNavigation
  Set-JsonProperty $Result "viewer_trusted_content" $ViewerTrustedContent
  Set-JsonProperty $Result "viewer_aggressive_gpu" $false
  Set-JsonProperty $Result "viewer_relaxed_webgl_validation" $false
  Set-JsonProperty $Result "viewer_zero_copy" $false
  Set-JsonProperty $Result "viewer_in_process_gpu" $false
  Set-JsonProperty $Result "viewer_single_process" $false
  Set-JsonProperty $Result "viewer_force_angle_backend" $null
  Set-JsonProperty $Result "requested_angle_backend" $null
  Set-JsonProperty $Result "viewer_disable_unneeded_blink_features" $false
  Set-JsonProperty $Result "viewer_direct_gpu_presentation" $false
  Set-JsonProperty $Result "resource_warmup_enabled" $false
  Set-JsonProperty $Result "resource_warmup_precompile" $false
  Set-JsonProperty $Result "resource_warmup_prerender_frames" 0
  return $Result
}

if (Test-Path -LiteralPath $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$OldSkip = $env:THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST
$OldAllowOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
$OldOfficialManifest = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
$OldTrustedManifest = $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST
$OldFinalDocsDir = $env:THREE_BROWSER_TEST_FINAL_DOCUMENTATION_DIR

try {
  if (-not (Test-Path $MetricSource)) {
    throw "Required metric source missing: $MetricSource"
  }
  $AuditText = Get-Content -LiteralPath (Join-Path $Root "scripts\audit_artifacts.ps1") -Raw
  Assert-Matches $AuditText "function Add-DocumentationFinalizationRow" "documentation finalization audit function"
  Assert-Matches $AuditText "official comparison manifest missing" "official evidence gap detection"
  Assert-Matches $AuditText "trusted experiment matrix manifest missing" "trusted evidence gap detection"
  Assert-Matches $AuditText "one-hour stock/fork stability evidence incomplete" "stability evidence gap detection"
  Assert-Matches $AuditText "pending/blocker documentation language present" "pending documentation language detection"
  Assert-Matches $AuditText "THREE_BROWSER_TEST_FINAL_DOCUMENTATION_DIR" "test-only final documentation fixture override"

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

  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = Write-TestFile (Join-Path $TempDir "official-comparison-manifest.json") "{}"
  $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = Write-TestFile (Join-Path $TempDir "trusted-experiment-matrix-manifest.json") "{}"
  $env:THREE_BROWSER_TEST_FINAL_DOCUMENTATION_DIR = $FinalDocsRoot
  Write-FinalDocumentationFixture
  $ActualChromiumRevision = (Get-Content (Join-Path $Root ".chromium_revision") -Raw).Trim()
  $ExpectedForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ActualChromiumRevision -Root $Root
  $BaselineBuildArgsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root "src\out\ReleaseBaseline\args.gn")).Hash.ToLowerInvariant()
  $ForkBuildArgsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root "src\out\ReleaseViewerDefault\args.gn")).Hash.ToLowerInvariant()
  Write-Json $FinalBaselineStabilityPath (New-FinalStabilityResult `
      -Variant "baseline-content-shell-long-stability" `
      -Browser (Join-Path $Root "src\out\ReleaseBaseline\content_shell.exe") `
      -BuildArgsHash $BaselineBuildArgsHash `
      -ViewerMode $false `
      -ViewerBlockExternalNavigation $false `
      -ViewerTrustedContent $false `
      -ForkRevision $null)
  Write-Json $FinalForkStabilityPath (New-FinalStabilityResult `
      -Variant "fork-viewer-default-long-stability" `
      -Browser (Join-Path $Root "src\out\ReleaseViewerDefault\content_shell.exe") `
      -BuildArgsHash $ForkBuildArgsHash `
      -ViewerMode $true `
      -ViewerBlockExternalNavigation $true `
      -ViewerTrustedContent $true `
      -ForkRevision $ExpectedForkRevision)
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
  if ($null -eq $OldFinalDocsDir) {
    Remove-Item Env:\THREE_BROWSER_TEST_FINAL_DOCUMENTATION_DIR -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_FINAL_DOCUMENTATION_DIR = $OldFinalDocsDir
  }
  foreach ($PathValue in @($FinalBaselineStabilityPath, $FinalForkStabilityPath)) {
    if (Test-Path -LiteralPath $PathValue) {
      Remove-Item -LiteralPath $PathValue -Force
    }
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Documentation completion audit rejects missing evidence and accepts the completed final documentation evidence set."

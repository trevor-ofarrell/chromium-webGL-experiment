[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\suite-promotion-manifest-audit"
$TriagePath = Join-Path $TempDir "triage-analysis.json"
$TargetedPlanPath = Join-Path $TempDir "targeted-plan.json"
$PromotionPlanPath = Join-Path $TempDir "promotion-plan.json"
$InputListPath = Join-Path $TempDir "promotion-inputs.txt"
$PromotionAnalysisPath = Join-Path $TempDir "promotion-analysis.json"
$AuditOutput = Join-Path $TempDir "audit.md"
$ExpectedChromiumRevision = (Get-Content -LiteralPath (Join-Path $Root ".chromium_revision") -Raw).Trim()
$ExpectedForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ExpectedChromiumRevision -Root $Root

function Assert-Matches {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )

  if ($Text -notmatch $Pattern) {
    throw "Missing $Description. Pattern: $Pattern Text: $Text"
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

function New-PromotionManifest {
  param(
    [object[]]$PromotionProfiles = @(),
    [object[]]$CacheAttributionConfirmations = @(),
    [object[]]$Steps = @(),
    [int]$GeneratedInputCount = 0
  )

  return [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $true
    phase = "planned"
    triage_analysis_json = $TriagePath
    targeted_plan_manifest = $TargetedPlanPath
    promotion_plan_manifest = $PromotionPlanPath
    chromium_revision = $ExpectedChromiumRevision
    fork_revision = $ExpectedForkRevision
    options = [pscustomobject]@{
      duration = 60
      warmup = 10
      complexity = 2
      precompile = $false
      prerender_frames = 0
      settle_gpu_after_warmup = $false
      label_suffix = ""
      disable_webgpu_timing = $true
      run_comparable_baselines = $false
      max_profiles_per_renderer = 3
      fresh_profile_confirmation_label_suffix = "-fresh-profile-confirmation"
    }
    required_scenes = @(
      "many-draw-calls",
      "instancing",
      "shader-heavy",
      "texture-streaming",
      "postprocessing",
      "large-static",
      "gltf-loader-stress"
    )
    required_candidate_renderers = @("webgl2", "webgpu")
    promotion_profiles = @($PromotionProfiles)
    cache_attribution_confirmations = @($CacheAttributionConfirmations)
    generated_input_list = $InputListPath
    generated_input_count = $GeneratedInputCount
    analysis = [pscustomobject]@{
      output = ".\benchmarks\reports\targeted-suite-promotion-analysis.md"
      json = ".\benchmarks\reports\targeted-suite-promotion-analysis.json"
      min_measured_seconds = 30
      min_avg_fps_delta_pct = 0.5
      min_scenes = 7
      scene_regression_pct = 1
      dropped_frames_regression = 0
      cpu_frame_regression_ms = 0.5
      render_submission_regression_ms = 0.5
      pipeline_create_regression_ms = 1.0
      require_frame_times = $true
      require_checkout = $true
      require_package_size = $true
      expected_input_file_digest = ""
      expected_chromium_revision = $ExpectedChromiumRevision
      expected_fork_revision = $ExpectedForkRevision
    }
    steps = @($Steps)
  }
}

$OldAllowOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
$OldPromotionManifest = $env:THREE_BROWSER_TEST_SUITE_PROMOTION_PLAN_MANIFEST

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  Write-Json $TriagePath ([pscustomobject]@{ families = @() })
  Write-Json $TargetedPlanPath ([pscustomobject]@{ phase = "planned" })
  Set-Content -LiteralPath $InputListPath -Value @() -Encoding ASCII

  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_SUITE_PROMOTION_PLAN_MANIFEST = $PromotionPlanPath

  Write-Json $PromotionPlanPath (New-PromotionManifest)
  $NoPromotionAudit = Invoke-Audit
  Assert-Matches $NoPromotionAudit "Official performance \| Targeted suite-promotion plan manifest \| done" "done no-promotion audit row"
  Assert-Matches $NoPromotionAudit "no promotable triage profiles" "no-promotion evidence wording"

  $StaleRevisionManifest = New-PromotionManifest
  $StaleRevisionManifest.chromium_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  $StaleRevisionManifest.fork_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb+viewerpatch-stale"
  $StaleRevisionManifest.analysis.expected_chromium_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  $StaleRevisionManifest.analysis.expected_fork_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb+viewerpatch-stale"
  Write-Json $PromotionPlanPath $StaleRevisionManifest
  $StaleRevisionAudit = Invoke-Audit
  Assert-Matches $StaleRevisionAudit "Official performance \| Targeted suite-promotion plan manifest \| pending" "pending suite-promotion audit row for stale revisions"
  Assert-Matches $StaleRevisionAudit "chromium_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb expected=$ExpectedChromiumRevision" "suite-promotion current Chromium revision rejection"
  Assert-Matches $StaleRevisionAudit ([regex]::Escape("fork_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb+viewerpatch-stale expected=$ExpectedForkRevision")) "suite-promotion current fork revision rejection"

  $RawInputOne = Join-Path $TempDir "promotion-baseline-result.json"
  $RawInputTwo = Join-Path $TempDir "promotion-fork-result.json"
  Write-Json $RawInputOne ([pscustomobject]@{})
  Write-Json $RawInputTwo ([pscustomobject]@{})
  Set-Content -LiteralPath $InputListPath -Value @($RawInputOne, $RawInputTwo) -Encoding ASCII
  & node (Join-Path $Root "scripts\analyze_candidates.mjs") --fileList $InputListPath --json $PromotionAnalysisPath --quiet
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate suite-promotion analysis digest fixture."
  }
  $Digest = [string]((Get-Content -LiteralPath $PromotionAnalysisPath -Raw | ConvertFrom-Json).input_file_digest)
  $RequiredScenes = @(
    "many-draw-calls",
    "instancing",
    "shader-heavy",
    "texture-streaming",
    "postprocessing",
    "large-static",
    "gltf-loader-stress"
  )
  $CompletedProfile = [pscustomobject]@{
    renderer = "webgl2"
    status = "candidate"
    candidate_family = "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation"
    base_experiment_label = "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation"
    triage_scenes = @("many-draw-calls")
  }
  $CompletedAnalysisCommand = @(
    "node",
    ".\scripts\analyze_candidates.mjs",
    "--fileList",
    $InputListPath,
    "--json",
    $PromotionAnalysisPath,
    "--minMeasuredSeconds",
    "30",
    "--minScenes",
    "7",
    "--minAvgFpsDeltaPct",
    "0.5",
    "--sceneRegressionPct",
    "1",
    "--droppedFramesRegression",
    "0",
    "--cpuFrameRegressionMs",
    "0.5",
    "--renderSubmissionRegressionMs",
    "0.5",
    "--pipelineCreateRegressionMs",
    "1.0",
    "--requireFrameTimes",
    "--requireCheckout",
    "--requirePackageSize",
    "--expectedChromiumRevision",
    $ExpectedChromiumRevision,
    "--expectedForkRevision",
    $ExpectedForkRevision
  )
  foreach ($Scene in $RequiredScenes) {
    $CompletedAnalysisCommand += @("--requiredScene", $Scene)
  }
  $CompletedAnalysisCommand += @("--requireCandidateRenderer", "webgl2")
  $CompletedSteps = @(
    [pscustomobject]@{
      name = "promotion webgl2 full-suite candidate matrix"
      command_line = "scripts\run_trusted_experiment_matrix.ps1 -Renderer webgl2"
    },
    [pscustomobject]@{
      name = "promotion full-suite candidate speed analysis"
      command_line = $CompletedAnalysisCommand -join " "
    }
  )
  $CompletedManifest = New-PromotionManifest `
    -PromotionProfiles @($CompletedProfile) `
    -Steps $CompletedSteps `
    -GeneratedInputCount 2
  $CompletedManifest.dry_run = $false
  $CompletedManifest.phase = "completed"
  $CompletedManifest.required_candidate_renderers = @("webgl2")
  $CompletedManifest.analysis.json = $PromotionAnalysisPath
  $CompletedManifest.analysis.expected_input_file_digest = $Digest
  Write-Json $PromotionPlanPath $CompletedManifest
  $CompletedAudit = Invoke-Audit
  Assert-Matches $CompletedAudit "Official performance \| Targeted suite-promotion plan manifest \| done" "done completed promotion audit row"
  Assert-Matches $CompletedAudit "completed-run digest plus exact input-file metadata checks" "completed suite-promotion digest and input metadata wording"

  $BrokenDigestManifest = New-PromotionManifest `
    -PromotionProfiles @($CompletedProfile) `
    -Steps $CompletedSteps `
    -GeneratedInputCount 2
  $BrokenDigestManifest.dry_run = $false
  $BrokenDigestManifest.phase = "completed"
  $BrokenDigestManifest.required_candidate_renderers = @("webgl2")
  $BrokenDigestManifest.analysis.json = $PromotionAnalysisPath
  $BrokenDigestManifest.analysis.expected_input_file_digest = ("0" * 64)
  Write-Json $PromotionPlanPath $BrokenDigestManifest
  $BrokenDigestAudit = Invoke-Audit
  Assert-Matches $BrokenDigestAudit "Official performance \| Targeted suite-promotion plan manifest \| pending" "pending promotion audit row for digest mismatch"
  Assert-Matches $BrokenDigestAudit "expected_input_file_digest does not match generated input list" "suite-promotion digest mismatch rejection"

  $BrokenInputMetadataAnalysisPath = Join-Path $TempDir "promotion-analysis-bad-input-files.json"
  $BrokenInputMetadataAnalysis = Get-Content -LiteralPath $PromotionAnalysisPath -Raw | ConvertFrom-Json
  $BrokenInputMetadataAnalysis.input_files[0].sha256 = ("f" * 64)
  Write-Json $BrokenInputMetadataAnalysisPath $BrokenInputMetadataAnalysis
  $BrokenInputMetadataManifest = New-PromotionManifest `
    -PromotionProfiles @($CompletedProfile) `
    -Steps $CompletedSteps `
    -GeneratedInputCount 2
  $BrokenInputMetadataManifest.dry_run = $false
  $BrokenInputMetadataManifest.phase = "completed"
  $BrokenInputMetadataManifest.required_candidate_renderers = @("webgl2")
  $BrokenInputMetadataManifest.analysis.json = $BrokenInputMetadataAnalysisPath
  $BrokenInputMetadataManifest.analysis.expected_input_file_digest = $Digest
  Write-Json $PromotionPlanPath $BrokenInputMetadataManifest
  $BrokenInputMetadataAudit = Invoke-Audit
  Assert-Matches $BrokenInputMetadataAudit "Official performance \| Targeted suite-promotion plan manifest \| pending" "pending promotion audit row for stale input_files metadata"
  Assert-Matches $BrokenInputMetadataAudit "analysis JSON input_files path/hash/size metadata does not match generated input list" "suite-promotion input_files metadata mismatch rejection"

  $BrokenSettleManifest = New-PromotionManifest
  $BrokenSettleManifest.options.label_suffix = "-warmup-precompile-prerender2-settlegpu"
  $BrokenSettleManifest.options.settle_gpu_after_warmup = $false
  Write-Json $PromotionPlanPath $BrokenSettleManifest
  $BrokenSettleAudit = Invoke-Audit
  Assert-Matches $BrokenSettleAudit "Official performance \| Targeted suite-promotion plan manifest \| pending" "pending GPU-settle mismatch audit row"
  Assert-Matches $BrokenSettleAudit "settlegpu label suffix but settle_gpu_after_warmup is not true" "GPU-settle label mismatch rejection"

  Write-Json $TargetedPlanPath ([pscustomobject]@{
      options = [pscustomobject]@{
        resource_warmup_label_suffix = "-warmup-precompile-prerender2-settlegpu"
        webgl2_resource_warmup_label_suffix = "-warmup-precompile-prerender2-settlegpu"
        webgpu_resource_warmup_label_suffix = "-warmup-precompile-prerender2-settlegpu-pipelinequiet2"
        webgpu_pipeline_quiet_frames = 2
      }
    })
  Set-Content -LiteralPath $InputListPath -Value @() -Encoding ASCII
  $StaleWebGpuSuffixManifest = New-PromotionManifest
  $StaleWebGpuSuffixManifest.required_candidate_renderers = @("webgpu")
  $StaleWebGpuSuffixManifest.options.label_suffix = "-warmup-precompile-prerender2-settlegpu"
  Write-Json $PromotionPlanPath $StaleWebGpuSuffixManifest
  $StaleWebGpuSuffixAudit = Invoke-Audit
  Assert-Matches $StaleWebGpuSuffixAudit "Official performance \| Targeted suite-promotion plan manifest \| pending" "pending stale WebGPU suffix audit row"
  Assert-Matches $StaleWebGpuSuffixAudit "webgpu_label_suffix=.*expected targeted webgpu suffix -warmup-precompile-prerender2-settlegpu-pipelinequiet2" "stale WebGPU suffix rejection"
  Assert-Matches $StaleWebGpuSuffixAudit "webgpu_pipeline_quiet_frames=0 expected targeted value 2" "missing WebGPU pipeline-quiet frame count rejection"

  $AlignedWebGpuSuffixManifest = New-PromotionManifest
  $AlignedWebGpuSuffixManifest.required_candidate_renderers = @("webgpu")
  $AlignedWebGpuSuffixManifest.options.label_suffix = "-warmup-precompile-prerender2-settlegpu"
  $AlignedWebGpuSuffixManifest.options.settle_gpu_after_warmup = $true
  $AlignedWebGpuSuffixManifest.options | Add-Member -NotePropertyName webgpu_label_suffix -NotePropertyValue "-warmup-precompile-prerender2-settlegpu-pipelinequiet2" -Force
  $AlignedWebGpuSuffixManifest.options | Add-Member -NotePropertyName webgpu_pipeline_quiet_frames -NotePropertyValue 2 -Force
  Write-Json $PromotionPlanPath $AlignedWebGpuSuffixManifest
  $AlignedWebGpuSuffixAudit = Invoke-Audit
  Assert-Matches $AlignedWebGpuSuffixAudit "Official performance \| Targeted suite-promotion plan manifest \| done" "done aligned WebGPU suffix audit row"

  Write-Json $TargetedPlanPath ([pscustomobject]@{ phase = "planned" })

  $BrokenProfile = [pscustomobject]@{
    renderer = "webgl2"
    status = "candidate"
    candidate_family = "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation"
    base_experiment_label = "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation"
    baseline_family = "baseline-content-shell"
    triage_scenes = @("many-draw-calls")
    avg_fps_delta_pct = 2
    min_fps_delta_pct = 2
    p99_frame_ms_delta = -1
  }
  Write-Json $PromotionPlanPath (New-PromotionManifest -PromotionProfiles @($BrokenProfile) -GeneratedInputCount 0)
  $BrokenAudit = Invoke-Audit
  Assert-Matches $BrokenAudit "Official performance \| Targeted suite-promotion plan manifest \| pending" "pending broken-promotion audit row"
  Assert-Matches $BrokenAudit "promotion or confirmation profiles exist but no analyzer inputs were generated" "missing promotion input rejection"
  Assert-Matches $BrokenAudit "promotion analysis step missing" "missing promotion analysis step rejection"

  $Confirmation = [pscustomobject]@{
    renderer = "webgpu"
    status = "fresh-profile-confirmation"
    source_status = "cache-attribution"
    source_candidate_family = "fork-viewer-exp-webgpu-warm-cache"
    candidate_family = "fork-viewer-exp-webgpu-warm-cache-fresh-profile-confirmation"
    base_experiment_label = "fork-viewer-exp-webgpu-warm-cache"
    baseline_family = "baseline-content-shell-webgpu-warm-cache"
    triage_scenes = @("shader-heavy")
    avg_fps_delta_pct = 4
    min_fps_delta_pct = 2
    p99_frame_ms_delta = -1
    source_profile_cache_mode = "explicit-reuse"
    source_profile_cache_key = "webgpu-warm-cache-test"
  }
  $ConfirmationInputs = @()
  foreach ($Scene in @(
      "many-draw-calls",
      "instancing",
      "shader-heavy",
      "texture-streaming",
      "postprocessing",
      "large-static",
      "gltf-loader-stress"
    )) {
    $ConfirmationInputs += ".\benchmarks\raw\baseline-content-shell-suite-promotion-fresh-profile-webgpu-fresh-profile-confirmation-$Scene-webgpu.json"
    $ConfirmationInputs += ".\benchmarks\raw\fork-viewer-exp-webgpu-warm-cache-fresh-profile-confirmation-$Scene-webgpu.json"
  }
  Set-Content -LiteralPath $InputListPath -Value $ConfirmationInputs -Encoding ASCII
  $ConfirmationAnalysisCommand = @(
    "node",
    ".\scripts\analyze_candidates.mjs",
    "--fileList",
    $InputListPath
  )
  foreach ($Scene in @(
      "many-draw-calls",
      "instancing",
      "shader-heavy",
      "texture-streaming",
      "postprocessing",
      "large-static",
      "gltf-loader-stress"
    )) {
    $ConfirmationAnalysisCommand += @("--requiredScene", $Scene)
  }
  $ConfirmationAnalysisCommand += @(
    "--minMeasuredSeconds",
    "30",
    "--minScenes",
    "7",
    "--minAvgFpsDeltaPct",
    "0.5",
    "--sceneRegressionPct",
    "1",
    "--droppedFramesRegression",
    "0",
    "--cpuFrameRegressionMs",
    "0.5",
    "--renderSubmissionRegressionMs",
    "0.5",
    "--pipelineCreateRegressionMs",
    "1.0",
    "--requireCandidateRenderer",
    "webgpu",
    "--requireFrameTimes",
    "--requireCheckout",
    "--requirePackageSize",
    "--expectedChromiumRevision",
    $ExpectedChromiumRevision,
    "--expectedForkRevision",
    $ExpectedForkRevision
  )
  $ConfirmationSteps = @(
    [pscustomobject]@{
      name = "fresh-profile confirmation webgpu comparable baseline suite"
      command_line = "powershell -File .\scripts\run_full_suite.ps1 -Renderer webgpu -Label baseline-content-shell-suite-promotion-fresh-profile-webgpu-fresh-profile-confirmation"
    },
    [pscustomobject]@{
      name = "fresh-profile confirmation webgpu full-suite candidate matrix"
      command_line = "powershell -File .\scripts\run_trusted_experiment_matrix.ps1 -Renderer webgpu -ExperimentLabelFilter fork-viewer-exp-webgpu-warm-cache -LabelSuffix -fresh-profile-confirmation"
    },
    [pscustomobject]@{
      name = "promotion full-suite candidate speed analysis"
      command_line = $ConfirmationAnalysisCommand -join " "
    }
  )
  $ConfirmationManifest = New-PromotionManifest `
    -CacheAttributionConfirmations @($Confirmation) `
    -Steps $ConfirmationSteps `
    -GeneratedInputCount $ConfirmationInputs.Count
  $ConfirmationManifest.required_candidate_renderers = @("webgpu")
  Write-Json $PromotionPlanPath $ConfirmationManifest
  $ConfirmationAudit = Invoke-Audit
  Assert-Matches $ConfirmationAudit "Official performance \| Targeted suite-promotion plan manifest \| done" "done cache-attribution confirmation audit row"
  Assert-Matches $ConfirmationAudit "cache-attribution triage profile" "cache-attribution confirmation wording"
  Assert-Matches $ConfirmationAudit "fresh-profile confirmation suites" "fresh-profile confirmation wording"

  $BrokenConfirmationSteps = @($ConfirmationSteps | ForEach-Object { $_.PSObject.Copy() })
  $BrokenConfirmationSteps[1].command_line = "$($BrokenConfirmationSteps[1].command_line) -ProfileCacheKey webgpu-warm-cache-test -PrimeProfileCache"
  $BrokenConfirmationManifest = New-PromotionManifest `
    -CacheAttributionConfirmations @($Confirmation) `
    -Steps $BrokenConfirmationSteps `
    -GeneratedInputCount $ConfirmationInputs.Count
  $BrokenConfirmationManifest.required_candidate_renderers = @("webgpu")
  Write-Json $PromotionPlanPath $BrokenConfirmationManifest
  $BrokenConfirmationAudit = Invoke-Audit
  Assert-Matches $BrokenConfirmationAudit "Official performance \| Targeted suite-promotion plan manifest \| pending" "pending broken confirmation audit row"
  Assert-Matches $BrokenConfirmationAudit "carries profile-cache flags" "profile-cache flag rejection"

  $BrokenAnalysisSteps = @($ConfirmationSteps | ForEach-Object { $_.PSObject.Copy() })
  $BrokenAnalysisSteps[2].command_line = $BrokenAnalysisSteps[2].command_line -replace "--expectedForkRevision\s+$([regex]::Escape($ExpectedForkRevision))", ""
  $BrokenAnalysisManifest = New-PromotionManifest `
    -CacheAttributionConfirmations @($Confirmation) `
    -Steps $BrokenAnalysisSteps `
    -GeneratedInputCount $ConfirmationInputs.Count
  $BrokenAnalysisManifest.required_candidate_renderers = @("webgpu")
  Write-Json $PromotionPlanPath $BrokenAnalysisManifest
  $BrokenAnalysisAudit = Invoke-Audit
  Assert-Matches $BrokenAnalysisAudit "Official performance \| Targeted suite-promotion plan manifest \| pending" "pending broken analysis command audit row"
  Assert-Matches $BrokenAnalysisAudit "analysis command missing expectedForkRevision" "expected fork revision command rejection"

  Write-Host "Suite-promotion manifest audit accepts no-candidate handoffs, audits completed-run input digests plus exact input file metadata, handles cache-attribution confirmations, and rejects incomplete promotion evidence."
} finally {
  if ($null -eq $OldAllowOverrides) {
    Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowOverrides
  }
  if ($null -eq $OldPromotionManifest) {
    Remove-Item Env:\THREE_BROWSER_TEST_SUITE_PROMOTION_PLAN_MANIFEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_SUITE_PROMOTION_PLAN_MANIFEST = $OldPromotionManifest
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

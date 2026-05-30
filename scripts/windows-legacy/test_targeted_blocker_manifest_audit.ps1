[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\targeted-blocker-manifest-audit"
$PlanPath = Join-Path $TempDir "targeted-plan.json"
$CandidateAnalysisPath = Join-Path $TempDir "candidate-analysis.json"
$OfficialManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$TrustedManifestPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.json"
$SeedInputListPath = Join-Path $TempDir "seed-current-candidate-analysis-inputs.txt"
$InputListPath = Join-Path $TempDir "post-run-inputs.txt"
$TriageAnalysisPath = Join-Path $TempDir "post-run-triage-analysis.json"
$PostRunAnalysisPath = Join-Path $TempDir "post-run-candidate-analysis.json"
$AuditOutput = Join-Path $TempDir "audit.md"
$ExpectedChromiumRevision = (Get-Content -LiteralPath (Join-Path $Root ".chromium_revision") -Raw).Trim()
$ExpectedForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ExpectedChromiumRevision -Root $Root
$RequiredBenchmarkScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)
$SeedRawInputOne = Join-Path $TempDir "official-baseline-result.json"
$SeedRawInputTwo = Join-Path $TempDir "official-fork-result.json"

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

function Write-SeedOfficialManifest {
  param(
    [string]$ForkRevision = $ExpectedForkRevision
  )

  Write-Json $SeedRawInputOne ([pscustomobject]@{})
  Write-Json $SeedRawInputTwo ([pscustomobject]@{})
  Write-Json $OfficialManifestPath ([pscustomobject]@{
      generated_at = (Get-Date).ToUniversalTime().ToString("o")
      dry_run = $false
      phase = "completed"
      chromium_revision = $ExpectedChromiumRevision
      fork_revision = $ForkRevision
      options = [pscustomobject]@{
        duration = 30
        warmup = 5
        complexity = 2
      }
      result_files = [pscustomobject]@{
        baseline_webgl2 = @($SeedRawInputOne)
        fork_default_webgl2 = @($SeedRawInputTwo)
        aggressive_webgl2 = @()
        baseline_webgpu = @()
        fork_default_webgpu = @()
        aggressive_webgpu = @()
      }
    })
  Write-Json $TrustedManifestPath ([pscustomobject]@{
      generated_at = (Get-Date).ToUniversalTime().ToString("o")
      dry_run = $true
      phase = "planned"
      chromium_revision = $ExpectedChromiumRevision
      fork_revision = $ForkRevision
      options = [pscustomobject]@{
        duration = 30
        warmup = 5
        complexity = 2
      }
      result_files = [pscustomobject]@{
        all = @()
      }
    })
}

function Write-SeedCandidateAnalysis {
  param(
    [string]$ChromiumRevision = $ExpectedChromiumRevision,
    [string]$ForkRevision = $ExpectedForkRevision
  )

  Set-Content -LiteralPath $SeedInputListPath -Encoding ASCII -Value @($SeedRawInputOne, $SeedRawInputTwo)
  $Args = @(
    (Join-Path $Root "scripts\analyze_candidates.mjs"),
    "--fileList", $SeedInputListPath,
    "--json", $CandidateAnalysisPath,
    "--minMeasuredSeconds", "30",
    "--minScenes", "7",
    "--minAvgFpsDeltaPct", "0.5",
    "--sceneRegressionPct", "1",
    "--droppedFramesRegression", "0",
    "--cpuFrameRegressionMs", "0.5",
    "--renderSubmissionRegressionMs", "0.5",
    "--pipelineCreateRegressionMs", "1.0",
    "--requireFrameTimes",
    "--requireCheckout",
    "--requirePackageSize",
    "--expectedChromiumRevision", $ChromiumRevision,
    "--expectedForkRevision", $ForkRevision,
    "--quiet"
  )
  foreach ($Scene in $RequiredBenchmarkScenes) {
    $Args += @("--requiredScene", $Scene)
  }
  foreach ($Renderer in @("webgl2", "webgpu")) {
    $Args += @("--requireCandidateRenderer", $Renderer)
  }

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $null = & node @Args 2>&1
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if (-not (Test-Path -LiteralPath $CandidateAnalysisPath -PathType Leaf)) {
    throw "Failed to generate seed candidate analysis fixture."
  }
}

function Invoke-Audit {
  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -ManifestAuditOnly -Output $AuditOutput *>&1
  return Get-Content -LiteralPath $AuditOutput -Raw
}

function New-TargetedPlan {
  param(
    [bool]$RequireCheckout = $true,
    [bool]$CommandRequiresCheckout = $true,
    [bool]$RequirePackageSize = $true,
    [bool]$CommandRequiresPackageSize = $true,
    [bool]$IncludeTargetedTrace = $true,
    [bool]$RejectWebGpuCpuFallback = $true
  )

  $Scenes = @($RequiredBenchmarkScenes)
  $CheckoutFlag = if ($CommandRequiresCheckout) { " --requireCheckout" } else { "" }
  $PackageSizeFlag = if ($CommandRequiresPackageSize) { " --requirePackageSize" } else { "" }
  $RequiredSceneArgs = ($Scenes | ForEach-Object { "--requiredScene $_" }) -join " "
  $TraceScene = "large-static"
  $TraceDuration = 10
  $TraceWarmup = 2
  $TraceStartDelayMs = 2000
  $TraceFiles = @()
  $TraceSteps = @()
  if ($IncludeTargetedTrace) {
    $RejectTraceArg = if ($RejectWebGpuCpuFallback) { " --rejectWebGpuCpuFallback" } else { "" }
    $ForkRejectCaptureArg = if ($RejectWebGpuCpuFallback) { " --viewerRejectWebgpuCpuTextureFallback" } else { "" }
    $BaselineRejectMetadata = if ($RejectWebGpuCpuFallback) { " --expectedFlagMetadata viewer_reject_webgpu_cpu_texture_fallback=false" } else { "" }
    $ForkRejectMetadata = if ($RejectWebGpuCpuFallback) { " --expectedFlagMetadata viewer_reject_webgpu_cpu_texture_fallback=true" } else { "" }
    $ForkRejectRequiredFlag = if ($RejectWebGpuCpuFallback) { " --requiredBrowserFlag --viewer-reject-webgpu-cpu-texture-fallback" } else { "" }
    $BaselineTrace = "benchmarks\traces\baseline-content-shell-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace.json"
    $ForkTrace = "benchmarks\traces\fork-viewer-default-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace.json"
    $TraceFiles = @(
      [pscustomobject]@{
        label = "baseline-content-shell-targeted-blocker-webgpu-trace"
        scene = $TraceScene
        renderer = "webgpu"
        trace = $BaselineTrace
        trace_result = "benchmarks\traces\baseline-content-shell-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace.result.json"
        trace_summary = "benchmarks\reports\baseline-content-shell-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace-summary.md"
      },
      [pscustomobject]@{
        label = "fork-viewer-default-targeted-blocker-webgpu-trace"
        scene = $TraceScene
        renderer = "webgpu"
        trace = $ForkTrace
        trace_result = "benchmarks\traces\fork-viewer-default-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace.result.json"
        trace_summary = "benchmarks\reports\fork-viewer-default-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace-summary.md"
      }
    )
    $TraceSteps = @(
      [pscustomobject]@{
        name = "targeted WebGPU baseline trace ($TraceScene)"
        command_line = "node scripts\run_trace_capture.mjs --browser baseline.exe --scene $TraceScene --renderer webgpu --duration $TraceDuration --warmup $TraceWarmup --startDelayMs $TraceStartDelayMs --output $BaselineTrace"
      },
      [pscustomobject]@{
        name = "validate targeted WebGPU baseline trace file ($TraceScene)"
        command_line = "node scripts\validate_trace_file.mjs --minEvents 1$RejectTraceArg $BaselineTrace"
      },
      [pscustomobject]@{
        name = "validate targeted WebGPU baseline trace sidecar ($TraceScene)"
        command_line = "node scripts\validate_trace_result.mjs --expectedScene $TraceScene --expectedRenderer webgpu --expectedStartDelayMs $TraceStartDelayMs --rejectSoftwareRendering --expectedFlagMetadata viewer_trace_webgpu_queue=false$BaselineRejectMetadata benchmarks\traces\baseline-content-shell-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace.result.json"
      },
      [pscustomobject]@{
        name = "summarize targeted WebGPU baseline trace ($TraceScene)"
        command_line = "node scripts\summarize_trace.mjs $BaselineTrace --output benchmarks\reports\baseline-content-shell-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace-summary.md$RejectTraceArg"
      },
      [pscustomobject]@{
        name = "targeted WebGPU fork trace ($TraceScene)"
        command_line = "node scripts\run_trace_capture.mjs --browser fork.exe --scene $TraceScene --renderer webgpu --duration $TraceDuration --warmup $TraceWarmup --startDelayMs $TraceStartDelayMs --output $ForkTrace --viewerMode --viewerTrustedContent --viewerTraceWebgpuQueue$ForkRejectCaptureArg"
      },
      [pscustomobject]@{
        name = "validate targeted WebGPU fork trace file ($TraceScene)"
        command_line = "node scripts\validate_trace_file.mjs --minEvents 1$RejectTraceArg $ForkTrace"
      },
      [pscustomobject]@{
        name = "validate targeted WebGPU fork trace sidecar ($TraceScene)"
        command_line = "node scripts\validate_trace_result.mjs --expectedScene $TraceScene --expectedRenderer webgpu --expectedStartDelayMs $TraceStartDelayMs --rejectSoftwareRendering --expectedFlagMetadata viewer_trace_webgpu_queue=true$ForkRejectMetadata --requiredBrowserFlag --viewer-trace-webgpu-queue$ForkRejectRequiredFlag benchmarks\traces\fork-viewer-default-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace.result.json"
      },
      [pscustomobject]@{
        name = "summarize targeted WebGPU fork trace ($TraceScene)"
        command_line = "node scripts\summarize_trace.mjs $ForkTrace --output benchmarks\reports\fork-viewer-default-targeted-blocker-webgpu-trace-$TraceScene-webgpu-targeted-trace-summary.md$RejectTraceArg"
      }
    )
  }
  return [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $true
    phase = "planned"
    candidate_analysis_json = $CandidateAnalysisPath
    chromium_revision = $ExpectedChromiumRevision
    fork_revision = $ExpectedForkRevision
    post_run_analysis = [pscustomobject]@{
      enabled = $true
      input_list = $InputListPath
      generated_input_count = 2
      triage_output = ".\benchmarks\reports\targeted-blocker-triage-analysis.md"
      triage_json = ".\benchmarks\reports\targeted-blocker-triage-analysis.json"
      triage_min_scenes = 1
      output = ".\benchmarks\reports\targeted-blocker-candidate-analysis.md"
      json = ".\benchmarks\reports\targeted-blocker-candidate-analysis.json"
      expected_input_file_digest = ""
      min_measured_seconds = 30
      min_avg_fps_delta_pct = 0.5
      min_scenes = 7
      required_scenes = @($Scenes)
      scene_regression_pct = 1
      dropped_frames_regression = 0
      cpu_frame_regression_ms = 0.5
      render_submission_regression_ms = 0.5
      pipeline_create_regression_ms = 1.0
      require_frame_times = $true
      require_checkout = $RequireCheckout
      require_package_size = $RequirePackageSize
      required_candidate_renderers = @("webgl2", "webgpu")
      build_args_compatibility_policy = "same-build-args-hash"
      environment_compatibility_policy = "same-platform-driver-gpu-device"
      complexity_compatibility_policy = "same-explicit-benchmark-complexity"
      webgpu_bundle_mode_compatibility_policy = "same-webgpu-bundle-mode"
      webgpu_pipeline_instrumentation_compatibility_policy = "same-webgpu-pipeline-instrumentation-mode"
      baseline_selection_policy = "fastest-compatible-baseline"
      expected_chromium_revision = $ExpectedChromiumRevision
      expected_fork_revision = $ExpectedForkRevision
    }
    planned_scenes = [pscustomobject]@{
      webgl2 = @("many-draw-calls")
      webgpu = @($TraceScene)
    }
    targeted_trace = [pscustomobject]@{
      enabled = $IncludeTargetedTrace
      renderer = "webgpu"
      duration = $TraceDuration
      warmup = $TraceWarmup
      start_delay_ms = $TraceStartDelayMs
      queue_instrumentation = $false
      reject_webgpu_cpu_fallback = $RejectWebGpuCpuFallback
      viewer_trace_webgpu_queue = $IncludeTargetedTrace
      disable_webgpu_timing = $true
      trace_files = @($TraceFiles)
    }
    suite_promotion = [pscustomobject]@{
      enabled = $true
      plan_manifest = ".\benchmarks\reports\targeted-suite-promotion-plan.json"
    }
    steps = @($TraceSteps) + @(
      [pscustomobject]@{
        name = "post-run blocker triage analysis"
        command_line = "node scripts\analyze_candidates.mjs --fileList $InputListPath --minScenes 1 --droppedFramesRegression 0 --cpuFrameRegressionMs 0.5 --renderSubmissionRegressionMs 0.5 --pipelineCreateRegressionMs 1.0 --requireFrameTimes$CheckoutFlag$PackageSizeFlag --expectedChromiumRevision $ExpectedChromiumRevision --expectedForkRevision $ExpectedForkRevision"
      },
      [pscustomobject]@{
        name = "post-run candidate speed analysis"
        command_line = "node scripts\analyze_candidates.mjs --fileList $InputListPath --minScenes 7 --droppedFramesRegression 0 --cpuFrameRegressionMs 0.5 --renderSubmissionRegressionMs 0.5 --pipelineCreateRegressionMs 1.0 --requireFrameTimes$CheckoutFlag$PackageSizeFlag --expectedChromiumRevision $ExpectedChromiumRevision --expectedForkRevision $ExpectedForkRevision $RequiredSceneArgs --requireCandidateRenderer webgl2 --requireCandidateRenderer webgpu"
      }
    )
  }
}

$OldAllowOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
$OldTargetedPlan = $env:THREE_BROWSER_TEST_TARGETED_BLOCKER_PLAN_MANIFEST
$OldOfficialManifest = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
$OldTrustedManifest = $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  Write-SeedOfficialManifest
  Write-SeedCandidateAnalysis
  Set-Content -LiteralPath $InputListPath -Encoding ASCII -Value @(
    "benchmarks\raw\baseline-content-shell-targeted-blocker-many-draw-calls-webgl2.json",
    "benchmarks\raw\fork-viewer-exp-default-many-draw-calls-webgl2.json"
  )

  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_TARGETED_BLOCKER_PLAN_MANIFEST = $PlanPath
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OfficialManifestPath
  $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $TrustedManifestPath

  Write-Json $PlanPath (New-TargetedPlan)
  $GoodAudit = Invoke-Audit
  Assert-Matches $GoodAudit "Official performance \| Targeted blocker experiment plan manifest \| done" "done targeted blocker audit row"
  Assert-Matches $GoodAudit "source candidate-analysis policy and input digest checks" "source candidate-analysis policy and digest wording"
  Assert-Matches $GoodAudit "current official/trusted seed digest checks when current completed manifests are available" "current seed candidate-analysis digest wording"
  Assert-Matches $GoodAudit "checkout-built browser gating" "checkout-built browser evidence wording"
  Assert-Matches $GoodAudit "targeted WebGPU trace capture with CPU-fallback and software-renderer rejection" "targeted trace evidence wording"

  Write-SeedOfficialManifest -ForkRevision "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb+viewerpatch-stale"
  Write-Json $PlanPath (New-TargetedPlan)
  $StaleOfficialAudit = Invoke-Audit
  Assert-Matches $StaleOfficialAudit "Official performance \| Targeted blocker experiment plan manifest \| done" "done targeted blocker audit row with stale official evidence"
  Assert-Matches $StaleOfficialAudit "source candidate-analysis policy and input digest checks" "source policy and digest still gate targeted blocker plan when official evidence is stale"
  Write-SeedOfficialManifest

  $StaleRevisionPlan = New-TargetedPlan
  $StaleRevisionPlan.chromium_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  $StaleRevisionPlan.fork_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb+viewerpatch-stale"
  $StaleRevisionPlan.post_run_analysis.expected_chromium_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  $StaleRevisionPlan.post_run_analysis.expected_fork_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb+viewerpatch-stale"
  Write-Json $PlanPath $StaleRevisionPlan
  $StaleRevisionAudit = Invoke-Audit
  Assert-Matches $StaleRevisionAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for stale revisions"
  Assert-Matches $StaleRevisionAudit "chromium_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb expected=$ExpectedChromiumRevision" "targeted blocker current Chromium revision rejection"
  Assert-Matches $StaleRevisionAudit ([regex]::Escape("fork_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb+viewerpatch-stale expected=$ExpectedForkRevision")) "targeted blocker current fork revision rejection"

  Write-SeedCandidateAnalysis -ForkRevision "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb+viewerpatch-stale"
  Write-Json $PlanPath (New-TargetedPlan)
  $StaleCandidateAnalysisAudit = Invoke-Audit
  Assert-Matches $StaleCandidateAnalysisAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for stale seed candidate analysis"
  Assert-Matches $StaleCandidateAnalysisAudit "candidate_analysis_json expected_fork_revision=.*expected=$([regex]::Escape($ExpectedForkRevision))" "stale seed candidate-analysis fork revision rejection"
  Write-SeedCandidateAnalysis

  $BrokenSeedAnalysis = Get-Content -LiteralPath $CandidateAnalysisPath -Raw | ConvertFrom-Json
  $BrokenSeedAnalysis.input_file_digest = ("0" * 64)
  Write-Json $CandidateAnalysisPath $BrokenSeedAnalysis
  Write-Json $PlanPath (New-TargetedPlan)
  $BrokenSeedDigestAudit = Invoke-Audit
  Assert-Matches $BrokenSeedDigestAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for seed digest mismatch"
  Assert-Matches $BrokenSeedDigestAudit "candidate_analysis_json current official/trusted analysis analysis JSON input_file_digest does not match generated input list" "seed current candidate-analysis digest mismatch rejection"
  Write-SeedCandidateAnalysis

  $WeakPolicyAnalysis = Get-Content -LiteralPath $CandidateAnalysisPath -Raw | ConvertFrom-Json
  $WeakPolicyAnalysis.options.PSObject.Properties.Remove("webgpu_pipeline_quiet_success_policy")
  Write-Json $CandidateAnalysisPath $WeakPolicyAnalysis
  Write-Json $PlanPath (New-TargetedPlan)
  $WeakPolicyAudit = Invoke-Audit
  Assert-Matches $WeakPolicyAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for weak source analyzer policy"
  Assert-Matches $WeakPolicyAudit "candidate_analysis_json webgpu_pipeline_quiet_success_policy is not candidate-analysis-filters-unachieved-or-measured-pipeline-create-webgpu-pipeline-quiet-warmup" "missing source pipeline-quiet policy rejection"
  Write-SeedCandidateAnalysis

  $WeakGpuTimingPolicyAnalysis = Get-Content -LiteralPath $CandidateAnalysisPath -Raw | ConvertFrom-Json
  $WeakGpuTimingPolicyAnalysis.options.PSObject.Properties.Remove("gpu_timing_evidence_policy")
  Write-Json $CandidateAnalysisPath $WeakGpuTimingPolicyAnalysis
  Write-Json $PlanPath (New-TargetedPlan)
  $WeakGpuTimingPolicyAudit = Invoke-Audit
  Assert-Matches $WeakGpuTimingPolicyAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for weak GPU timing source analyzer policy"
  Assert-Matches $WeakGpuTimingPolicyAudit "candidate_analysis_json gpu_timing_evidence_policy is not candidate-analysis-requires-explicit-gpu-timing-mode" "missing source GPU timing evidence policy rejection"
  Write-SeedCandidateAnalysis

  $RawInputOne = Join-Path $TempDir "baseline-result.json"
  $RawInputTwo = Join-Path $TempDir "fork-result.json"
  Write-Json $RawInputOne ([pscustomobject]@{})
  Write-Json $RawInputTwo ([pscustomobject]@{})
  Set-Content -LiteralPath $InputListPath -Encoding ASCII -Value @($RawInputOne, $RawInputTwo)
  & node (Join-Path $Root "scripts\analyze_candidates.mjs") --fileList $InputListPath --json $TriageAnalysisPath --quiet
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate targeted blocker triage analysis digest fixture."
  }
  & node (Join-Path $Root "scripts\analyze_candidates.mjs") --fileList $InputListPath --json $PostRunAnalysisPath --quiet
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate targeted blocker candidate analysis digest fixture."
  }
  $Digest = [string]((Get-Content -LiteralPath $PostRunAnalysisPath -Raw | ConvertFrom-Json).input_file_digest)
  $CompletedPlan = New-TargetedPlan
  $CompletedPlan.dry_run = $false
  $CompletedPlan.phase = "completed"
  $CompletedPlan.post_run_analysis.generated_input_count = 2
  $CompletedPlan.post_run_analysis.triage_json = $TriageAnalysisPath
  $CompletedPlan.post_run_analysis.json = $PostRunAnalysisPath
  $CompletedPlan.post_run_analysis.expected_input_file_digest = $Digest
  Write-Json $PlanPath $CompletedPlan
  $CompletedAudit = Invoke-Audit
  Assert-Matches $CompletedAudit "Official performance \| Targeted blocker experiment plan manifest \| done" "done completed targeted blocker audit row"
  Assert-Matches $CompletedAudit "completed-run digest and exact input-file metadata checks" "completed targeted blocker digest and input metadata evidence wording"

  $BrokenDigestPlan = New-TargetedPlan
  $BrokenDigestPlan.dry_run = $false
  $BrokenDigestPlan.phase = "completed"
  $BrokenDigestPlan.post_run_analysis.generated_input_count = 2
  $BrokenDigestPlan.post_run_analysis.triage_json = $TriageAnalysisPath
  $BrokenDigestPlan.post_run_analysis.json = $PostRunAnalysisPath
  $BrokenDigestPlan.post_run_analysis.expected_input_file_digest = ("0" * 64)
  Write-Json $PlanPath $BrokenDigestPlan
  $BrokenDigestAudit = Invoke-Audit
  Assert-Matches $BrokenDigestAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for digest mismatch"
  Assert-Matches $BrokenDigestAudit "expected_input_file_digest does not match generated input list" "targeted blocker digest mismatch rejection"

  Write-Json $PlanPath (New-TargetedPlan -RequireCheckout $false -CommandRequiresCheckout $false)
  $BrokenAudit = Invoke-Audit
  Assert-Matches $BrokenAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row"
  Assert-Matches $BrokenAudit "post-run analysis does not require checkout-built browsers" "missing checkout setting rejection"
  Assert-Matches $BrokenAudit "post-run candidate command missing --requireCheckout" "missing checkout command rejection"

  Write-Json $PlanPath (New-TargetedPlan -RequirePackageSize $false -CommandRequiresPackageSize $false)
  $MissingPackageAudit = Invoke-Audit
  Assert-Matches $MissingPackageAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for missing package-size gate"
  Assert-Matches $MissingPackageAudit "post-run analysis does not require package-size evidence" "missing package-size setting rejection"
  Assert-Matches $MissingPackageAudit "post-run candidate command missing --requirePackageSize" "missing package-size command rejection"

  $MissingComplexityPolicyPlan = New-TargetedPlan
  $MissingComplexityPolicyPlan.post_run_analysis.PSObject.Properties.Remove("complexity_compatibility_policy")
  Write-Json $PlanPath $MissingComplexityPolicyPlan
  $MissingComplexityPolicyAudit = Invoke-Audit
  Assert-Matches $MissingComplexityPolicyAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for missing complexity policy"
  Assert-Matches $MissingComplexityPolicyAudit "post-run analysis complexity policy is not same-explicit-benchmark-complexity" "missing complexity compatibility policy rejection"

  Write-Json $PlanPath (New-TargetedPlan -IncludeTargetedTrace $false)
  $MissingTraceAudit = Invoke-Audit
  Assert-Matches $MissingTraceAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for missing traces"
  Assert-Matches $MissingTraceAudit "targeted_trace missing or disabled for planned WebGPU blocker scenes" "missing targeted trace rejection"

  Write-Json $PlanPath (New-TargetedPlan -RejectWebGpuCpuFallback $false)
  $MissingCpuFallbackRejectionAudit = Invoke-Audit
  Assert-Matches $MissingCpuFallbackRejectionAudit "Official performance \| Targeted blocker experiment plan manifest \| pending" "pending targeted blocker audit row for missing CPU-fallback rejection"
  Assert-Matches $MissingCpuFallbackRejectionAudit "targeted_trace does not reject WebGPU CPU texture fallback/readback" "missing targeted trace CPU-fallback rejection"

  Write-Host "Targeted blocker manifest audit requires source candidate-analysis policies including explicit GPU timing evidence, input digests, current official/trusted seed digests when completed current manifests are available, checkout-built browser gating, package-size evidence, analyzer commands, completed-run input digests plus exact input file metadata, and targeted WebGPU trace capture with CPU-fallback and software-renderer rejection."
} finally {
  if ($null -eq $OldAllowOverrides) {
    Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowOverrides
  }
  if ($null -eq $OldTargetedPlan) {
    Remove-Item Env:\THREE_BROWSER_TEST_TARGETED_BLOCKER_PLAN_MANIFEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_TARGETED_BLOCKER_PLAN_MANIFEST = $OldTargetedPlan
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
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

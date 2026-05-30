[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\suite-promotion-plan-test"
$TriagePath = Join-Path $TempDir "triage-analysis.json"
$TargetedPlanPath = Join-Path $TempDir "targeted-plan.json"
$PromotionPlanPath = Join-Path $TempDir "promotion-plan.json"
$InputListPath = Join-Path $TempDir "promotion-inputs.txt"

function Assert-Matches {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Suite-promotion plan missing $Description. Pattern: $Pattern Text: $Text"
  }
}

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  $Scenes = @(
    "many-draw-calls",
    "instancing",
    "shader-heavy",
    "texture-streaming",
    "postprocessing",
    "large-static",
    "gltf-loader-stress"
  )
  $CommonSuffix = "-warmup-precompile-prerender2-settlegpu"
  $WebGlSuffix = $CommonSuffix
  $WebGpuSuffix = "$CommonSuffix-pipelinequiet2"
  $WebGlBase = "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy"
  $WebGpuBase = "fork-viewer-exp-webgpu-d3d11-skip-validation"
  $IgnoredWebGpuBase = "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment"

  $TargetedPlan = [pscustomobject]@{
    chromium_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    fork_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa+viewerpatch-test"
    browsers = [pscustomobject]@{
      baseline = ".\src\out\ReleaseBaseline\content_shell.exe"
      fork = ".\src\out\ReleaseViewerDefault\content_shell.exe"
    }
    build_args = [pscustomobject]@{
      baseline = ".\src\out\ReleaseBaseline\args.gn"
      fork = ".\src\out\ReleaseViewerDefault\args.gn"
    }
    package_dirs = [pscustomobject]@{
      baseline = ".\benchmarks\packages\baseline-content-shell"
      fork = ".\benchmarks\packages\viewer-default"
    }
    options = [pscustomobject]@{
      duration = 60
      warmup = 10
      complexity = 2
      precompile = $true
      prerender_frames = 2
      settle_gpu_after_warmup = $true
      webgpu_pipeline_quiet_frames = 2
      webgpu_pipeline_quiet_max_frames = 12
      webgl_angle_backend = @("d3d11")
      resource_warmup_label_suffix = $CommonSuffix
      webgl2_resource_warmup_label_suffix = $WebGlSuffix
      webgpu_resource_warmup_label_suffix = $WebGpuSuffix
      disable_webgpu_timing = $true
      run_comparable_baselines = $true
    }
    experiment_labels = [pscustomobject]@{
      webgl2 = @("$WebGlBase$WebGlSuffix")
      webgpu = @("$WebGpuBase$WebGpuSuffix", "$IgnoredWebGpuBase$WebGpuSuffix")
    }
    base_experiment_labels = [pscustomobject]@{
      webgl2 = @($WebGlBase)
      webgpu = @($WebGpuBase, $IgnoredWebGpuBase)
    }
    result_files = [pscustomobject]@{
      baseline_webgl2 = @($Scenes | ForEach-Object { [pscustomobject]@{ path = "C:\tmp\baseline-content-shell-targeted-blocker$WebGlSuffix-$_-webgl2.json" } })
      baseline_webgpu = @($Scenes | ForEach-Object { [pscustomobject]@{ path = "C:\tmp\baseline-content-shell-targeted-blocker-webgpu$WebGpuSuffix-$_-webgpu.json" } })
    }
    post_run_analysis = [pscustomobject]@{
      min_measured_seconds = 30
      min_avg_fps_delta_pct = 0.5
      scene_regression_pct = 1
      dropped_frames_regression = 0
      cpu_frame_regression_ms = 0.5
      render_submission_regression_ms = 0.5
      pipeline_create_regression_ms = 1.0
      required_scenes = @($Scenes)
      expected_chromium_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      expected_fork_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa+viewerpatch-test"
    }
  }
  $TargetedPlan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $TargetedPlanPath -Encoding UTF8

  $Triage = [pscustomobject]@{
    families = @(
      [pscustomobject]@{
        renderer = "webgpu"
        status = "candidate"
        candidate_family = "$WebGpuBase$WebGpuSuffix"
        baseline_family = "baseline-webgpu"
        scene_names = @("gltf-loader-stress")
        avg_fps_delta_pct = 2.4
        min_fps_delta_pct = 2.4
        p99_frame_ms_delta = -1.2
      },
      [pscustomobject]@{
        renderer = "webgl2"
        status = "needs-suite"
        candidate_family = "$WebGlBase$WebGlSuffix"
        baseline_family = "baseline-webgl2"
        scene_names = @("many-draw-calls")
        avg_fps_delta_pct = 0.9
        min_fps_delta_pct = 0.9
        p99_frame_ms_delta = -0.2
      },
      [pscustomobject]@{
        renderer = "webgpu"
        status = "candidate"
        candidate_family = "$IgnoredWebGpuBase$WebGpuSuffix"
        baseline_family = "baseline-webgpu"
        scene_names = @("texture-streaming")
        avg_fps_delta_pct = 0.1
        min_fps_delta_pct = 0.1
        p99_frame_ms_delta = -0.1
      },
      [pscustomobject]@{
        renderer = "webgpu"
        status = "blocked-throughput"
        candidate_family = "fork-viewer-exp-webgpu-dawn-use-dxc$WebGpuSuffix"
        baseline_family = "baseline-webgpu"
        scene_names = @("gltf-loader-stress")
        avg_fps_delta_pct = 10
        min_fps_delta_pct = -2
        p99_frame_ms_delta = -2
      }
    )
  }
  $Triage | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $TriagePath -Encoding UTF8

  $Output = & (Join-Path $Root "scripts\plan_suite_promotion.ps1") `
    -TriageAnalysisJson $TriagePath `
    -TargetedPlanManifest $TargetedPlanPath `
    -PromotionPlanManifest $PromotionPlanPath `
    -PromotionInputList $InputListPath `
    -RequireCandidateRenderer "webgl2,webgpu" `
    -DryRun *>&1
  $Text = ($Output | ForEach-Object { [string]$_ }) -join "`n"

  Assert-Matches $Text "promotion webgl2 full-suite candidate matrix" "WebGL2 full-suite promotion step"
  Assert-Matches $Text "promotion webgpu full-suite candidate matrix" "WebGPU full-suite promotion step"
  Assert-Matches $Text "-Scenes\s+many-draw-calls,instancing,shader-heavy,texture-streaming,postprocessing,large-static,gltf-loader-stress\b" "required seven-scene suite handoff"
  Assert-Matches $Text "-Precompile\b" "precompile handoff"
  Assert-Matches $Text "-PrerenderFrames\s+2\b" "prerender handoff"
  Assert-Matches $Text "-SettleGpuAfterWarmup\b" "GPU-settle warmup handoff"
  Assert-Matches $Text "-LabelSuffix\s+$([regex]::Escape($WebGlSuffix))(?!-)" "WebGL2 resource warmup label suffix handoff"
  Assert-Matches $Text "-LabelSuffix\s+$([regex]::Escape($WebGpuSuffix))\b" "WebGPU resource warmup label suffix handoff"
  Assert-Matches $Text "-WebGpuPipelineQuietFrames\s+2\b" "WebGPU pipeline-quiet warmup handoff"
  Assert-Matches $Text "-WebGpuPipelineQuietMaxFrames\s+12\b" "WebGPU pipeline-quiet max-frame handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+$WebGpuBase\b" "WebGPU base label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+$WebGlBase\b" "WebGL2 base label filter handoff"
  Assert-Matches $Text "-DisableGpuTiming\b" "WebGPU timestamp timing handoff"
  Assert-Matches $Text "--requiredScene\s+many-draw-calls\b" "analysis many-draw-calls required scene"
  Assert-Matches $Text "--requiredScene\s+gltf-loader-stress\b" "analysis glTF required scene"
  Assert-Matches $Text "--droppedFramesRegression\s+0\b" "analysis dropped-frame regression threshold"
  Assert-Matches $Text "--cpuFrameRegressionMs\s+0\.5\b" "analysis CPU-frame regression threshold"
  Assert-Matches $Text "--renderSubmissionRegressionMs\s+0\.5\b" "analysis render-submission regression threshold"
  Assert-Matches $Text "--pipelineCreateRegressionMs\s+1\b" "analysis WebGPU pipeline-create regression threshold"
  Assert-Matches $Text "--requireCandidateRenderer\s+webgl2\b" "analysis WebGL2 renderer requirement"
  Assert-Matches $Text "--requireCandidateRenderer\s+webgpu\b" "analysis WebGPU renderer requirement"
  Assert-Matches $Text "--requireCheckout\b" "analysis checkout-built browser requirement"
  Assert-Matches $Text "--requirePackageSize\b" "analysis package-size evidence requirement"
  if ($Text -match $IgnoredWebGpuBase) {
    throw "Suite-promotion plan promoted a below-threshold WebGPU profile."
  }

  $InputList = Get-Content -LiteralPath $InputListPath -Raw
  Assert-Matches $InputList "baseline-content-shell-targeted-blocker$WebGlSuffix-many-draw-calls-webgl2\.json" "existing WebGL2 baseline input reuse"
  Assert-Matches $InputList "$WebGlBase$WebGlSuffix-instancing-webgl2\.json" "WebGL2 promoted full-suite input"
  Assert-Matches $InputList "$WebGpuBase$WebGpuSuffix-postprocessing-webgpu\.json" "WebGPU promoted full-suite input"
  if ($InputList -match "$([regex]::Escape($WebGpuSuffix))-[A-Za-z0-9-]+-webgl2\.json") {
    throw "Suite-promotion input list applied the WebGPU pipeline-quiet suffix to WebGL2 files."
  }
  if ($InputList -match $IgnoredWebGpuBase) {
    throw "Suite-promotion input list included a below-threshold WebGPU profile."
  }

  $Manifest = Get-Content -LiteralPath $PromotionPlanPath -Raw | ConvertFrom-Json
  if ($Manifest.dry_run -ne $true -or $Manifest.phase -ne "planned") {
    throw "Suite-promotion manifest did not record dry-run planned phase."
  }
  if (@($Manifest.promotion_profiles).Count -ne 2) {
    throw "Suite-promotion manifest did not record exactly two promoted profiles."
  }
  if (@($Manifest.required_scenes).Count -ne 7) {
    throw "Suite-promotion manifest did not retain all seven required scenes."
  }
  if (@($Manifest.required_candidate_renderers) -notcontains "webgl2" -or @($Manifest.required_candidate_renderers) -notcontains "webgpu") {
    throw "Suite-promotion manifest did not record required renderers."
  }
  if ([int]$Manifest.generated_input_count -ne 28) {
    throw "Suite-promotion manifest generated_input_count expected 28, got $($Manifest.generated_input_count)."
  }
  if ($Manifest.analysis.require_checkout -ne $true) {
    throw "Suite-promotion manifest did not record checkout-built browser analysis requirement."
  }
  if ($Manifest.analysis.require_package_size -ne $true) {
    throw "Suite-promotion manifest did not record package-size analysis requirement."
  }
  if ([double]$Manifest.analysis.dropped_frames_regression -ne 0.0) {
    throw "Suite-promotion manifest did not record the dropped-frame regression threshold."
  }
  if ([double]$Manifest.analysis.cpu_frame_regression_ms -ne 0.5 -or
      [double]$Manifest.analysis.render_submission_regression_ms -ne 0.5) {
    throw "Suite-promotion manifest did not record CPU/render-submission regression thresholds."
  }
  if ([double]$Manifest.analysis.pipeline_create_regression_ms -ne 1.0) {
    throw "Suite-promotion manifest did not record the WebGPU pipeline-create regression threshold."
  }
  if ($Manifest.options.settle_gpu_after_warmup -ne $true) {
    throw "Suite-promotion manifest did not record GPU-settle warmup mode."
  }
  if ([int]$Manifest.options.webgpu_pipeline_quiet_frames -ne 2 -or [int]$Manifest.options.webgpu_pipeline_quiet_max_frames -ne 12) {
    throw "Suite-promotion manifest did not record WebGPU pipeline-quiet warmup mode."
  }
  if ([string]$Manifest.options.webgl2_label_suffix -ne $WebGlSuffix -or [string]$Manifest.options.webgpu_label_suffix -ne $WebGpuSuffix) {
    throw "Suite-promotion manifest did not record renderer-specific label suffixes."
  }

  $TargetedPlan.options | Add-Member -NotePropertyName webgpu_profile_cache_key -NotePropertyValue "warm-cache-dryrun" -Force
  $TargetedPlan.options | Add-Member -NotePropertyName webgpu_profile_cache_mode -NotePropertyValue "explicit-reuse" -Force
  $TargetedPlan.options | Add-Member -NotePropertyName profile_cache_root -NotePropertyValue ".\benchmarks\tmp\suite-promotion-profile-cache" -Force
  $TargetedPlan.options | Add-Member -NotePropertyName prime_webgpu_profile_cache -NotePropertyValue $true -Force
  $TargetedPlan.options | Add-Member -NotePropertyName profile_cache_policy -NotePropertyValue "same-profile-cache-mode-and-key" -Force
  $TargetedPlan.options | Add-Member -NotePropertyName profile_cache_prime_policy -NotePropertyValue "prime-before-measured-run" -Force
  $TargetedPlan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $TargetedPlanPath -Encoding UTF8

  $CacheTriage = [pscustomobject]@{
    families = @(
      [pscustomobject]@{
        renderer = "webgpu"
        status = "cache-attribution"
        candidate_family = "$WebGpuBase$WebGpuSuffix"
        baseline_family = "baseline-webgpu"
        scene_names = @("gltf-loader-stress")
        avg_fps_delta_pct = 3.2
        min_fps_delta_pct = 3.2
        p99_frame_ms_delta = -1.4
        profile_cache_mode = "explicit-reuse"
        profile_cache_key = "warm-cache-dryrun"
      }
    )
  }
  $CacheTriage | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $TriagePath -Encoding UTF8

  $CacheOutput = & (Join-Path $Root "scripts\plan_suite_promotion.ps1") `
    -TriageAnalysisJson $TriagePath `
    -TargetedPlanManifest $TargetedPlanPath `
    -PromotionPlanManifest $PromotionPlanPath `
    -PromotionInputList $InputListPath `
    -RequireCandidateRenderer "webgpu" `
    -DryRun *>&1
  $CacheText = ($CacheOutput | ForEach-Object { [string]$_ }) -join "`n"

  Assert-Matches $CacheText "fresh-profile confirmation webgpu comparable baseline suite" "fresh-profile WebGPU baseline confirmation step"
  Assert-Matches $CacheText "fresh-profile confirmation webgpu full-suite candidate matrix" "fresh-profile WebGPU candidate confirmation step"
  Assert-Matches $CacheText "-LabelSuffix\s+$([regex]::Escape($WebGpuSuffix))-fresh-profile-confirmation\b" "fresh-profile confirmation label suffix"
  Assert-Matches $CacheText "-WebGpuPipelineQuietFrames\s+2\b" "fresh-profile WebGPU pipeline-quiet warmup handoff"
  Assert-Matches $CacheText "-WebGpuPipelineQuietMaxFrames\s+12\b" "fresh-profile WebGPU pipeline-quiet max-frame handoff"
  Assert-Matches $CacheText "--requireCandidateRenderer\s+webgpu\b" "fresh-profile confirmation WebGPU analysis gate"
  Assert-Matches $CacheText "--requirePackageSize\b" "fresh-profile confirmation package-size analysis gate"
  Assert-Matches $CacheText "--droppedFramesRegression\s+0\b" "fresh-profile confirmation dropped-frame regression threshold"
  Assert-Matches $CacheText "--cpuFrameRegressionMs\s+0\.5\b" "fresh-profile confirmation CPU-frame regression threshold"
  Assert-Matches $CacheText "--renderSubmissionRegressionMs\s+0\.5\b" "fresh-profile confirmation render-submission regression threshold"
  Assert-Matches $CacheText "--pipelineCreateRegressionMs\s+1\b" "fresh-profile confirmation WebGPU pipeline-create regression threshold"
  if ($CacheText -match "-ProfileCacheKey" -or $CacheText -match "-PrimeProfileCache") {
    throw "Fresh-profile confirmation commands must not reuse the warm profile-cache flags. Text: $CacheText"
  }

  $CacheManifest = Get-Content -LiteralPath $PromotionPlanPath -Raw | ConvertFrom-Json
  if (@($CacheManifest.promotion_profiles).Count -ne 0) {
    throw "Cache-attribution triage rows must not be promoted as retained candidate profiles."
  }
  if (@($CacheManifest.cache_attribution_confirmations).Count -ne 1) {
    throw "Suite-promotion manifest did not record the cache-attribution fresh-profile confirmation."
  }
  $CacheConfirmation = @($CacheManifest.cache_attribution_confirmations)[0]
  if ([string]$CacheConfirmation.status -ne "fresh-profile-confirmation" -or
      [string]$CacheConfirmation.source_status -ne "cache-attribution" -or
      [string]$CacheConfirmation.candidate_family -ne "$WebGpuBase$WebGpuSuffix-fresh-profile-confirmation") {
    throw "Cache-attribution confirmation manifest did not preserve source and planned fresh-profile labels."
  }
  if ([int]$CacheManifest.generated_input_count -ne 14) {
    throw "Cache-attribution fresh-profile confirmation expected 14 full-suite inputs, got $($CacheManifest.generated_input_count)."
  }
  $CacheInputList = Get-Content -LiteralPath $InputListPath -Raw
  Assert-Matches $CacheInputList "baseline-content-shell-suite-promotion-fresh-profile-webgpu$WebGpuSuffix-fresh-profile-confirmation-many-draw-calls-webgpu\.json" "fresh-profile confirmation baseline input"
  Assert-Matches $CacheInputList "$WebGpuBase$WebGpuSuffix-fresh-profile-confirmation-gltf-loader-stress-webgpu\.json" "fresh-profile confirmation candidate input"

  Write-Host "Suite-promotion planner expands clean one-scene candidates into full-suite WebGL2/WebGPU retest commands, and converts cache-attribution wins into fresh-profile confirmation suites."
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\blocker-experiment-plan-test"
$AnalysisPath = Join-Path $TempDir "candidate-analysis.json"

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

function Assert-Matches {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Blocker experiment plan missing $Description. Pattern: $Pattern Output: $Text"
  }
}

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  $Analysis = [pscustomobject]@{
    required_candidate_gate = [pscustomobject]@{
      renderers = @(
        [pscustomobject]@{
          renderer = "webgl2"
          ok = $false
          best_status = "needs-suite"
          best_candidate_family = "fork-needs-suite"
          best_baseline_family = "baseline-webgl2"
        },
        [pscustomobject]@{
          renderer = "webgpu"
          ok = $false
          best_status = "blocked-tail"
          best_candidate_family = "fork-webgpu-default"
          best_baseline_family = "baseline-webgpu"
        }
      )
    }
    blocker_diagnostics = @(
      [pscustomobject]@{ renderer = "webgl2"; baseline_family = "baseline-webgl2"; status = "needs-suite"; scene = "coverage 1/7"; candidate_family = "fork-needs-suite" },
      [pscustomobject]@{ renderer = "webgl2"; baseline_family = "baseline-webgl2"; status = "blocked-tail"; scene = "postprocessing"; candidate_family = "fork-webgl2-zero-copy" },
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "blocked-tail"; scene = "large-static"; candidate_family = "fork-webgpu-default" },
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "not useful"; scene = "texture-streaming"; candidate_family = "fork-webgpu-single-process" }
    )
  }
  $Analysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $AnalysisPath -Encoding UTF8

  $PostRunTriageOutput = Join-Path $TempDir "targeted-blocker-triage-analysis.md"
  $PostRunTriageJson = Join-Path $TempDir "targeted-blocker-triage-analysis.json"
  $PromotionPlanPath = Join-Path $TempDir "promotion-plan.json"
  $PromotionInputListPath = Join-Path $TempDir "promotion-inputs.txt"

  $Output = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $AnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -Precompile `
    -PrerenderFrames 2 `
    -DisableWebGpuTiming `
    -AnalyzeAfterRun `
    -PostRunAnalysisInputList (Join-Path $TempDir "post-run-inputs.txt") `
    -PostRunTriageAnalysisOutput $PostRunTriageOutput `
    -PostRunTriageAnalysisJson $PostRunTriageJson `
    -TargetedPlanManifest (Join-Path $TempDir "targeted-plan.json") `
    -PlanSuitePromotionAfterTriage `
    -SuitePromotionPlanManifest $PromotionPlanPath `
    -SuitePromotionInputList $PromotionInputListPath `
    -SuitePromotionAnalysisOutput ".\benchmarks\reports\targeted-suite-promotion-analysis.md" `
    -SuitePromotionAnalysisJson ".\benchmarks\reports\targeted-suite-promotion-analysis.json" `
    -PostRunAnalysisMinMeasuredSeconds 1 `
    -PostRunAnalysisSceneRegressionPct 0.5 `
    -RunComparableBaselines `
    -CaptureTargetedTrace `
    -TraceDuration 1 `
    -TraceWarmup 1 `
    -TraceStartDelayMs 1234 `
    -TraceQueueInstrumentation `
    -TraceBindGroupInstrumentation `
    -TracePipelineStateInstrumentation `
    -TraceBufferStateInstrumentation `
    -TraceRenderStateInstrumentation `
    -TraceImmediateInstrumentation `
    -RejectWebGpuCpuFallbackTrace `
    -WebGpuProfileCacheKey "dryrun-targeted-webgpu-cache" `
    -ProfileCacheRoot (Join-Path $TempDir "targeted-profile-cache") `
    -PrimeWebGpuProfileCache `
    -DryRun *>&1
  $Text = ($Output | ForEach-Object { [string]$_ }) -join "`n"

  Assert-Matches $Text "targeted WebGL2 comparable baseline suite" "WebGL2 comparable baseline suite step"
  Assert-Matches $Text "run_full_suite\.ps1\b" "WebGL2 comparable baseline command helper"
  Assert-Matches $Text "-Label\s+baseline-content-shell-targeted-blocker-warmup-precompile-prerender2\b" "WebGL2 comparable baseline resource-warmup label"
  Assert-Matches $Text "-Duration\s+1\b" "comparable baseline duration"
  Assert-Matches $Text "-Warmup\s+1\b" "comparable baseline warmup"
  Assert-Matches $Text "-Complexity\s+2\b" "comparable baseline complexity"
  Assert-Matches $Text "-Precompile\b" "matched resource precompile handoff"
  Assert-Matches $Text "-PrerenderFrames\s+2\b" "matched resource prerender-frame handoff"
  Assert-Matches $Text "-LabelSuffix\s+-warmup-precompile-prerender2\b" "trusted matrix resource-warmup label suffix handoff"
  Assert-Matches $Text "-RequireGpuMetadata\b" "comparable baseline GPU metadata validation"

  Assert-Matches $Text "targeted WebGL2 needs-suite expansion matrix" "WebGL2 needs-suite expansion matrix step"
  Assert-Matches $Text "-Renderer\s+webgl2\b" "WebGL2 renderer handoff"
  Assert-Matches $Text "-Scenes\s+many-draw-calls,instancing,shader-heavy,texture-streaming,postprocessing,large-static,gltf-loader-stress\b" "WebGL2 full-suite expansion scenes"
  Assert-Matches $Text "-AngleBackend\s+d3d11\b" "WebGL2 D3D11 ANGLE interaction experiment"
  Assert-Matches $Text "-IncludeZeroCopy\b" "WebGL2 zero-copy experiment"
  Assert-Matches $Text "-IncludeWebGlCompositorExperiments\b" "WebGL2 compositor-resource experiment"
  Assert-Matches $Text "-IncludeFramePacingExperiments\b" "trusted frame-pacing experiments"
  Assert-Matches $Text "-IncludeReservedNoopGates\b" "WebGL2 reserved/relaxed gate experiment"
  if ($Text -match "coverage 1/7") {
    throw "Blocker experiment plan treated a coverage diagnostic as a scene."
  }

  Assert-Matches $Text "targeted WebGPU comparable baseline suite" "WebGPU comparable baseline suite step"
  Assert-Matches $Text "prime targeted WebGPU comparable baseline suite" "WebGPU comparable baseline profile-cache priming step"
  Assert-Matches $Text "-Label\s+baseline-content-shell-targeted-blocker-webgpu-warmup-precompile-prerender2\b" "WebGPU comparable baseline resource-warmup label"
  Assert-Matches $Text "-DisableGpuTiming\b" "WebGPU comparable baseline timestamp timing mode"
  Assert-Matches $Text "-ProfileCacheKey\s+dryrun-targeted-webgpu-cache\b.*-UserDataDirRoot\s+.*targeted-profile-cache" "WebGPU comparable baseline profile-cache handoff"

  Assert-Matches $Text "targeted WebGPU blocker matrix" "WebGPU blocker matrix step"
  Assert-Matches $Text "-Renderer\s+webgpu\b" "WebGPU renderer handoff"
  Assert-Matches $Text "-Scenes\s+large-static\b" "required-gate focused WebGPU blocker scene"
  Assert-Matches $Text "-IncludeSingleProcess\b" "WebGPU single-process experiment"
  Assert-Matches $Text "-IncludeInProcessGpu\b" "WebGPU in-process GPU experiment"
  Assert-Matches $Text "-IncludeFramePacingExperiments\b" "WebGPU frame-pacing experiment"
  Assert-Matches $Text "-IncludeWebGpuDawnExperiments\b" "WebGPU Dawn experiment"
  Assert-Matches $Text "-IncludeWebGpuChromiumFeatureExperiments\b" "WebGPU Chromium feature experiment"
  Assert-Matches $Text "-IncludeWebGpuUploadExperiments\b" "WebGPU upload/command-buffer experiment"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-dawn-use-dxc\b" "focused WebGPU Dawn DXC experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation\b" "focused WebGPU Dawn blob-cache hash-validation disable experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-disable-range-analysis\b" "focused WebGPU robustness range-analysis disable experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-disable-frame-rate-limit\b" "focused frame-rate-limit experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-disable-gpu-vsync\b" "focused GPU-vsync experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d12-toggles\b" "focused WebGPU D3D12 toggle experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-discard-view\b" "focused WebGPU D3D11 DiscardView experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-wait-thread-safe\b" "focused WebGPU D3D11 thread-safe wait experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-delay-flush-wait-thread-safe\b" "focused WebGPU D3D11 delayed-flush plus thread-safe wait experiment label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range\b" "focused WebGPU D3D11 DXC/IPC/HLSL/range-analysis interaction label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush\b" "focused WebGPU async pipeline flush deferral interaction label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush\b" "focused WebGPU queue-flush deferral interaction label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush\b" "focused WebGPU submit-flush deferral interaction label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation\b" "focused WebGPU canvas validation skip interaction label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory\b" "focused WebGPU canvas memory-accounting skip interaction label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters\b" "focused WebGPU use-counter skip interaction label filter handoff"
  Assert-Matches $Text "-ExperimentLabelFilter\s+fork-viewer-exp-default,.*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip\b" "focused WebGPU experiment label filter handoff"
  Assert-Matches $Text "-ProfileCacheKey\s+dryrun-targeted-webgpu-cache\b.*-UserDataDirRoot\s+.*targeted-profile-cache\b.*-PrimeProfileCache\b" "focused WebGPU matrix profile-cache and priming handoff"
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment") {
    throw "Blocker experiment plan scheduled texture-upload rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "Blocker experiment plan scheduled copyExternalImage upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion") {
    throw "Blocker experiment plan scheduled copyExternalImage color-conversion upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation") {
    throw "Blocker experiment plan scheduled copyExternalImage color-space upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-source-validation") {
    throw "Blocker experiment plan scheduled copyExternalImage source upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation") {
    throw "Blocker experiment plan scheduled copyExternalImage copy-size upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path") {
    throw "Blocker experiment plan scheduled copyExternalImage combined upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") {
    throw "Blocker experiment plan scheduled the aggressive D3D11 upload fast-path even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path") {
    throw "Blocker experiment plan scheduled the aggressive D3D11 pipeline fast-path even though the required-gate WebGPU blocker is large-static, not glTF/draw-call."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-defer-queue-flush(,|\b)") {
    throw "Blocker experiment plan scheduled standalone queue-flush rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-defer-pipeline-flush(,|\b)") {
    throw "Blocker experiment plan scheduled standalone async pipeline flush rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($Text -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-dawn-skip-validation") {
    throw "Blocker experiment plan scheduled Dawn skip-validation for large-static/texture-streaming blockers instead of keeping the WebGPU filter focused."
  }
  if ($Text -match "--variant\s+fork-viewer-exp-webgpu-dawn-skip-validation") {
    throw "Trusted matrix ignored the focused WebGPU experiment label filter and emitted a Dawn skip-validation benchmark command."
  }
  Assert-Matches $Text "-DisableGpuTiming\b" "WebGPU timestamp timing disabled handoff"
  Assert-Matches $Text "targeted WebGPU baseline trace \(large-static\)" "targeted WebGPU baseline trace step"
  Assert-Matches $Text "run_trace_capture\.mjs\b.*--scene\s+large-static\b.*--renderer\s+webgpu\b.*--duration\s+1\b.*--warmup\s+1\b.*--startDelayMs\s+1234\b" "targeted WebGPU trace capture command"
  Assert-Matches $Text "run_trace_capture\.mjs\b.*--queueInstrumentation\b" "targeted WebGPU trace queue instrumentation handoff"
  Assert-Matches $Text "run_trace_capture\.mjs\b.*--bindGroupInstrumentation\b" "targeted WebGPU trace bind-group instrumentation handoff"
  Assert-Matches $Text "run_trace_capture\.mjs\b.*--pipelineStateInstrumentation\b" "targeted WebGPU trace pipeline-state instrumentation handoff"
  Assert-Matches $Text "run_trace_capture\.mjs\b.*--bufferStateInstrumentation\b" "targeted WebGPU trace buffer-state instrumentation handoff"
  Assert-Matches $Text "run_trace_capture\.mjs\b.*--renderStateInstrumentation\b" "targeted WebGPU trace render-state instrumentation handoff"
  Assert-Matches $Text "run_trace_capture\.mjs\b.*--immediateInstrumentation\b" "targeted WebGPU trace immediate instrumentation handoff"
  Assert-Matches $Text "targeted WebGPU fork trace \(large-static\)" "targeted WebGPU fork trace step"
  Assert-Matches $Text "run_trace_capture\.mjs\b.*--viewerMode\b.*--viewerTrustedContent\b.*--viewerTraceWebgpuQueue\b.*--viewerRejectWebgpuCpuTextureFallback\b" "targeted WebGPU fork source trace and CPU-fallback rejection handoff"
  Assert-Matches $Text "validate_trace_file\.mjs\b.*--rejectWebGpuCpuFallback\b.*large-static-webgpu-targeted-trace\.json" "targeted WebGPU trace file CPU-fallback rejection validation"
  Assert-Matches $Text "validate_trace_result\.mjs\b.*--expectedScene\s+large-static\b.*--expectedRenderer\s+webgpu\b.*--expectedStartDelayMs\s+1234\b" "targeted WebGPU trace sidecar validation"
  Assert-Matches $Text "validate_trace_result\.mjs\b.*--expectedFlagMetadata\s+viewer_trace_webgpu_queue=true\b.*--expectedFlagMetadata\s+webgpu_queue_instrumentation_enabled=true\b.*--expectedFlagMetadata\s+webgpu_bind_group_instrumentation_enabled=true\b.*--expectedFlagMetadata\s+webgpu_pipeline_state_instrumentation_enabled=true\b.*--expectedFlagMetadata\s+webgpu_buffer_state_instrumentation_enabled=true\b.*--expectedFlagMetadata\s+webgpu_render_state_instrumentation_enabled=true\b.*--expectedFlagMetadata\s+webgpu_immediate_instrumentation_enabled=true\b" "targeted WebGPU fork trace sidecar metadata validation"
  Assert-Matches $Text "summarize_trace\.mjs\b.*--rejectWebGpuCpuFallback\b" "targeted WebGPU trace summary CPU-fallback rejection"

  Assert-Matches $Text "post-run blocker triage analysis" "post-run blocker triage analysis step"
  Assert-Matches $Text "analyze_candidates\.mjs" "post-run candidate analyzer"
  Assert-Matches $Text "--fileList\s+.*post-run-inputs\.txt" "post-run scoped input list handoff"
  if ($Text -match "\\benchmarks\\raw\\\*\.json") {
    throw "Blocker experiment plan used a broad post-run analysis glob instead of scoped current-run result files."
  }
  Assert-Matches $Text "--output\s+.*targeted-blocker-triage-analysis\.md" "post-run blocker triage markdown report output"
  Assert-Matches $Text "--json\s+.*targeted-blocker-triage-analysis\.json" "post-run blocker triage JSON report output"
  Assert-Matches $Text "--minScenes\s+1\b" "post-run blocker triage one-scene gate"
  Assert-Matches $Text "--minAvgFpsDeltaPct\s+0\.5\b" "post-run blocker triage minimum retained speedup threshold"
  Assert-Matches $Text "--droppedFramesRegression\s+0\b" "post-run blocker triage dropped-frame regression threshold"
  Assert-Matches $Text "--cpuFrameRegressionMs\s+0\.5\b" "post-run blocker triage CPU-frame regression threshold"
  Assert-Matches $Text "--renderSubmissionRegressionMs\s+0\.5\b" "post-run blocker triage render-submission regression threshold"
  Assert-Matches $Text "--pipelineCreateRegressionMs\s+1\b" "post-run blocker triage WebGPU pipeline-create regression threshold"
  Assert-Matches $Text "post-run candidate speed analysis" "post-run candidate analysis step"
  Assert-Matches $Text "--output\s+\.\\benchmarks\\reports\\targeted-blocker-candidate-analysis\.md" "post-run markdown report output"
  Assert-Matches $Text "--json\s+\.\\benchmarks\\reports\\targeted-blocker-candidate-analysis\.json" "post-run JSON report output"
  Assert-Matches $Text "--minMeasuredSeconds\s+1\b" "post-run candidate analysis minimum duration handoff"
  Assert-Matches $Text "--minScenes\s+7\b" "post-run candidate analysis full-suite scene gate"
  Assert-Matches $Text "--requiredScene\s+many-draw-calls\b" "post-run candidate analysis many-draw-calls required scene"
  Assert-Matches $Text "--requiredScene\s+gltf-loader-stress\b" "post-run candidate analysis glTF required scene"
  Assert-Matches $Text "--minAvgFpsDeltaPct\s+0\.5\b" "post-run candidate analysis minimum retained speedup threshold"
  Assert-Matches $Text "--sceneRegressionPct\s+0\.5\b" "post-run candidate analysis scene-throughput regression threshold handoff"
  Assert-Matches $Text "--droppedFramesRegression\s+0\b" "post-run candidate analysis dropped-frame regression threshold handoff"
  Assert-Matches $Text "--cpuFrameRegressionMs\s+0\.5\b" "post-run candidate analysis CPU-frame regression threshold handoff"
  Assert-Matches $Text "--renderSubmissionRegressionMs\s+0\.5\b" "post-run candidate analysis render-submission regression threshold handoff"
  Assert-Matches $Text "--pipelineCreateRegressionMs\s+1\b" "post-run candidate analysis WebGPU pipeline-create regression threshold handoff"
  Assert-Matches $Text "--requireFrameTimes\b" "post-run candidate analysis frame-time requirement"
  Assert-Matches $Text "--requireCheckout\b" "post-run candidate analysis checkout-built browser requirement"
  Assert-Matches $Text "--requirePackageSize\b" "post-run candidate analysis package-size evidence requirement"
  Assert-Matches $Text "--expectedChromiumRevision\s+[0-9a-f]{40}\b" "post-run expected Chromium revision filter"
  Assert-Matches $Text "--expectedForkRevision\s+rev-a\+viewerpatch-test\b" "post-run expected fork revision filter"
  Assert-Matches $Text "--requireCandidateRenderer\s+webgl2\b" "post-run WebGL2 candidate gate"
  Assert-Matches $Text "--requireCandidateRenderer\s+webgpu\b" "post-run WebGPU candidate gate"
  Assert-Matches $Text "post-run suite promotion planning" "post-run suite promotion planning step"
  Assert-Matches $Text "plan_suite_promotion\.ps1\b" "suite promotion planner handoff"
  Assert-Matches $Text "-TriageAnalysisJson\s+.*targeted-blocker-triage-analysis\.json\b" "suite promotion triage JSON handoff"
  Assert-Matches $Text "-TargetedPlanManifest\s+.*targeted-plan\.json\b" "suite promotion targeted plan handoff"
  Assert-Matches $Text "-PromotionPlanManifest\s+.*promotion-plan\.json\b" "suite promotion manifest output handoff"
  Assert-Matches $Text "-PromotionInputList\s+.*promotion-inputs\.txt\b" "suite promotion scoped input list handoff"
  Assert-Matches $Text "-RequireCandidateRenderer\s+webgl2,webgpu\b" "suite promotion WebGL2/WebGPU renderer gate"
  Assert-Matches $Text "-PipelineCreateRegressionMs\s+1\b" "suite promotion WebGPU pipeline-create regression gate handoff"
  Assert-Matches $Text "targeted-plan\.json" "targeted plan manifest output"

  $InputListPath = Join-Path $TempDir "post-run-inputs.txt"
  if (-not (Test-Path -LiteralPath $InputListPath -PathType Leaf)) {
    throw "Blocker experiment plan did not write the scoped post-run input list: $InputListPath"
  }
  $InputList = Get-Content -LiteralPath $InputListPath -Raw
  Assert-Matches $InputList "baseline-content-shell-targeted-blocker-warmup-precompile-prerender2-many-draw-calls-webgl2\.json" "post-run scoped WebGL2 baseline input"
  Assert-Matches $InputList "fork-viewer-exp-relaxed-webgl-validation-zero-copy-warmup-precompile-prerender2-many-draw-calls-webgl2\.json" "post-run scoped WebGL2 fork input"
  Assert-Matches $InputList "fork-viewer-exp-angle-d3d11-zero-copy-warmup-precompile-prerender2-many-draw-calls-webgl2\.json" "post-run scoped WebGL2 D3D11 zero-copy input"
  Assert-Matches $InputList "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy-warmup-precompile-prerender2-many-draw-calls-webgl2\.json" "post-run scoped WebGL2 D3D11 relaxed zero-copy input"
  Assert-Matches $InputList "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync-warmup-precompile-prerender2-many-draw-calls-webgl2\.json" "post-run scoped WebGL2 frame-pacing input"
  Assert-Matches $InputList "baseline-content-shell-targeted-blocker-webgpu-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU baseline input"
  Assert-Matches $InputList "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU frame-pacing input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-unmonitored-fence-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU D3D11 fence input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-delay-flush-unmonitored-fence-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU D3D11 delayed-flush plus unmonitored-fence input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-dawn-use-dxc-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU Dawn DXC input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU Dawn blob-cache hash-validation disable input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-disable-range-analysis-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU range-analysis disable input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d12-toggles-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU D3D12 toggle input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-discard-view-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU D3D11 DiscardView input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU D3D11 DXC/IPC/HLSL/range-analysis interaction input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU D3D11 DXC/flush/fence/clear-skip interaction input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU async pipeline flush deferral interaction input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU redundant setPipeline skip interaction input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU redundant setBindGroup skip interaction input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU queue-flush deferral interaction input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU submit-flush deferral interaction input"
  Assert-Matches $InputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory-warmup-precompile-prerender2-large-static-webgpu\.json" "post-run scoped WebGPU canvas memory-accounting skip interaction input"
  if ($InputList -match "fork-viewer-exp-[^\r\n]*texture-streaming-webgpu") {
    throw "Blocker experiment input list included fork texture-streaming experiments even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment") {
    throw "Blocker experiment input list included texture-upload rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "Blocker experiment input list included copyExternalImage upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion") {
    throw "Blocker experiment input list included copyExternalImage color-conversion upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation") {
    throw "Blocker experiment input list included copyExternalImage color-space upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation") {
    throw "Blocker experiment input list included copyExternalImage source upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation") {
    throw "Blocker experiment input list included copyExternalImage copy-size upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path") {
    throw "Blocker experiment input list included copyExternalImage combined upload-only rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") {
    throw "Blocker experiment input list included the aggressive D3D11 upload fast-path even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-dawn-skip-validation") {
    throw "Blocker experiment input list included Dawn skip-validation even though the synthetic WebGPU blockers were texture/large-pass scenes."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-defer-pipeline-flush-warmup-precompile-prerender2-large-static-webgpu") {
    throw "Blocker experiment input list included standalone async pipeline flush rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets-warmup-precompile-prerender2-large-static-webgpu") {
    throw "Blocker experiment input list included standalone redundant setPipeline rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets-warmup-precompile-prerender2-large-static-webgpu") {
    throw "Blocker experiment input list included standalone redundant setBindGroup rows even though the required-gate WebGPU blocker is large-static."
  }
  if ($InputList -match "\\benchmarks\\raw\\\*\.json") {
    throw "Blocker experiment input list used a broad post-run analysis glob instead of scoped current-run result files."
  }

  $ManifestPath = Join-Path $TempDir "targeted-plan.json"
  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Blocker experiment plan did not write the targeted plan manifest: $ManifestPath"
  }
  $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  if ($Manifest.dry_run -ne $true -or $Manifest.phase -ne "planned") {
    throw "Targeted plan manifest did not record dry-run planned phase."
  }
  if ($Manifest.options.precompile -ne $true -or [int]$Manifest.options.prerender_frames -ne 2) {
    throw "Targeted plan manifest did not record matched resource-warmup options."
  }
  if ([string]$Manifest.options.resource_warmup_label_suffix -ne "-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not record the resource-warmup label suffix."
  }
  if ($Manifest.options.include_all_blocker_diagnostics -ne $false) {
    throw "Targeted plan manifest did not record focused required-gate blocker planning."
  }
  if ($Manifest.options.include_severe_blocker_diagnostics -ne $true -or [double]$Manifest.options.severe_blocker_fps_regression_pct -ne 20.0) {
    throw "Targeted plan manifest did not record default severe blocker expansion settings."
  }
  if ($Manifest.options.include_cpu_overhead_blocker_diagnostics -ne $true) {
    throw "Targeted plan manifest did not record CPU/render-submission blocker expansion settings."
  }
  if ($Manifest.options.plan_suite_promotion_after_triage -ne $true) {
    throw "Targeted plan manifest did not record suite-promotion planning enablement."
  }
  if ([string]$Manifest.options.webgpu_profile_cache_key -ne "dryrun-targeted-webgpu-cache" -or [string]$Manifest.options.webgpu_profile_cache_mode -ne "explicit-reuse") {
    throw "Targeted plan manifest did not record WebGPU profile-cache key/mode."
  }
  if ([string]$Manifest.options.profile_cache_root -notmatch "targeted-profile-cache") {
    throw "Targeted plan manifest did not record the WebGPU profile-cache root."
  }
  if ($Manifest.options.prime_webgpu_profile_cache -ne $true -or [string]$Manifest.options.profile_cache_prime_policy -ne "prime-before-measured-run") {
    throw "Targeted plan manifest did not record WebGPU profile-cache priming policy."
  }
  if ([string]$Manifest.options.profile_cache_policy -ne "same-profile-cache-mode-and-key" -or [string]$Manifest.post_run_analysis.profile_cache_compatibility_policy -ne "same-profile-cache-mode-and-key") {
    throw "Targeted plan manifest did not record profile-cache compatibility policy."
  }
  if ([double]$Manifest.post_run_analysis.dropped_frames_regression -ne 0.0) {
    throw "Targeted plan manifest did not record the dropped-frame regression threshold."
  }
  if ([double]$Manifest.post_run_analysis.cpu_frame_regression_ms -ne 0.5 -or
      [double]$Manifest.post_run_analysis.render_submission_regression_ms -ne 0.5) {
    throw "Targeted plan manifest did not record CPU/render-submission regression thresholds."
  }
  if ([double]$Manifest.post_run_analysis.pipeline_create_regression_ms -ne 1.0) {
    throw "Targeted plan manifest did not record the WebGPU pipeline-create regression threshold."
  }
  if ($Manifest.targeted_trace.enabled -ne $true -or [string]$Manifest.targeted_trace.renderer -ne "webgpu") {
    throw "Targeted plan manifest did not record targeted WebGPU trace capture enablement."
  }
  if ([int]$Manifest.targeted_trace.duration -ne 1 -or [int]$Manifest.targeted_trace.warmup -ne 1 -or [int]$Manifest.targeted_trace.start_delay_ms -ne 1234) {
    throw "Targeted plan manifest did not record targeted trace timing options."
  }
  if ($Manifest.targeted_trace.queue_instrumentation -ne $true -or $Manifest.targeted_trace.bind_group_instrumentation -ne $true -or $Manifest.targeted_trace.pipeline_state_instrumentation -ne $true -or $Manifest.targeted_trace.buffer_state_instrumentation -ne $true -or $Manifest.targeted_trace.render_state_instrumentation -ne $true -or $Manifest.targeted_trace.immediate_instrumentation -ne $true -or $Manifest.targeted_trace.reject_webgpu_cpu_fallback -ne $true -or $Manifest.targeted_trace.viewer_trace_webgpu_queue -ne $true) {
    throw "Targeted plan manifest did not record targeted trace diagnostic flags."
  }
  if (@($Manifest.targeted_trace.trace_files).Count -ne 2) {
    throw "Targeted plan manifest did not record the expected baseline/fork targeted trace artifacts."
  }
  if (-not (@($Manifest.targeted_trace.trace_files) | Where-Object { [string]$_.label -match "baseline-content-shell-targeted-blocker-webgpu-trace-warmup-precompile-prerender2" -and [string]$_.scene -eq "large-static" })) {
    throw "Targeted plan manifest did not record the baseline targeted trace artifact."
  }
  if (-not (@($Manifest.targeted_trace.trace_files) | Where-Object { [string]$_.label -match "fork-viewer-default-targeted-blocker-webgpu-trace-warmup-precompile-prerender2" -and [string]$_.scene -eq "large-static" })) {
    throw "Targeted plan manifest did not record the fork targeted trace artifact."
  }
  if (@($Manifest.options.webgl_angle_backend) -notcontains "d3d11") {
    throw "Targeted plan manifest did not record the WebGL2 ANGLE backend experiments."
  }
  if (@($Manifest.experiment_labels.webgl2) -notcontains "fork-viewer-exp-relaxed-webgl-validation-zero-copy-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGL2 experiment labels for resource-warmup output files."
  }
  if (@($Manifest.experiment_labels.webgl2) -notcontains "fork-viewer-exp-angle-d3d11-zero-copy-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGL2 D3D11 zero-copy interaction labels."
  }
  if (@($Manifest.experiment_labels.webgl2) -notcontains "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGL2 D3D11 relaxed zero-copy interaction labels."
  }
  if (@($Manifest.experiment_labels.webgl2) -notcontains "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGL2 frame-pacing labels."
  }
  if (@($Manifest.base_experiment_labels.webgl2) -notcontains "fork-viewer-exp-relaxed-webgl-validation-zero-copy") {
    throw "Targeted plan manifest did not retain WebGL2 base experiment labels."
  }
  if (@($Manifest.base_experiment_labels.webgl2) -notcontains "fork-viewer-exp-angle-d3d11-zero-copy") {
    throw "Targeted plan manifest did not retain WebGL2 D3D11 zero-copy base labels."
  }
  if (@($Manifest.base_experiment_labels.webgl2) -notcontains "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy") {
    throw "Targeted plan manifest did not retain WebGL2 D3D11 relaxed zero-copy base labels."
  }
  if (@($Manifest.base_experiment_labels.webgl2) -notcontains "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync") {
    throw "Targeted plan manifest did not retain WebGL2 frame-pacing base labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU D3D11 DXC/flush/fence/clear-skip interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU async pipeline flush deferral interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU redundant setPipeline skip interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU redundant setBindGroup skip interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU frame-pacing labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d12-toggles-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU D3D12 toggle labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-discard-view-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU D3D11 DiscardView labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU D3D11 DXC/IPC/HLSL/range-analysis interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included texture-upload labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included copyExternalImage upload-only labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included copyExternalImage color-conversion upload-only labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included copyExternalImage color-space upload-only labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included copyExternalImage source upload-only labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included copyExternalImage copy-size upload-only labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included copyExternalImage combined upload-only labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included aggressive upload labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-defer-queue-flush-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included standalone queue-flush labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-defer-pipeline-flush-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included standalone async pipeline flush labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included standalone redundant setPipeline labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets-warmup-precompile-prerender2") {
    throw "Targeted plan manifest included standalone redundant setBindGroup labels even though the required-gate WebGPU blocker is large-static."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU queue-flush deferral interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU submit-flush deferral interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU canvas validation skip interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU canvas memory-accounting skip interaction labels."
  }
  if (@($Manifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters-warmup-precompile-prerender2") {
    throw "Targeted plan manifest did not suffix WebGPU use-counter skip interaction labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-dawn-use-dxc") {
    throw "Targeted plan manifest did not retain WebGPU Dawn DXC base labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-disable-range-analysis") {
    throw "Targeted plan manifest did not retain WebGPU robustness range-analysis disable base labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -notcontains "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync") {
    throw "Targeted plan manifest did not retain WebGPU frame-pacing base labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d12-toggles") {
    throw "Targeted plan manifest did not retain WebGPU D3D12 toggle base labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-discard-view") {
    throw "Targeted plan manifest did not retain WebGPU D3D11 DiscardView base labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range") {
    throw "Targeted plan manifest did not retain WebGPU D3D11 DXC/IPC/HLSL/range-analysis interaction base labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets") {
    throw "Targeted plan manifest did not retain WebGPU redundant setPipeline interaction base labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets") {
    throw "Targeted plan manifest did not retain WebGPU redundant setBindGroup interaction base labels."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment") {
    throw "Targeted plan manifest did not keep WebGPU labels focused to the required-gate blocker scene class."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "Targeted plan manifest did not keep WebGPU copyExternalImage labels focused to texture-upload blocker scenes."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion") {
    throw "Targeted plan manifest did not keep WebGPU copyExternalImage color-conversion labels focused to texture-upload blocker scenes."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation") {
    throw "Targeted plan manifest did not keep WebGPU copyExternalImage color-space labels focused to texture-upload blocker scenes."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation") {
    throw "Targeted plan manifest did not keep WebGPU copyExternalImage source labels focused to texture-upload blocker scenes."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation") {
    throw "Targeted plan manifest did not keep WebGPU copyExternalImage copy-size labels focused to texture-upload blocker scenes."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path") {
    throw "Targeted plan manifest did not keep WebGPU copyExternalImage combined fast-path labels focused to texture-upload blocker scenes."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") {
    throw "Targeted plan manifest did not keep WebGPU aggressive upload labels focused to texture-upload blocker scenes."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-defer-queue-flush") {
    throw "Targeted plan manifest did not keep standalone queue-flush labels focused to the required-gate blocker scene class."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-defer-pipeline-flush") {
    throw "Targeted plan manifest did not keep standalone async pipeline flush labels focused to the required-gate blocker scene class."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets") {
    throw "Targeted plan manifest did not keep standalone redundant setPipeline labels focused to the required-gate blocker scene class."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets") {
    throw "Targeted plan manifest did not keep standalone redundant setBindGroup labels focused to the required-gate blocker scene class."
  }
  if (@($Manifest.base_experiment_labels.webgpu) -contains "fork-viewer-exp-webgpu-dawn-skip-validation") {
    throw "Targeted plan manifest did not keep WebGPU experiment labels focused to the blocker scene classes."
  }
  if ([double]$Manifest.post_run_analysis.scene_regression_pct -ne 0.5) {
    throw "Targeted plan manifest did not record the post-run scene-throughput regression threshold."
  }
  if ([string]$Manifest.post_run_analysis.triage_output -ne $PostRunTriageOutput) {
    throw "Targeted plan manifest did not record the post-run blocker triage report output."
  }
  if ([string]$Manifest.post_run_analysis.triage_json -ne $PostRunTriageJson) {
    throw "Targeted plan manifest did not record the post-run blocker triage JSON output."
  }
  if ([int]$Manifest.post_run_analysis.triage_min_scenes -ne 1) {
    throw "Targeted plan manifest did not record the post-run blocker triage one-scene gate."
  }
  if ([double]$Manifest.post_run_analysis.min_avg_fps_delta_pct -ne 0.5) {
    throw "Targeted plan manifest did not record the post-run minimum retained speedup threshold."
  }
  if ([string]$Manifest.post_run_analysis.build_args_compatibility_policy -ne "same-build-args-hash") {
    throw "Targeted plan manifest did not record the post-run same-build-args compatibility policy."
  }
  if ([string]$Manifest.post_run_analysis.environment_compatibility_policy -ne "same-platform-driver-gpu-device") {
    throw "Targeted plan manifest did not record the post-run same-platform/driver/GPU compatibility policy."
  }
  if ([string]$Manifest.post_run_analysis.webgpu_pipeline_instrumentation_compatibility_policy -ne "same-webgpu-pipeline-instrumentation-mode") {
    throw "Targeted plan manifest did not record the post-run WebGPU pipeline-instrumentation compatibility policy."
  }
  if ([string]$Manifest.post_run_analysis.baseline_selection_policy -ne "fastest-compatible-baseline") {
    throw "Targeted plan manifest did not record the post-run fastest-compatible-baseline policy."
  }
  if ($Manifest.post_run_analysis.require_checkout -ne $true) {
    throw "Targeted plan manifest did not record the post-run checkout-built browser requirement."
  }
  if (@($Manifest.post_run_analysis.required_scenes).Count -ne 7 -or
      @($Manifest.post_run_analysis.required_scenes) -notcontains "many-draw-calls" -or
      @($Manifest.post_run_analysis.required_scenes) -notcontains "gltf-loader-stress") {
    throw "Targeted plan manifest did not record the post-run required scene set."
  }
  if (@($Manifest.planned_scenes.webgl2).Count -ne 7) {
    throw "Targeted plan manifest did not record WebGL2 needs-suite expansion scenes."
  }
  if (@($Manifest.planned_scenes.webgpu).Count -ne 1 -or @($Manifest.planned_scenes.webgpu) -notcontains "large-static") {
    throw "Targeted plan manifest did not record the required-gate focused WebGPU blocker scene."
  }
  if (@($Manifest.active_blocker_diagnostics).Count -ne 3) {
    throw "Targeted plan manifest did not record the active required-gate and blocked-tail diagnostics."
  }
  if (-not (@($Manifest.active_blocker_diagnostics) | Where-Object { [string]$_.status -eq "blocked-tail" -and [string]$_.scene -eq "postprocessing" })) {
    throw "Targeted plan manifest did not keep same-renderer blocked-tail diagnostics active."
  }
  if ($Manifest.needs_suite_expansion.webgl2 -ne $true -or $Manifest.needs_suite_expansion.webgpu -ne $false) {
    throw "Targeted plan manifest did not record needs-suite expansion state."
  }
  if ([int]$Manifest.post_run_analysis.generated_input_count -le 0) {
    throw "Targeted plan manifest did not record generated post-run input count."
  }
  if ($Manifest.suite_promotion.enabled -ne $true -or
      [string]$Manifest.suite_promotion.output -ne ".\benchmarks\reports\targeted-suite-promotion-analysis.md" -or
      [string]$Manifest.suite_promotion.json -ne ".\benchmarks\reports\targeted-suite-promotion-analysis.json") {
    throw "Targeted plan manifest did not record suite-promotion analysis outputs."
  }
  if (@($Manifest.steps).Count -lt 5) {
    throw "Targeted plan manifest did not record the expected command steps."
  }
  if (@($Manifest.steps | Where-Object { $_.name -eq "post-run suite promotion planning" }).Count -ne 1) {
    throw "Targeted plan manifest did not record the suite-promotion planning command step."
  }
  if (-not (Test-Path -LiteralPath $PostRunTriageJson -PathType Leaf)) {
    throw "Dry-run blocker plan did not write the suite-promotion triage placeholder JSON."
  }
  if (-not (Test-Path -LiteralPath $PostRunTriageOutput -PathType Leaf)) {
    throw "Dry-run blocker plan did not write the suite-promotion triage placeholder report."
  }
  $TriagePlaceholder = Get-Content -LiteralPath $PostRunTriageJson -Raw | ConvertFrom-Json
  if ($TriagePlaceholder.dry_run -ne $true -or [string]$TriagePlaceholder.phase -ne "planned") {
    throw "Dry-run triage placeholder did not record planned dry-run phase."
  }
  if (@($TriagePlaceholder.families).Count -ne 0) {
    throw "Dry-run triage placeholder should not contain measured candidate families."
  }
  if ($TriagePlaceholder.required_candidate_gate.ok -ne $false -or
      @($TriagePlaceholder.required_candidate_gate.required_renderers) -notcontains "webgl2" -or
      @($TriagePlaceholder.required_candidate_gate.required_renderers) -notcontains "webgpu") {
    throw "Dry-run triage placeholder did not record the required renderer gate."
  }
  if (-not (Test-Path -LiteralPath $PromotionPlanPath -PathType Leaf)) {
    throw "Dry-run blocker plan did not write the synchronized suite-promotion plan."
  }
  $PromotionPlan = Get-Content -LiteralPath $PromotionPlanPath -Raw | ConvertFrom-Json
  if ($PromotionPlan.dry_run -ne $true -or [string]$PromotionPlan.phase -ne "planned") {
    throw "Suite-promotion dry-run plan did not record planned dry-run phase."
  }
  if ([string]$PromotionPlan.fork_revision -ne [string]$Manifest.fork_revision -or
      [string]$PromotionPlan.chromium_revision -ne [string]$Manifest.chromium_revision) {
    throw "Suite-promotion dry-run plan did not stay synchronized with the targeted plan revision metadata."
  }
  if ([int]$PromotionPlan.generated_input_count -ne 0 -or @($PromotionPlan.steps).Count -ne 0) {
    throw "Suite-promotion dry-run plan should be a no-promotion handoff when the dry-run triage placeholder has no families."
  }
  if ([string]$PromotionPlan.triage_analysis_json -ne [System.IO.Path]::GetFullPath($PostRunTriageJson) -or
      [string]$PromotionPlan.targeted_plan_manifest -ne [System.IO.Path]::GetFullPath($ManifestPath)) {
    throw "Suite-promotion dry-run plan did not reference the synchronized triage and targeted-plan handoff files."
  }
  if (-not (Test-Path -LiteralPath $PromotionInputListPath -PathType Leaf)) {
    throw "Suite-promotion dry-run plan did not write the scoped promotion input list."
  }

  $AllDiagnosticsOutput = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $AnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -DisableWebGpuTiming `
    -AnalyzeAfterRun `
    -PostRunAnalysisInputList (Join-Path $TempDir "all-post-run-inputs.txt") `
    -TargetedPlanManifest (Join-Path $TempDir "all-targeted-plan.json") `
    -PostRunAnalysisMinMeasuredSeconds 1 `
    -RequireCandidateRenderer "webgl2,webgpu" `
    -RunComparableBaselines `
    -IncludeAllBlockerDiagnostics `
    -DryRun *>&1
  $AllDiagnosticsText = ($AllDiagnosticsOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $AllDiagnosticsText "-Scenes\s+large-static\b" "all-diagnostics WebGPU large-static blocker scene group"
  Assert-Matches $AllDiagnosticsText "-Scenes\s+texture-streaming\b" "all-diagnostics WebGPU texture-streaming blocker scene group"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment\b" "all-diagnostics texture upload label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-disable-range-analysis\b" "all-diagnostics WebGPU range-analysis disable label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-disable-frame-rate-limit-gpu-vsync\b" "all-diagnostics frame-pacing label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion\b" "all-diagnostics WebGPU copyExternalImage color-conversion setup skip label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation\b" "all-diagnostics WebGPU copyExternalImage color-space validation skip label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation\b" "all-diagnostics WebGPU copyExternalImage destination validation skip label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-source-validation\b" "all-diagnostics WebGPU copyExternalImage source validation skip label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation\b" "all-diagnostics WebGPU copyExternalImage copy-size validation skip label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path\b" "all-diagnostics WebGPU copyExternalImage combined fast-path label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-color-conv\b" "all-diagnostics WebGPU D3D11 copyExternalImage color-conversion setup skip interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-colorspace\b" "all-diagnostics WebGPU D3D11 copyExternalImage color-space validation skip interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-validation\b" "all-diagnostics WebGPU D3D11 copyExternalImage destination validation skip interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-source\b" "all-diagnostics WebGPU D3D11 copyExternalImage source validation skip interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-copy-size\b" "all-diagnostics WebGPU D3D11 copyExternalImage copy-size validation skip interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-copy-ext-image-fast-path\b" "all-diagnostics WebGPU D3D11 copyExternalImage combined fast-path interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path\b" "all-diagnostics WebGPU aggressive D3D11 upload fast-path label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush\b" "all-diagnostics WebGPU async pipeline flush deferral interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts\b" "all-diagnostics WebGPU bind-group-layout cache interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels\b" "all-diagnostics WebGPU command-label skip interaction label filter handoff"
  Assert-Matches $AllDiagnosticsText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels\b" "all-diagnostics WebGPU resource-label skip interaction label filter handoff"
  $AllDiagnosticsManifest = Get-Content -LiteralPath (Join-Path $TempDir "all-targeted-plan.json") -Raw | ConvertFrom-Json
  if ($AllDiagnosticsManifest.options.include_all_blocker_diagnostics -ne $true) {
    throw "All-diagnostics targeted plan manifest did not record IncludeAllBlockerDiagnostics."
  }
  if (@($AllDiagnosticsManifest.active_blocker_diagnostics).Count -ne 4) {
    throw "All-diagnostics targeted plan did not include every blocker diagnostic as active."
  }
  if (@($AllDiagnosticsManifest.planned_scenes.webgpu).Count -ne 2) {
    throw "All-diagnostics targeted plan did not include both WebGPU blocker scenes."
  }
  if (@($AllDiagnosticsManifest.scene_label_groups.webgpu).Count -ne 2) {
    throw "All-diagnostics targeted plan did not split WebGPU blockers into scene-label groups."
  }
  $AllLargeGroup = @($AllDiagnosticsManifest.scene_label_groups.webgpu | Where-Object { @($_.scenes) -contains "large-static" })
  $AllTextureGroup = @($AllDiagnosticsManifest.scene_label_groups.webgpu | Where-Object { @($_.scenes) -contains "texture-streaming" })
  if ($AllLargeGroup.Count -ne 1 -or $AllTextureGroup.Count -ne 1) {
    throw "All-diagnostics targeted plan did not record separate large-static and texture-streaming WebGPU scene-label groups."
  }
  if (@($AllLargeGroup[0].base_experiment_labels) -contains "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "All-diagnostics large-static WebGPU scene-label group included texture-upload labels."
  }
  if (@($AllTextureGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "All-diagnostics texture-streaming WebGPU scene-label group did not include texture-upload labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage destination validation skip labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage color-conversion setup skip labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage color-space validation skip labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage source validation skip labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage copy-size validation skip labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage combined fast-path labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-validation") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage destination validation skip interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-color-conv") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage color-conversion setup skip interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-colorspace") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage color-space validation skip interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-source") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage source validation skip interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-copy-size") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage copy-size validation skip interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-copy-ext-image-fast-path") {
    throw "All-diagnostics targeted plan did not include WebGPU copyExternalImage combined fast-path interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") {
    throw "All-diagnostics targeted plan did not include WebGPU aggressive D3D11 upload fast-path labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush") {
    throw "All-diagnostics targeted plan did not include WebGPU async pipeline flush deferral interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts") {
    throw "All-diagnostics targeted plan did not include WebGPU bind-group-layout cache interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels") {
    throw "All-diagnostics targeted plan did not include WebGPU command-label skip interaction labels."
  }
  if (@($AllDiagnosticsManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels") {
    throw "All-diagnostics targeted plan did not include WebGPU resource-label skip interaction labels."
  }

  $DrawCallAnalysisPath = Join-Path $TempDir "candidate-analysis-gltf.json"
  $DrawCallAnalysis = [pscustomobject]@{
    required_candidate_gate = [pscustomobject]@{
      renderers = @(
        [pscustomobject]@{
          renderer = "webgpu"
          ok = $false
          best_status = "blocked-throughput"
          best_candidate_family = "fork-webgpu-default"
          best_baseline_family = "baseline-webgpu"
        }
      )
    }
    blocker_diagnostics = @(
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "blocked-throughput"; scene = "gltf-loader-stress"; candidate_family = "fork-webgpu-default"; primary_blocker = "avg FPS -1.20%" }
    )
  }
  $DrawCallAnalysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DrawCallAnalysisPath -Encoding UTF8

  $DrawCallOutput = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $DrawCallAnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -DisableWebGpuTiming `
    -AnalyzeAfterRun `
    -PostRunAnalysisInputList (Join-Path $TempDir "gltf-post-run-inputs.txt") `
    -TargetedPlanManifest (Join-Path $TempDir "gltf-targeted-plan.json") `
    -PostRunAnalysisMinMeasuredSeconds 1 `
    -RequireCandidateRenderer "webgpu" `
    -RunComparableBaselines `
    -DryRun *>&1
  $DrawCallText = ($DrawCallOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $DrawCallText "-Scenes\s+gltf-loader-stress\b" "draw-call/glTF WebGPU blocker scene"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-dawn-skip-validation\b" "draw-call/glTF standalone Dawn skip-validation label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-dawn-disable-robustness\b" "draw-call/glTF standalone Dawn disable-robustness label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-skip-validation\b" "draw-call/glTF D3D11 skip-validation interaction label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-disable-robustness\b" "draw-call/glTF D3D11 disable-robustness interaction label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-skip-validation-disable-robustness\b" "draw-call/glTF D3D11 skip-validation plus disable-robustness interaction label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-canvas-texture-validation\b" "draw-call/glTF WebGPU canvas validation skip label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-canvas-memory-accounting\b" "draw-call/glTF WebGPU canvas memory-accounting skip label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-use-counters\b" "draw-call/glTF WebGPU use-counter skip label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-dawn-use-dxc\b" "draw-call/glTF Dawn DXC shader compiler label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-hlsl2021\b" "draw-call/glTF HLSL 2021 shader-codegen label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-disable-range-analysis\b" "draw-call/glTF WebGPU range-analysis disable label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-disable-frame-rate-limit-gpu-vsync\b" "draw-call/glTF frame-pacing label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-defer-pipeline-flush\b" "draw-call/glTF WebGPU async pipeline flush deferral label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-cache-bind-group-layouts\b" "draw-call/glTF WebGPU bind-group-layout cache label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-command-labels\b" "draw-call/glTF WebGPU command-label skip label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-resource-labels\b" "draw-call/glTF WebGPU resource-label skip label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path\b" "draw-call/glTF aggressive D3D11 pipeline fast-path label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip\b" "draw-call/glTF D3D11 DXC/flush/fence/clear-skip interaction label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush\b" "draw-call/glTF D3D11 DXC plus async pipeline flush interaction label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts\b" "draw-call/glTF D3D11 DXC plus bind-group-layout cache interaction label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels\b" "draw-call/glTF D3D11 DXC plus command-label skip interaction label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels\b" "draw-call/glTF D3D11 DXC plus resource-label skip interaction label filter"
  Assert-Matches $DrawCallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush\b" "draw-call/glTF D3D11 DXC plus submit-flush interaction label filter"
  if ($DrawCallText -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment") {
    throw "Draw-call/glTF blocker plan scheduled texture-upload rows."
  }
  if ($DrawCallText -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "Draw-call/glTF blocker plan scheduled copyExternalImage upload-only rows."
  }
  if ($DrawCallText -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion") {
    throw "Draw-call/glTF blocker plan scheduled copyExternalImage color-conversion upload-only rows."
  }
  if ($DrawCallText -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation") {
    throw "Draw-call/glTF blocker plan scheduled copyExternalImage color-space upload-only rows."
  }
  if ($DrawCallText -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-source-validation") {
    throw "Draw-call/glTF blocker plan scheduled copyExternalImage source upload-only rows."
  }
  if ($DrawCallText -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation") {
    throw "Draw-call/glTF blocker plan scheduled copyExternalImage copy-size upload-only rows."
  }
  if ($DrawCallText -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path") {
    throw "Draw-call/glTF blocker plan scheduled copyExternalImage combined upload-only rows."
  }
  if ($DrawCallText -match "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") {
    throw "Draw-call/glTF blocker plan scheduled the aggressive D3D11 upload fast-path."
  }

  $DrawCallInputList = Get-Content -LiteralPath (Join-Path $TempDir "gltf-post-run-inputs.txt") -Raw
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-skip-validation-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 skip-validation input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-disable-robustness-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 disable-robustness input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-skip-validation-disable-robustness-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 unsafe interaction input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-skip-canvas-memory-accounting-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU canvas memory-accounting skip input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-dawn-use-dxc-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU Dawn DXC input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-hlsl2021-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU HLSL 2021 input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-disable-range-analysis-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU range-analysis disable input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU frame-pacing input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-defer-pipeline-flush-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU async pipeline flush deferral input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-cache-bind-group-layouts-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU bind-group-layout cache input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-skip-command-labels-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU command-label skip input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-skip-resource-labels-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU resource-label skip input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU aggressive D3D11 pipeline fast-path input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 DXC/flush/fence/clear-skip input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 DXC async pipeline flush input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 DXC bind-group-layout cache input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 DXC command-label skip input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 DXC resource-label skip input"
  Assert-Matches $DrawCallInputList "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush-gltf-loader-stress-webgpu\.json" "post-run scoped WebGPU D3D11 DXC submit-flush input"
  $DrawCallManifest = Get-Content -LiteralPath (Join-Path $TempDir "gltf-targeted-plan.json") -Raw | ConvertFrom-Json
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-skip-validation") {
    throw "Draw-call/glTF targeted plan manifest did not include D3D11 skip-validation interaction labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-disable-robustness") {
    throw "Draw-call/glTF targeted plan manifest did not include D3D11 disable-robustness interaction labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-skip-validation-disable-robustness") {
    throw "Draw-call/glTF targeted plan manifest did not include D3D11 skip-validation plus disable-robustness interaction labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-skip-canvas-memory-accounting") {
    throw "Draw-call/glTF targeted plan manifest did not include WebGPU canvas memory-accounting skip labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-dawn-use-dxc") {
    throw "Draw-call/glTF targeted plan manifest did not include Dawn DXC labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-hlsl2021") {
    throw "Draw-call/glTF targeted plan manifest did not include HLSL 2021 labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-disable-range-analysis") {
    throw "Draw-call/glTF targeted plan manifest did not include WebGPU range-analysis disable labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync") {
    throw "Draw-call/glTF targeted plan manifest did not include frame-pacing labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-defer-pipeline-flush") {
    throw "Draw-call/glTF targeted plan manifest did not include async pipeline flush deferral labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-cache-bind-group-layouts") {
    throw "Draw-call/glTF targeted plan manifest did not include bind-group-layout cache labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-skip-command-labels") {
    throw "Draw-call/glTF targeted plan manifest did not include command-label skip labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-skip-resource-labels") {
    throw "Draw-call/glTF targeted plan manifest did not include resource-label skip labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path") {
    throw "Draw-call/glTF targeted plan manifest did not include aggressive D3D11 pipeline fast-path labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip") {
    throw "Draw-call/glTF targeted plan manifest did not include D3D11 DXC/flush/fence/clear-skip labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush") {
    throw "Draw-call/glTF targeted plan manifest did not include D3D11 DXC async pipeline flush interaction labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts") {
    throw "Draw-call/glTF targeted plan manifest did not include D3D11 DXC bind-group-layout cache interaction labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels") {
    throw "Draw-call/glTF targeted plan manifest did not include D3D11 DXC command-label skip interaction labels."
  }
  if (@($DrawCallManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels") {
    throw "Draw-call/glTF targeted plan manifest did not include D3D11 DXC resource-label skip interaction labels."
  }

  $SevereAnalysisPath = Join-Path $TempDir "candidate-analysis-severe.json"
  $SevereAnalysis = [pscustomobject]@{
    required_candidate_gate = [pscustomobject]@{
      renderers = @(
        [pscustomobject]@{
          renderer = "webgpu"
          ok = $false
          best_status = "blocked-throughput"
          best_candidate_family = "fork-webgpu-default"
          best_baseline_family = "baseline-webgpu"
        }
      )
    }
    blocker_diagnostics = @(
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "blocked-throughput"; scene = "gltf-loader-stress"; candidate_family = "fork-webgpu-default"; primary_blocker = "avg FPS -1.20%"; avg_fps_delta_pct = -1.2 },
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-official-webgpu"; status = "not useful"; scene = "large-static"; candidate_family = "fork-viewer-default-webgpu"; primary_blocker = "avg FPS -57.29%"; avg_fps_delta_pct = -57.29 },
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "not useful"; scene = "texture-streaming"; candidate_family = "fork-webgpu-single-process"; primary_blocker = "avg FPS -18.40%"; avg_fps_delta_pct = -18.4 }
    )
  }
  $SevereAnalysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SevereAnalysisPath -Encoding UTF8

  $SevereOutput = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $SevereAnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -DisableWebGpuTiming `
    -AnalyzeAfterRun `
    -PostRunAnalysisInputList (Join-Path $TempDir "severe-post-run-inputs.txt") `
    -TargetedPlanManifest (Join-Path $TempDir "severe-targeted-plan.json") `
    -PostRunAnalysisMinMeasuredSeconds 1 `
    -RequireCandidateRenderer "webgpu" `
    -RunComparableBaselines `
    -DryRun *>&1
  $SevereText = ($SevereOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $SevereText "-Scenes\s+gltf-loader-stress\b" "default severe-blocker expansion WebGPU glTF scene group"
  Assert-Matches $SevereText "-Scenes\s+large-static\b" "default severe-blocker expansion WebGPU large-static scene group"
  Assert-Matches $SevereText "-Scenes\s+texture-streaming\b" "default WebGPU upload-blocker texture-streaming scene group"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path\b" "severe expansion preserves glTF aggressive pipeline labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-cache-bind-group-layouts\b" "severe expansion adds standalone bind-group-layout cache labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-command-labels\b" "severe expansion adds standalone command-label skip labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-resource-labels\b" "severe expansion adds standalone resource-label skip labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d12-toggles\b" "severe expansion adds large-pass pipeline/backend labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush\b" "severe expansion adds async pipeline flush deferral interaction labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts\b" "severe expansion adds bind-group-layout cache interaction labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels\b" "severe expansion adds command-label skip interaction labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels\b" "severe expansion adds resource-label skip interaction labels"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation\b" "default WebGPU upload-blocker copyExternalImage label filter"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-disable-cpu-upload-buffers\b" "default WebGPU upload-blocker D3D11 CPU upload-buffer label filter"
  Assert-Matches $SevereText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path\b" "default WebGPU upload-blocker aggressive upload label filter"
  $SevereManifest = Get-Content -LiteralPath (Join-Path $TempDir "severe-targeted-plan.json") -Raw | ConvertFrom-Json
  if (@($SevereManifest.active_blocker_diagnostics).Count -ne 3) {
    throw "Default blocker expansion did not keep the required-gate row, one severe same-renderer blocker, and the WebGPU texture-upload blocker."
  }
  if (@($SevereManifest.planned_scenes.webgpu).Count -ne 3 -or
      @($SevereManifest.planned_scenes.webgpu) -notcontains "gltf-loader-stress" -or
      @($SevereManifest.planned_scenes.webgpu) -notcontains "large-static" -or
      @($SevereManifest.planned_scenes.webgpu) -notcontains "texture-streaming") {
    throw "Severe blocker expansion did not plan the expected WebGPU scene set."
  }
  if ($SevereManifest.options.include_severe_blocker_diagnostics -ne $true -or [double]$SevereManifest.options.severe_blocker_fps_regression_pct -ne 20.0) {
    throw "Severe blocker expansion manifest did not record the default threshold."
  }
  if (@($SevereManifest.scene_label_groups.webgpu).Count -ne 3) {
    throw "Severe blocker expansion did not split WebGPU blockers into separate scene-label groups."
  }
  $SevereGltfGroup = @($SevereManifest.scene_label_groups.webgpu | Where-Object { @($_.scenes) -contains "gltf-loader-stress" })
  $SevereLargeGroup = @($SevereManifest.scene_label_groups.webgpu | Where-Object { @($_.scenes) -contains "large-static" })
  $SevereTextureGroup = @($SevereManifest.scene_label_groups.webgpu | Where-Object { @($_.scenes) -contains "texture-streaming" })
  if ($SevereGltfGroup.Count -ne 1 -or $SevereLargeGroup.Count -ne 1 -or $SevereTextureGroup.Count -ne 1) {
    throw "Severe blocker expansion did not record separate glTF, large-static, and texture-streaming WebGPU scene-label groups."
  }
  if (@($SevereGltfGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path") {
    throw "Severe glTF WebGPU scene-label group did not include the aggressive D3D11 pipeline fast-path label."
  }
  if (@($SevereGltfGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-defer-pipeline-flush") {
    throw "Severe glTF WebGPU scene-label group did not include the standalone async pipeline flush label."
  }
  if (@($SevereGltfGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-cache-bind-group-layouts") {
    throw "Severe glTF WebGPU scene-label group did not include the standalone bind-group-layout cache label."
  }
  if (@($SevereGltfGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-skip-command-labels") {
    throw "Severe glTF WebGPU scene-label group did not include the standalone command-label skip label."
  }
  if (@($SevereGltfGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-skip-resource-labels") {
    throw "Severe glTF WebGPU scene-label group did not include the standalone resource-label skip label."
  }
  if (@($SevereLargeGroup[0].base_experiment_labels) -contains "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path") {
    throw "Severe large-static WebGPU scene-label group included glTF/draw-call-only aggressive pipeline labels."
  }
  if (@($SevereLargeGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d12-toggles") {
    throw "Severe large-static WebGPU scene-label group did not include large-pass pipeline/backend labels."
  }
  if (@($SevereLargeGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush") {
    throw "Severe large-static WebGPU scene-label group did not include async pipeline flush deferral interaction labels."
  }
  if (@($SevereLargeGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts") {
    throw "Severe large-static WebGPU scene-label group did not include bind-group-layout cache interaction labels."
  }
  if (@($SevereLargeGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels") {
    throw "Severe large-static WebGPU scene-label group did not include command-label skip interaction labels."
  }
  if (@($SevereLargeGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels") {
    throw "Severe large-static WebGPU scene-label group did not include resource-label skip interaction labels."
  }
  if (@($SevereTextureGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "Default texture-streaming WebGPU scene-label group did not include copyExternalImage upload labels."
  }
  if (@($SevereTextureGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d11-disable-cpu-upload-buffers") {
    throw "Default texture-streaming WebGPU scene-label group did not include D3D11 upload-path labels."
  }
  if (@($SevereTextureGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") {
    throw "Default texture-streaming WebGPU scene-label group did not include the aggressive D3D11 upload fast-path."
  }

  $TailAnalysisPath = Join-Path $TempDir "candidate-analysis-tail.json"
  $TailAnalysis = [pscustomobject]@{
    required_candidate_gate = [pscustomobject]@{
      renderers = @(
        [pscustomobject]@{
          renderer = "webgpu"
          ok = $false
          best_status = "blocked-throughput"
          best_candidate_family = "fork-webgpu-default"
          best_baseline_family = "baseline-webgpu"
        }
      )
    }
    blocker_diagnostics = @(
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "blocked-throughput"; scene = "gltf-loader-stress"; candidate_family = "fork-webgpu-default"; primary_blocker = "avg FPS -1.20%"; avg_fps_delta_pct = -1.2 },
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "blocked-tail"; scene = "texture-streaming"; candidate_family = "fork-webgpu-tail-candidate"; primary_blocker = "p99 8.00 ms"; avg_fps_delta_pct = 0.8; p99_frame_ms_delta = 8.0 },
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "not useful"; scene = "postprocessing"; candidate_family = "fork-webgpu-not-useful-tail"; primary_blocker = "p99 12.00 ms"; avg_fps_delta_pct = -2.0; p99_frame_ms_delta = 12.0 }
    )
  }
  $TailAnalysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $TailAnalysisPath -Encoding UTF8

  $TailOutput = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $TailAnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -DisableWebGpuTiming `
    -AnalyzeAfterRun `
    -PostRunAnalysisInputList (Join-Path $TempDir "tail-post-run-inputs.txt") `
    -TargetedPlanManifest (Join-Path $TempDir "tail-targeted-plan.json") `
    -PostRunAnalysisMinMeasuredSeconds 1 `
    -RequireCandidateRenderer "webgpu" `
    -RunComparableBaselines `
    -DryRun *>&1
  $TailText = ($TailOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $TailText "-Scenes\s+gltf-loader-stress\b" "tail expansion keeps required-gate WebGPU glTF blocker scene"
  Assert-Matches $TailText "-Scenes\s+texture-streaming\b" "tail expansion adds blocked-tail WebGPU texture-streaming scene"
  Assert-Matches $TailText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation\b" "tail expansion schedules texture-upload labels for texture-streaming blocker"
  Assert-Matches $TailText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path\b" "tail expansion schedules aggressive upload labels for texture-streaming blocker"
  if ($TailText -match "-Scenes\s+[^\r\n]*postprocessing") {
    throw "Tail blocker expansion included a not-useful tail regression instead of limiting expansion to blocked-tail candidates."
  }
  $TailManifest = Get-Content -LiteralPath (Join-Path $TempDir "tail-targeted-plan.json") -Raw | ConvertFrom-Json
  if (@($TailManifest.active_blocker_diagnostics).Count -ne 2) {
    throw "Tail blocker expansion did not keep the required-gate row plus one blocked-tail same-renderer candidate."
  }
  if (@($TailManifest.planned_scenes.webgpu).Count -ne 2 -or
      @($TailManifest.planned_scenes.webgpu) -notcontains "gltf-loader-stress" -or
      @($TailManifest.planned_scenes.webgpu) -notcontains "texture-streaming") {
    throw "Tail blocker expansion did not plan the expected WebGPU scene set."
  }
  if (@($TailManifest.planned_scenes.webgpu) -contains "postprocessing") {
    throw "Tail blocker expansion included a not-useful WebGPU tail diagnostic."
  }
  if ($TailManifest.options.include_tail_blocker_diagnostics -ne $true) {
    throw "Tail blocker expansion manifest did not record tail blocker expansion enablement."
  }
  $TailTextureGroup = @($TailManifest.scene_label_groups.webgpu | Where-Object { @($_.scenes) -contains "texture-streaming" })
  if ($TailTextureGroup.Count -ne 1) {
    throw "Tail blocker expansion did not record a texture-streaming WebGPU scene-label group."
  }
  if (@($TailTextureGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") {
    throw "Tail texture-streaming WebGPU scene-label group did not include texture-upload labels."
  }
  if (@($TailTextureGroup[0].base_experiment_labels) -notcontains "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") {
    throw "Tail texture-streaming WebGPU scene-label group did not include the aggressive D3D11 upload fast-path."
  }

  $WeakAnalysisPath = Join-Path $TempDir "candidate-analysis-weak.json"
  $WeakAnalysis = [pscustomobject]@{
    required_candidate_gate = [pscustomobject]@{
      renderers = @(
        [pscustomobject]@{
          renderer = "webgpu"
          ok = $false
          best_status = "weak-throughput"
          best_candidate_family = "fork-webgpu-weak"
          best_baseline_family = "baseline-webgpu"
        }
      )
    }
    blocker_diagnostics = @(
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "weak-throughput"; scene = "suite average"; candidate_family = "fork-webgpu-weak"; primary_blocker = "avg FPS 0.20% below required 0.50%" }
    )
  }
  $WeakAnalysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $WeakAnalysisPath -Encoding UTF8

  $WeakOutput = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $WeakAnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -DisableWebGpuTiming `
    -AnalyzeAfterRun `
    -PostRunAnalysisInputList (Join-Path $TempDir "weak-post-run-inputs.txt") `
    -TargetedPlanManifest (Join-Path $TempDir "weak-targeted-plan.json") `
    -PostRunAnalysisMinMeasuredSeconds 1 `
    -RequireCandidateRenderer "webgpu" `
    -RunComparableBaselines `
    -DryRun *>&1
  $WeakText = ($WeakOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $WeakText "targeted WebGPU needs-suite expansion matrix" "weak-throughput WebGPU full-suite expansion matrix"
  Assert-Matches $WeakText "-Scenes\s+many-draw-calls,instancing,shader-heavy,texture-streaming,postprocessing,large-static,gltf-loader-stress\b" "weak-throughput WebGPU full-suite scenes"
  if ($WeakText -match "-Scenes\s+suite average\b") {
    throw "Weak-throughput plan treated the suite-average diagnostic label as a scene."
  }
  $WeakManifest = Get-Content -LiteralPath (Join-Path $TempDir "weak-targeted-plan.json") -Raw | ConvertFrom-Json
  if ($WeakManifest.needs_suite_expansion.webgpu -ne $true) {
    throw "Weak-throughput targeted plan did not record WebGPU needs-suite expansion state."
  }
  if (@($WeakManifest.planned_scenes.webgpu).Count -ne 7) {
    throw "Weak-throughput targeted plan did not expand WebGPU to the full scene suite."
  }

  $ShaderStallAnalysisPath = Join-Path $TempDir "candidate-analysis-shader-stall.json"
  $ShaderStallAnalysis = [pscustomobject]@{
    required_candidate_gate = [pscustomobject]@{
      renderers = @(
        [pscustomobject]@{
          renderer = "webgpu"
          ok = $false
          best_status = "blocked-shader-stalls"
          best_candidate_family = "fork-webgpu-shader-stall"
          best_baseline_family = "baseline-webgpu"
        }
      )
    }
    blocker_diagnostics = @(
      [pscustomobject]@{
        renderer = "webgpu"
        baseline_family = "baseline-webgpu"
        status = "blocked-shader-stalls"
        scene = "shader-heavy"
        candidate_family = "fork-webgpu-shader-stall"
        primary_blocker = "shader compile events +3"
        shader_compile_events_delta = 3
      }
    )
  }
  $ShaderStallAnalysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ShaderStallAnalysisPath -Encoding UTF8

  $ShaderStallOutput = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $ShaderStallAnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -DisableWebGpuTiming `
    -TargetedPlanManifest (Join-Path $TempDir "shader-stall-targeted-plan.json") `
    -DryRun *>&1
  $ShaderStallText = ($ShaderStallOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $ShaderStallText "-Scenes\s+shader-heavy\b" "shader-stall focused WebGPU scene"
  Assert-Matches $ShaderStallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-dawn-use-dxc\b" "shader-stall Dawn DXC label filter"
  Assert-Matches $ShaderStallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation\b" "shader-stall blob-cache label filter"
  Assert-Matches $ShaderStallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush\b" "shader-stall async pipeline-flush interaction label filter"
  Assert-Matches $ShaderStallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts\b" "shader-stall bind-group-layout cache interaction label filter"
  Assert-Matches $ShaderStallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels\b" "shader-stall command-label skip interaction label filter"
  Assert-Matches $ShaderStallText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels\b" "shader-stall resource-label skip interaction label filter"
  $ShaderStallManifest = Get-Content -LiteralPath (Join-Path $TempDir "shader-stall-targeted-plan.json") -Raw | ConvertFrom-Json
  if (@($ShaderStallManifest.active_blocker_diagnostics | Where-Object { [string]$_.status -eq "blocked-shader-stalls" -and [string]$_.scene -eq "shader-heavy" }).Count -ne 1) {
    throw "Shader-stall targeted plan did not preserve the blocked-shader-stalls diagnostic."
  }

  $NoComparableAnalysisPath = Join-Path $TempDir "no-comparable-candidate-analysis.json"
  $NoComparableAnalysis = [pscustomobject]@{
    required_candidate_gate = [pscustomobject]@{
      renderers = @(
        [pscustomobject]@{
          renderer = "webgl2"
          ok = $false
          best_status = "missing"
          best_candidate_family = ""
          best_baseline_family = ""
        },
        [pscustomobject]@{
          renderer = "webgpu"
          ok = $false
          best_status = "missing"
          best_candidate_family = ""
          best_baseline_family = ""
        }
      )
    }
    blocker_diagnostics = @()
  }
  $NoComparableAnalysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $NoComparableAnalysisPath -Encoding UTF8
  $NoComparableOutput = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $NoComparableAnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -Precompile `
    -PrerenderFrames 2 `
    -SettleGpuAfterWarmup `
    -WebGpuPipelineQuietFrames 2 `
    -WebGpuPipelineQuietMaxFrames 12 `
    -DisableWebGpuTiming `
    -RunComparableBaselines `
    -AnalyzeAfterRun `
    -PostRunAnalysisMinMeasuredSeconds 1 `
    -PostRunAnalysisInputList (Join-Path $TempDir "no-comparable-inputs.txt") `
    -TargetedPlanManifest (Join-Path $TempDir "no-comparable-targeted-plan.json") `
    -RequireCandidateRenderer webgl2,webgpu `
    -DryRun *>&1
  $NoComparableText = ($NoComparableOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $NoComparableText "targeted WebGL2 needs-suite expansion matrix" "fallback WebGL2 full-suite expansion when current analysis has no comparable families"
  Assert-Matches $NoComparableText "targeted WebGPU needs-suite expansion matrix" "fallback WebGPU full-suite expansion when current analysis has no comparable families"
  Assert-Matches $NoComparableText "-Scenes\s+many-draw-calls,instancing,shader-heavy,texture-streaming,postprocessing,large-static,gltf-loader-stress\b" "fallback complete scene list"
  Assert-Matches $NoComparableText "-Label\s+baseline-content-shell-targeted-blocker-warmup-precompile-prerender2-settlegpu\b" "fallback WebGL2 baseline resource-warmup label without WebGPU pipeline-quiet suffix"
  Assert-Matches $NoComparableText "-LabelSuffix\s+-warmup-precompile-prerender2-settlegpu\b" "fallback WebGL2 trusted matrix resource-warmup suffix"
  Assert-Matches $NoComparableText "-Label\s+baseline-content-shell-targeted-blocker-webgpu-warmup-precompile-prerender2-settlegpu-pipelinequiet2\b" "fallback WebGPU baseline resource-warmup label with WebGPU pipeline-quiet suffix"
  Assert-Matches $NoComparableText "-LabelSuffix\s+-warmup-precompile-prerender2-settlegpu-pipelinequiet2\b" "fallback WebGPU trusted matrix resource-warmup suffix"
  if ($NoComparableText -match "baseline-content-shell-targeted-blocker-warmup-precompile-prerender2-settlegpu-pipelinequiet2") {
    throw "No-comparable fallback applied the WebGPU pipeline-quiet suffix to WebGL2 baseline labels."
  }
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path\b" "fallback full-suite WebGPU pipeline/submit fast-path probe"
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-cache-bind-group-layouts\b" "fallback full-suite WebGPU bind-group-layout cache probe"
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts\b" "fallback full-suite WebGPU D3D11 bind-group-layout cache interaction probe"
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-command-labels\b" "fallback full-suite WebGPU command-label skip probe"
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels\b" "fallback full-suite WebGPU D3D11 command-label skip interaction probe"
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-skip-resource-labels\b" "fallback full-suite WebGPU resource-label skip probe"
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels\b" "fallback full-suite WebGPU D3D11 resource-label skip interaction probe"
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path\b" "fallback full-suite WebGPU texture-upload fast-path probe"
  Assert-Matches $NoComparableText "-ExperimentLabelFilter\s+[^\r\n]*fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path\b" "fallback full-suite WebGPU copyExternalImage fast-path probe"
  Assert-Matches $NoComparableText "--requireCandidateRenderer\s+webgl2\b" "fallback post-run WebGL2 retained-speed gate"
  Assert-Matches $NoComparableText "--requireCandidateRenderer\s+webgpu\b" "fallback post-run WebGPU retained-speed gate"
  $NoComparableManifest = Get-Content -LiteralPath (Join-Path $TempDir "no-comparable-targeted-plan.json") -Raw | ConvertFrom-Json
  if (@($NoComparableManifest.active_blocker_diagnostics | Where-Object { [string]$_.status -eq "needs-suite" -and [string]$_.scene -eq "coverage 0/7" }).Count -ne 2) {
    throw "No-comparable fallback did not record synthetic needs-suite diagnostics for both required renderers."
  }
  if ($NoComparableManifest.needs_suite_expansion.webgl2 -ne $true -or $NoComparableManifest.needs_suite_expansion.webgpu -ne $true) {
    throw "No-comparable fallback did not record full-suite expansion for both renderers."
  }
  if (@($NoComparableManifest.planned_scenes.webgl2).Count -ne 7 -or @($NoComparableManifest.planned_scenes.webgpu).Count -ne 7) {
    throw "No-comparable fallback did not plan complete seven-scene WebGL2/WebGPU suites."
  }
  if ([string]$NoComparableManifest.options.resource_warmup_label_suffix -ne "-warmup-precompile-prerender2-settlegpu" -or
      [string]$NoComparableManifest.options.webgl2_resource_warmup_label_suffix -ne "-warmup-precompile-prerender2-settlegpu" -or
      [string]$NoComparableManifest.options.webgpu_resource_warmup_label_suffix -ne "-warmup-precompile-prerender2-settlegpu-pipelinequiet2") {
    throw "No-comparable fallback did not record renderer-specific resource-warmup suffixes."
  }
  if (@($NoComparableManifest.experiment_labels.webgl2 | Where-Object { [string]$_ -match "pipelinequiet2" }).Count -ne 0) {
    throw "No-comparable fallback contaminated WebGL2 experiment labels with WebGPU pipeline-quiet suffixes."
  }
  if (@($NoComparableManifest.experiment_labels.webgpu | Where-Object { [string]$_ -match "pipelinequiet2" }).Count -eq 0) {
    throw "No-comparable fallback did not apply the WebGPU pipeline-quiet suffix to WebGPU experiment labels."
  }
  $NoComparableInputList = Get-Content -LiteralPath (Join-Path $TempDir "no-comparable-inputs.txt") -Raw
  if ($NoComparableInputList -match "pipelinequiet2-[A-Za-z0-9-]+-webgl2\.json") {
    throw "No-comparable fallback scoped analyzer inputs included WebGL2 files with a WebGPU pipeline-quiet suffix."
  }

  $BundleAnalysisPath = Join-Path $TempDir "candidate-analysis-bundlegroup.json"
  $BundleAnalysis = [pscustomobject]@{
    required_candidate_gate = [pscustomobject]@{
      renderers = @(
        [pscustomobject]@{
          renderer = "webgpu"
          ok = $false
          best_status = "blocked-throughput"
          best_candidate_family = "fork-webgpu-default"
          best_baseline_family = "baseline-webgpu"
        }
      )
    }
    blocker_diagnostics = @(
      [pscustomobject]@{ renderer = "webgpu"; baseline_family = "baseline-webgpu"; status = "blocked-throughput"; scene = "many-draw-calls"; candidate_family = "fork-webgpu-default"; primary_blocker = "avg FPS -1.20%" }
    )
  }
  $BundleAnalysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $BundleAnalysisPath -Encoding UTF8
  $BundleOutput = & (Join-Path $Root "scripts\run_blocker_experiments.ps1") `
    -CandidateAnalysisJson $BundleAnalysisPath `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -ForkRevision "rev-a+viewerpatch-test" `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -DisableWebGpuTiming `
    -WebGpuBundleMode static `
    -RunComparableBaselines `
    -CaptureTargetedTrace `
    -TraceDuration 1 `
    -TraceWarmup 1 `
    -TraceStartDelayMs 1234 `
    -PostRunAnalysisInputList (Join-Path $TempDir "bundle-post-run-inputs.txt") `
    -TargetedPlanManifest (Join-Path $TempDir "bundle-targeted-plan.json") `
    -DryRun *>&1
  $BundleText = ($BundleOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $BundleText "-Label\s+baseline-content-shell-targeted-blocker-webgpu-bundlegroup-static\b" "WebGPU BundleGroup comparable baseline label"
  Assert-Matches $BundleText "-WebGpuBundleMode\s+static\b" "WebGPU BundleGroup suite/matrix handoff"
  Assert-Matches $BundleText "-LabelSuffix\s+-bundlegroup-static\b" "WebGPU BundleGroup trusted matrix label suffix"
  Assert-Matches $BundleText "--webgpuBundleMode\s+static\b" "WebGPU BundleGroup targeted trace handoff"
  Assert-Matches $BundleText "--expectedFlagMetadata\s+webgpu_bundle_mode=static\b" "WebGPU BundleGroup trace sidecar metadata validation"

  $BundleManifest = Get-Content -LiteralPath (Join-Path $TempDir "bundle-targeted-plan.json") -Raw | ConvertFrom-Json
  if ([string]$BundleManifest.options.webgpu_bundle_mode -ne "static") {
    throw "BundleGroup targeted plan manifest did not record WebGPU BundleGroup mode."
  }
  if ([string]$BundleManifest.options.webgpu_resource_warmup_label_suffix -ne "-bundlegroup-static") {
    throw "BundleGroup targeted plan manifest did not isolate WebGPU BundleGroup labels."
  }
  if ($BundleManifest.targeted_trace.enabled -ne $true -or [string]$BundleManifest.targeted_trace.webgpu_bundle_mode -ne "static") {
    throw "BundleGroup targeted plan manifest did not record targeted trace BundleGroup mode."
  }
  if (@($BundleManifest.experiment_labels.webgpu) -notcontains "fork-viewer-exp-default-bundlegroup-static") {
    throw "BundleGroup targeted plan manifest did not suffix WebGPU experiment labels."
  }
  if (@($BundleManifest.result_files.baseline_webgpu | Where-Object { [string]$_ -match "baseline-content-shell-targeted-blocker-webgpu-bundlegroup-static-many-draw-calls-webgpu\.json$" }).Count -ne 1) {
    throw "BundleGroup targeted plan manifest did not suffix WebGPU baseline result files."
  }
  if (@($BundleManifest.targeted_trace.trace_files | Where-Object { [string]$_.label -eq "baseline-content-shell-targeted-blocker-webgpu-trace-bundlegroup-static" -and [string]$_.scene -eq "many-draw-calls" }).Count -ne 1) {
    throw "BundleGroup targeted plan manifest did not suffix baseline trace artifacts."
  }
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Blocker experiment dry-run builds targeted WebGL2/WebGPU trusted matrices from candidate-analysis blocker diagnostics, including shader-stall diagnostics, with focused WebGPU experiment filters."

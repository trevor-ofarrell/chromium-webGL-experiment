[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TmpDir = Join-Path $Root "benchmarks\tmp\candidate-analysis-test"
$Analyzer = Join-Path $Root "scripts\analyze_candidates.mjs"

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

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Value
  )

  $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PathValue -Encoding UTF8
}

function New-Result {
  param(
    [string]$Variant,
    [string]$Scene,
    [string]$Renderer = "webgl2",
    [double]$AvgFps = 100,
    [double]$OneLow = 90,
    [double]$PointOneLow = 80,
    [double]$P95 = 10,
    [double]$P99 = 12,
    [int]$MeasuredSeconds = 30,
    [bool]$DeviceLost = $false,
    [bool]$QueueInstrumentation = $false,
    [bool]$BindGroupInstrumentation = $false,
    [bool]$PipelineStateInstrumentation = $false,
    [bool]$BufferStateInstrumentation = $false,
    [bool]$RenderStateInstrumentation = $false,
    [bool]$ImmediateInstrumentation = $false,
    [string]$TextureMode = "canvas",
    [ValidateSet("off", "static")]
    [string]$WebGpuBundleMode = "off",
    [int]$WebGpuBundleGroups = 0,
    [bool]$Precompile = $false,
    [int]$PrerenderFrames = 0,
    [bool]$SettleGpuAfterWarmup = $false,
    [int]$PipelineQuietFrames = 0,
    [int]$PipelineQuietMaxFrames = 30,
    [bool]$PipelineQuietAchieved = $true,
    [int]$PipelineCreateMeasuredCount = 0,
    [double]$PipelineCreateMeasuredMs = 0,
    [string]$ForkRevision = "",
    [string]$ChromiumRevision = "rev-a",
    [string]$BuildArgsHash = "args-a",
    [string]$Platform = "synthetic",
    [string]$GpuName = "ANGLE (NVIDIA, Synthetic GPU (0x00001234), D3D11)",
    [string]$DriverVersion = "Synthetic",
    [double]$Complexity = 2,
    [int]$ResourceWarmupCompileTargets = -1,
    [int]$ResourceWarmupTextureTargets = -1,
    [int]$ResourceWarmupRenderTargets = -1,
    [double]$AvgCpuFrameMs = 7,
    [double]$AvgRenderSubmissionMs = 6,
    [int]$ShaderCompileEvents = 0,
    [int]$DroppedFrames = 0,
    [string]$ResourceWarmupTextureInitError = $null,
    [bool]$ViewerTraceWebgpuQueue = $false,
    [bool]$GpuTiming = $true,
    [ValidateSet("unset", "true", "false")]
    [string]$BenchmarkHud = "unset",
    [bool]$BrowserFromCheckout = $true,
    [ValidateSet("fresh-temp", "explicit-reuse")]
    [string]$ProfileCacheMode = "fresh-temp",
    [string]$ProfileCacheKey = "",
    [ValidateSet("unset", "true", "false")]
    [string]$WebGpuPipelineInstrumentation = "unset",
    [bool]$AllowSoftwareRendering = $false
  )

  $ViewerPrefix = if ($Variant -match "fork") { "--viewer-app-url=" } else { "" }
  $PrecompileParam = if ($Precompile) { "1" } else { "0" }
  $SettleGpuParam = if ($SettleGpuAfterWarmup) { "1" } else { "0" }
  $GpuTimingParam = if ($GpuTiming) { "1" } else { "0" }
  $CompileTargets = if ($ResourceWarmupCompileTargets -ge 0) {
    $ResourceWarmupCompileTargets
  } elseif ($Precompile) {
    1
  } else {
    0
  }
  $TextureTargets = if ($ResourceWarmupTextureTargets -ge 0) {
    $ResourceWarmupTextureTargets
  } elseif ($Precompile) {
    0
  } else {
    0
  }
  $RenderTargets = if ($ResourceWarmupRenderTargets -ge 0) {
    $ResourceWarmupRenderTargets
  } elseif ($Precompile) {
    0
  } else {
    0
  }
  $ShowHudQuery = if ($BenchmarkHud -eq "unset") { "" } else { "&showHud=$([int]($BenchmarkHud -eq "true"))" }
  $BenchmarkHudEnabled = if ($BenchmarkHud -eq "unset") { $null } else { $BenchmarkHud -eq "true" }
  $Result = [pscustomobject]@{
    chromium_revision = $ChromiumRevision
    fork_revision = if ($Variant -match "fork") { if ($ForkRevision) { $ForkRevision } else { "rev-a+viewer" } } else { $null }
    build_args_hash = $BuildArgsHash
    platform = $Platform
    gpu_name = $GpuName
    driver_version = $DriverVersion
    angle_backend = "D3D11"
    renderer_type = $Renderer
    scene_name = $Scene
    warmup_seconds = 5
    measured_seconds = $MeasuredSeconds
    complexity = $Complexity
    avg_fps = $AvgFps
    p50_frame_ms = 10
    p95_frame_ms = $P95
    p99_frame_ms = $P99
    one_percent_low_fps = $OneLow
    point_one_percent_low_fps = $PointOneLow
    avg_cpu_frame_ms = $AvgCpuFrameMs
    avg_gpu_frame_ms = $null
    avg_js_frame_ms = 1
    avg_render_submission_ms = $AvgRenderSubmissionMs
    avg_compositor_latency_ms = $null
    avg_presentation_latency_ms = $null
    max_frame_ms = 20
    dropped_frames = $DroppedFrames
    draw_calls = 100
    triangles = 1000
    texture_upload_mb = 0
    buffer_upload_mb = 0
    shader_compile_events = $ShaderCompileEvents
    js_heap_mb = 10
    gpu_memory_mb = $null
    process_rss_mb = 500
    startup_ms_to_first_frame = 1000
    browser_binary_size_mb = 100
    viewer_bundle_size_mb = 1
    package_size_mb = 200
    browser_is_from_checkout = $BrowserFromCheckout
    benchmark_variant = $Variant
    texture_upload_mode = $TextureMode
    webgpu_bundle_mode = $WebGpuBundleMode
    webgpu_bundle_groups = $WebGpuBundleGroups
    resource_warmup_enabled = $Precompile -or $PrerenderFrames -gt 0 -or $SettleGpuAfterWarmup -or $PipelineQuietFrames -gt 0
    resource_warmup_precompile = $Precompile
    resource_warmup_prerender_frames = $PrerenderFrames
    resource_warmup_settle_gpu = $SettleGpuAfterWarmup
    resource_warmup_pipeline_quiet_frames = $PipelineQuietFrames
    resource_warmup_pipeline_quiet_max_frames = if ($PipelineQuietFrames -gt 0) { $PipelineQuietMaxFrames } else { 0 }
    resource_warmup_pipeline_quiet_actual_frames = if ($PipelineQuietFrames -gt 0 -and $PipelineQuietAchieved) { $PipelineQuietFrames } else { 0 }
    resource_warmup_pipeline_quiet_achieved = $PipelineQuietFrames -eq 0 -or $PipelineQuietAchieved
    resource_warmup_pipeline_quiet_error = if ($PipelineQuietFrames -gt 0 -and -not $PipelineQuietAchieved) { "pipeline-create-not-quiet-after-$PipelineQuietMaxFrames-frames" } else { $null }
    resource_warmup_compile_targets = $CompileTargets
    resource_warmup_texture_targets = $TextureTargets
    resource_warmup_render_targets = $RenderTargets
    resource_warmup_texture_init_error = $ResourceWarmupTextureInitError
    benchmark_hud_enabled = $BenchmarkHudEnabled
    profile_cache_mode = $ProfileCacheMode
    profile_cache_key = if ($ProfileCacheKey) { $ProfileCacheKey } else { $null }
    profile_reuse_enabled = $ProfileCacheMode -eq "explicit-reuse"
    allow_software_rendering = $AllowSoftwareRendering
    webgpu_queue_instrumentation_enabled = $QueueInstrumentation
    webgpu_bind_group_instrumentation_enabled = $BindGroupInstrumentation
    webgpu_pipeline_state_instrumentation_enabled = $PipelineStateInstrumentation
    webgpu_buffer_state_instrumentation_enabled = $BufferStateInstrumentation
    webgpu_render_state_instrumentation_enabled = $RenderStateInstrumentation
    webgpu_immediate_instrumentation_enabled = $ImmediateInstrumentation
    webgpu_pipeline_create_measured_ms = $PipelineCreateMeasuredMs
    viewer_trace_webgpu_queue = $ViewerTraceWebgpuQueue
    webgpu_device_lost = $DeviceLost
    gpu_timing_enabled = $GpuTiming
    webgl_context_currently_lost = $false
    webgl_context_lost_count = 0
    render_error_count = 0
    frame_times_ms = @(10, 10, 10)
    browser_flags = @("$ViewerPrefix" + "http://127.0.0.1:1/?benchmark=1&scene=$Scene&renderer=$Renderer&complexity=2&duration=$MeasuredSeconds&warmup=5&gpuTiming=$GpuTimingParam&textureUploadMode=$TextureMode&webgpuBundleMode=$WebGpuBundleMode&queueInstrumentation=$([int]$QueueInstrumentation)&bindGroupInstrumentation=$([int]$BindGroupInstrumentation)&pipelineStateInstrumentation=$([int]$PipelineStateInstrumentation)&bufferStateInstrumentation=$([int]$BufferStateInstrumentation)&renderStateInstrumentation=$([int]$RenderStateInstrumentation)&immediateInstrumentation=$([int]$ImmediateInstrumentation)&precompile=$PrecompileParam&prerenderFrames=$PrerenderFrames&settleGpuAfterWarmup=$SettleGpuParam&pipelineQuietFrames=$PipelineQuietFrames&pipelineQuietMaxFrames=$PipelineQuietMaxFrames$ShowHudQuery")
  }
  if ($WebGpuPipelineInstrumentation -ne "unset") {
    $Result | Add-Member -NotePropertyName "webgpu_pipeline_instrumentation_enabled" -NotePropertyValue ($WebGpuPipelineInstrumentation -eq "true")
  }
  if ($PipelineQuietFrames -gt 0) {
    $Result | Add-Member -NotePropertyName "webgpu_pipeline_instrumentation_available" -NotePropertyValue $true
    $Result | Add-Member -NotePropertyName "webgpu_pipeline_create_measured_count" -NotePropertyValue $PipelineCreateMeasuredCount
  }
  return $Result
}

function Invoke-Analyzer {
  param(
    [string[]]$Files,
    [string[]]$Arguments
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node $Analyzer @Files @Arguments 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = @($Output)
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

try {
  if (Test-Path -LiteralPath $TmpDir) {
    Remove-Item -LiteralPath $TmpDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null

  $Files = @()
  $StaleBlobCacheExperiment = New-Result "iter9-fork-webgpu-dawn-disable-blob-cache-hash-validation-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 160
  $StaleBlobCacheExperiment.browser_flags += "--disable-dawn-features=blob_cache_hash_validation"
  $CpuFallbackExperiment = New-Result "iter9-fork-webgpu-cpu-fallback-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 160
  $CpuFallbackExperiment | Add-Member -NotePropertyName "webgpu_cpu_texture_fallback_count" -NotePropertyValue 1
  $MissingCopyExternalImageFallbackRejection = New-Result "iter9-fork-webgpu-copy-external-image-trusted-fast-path-c2-texture-streaming-webgpu" "texture-streaming" -Renderer "webgpu" -AvgFps 160
  $MissingCopyExternalImageFallbackRejection | Add-Member -NotePropertyName "viewer_skip_webgpu_copy_external_image_dest_validation" -NotePropertyValue $true
  $MissingTrustedViewerMetadata = New-Result "iter9-fork-webgpu-skip-resource-labels-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 160
  $MissingTrustedViewerMetadata | Add-Member -NotePropertyName "viewer_skip_webgpu_resource_labels" -NotePropertyValue $true
  $Cases = @(
    (New-Result "iter9-baseline-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100 -OneLow 90 -PointOneLow 80 -P95 10 -P99 12),
    (New-Result "iter9-fork-clean-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 110 -OneLow 92 -PointOneLow 82 -P95 9 -P99 11),
    (New-Result "iter9-fork-tail-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 111 -OneLow 88 -PointOneLow 77 -P95 14 -P99 16),
    (New-Result "iter9-fork-short-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 140 -MeasuredSeconds 5),
    (New-Result "iter9-fork-device-loss-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 140 -DeviceLost $true),
    $CpuFallbackExperiment,
    $MissingCopyExternalImageFallbackRejection,
    $MissingTrustedViewerMetadata,
    (New-Result "iter9-fork-diagnostic-software-optin-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -AllowSoftwareRendering $true),
    (New-Result "iter9-fork-queue-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 140 -QueueInstrumentation $true),
    (New-Result "iter9-fork-bind-group-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 140 -BindGroupInstrumentation $true),
    (New-Result "iter9-fork-pipeline-state-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 140 -PipelineStateInstrumentation $true),
    (New-Result "iter9-fork-buffer-state-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 140 -BufferStateInstrumentation $true),
    (New-Result "iter9-fork-pipelinequiet-failed-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 160 -PipelineQuietFrames 2 -PipelineQuietMaxFrames 12 -PipelineQuietAchieved $false),
    (New-Result "iter9-fork-pipelinequiet-measured-create-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 160 -PipelineQuietFrames 2 -PipelineQuietMaxFrames 12 -PipelineCreateMeasuredCount 1),
    $StaleBlobCacheExperiment,
    (New-Result "iter9-fork-data-c2-texture-streaming-webgpu" "texture-streaming" -Renderer "webgpu" -AvgFps 140 -TextureMode "data"),
    (New-Result "iter9-fork-warmup-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 140 -Precompile $true -PrerenderFrames 4),
    (New-Result "iter9-fork-settled-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 140 -SettleGpuAfterWarmup $true),
    (New-Result "iter9-fork-stale-revision-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -ForkRevision "rev-a"),
    (New-Result "iter9-baseline-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 100 -OneLow 90 -PointOneLow 80 -P95 10 -P99 12),
    (New-Result "iter9-fork-clean-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 115 -OneLow 94 -PointOneLow 85 -P95 8 -P99 10),
    (New-Result "iter9-baseline-c2-texture-streaming-webgl2" "texture-streaming" -AvgFps 100 -OneLow 90 -PointOneLow 80 -P95 10 -P99 12),
    (New-Result "iter9-fork-mixed-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 115 -OneLow 94 -PointOneLow 85 -P95 8 -P99 10),
    (New-Result "iter9-fork-mixed-c2-texture-streaming-webgl2" "texture-streaming" -AvgFps 98 -OneLow 91 -PointOneLow 81 -P95 9 -P99 11),
    (New-Result "iter9-baseline-content-shell-long-stability-instancing-webgl2" "instancing" -AvgFps 100 -MeasuredSeconds 3600),
    (New-Result "iter9-fork-viewer-default-long-stability-instancing-webgl2" "instancing" -AvgFps 50 -MeasuredSeconds 3600),
    (New-Result "iter9-baseline-c2-shader-heavy-webgpu" "shader-heavy" -Renderer "webgpu" -AvgFps 100 -ShaderCompileEvents 0),
    (New-Result "iter9-fork-shader-stall-c2-shader-heavy-webgpu" "shader-heavy" -Renderer "webgpu" -AvgFps 130 -OneLow 94 -PointOneLow 85 -P95 8 -P99 10 -ShaderCompileEvents 3),
    (New-Result "iter9-baseline-c2-large-static-webgpu" "large-static" -Renderer "webgpu" -AvgFps 100 -PipelineCreateMeasuredMs 1.0),
    (New-Result "iter9-fork-pipeline-stall-c2-large-static-webgpu" "large-static" -Renderer "webgpu" -AvgFps 130 -OneLow 94 -PointOneLow 85 -P95 8 -P99 10 -PipelineCreateMeasuredMs 3.2),
    (New-Result "iter9-fork-source-queue-trace-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 150 -ViewerTraceWebgpuQueue $true),
    (New-Result "iter9-fork-render-state-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 140 -RenderStateInstrumentation $true),
    (New-Result "iter9-fork-immediate-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 140 -ImmediateInstrumentation $true),
    (New-Result "iter9-fork-dropped-frames-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 115 -OneLow 94 -PointOneLow 85 -P95 8 -P99 10 -DroppedFrames 2),
    (New-Result "iter9-fork-cpu-overhead-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 116 -OneLow 94 -PointOneLow 85 -P95 8 -P99 10 -AvgCpuFrameMs 8.1),
    (New-Result "iter9-fork-submit-overhead-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 116 -OneLow 94 -PointOneLow 85 -P95 8 -P99 10 -AvgRenderSubmissionMs 6.8)
  )

  for ($Index = 0; $Index -lt $Cases.Count; $Index++) {
    $PathValue = Join-Path $TmpDir "case-$Index.json"
    Write-Json $PathValue $Cases[$Index]
    $Files += $PathValue
  }

  $ReportPath = Join-Path $TmpDir "candidate-report.md"
  $JsonPath = Join-Path $TmpDir "candidate-report.json"
  $Analysis = Invoke-Analyzer -Files $Files -Arguments @("--output", $ReportPath, "--json", $JsonPath, "--requireFrameTimes", "--minScenes", "1")
  if ($Analysis.ExitCode -ne 0) {
    throw "Candidate analyzer failed. Output: $($Analysis.Output -join "`n")"
  }

  $Report = Get-Content -LiteralPath $ReportPath -Raw
  if ($Report -notmatch "Input file digest: ``[0-9a-f]{64}``") {
    throw "Candidate analyzer markdown did not record the raw input file digest. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-clean-c2" -or $Report -notmatch "candidate") {
    throw "Candidate analyzer did not report the clean speed win as a candidate. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-tail-c2" -or $Report -notmatch "blocked-tail") {
    throw "Candidate analyzer did not report the tail-regressing speed win as blocked-tail. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-mixed-c2" -or $Report -notmatch "blocked-throughput") {
    throw "Candidate analyzer did not block a suite-average FPS win with a material scene throughput regression. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-shader-stall-c2" -or
      $Report -notmatch "blocked-shader-stalls" -or
      $Report -notmatch "shader compile events \+3") {
    throw "Candidate analyzer did not block a speed win with shader compile event regression. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-pipeline-stall-c2" -or
      $Report -notmatch "blocked-shader-stalls" -or
      $Report -notmatch "WebGPU pipeline create \+2\.20 ms") {
    throw "Candidate analyzer did not block a speed win with WebGPU pipeline-create timing regression. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-dropped-frames-c2" -or
      $Report -notmatch "blocked-dropped-frames" -or
      $Report -notmatch "dropped frames \+2") {
    throw "Candidate analyzer did not block a speed win with dropped-frame regression. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-cpu-overhead-c2" -or
      $Report -notmatch "blocked-cpu-overhead" -or
      $Report -notmatch "CPU frame \+1\.10 ms") {
    throw "Candidate analyzer did not block a speed win with CPU-frame regression. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-submit-overhead-c2" -or
      $Report -notmatch "blocked-cpu-overhead" -or
      $Report -notmatch "render submission \+0\.80 ms") {
    throw "Candidate analyzer did not block a speed win with render-submission regression. Report: $Report"
  }
  if ($Report -notmatch "## Blocker Diagnostics" -or
      $Report -notmatch "iter9-fork-tail-c2" -or
      $Report -notmatch "many-draw-calls" -or
      $Report -notmatch "p95") {
    throw "Candidate analyzer did not report actionable blocker diagnostics for the tail-regressing speed win. Report: $Report"
  }
  if ($Report -notmatch "iter9-fork-mixed-c2" -or
      $Report -notmatch "texture-streaming" -or
      $Report -notmatch "avg FPS -2") {
    throw "Candidate analyzer did not report the scene throughput blocker for the mixed suite win. Report: $Report"
  }
  if ($Report -match "iter9-fork-warmup-c2") {
    throw "Candidate analyzer compared a warmed fork run against a non-warmed baseline. Report: $Report"
  }
  if ($Report -match "iter9-fork-settled-c2") {
    throw "Candidate analyzer compared a GPU-settled warmup fork run against a non-settled baseline. Report: $Report"
  }
  foreach ($Pattern in @(
      "measured_seconds 5 below 30",
      "WebGPU device loss",
      "WebGPU CPU texture fallback/readback webgpu_cpu_texture_fallback_count=1",
      "WebGPU copyExternalImage upload experiment missing CPU texture fallback rejection",
      "trusted experiment requires viewer_mode=true and viewer_trusted_content=true",
      "diagnostic software-rendering opt-in",
      "queue instrumentation attribution run",
      "bind-group instrumentation attribution run",
      "pipeline-state instrumentation attribution run",
      "buffer-state instrumentation attribution run",
      "render-state instrumentation attribution run",
      "immediate instrumentation attribution run",
      "source WebGPU queue trace attribution run",
      "WebGPU pipeline-quiet warmup not achieved",
      "WebGPU pipeline-quiet warmup measured-window pipeline creates 1",
      "WebGPU blob-cache hash-validation experiment missing webgpu_blob_cache_expected_available=true",
      "diagnostic texture_upload_mode=data",
      "fork_revision does not identify viewer patch",
      "stability benchmark artifact"
    )) {
    if ($Report -notmatch [regex]::Escape($Pattern)) {
      throw "Candidate analyzer report missing filtered reason '$Pattern'. Report: $Report"
    }
  }

  $MissingInstabilityPath = Join-Path $TmpDir "missing-instability.json"
  $MissingInstability = New-Result "iter9-fork-missing-instability-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150
  $MissingInstability.PSObject.Properties.Remove("webgpu_device_lost")
  Write-Json $MissingInstabilityPath $MissingInstability
  $MissingInstabilityReportPath = Join-Path $TmpDir "missing-instability-report.md"
  $MissingInstabilityAnalysis = Invoke-Analyzer -Files @($Files[0], $MissingInstabilityPath) -Arguments @("--output", $MissingInstabilityReportPath, "--requireFrameTimes", "--minScenes", "1")
  if ($MissingInstabilityAnalysis.ExitCode -ne 0) {
    throw "Candidate analyzer failed while checking missing instability telemetry. Output: $($MissingInstabilityAnalysis.Output -join "`n")"
  }
  $MissingInstabilityReport = Get-Content -LiteralPath $MissingInstabilityReportPath -Raw
  if ($MissingInstabilityReport -notmatch "missing webgpu_device_lost") {
    throw "Candidate analyzer did not filter missing instability telemetry. Report: $MissingInstabilityReport"
  }

  $MissingEvidencePath = Join-Path $TmpDir "missing-required-evidence.json"
  $MissingEvidence = New-Result "iter9-fork-missing-evidence-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150
  $MissingEvidence.PSObject.Properties.Remove("startup_ms_to_first_frame")
  Write-Json $MissingEvidencePath $MissingEvidence
  $MissingEvidenceReportPath = Join-Path $TmpDir "missing-required-evidence-report.md"
  $MissingEvidenceJsonPath = Join-Path $TmpDir "missing-required-evidence-report.json"
  $MissingEvidenceAnalysis = Invoke-Analyzer -Files @($Files[0], $MissingEvidencePath) -Arguments @("--output", $MissingEvidenceReportPath, "--json", $MissingEvidenceJsonPath, "--requireFrameTimes", "--minScenes", "1")
  if ($MissingEvidenceAnalysis.ExitCode -ne 0) {
    throw "Candidate analyzer failed while checking missing required benchmark evidence. Output: $($MissingEvidenceAnalysis.Output -join "`n")"
  }
  $MissingEvidenceReport = Get-Content -LiteralPath $MissingEvidenceReportPath -Raw
  if ($MissingEvidenceReport -notmatch "missing evidence startup_ms_to_first_frame") {
    throw "Candidate analyzer did not filter missing required benchmark evidence. Report: $MissingEvidenceReport"
  }

  $MissingGpuTimingPath = Join-Path $TmpDir "missing-gpu-timing.json"
  $MissingGpuTiming = New-Result "iter9-fork-missing-gpu-timing-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150
  $MissingGpuTiming.PSObject.Properties.Remove("gpu_timing_enabled")
  Write-Json $MissingGpuTimingPath $MissingGpuTiming
  $MissingGpuTimingReportPath = Join-Path $TmpDir "missing-gpu-timing-report.md"
  $MissingGpuTimingJsonPath = Join-Path $TmpDir "missing-gpu-timing-report.json"
  $MissingGpuTimingAnalysis = Invoke-Analyzer -Files @($Files[0], $MissingGpuTimingPath) -Arguments @("--output", $MissingGpuTimingReportPath, "--json", $MissingGpuTimingJsonPath, "--requireFrameTimes", "--minScenes", "1")
  if ($MissingGpuTimingAnalysis.ExitCode -ne 0) {
    throw "Candidate analyzer failed while checking missing GPU timing evidence. Output: $($MissingGpuTimingAnalysis.Output -join "`n")"
  }
  $MissingGpuTimingReport = Get-Content -LiteralPath $MissingGpuTimingReportPath -Raw
  if ($MissingGpuTimingReport -notmatch "missing evidence gpu_timing_enabled") {
    throw "Candidate analyzer did not filter missing GPU timing evidence. Report: $MissingGpuTimingReport"
  }
  $MissingGpuTimingJson = Get-Content -LiteralPath $MissingGpuTimingJsonPath -Raw | ConvertFrom-Json
  if ([string]$MissingGpuTimingJson.options.gpu_timing_evidence_policy -ne "candidate-analysis-requires-explicit-gpu-timing-mode" -or
      [string]$MissingGpuTimingJson.params.gpu_timing_evidence_policy -ne "candidate-analysis-requires-explicit-gpu-timing-mode") {
    throw "Candidate analyzer JSON did not record the explicit GPU timing evidence policy."
  }

  $MissingPackagePath = Join-Path $TmpDir "missing-package-size.json"
  $MissingPackage = New-Result "iter9-fork-missing-package-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150
  $MissingPackage.package_size_mb = $null
  Write-Json $MissingPackagePath $MissingPackage
  $MissingPackageReportPath = Join-Path $TmpDir "missing-package-size-report.md"
  $MissingPackageJsonPath = Join-Path $TmpDir "missing-package-size-report.json"
  $MissingPackageAnalysis = Invoke-Analyzer -Files @($Files[0], $MissingPackagePath) -Arguments @("--output", $MissingPackageReportPath, "--json", $MissingPackageJsonPath, "--requireFrameTimes", "--requirePackageSize", "--minScenes", "1")
  if ($MissingPackageAnalysis.ExitCode -ne 0) {
    throw "Candidate analyzer failed while checking required package-size evidence. Output: $($MissingPackageAnalysis.Output -join "`n")"
  }
  $MissingPackageReport = Get-Content -LiteralPath $MissingPackageReportPath -Raw
  if ($MissingPackageReport -notmatch "package_size_mb missing or non-positive") {
    throw "Candidate analyzer did not filter missing package-size evidence when required. Report: $MissingPackageReport"
  }
  $MissingPackageJson = Get-Content -LiteralPath $MissingPackageJsonPath -Raw | ConvertFrom-Json
  if ($MissingPackageJson.options.require_package_size -ne $true -or
      [string]$MissingPackageJson.options.package_size_speed_claim_policy -ne "require-package-size-when-enabled") {
    throw "Candidate analyzer JSON did not record the package-size speed-claim policy."
  }

  $MissingComplexityPath = Join-Path $TmpDir "missing-complexity.json"
  $MissingComplexity = New-Result "iter12-fork-missing-complexity-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150
  $MissingComplexity.PSObject.Properties.Remove("complexity")
  Write-Json $MissingComplexityPath $MissingComplexity
  $MissingComplexityJsonPath = Join-Path $TmpDir "missing-complexity-report.json"
  $MissingComplexityRun = Invoke-Analyzer -Files @($Files[0], $MissingComplexityPath) -Arguments @("--json", $MissingComplexityJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($MissingComplexityRun.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork result without explicit benchmark complexity."
  }
  $MissingComplexityJson = Get-Content -LiteralPath $MissingComplexityJsonPath -Raw | ConvertFrom-Json
  $MissingComplexityReason = @($MissingComplexityJson.filtered_reason_counts | Where-Object { [string]$_.reason -eq "missing evidence complexity" })
  if ($MissingComplexityReason.Count -ne 1 -or [int]$MissingComplexityReason[0].count -ne 1) {
    throw "Candidate analyzer did not report the missing explicit complexity filter reason."
  }

  $ComplexityMismatchBaselinePath = Join-Path $TmpDir "complexity-baseline.json"
  $ComplexityMismatchForkPath = Join-Path $TmpDir "complexity-fork.json"
  Write-Json $ComplexityMismatchBaselinePath (New-Result "iter12-baseline-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100 -Complexity 2)
  Write-Json $ComplexityMismatchForkPath (New-Result "iter12-fork-complexity-c1-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -Complexity 1)
  $ComplexityMismatchJsonPath = Join-Path $TmpDir "complexity-mismatch-report.json"
  $ComplexityMismatch = Invoke-Analyzer -Files @($ComplexityMismatchBaselinePath, $ComplexityMismatchForkPath) -Arguments @("--json", $ComplexityMismatchJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($ComplexityMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork-over-baseline comparison with mismatched benchmark complexity."
  }
  $ComplexityMismatchJson = Get-Content -LiteralPath $ComplexityMismatchJsonPath -Raw | ConvertFrom-Json
  if (@($ComplexityMismatchJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for mismatched benchmark complexity."
  }

  $AnalysisJson = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
  if ([string]$AnalysisJson.input_file_digest -notmatch "^[0-9a-f]{64}$" -or
      @($AnalysisJson.input_files).Count -ne $Files.Count) {
    throw "Candidate analyzer JSON did not record exact raw input file provenance."
  }
  if (@($AnalysisJson.blocker_diagnostics).Count -lt 1) {
    throw "Candidate analyzer JSON did not include blocker_diagnostics."
  }
  if ([double]$AnalysisJson.options.min_avg_fps_delta_pct -ne 0 -or
      [double]$AnalysisJson.params.min_avg_fps_delta_pct -ne 0) {
    throw "Candidate analyzer JSON did not record the default minimum average-FPS speedup threshold."
  }
  if ([string]$AnalysisJson.options.build_args_compatibility_policy -ne "same-build-args-hash" -or
      [string]$AnalysisJson.params.build_args_compatibility_policy -ne "same-build-args-hash") {
    throw "Candidate analyzer JSON did not record the same-build-args compatibility policy."
  }
  if ([string]$AnalysisJson.options.environment_compatibility_policy -ne "same-platform-driver-gpu-device" -or
      [string]$AnalysisJson.params.environment_compatibility_policy -ne "same-platform-driver-gpu-device") {
    throw "Candidate analyzer JSON did not record the same-platform/driver/GPU compatibility policy."
  }
  if ([string]$AnalysisJson.options.complexity_compatibility_policy -ne "same-explicit-benchmark-complexity" -or
      [string]$AnalysisJson.params.complexity_compatibility_policy -ne "same-explicit-benchmark-complexity") {
    throw "Candidate analyzer JSON did not record the same explicit benchmark complexity compatibility policy."
  }
  if ([string]$AnalysisJson.options.webgpu_bundle_mode_compatibility_policy -ne "same-webgpu-bundle-mode" -or
      [string]$AnalysisJson.params.webgpu_bundle_mode_compatibility_policy -ne "same-webgpu-bundle-mode") {
    throw "Candidate analyzer JSON did not record the WebGPU bundle-mode compatibility policy."
  }
  if ([string]$AnalysisJson.options.webgpu_pipeline_instrumentation_compatibility_policy -ne "same-webgpu-pipeline-instrumentation-mode" -or
      [string]$AnalysisJson.params.webgpu_pipeline_instrumentation_compatibility_policy -ne "same-webgpu-pipeline-instrumentation-mode") {
    throw "Candidate analyzer JSON did not record the WebGPU pipeline-instrumentation compatibility policy."
  }
  if ([string]$AnalysisJson.options.resource_warmup_compatibility_policy -ne "same-precompile-prerender-compile-texture-render-target-count-gpu-settle-and-webgpu-pipeline-quiet-mode" -or
      [string]$AnalysisJson.params.resource_warmup_compatibility_policy -ne "same-precompile-prerender-compile-texture-render-target-count-gpu-settle-and-webgpu-pipeline-quiet-mode") {
    throw "Candidate analyzer JSON did not record the resource warmup compatibility policy."
  }
  if ([string]$AnalysisJson.options.profile_cache_compatibility_policy -ne "same-profile-cache-mode-and-key" -or
      [string]$AnalysisJson.params.profile_cache_compatibility_policy -ne "same-profile-cache-mode-and-key") {
    throw "Candidate analyzer JSON did not record the profile-cache compatibility policy."
  }
  if ([string]$AnalysisJson.options.warm_profile_speed_claim_policy -ne "explicit-reuse-is-cache-attribution-not-retained-candidate" -or
      [string]$AnalysisJson.params.warm_profile_speed_claim_policy -ne "explicit-reuse-is-cache-attribution-not-retained-candidate") {
    throw "Candidate analyzer JSON did not record the warm-profile speed-claim policy."
  }
  if ([string]$AnalysisJson.options.required_benchmark_evidence_policy -ne "candidate-analysis-filters-missing-required-metric-fields" -or
      [string]$AnalysisJson.params.required_benchmark_evidence_policy -ne "candidate-analysis-filters-missing-required-metric-fields") {
    throw "Candidate analyzer JSON did not record the required benchmark evidence policy."
  }
  if ([string]$AnalysisJson.options.stability_evidence_policy -ne "candidate-analysis-filters-stability-artifacts" -or
      [string]$AnalysisJson.params.stability_evidence_policy -ne "candidate-analysis-filters-stability-artifacts") {
    throw "Candidate analyzer JSON did not record the stability-artifact filtering policy."
  }
  if ([string]$AnalysisJson.options.trace_instrumentation_policy -ne "candidate-analysis-filters-viewer-and-source-webgpu-attribution-runs" -or
      [string]$AnalysisJson.params.trace_instrumentation_policy -ne "candidate-analysis-filters-viewer-and-source-webgpu-attribution-runs") {
    throw "Candidate analyzer JSON did not record the trace-instrumentation filtering policy."
  }
  if ([string]$AnalysisJson.options.trusted_experiment_metadata_policy -ne "candidate-analysis-filters-unsafe-experiments-missing-viewer-trusted-content-metadata" -or
      [string]$AnalysisJson.params.trusted_experiment_metadata_policy -ne "candidate-analysis-filters-unsafe-experiments-missing-viewer-trusted-content-metadata") {
    throw "Candidate analyzer JSON did not record the trusted experiment metadata filtering policy."
  }
  if ([string]$AnalysisJson.options.webgpu_cpu_fallback_policy -ne "candidate-analysis-filters-webgpu-cpu-texture-fallback-and-missing-copyexternalimage-rejection" -or
      [string]$AnalysisJson.params.webgpu_cpu_fallback_policy -ne "candidate-analysis-filters-webgpu-cpu-texture-fallback-and-missing-copyexternalimage-rejection") {
    throw "Candidate analyzer JSON did not record the WebGPU CPU-fallback filtering policy."
  }
  if ([string]$AnalysisJson.options.webgpu_pipeline_quiet_success_policy -ne "candidate-analysis-filters-unachieved-or-measured-pipeline-create-webgpu-pipeline-quiet-warmup" -or
      [string]$AnalysisJson.params.webgpu_pipeline_quiet_success_policy -ne "candidate-analysis-filters-unachieved-or-measured-pipeline-create-webgpu-pipeline-quiet-warmup") {
    throw "Candidate analyzer JSON did not record the WebGPU pipeline-quiet warmup success filtering policy."
  }
  if ([double]$AnalysisJson.options.shader_compile_regression_events -ne 0 -or
      [double]$AnalysisJson.params.shader_compile_regression_events -ne 0 -or
      [double]$AnalysisJson.options.pipeline_create_regression_ms -ne 1.0 -or
      [double]$AnalysisJson.params.pipeline_create_regression_ms -ne 1.0 -or
      [string]$AnalysisJson.options.shader_compile_stall_policy -ne "candidate-analysis-blocks-shader-compile-event-and-webgpu-pipeline-create-time-regressions" -or
      [string]$AnalysisJson.params.shader_compile_stall_policy -ne "candidate-analysis-blocks-shader-compile-event-and-webgpu-pipeline-create-time-regressions") {
    throw "Candidate analyzer JSON did not record the shader compile/pipeline-create regression policy."
  }
  if ([double]$AnalysisJson.options.cpu_frame_regression_ms -ne 0.5 -or
      [double]$AnalysisJson.params.cpu_frame_regression_ms -ne 0.5 -or
      [double]$AnalysisJson.options.render_submission_regression_ms -ne 0.5 -or
      [double]$AnalysisJson.params.render_submission_regression_ms -ne 0.5 -or
      [string]$AnalysisJson.options.cpu_submission_regression_policy -ne "candidate-analysis-blocks-cpu-frame-and-render-submission-regressions" -or
      [string]$AnalysisJson.params.cpu_submission_regression_policy -ne "candidate-analysis-blocks-cpu-frame-and-render-submission-regressions") {
    throw "Candidate analyzer JSON did not record the CPU/render-submission regression policy."
  }
  if ([string]$AnalysisJson.options.package_size_speed_claim_policy -ne "require-package-size-when-enabled" -or
      [string]$AnalysisJson.params.package_size_speed_claim_policy -ne "require-package-size-when-enabled") {
    throw "Candidate analyzer JSON did not record the package-size speed-claim policy."
  }
  if ([string]$AnalysisJson.options.baseline_selection_policy -ne "fastest-compatible-baseline" -or
      [string]$AnalysisJson.params.baseline_selection_policy -ne "fastest-compatible-baseline") {
    throw "Candidate analyzer JSON did not record the conservative compatible-baseline selection policy."
  }

  $CrossGpuBaselinePath = Join-Path $TmpDir "cross-gpu-baseline.json"
  $CrossGpuForkPath = Join-Path $TmpDir "cross-gpu-fork.json"
  Write-Json $CrossGpuBaselinePath (New-Result "iter11-baseline-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100 -GpuName "ANGLE (NVIDIA, Synthetic GPU A (0x00001234), D3D11)" -DriverVersion "Driver-A")
  Write-Json $CrossGpuForkPath (New-Result "iter11-fork-cross-gpu-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -GpuName "ANGLE (NVIDIA, Synthetic GPU B (0x00005678), D3D11)" -DriverVersion "Driver-B")
  $CrossGpuReportPath = Join-Path $TmpDir "cross-gpu-report.md"
  $CrossGpuJsonPath = Join-Path $TmpDir "cross-gpu-report.json"
  $CrossGpu = Invoke-Analyzer -Files @($CrossGpuBaselinePath, $CrossGpuForkPath) -Arguments @("--output", $CrossGpuReportPath, "--json", $CrossGpuJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2")
  if ($CrossGpu.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a cross-GPU/driver fork-over-baseline comparison."
  }
  $CrossGpuReport = Get-Content -LiteralPath $CrossGpuReportPath -Raw
  if ($CrossGpuReport -match "iter11-fork-cross-gpu-c2" -and $CrossGpuReport -match "candidate") {
    throw "Candidate analyzer reported a cross-GPU/driver result as a candidate. Report: $CrossGpuReport"
  }
  $CrossGpuJson = Get-Content -LiteralPath $CrossGpuJsonPath -Raw | ConvertFrom-Json
  if (@($CrossGpuJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for cross-GPU/driver artifacts."
  }

  $MismatchedArgsBaselinePath = Join-Path $TmpDir "mismatched-build-args-baseline.json"
  $MismatchedArgsForkPath = Join-Path $TmpDir "mismatched-build-args-fork.json"
  Write-Json $MismatchedArgsBaselinePath (New-Result "iter12-baseline-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100 -BuildArgsHash "args-stock")
  Write-Json $MismatchedArgsForkPath (New-Result "iter12-fork-mismatched-args-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -BuildArgsHash "args-fork")
  $MismatchedArgsReportPath = Join-Path $TmpDir "mismatched-build-args-report.md"
  $MismatchedArgsJsonPath = Join-Path $TmpDir "mismatched-build-args-report.json"
  $MismatchedArgs = Invoke-Analyzer -Files @($MismatchedArgsBaselinePath, $MismatchedArgsForkPath) -Arguments @("--output", $MismatchedArgsReportPath, "--json", $MismatchedArgsJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2")
  if ($MismatchedArgs.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork-over-baseline comparison with mismatched build args."
  }
  $MismatchedArgsJson = Get-Content -LiteralPath $MismatchedArgsJsonPath -Raw | ConvertFrom-Json
  if (@($MismatchedArgsJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for mismatched build-args artifacts."
  }

  $HudBaselinePath = Join-Path $TmpDir "hud-baseline.json"
  $HudForkPath = Join-Path $TmpDir "hud-fork.json"
  Write-Json $HudBaselinePath (New-Result "iter12-baseline-hud-off-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100 -BenchmarkHud "false")
  Write-Json $HudForkPath (New-Result "iter12-fork-hud-on-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -BenchmarkHud "true")
  $HudMismatchJsonPath = Join-Path $TmpDir "hud-mismatch-report.json"
  $HudMismatch = Invoke-Analyzer -Files @($HudBaselinePath, $HudForkPath) -Arguments @("--json", $HudMismatchJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($HudMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork-over-baseline comparison with mismatched benchmark HUD state."
  }
  $HudMismatchJson = Get-Content -LiteralPath $HudMismatchJsonPath -Raw | ConvertFrom-Json
  if (@($HudMismatchJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for mismatched benchmark HUD state."
  }

  $PipelineInstBaselinePath = Join-Path $TmpDir "pipeline-instrumentation-baseline.json"
  $PipelineInstForkPath = Join-Path $TmpDir "pipeline-instrumentation-fork.json"
  Write-Json $PipelineInstBaselinePath (New-Result "iter12-baseline-pipeline-inst-off-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 100 -WebGpuPipelineInstrumentation "false")
  Write-Json $PipelineInstForkPath (New-Result "iter12-fork-pipeline-inst-on-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 150 -WebGpuPipelineInstrumentation "true")
  $PipelineInstMismatchJsonPath = Join-Path $TmpDir "pipeline-instrumentation-mismatch-report.json"
  $PipelineInstMismatch = Invoke-Analyzer -Files @($PipelineInstBaselinePath, $PipelineInstForkPath) -Arguments @("--json", $PipelineInstMismatchJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($PipelineInstMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork-over-baseline comparison with mismatched WebGPU pipeline instrumentation."
  }
  $PipelineInstMismatchJson = Get-Content -LiteralPath $PipelineInstMismatchJsonPath -Raw | ConvertFrom-Json
  if (@($PipelineInstMismatchJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for mismatched WebGPU pipeline instrumentation."
  }

  $BundleModeBaselinePath = Join-Path $TmpDir "webgpu-bundle-mode-baseline.json"
  $BundleModeForkPath = Join-Path $TmpDir "webgpu-bundle-mode-fork.json"
  Write-Json $BundleModeBaselinePath (New-Result "iter12-baseline-bundle-off-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 100 -WebGpuBundleMode "off")
  Write-Json $BundleModeForkPath (New-Result "iter12-fork-bundle-static-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 150 -WebGpuBundleMode "static" -WebGpuBundleGroups 1)
  $BundleModeMismatchJsonPath = Join-Path $TmpDir "webgpu-bundle-mode-mismatch-report.json"
  $BundleModeMismatch = Invoke-Analyzer -Files @($BundleModeBaselinePath, $BundleModeForkPath) -Arguments @("--json", $BundleModeMismatchJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($BundleModeMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork-over-baseline comparison with mismatched WebGPU BundleGroup scene mode."
  }
  $BundleModeMismatchJson = Get-Content -LiteralPath $BundleModeMismatchJsonPath -Raw | ConvertFrom-Json
  if (@($BundleModeMismatchJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for mismatched WebGPU BundleGroup scene modes."
  }

  $BundleCountBaselinePath = Join-Path $TmpDir "webgpu-bundle-count-baseline.json"
  $BundleCountForkPath = Join-Path $TmpDir "webgpu-bundle-count-fork.json"
  Write-Json $BundleCountBaselinePath (New-Result "iter12-baseline-bundle-static-c2-texture-streaming-webgpu" "texture-streaming" -Renderer "webgpu" -AvgFps 100 -WebGpuBundleMode "static" -WebGpuBundleGroups 0)
  Write-Json $BundleCountForkPath (New-Result "iter12-fork-bundle-static-c2-texture-streaming-webgpu" "texture-streaming" -Renderer "webgpu" -AvgFps 150 -WebGpuBundleMode "static" -WebGpuBundleGroups 0)
  $BundleCountJsonPath = Join-Path $TmpDir "webgpu-bundle-count-report.json"
  $BundleCountFailure = Invoke-Analyzer -Files @($BundleCountBaselinePath, $BundleCountForkPath) -Arguments @("--json", $BundleCountJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($BundleCountFailure.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted WebGPU static BundleGroup evidence with no recorded BundleGroups."
  }
  $BundleCountJson = Get-Content -LiteralPath $BundleCountJsonPath -Raw | ConvertFrom-Json
  if (@($BundleCountJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for WebGPU static BundleGroup evidence with no recorded BundleGroups."
  }
  if (@($BundleCountJson.filtered_reason_counts | Where-Object { [string]$_.reason -match "webgpu_bundle_mode=static requires positive webgpu_bundle_groups" }).Count -eq 0) {
    throw "Candidate analyzer did not report the missing WebGPU BundleGroup count as the filter reason."
  }

  $WarmupTargetBaselinePath = Join-Path $TmpDir "warmup-target-baseline.json"
  $WarmupTargetForkPath = Join-Path $TmpDir "warmup-target-fork.json"
  Write-Json $WarmupTargetBaselinePath (New-Result "iter12-baseline-warmup-targets-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100 -Precompile $true -PrerenderFrames 2 -ResourceWarmupCompileTargets 1)
  Write-Json $WarmupTargetForkPath (New-Result "iter12-fork-warmup-targets-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -Precompile $true -PrerenderFrames 2 -ResourceWarmupCompileTargets 2)
  $WarmupTargetJsonPath = Join-Path $TmpDir "warmup-target-mismatch-report.json"
  $WarmupTargetMismatch = Invoke-Analyzer -Files @($WarmupTargetBaselinePath, $WarmupTargetForkPath) -Arguments @("--json", $WarmupTargetJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($WarmupTargetMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork-over-baseline comparison with mismatched resource precompile target count."
  }
  $WarmupTargetJson = Get-Content -LiteralPath $WarmupTargetJsonPath -Raw | ConvertFrom-Json
  if (@($WarmupTargetJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for mismatched resource precompile target counts."
  }

  $PipelineQuietBaselinePath = Join-Path $TmpDir "pipeline-quiet-baseline.json"
  $PipelineQuietForkPath = Join-Path $TmpDir "pipeline-quiet-fork.json"
  Write-Json $PipelineQuietBaselinePath (New-Result "iter12-baseline-pipelinequiet-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 100 -PipelineQuietFrames 0)
  Write-Json $PipelineQuietForkPath (New-Result "iter12-fork-pipelinequiet-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 150 -PipelineQuietFrames 2 -PipelineQuietMaxFrames 12)
  $PipelineQuietJsonPath = Join-Path $TmpDir "pipeline-quiet-mismatch-report.json"
  $PipelineQuietMismatch = Invoke-Analyzer -Files @($PipelineQuietBaselinePath, $PipelineQuietForkPath) -Arguments @("--json", $PipelineQuietJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($PipelineQuietMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork-over-baseline comparison with mismatched WebGPU pipeline-quiet warmup mode."
  }
  $PipelineQuietJson = Get-Content -LiteralPath $PipelineQuietJsonPath -Raw | ConvertFrom-Json
  if (@($PipelineQuietJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for mismatched WebGPU pipeline-quiet warmup modes."
  }

  $ProfileCacheBaselinePath = Join-Path $TmpDir "profile-cache-baseline.json"
  $ProfileCacheForkPath = Join-Path $TmpDir "profile-cache-fork.json"
  Write-Json $ProfileCacheBaselinePath (New-Result "iter12-baseline-profile-cold-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 100 -ProfileCacheMode "fresh-temp")
  Write-Json $ProfileCacheForkPath (New-Result "iter12-fork-profile-warm-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 150 -ProfileCacheMode "explicit-reuse" -ProfileCacheKey "webgpu-warm-one-prime")
  $ProfileCacheJsonPath = Join-Path $TmpDir "profile-cache-mismatch-report.json"
  $ProfileCacheMismatch = Invoke-Analyzer -Files @($ProfileCacheBaselinePath, $ProfileCacheForkPath) -Arguments @("--json", $ProfileCacheJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($ProfileCacheMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a warm-profile fork over a cold-profile baseline."
  }
  $ProfileCacheJson = Get-Content -LiteralPath $ProfileCacheJsonPath -Raw | ConvertFrom-Json
  if (@($ProfileCacheJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for mismatched profile-cache modes."
  }

  $ProfileCacheAttributionBaselinePath = Join-Path $TmpDir "profile-cache-attribution-baseline.json"
  $ProfileCacheAttributionForkPath = Join-Path $TmpDir "profile-cache-attribution-fork.json"
  Write-Json $ProfileCacheAttributionBaselinePath (New-Result "iter12-baseline-profile-warm-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 100 -ProfileCacheMode "explicit-reuse" -ProfileCacheKey "webgpu-warm-one-prime")
  Write-Json $ProfileCacheAttributionForkPath (New-Result "iter12-fork-profile-warm-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 150 -ProfileCacheMode "explicit-reuse" -ProfileCacheKey "webgpu-warm-one-prime")
  $ProfileCacheAttributionReportPath = Join-Path $TmpDir "profile-cache-attribution-report.md"
  $ProfileCacheAttributionJsonPath = Join-Path $TmpDir "profile-cache-attribution-report.json"
  $ProfileCacheAttribution = Invoke-Analyzer -Files @($ProfileCacheAttributionBaselinePath, $ProfileCacheAttributionForkPath) -Arguments @("--output", $ProfileCacheAttributionReportPath, "--json", $ProfileCacheAttributionJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgpu")
  if ($ProfileCacheAttribution.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted an explicit profile-cache attribution win as retained WebGPU evidence."
  }
  $ProfileCacheAttributionReport = Get-Content -LiteralPath $ProfileCacheAttributionReportPath -Raw
  if ($ProfileCacheAttributionReport -notmatch "cache-attribution" -or
      $ProfileCacheAttributionReport -notmatch "requires matching fresh-profile official run") {
    throw "Candidate analyzer did not label the warm-profile win as cache attribution. Report: $ProfileCacheAttributionReport"
  }
  $ProfileCacheAttributionJson = Get-Content -LiteralPath $ProfileCacheAttributionJsonPath -Raw | ConvertFrom-Json
  $ProfileCacheAttributionFamily = @($ProfileCacheAttributionJson.families)[0]
  if ([string]$ProfileCacheAttributionFamily.status -ne "cache-attribution" -or
      [string]$ProfileCacheAttributionFamily.evidence_class -ne "warm-profile-attribution" -or
      [string]$ProfileCacheAttributionFamily.profile_cache_mode -ne "explicit-reuse") {
    throw "Candidate analyzer JSON did not expose warm-profile attribution status."
  }
  $ProfileCacheAttributionCandidateFamilies = @($ProfileCacheAttributionJson.required_candidate_gate.renderers[0].candidate_families)
  if ([bool]$ProfileCacheAttributionJson.required_candidate_gate.ok -ne $false -or
      $ProfileCacheAttributionCandidateFamilies.Count -ne 0) {
    throw "Candidate analyzer counted warm-profile attribution as a retained candidate."
  }

  $ProfileCacheMissingKeyPath = Join-Path $TmpDir "profile-cache-missing-key.json"
  Write-Json $ProfileCacheMissingKeyPath (New-Result "iter12-fork-profile-missing-key-c2-many-draw-calls-webgpu" "many-draw-calls" -Renderer "webgpu" -AvgFps 150 -ProfileCacheMode "explicit-reuse")
  $ProfileCacheMissingKeyJsonPath = Join-Path $TmpDir "profile-cache-missing-key-report.json"
  $ProfileCacheMissingKey = Invoke-Analyzer -Files @($Files[20], $ProfileCacheMissingKeyPath) -Arguments @("--json", $ProfileCacheMissingKeyJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($ProfileCacheMissingKey.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted an explicit profile-cache run without profile_cache_key."
  }
  $ProfileCacheMissingKeyJson = Get-Content -LiteralPath $ProfileCacheMissingKeyJsonPath -Raw | ConvertFrom-Json
  $ProfileMissingKeyReason = @($ProfileCacheMissingKeyJson.filtered_reason_counts | Where-Object { [string]$_.reason -eq "explicit profile-cache run missing profile_cache_key" })
  if ($ProfileMissingKeyReason.Count -ne 1 -or [int]$ProfileMissingKeyReason[0].count -ne 1) {
    throw "Candidate analyzer did not report the missing profile-cache key filter reason."
  }

  $LegacyWarmupBaselinePath = Join-Path $TmpDir "legacy-warmup-baseline.json"
  $CurrentWarmupForkPath = Join-Path $TmpDir "current-warmup-fork.json"
  $LegacyWarmupBaseline = New-Result "iter12-baseline-legacy-warmup-c2-postprocessing-webgl2" "postprocessing" -AvgFps 100 -Precompile $true -PrerenderFrames 2
  $LegacyWarmupBaseline.PSObject.Properties.Remove("resource_warmup_compile_targets")
  Write-Json $LegacyWarmupBaselinePath $LegacyWarmupBaseline
  Write-Json $CurrentWarmupForkPath (New-Result "iter12-fork-current-warmup-c2-postprocessing-webgl2" "postprocessing" -AvgFps 150 -Precompile $true -PrerenderFrames 2 -ResourceWarmupCompileTargets 2)
  $LegacyWarmupJsonPath = Join-Path $TmpDir "legacy-warmup-mismatch-report.json"
  $LegacyWarmupMismatch = Invoke-Analyzer -Files @($LegacyWarmupBaselinePath, $CurrentWarmupForkPath) -Arguments @("--json", $LegacyWarmupJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($LegacyWarmupMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a current warmed fork run against a legacy warmed baseline with unknown compile-target count."
  }
  $LegacyWarmupJson = Get-Content -LiteralPath $LegacyWarmupJsonPath -Raw | ConvertFrom-Json
  if (@($LegacyWarmupJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for legacy/current resource precompile target mismatch."
  }

  $LegacyTextureWarmupBaselinePath = Join-Path $TmpDir "legacy-texture-warmup-baseline.json"
  $CurrentTextureWarmupForkPath = Join-Path $TmpDir "current-texture-warmup-fork.json"
  $LegacyTextureWarmupBaseline = New-Result "iter12-baseline-legacy-texture-warmup-c2-texture-streaming-webgpu" "texture-streaming" -Renderer "webgpu" -AvgFps 100 -Precompile $true -ResourceWarmupCompileTargets 1
  $LegacyTextureWarmupBaseline.PSObject.Properties.Remove("resource_warmup_texture_targets")
  $LegacyTextureWarmupBaseline.PSObject.Properties.Remove("resource_warmup_render_targets")
  Write-Json $LegacyTextureWarmupBaselinePath $LegacyTextureWarmupBaseline
  Write-Json $CurrentTextureWarmupForkPath (New-Result "iter12-fork-current-texture-warmup-c2-texture-streaming-webgpu" "texture-streaming" -Renderer "webgpu" -AvgFps 150 -Precompile $true -ResourceWarmupCompileTargets 1 -ResourceWarmupTextureTargets 96 -ResourceWarmupRenderTargets 0)
  $LegacyTextureWarmupJsonPath = Join-Path $TmpDir "legacy-texture-warmup-mismatch-report.json"
  $LegacyTextureWarmupMismatch = Invoke-Analyzer -Files @($LegacyTextureWarmupBaselinePath, $CurrentTextureWarmupForkPath) -Arguments @("--json", $LegacyTextureWarmupJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($LegacyTextureWarmupMismatch.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a current warmed fork run against a legacy warmed baseline with unknown texture/render-target warmup counts."
  }
  $LegacyTextureWarmupJson = Get-Content -LiteralPath $LegacyTextureWarmupJsonPath -Raw | ConvertFrom-Json
  if (@($LegacyTextureWarmupJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for legacy/current texture/render-target warmup mismatch."
  }

  $WarmupInitErrorPath = Join-Path $TmpDir "warmup-init-error-fork.json"
  Write-Json $WarmupInitErrorPath (New-Result "iter12-fork-warmup-init-error-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -Precompile $true -ResourceWarmupTextureTargets 1 -ResourceWarmupTextureInitError "renderer.initTexture failed")
  $WarmupInitErrorJsonPath = Join-Path $TmpDir "warmup-init-error-report.json"
  $WarmupInitError = Invoke-Analyzer -Files @($Files[0], $WarmupInitErrorPath) -Arguments @("--json", $WarmupInitErrorJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($WarmupInitError.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork result with resource warmup initialization error."
  }
  $WarmupInitErrorJson = Get-Content -LiteralPath $WarmupInitErrorJsonPath -Raw | ConvertFrom-Json
  $WarmupInitErrorReason = @($WarmupInitErrorJson.filtered_reason_counts | Where-Object { [string]$_.reason -match "resource_warmup_texture_init_error" })
  if ($WarmupInitErrorReason.Count -ne 1 -or [int]$WarmupInitErrorReason[0].count -ne 1) {
    throw "Candidate analyzer did not report the resource warmup texture initialization error filter reason."
  }

  $InstalledBaselinePath = Join-Path $TmpDir "installed-baseline.json"
  $InstalledForkPath = Join-Path $TmpDir "installed-fork.json"
  Write-Json $InstalledBaselinePath (New-Result "iter12-installed-baseline-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100 -BrowserFromCheckout $false)
  Write-Json $InstalledForkPath (New-Result "iter12-fork-installed-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 150 -BrowserFromCheckout $false)
  $InstalledJsonPath = Join-Path $TmpDir "installed-report.json"
  $InstalledCheckout = Invoke-Analyzer -Files @($InstalledBaselinePath, $InstalledForkPath) -Arguments @("--json", $InstalledJsonPath, "--requireFrameTimes", "--requireCheckout", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($InstalledCheckout.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted non-checkout browser artifacts with --requireCheckout."
  }
  $InstalledJson = Get-Content -LiteralPath $InstalledJsonPath -Raw | ConvertFrom-Json
  if (@($InstalledJson.families).Count -ne 0) {
    throw "Candidate analyzer produced comparable families for non-checkout browser artifacts."
  }
  $InstalledReason = @($InstalledJson.filtered_reason_counts | Where-Object { [string]$_.reason -eq "browser_is_from_checkout not true" })
  if ($InstalledReason.Count -ne 1 -or [int]$InstalledReason[0].count -ne 2) {
    throw "Candidate analyzer did not report the non-checkout browser filter reason."
  }

  $DuplicateBaselinePath = Join-Path $TmpDir "duplicate-scene-baseline.json"
  $DuplicateForkAPath = Join-Path $TmpDir "duplicate-scene-fork-a.json"
  $DuplicateForkBPath = Join-Path $TmpDir "duplicate-scene-fork-b.json"
  Write-Json $DuplicateBaselinePath (New-Result "iter13-baseline-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100)
  Write-Json $DuplicateForkAPath (New-Result "iter13-fork-duplicate-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 112)
  Write-Json $DuplicateForkBPath (New-Result "iter13-fork-duplicate-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 108)
  $DuplicateReportPath = Join-Path $TmpDir "duplicate-scene-report.md"
  $DuplicateJsonPath = Join-Path $TmpDir "duplicate-scene-report.json"
  $Duplicate = Invoke-Analyzer -Files @($DuplicateBaselinePath, $DuplicateForkAPath, $DuplicateForkBPath) -Arguments @("--output", $DuplicateReportPath, "--json", $DuplicateJsonPath, "--requireFrameTimes", "--minScenes", "2", "--requireCandidateRenderer", "webgl2")
  if ($Duplicate.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted duplicate rows for one scene as multi-scene coverage."
  }
  $DuplicateJson = Get-Content -LiteralPath $DuplicateJsonPath -Raw | ConvertFrom-Json
  $DuplicateFamily = @($DuplicateJson.families)[0]
  if ([int]$DuplicateFamily.scenes -ne 1 -or [int]$DuplicateFamily.duplicate_scene_rows_collapsed -ne 1) {
    throw "Candidate analyzer did not collapse duplicate scene rows to distinct-scene coverage."
  }

  $RequiredSceneReportPath = Join-Path $TmpDir "required-scene-report.md"
  $RequiredSceneJsonPath = Join-Path $TmpDir "required-scene-report.json"
  $RequiredScene = Invoke-Analyzer -Files @($Files[0], $Files[1]) -Arguments @("--output", $RequiredSceneReportPath, "--json", $RequiredSceneJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requiredScene", "many-draw-calls", "--requiredScene", "texture-streaming", "--requireCandidateRenderer", "webgl2")
  if ($RequiredScene.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a family missing an explicitly required scene."
  }
  $RequiredSceneJson = Get-Content -LiteralPath $RequiredSceneJsonPath -Raw | ConvertFrom-Json
  $RequiredSceneFamily = @($RequiredSceneJson.families)[0]
  if ([string]$RequiredSceneFamily.status -ne "needs-suite" -or
      @($RequiredSceneFamily.missing_required_scenes) -notcontains "texture-streaming") {
    throw "Candidate analyzer did not report missing required scene coverage."
  }

  $MaskedTailBaselineAPath = Join-Path $TmpDir "masked-tail-baseline-a.json"
  $MaskedTailBaselineBPath = Join-Path $TmpDir "masked-tail-baseline-b.json"
  $MaskedTailForkAPath = Join-Path $TmpDir "masked-tail-fork-a.json"
  $MaskedTailForkBPath = Join-Path $TmpDir "masked-tail-fork-b.json"
  Write-Json $MaskedTailBaselineAPath (New-Result "iter14-baseline-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100 -P95 10 -P99 12)
  Write-Json $MaskedTailBaselineBPath (New-Result "iter14-baseline-c2-texture-streaming-webgl2" "texture-streaming" -AvgFps 100 -P95 10 -P99 12)
  Write-Json $MaskedTailForkAPath (New-Result "iter14-fork-masked-tail-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 110 -P95 10 -P99 15)
  Write-Json $MaskedTailForkBPath (New-Result "iter14-fork-masked-tail-c2-texture-streaming-webgl2" "texture-streaming" -AvgFps 110 -P95 7 -P99 7)
  $MaskedTail = Invoke-Analyzer -Files @($MaskedTailBaselineAPath, $MaskedTailBaselineBPath, $MaskedTailForkAPath, $MaskedTailForkBPath) -Arguments @("--requireFrameTimes", "--minScenes", "2", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($MaskedTail.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a suite-average speedup with a material per-scene p99 regression."
  }
  if (($MaskedTail.Output -join "`n") -notmatch "blocked-tail") {
    throw "Candidate speedup claim gate failure did not identify masked per-scene tail regression. Output: $($MaskedTail.Output -join "`n")"
  }

  $SlowBaselinePath = Join-Path $TmpDir "multi-baseline-slow.json"
  $FastBaselinePath = Join-Path $TmpDir "multi-baseline-fast.json"
  $ApparentWinPath = Join-Path $TmpDir "multi-baseline-fork.json"
  Write-Json $SlowBaselinePath (New-Result "iter10-baseline-slow-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 100)
  Write-Json $FastBaselinePath (New-Result "iter10-baseline-fast-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 120)
  Write-Json $ApparentWinPath (New-Result "iter10-fork-apparent-win-c2-many-draw-calls-webgl2" "many-draw-calls" -AvgFps 110)
  $MultiBaselineReportPath = Join-Path $TmpDir "multi-baseline-report.md"
  $MultiBaselineJsonPath = Join-Path $TmpDir "multi-baseline-report.json"
  $MultiBaseline = Invoke-Analyzer -Files @($SlowBaselinePath, $FastBaselinePath, $ApparentWinPath) -Arguments @("--output", $MultiBaselineReportPath, "--json", $MultiBaselineJsonPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2")
  if ($MultiBaseline.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a fork candidate that only beat a slower compatible baseline instead of the fastest compatible baseline."
  }
  $MultiBaselineReport = Get-Content -LiteralPath $MultiBaselineReportPath -Raw
  if ($MultiBaselineReport -notmatch "## Baseline Selection" -or
      $MultiBaselineReport -notmatch "strongest-compatible-baseline" -or
      $MultiBaselineReport -notmatch "iter10-baseline-fast-c2-many-draw-calls-webgl2") {
    throw "Candidate analyzer did not document fastest-compatible-baseline selection. Report: $MultiBaselineReport"
  }
  $MultiBaselineJson = Get-Content -LiteralPath $MultiBaselineJsonPath -Raw | ConvertFrom-Json
  $MultiBaselineFamily = @($MultiBaselineJson.families)[0]
  if ([string]$MultiBaselineFamily.baseline_family -ne "strongest-compatible-baseline" -or
      [double]$MultiBaselineFamily.avg_fps_delta_pct -ge 0) {
    throw "Candidate analyzer did not compare the fork candidate against the fastest compatible baseline."
  }
  $MultiBaselineSelection = @($MultiBaselineJson.baseline_selection_diagnostics)[0]
  if ([int]$MultiBaselineSelection.compatible_baseline_count -ne 2 -or
      [string]$MultiBaselineSelection.selected_baseline_variant -ne "iter10-baseline-fast-c2-many-draw-calls-webgl2") {
    throw "Candidate analyzer JSON did not expose the fastest compatible baseline selection."
  }

  $OnlyWebGlCleanFiles = @($Files[0], $Files[1])
  $OnlyWebGl = Invoke-Analyzer -Files $OnlyWebGlCleanFiles -Arguments @("--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($OnlyWebGl.ExitCode -ne 0) {
    throw "Candidate speedup claim gate rejected a clean WebGL2 candidate. Output: $($OnlyWebGl.Output -join "`n")"
  }

  $WeakSpeedup = Invoke-Analyzer -Files $OnlyWebGlCleanFiles -Arguments @("--requireFrameTimes", "--minScenes", "1", "--minAvgFpsDeltaPct", "15", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($WeakSpeedup.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a speedup below the configured minimum average-FPS threshold."
  }
  if (($WeakSpeedup.Output -join "`n") -notmatch "weak-throughput") {
    throw "Candidate speedup claim gate failure did not identify weak-throughput status. Output: $($WeakSpeedup.Output -join "`n")"
  }

  $FileListPath = Join-Path $TmpDir "clean-webgl-inputs.txt"
  $OnlyWebGlCleanFiles | Set-Content -LiteralPath $FileListPath -Encoding UTF8
  $OnlyWebGlFileList = Invoke-Analyzer -Files @() -Arguments @("--fileList", $FileListPath, "--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($OnlyWebGlFileList.ExitCode -ne 0) {
    throw "Candidate speedup claim gate rejected a clean WebGL2 candidate supplied through --fileList. Output: $($OnlyWebGlFileList.Output -join "`n")"
  }

  $MissingWebGpu = Invoke-Analyzer -Files $OnlyWebGlCleanFiles -Arguments @("--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($MissingWebGpu.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted missing WebGPU candidate evidence."
  }
  if (($MissingWebGpu.Output -join "`n") -notmatch "webgpu") {
    throw "Candidate speedup claim gate failure did not identify WebGPU. Output: $($MissingWebGpu.Output -join "`n")"
  }

  $TailOnlyFiles = @($Files[0], $Files[2])
  $TailOnly = Invoke-Analyzer -Files $TailOnlyFiles -Arguments @("--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($TailOnly.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted an average-FPS win with tail regression."
  }
  if (($TailOnly.Output -join "`n") -notmatch "blocked-tail") {
    throw "Candidate speedup claim gate failure did not identify blocked-tail status. Output: $($TailOnly.Output -join "`n")"
  }

  $MixedThroughputFiles = @($Files[0], $Files[22], $Files[23], $Files[24])
  $MixedThroughput = Invoke-Analyzer -Files $MixedThroughputFiles -Arguments @("--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($MixedThroughput.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted a suite-average FPS win with a material scene throughput regression."
  }
  if (($MixedThroughput.Output -join "`n") -notmatch "blocked-throughput") {
    throw "Candidate speedup claim gate failure did not identify blocked-throughput status. Output: $($MixedThroughput.Output -join "`n")"
  }

  $BothRenderers = Invoke-Analyzer -Files $Files -Arguments @("--requireFrameTimes", "--minScenes", "1", "--requireCandidateRenderer", "webgl2", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($BothRenderers.ExitCode -ne 0) {
    throw "Candidate speedup claim gate rejected clean WebGL2 and WebGPU candidates. Output: $($BothRenderers.Output -join "`n")"
  }

  $ExactRevisions = Invoke-Analyzer -Files $Files -Arguments @("--requireFrameTimes", "--minScenes", "1", "--expectedChromiumRevision", "rev-a", "--expectedForkRevision", "rev-a+viewer", "--requireCandidateRenderer", "webgl2", "--requireCandidateRenderer", "webgpu", "--quiet")
  if ($ExactRevisions.ExitCode -ne 0) {
    throw "Candidate speedup claim gate rejected clean candidates with matching exact revision filters. Output: $($ExactRevisions.Output -join "`n")"
  }

  $MismatchedRevisionReportPath = Join-Path $TmpDir "mismatched-revision-report.md"
  $MismatchedRevisionJsonPath = Join-Path $TmpDir "mismatched-revision-report.json"
  $MismatchedRevision = Invoke-Analyzer -Files $Files -Arguments @("--output", $MismatchedRevisionReportPath, "--json", $MismatchedRevisionJsonPath, "--requireFrameTimes", "--minScenes", "1", "--expectedChromiumRevision", "rev-b", "--expectedForkRevision", "rev-a+viewer", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($MismatchedRevision.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted inputs from the wrong Chromium revision."
  }
  $MismatchedRevisionReport = Get-Content -LiteralPath $MismatchedRevisionReportPath -Raw
  if ($MismatchedRevisionReport -notmatch "chromium_revision rev-a does not match expected rev-b") {
    throw "Candidate analyzer did not report the expected Chromium revision mismatch. Report: $MismatchedRevisionReport"
  }

  $MismatchedForkReportPath = Join-Path $TmpDir "mismatched-fork-report.md"
  $MismatchedForkJsonPath = Join-Path $TmpDir "mismatched-fork-report.json"
  $MismatchedFork = Invoke-Analyzer -Files $Files -Arguments @("--output", $MismatchedForkReportPath, "--json", $MismatchedForkJsonPath, "--requireFrameTimes", "--minScenes", "1", "--expectedChromiumRevision", "rev-a", "--expectedForkRevision", "rev-a+viewer-new", "--requireCandidateRenderer", "webgl2", "--quiet")
  if ($MismatchedFork.ExitCode -eq 0) {
    throw "Candidate speedup claim gate accepted fork inputs from the wrong viewer patch revision."
  }
  $MismatchedForkReport = Get-Content -LiteralPath $MismatchedForkReportPath -Raw
  if ($MismatchedForkReport -notmatch "fork_revision rev-a\+viewer does not match expected rev-a\+viewer-new") {
    throw "Candidate analyzer did not report the expected fork revision mismatch. Report: $MismatchedForkReport"
  }
} finally {
  if (Test-Path -LiteralPath $TmpDir) {
    Assert-UnderDirectory $TmpDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TmpDir -Recurse -Force
  }
}

Write-Host "Candidate analysis identifies clean speed wins, blocks weak, shader-stall, dropped-frame, tail, per-scene masked-tail, scene-throughput, duplicate-scene, missing-required-scene, cross-environment, mismatched-build-args, mismatched benchmark complexity, mismatched GPU timing metadata, mismatched WebGPU BundleGroup mode, invalid WebGPU BundleGroup counts, mismatched WebGPU pipeline instrumentation, mismatched resource-warmup compile/texture/render-target counts, mismatched WebGPU pipeline-quiet warmup modes, mismatched profile-cache modes, warm-profile attribution wins, non-checkout browser artifacts, malformed metric evidence, missing complexity evidence, missing GPU timing evidence, missing package-size evidence when required, and slower-than-fastest-baseline regressions, enforces required WebGL2/WebGPU speedup gates, separates resource-warmup/profile-cache runs, and filters invalid, exact-revision-mismatched, stale-fork-provenance, stability, resource-warmup init errors, WebGPU CPU-fallback, unachieved or measured-window-contaminated WebGPU pipeline-quiet warmup, missing copyExternalImage CPU-fallback rejection, missing trusted-content provenance, cache-ineligible, or attribution-only runs."

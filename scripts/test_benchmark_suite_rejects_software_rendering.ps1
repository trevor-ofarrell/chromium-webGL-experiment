[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\suite-software-renderer-test"

if (Test-Path $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function New-Result {
  param(
    [string]$GpuName,
    [string]$AngleBackend,
    [AllowNull()]
    [string]$DriverVersion = "test-driver",
    [bool]$WebGpuDeviceLost = $false,
    [int]$RenderErrorCount = 0,
    [int]$PipelineQuietFrames = 0,
    [bool]$PipelineQuietAchieved = $true,
    [int]$PipelineCreateMeasuredCount = 0,
    [bool]$WebGpuQueueInstrumentation = $false,
    [bool]$WebGpuBindGroupInstrumentation = $false,
    [bool]$WebGpuPipelineStateInstrumentation = $false,
    [bool]$WebGpuBufferStateInstrumentation = $false,
    [bool]$WebGpuRenderStateInstrumentation = $false,
    [bool]$WebGpuImmediateInstrumentation = $false,
    [bool]$ViewerTraceWebgpuQueue = $false,
    [string]$ResourceWarmupTextureInitError = $null
  )

  return [ordered]@{
    chromium_revision = "test-chromium-revision"
    fork_revision = "test-chromium-revision+viewerpatch-test"
    build_args_hash = "test-build-args-hash"
    platform = "test-platform"
    gpu_name = $GpuName
    driver_version = $DriverVersion
    angle_backend = $AngleBackend
    renderer_type = "webgl2"
    scene_name = "many-draw-calls"
    warmup_seconds = 1
    measured_seconds = 1
    complexity = 2
    avg_fps = 60
    p50_frame_ms = 16
    p95_frame_ms = 17
    p99_frame_ms = 18
    one_percent_low_fps = 55
    point_one_percent_low_fps = 50
    avg_cpu_frame_ms = 1
    avg_gpu_frame_ms = 1
    avg_js_frame_ms = 0.5
    avg_render_submission_ms = 0.5
    avg_compositor_latency_ms = $null
    avg_presentation_latency_ms = $null
    max_frame_ms = 18
    dropped_frames = 0
    draw_calls = 100
    triangles = 1000
    texture_upload_mb = 0
    buffer_upload_mb = 0
    shader_compile_events = 0
    js_heap_mb = 10
    gpu_memory_mb = 20
    process_rss_mb = 100
    startup_ms_to_first_frame = 500
    browser_binary_size_mb = 100
    viewer_bundle_size_mb = 1
    package_size_mb = 120
    browser_is_from_checkout = $true
    benchmark_variant = "fork-viewer-default"
    resource_warmup_pipeline_quiet_frames = $PipelineQuietFrames
    resource_warmup_pipeline_quiet_max_frames = if ($PipelineQuietFrames -gt 0) { 12 } else { 0 }
    resource_warmup_pipeline_quiet_actual_frames = if ($PipelineQuietFrames -gt 0 -and $PipelineQuietAchieved) { $PipelineQuietFrames } else { 0 }
    resource_warmup_pipeline_quiet_achieved = $PipelineQuietFrames -eq 0 -or $PipelineQuietAchieved
    resource_warmup_pipeline_quiet_error = if ($PipelineQuietFrames -gt 0 -and -not $PipelineQuietAchieved) { "pipeline-create-not-quiet-after-12-frames" } else { $null }
    resource_warmup_texture_init_error = $ResourceWarmupTextureInitError
    webgpu_pipeline_instrumentation_available = $true
    webgpu_pipeline_create_measured_count = $PipelineCreateMeasuredCount
    webgpu_device_lost = $WebGpuDeviceLost
    webgpu_device_loss_source = if ($WebGpuDeviceLost) { "gpu.device.lost" } else { $null }
    webgpu_queue_instrumentation_enabled = $WebGpuQueueInstrumentation
    webgpu_bind_group_instrumentation_enabled = $WebGpuBindGroupInstrumentation
    webgpu_pipeline_state_instrumentation_enabled = $WebGpuPipelineStateInstrumentation
    webgpu_buffer_state_instrumentation_enabled = $WebGpuBufferStateInstrumentation
    webgpu_render_state_instrumentation_enabled = $WebGpuRenderStateInstrumentation
    webgpu_immediate_instrumentation_enabled = $WebGpuImmediateInstrumentation
    viewer_trace_webgpu_queue = $ViewerTraceWebgpuQueue
    webgl_context_currently_lost = $false
    webgl_context_lost_count = 0
    render_error_count = $RenderErrorCount
  }
}

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Value
  )

  $Value | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PathValue -Encoding ASCII
}

function Invoke-SuiteValidation {
  param(
    [string]$PathValue,
    [string]$Renderer = "webgl2",
    [string]$Variant = "fork-viewer-default"
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node (Join-Path $Root "scripts\validate_benchmark_suite.mjs") `
      --renderer $Renderer `
      --variant $Variant `
      --expectedScenes many-draw-calls `
      --requireCheckout `
      --requireBuildArgs `
      --requireForkRevision `
      --expectedForkRevision "test-chromium-revision+viewerpatch-test" `
      --forbidSmoke `
      --rejectSoftwareRendering `
      --rejectGpuInstability `
      --requireGpuMetadata `
      $PathValue 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output | ForEach-Object { [string]$_ }) -join " "
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

$ResultPath = Join-Path $TempDir "fork-viewer-default-many-draw-calls-webgl2.json"
Write-Json $ResultPath (New-Result "ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device), SwiftShader driver)" "ANGLE (Google, SwiftShader)")
$Failure = Invoke-SuiteValidation $ResultPath
if ($Failure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a known SwiftShader/software-rendered result."
}
if ($Failure.Output -notmatch "software-rendered|SwiftShader") {
  throw "Benchmark suite software-rendering rejection did not explain SwiftShader. Output: $($Failure.Output)"
}

$DiagnosticOptIn = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$DiagnosticOptIn["allow_software_rendering"] = $true
Write-Json $ResultPath $DiagnosticOptIn
$DiagnosticOptInFailure = Invoke-SuiteValidation $ResultPath
if ($DiagnosticOptInFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a diagnostic software-rendering opt-in result."
}
if ($DiagnosticOptInFailure.Output -notmatch "diagnostic software-rendering opt-in") {
  throw "Benchmark suite diagnostic software-rendering opt-in rejection did not explain the failure. Output: $($DiagnosticOptInFailure.Output)"
}

Write-Json $ResultPath (New-Result "" "" $null)
$MissingMetadataFailure = Invoke-SuiteValidation $ResultPath
if ($MissingMetadataFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result with missing GPU metadata."
}
if ($MissingMetadataFailure.Output -notmatch "GPU metadata") {
  throw "Benchmark suite missing-GPU-metadata rejection did not explain the failure. Output: $($MissingMetadataFailure.Output)"
}

Write-Json $ResultPath (New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WebGpuDeviceLost $true)
$DeviceLossFailure = Invoke-SuiteValidation $ResultPath
if ($DeviceLossFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result with WebGPU device loss."
}
if ($DeviceLossFailure.Output -notmatch "device loss") {
  throw "Benchmark suite device-loss rejection did not explain the failure. Output: $($DeviceLossFailure.Output)"
}

$MissingTelemetry = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$MissingTelemetry.Remove("webgpu_device_lost")
Write-Json $ResultPath $MissingTelemetry
$MissingTelemetryFailure = Invoke-SuiteValidation $ResultPath
if ($MissingTelemetryFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result with missing GPU-instability telemetry."
}
if ($MissingTelemetryFailure.Output -notmatch "webgpu_device_lost") {
  throw "Benchmark suite missing-instability-telemetry rejection did not explain the failure. Output: $($MissingTelemetryFailure.Output)"
}

Write-Json $ResultPath (New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -RenderErrorCount 1)
$RenderErrorFailure = Invoke-SuiteValidation $ResultPath
if ($RenderErrorFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result with render errors."
}
if ($RenderErrorFailure.Output -notmatch "render_error_count") {
  throw "Benchmark suite render-error rejection did not explain the failure. Output: $($RenderErrorFailure.Output)"
}

$CpuFallbackResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$CpuFallbackResult["renderer_type"] = "webgpu"
$CpuFallbackResult["webgpu_cpu_texture_fallback_count"] = 1
Write-Json $ResultPath $CpuFallbackResult
$CpuFallbackFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($CpuFallbackFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU result with CPU texture fallback/readback metadata."
}
if ($CpuFallbackFailure.Output -notmatch "CPU texture fallback|readback") {
  throw "Benchmark suite CPU-fallback rejection did not explain the failure. Output: $($CpuFallbackFailure.Output)"
}

$PipelineQuietFailureResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -PipelineQuietFrames 2 -PipelineQuietAchieved $false
$PipelineQuietFailureResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $PipelineQuietFailureResult
$PipelineQuietFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($PipelineQuietFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU result whose pipeline-quiet warmup was not achieved."
}
if ($PipelineQuietFailure.Output -notmatch "pipeline-quiet warmup") {
  throw "Benchmark suite pipeline-quiet warmup rejection did not explain the failure. Output: $($PipelineQuietFailure.Output)"
}

$PipelineQuietMeasuredCreateResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -PipelineQuietFrames 2 -PipelineQuietAchieved $true -PipelineCreateMeasuredCount 1
$PipelineQuietMeasuredCreateResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $PipelineQuietMeasuredCreateResult
$PipelineQuietMeasuredCreateFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($PipelineQuietMeasuredCreateFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU pipeline-quiet result with measured-window pipeline creation."
}
if ($PipelineQuietMeasuredCreateFailure.Output -notmatch "measured window|measured-window") {
  throw "Benchmark suite measured-window pipeline creation rejection did not explain the failure. Output: $($PipelineQuietMeasuredCreateFailure.Output)"
}

$WarmupInitErrorResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ResourceWarmupTextureInitError "renderer.initTexture failed"
Write-Json $ResultPath $WarmupInitErrorResult
$WarmupInitErrorFailure = Invoke-SuiteValidation $ResultPath
if ($WarmupInitErrorFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result with resource warmup texture initialization error."
}
if ($WarmupInitErrorFailure.Output -notmatch "resource warmup.*texture_init_error") {
  throw "Benchmark suite resource-warmup init-error rejection did not explain the failure. Output: $($WarmupInitErrorFailure.Output)"
}

$QueueInstrumentationResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WebGpuQueueInstrumentation $true
$QueueInstrumentationResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $QueueInstrumentationResult
$QueueInstrumentationFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($QueueInstrumentationFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU queue-instrumented attribution result."
}
if ($QueueInstrumentationFailure.Output -notmatch "queue instrumentation attribution") {
  throw "Benchmark suite queue-instrumentation rejection did not explain the failure. Output: $($QueueInstrumentationFailure.Output)"
}

$BindGroupInstrumentationResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WebGpuBindGroupInstrumentation $true
$BindGroupInstrumentationResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $BindGroupInstrumentationResult
$BindGroupInstrumentationFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($BindGroupInstrumentationFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU bind-group-instrumented attribution result."
}
if ($BindGroupInstrumentationFailure.Output -notmatch "bind-group instrumentation attribution") {
  throw "Benchmark suite bind-group-instrumentation rejection did not explain the failure. Output: $($BindGroupInstrumentationFailure.Output)"
}

$PipelineStateInstrumentationResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WebGpuPipelineStateInstrumentation $true
$PipelineStateInstrumentationResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $PipelineStateInstrumentationResult
$PipelineStateInstrumentationFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($PipelineStateInstrumentationFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU pipeline-state-instrumented attribution result."
}
if ($PipelineStateInstrumentationFailure.Output -notmatch "pipeline-state instrumentation attribution") {
  throw "Benchmark suite pipeline-state-instrumentation rejection did not explain the failure. Output: $($PipelineStateInstrumentationFailure.Output)"
}

$BufferStateInstrumentationResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WebGpuBufferStateInstrumentation $true
$BufferStateInstrumentationResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $BufferStateInstrumentationResult
$BufferStateInstrumentationFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($BufferStateInstrumentationFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU buffer-state-instrumented attribution result."
}
if ($BufferStateInstrumentationFailure.Output -notmatch "buffer-state instrumentation attribution") {
  throw "Benchmark suite buffer-state-instrumentation rejection did not explain the failure. Output: $($BufferStateInstrumentationFailure.Output)"
}

$RenderStateInstrumentationResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WebGpuRenderStateInstrumentation $true
$RenderStateInstrumentationResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $RenderStateInstrumentationResult
$RenderStateInstrumentationFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($RenderStateInstrumentationFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU render-state-instrumented attribution result."
}
if ($RenderStateInstrumentationFailure.Output -notmatch "render-state instrumentation attribution") {
  throw "Benchmark suite render-state-instrumentation rejection did not explain the failure. Output: $($RenderStateInstrumentationFailure.Output)"
}

$ImmediateInstrumentationResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WebGpuImmediateInstrumentation $true
$ImmediateInstrumentationResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $ImmediateInstrumentationResult
$ImmediateInstrumentationFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($ImmediateInstrumentationFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU immediate-instrumented attribution result."
}
if ($ImmediateInstrumentationFailure.Output -notmatch "immediate instrumentation attribution") {
  throw "Benchmark suite immediate-instrumentation rejection did not explain the failure. Output: $($ImmediateInstrumentationFailure.Output)"
}

$SourceTraceResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ViewerTraceWebgpuQueue $true
$SourceTraceResult["renderer_type"] = "webgpu"
Write-Json $ResultPath $SourceTraceResult
$SourceTraceFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($SourceTraceFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a source WebGPU queue trace attribution result."
}
if ($SourceTraceFailure.Output -notmatch "source WebGPU queue trace instrumentation") {
  throw "Benchmark suite source queue-trace rejection did not explain the failure. Output: $($SourceTraceFailure.Output)"
}

$MissingBundleGroupResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$MissingBundleGroupResult["renderer_type"] = "webgpu"
$MissingBundleGroupResult["webgpu_bundle_mode"] = "static"
$MissingBundleGroupResult["webgpu_bundle_groups"] = 0
Write-Json $ResultPath $MissingBundleGroupResult
$MissingBundleGroupFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($MissingBundleGroupFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU static BundleGroup result with no BundleGroup recorded."
}
if ($MissingBundleGroupFailure.Output -notmatch "webgpu_bundle_mode=static.*positive webgpu_bundle_groups") {
  throw "Benchmark suite missing BundleGroup-count rejection did not explain the failure. Output: $($MissingBundleGroupFailure.Output)"
}

$OffModeBundleGroupResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$OffModeBundleGroupResult["renderer_type"] = "webgpu"
$OffModeBundleGroupResult["webgpu_bundle_mode"] = "off"
$OffModeBundleGroupResult["webgpu_bundle_groups"] = 1
Write-Json $ResultPath $OffModeBundleGroupResult
$OffModeBundleGroupFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu"
if ($OffModeBundleGroupFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted WebGPU BundleGroup count metadata while mode was off."
}
if ($OffModeBundleGroupFailure.Output -notmatch "webgpu_bundle_groups must be zero") {
  throw "Benchmark suite off-mode BundleGroup rejection did not explain the failure. Output: $($OffModeBundleGroupFailure.Output)"
}

$UntrustedWebGpuExperiment = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$UntrustedWebGpuExperiment["renderer_type"] = "webgpu"
$UntrustedWebGpuExperiment["benchmark_variant"] = "fork-viewer-exp-webgpu-skip-resource-labels"
$UntrustedWebGpuExperiment["viewer_skip_webgpu_resource_labels"] = $true
Write-Json $ResultPath $UntrustedWebGpuExperiment
$UntrustedWebGpuExperimentFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu" -Variant "fork-viewer-exp-webgpu-skip-resource-labels"
if ($UntrustedWebGpuExperimentFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted trusted-only experiment metadata without viewer trusted-content provenance."
}
if ($UntrustedWebGpuExperimentFailure.Output -notmatch "viewer_mode=true.*viewer_trusted_content=true") {
  throw "Benchmark suite trusted-experiment provenance rejection did not explain the failure. Output: $($UntrustedWebGpuExperimentFailure.Output)"
}

$MissingCopyExternalImageFallbackRejection = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$MissingCopyExternalImageFallbackRejection["renderer_type"] = "webgpu"
$MissingCopyExternalImageFallbackRejection["benchmark_variant"] = "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path"
$MissingCopyExternalImageFallbackRejection["viewer_skip_webgpu_copy_external_image_dest_validation"] = $true
Write-Json $ResultPath $MissingCopyExternalImageFallbackRejection
$MissingCopyExternalImageFallbackRejectionFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu" -Variant "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path"
if ($MissingCopyExternalImageFallbackRejectionFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU copyExternalImage upload experiment without CPU fallback rejection."
}
if ($MissingCopyExternalImageFallbackRejectionFailure.Output -notmatch "copyExternalImage.*viewer_reject_webgpu_cpu_texture_fallback") {
  throw "Benchmark suite missing copyExternalImage CPU-fallback rejection did not explain the failure. Output: $($MissingCopyExternalImageFallbackRejectionFailure.Output)"
}

$ValidCopyExternalImageFallbackRejection = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$ValidCopyExternalImageFallbackRejection["renderer_type"] = "webgpu"
$ValidCopyExternalImageFallbackRejection["benchmark_variant"] = "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path"
$ValidCopyExternalImageFallbackRejection["viewer_skip_webgpu_copy_external_image_dest_validation"] = $true
$ValidCopyExternalImageFallbackRejection["viewer_reject_webgpu_cpu_texture_fallback"] = $true
$ValidCopyExternalImageFallbackRejection["viewer_mode"] = $true
$ValidCopyExternalImageFallbackRejection["viewer_trusted_content"] = $true
Write-Json $ResultPath $ValidCopyExternalImageFallbackRejection
$ValidCopyExternalImageFallbackRejectionSuccess = Invoke-SuiteValidation $ResultPath -Renderer "webgpu" -Variant "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path"
if ($ValidCopyExternalImageFallbackRejectionSuccess.ExitCode -ne 0) {
  throw "Benchmark suite validation rejected a WebGPU copyExternalImage upload experiment with CPU fallback rejection. Output: $($ValidCopyExternalImageFallbackRejectionSuccess.Output)"
}

Write-Json $ResultPath (New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")
$Success = Invoke-SuiteValidation $ResultPath
if ($Success.ExitCode -ne 0) {
  throw "Benchmark suite validation rejected hardware-like GPU metadata. Output: $($Success.Output)"
}

$CacheResult = New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$CacheResult.renderer_type = "webgpu"
$CacheResult.benchmark_variant = "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation"
$CacheResult.browser_flags = @("--disable-software-rasterizer", "--disable-dawn-features=blob_cache_hash_validation")
Write-Json $ResultPath $CacheResult
$CacheFailure = Invoke-SuiteValidation $ResultPath -Renderer "webgpu" -Variant "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation"
if ($CacheFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a WebGPU blob-cache hash-validation result without blob-cache eligibility metadata."
}
if ($CacheFailure.Output -notmatch "webgpu_blob_cache_expected_available") {
  throw "Benchmark suite blob-cache eligibility rejection did not explain the failure. Output: $($CacheFailure.Output)"
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Benchmark suite validation rejects known software-rendered GPU paths, diagnostic software-rendering opt-in results, missing GPU metadata, missing instability telemetry, GPU-unstable results, invalid WebGPU BundleGroup metadata, WebGPU attribution instrumentation, WebGPU CPU texture fallback/readback metadata, resource-warmup initialization errors, unachieved or measured-window-contaminated WebGPU pipeline-quiet warmup, trusted-only experiment metadata without viewer trusted-content provenance, copyExternalImage upload experiments missing CPU-fallback rejection, and cache-ineligible WebGPU blob-cache experiments."

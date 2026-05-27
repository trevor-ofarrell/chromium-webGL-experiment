[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\strict-official-software-renderer-test"

if (Test-Path $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function New-Result {
  param(
    [string]$Variant,
    [string]$GpuName,
    [string]$AngleBackend,
    [AllowNull()]
    [string]$DriverVersion = "test-driver",
    [double]$MeasuredSeconds = 1,
    [double]$WarmupSeconds = 1,
    [string]$ForkRevision = "__default__",
    [bool]$WebGpuDeviceLost = $false,
    [int]$RenderErrorCount = 0,
    [ValidateSet("fresh-temp", "explicit-reuse")]
    [string]$ProfileCacheMode = "fresh-temp",
    [string]$ProfileCacheKey = ""
  )

  $ResultForkRevision = $null
  if ($Variant -match "fork") {
    $ResultForkRevision = if ($ForkRevision -eq "__default__") {
      "test-chromium-revision+viewerpatch-test"
    } else {
      $ForkRevision
    }
  } elseif ($ForkRevision -ne "__default__") {
    $ResultForkRevision = $ForkRevision
  }

  return [ordered]@{
    chromium_revision = "test-chromium-revision"
    fork_revision = $ResultForkRevision
    build_args_hash = "test-build-args-hash"
    platform = "test-platform"
    gpu_name = $GpuName
    driver_version = $DriverVersion
    angle_backend = $AngleBackend
    renderer_type = "webgl2"
    scene_name = "many-draw-calls"
    warmup_seconds = $WarmupSeconds
    measured_seconds = $MeasuredSeconds
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
    benchmark_variant = $Variant
    profile_cache_mode = $ProfileCacheMode
    profile_cache_key = if ($ProfileCacheKey) { $ProfileCacheKey } else { $null }
    profile_reuse_enabled = $ProfileCacheMode -eq "explicit-reuse"
    gpu_timing_enabled = $true
    webgpu_device_lost = $WebGpuDeviceLost
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

function Invoke-NodeCompare {
  param(
    [string]$BaselinePath,
    [string]$ForkPath,
    [string]$ReportPath
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node (Join-Path $Root "scripts\compare_results.mjs") $BaselinePath $ForkPath --strictOfficial --output $ReportPath 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output | ForEach-Object { [string]$_ }) -join " "
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

$Baseline = Join-Path $TempDir "baseline.json"
$Fork = Join-Path $TempDir "fork.json"
$Report = Join-Path $TempDir "report.md"

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device), SwiftShader driver)" "ANGLE (Google, SwiftShader)")
Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")

$Failure = Invoke-NodeCompare $Baseline $Fork $Report
if ($Failure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a known SwiftShader/software-rendered result."
}
if ($Failure.Output -notmatch "software-rendered|SwiftShader") {
  throw "Strict official software-rendering rejection did not explain SwiftShader. Output: $($Failure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")
$DiagnosticOptIn = New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$DiagnosticOptIn["allow_software_rendering"] = $true
Write-Json $Fork $DiagnosticOptIn
$DiagnosticOptInFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($DiagnosticOptInFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a diagnostic software-rendering opt-in result."
}
if ($DiagnosticOptInFailure.Output -notmatch "diagnostic software-rendering opt-in") {
  throw "Strict official diagnostic software-rendering opt-in rejection did not explain the failure. Output: $($DiagnosticOptInFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "" "" $null)
$MissingMetadataFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MissingMetadataFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a result with missing GPU metadata."
}
if ($MissingMetadataFailure.Output -notmatch "GPU/backend metadata") {
  throw "Strict official missing-GPU-metadata rejection did not explain the failure. Output: $($MissingMetadataFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")
$MissingMetric = New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$MissingMetric.Remove("startup_ms_to_first_frame")
Write-Json $Fork $MissingMetric

$MissingMetricFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MissingMetricFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a result with missing required benchmark metric evidence."
}
if ($MissingMetricFailure.Output -notmatch "startup_ms_to_first_frame") {
  throw "Strict official missing-metric-evidence rejection did not explain startup_ms_to_first_frame. Output: $($MissingMetricFailure.Output)"
}

$MissingGpuTiming = New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$MissingGpuTiming.Remove("gpu_timing_enabled")
Write-Json $Fork $MissingGpuTiming

$MissingGpuTimingFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MissingGpuTimingFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a result with missing gpu_timing_enabled evidence."
}
if ($MissingGpuTimingFailure.Output -notmatch "gpu_timing_enabled") {
  throw "Strict official missing-GPU-timing-evidence rejection did not explain gpu_timing_enabled. Output: $($MissingGpuTimingFailure.Output)"
}

$MissingPackageSize = New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$MissingPackageSize["package_size_mb"] = $null
Write-Json $Fork $MissingPackageSize

$MissingPackageSizeFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MissingPackageSizeFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a result with missing package_size_mb evidence."
}
if ($MissingPackageSizeFailure.Output -notmatch "package_size_mb missing or non-positive") {
  throw "Strict official missing-package-size rejection did not explain package_size_mb. Output: $($MissingPackageSizeFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")
Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WebGpuDeviceLost $true)

$DeviceLossFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($DeviceLossFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a result with WebGPU device loss."
}
if ($DeviceLossFailure.Output -notmatch "GPU-unstable|device loss") {
  throw "Strict official device-loss rejection did not explain the failure. Output: $($DeviceLossFailure.Output)"
}

$MissingTelemetry = New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$MissingTelemetry.Remove("webgpu_device_lost")
Write-Json $Fork $MissingTelemetry

$MissingTelemetryFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MissingTelemetryFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a result with missing GPU-instability telemetry."
}
if ($MissingTelemetryFailure.Output -notmatch "GPU-unstable|webgpu_device_lost") {
  throw "Strict official missing-instability-telemetry rejection did not explain the failure. Output: $($MissingTelemetryFailure.Output)"
}

Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -RenderErrorCount 1)

$RenderErrorFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($RenderErrorFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a result with render errors."
}
if ($RenderErrorFailure.Output -notmatch "render_error_count") {
  throw "Strict official render-error rejection did not explain the failure. Output: $($RenderErrorFailure.Output)"
}

$WebGpuCleanBaseline = New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$WebGpuCleanBaseline["renderer_type"] = "webgpu"
$WebGpuCpuFallbackFork = New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$WebGpuCpuFallbackFork["renderer_type"] = "webgpu"
$WebGpuCpuFallbackFork["webgpu_cpu_texture_fallback_detected"] = $true
Write-Json $Baseline $WebGpuCleanBaseline
Write-Json $Fork $WebGpuCpuFallbackFork

$CpuFallbackFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($CpuFallbackFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a WebGPU result with CPU texture fallback/readback metadata."
}
if ($CpuFallbackFailure.Output -notmatch "CPU texture fallback|readback") {
  throw "Strict official CPU-fallback rejection did not explain the failure. Output: $($CpuFallbackFailure.Output)"
}

$WebGpuMissingCopyExternalImageFallbackRejectionFork = New-Result "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$WebGpuMissingCopyExternalImageFallbackRejectionFork["renderer_type"] = "webgpu"
$WebGpuMissingCopyExternalImageFallbackRejectionFork["viewer_skip_webgpu_copy_external_image_dest_validation"] = $true
Write-Json $Baseline $WebGpuCleanBaseline
Write-Json $Fork $WebGpuMissingCopyExternalImageFallbackRejectionFork

$MissingCopyExternalImageFallbackRejectionFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MissingCopyExternalImageFallbackRejectionFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a WebGPU copyExternalImage upload experiment without CPU fallback rejection."
}
if ($MissingCopyExternalImageFallbackRejectionFailure.Output -notmatch "copyExternalImage.*CPU texture fallback rejection") {
  throw "Strict official missing copyExternalImage CPU-fallback rejection did not explain the failure. Output: $($MissingCopyExternalImageFallbackRejectionFailure.Output)"
}

$UntrustedWebGpuExperimentFork = New-Result "fork-viewer-exp-webgpu-skip-resource-labels" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$UntrustedWebGpuExperimentFork["renderer_type"] = "webgpu"
$UntrustedWebGpuExperimentFork["viewer_skip_webgpu_resource_labels"] = $true
Write-Json $Baseline $WebGpuCleanBaseline
Write-Json $Fork $UntrustedWebGpuExperimentFork

$UntrustedWebGpuExperimentFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($UntrustedWebGpuExperimentFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted trusted-only experiment metadata without viewer trusted-content provenance."
}
if ($UntrustedWebGpuExperimentFailure.Output -notmatch "trusted-only experiment|viewer_mode=true.*viewer_trusted_content=true") {
  throw "Strict official trusted-experiment provenance rejection did not explain the failure. Output: $($UntrustedWebGpuExperimentFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")
Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ForkRevision "")

$MissingForkRevisionFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MissingForkRevisionFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a fork result with missing fork_revision."
}
if ($MissingForkRevisionFailure.Output -notmatch "fork_revision") {
  throw "Strict official fork_revision rejection did not explain missing fork_revision. Output: $($MissingForkRevisionFailure.Output)"
}

Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ForkRevision "other-chromium-revision+viewerpatch-test")

$MismatchedForkRevisionFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MismatchedForkRevisionFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a fork_revision derived from the wrong Chromium revision."
}
if ($MismatchedForkRevisionFailure.Output -notmatch "fork_revision") {
  throw "Strict official fork_revision rejection did not explain mismatched fork_revision. Output: $($MismatchedForkRevisionFailure.Output)"
}

Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ForkRevision "test-chromium-revision+not-viewer-patch")

$NonPatchForkRevisionFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($NonPatchForkRevisionFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a fork_revision without the viewerpatch marker."
}
if ($NonPatchForkRevisionFailure.Output -notmatch "viewer patch") {
  throw "Strict official fork_revision rejection did not explain missing viewer patch derivation. Output: $($NonPatchForkRevisionFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ForkRevision "test-chromium-revision+viewerpatch-test")
Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")

$BaselineForkRevisionFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($BaselineForkRevisionFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted fork_revision metadata on a baseline result."
}
if ($BaselineForkRevisionFailure.Output -notmatch "only on fork variants") {
  throw "Strict official baseline fork_revision rejection did not explain non-fork fork_revision metadata. Output: $($BaselineForkRevisionFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")
Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -MeasuredSeconds 2)

$DurationFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($DurationFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted mismatched measured_seconds."
}
if ($DurationFailure.Output -notmatch "measured_seconds") {
  throw "Strict official duration rejection did not explain measured_seconds. Output: $($DurationFailure.Output)"
}

Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -WarmupSeconds 2)

$WarmupFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($WarmupFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted mismatched warmup_seconds."
}
if ($WarmupFailure.Output -notmatch "warmup_seconds") {
  throw "Strict official warmup rejection did not explain warmup_seconds. Output: $($WarmupFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ProfileCacheMode "fresh-temp")
Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ProfileCacheMode "explicit-reuse" -ProfileCacheKey "webgpu-warm-one-prime")

$ProfileCacheFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($ProfileCacheFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted mismatched profile-cache modes."
}
if ($ProfileCacheFailure.Output -notmatch "profile_cache_mode|profile_cache_key") {
  throw "Strict official profile-cache rejection did not explain profile_cache_mode/profile_cache_key. Output: $($ProfileCacheFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ProfileCacheMode "explicit-reuse" -ProfileCacheKey "webgpu-warm-one-prime")
Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)" -ProfileCacheMode "explicit-reuse" -ProfileCacheKey "webgpu-warm-one-prime")

$ProfileCacheAttribution = Invoke-NodeCompare $Baseline $Fork $Report
if ($ProfileCacheAttribution.ExitCode -ne 0) {
  throw "Strict official comparison rejected matched explicit profile-cache attribution inputs. Output: $($ProfileCacheAttribution.Output)"
}
$ProfileCacheAttributionReport = Get-Content -LiteralPath $Report -Raw
if ($ProfileCacheAttributionReport -notmatch "cache-attribution" -or
    $ProfileCacheAttributionReport -notmatch "explicit-reuse/webgpu-warm-one-prime" -or
    $ProfileCacheAttributionReport -notmatch "retained speed claims still require a matching fresh-profile") {
  throw "Strict official comparison report did not label matched profile-reuse rows as cache attribution. Report: $ProfileCacheAttributionReport"
}

$WebGpuBaseline = New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$WebGpuBaseline["renderer_type"] = "webgpu"
$WebGpuFork = New-Result "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)"
$WebGpuFork["renderer_type"] = "webgpu"
$WebGpuFork["browser_flags"] = @("--disable-software-rasterizer", "--disable-dawn-features=blob_cache_hash_validation")
Write-Json $Baseline $WebGpuBaseline
Write-Json $Fork $WebGpuFork

$BlobCacheFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($BlobCacheFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a cache-ineligible WebGPU blob-cache hash-validation result."
}
if ($BlobCacheFailure.Output -notmatch "cache-ineligible|webgpu_blob_cache_expected_available") {
  throw "Strict official blob-cache eligibility rejection did not explain the failure. Output: $($BlobCacheFailure.Output)"
}

Write-Json $Baseline (New-Result "baseline-content-shell" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")
Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")

$Success = Invoke-NodeCompare $Baseline $Fork $Report
if ($Success.ExitCode -ne 0) {
  throw "Strict official comparison rejected hardware-like GPU metadata. Output: $($Success.Output)"
}
if (-not (Test-Path $Report)) {
  throw "Strict official comparison did not write report for hardware-like GPU metadata."
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Strict official comparison rejects known software-rendered GPU paths, diagnostic software-rendering opt-in results, missing GPU metadata, missing required metric/GPU-timing/package-size evidence, missing instability telemetry, GPU-unstable results, WebGPU CPU texture fallback/readback metadata, copyExternalImage upload experiments missing CPU-fallback rejection, trusted-only experiment metadata without viewer trusted-content provenance, cache-ineligible WebGPU blob-cache experiments, missing/mismatched/non-patch fork revision metadata, mismatched duration/warmup/profile-cache mode, and labels matched profile-reuse reports as cache attribution."

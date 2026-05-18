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
    [string]$DriverVersion = "test-driver"
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
  param([string]$PathValue)

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node (Join-Path $Root "scripts\validate_benchmark_suite.mjs") `
      --renderer webgl2 `
      --variant fork-viewer-default `
      --expectedScenes many-draw-calls `
      --requireCheckout `
      --requireBuildArgs `
      --requireForkRevision `
      --expectedForkRevision "test-chromium-revision+viewerpatch-test" `
      --forbidSmoke `
      --rejectSoftwareRendering `
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

Write-Json $ResultPath (New-Result "" "" $null)
$MissingMetadataFailure = Invoke-SuiteValidation $ResultPath
if ($MissingMetadataFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result with missing GPU metadata."
}
if ($MissingMetadataFailure.Output -notmatch "GPU metadata") {
  throw "Benchmark suite missing-GPU-metadata rejection did not explain the failure. Output: $($MissingMetadataFailure.Output)"
}

Write-Json $ResultPath (New-Result "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")
$Success = Invoke-SuiteValidation $ResultPath
if ($Success.ExitCode -ne 0) {
  throw "Benchmark suite validation rejected hardware-like GPU metadata. Output: $($Success.Output)"
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Benchmark suite validation rejects known software-rendered GPU paths and missing GPU metadata."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\suite-duration-test"

if (Test-Path $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function New-Result {
  param(
    [double]$MeasuredSeconds = 120,
    [double]$WarmupSeconds = 20
  )

  return [ordered]@{
    chromium_revision = "test-chromium-revision"
    fork_revision = "test-chromium-revision+viewerpatch-test"
    build_args_hash = "test-build-args-hash"
    platform = "test-platform"
    gpu_name = "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)"
    driver_version = "test-driver"
    angle_backend = "ANGLE (NVIDIA, D3D11)"
    renderer_type = "webgl2"
    scene_name = "many-draw-calls"
    complexity = 2
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
      --expectedMeasuredSeconds 120 `
      --expectedWarmupSeconds 20 `
      --expectedComplexity 2 `
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

Write-Json $ResultPath (New-Result)
$Success = Invoke-SuiteValidation $ResultPath
if ($Success.ExitCode -ne 0) {
  throw "Benchmark suite duration validation rejected matching duration/warmup. Output: $($Success.Output)"
}

Write-Json $ResultPath (New-Result -MeasuredSeconds 1 -WarmupSeconds 20)
$MeasuredFailure = Invoke-SuiteValidation $ResultPath
if ($MeasuredFailure.ExitCode -eq 0) {
  throw "Benchmark suite duration validation accepted mismatched measured_seconds."
}
if ($MeasuredFailure.Output -notmatch "measured_seconds") {
  throw "Benchmark suite duration validation did not explain measured_seconds mismatch. Output: $($MeasuredFailure.Output)"
}

Write-Json $ResultPath (New-Result -MeasuredSeconds 120 -WarmupSeconds 1)
$WarmupFailure = Invoke-SuiteValidation $ResultPath
if ($WarmupFailure.ExitCode -eq 0) {
  throw "Benchmark suite duration validation accepted mismatched warmup_seconds."
}
if ($WarmupFailure.Output -notmatch "warmup_seconds") {
  throw "Benchmark suite duration validation did not explain warmup_seconds mismatch. Output: $($WarmupFailure.Output)"
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Benchmark suite validation enforces expected measured and warmup seconds."

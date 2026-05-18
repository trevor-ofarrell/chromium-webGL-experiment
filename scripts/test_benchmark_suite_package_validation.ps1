[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\suite-package-size-test"

if (Test-Path $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function New-Result {
  param(
    [AllowNull()]
    [object]$PackageSizeMb = 120
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
    warmup_seconds = 20
    measured_seconds = 120
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
    package_size_mb = $PackageSizeMb
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
      --requirePackageSize `
      --expectedMeasuredSeconds 120 `
      --expectedWarmupSeconds 20 `
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
  throw "Benchmark suite package-size validation rejected positive package_size_mb. Output: $($Success.Output)"
}

Write-Json $ResultPath (New-Result -PackageSizeMb $null)
$MissingFailure = Invoke-SuiteValidation $ResultPath
if ($MissingFailure.ExitCode -eq 0) {
  throw "Benchmark suite package-size validation accepted null package_size_mb."
}
if ($MissingFailure.Output -notmatch "package_size_mb") {
  throw "Benchmark suite package-size validation did not explain null package_size_mb. Output: $($MissingFailure.Output)"
}

Write-Json $ResultPath (New-Result -PackageSizeMb 0)
$ZeroFailure = Invoke-SuiteValidation $ResultPath
if ($ZeroFailure.ExitCode -eq 0) {
  throw "Benchmark suite package-size validation accepted zero package_size_mb."
}
if ($ZeroFailure.Output -notmatch "positive") {
  throw "Benchmark suite package-size validation did not explain zero package_size_mb. Output: $($ZeroFailure.Output)"
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Benchmark suite validation enforces package size when requested."

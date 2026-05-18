[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\revision-validation-test"

if (Test-Path $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function New-Result {
  param(
    [string]$ChromiumRevision = "test-chromium-revision",
    [string]$Variant = "fork-viewer-default"
  )

  return [ordered]@{
    chromium_revision = $ChromiumRevision
    fork_revision = "test-chromium-revision+viewerpatch-test"
    build_args_hash = "test-build-args-hash"
    platform = "test-platform"
    gpu_name = "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)"
    driver_version = "test-driver"
    angle_backend = "ANGLE (NVIDIA, D3D11)"
    renderer_type = "webgl2"
    scene_name = "many-draw-calls"
    warmup_seconds = 30
    measured_seconds = 3600
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
    frame_times_ms = @(16, 16, 17)
    process_rss_delta_mb = 0
    renderer_memory_geometries_delta = 0
    renderer_memory_textures_delta = 0
    renderer_programs_delta = 0
  }
}

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Value
  )

  $Value | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $PathValue -Encoding ASCII
}

function Invoke-CommandCapture {
  param([object[]]$Command)

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $CommandArgs = @($Command | Select-Object -Skip 1)
    $Output = & $Command[0] @CommandArgs 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output | ForEach-Object { [string]$_ }) -join " "
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Assert-FailedWithRevision {
  param(
    [object]$Result,
    [string]$Description
  )

  if ($Result.ExitCode -eq 0) {
    throw "$Description accepted a mismatched chromium_revision."
  }
  if ($Result.Output -notmatch "chromium_revision") {
    throw "$Description did not explain chromium_revision mismatch. Output: $($Result.Output)"
  }
}

try {
  $SuitePath = Join-Path $TempDir "fork-viewer-default-many-draw-calls-webgl2.json"
  Write-Json $SuitePath (New-Result -ChromiumRevision "test-chromium-revision")
  $SuiteSuccess = Invoke-CommandCapture @(
    "node",
    (Join-Path $Root "scripts\validate_benchmark_suite.mjs"),
    "--renderer", "webgl2",
    "--variant", "fork-viewer-default",
    "--expectedScenes", "many-draw-calls",
    "--requireCheckout",
    "--requireBuildArgs",
    "--expectedChromiumRevision", "test-chromium-revision",
    "--requireForkRevision",
    "--expectedForkRevision", "test-chromium-revision+viewerpatch-test",
    "--forbidSmoke",
    "--rejectSoftwareRendering",
    "--requireGpuMetadata",
    $SuitePath
  )
  if ($SuiteSuccess.ExitCode -ne 0) {
    throw "Benchmark suite revision validation rejected matching Chromium revision. Output: $($SuiteSuccess.Output)"
  }

  Write-Json $SuitePath (New-Result -ChromiumRevision "stale-chromium-revision")
  $SuiteFailure = Invoke-CommandCapture @(
    "node",
    (Join-Path $Root "scripts\validate_benchmark_suite.mjs"),
    "--renderer", "webgl2",
    "--variant", "fork-viewer-default",
    "--expectedScenes", "many-draw-calls",
    "--requireCheckout",
    "--requireBuildArgs",
    "--expectedChromiumRevision", "test-chromium-revision",
    "--requireForkRevision",
    "--expectedForkRevision", "test-chromium-revision+viewerpatch-test",
    "--forbidSmoke",
    "--rejectSoftwareRendering",
    "--requireGpuMetadata",
    $SuitePath
  )
  Assert-FailedWithRevision $SuiteFailure "Benchmark suite validation"

  $StabilityPath = Join-Path $TempDir "fork-viewer-default-long-stability-instancing-webgl2.json"
  $Stability = New-Result -ChromiumRevision "test-chromium-revision" -Variant "fork-viewer-default-long-stability"
  $Stability.scene_name = "instancing"
  Write-Json $StabilityPath $Stability
  $StabilitySuccess = Invoke-CommandCapture @(
    "node",
    (Join-Path $Root "scripts\validate_stability_result.mjs"),
    $StabilityPath,
    "--minMeasuredSeconds", "3600",
    "--minWarmupSeconds", "30",
    "--expectedRenderer", "webgl2",
    "--expectedScene", "instancing",
    "--expectedVariant", "fork-viewer-default-long-stability",
    "--requireCheckout",
    "--requireBuildArgs",
    "--expectedChromiumRevision", "test-chromium-revision",
    "--requireForkRevision",
    "--expectedForkRevision", "test-chromium-revision+viewerpatch-test",
    "--rejectSoftwareRendering",
    "--requireGpuMetadata",
    "--maxRendererResourceDelta", "0"
  )
  if ($StabilitySuccess.ExitCode -ne 0) {
    throw "Stability revision validation rejected matching Chromium revision. Output: $($StabilitySuccess.Output)"
  }

  $Stability.chromium_revision = "stale-chromium-revision"
  Write-Json $StabilityPath $Stability
  $StabilityFailure = Invoke-CommandCapture @(
    "node",
    (Join-Path $Root "scripts\validate_stability_result.mjs"),
    $StabilityPath,
    "--minMeasuredSeconds", "3600",
    "--minWarmupSeconds", "30",
    "--expectedRenderer", "webgl2",
    "--expectedScene", "instancing",
    "--expectedVariant", "fork-viewer-default-long-stability",
    "--requireCheckout",
    "--requireBuildArgs",
    "--expectedChromiumRevision", "test-chromium-revision",
    "--requireForkRevision",
    "--expectedForkRevision", "test-chromium-revision+viewerpatch-test",
    "--rejectSoftwareRendering",
    "--requireGpuMetadata",
    "--maxRendererResourceDelta", "0"
  )
  Assert-FailedWithRevision $StabilityFailure "Stability validation"
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Suite and stability validation enforce the expected Chromium revision."

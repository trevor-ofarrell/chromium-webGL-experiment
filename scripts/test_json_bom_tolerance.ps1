[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\json-bom-tolerance"

if (Test-Path -LiteralPath $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function Write-JsonBom {
  param(
    [string]$PathValue,
    [object]$Value
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  $Json = $Value | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($PathValue, $Json, [System.Text.UTF8Encoding]::new($true))
  return $PathValue
}

function Invoke-NodeSuccess {
  param(
    [string[]]$Arguments,
    [string]$Description
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }

  if ($ExitCode -ne 0) {
    throw "$Description should accept UTF-8 BOM JSON. Output: $(($Output | ForEach-Object { [string]$_ }) -join ' ')"
  }
}

function Invoke-NodeFailure {
  param(
    [string[]]$Arguments,
    [string]$Description,
    [string]$ExpectedPattern
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }

  $Text = ($Output | ForEach-Object { [string]$_ }) -join ' '
  if ($ExitCode -eq 0) {
    throw "$Description should fail. Output: $Text"
  }
  if ($Text -notmatch $ExpectedPattern) {
    throw "$Description failed without expected message '$ExpectedPattern'. Output: $Text"
  }
}

function New-MetricResult {
  [ordered]@{
    generated_at = "2026-05-22T00:00:00.000Z"
    chromium_revision = "test-chromium-revision"
    fork_revision = $null
    build_args_hash = "test-build-args-hash"
    platform = "test-platform"
    gpu_name = "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)"
    driver_version = "test-driver"
    angle_backend = "ANGLE (NVIDIA, D3D11)"
    renderer_type = "webgl2"
    scene_name = "many-draw-calls"
    complexity = 2
    warmup_seconds = 1
    measured_seconds = 1
    avg_fps = 60
    p50_frame_ms = 16
    p95_frame_ms = 17
    p99_frame_ms = 18
    frame_times_ms = @(16, 17, 18)
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
    process_rss_delta_mb = 0
    renderer_memory_geometries_delta = 0
    renderer_memory_textures_delta = 0
    renderer_programs_delta = 0
    startup_ms_to_first_frame = 500
    browser_binary_size_mb = 100
    viewer_bundle_size_mb = 1
    package_size_mb = 120
    browser_is_from_checkout = $true
    browser_executable = "synthetic-content-shell.exe"
    benchmark_variant = "bom-test"
    webgpu_device_lost = $false
    webgl_context_currently_lost = $false
    webgl_context_lost_count = 0
    render_error_count = 0
    viewer_mode = $false
    browser_flags = @("--disable-software-rasterizer")
  }
}

try {
  $MetricPath = Write-JsonBom (Join-Path $TempDir "bom-metric.json") (New-MetricResult)
  $SummaryPath = Join-Path $TempDir "summary.md"
  $ComparisonPath = Join-Path $TempDir "comparison.md"
  Invoke-NodeSuccess -Arguments @((Join-Path $Root "scripts\validate_metrics.mjs"), $MetricPath) -Description "validate_metrics.mjs"

  $InvalidMetric = New-MetricResult
  $InvalidMetric["webgpu_pipeline_create_measured_count"] = 0.5
  $InvalidMetricPath = Write-JsonBom (Join-Path $TempDir "invalid-fractional-pipeline-count.json") $InvalidMetric
  Invoke-NodeFailure -Arguments @((Join-Path $Root "scripts\validate_metrics.mjs"), $InvalidMetricPath) -Description "validate_metrics.mjs fractional optional count rejection" -ExpectedPattern "webgpu_pipeline_create_measured_count must be an integer"

  $InvalidShaderSource = New-MetricResult
  $InvalidShaderSource["shader_compile_event_source"] = "query-string-fallback"
  $InvalidShaderSourcePath = Write-JsonBom (Join-Path $TempDir "invalid-shader-event-source.json") $InvalidShaderSource
  Invoke-NodeFailure -Arguments @((Join-Path $Root "scripts\validate_metrics.mjs"), $InvalidShaderSourcePath) -Description "validate_metrics.mjs shader event source enum rejection" -ExpectedPattern "shader_compile_event_source must be one of"

  $InvalidNullComplexity = New-MetricResult
  $InvalidNullComplexity["complexity"] = $null
  $InvalidNullComplexityPath = Write-JsonBom (Join-Path $TempDir "invalid-null-complexity.json") $InvalidNullComplexity
  Invoke-NodeFailure -Arguments @((Join-Path $Root "scripts\validate_metrics.mjs"), $InvalidNullComplexityPath) -Description "validate_metrics.mjs null complexity rejection" -ExpectedPattern "complexity must be a finite number"

  $InvalidZeroComplexity = New-MetricResult
  $InvalidZeroComplexity["complexity"] = 0
  $InvalidZeroComplexityPath = Write-JsonBom (Join-Path $TempDir "invalid-zero-complexity.json") $InvalidZeroComplexity
  Invoke-NodeFailure -Arguments @((Join-Path $Root "scripts\validate_metrics.mjs"), $InvalidZeroComplexityPath) -Description "validate_metrics.mjs zero complexity rejection" -ExpectedPattern "complexity must be greater than zero"

  Invoke-NodeSuccess -Arguments @(
    (Join-Path $Root "scripts\validate_benchmark_suite.mjs"),
    "--renderer", "webgl2",
    "--variant", "bom-test",
    "--expectedScenes", "many-draw-calls",
    $MetricPath
  ) -Description "validate_benchmark_suite.mjs"
  Invoke-NodeSuccess -Arguments @((Join-Path $Root "scripts\summarize_results.mjs"), "--output", $SummaryPath, $MetricPath) -Description "summarize_results.mjs"
  Invoke-NodeSuccess -Arguments @((Join-Path $Root "scripts\compare_results.mjs"), "--output", $ComparisonPath, $MetricPath) -Description "compare_results.mjs"

  $SmokePath = Write-JsonBom (Join-Path $TempDir "bom-smoke.json") ([ordered]@{
      generated_at = "2026-05-22T00:00:00.000Z"
      platform = "synthetic"
      browser_executable = "synthetic-content-shell.exe"
      browser_version = "synthetic"
      viewer_mode = $true
      viewer_trusted_content = $true
      viewer_app_url = "http://127.0.0.1:1111/__smoke.html"
      ok = $true
      tests = @(
        [pscustomobject]@{ name = "viewer_launch"; status = "pass" },
        [pscustomobject]@{ name = "webgl2_context"; status = "pass" },
        [pscustomobject]@{ name = "web_platform_basics"; status = "pass"; details = [pscustomobject]@{ canvas_2d = $true; raf_timestamp_ms = 16; performance_delta_ms = 1; fetch_content_type = "image/svg+xml"; fetch_bytes = 100 } },
        [pscustomobject]@{ name = "basic_input_events"; status = "pass"; details = [pscustomobject]@{ events = @("pointerdown", "pointermove", "pointerup", "wheel", "keydown"); pointer_event_constructor = $true; wheel_delta_y = 42; key = "ArrowLeft" } },
        [pscustomobject]@{ name = "three_cube_render"; status = "pass" },
        [pscustomobject]@{ name = "texture_load"; status = "pass" },
        [pscustomobject]@{ name = "shader_material"; status = "pass" },
        [pscustomobject]@{ name = "benchmark_run"; status = "pass"; details = [pscustomobject]@{ scene_name = "many-draw-calls"; renderer_type = "webgl2"; avg_fps = 60; frame_count = 60; startup_ms_to_first_frame = 10 } }
      )
    })
  Invoke-NodeSuccess -Arguments @((Join-Path $Root "scripts\validate_smoke_result.mjs"), "--type", "runtime", $SmokePath) -Description "validate_smoke_result.mjs"

  $PinPath = Write-JsonBom (Join-Path $TempDir "bom-pin-refresh.json") ([ordered]@{
      target_revision = "test-chromium-revision"
      selected_from_upstream_head = $true
      selected_at = "2026-05-21T00:00:00.000Z"
      source = "synthetic BOM tolerance test"
    })
  Invoke-NodeSuccess -Arguments @(
    (Join-Path $Root "scripts\validate_stability_result.mjs"),
    $MetricPath,
    "--pinRefreshManifest", $PinPath,
    "--expectedVariant", "bom-test",
    "--expectedFlagMetadata", "viewer_mode=false",
    "--maxRssDeltaMb", "1",
    "--maxRendererResourceDelta", "0"
  ) -Description "validate_stability_result.mjs"
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "JSON validators accept UTF-8 BOM metric, suite, comparison, summary, smoke, and stability pin files."

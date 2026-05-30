[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\tail-breakdown-analysis"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function Write-JsonNoBom {
  param(
    [string]$PathValue,
    [object]$Data
  )
  $Json = $Data | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($PathValue, $Json, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Node {
  param([string[]]$NodeArgs)
  $PreviousErrorActionPreference = $ErrorActionPreference
  $HadNativePreference = Test-Path Variable:\PSNativeCommandUseErrorActionPreference
  if ($HadNativePreference) {
    $PreviousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
  }
  try {
    $ErrorActionPreference = "Continue"
    $Output = & node @NodeArgs 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output -join "`n")
    }
  } finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
    if ($HadNativePreference) {
      $PSNativeCommandUseErrorActionPreference = $PreviousNativePreference
    }
  }
}

function New-Result {
  param(
    [string]$Variant,
    [double[]]$FrameTimes,
    [double[]]$CpuTimes,
    [double[]]$JsTimes,
    [double[]]$RenderTimes
  )
  return [ordered]@{
    chromium_revision = "test-chromium-revision"
    fork_revision = $null
    build_args_hash = "test-build-args"
    platform = "Windows test"
    gpu_name = "Test GPU"
    driver_version = "test-driver"
    angle_backend = "D3D11"
    renderer_type = "webgpu"
    scene_name = "texture-streaming"
    complexity = 2
    warmup_seconds = 1
    measured_seconds = 5
    avg_fps = 60
    p50_frame_ms = 16
    p95_frame_ms = 16
    p99_frame_ms = 16
    one_percent_low_fps = 60
    point_one_percent_low_fps = 60
    avg_cpu_frame_ms = 10
    avg_gpu_frame_ms = $null
    avg_js_frame_ms = 2
    avg_render_submission_ms = 5
    avg_compositor_latency_ms = $null
    avg_presentation_latency_ms = $null
    max_frame_ms = 16
    dropped_frames = 0
    draw_calls = 100
    triangles = 1000
    texture_upload_mb = 10
    buffer_upload_mb = 0
    shader_compile_events = 0
    js_heap_mb = $null
    gpu_memory_mb = $null
    process_rss_mb = $null
    startup_ms_to_first_frame = 100
    browser_binary_size_mb = 10
    viewer_bundle_size_mb = 1
    package_size_mb = 120
    benchmark_variant = $Variant
    frame_times_ms = $FrameTimes
    cpu_frame_times_ms = $CpuTimes
    js_frame_times_ms = $JsTimes
    render_submission_times_ms = $RenderTimes
  }
}

$BaselinePath = Join-Path $TempDir "baseline.json"
$CandidatePath = Join-Path $TempDir "candidate.json"
$InvalidPath = Join-Path $TempDir "invalid-series.json"
$ReportPath = Join-Path $TempDir "tail-report.md"
$ReportJsonPath = Join-Path $TempDir "tail-report.json"

$Baseline = New-Result `
  -Variant "baseline-content-shell-tail-test" `
  -FrameTimes @(16, 16, 16, 16, 16, 16, 16, 16, 16, 16) `
  -CpuTimes @(10, 10, 10, 10, 10, 10, 10, 10, 10, 10) `
  -JsTimes @(2, 2, 2, 2, 2, 2, 2, 2, 2, 2) `
  -RenderTimes @(5, 5, 5, 5, 5, 5, 5, 5, 5, 5)
$Candidate = New-Result `
  -Variant "fork-viewer-tail-test" `
  -FrameTimes @(16, 16, 16, 16, 16, 16, 16, 16, 18, 20) `
  -CpuTimes @(10, 10, 10, 10, 10, 10, 10, 10, 12, 14) `
  -JsTimes @(2, 2, 2, 2, 2, 2, 2, 2, 3, 4) `
  -RenderTimes @(5, 5, 5, 5, 5, 5, 5, 5, 20, 30)

Write-JsonNoBom $BaselinePath $Baseline
Write-JsonNoBom $CandidatePath $Candidate

$ValidResult = Invoke-Node @((Join-Path $Root "scripts\validate_metrics.mjs"), $BaselinePath, $CandidatePath)
if ($ValidResult.ExitCode -ne 0) {
  throw "validate_metrics.mjs rejected valid optional timing series. Output: $($ValidResult.Output)"
}

$Invalid = New-Result `
  -Variant "fork-viewer-tail-invalid-test" `
  -FrameTimes @(16, 16) `
  -CpuTimes @(10, -1) `
  -JsTimes @(2, 2) `
  -RenderTimes @(5, 5)
Write-JsonNoBom $InvalidPath $Invalid
$InvalidResult = Invoke-Node @((Join-Path $Root "scripts\validate_metrics.mjs"), $InvalidPath)
if ($InvalidResult.ExitCode -eq 0 -or $InvalidResult.Output -notmatch "cpu_frame_times_ms\[1\]") {
  throw "validate_metrics.mjs did not reject an invalid optional timing series. Output: $($InvalidResult.Output)"
}

$AnalysisResult = Invoke-Node @(
  (Join-Path $Root "scripts\analyze_tail_breakdown.mjs"),
  "--baseline", $BaselinePath,
  "--candidate", $CandidatePath,
  "--output", $ReportPath,
  "--json", $ReportJsonPath
)
if ($AnalysisResult.ExitCode -ne 0) {
  throw "analyze_tail_breakdown.mjs failed. Output: $($AnalysisResult.Output)"
}

$Report = Get-Content $ReportPath -Raw
if ($Report -notmatch "Render submission" -or $Report -notmatch "Worst p99 delta series") {
  throw "tail breakdown markdown did not include expected diagnostic rows."
}

$ReportJson = Get-Content $ReportJsonPath -Raw | ConvertFrom-Json
if ($ReportJson.worst_p99_delta_series -ne "render_submission_times_ms") {
  throw "tail breakdown did not identify render_submission_times_ms as the worst p99 delta series."
}

Write-Host "Tail breakdown analysis validates optional timing series and identifies p99 regression sources."

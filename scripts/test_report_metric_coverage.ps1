[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path $Resolved)) {
    throw "Required file not found: $PathValue"
  }
  return Get-Content $Resolved -Raw
}

function Assert-Contains {
  param(
    [string]$Label,
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "$Label missing report metric coverage: $Description. Pattern: $Pattern"
  }
}

$Summary = Read-RepoFile "scripts\summarize_results.mjs"
$Compare = Read-RepoFile "scripts\compare_results.mjs"
$Docs = Read-RepoFile "docs\benchmark_methodology.md"

$SummaryFields = @(
  "avg_fps",
  "one_percent_low_fps",
  "point_one_percent_low_fps",
  "p50_frame_ms",
  "p95_frame_ms",
  "p99_frame_ms",
  "max_frame_ms",
  "avg_cpu_frame_ms",
  "avg_gpu_frame_ms",
  "avg_js_frame_ms",
  "avg_render_submission_ms",
  "avg_compositor_latency_ms",
  "avg_presentation_latency_ms",
  "dropped_frames",
  "draw_calls",
  "triangles",
  "texture_upload_mb",
  "buffer_upload_mb",
  "shader_compile_events",
  "js_heap_mb",
  "gpu_memory_mb",
  "process_rss_mb",
  "startup_ms_to_first_frame",
  "browser_binary_size_mb",
  "viewer_bundle_size_mb",
  "package_size_mb"
)

$SummaryHeaders = @(
  "Variant",
  "Avg FPS",
  "1% Low FPS",
  "0.1% Low FPS",
  "P50 ms",
  "P95 ms",
  "P99 ms",
  "Max ms",
  "CPU ms",
  "GPU ms",
  "JS ms",
  "Submit ms",
  "Compositor ms",
  "Present ms",
  "Dropped",
  "Draw calls",
  "Triangles",
  "Texture MB",
  "Buffer MB",
  "Shader events",
  "JS heap MB",
  "GPU memory MB",
  "RSS MB",
  "Startup ms",
  "Binary MB",
  "Viewer MB",
  "Package MB"
)

$CompareFields = @(
  "avg_fps",
  "one_percent_low_fps",
  "point_one_percent_low_fps",
  "p50_frame_ms",
  "p95_frame_ms",
  "p99_frame_ms",
  "max_frame_ms",
  "avg_cpu_frame_ms",
  "avg_gpu_frame_ms",
  "avg_js_frame_ms",
  "avg_render_submission_ms",
  "avg_compositor_latency_ms",
  "avg_presentation_latency_ms",
  "dropped_frames",
  "process_rss_mb",
  "js_heap_mb",
  "gpu_memory_mb",
  "startup_ms_to_first_frame",
  "draw_calls",
  "triangles",
  "texture_upload_mb",
  "buffer_upload_mb",
  "shader_compile_events",
  "browser_binary_size_mb",
  "viewer_bundle_size_mb",
  "package_size_mb"
)

$CompareHeaders = @(
  "FPS Delta",
  "1% Low Delta",
  "0.1% Low Delta",
  "P50 Delta",
  "P95 Delta",
  "P99 Delta",
  "Max Delta",
  "CPU Delta",
  "GPU Delta",
  "JS Delta",
  "Submit Delta",
  "Compositor Delta",
  "Present Delta",
  "Dropped Delta",
  "RSS Delta",
  "JS heap Delta",
  "GPU memory Delta",
  "Startup Delta",
  "Draw calls Delta",
  "Triangles Delta",
  "Texture Delta",
  "Buffer Delta",
  "Shader events Delta",
  "Binary Delta",
  "Viewer Delta",
  "Package Delta"
)

foreach ($Field in $SummaryFields) {
  Assert-Contains "summarize_results.mjs" $Summary ([regex]::Escape("result.$Field")) "summary references $Field"
}
foreach ($Header in $SummaryHeaders) {
  Assert-Contains "summarize_results.mjs" $Summary ([regex]::Escape($Header)) "summary table header $Header"
}

foreach ($Field in $CompareFields) {
  Assert-Contains "compare_results.mjs" $Compare ([regex]::Escape("result.$Field")) "comparison references $Field"
  Assert-Contains "compare_results.mjs" $Compare ([regex]::Escape("baseline.$Field")) "comparison computes baseline delta for $Field"
}
foreach ($Header in $CompareHeaders) {
  Assert-Contains "compare_results.mjs" $Compare ([regex]::Escape($Header)) "comparison table header $Header"
}

Assert-Contains "compare_results.mjs" $Compare "pct\(row\.avgFpsDelta,\s*row\.avgFps - row\.avgFpsDelta\)" "comparison reports FPS delta percentage"
Assert-Contains "docs/benchmark_methodology.md" $Docs "Human-readable official comparison reports" "docs mention human-readable official comparison reports"

function New-SyntheticResult {
  param(
    [string]$Variant,
    [double]$Offset
  )

  return [ordered]@{
    chromium_revision = "test-chromium-revision"
    fork_revision = if ($Variant -match "fork") { "test-chromium-revision+viewerpatch-test" } else { $null }
    build_args_hash = "test-build-args-hash"
    platform = "TestOS"
    gpu_name = "Test GPU"
    driver_version = "Test Driver"
    angle_backend = "D3D11"
    renderer_type = "webgl2"
    scene_name = "many-draw-calls"
    warmup_seconds = 1
    measured_seconds = 2
    avg_fps = 60 + $Offset
    p50_frame_ms = 16 - $Offset
    p95_frame_ms = 20 - $Offset
    p99_frame_ms = 25 - $Offset
    one_percent_low_fps = 50 + $Offset
    point_one_percent_low_fps = 45 + $Offset
    avg_cpu_frame_ms = 4 - $Offset
    avg_gpu_frame_ms = 5 - $Offset
    avg_js_frame_ms = 1 - ($Offset / 10)
    avg_render_submission_ms = 2 - ($Offset / 10)
    avg_compositor_latency_ms = 3 - ($Offset / 10)
    avg_presentation_latency_ms = 4 - ($Offset / 10)
    max_frame_ms = 30 - $Offset
    dropped_frames = 0
    draw_calls = 1000
    triangles = 12000
    texture_upload_mb = 10 + $Offset
    buffer_upload_mb = 20 + $Offset
    shader_compile_events = 2
    js_heap_mb = 30 + $Offset
    gpu_memory_mb = 40 + $Offset
    process_rss_mb = 500 - $Offset
    startup_ms_to_first_frame = 700 - ($Offset * 10)
    browser_binary_size_mb = 100 - $Offset
    viewer_bundle_size_mb = 5
    package_size_mb = 120 - $Offset
    benchmark_variant = $Variant
  }
}

function Write-JsonNoBom {
  param(
    [string]$PathValue,
    [object]$Value
  )

  $Json = $Value | ConvertTo-Json -Depth 5
  $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($PathValue, $Json, $Utf8NoBom)
}

$TempRoot = Resolve-Path (Join-Path $Root "benchmarks")
$TempDir = Join-Path $TempRoot "tmp\report-metric-coverage"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$BaselinePath = Join-Path $TempDir "baseline.json"
$ForkPath = Join-Path $TempDir "fork.json"
$SummaryPath = Join-Path $TempDir "summary.md"
$ComparePath = Join-Path $TempDir "compare.md"

try {
  Write-JsonNoBom $BaselinePath (New-SyntheticResult "baseline-content-shell" 0)
  Write-JsonNoBom $ForkPath (New-SyntheticResult "fork-viewer-default" 5)

  & node (Join-Path $Root "scripts\summarize_results.mjs") $BaselinePath $ForkPath "--output" $SummaryPath
  if ($LASTEXITCODE -ne 0) {
    throw "summarize_results.mjs failed for synthetic report metric coverage test."
  }
  & node (Join-Path $Root "scripts\compare_results.mjs") $BaselinePath $ForkPath "--output" $ComparePath
  if ($LASTEXITCODE -ne 0) {
    throw "compare_results.mjs failed for synthetic report metric coverage test."
  }

  $SummaryOutput = Get-Content -LiteralPath $SummaryPath -Raw
  $CompareOutput = Get-Content -LiteralPath $ComparePath -Raw
  foreach ($Header in $SummaryHeaders) {
    Assert-Contains "synthetic summary report" $SummaryOutput ([regex]::Escape($Header)) "rendered summary header $Header"
  }
  Assert-Contains "synthetic summary report" $SummaryOutput "baseline-content-shell" "rendered baseline variant row"
  Assert-Contains "synthetic summary report" $SummaryOutput "fork-viewer-default" "rendered fork variant row"
  foreach ($Header in $CompareHeaders) {
    Assert-Contains "synthetic comparison report" $CompareOutput ([regex]::Escape($Header)) "rendered comparison header $Header"
  }
  Assert-Contains "synthetic comparison report" $CompareOutput "fork-viewer-default" "rendered fork variant row"
} finally {
  if (Test-Path $TempDir) {
    $ResolvedTempDir = Resolve-Path $TempDir
    if (-not $ResolvedTempDir.Path.StartsWith($TempRoot.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to clean synthetic report temp directory outside benchmark root: $ResolvedTempDir"
    }
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Report metric coverage checks passed for summary and comparison reports."

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
$OfficialRunner = Read-RepoFile "scripts\run_official_comparison.ps1"
$TrustedRunner = Read-RepoFile "scripts\run_trusted_experiment_matrix.ps1"
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
Assert-Contains "compare_results.mjs" $Compare "--strictEvidence" "comparison supports strict evidence validation"
Assert-Contains "compare_results.mjs" $Compare "Strict comparison evidence validation was enabled" "comparison reports strict evidence validation note"
Assert-Contains "compare_results.mjs" $Compare "missing evidence gpu_timing_enabled" "comparison rejects missing GPU timing evidence in strict mode"
Assert-Contains "compare_results.mjs" $Compare "webgpu_buffer_state_instrumentation_enabled" "comparison rejects buffer-state attribution rows in strict mode"
Assert-Contains "compare_results.mjs" $Compare "webgpu_render_state_instrumentation_enabled" "comparison rejects render-state attribution rows in strict mode"
Assert-Contains "compare_results.mjs" $Compare "webgpu_immediate_instrumentation_enabled" "comparison rejects immediate attribution rows in strict mode"
Assert-Contains "compare_results.mjs" $Compare "cannot use attribution-instrumented results as clean speed evidence" "comparison explains attribution rejection in strict mode"
Assert-Contains "compare_results.mjs" $Compare "Input file digest:" "comparison reports raw input digest"
Assert-Contains "summarize_results.mjs" $Summary "--strictEvidence" "summary supports strict evidence validation"
Assert-Contains "summarize_results.mjs" $Summary "Input file digest:" "summary reports raw input digest"
Assert-Contains "summarize_results.mjs" $Summary "package_size_mb missing or non-positive" "summary rejects missing package-size evidence in strict mode"
Assert-Contains "summarize_results.mjs" $Summary "missing evidence gpu_timing_enabled" "summary rejects missing GPU timing evidence in strict mode"
Assert-Contains "summarize_results.mjs" $Summary "webgpu_buffer_state_instrumentation_enabled" "summary rejects buffer-state attribution rows in strict mode"
Assert-Contains "summarize_results.mjs" $Summary "webgpu_render_state_instrumentation_enabled" "summary rejects render-state attribution rows in strict mode"
Assert-Contains "summarize_results.mjs" $Summary "webgpu_immediate_instrumentation_enabled" "summary rejects immediate attribution rows in strict mode"
Assert-Contains "summarize_results.mjs" $Summary "cannot use attribution-instrumented results as clean speed evidence" "summary explains attribution rejection in strict mode"
Assert-Contains "summarize_results.mjs" $Summary "WebGPU Fast-Path Coverage" "summary renders optional WebGPU fast-path coverage section"
Assert-Contains "summarize_results.mjs" $Summary "webgpu_queue_write_texture_common_layout_count" "summary references WebGPU writeTexture fast-path coverage metric"
Assert-Contains "summarize_results.mjs" $Summary "webgpu_queue_copy_external_image_common_origin_count" "summary references WebGPU copyExternalImage common-origin fast-path coverage metric"
Assert-Contains "summarize_results.mjs" $Summary "webgpu_queue_copy_external_image_explicit_common_origin_count" "summary references WebGPU copyExternalImage explicit common-origin fast-path coverage metric"
Assert-Contains "summarize_results.mjs" $Summary "webgpu_queue_copy_external_image_full_source_count" "summary references WebGPU copyExternalImage fast-path coverage metric"
Assert-Contains "summarize_results.mjs" $Summary "webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count" "summary references WebGPU pipeline descriptor fast-path coverage metric"
Assert-Contains "run_official_comparison.ps1" $OfficialRunner "--strictEvidence" "official summary generation enables strict evidence validation"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedRunner "--strictEvidence" "trusted summary generation enables strict evidence validation"
Assert-Contains "docs/benchmark_methodology.md" $Docs "Human-readable official comparison reports" "docs mention human-readable official comparison reports"
Assert-Contains "docs/benchmark_methodology.md" $Docs "Input file digest" "docs mention report raw input digest"
Assert-Contains "docs/benchmark_methodology.md" $Docs "attribution-instrumented" "docs mention attribution-instrumented report rejection"

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
    gpu_timing_enabled = $true
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
$MissingMetricPath = Join-Path $TempDir "missing-metric.json"
$MissingGpuTimingPath = Join-Path $TempDir "missing-gpu-timing.json"
$MissingPackagePath = Join-Path $TempDir "missing-package.json"
$AttributionPath = Join-Path $TempDir "webgpu-attribution.json"
$SummaryPath = Join-Path $TempDir "summary.md"
$AttributionSummaryPath = Join-Path $TempDir "attribution-summary.md"
$ComparePath = Join-Path $TempDir "compare.md"
$InvalidSummaryPath = Join-Path $TempDir "invalid-summary.md"
$InvalidComparePath = Join-Path $TempDir "invalid-compare.md"

try {
  Write-JsonNoBom $BaselinePath (New-SyntheticResult "baseline-content-shell" 0)
  Write-JsonNoBom $ForkPath (New-SyntheticResult "fork-viewer-default" 2)

  & node (Join-Path $Root "scripts\summarize_results.mjs") $BaselinePath $ForkPath "--strictEvidence" "--output" $SummaryPath
  if ($LASTEXITCODE -ne 0) {
    throw "summarize_results.mjs failed for synthetic report metric coverage test."
  }
  & node (Join-Path $Root "scripts\compare_results.mjs") $BaselinePath $ForkPath "--strictEvidence" "--output" $ComparePath
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
  Assert-Contains "synthetic summary report" $SummaryOutput "Input file digest: ``[0-9a-f]{64}``" "rendered raw input digest"
  Assert-Contains "synthetic summary report" $SummaryOutput "Strict summary evidence validation was enabled" "rendered strict summary evidence note"
  foreach ($Header in $CompareHeaders) {
    Assert-Contains "synthetic comparison report" $CompareOutput ([regex]::Escape($Header)) "rendered comparison header $Header"
  }
  Assert-Contains "synthetic comparison report" $CompareOutput "fork-viewer-default" "rendered fork variant row"
  Assert-Contains "synthetic comparison report" $CompareOutput "Input file digest: ``[0-9a-f]{64}``" "rendered raw input digest"
  Assert-Contains "synthetic comparison report" $CompareOutput "Strict comparison evidence validation was enabled" "rendered strict comparison evidence note"

  $AttributionResult = New-SyntheticResult "fork-viewer-webgpu-buffer-attribution" 2
  $AttributionResult["renderer_type"] = "webgpu"
  $AttributionResult["scene_name"] = "texture-streaming"
  $AttributionResult["webgpu_buffer_state_instrumentation_enabled"] = $true
  $AttributionResult["webgpu_queue_write_texture_count"] = 10
  $AttributionResult["webgpu_queue_write_texture_common_layout_count"] = 8
  $AttributionResult["webgpu_queue_write_texture_common_extent_count"] = 9
  $AttributionResult["webgpu_queue_copy_external_image_count"] = 7
  $AttributionResult["webgpu_queue_copy_external_image_default_origin_count"] = 6
  $AttributionResult["webgpu_queue_copy_external_image_common_origin_count"] = 7
  $AttributionResult["webgpu_queue_copy_external_image_explicit_common_origin_count"] = 1
  $AttributionResult["webgpu_queue_copy_external_image_srgb_destination_count"] = 7
  $AttributionResult["webgpu_queue_copy_external_image_full_source_count"] = 5
  $AttributionResult["webgpu_pipeline_descriptor_stack_fast_path_eligible_count"] = 4
  $AttributionResult["webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count"] = 3
  Write-JsonNoBom $AttributionPath $AttributionResult

  & node (Join-Path $Root "scripts\summarize_results.mjs") $AttributionPath "--output" $AttributionSummaryPath
  if ($LASTEXITCODE -ne 0) {
    throw "summarize_results.mjs failed for synthetic WebGPU fast-path coverage report."
  }
  $AttributionSummaryOutput = Get-Content -LiteralPath $AttributionSummaryPath -Raw
  Assert-Contains "synthetic attribution summary report" $AttributionSummaryOutput "WebGPU Fast-Path Coverage" "rendered WebGPU fast-path coverage section"
  Assert-Contains "synthetic attribution summary report" $AttributionSummaryOutput "Common writeTexture layout" "rendered writeTexture fast-path coverage header"
  Assert-Contains "synthetic attribution summary report" $AttributionSummaryOutput "Explicit common source origin" "rendered copyExternalImage explicit common-origin coverage header"
  Assert-Contains "synthetic attribution summary report" $AttributionSummaryOutput "Full-source copy" "rendered copyExternalImage fast-path coverage header"
  Assert-Contains "synthetic attribution summary report" $AttributionSummaryOutput "\| texture-streaming \| webgpu \| fork-viewer-webgpu-buffer-attribution \| 10 \| 8 \| 9 \| 7 \| 6 \| 7 \| 1 \| 7 \| 5 \| 4 \| 3 \|" "rendered WebGPU fast-path coverage counters"

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $AttributionSummaryOutput = & node (Join-Path $Root "scripts\summarize_results.mjs") $BaselinePath $AttributionPath "--strictEvidence" "--output" $InvalidSummaryPath 2>&1
    $AttributionSummaryExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($AttributionSummaryExit -eq 0) {
    throw "summarize_results.mjs strict mode accepted WebGPU buffer-state attribution evidence."
  }
  $AttributionSummaryText = ($AttributionSummaryOutput | ForEach-Object { [string]$_ }) -join " "
  if ($AttributionSummaryText -notmatch "buffer-state instrumentation attribution run") {
    throw "summarize_results.mjs strict mode did not explain WebGPU buffer-state attribution rejection. Output: $AttributionSummaryText"
  }

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $AttributionCompareOutput = & node (Join-Path $Root "scripts\compare_results.mjs") $BaselinePath $AttributionPath "--strictEvidence" "--output" $InvalidComparePath 2>&1
    $AttributionCompareExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($AttributionCompareExit -eq 0) {
    throw "compare_results.mjs strict mode accepted WebGPU buffer-state attribution evidence."
  }
  $AttributionCompareText = ($AttributionCompareOutput | ForEach-Object { [string]$_ }) -join " "
  if ($AttributionCompareText -notmatch "buffer-state instrumentation attribution run") {
    throw "compare_results.mjs strict mode did not explain WebGPU buffer-state attribution rejection. Output: $AttributionCompareText"
  }

  $MissingMetric = New-SyntheticResult "fork-viewer-default" 2
  $MissingMetric.Remove("startup_ms_to_first_frame")
  Write-JsonNoBom $MissingMetricPath $MissingMetric

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $MissingMetricOutput = & node (Join-Path $Root "scripts\summarize_results.mjs") $BaselinePath $MissingMetricPath "--strictEvidence" "--output" $InvalidSummaryPath 2>&1
    $MissingMetricExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($MissingMetricExit -eq 0) {
    throw "summarize_results.mjs strict mode accepted missing startup_ms_to_first_frame evidence."
  }
  $MissingMetricText = ($MissingMetricOutput | ForEach-Object { [string]$_ }) -join " "
  if ($MissingMetricText -notmatch "startup_ms_to_first_frame") {
    throw "summarize_results.mjs strict mode did not explain missing startup_ms_to_first_frame evidence. Output: $MissingMetricText"
  }

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $MissingCompareMetricOutput = & node (Join-Path $Root "scripts\compare_results.mjs") $BaselinePath $MissingMetricPath "--strictEvidence" "--output" $InvalidComparePath 2>&1
    $MissingCompareMetricExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($MissingCompareMetricExit -eq 0) {
    throw "compare_results.mjs strict mode accepted missing startup_ms_to_first_frame evidence."
  }
  $MissingCompareMetricText = ($MissingCompareMetricOutput | ForEach-Object { [string]$_ }) -join " "
  if ($MissingCompareMetricText -notmatch "startup_ms_to_first_frame") {
    throw "compare_results.mjs strict mode did not explain missing startup_ms_to_first_frame evidence. Output: $MissingCompareMetricText"
  }

  $MissingGpuTiming = New-SyntheticResult "fork-viewer-default" 2
  $MissingGpuTiming.Remove("gpu_timing_enabled")
  Write-JsonNoBom $MissingGpuTimingPath $MissingGpuTiming

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $MissingGpuTimingOutput = & node (Join-Path $Root "scripts\summarize_results.mjs") $BaselinePath $MissingGpuTimingPath "--strictEvidence" "--output" $InvalidSummaryPath 2>&1
    $MissingGpuTimingExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($MissingGpuTimingExit -eq 0) {
    throw "summarize_results.mjs strict mode accepted missing gpu_timing_enabled evidence."
  }
  $MissingGpuTimingText = ($MissingGpuTimingOutput | ForEach-Object { [string]$_ }) -join " "
  if ($MissingGpuTimingText -notmatch "gpu_timing_enabled") {
    throw "summarize_results.mjs strict mode did not explain missing gpu_timing_enabled evidence. Output: $MissingGpuTimingText"
  }

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $MissingCompareGpuTimingOutput = & node (Join-Path $Root "scripts\compare_results.mjs") $BaselinePath $MissingGpuTimingPath "--strictEvidence" "--output" $InvalidComparePath 2>&1
    $MissingCompareGpuTimingExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($MissingCompareGpuTimingExit -eq 0) {
    throw "compare_results.mjs strict mode accepted missing gpu_timing_enabled evidence."
  }
  $MissingCompareGpuTimingText = ($MissingCompareGpuTimingOutput | ForEach-Object { [string]$_ }) -join " "
  if ($MissingCompareGpuTimingText -notmatch "gpu_timing_enabled") {
    throw "compare_results.mjs strict mode did not explain missing gpu_timing_enabled evidence. Output: $MissingCompareGpuTimingText"
  }

  $MissingPackage = New-SyntheticResult "fork-viewer-default" 2
  $MissingPackage["package_size_mb"] = $null
  Write-JsonNoBom $MissingPackagePath $MissingPackage

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $MissingPackageOutput = & node (Join-Path $Root "scripts\summarize_results.mjs") $BaselinePath $MissingPackagePath "--strictEvidence" "--output" $InvalidSummaryPath 2>&1
    $MissingPackageExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($MissingPackageExit -eq 0) {
    throw "summarize_results.mjs strict mode accepted missing package_size_mb evidence."
  }
  $MissingPackageText = ($MissingPackageOutput | ForEach-Object { [string]$_ }) -join " "
  if ($MissingPackageText -notmatch "package_size_mb missing or non-positive") {
    throw "summarize_results.mjs strict mode did not explain missing package_size_mb evidence. Output: $MissingPackageText"
  }

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $MissingComparePackageOutput = & node (Join-Path $Root "scripts\compare_results.mjs") $BaselinePath $MissingPackagePath "--strictEvidence" "--output" $InvalidComparePath 2>&1
    $MissingComparePackageExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($MissingComparePackageExit -eq 0) {
    throw "compare_results.mjs strict mode accepted missing package_size_mb evidence."
  }
  $MissingComparePackageText = ($MissingComparePackageOutput | ForEach-Object { [string]$_ }) -join " "
  if ($MissingComparePackageText -notmatch "package_size_mb missing or non-positive") {
    throw "compare_results.mjs strict mode did not explain missing package_size_mb evidence. Output: $MissingComparePackageText"
  }
} finally {
  if (Test-Path $TempDir) {
    $ResolvedTempDir = Resolve-Path $TempDir
    if (-not $ResolvedTempDir.Path.StartsWith($TempRoot.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to clean synthetic report temp directory outside benchmark root: $ResolvedTempDir"
    }
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Report metric coverage checks passed for summary and comparison reports, including strict summary/comparison evidence validation."

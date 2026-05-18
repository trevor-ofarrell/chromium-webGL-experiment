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
    [string]$ForkRevision = "__default__"
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

Write-Json $Baseline (New-Result "baseline-content-shell" "" "" $null)
$MissingMetadataFailure = Invoke-NodeCompare $Baseline $Fork $Report
if ($MissingMetadataFailure.ExitCode -eq 0) {
  throw "Strict official comparison accepted a result with missing GPU metadata."
}
if ($MissingMetadataFailure.Output -notmatch "GPU/backend metadata") {
  throw "Strict official missing-GPU-metadata rejection did not explain the failure. Output: $($MissingMetadataFailure.Output)"
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

Write-Json $Fork (New-Result "fork-viewer-default" "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)" "ANGLE (NVIDIA, D3D11)")

$Success = Invoke-NodeCompare $Baseline $Fork $Report
if ($Success.ExitCode -ne 0) {
  throw "Strict official comparison rejected hardware-like GPU metadata. Output: $($Success.Output)"
}
if (-not (Test-Path $Report)) {
  throw "Strict official comparison did not write report for hardware-like GPU metadata."
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Strict official comparison rejects known software-rendered GPU paths, missing GPU metadata, missing/mismatched/non-patch fork revision metadata, and mismatched duration/warmup."

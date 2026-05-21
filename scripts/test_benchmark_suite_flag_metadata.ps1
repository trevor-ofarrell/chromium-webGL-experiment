[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\suite-flag-metadata-test"

if (Test-Path $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function New-Result {
  param(
    [bool]$ViewerMode = $true,
    [bool]$ViewerTrustedContent = $true,
    [bool]$ViewerInProcessGpu = $true,
    [AllowNull()]
    [object]$ViewerForceAngleBackend = "d3d11",
    [switch]$OmitSingleProcess
  )

  $Result = [ordered]@{
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
    frame_times_ms = @(16, 16.5, 17, 18)
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
    browser_executable = "C:\synthetic\fork-content_shell.exe"
    browser_is_from_checkout = $true
    benchmark_variant = "fork-viewer-exp-in-process-gpu"
    viewer_mode = $ViewerMode
    viewer_block_external_navigation = $ViewerMode
    viewer_trusted_content = $ViewerTrustedContent
    viewer_aggressive_gpu = $false
    viewer_relaxed_webgl_validation = $false
    viewer_in_process_gpu = $ViewerInProcessGpu
    viewer_force_angle_backend = $ViewerForceAngleBackend
    viewer_disable_unneeded_blink_features = $false
    viewer_direct_gpu_presentation = $false
    requested_angle_backend = $ViewerForceAngleBackend
    browser_flags = @("--disable-software-rasterizer")
  }
  if (-not $OmitSingleProcess) {
    $Result.viewer_single_process = $false
  }
  return $Result
}

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Value
  )
  $Value | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $PathValue -Encoding ASCII
}

function Invoke-SuiteValidation {
  param([string]$PathValue)

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node (Join-Path $Root "scripts\validate_benchmark_suite.mjs") `
      --renderer webgl2 `
      --variant fork-viewer-exp-in-process-gpu `
      --expectedScenes many-draw-calls `
      --requireCheckout `
      --requireBuildArgs `
      --expectedBuildArgsHash "test-build-args-hash" `
      --requireForkRevision `
      --expectedForkRevision "test-chromium-revision+viewerpatch-test" `
      --expectedBrowser "C:\synthetic\fork-content_shell.exe" `
      --forbidSmoke `
      --rejectSoftwareRendering `
      --requireGpuMetadata `
      --requirePackageSize `
      --requireFrameTimes `
      --expectedMeasuredSeconds 120 `
      --expectedWarmupSeconds 20 `
      --expectedFlagMetadata viewer_mode=true `
      --expectedFlagMetadata viewer_block_external_navigation=true `
      --expectedFlagMetadata viewer_trusted_content=true `
      --expectedFlagMetadata viewer_in_process_gpu=true `
      --expectedFlagMetadata viewer_single_process=false `
      --expectedFlagMetadata viewer_force_angle_backend=d3d11 `
      --expectedFlagMetadata requested_angle_backend=d3d11 `
      --requiredBrowserFlag "--disable-software-rasterizer" `
      $PathValue 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output | ForEach-Object { [string]$_ }) -join " "
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

$ResultPath = Join-Path $TempDir "fork-viewer-exp-in-process-gpu-many-draw-calls-webgl2.json"

Write-Json $ResultPath (New-Result)
$Success = Invoke-SuiteValidation $ResultPath
if ($Success.ExitCode -ne 0) {
  throw "Benchmark suite flag metadata validation rejected matching metadata. Output: $($Success.Output)"
}

Write-Json $ResultPath (New-Result -ViewerInProcessGpu:$false)
$Mismatch = Invoke-SuiteValidation $ResultPath
if ($Mismatch.ExitCode -eq 0) {
  throw "Benchmark suite flag metadata validation accepted mismatched viewer_in_process_gpu."
}
if ($Mismatch.Output -notmatch "viewer_in_process_gpu") {
  throw "Benchmark suite flag metadata mismatch did not name viewer_in_process_gpu. Output: $($Mismatch.Output)"
}

Write-Json $ResultPath (New-Result -OmitSingleProcess)
$Missing = Invoke-SuiteValidation $ResultPath
if ($Missing.ExitCode -eq 0) {
  throw "Benchmark suite flag metadata validation accepted missing viewer_single_process."
}
if ($Missing.Output -notmatch "viewer_single_process") {
  throw "Benchmark suite flag metadata missing-field failure did not name viewer_single_process. Output: $($Missing.Output)"
}

Write-Json $ResultPath (New-Result)
$WrongBrowser = Get-Content $ResultPath -Raw | ConvertFrom-Json
$WrongBrowser.browser_executable = "C:\synthetic\other-content_shell.exe"
Write-Json $ResultPath $WrongBrowser
$WrongBrowserFailure = Invoke-SuiteValidation $ResultPath
if ($WrongBrowserFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result from the wrong browser executable."
}
if ($WrongBrowserFailure.Output -notmatch "browser_executable") {
  throw "Benchmark suite browser executable mismatch did not name browser_executable. Output: $($WrongBrowserFailure.Output)"
}

Write-Json $ResultPath (New-Result)
$WrongBuildArgsHash = Get-Content $ResultPath -Raw | ConvertFrom-Json
$WrongBuildArgsHash.build_args_hash = "other-build-args-hash"
Write-Json $ResultPath $WrongBuildArgsHash
$WrongBuildArgsHashFailure = Invoke-SuiteValidation $ResultPath
if ($WrongBuildArgsHashFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result with the wrong build_args_hash."
}
if ($WrongBuildArgsHashFailure.Output -notmatch "build_args_hash") {
  throw "Benchmark suite build-args hash mismatch did not name build_args_hash. Output: $($WrongBuildArgsHashFailure.Output)"
}

Write-Json $ResultPath (New-Result)
$MissingLaunchFlag = Get-Content $ResultPath -Raw | ConvertFrom-Json
$MissingLaunchFlag.browser_flags = @()
Write-Json $ResultPath $MissingLaunchFlag
$MissingLaunchFlagFailure = Invoke-SuiteValidation $ResultPath
if ($MissingLaunchFlagFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result without the required effective browser launch flag."
}
if ($MissingLaunchFlagFailure.Output -notmatch "browser_flags.*--disable-software-rasterizer") {
  throw "Benchmark suite missing-browser-flag failure did not name browser_flags and --disable-software-rasterizer. Output: $($MissingLaunchFlagFailure.Output)"
}

Write-Json $ResultPath (New-Result)
$MissingFrameTimes = Get-Content $ResultPath -Raw | ConvertFrom-Json
$MissingFrameTimes.PSObject.Properties.Remove("frame_times_ms")
Write-Json $ResultPath $MissingFrameTimes
$MissingFrameTimesFailure = Invoke-SuiteValidation $ResultPath
if ($MissingFrameTimesFailure.ExitCode -eq 0) {
  throw "Benchmark suite validation accepted a result without required raw frame-time samples."
}
if ($MissingFrameTimesFailure.Output -notmatch "frame_times_ms") {
  throw "Benchmark suite missing-frame-times failure did not name frame_times_ms. Output: $($MissingFrameTimesFailure.Output)"
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Benchmark suite validation enforces expected trusted viewer flag metadata, browser executable provenance, build-args hash provenance, required launch flags, and raw frame-time samples."

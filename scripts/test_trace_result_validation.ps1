[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TmpDir = Join-Path $Root "benchmarks\tmp\trace-result-validation-test"
$Validator = Join-Path $Root "scripts\validate_trace_result.mjs"

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Value
  )
  $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PathValue -Encoding UTF8
}

function New-Sidecar {
  param(
    [string]$Scene = "many-draw-calls",
    [string]$Renderer = "webgl2",
    [double]$Duration = 10,
    [double]$Warmup = 2,
    [double]$StartDelayMs = 2000,
    [double]$AvgFps = 60,
    [string]$Browser = "test-browser.exe"
  )
  return [pscustomobject]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    platform = "test-platform"
    browser = $Browser
    gpu_name = "NVIDIA Test GPU"
    driver_version = "test-driver"
    angle_backend = "ANGLE D3D11"
    scene = $Scene
    renderer = $Renderer
    duration_seconds = $Duration
    warmup_seconds = $Warmup
    start_delay_ms = $StartDelayMs
    benchmark_hud_enabled = $false
    viewer_mode = $true
    viewer_block_external_navigation = $true
    viewer_trusted_content = $true
    viewer_aggressive_gpu = $false
    viewer_relaxed_webgl_validation = $false
    viewer_in_process_gpu = $false
    viewer_single_process = $false
    viewer_force_angle_backend = $null
    requested_angle_backend = $null
    viewer_disable_unneeded_blink_features = $false
    viewer_direct_gpu_presentation = $false
    browser_flags = @("--disable-software-rasterizer")
    categories = "gpu,viz,v8"
    webgpu_queue_write_texture_common_layout_count = 8
    webgpu_queue_write_texture_common_extent_count = 9
    webgpu_queue_copy_external_image_default_origin_count = 6
    webgpu_queue_copy_external_image_common_origin_count = 7
    webgpu_queue_copy_external_image_explicit_common_origin_count = 1
    webgpu_queue_copy_external_image_srgb_destination_count = 7
    webgpu_queue_copy_external_image_full_source_count = 5
    webgpu_pipeline_descriptor_stack_fast_path_eligible_count = 4
    webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count = 3
    benchmark_result = [pscustomobject]@{
      scene_name = $Scene
      renderer_type = $Renderer
      measured_seconds = $Duration
      warmup_seconds = $Warmup
      avg_fps = $AvgFps
      startup_ms_to_first_frame = 123
      webgpu_queue_write_texture_common_layout_count = 8
      webgpu_queue_write_texture_common_extent_count = 9
      webgpu_queue_copy_external_image_default_origin_count = 6
      webgpu_queue_copy_external_image_common_origin_count = 7
      webgpu_queue_copy_external_image_explicit_common_origin_count = 1
      webgpu_queue_copy_external_image_srgb_destination_count = 7
      webgpu_queue_copy_external_image_full_source_count = 5
      webgpu_pipeline_descriptor_stack_fast_path_eligible_count = 4
      webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count = 3
    }
  }
}

function Invoke-Validator {
  param([string[]]$ValidatorArgs)
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node $Validator @ValidatorArgs 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output | ForEach-Object { [string]$_ }) -join "`n"
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

if (Test-Path -LiteralPath $TmpDir) {
  Remove-Item -LiteralPath $TmpDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null

try {
  $Valid = Join-Path $TmpDir "valid.result.json"
  Write-Json $Valid (New-Sidecar)
  $Result = Invoke-Validator -ValidatorArgs @(
    "--expectedScene", "many-draw-calls",
    "--expectedRenderer", "webgl2",
    "--expectedBrowser", "test-browser.exe",
    "--expectedDuration", "10",
    "--expectedWarmup", "2",
    "--expectedStartDelayMs", "2000",
    "--expectedFlagMetadata", "viewer_mode=true",
    "--expectedFlagMetadata", "benchmark_hud_enabled=false",
    "--expectedFlagMetadata", "viewer_block_external_navigation=true",
    "--expectedFlagMetadata", "viewer_trusted_content=true",
    "--expectedFlagMetadata", "viewer_force_angle_backend=null",
    "--rejectSoftwareRendering",
    "--requiredBrowserFlag", "--disable-software-rasterizer",
    $Valid
  )
  if ($Result.ExitCode -ne 0) {
    throw "Expected valid trace sidecar to pass. Output: $($Result.Output)"
  }

  $WrongScene = Join-Path $TmpDir "wrong-scene.result.json"
  Write-Json $WrongScene (New-Sidecar -Scene "instancing")
  $Result = Invoke-Validator -ValidatorArgs @("--expectedScene", "many-draw-calls", $WrongScene)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "scene is instancing") {
    throw "Expected mismatched trace sidecar scene to fail. Output: $($Result.Output)"
  }

  $WrongDelay = Join-Path $TmpDir "wrong-delay.result.json"
  Write-Json $WrongDelay (New-Sidecar -StartDelayMs 0)
  $Result = Invoke-Validator -ValidatorArgs @("--expectedStartDelayMs", "2000", $WrongDelay)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "start_delay_ms is 0") {
    throw "Expected mismatched trace sidecar start delay to fail. Output: $($Result.Output)"
  }

  $WrongBrowser = Join-Path $TmpDir "wrong-browser.result.json"
  Write-Json $WrongBrowser (New-Sidecar -Browser "other-browser.exe")
  $Result = Invoke-Validator -ValidatorArgs @("--expectedBrowser", "test-browser.exe", $WrongBrowser)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "browser is .*other-browser\.exe") {
    throw "Expected mismatched trace sidecar browser to fail. Output: $($Result.Output)"
  }

  $WrongBenchmark = Join-Path $TmpDir "wrong-benchmark.result.json"
  $Sidecar = New-Sidecar
  $Sidecar.benchmark_result.renderer_type = "webgpu"
  Write-Json $WrongBenchmark $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @($WrongBenchmark)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "benchmark_result\.renderer_type") {
    throw "Expected mismatched embedded benchmark renderer to fail. Output: $($Result.Output)"
  }

  $WrongFastPathCoverage = Join-Path $TmpDir "wrong-fast-path-coverage.result.json"
  $Sidecar = New-Sidecar -Renderer "webgpu"
  $Sidecar.webgpu_queue_copy_external_image_full_source_count = 99
  Write-Json $WrongFastPathCoverage $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @($WrongFastPathCoverage)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "webgpu_queue_copy_external_image_full_source_count.*benchmark_result") {
    throw "Expected mismatched WebGPU fast-path coverage metadata to fail. Output: $($Result.Output)"
  }

  $WrongFlag = Join-Path $TmpDir "wrong-flag.result.json"
  $Sidecar = New-Sidecar
  $Sidecar.viewer_trusted_content = $false
  Write-Json $WrongFlag $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @("--expectedFlagMetadata", "viewer_trusted_content=true", $WrongFlag)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "viewer_trusted_content is false") {
    throw "Expected mismatched trace sidecar viewer flag metadata to fail. Output: $($Result.Output)"
  }

  $MissingBrowserFlag = Join-Path $TmpDir "missing-browser-flag.result.json"
  $Sidecar = New-Sidecar
  $Sidecar.browser_flags = @()
  Write-Json $MissingBrowserFlag $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @("--requiredBrowserFlag", "--disable-software-rasterizer", $MissingBrowserFlag)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "browser_flags.*--disable-software-rasterizer") {
    throw "Expected trace sidecar without required browser flag to fail. Output: $($Result.Output)"
  }

  $SoftwareRenderer = Join-Path $TmpDir "software-renderer.result.json"
  $Sidecar = New-Sidecar
  $Sidecar.gpu_name = "Google SwiftShader"
  Write-Json $SoftwareRenderer $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @("--rejectSoftwareRendering", $SoftwareRenderer)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "software-rendered.*SwiftShader") {
    throw "Expected trace sidecar with software renderer metadata to fail. Output: $($Result.Output)"
  }

  $SoftwareBenchmark = Join-Path $TmpDir "software-benchmark.result.json"
  $Sidecar = New-Sidecar
  $Sidecar.benchmark_result | Add-Member -NotePropertyName gpu_name -NotePropertyValue "Microsoft Basic Render Driver" -Force
  Write-Json $SoftwareBenchmark $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @("--rejectSoftwareRendering", $SoftwareBenchmark)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "benchmark_result.*Microsoft Basic Render Driver") {
    throw "Expected trace sidecar with software-rendered embedded benchmark metadata to fail. Output: $($Result.Output)"
  }

  $DiagnosticOptIn = Join-Path $TmpDir "diagnostic-opt-in.result.json"
  $Sidecar = New-Sidecar
  $Sidecar | Add-Member -NotePropertyName allow_software_rendering -NotePropertyValue $true -Force
  Write-Json $DiagnosticOptIn $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @("--rejectSoftwareRendering", $DiagnosticOptIn)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "diagnostic software-rendering opt-in") {
    throw "Expected trace sidecar with diagnostic software-rendering opt-in metadata to fail. Output: $($Result.Output)"
  }

  $DiagnosticBenchmarkOptIn = Join-Path $TmpDir "diagnostic-benchmark-opt-in.result.json"
  $Sidecar = New-Sidecar
  $Sidecar.benchmark_result | Add-Member -NotePropertyName allow_software_rendering -NotePropertyValue $true -Force
  Write-Json $DiagnosticBenchmarkOptIn $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @("--rejectSoftwareRendering", $DiagnosticBenchmarkOptIn)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "benchmark_result uses diagnostic software-rendering opt-in") {
    throw "Expected trace sidecar with diagnostic software-rendering opt-in embedded benchmark metadata to fail. Output: $($Result.Output)"
  }

  $MissingBundleGroup = Join-Path $TmpDir "missing-bundlegroup.result.json"
  $Sidecar = New-Sidecar -Scene "texture-streaming" -Renderer "webgpu"
  $Sidecar | Add-Member -NotePropertyName webgpu_bundle_mode -NotePropertyValue "static" -Force
  $Sidecar | Add-Member -NotePropertyName webgpu_bundle_groups -NotePropertyValue 0 -Force
  $Sidecar.benchmark_result | Add-Member -NotePropertyName webgpu_bundle_mode -NotePropertyValue "static" -Force
  $Sidecar.benchmark_result | Add-Member -NotePropertyName webgpu_bundle_groups -NotePropertyValue 0 -Force
  Write-Json $MissingBundleGroup $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @($MissingBundleGroup)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "webgpu_bundle_mode=static requires a positive webgpu_bundle_groups") {
    throw "Expected trace sidecar with static BundleGroup mode and no recorded BundleGroups to fail. Output: $($Result.Output)"
  }

  $OffModeBundleGroup = Join-Path $TmpDir "off-mode-bundlegroup.result.json"
  $Sidecar = New-Sidecar -Scene "texture-streaming" -Renderer "webgpu"
  $Sidecar | Add-Member -NotePropertyName webgpu_bundle_mode -NotePropertyValue "off" -Force
  $Sidecar | Add-Member -NotePropertyName webgpu_bundle_groups -NotePropertyValue 1 -Force
  Write-Json $OffModeBundleGroup $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @($OffModeBundleGroup)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "webgpu_bundle_groups must be zero") {
    throw "Expected trace sidecar with BundleGroup count while mode is off to fail. Output: $($Result.Output)"
  }

  $ValidBundleGroup = Join-Path $TmpDir "valid-bundlegroup.result.json"
  $Sidecar = New-Sidecar -Scene "texture-streaming" -Renderer "webgpu"
  $Sidecar | Add-Member -NotePropertyName webgpu_bundle_mode -NotePropertyValue "static" -Force
  $Sidecar | Add-Member -NotePropertyName webgpu_bundle_groups -NotePropertyValue 1 -Force
  $Sidecar.benchmark_result | Add-Member -NotePropertyName webgpu_bundle_mode -NotePropertyValue "static" -Force
  $Sidecar.benchmark_result | Add-Member -NotePropertyName webgpu_bundle_groups -NotePropertyValue 1 -Force
  Write-Json $ValidBundleGroup $Sidecar
  $Result = Invoke-Validator -ValidatorArgs @("--expectedFlagMetadata", "webgpu_bundle_mode=static", $ValidBundleGroup)
  if ($Result.ExitCode -ne 0) {
    throw "Expected valid static BundleGroup trace sidecar to pass. Output: $($Result.Output)"
  }
} finally {
  if (Test-Path -LiteralPath $TmpDir) {
    Remove-Item -LiteralPath $TmpDir -Recurse -Force
  }
}

Write-Host "Trace result sidecar validation accepts matching sidecars and static BundleGroup metadata, and rejects mismatched browser, scene, delay, flag, benchmark metadata, required launch flags, software-rendered GPU metadata, diagnostic software-rendering opt-in metadata, and invalid static BundleGroup evidence."

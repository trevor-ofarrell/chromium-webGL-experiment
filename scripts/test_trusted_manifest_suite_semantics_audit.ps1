[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\trusted-manifest-suite-semantics-audit"
$ManifestPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.json"
$PinRefreshPath = Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json"
$PinRefreshBackupPath = Join-Path $TempDir "chromium-pin-refresh.trusted-suite-semantics-audit.backup.json"
$TempOutput = Join-Path $TempDir "trusted-manifest-suite-semantics-audit.md"
$RequiredScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

function Get-GitRevision {
  param([string]$RepoPath)
  $Revision = (& git -C $RepoPath rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $Revision) {
    throw "Unable to read git revision from $RepoPath"
  }
  return $Revision
}

function Get-ShortSha256 {
  param([string]$PathValue)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.Substring(0, 12).ToLowerInvariant()
}

function Get-Sha256 {
  param([string]$PathValue)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
}

function Convert-BytesToHexString {
  param([byte[]]$Bytes)
  return (($Bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-StringSha256 {
  param([string]$Text)
  $Sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return Convert-BytesToHexString ($Sha256.ComputeHash($Bytes))
  } finally {
    $Sha256.Dispose()
  }
}

function ConvertTo-ReportInputPath {
  param([string]$PathValue)
  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  $Prefix = "$FullRoot$([System.IO.Path]::DirectorySeparatorChar)"
  if ($FullPath.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    $FullPath = $FullPath.Substring($Prefix.Length)
  }
  return (($FullPath -replace "\\", "/") -replace [regex]::Escape([System.IO.Path]::AltDirectorySeparatorChar), "/")
}

function Get-ReportInputDigest {
  param([string[]]$PathValues)
  $Entries = @($PathValues | ForEach-Object {
      $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
      $Size = (Get-Item -LiteralPath $_).Length
      "$(ConvertTo-ReportInputPath $_)`t$Hash`t$Size"
    } | Sort-Object)
  return Get-StringSha256 ($Entries -join "`n")
}

function Convert-MetadataValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) {
    return "null"
  }
  if ($Value -is [bool]) {
    return $Value.ToString().ToLowerInvariant()
  }
  return [string]$Value
}

function Get-ExperimentFlagValues {
  param([string[]]$Flags)

  $Values = [ordered]@{
    viewer_mode = $true
    viewer_block_external_navigation = $true
    viewer_trusted_content = $true
    viewer_aggressive_gpu = $false
    viewer_relaxed_webgl_validation = $false
    viewer_zero_copy = $false
    viewer_in_process_gpu = $false
    viewer_single_process = $false
    viewer_force_angle_backend = $null
    requested_angle_backend = $null
    viewer_disable_unneeded_blink_features = $false
    viewer_direct_gpu_presentation = $false
    viewer_defer_webgpu_pipeline_flush = $false
    viewer_defer_webgpu_queue_flush = $false
    viewer_defer_webgpu_submit_flush = $false
    viewer_skip_webgpu_canvas_texture_validation = $false
    viewer_skip_webgpu_canvas_memory_accounting = $false
    viewer_skip_webgpu_copy_external_image_color_conversion = $false
    viewer_skip_webgpu_copy_external_image_color_space_validation = $false
    viewer_skip_webgpu_copy_external_image_dest_validation = $false
    viewer_skip_webgpu_copy_external_image_source_validation = $false
    viewer_skip_webgpu_copy_external_image_copy_size_validation = $false
    viewer_skip_webgpu_write_texture_layout_validation = $false
    viewer_reject_webgpu_cpu_texture_fallback = $false
    viewer_skip_webgpu_use_counters = $false
    viewer_skip_webgpu_resource_labels = $false
    viewer_skip_webgpu_shader_source_null_check = $false
    viewer_skip_webgpu_shader_memory_accounting = $false
    viewer_skip_webgpu_redundant_pipeline_sets = $false
    viewer_skip_webgpu_redundant_bind_group_sets = $false
    viewer_skip_webgpu_redundant_buffer_sets = $false
    viewer_skip_webgpu_redundant_render_state_sets = $false
    viewer_trace_webgpu_queue = $false
    resource_warmup_enabled = $false
    resource_warmup_precompile = $false
    resource_warmup_prerender_frames = 0
  }

  for ($Index = 0; $Index -lt $Flags.Count; $Index += 1) {
    switch ($Flags[$Index]) {
      "--viewerAggressiveGpu" { $Values.viewer_aggressive_gpu = $true }
      "--viewerRelaxedWebglValidation" { $Values.viewer_relaxed_webgl_validation = $true }
      "--viewerZeroCopy" { $Values.viewer_zero_copy = $true }
      "--viewerInProcessGpu" { $Values.viewer_in_process_gpu = $true }
      "--viewerSingleProcess" { $Values.viewer_single_process = $true }
      "--viewerDisableUnneededBlinkFeatures" { $Values.viewer_disable_unneeded_blink_features = $true }
      "--viewerDirectGpuPresentation" { $Values.viewer_direct_gpu_presentation = $true }
      "--viewerDeferWebgpuPipelineFlush" { $Values.viewer_defer_webgpu_pipeline_flush = $true }
      "--viewerDeferWebgpuQueueFlush" { $Values.viewer_defer_webgpu_queue_flush = $true }
      "--viewerDeferWebgpuSubmitFlush" { $Values.viewer_defer_webgpu_submit_flush = $true }
      "--viewerSkipWebgpuCanvasTextureValidation" { $Values.viewer_skip_webgpu_canvas_texture_validation = $true }
      "--viewerSkipWebgpuCanvasMemoryAccounting" { $Values.viewer_skip_webgpu_canvas_memory_accounting = $true }
      "--viewerSkipWebgpuCopyExternalImageColorConversion" { $Values.viewer_skip_webgpu_copy_external_image_color_conversion = $true }
      "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation" { $Values.viewer_skip_webgpu_copy_external_image_color_space_validation = $true }
      "--viewerSkipWebgpuCopyExternalImageDestValidation" { $Values.viewer_skip_webgpu_copy_external_image_dest_validation = $true }
      "--viewerSkipWebgpuCopyExternalImageSourceValidation" { $Values.viewer_skip_webgpu_copy_external_image_source_validation = $true }
      "--viewerSkipWebgpuCopyExternalImageCopySizeValidation" { $Values.viewer_skip_webgpu_copy_external_image_copy_size_validation = $true }
      "--viewerSkipWebgpuWriteTextureLayoutValidation" { $Values.viewer_skip_webgpu_write_texture_layout_validation = $true }
      "--viewerRejectWebgpuCpuTextureFallback" { $Values.viewer_reject_webgpu_cpu_texture_fallback = $true }
      "--viewerSkipWebgpuUseCounters" { $Values.viewer_skip_webgpu_use_counters = $true }
      "--viewerSkipWebgpuResourceLabels" { $Values.viewer_skip_webgpu_resource_labels = $true }
      "--viewerSkipWebgpuShaderSourceNullCheck" { $Values.viewer_skip_webgpu_shader_source_null_check = $true }
      "--viewerSkipWebgpuShaderMemoryAccounting" { $Values.viewer_skip_webgpu_shader_memory_accounting = $true }
      "--viewerSkipWebgpuRedundantPipelineSets" { $Values.viewer_skip_webgpu_redundant_pipeline_sets = $true }
      "--viewerSkipWebgpuRedundantBindGroupSets" { $Values.viewer_skip_webgpu_redundant_bind_group_sets = $true }
      "--viewerSkipWebgpuRedundantBufferSets" { $Values.viewer_skip_webgpu_redundant_buffer_sets = $true }
      "--viewerSkipWebgpuRedundantRenderStateSets" { $Values.viewer_skip_webgpu_redundant_render_state_sets = $true }
      "--viewerTraceWebgpuQueue" { $Values.viewer_trace_webgpu_queue = $true }
      "--viewerForceAngleBackend" {
        $Index += 1
        if ($Index -ge $Flags.Count) {
          throw "Missing backend after --viewerForceAngleBackend"
        }
        $Values.viewer_force_angle_backend = $Flags[$Index]
        $Values.requested_angle_backend = $Flags[$Index]
      }
    }
  }

  return $Values
}

function Get-ExpectedFlagMetadata {
  param([string[]]$Flags)
  $Values = Get-ExperimentFlagValues -Flags $Flags
  return @($Values.GetEnumerator() | ForEach-Object {
    "$($_.Key)=$(Convert-MetadataValue $_.Value)"
  })
}

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Data
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  $Json = $Data | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($PathValue, $Json, [System.Text.UTF8Encoding]::new($false))
}

function Write-ArtifactFile {
  param(
    [string]$PathValue,
    [string]$Content
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  [System.IO.File]::WriteAllText($PathValue, $Content, [System.Text.UTF8Encoding]::new($false))
  return $PathValue
}

function Write-PackageDir {
  param([string]$PathValue)

  New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
  $null = Write-ArtifactFile (Join-Path $PathValue "content_shell.exe") "fork browser"
  return $PathValue
}

function New-FileMetadata {
  param([string]$PathValue)

  [pscustomobject]@{
    path = $PathValue
    exists = $true
    size_bytes = (Get-Item -LiteralPath $PathValue).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
  }
}

function New-DirectoryMetadata {
  param([string]$PathValue)

  $Files = @(Get-ChildItem -LiteralPath $PathValue -File -Recurse -ErrorAction SilentlyContinue)
  $Size = 0L
  foreach ($File in $Files) {
    $Size += $File.Length
  }

  [pscustomobject]@{
    path = $PathValue
    exists = $true
    file_count = $Files.Count
    size_bytes = $Size
  }
}

function New-MetadataList {
  param([string[]]$Paths)
  @($Paths | ForEach-Object { New-FileMetadata $_ })
}

function New-TrustedSummaryReportContent {
  param(
    [object[]]$Experiments,
    [string[]]$Scenes = $RequiredScenes,
    [string]$InputDigest = "synthetic-input-digest"
  )

  $Rows = [System.Collections.Generic.List[string]]::new()
  foreach ($Experiment in $Experiments) {
    foreach ($Scene in $Scenes) {
      $Rows.Add("| $Scene | webgl2 | $($Experiment.label) | 60 |") | Out-Null
    }
  }
  $Tick = [char]0x60
  $DigestLine = "Input file digest: $Tick$InputDigest$Tick"

  @"
# Benchmark Summary

Generated from synthetic trusted manifest test fixtures.
$DigestLine

Strict summary evidence validation was enabled: synthetic.

| Scene | Renderer | Variant | Avg FPS |
| --- | --- | --- | --- |
$($Rows -join "`n")
"@
}

function New-TrustedComparisonReportContent {
  param(
    [object[]]$Experiments,
    [string[]]$Scenes = $RequiredScenes,
    [string]$InputDigest = "synthetic-input-digest"
  )

  $Rows = [System.Collections.Generic.List[string]]::new()
  foreach ($Experiment in $Experiments) {
    foreach ($Scene in $Scenes) {
      $Rows.Add("| $Scene | webgl2 | $($Experiment.label) | 60 | 0 | 0 | 0 |") | Out-Null
    }
  }
  $Tick = [char]0x60
  $DigestLine = "Input file digest: $Tick$InputDigest$Tick"

  @"
# Benchmark Comparison

Generated from synthetic trusted manifest test fixtures.
$DigestLine

Strict comparison evidence validation was enabled: synthetic.

| Scene | Renderer | Variant | Avg FPS | Dropped Delta | JS heap Delta | GPU memory Delta |
| --- | --- | --- | ---: | ---: | ---: | ---: |
$($Rows -join "`n")
"@
}

function New-Result {
  param(
    [string]$Scene,
    [string]$Variant,
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$BrowserExecutable,
    [string]$BuildArgsHash,
    [string[]]$Flags
  )

  $FlagValues = Get-ExperimentFlagValues -Flags $Flags
  [ordered]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    build_args_hash = $BuildArgsHash
    platform = "test-platform"
    gpu_name = "NVIDIA GeForce RTX Test"
    driver_version = "test-driver"
    angle_backend = "ANGLE (NVIDIA, D3D11)"
    renderer_type = "webgl2"
    scene_name = $Scene
    complexity = 2
    warmup_seconds = 10
    measured_seconds = 60
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
    webgpu_device_lost = $false
    webgl_context_currently_lost = $false
    webgl_context_lost_count = 0
    render_error_count = 0
    js_heap_mb = 10
    gpu_memory_mb = 20
    process_rss_mb = 100
    startup_ms_to_first_frame = 500
    browser_binary_size_mb = 100
    viewer_bundle_size_mb = 1
    package_size_mb = 120
    browser_executable = $BrowserExecutable
    browser_is_from_checkout = $true
    benchmark_variant = $Variant
    viewer_mode = $FlagValues.viewer_mode
    viewer_block_external_navigation = $FlagValues.viewer_block_external_navigation
    viewer_trusted_content = $FlagValues.viewer_trusted_content
    viewer_aggressive_gpu = $FlagValues.viewer_aggressive_gpu
    viewer_relaxed_webgl_validation = $FlagValues.viewer_relaxed_webgl_validation
    viewer_zero_copy = $FlagValues.viewer_zero_copy
    viewer_in_process_gpu = $FlagValues.viewer_in_process_gpu
    viewer_single_process = $FlagValues.viewer_single_process
    viewer_force_angle_backend = $FlagValues.viewer_force_angle_backend
    requested_angle_backend = $FlagValues.requested_angle_backend
    viewer_disable_unneeded_blink_features = $FlagValues.viewer_disable_unneeded_blink_features
    viewer_direct_gpu_presentation = $FlagValues.viewer_direct_gpu_presentation
    viewer_defer_webgpu_pipeline_flush = $FlagValues.viewer_defer_webgpu_pipeline_flush
    viewer_defer_webgpu_queue_flush = $FlagValues.viewer_defer_webgpu_queue_flush
    viewer_defer_webgpu_submit_flush = $FlagValues.viewer_defer_webgpu_submit_flush
    viewer_skip_webgpu_canvas_texture_validation = $FlagValues.viewer_skip_webgpu_canvas_texture_validation
    viewer_skip_webgpu_canvas_memory_accounting = $FlagValues.viewer_skip_webgpu_canvas_memory_accounting
    viewer_skip_webgpu_copy_external_image_color_conversion = $FlagValues.viewer_skip_webgpu_copy_external_image_color_conversion
    viewer_skip_webgpu_copy_external_image_color_space_validation = $FlagValues.viewer_skip_webgpu_copy_external_image_color_space_validation
    viewer_skip_webgpu_copy_external_image_dest_validation = $FlagValues.viewer_skip_webgpu_copy_external_image_dest_validation
    viewer_skip_webgpu_copy_external_image_source_validation = $FlagValues.viewer_skip_webgpu_copy_external_image_source_validation
    viewer_skip_webgpu_copy_external_image_copy_size_validation = $FlagValues.viewer_skip_webgpu_copy_external_image_copy_size_validation
    viewer_skip_webgpu_write_texture_layout_validation = $FlagValues.viewer_skip_webgpu_write_texture_layout_validation
    viewer_reject_webgpu_cpu_texture_fallback = $FlagValues.viewer_reject_webgpu_cpu_texture_fallback
    viewer_skip_webgpu_use_counters = $FlagValues.viewer_skip_webgpu_use_counters
    viewer_skip_webgpu_resource_labels = $FlagValues.viewer_skip_webgpu_resource_labels
    viewer_skip_webgpu_shader_source_null_check = $FlagValues.viewer_skip_webgpu_shader_source_null_check
    viewer_skip_webgpu_shader_memory_accounting = $FlagValues.viewer_skip_webgpu_shader_memory_accounting
    viewer_skip_webgpu_redundant_pipeline_sets = $FlagValues.viewer_skip_webgpu_redundant_pipeline_sets
    viewer_skip_webgpu_redundant_bind_group_sets = $FlagValues.viewer_skip_webgpu_redundant_bind_group_sets
    viewer_skip_webgpu_redundant_buffer_sets = $FlagValues.viewer_skip_webgpu_redundant_buffer_sets
    viewer_skip_webgpu_redundant_render_state_sets = $FlagValues.viewer_skip_webgpu_redundant_render_state_sets
    viewer_trace_webgpu_queue = $FlagValues.viewer_trace_webgpu_queue
    resource_warmup_enabled = $FlagValues.resource_warmup_enabled
    resource_warmup_precompile = $FlagValues.resource_warmup_precompile
    resource_warmup_prerender_frames = $FlagValues.resource_warmup_prerender_frames
    browser_flags = @("--disable-software-rasterizer")
  }
}

function New-Experiment {
  param(
    [string]$Label,
    [string[]]$Flags,
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$Browser,
    [string]$BuildArgsHash
  )

  $ResultFiles = @($RequiredScenes | ForEach-Object {
    Join-Path $TempDir "results\$Label-$_-webgl2.json"
  })
  for ($Index = 0; $Index -lt $RequiredScenes.Count; $Index += 1) {
    Write-Json $ResultFiles[$Index] (New-Result `
        -Scene $RequiredScenes[$Index] `
        -Variant $Label `
        -ChromiumRevision $ChromiumRevision `
        -ForkRevision $ForkRevision `
        -BrowserExecutable $Browser `
        -BuildArgsHash $BuildArgsHash `
        -Flags $Flags)
  }

  [pscustomobject]@{
    label = $Label
    description = "synthetic trusted exact-suite audit experiment"
    flags = $Flags
    expected_flag_metadata = @(Get-ExpectedFlagMetadata -Flags $Flags)
    result_files = $ResultFiles
  }
}

function New-ValidTrustedManifest {
  param(
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$Browser,
    [string]$BuildArgs,
    [string]$PackageDir,
    [string]$Summary,
    [string]$Comparison
  )

  $BuildArgsHash = Get-Sha256 $BuildArgs
  $Experiments = @(
    (New-Experiment "fork-viewer-exp-default" @() $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-aggressive-gpu" @("--viewerAggressiveGpu") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-zero-copy" @("--viewerZeroCopy") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-in-process-gpu" @("--viewerInProcessGpu") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-single-process" @("--viewerSingleProcess") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-angle-d3d11" @("--viewerForceAngleBackend", "d3d11") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" @("--viewerRelaxedWebglValidation") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" @("--viewerDisableUnneededBlinkFeatures") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" @("--viewerDirectGpuPresentation") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
  )
  $AllResultFiles = @($Experiments | ForEach-Object { $_.result_files })
  $InputDigest = Get-ReportInputDigest $AllResultFiles
  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Experiments -InputDigest $InputDigest)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Experiments -InputDigest $InputDigest)

  [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browser = $Browser
    build_args = $BuildArgs
    package_dir = $PackageDir
    renderer = "webgl2"
    scenes = $RequiredScenes
    suite_validation = [pscustomobject]@{
      expected_scenes = $RequiredScenes
      require_checkout = $true
      require_build_args = $true
      require_fork_revision = $true
      expected_fork_revision = $ForkRevision
      forbid_smoke = $true
      reject_software_rendering = $true
      reject_gpu_instability = $true
      require_gpu_metadata = $true
      require_frame_times = $true
      expected_chromium_revision = $ChromiumRevision
      expected_browser = $Browser
      expected_build_args_hash = $BuildArgsHash
      expected_measured_seconds = 60
      expected_warmup_seconds = 10
      expected_complexity = 2
      exact_scene_output_files = $true
      expected_flag_metadata = $true
    }
    options = [pscustomobject]@{
      duration = 60
      warmup = 10
      complexity = 2
      precompile = $false
      prerender_frames = 0
    }
    experiments = $Experiments
    result_files = [pscustomobject]@{
      all = $AllResultFiles
    }
    report_files = [pscustomobject]@{
      summary = $Summary
      comparison = $Comparison
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        browser = New-FileMetadata $Browser
        build_args = New-FileMetadata $BuildArgs
        viewer_patch = New-FileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
        package = New-DirectoryMetadata $PackageDir
      }
      results = [pscustomobject]@{
        all = New-MetadataList $AllResultFiles
      }
      reports = [pscustomobject]@{
        summary = New-FileMetadata $Summary
        comparison = New-FileMetadata $Comparison
      }
    }
  }
}

function Invoke-AuditAndReadChecklist {
  $OldAllowManifestOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
  $OldTrustedManifestPath = $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST
  $OldOfficialManifestPath = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $ManifestPath
  Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $TempOutput -ManifestAuditOnly *>&1
  } finally {
    if ($null -eq $OldAllowManifestOverrides) {
      Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowManifestOverrides
    }
    if ($null -eq $OldTrustedManifestPath) {
      Remove-Item Env:\THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $OldTrustedManifestPath
    }
    if ($null -eq $OldOfficialManifestPath) {
      Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OldOfficialManifestPath
    }
  }

  Get-Content -LiteralPath $TempOutput -Raw
}

function Assert-UnderDirectory {
  param(
    [string]$PathValue,
    [string]$Parent
  )

  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if (-not $FullPath.StartsWith($FullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside expected directory. path=$FullPath parent=$FullParent"
  }
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$HadPinRefresh = Test-Path -LiteralPath $PinRefreshPath
if ($HadPinRefresh) {
  Copy-Item -LiteralPath $PinRefreshPath -Destination $PinRefreshBackupPath -Force
}

try {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PinSelectedAt = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString("o")
  $SyntheticPinRefresh = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    target_revision = $ChromiumRevision
    previous_revision = $ChromiumRevision
    selected_from_upstream_head = $true
    selected_at = $PinSelectedAt
    source = "synthetic trusted suite semantics audit test"
    skip_sync = $true
    skip_hooks = $true
    skip_gn_gen = $true
  }
  New-Item -ItemType Directory -Path (Split-Path $PinRefreshPath -Parent) -Force | Out-Null
  Write-Json $PinRefreshPath $SyntheticPinRefresh

  $ForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ChromiumRevision -Root $Root
  $Browser = Write-ArtifactFile (Join-Path $TempDir "fork.exe") "fork browser"
  $BuildArgs = Write-ArtifactFile (Join-Path $TempDir "args.gn") "is_debug=false"
  $PackageDir = Write-PackageDir (Join-Path $TempDir "package")
  $Summary = Write-ArtifactFile (Join-Path $TempDir "trusted-summary.md") ""
  $Comparison = Write-ArtifactFile (Join-Path $TempDir "trusted-comparison.md") ""

  $Manifest = New-ValidTrustedManifest `
    -ChromiumRevision $ChromiumRevision `
    -ForkRevision $ForkRevision `
    -Browser $Browser `
    -BuildArgs $BuildArgs `
    -PackageDir $PackageDir `
    -Summary $Summary `
    -Comparison $Comparison
  Write-Json $ManifestPath $Manifest
  $DoneChecklist = Invoke-AuditAndReadChecklist
  if ($DoneChecklist -notmatch "Trusted experiment matrix manifest.*done.*benchmark suites semantically validated") {
    throw "Artifact audit did not accept a completed trusted manifest whose exact experiment suites pass validation. Checklist: $DoneChecklist"
  }
  $InputDigest = Get-ReportInputDigest @($Manifest.result_files.all)

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest "wrong-input-digest")
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  Write-Json $ManifestPath $Manifest
  $WrongDigestChecklist = Invoke-AuditAndReadChecklist
  if ($WrongDigestChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $WrongDigestChecklist -notmatch "trusted summary input digest does not match manifest result files") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose summary report input digest does not match the exact raw result files. Checklist: $WrongDigestChecklist"
  }

  $null = Write-ArtifactFile $Summary ((New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest) -replace "Strict summary evidence validation was enabled: synthetic.\r?\n\r?\n", "")
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  Write-Json $ManifestPath $Manifest
  $MissingStrictSummaryChecklist = Invoke-AuditAndReadChecklist
  if ($MissingStrictSummaryChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $MissingStrictSummaryChecklist -notmatch "trusted summary missing strict summary evidence validation note") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose summary report lacks strict-evidence validation text. Checklist: $MissingStrictSummaryChecklist"
  }

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -Scenes @($RequiredScenes | Select-Object -Skip 1) -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  Write-Json $ManifestPath $Manifest
  $SceneIncompleteReportChecklist = Invoke-AuditAndReadChecklist
  if ($SceneIncompleteReportChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $SceneIncompleteReportChecklist -notmatch "trusted summary missing scene many-draw-calls") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose summary report omits a required scene. Checklist: $SceneIncompleteReportChecklist"
  }

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments @($Manifest.experiments | Select-Object -Skip 1) -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  Write-Json $ManifestPath $Manifest
  $LabelIncompleteReportChecklist = Invoke-AuditAndReadChecklist
  if ($LabelIncompleteReportChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $LabelIncompleteReportChecklist -notmatch "trusted summary missing variant label fork-viewer-exp-default") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose summary report omits an experiment label. Checklist: $LabelIncompleteReportChecklist"
  }

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary

  $null = Write-ArtifactFile $Comparison ((New-TrustedComparisonReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest) -replace "Strict comparison evidence validation was enabled: synthetic.\r?\n\r?\n", "")
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison
  Write-Json $ManifestPath $Manifest
  $MissingStrictComparisonChecklist = Invoke-AuditAndReadChecklist
  if ($MissingStrictComparisonChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $MissingStrictComparisonChecklist -notmatch "trusted comparison missing strict comparison evidence validation note") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose comparison report lacks strict-evidence validation text. Checklist: $MissingStrictComparisonChecklist"
  }
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison

  $null = Write-ArtifactFile $Summary "not a benchmark summary"
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  Write-Json $ManifestPath $Manifest
  $BadReportChecklist = Invoke-AuditAndReadChecklist
  if ($BadReportChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $BadReportChecklist -notmatch "trusted summary missing summary heading") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose hashed report content is not a benchmark summary. Checklist: $BadReportChecklist"
  }

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison

  $FirstResult = [string]$Manifest.experiments[0].result_files[0]
  $OriginalFirstResult = Get-Content -LiteralPath $FirstResult -Raw | ConvertFrom-Json
  $WrongBrowserResult = Get-Content -LiteralPath $FirstResult -Raw | ConvertFrom-Json
  $WrongBrowserResult.browser_executable = Join-Path $TempDir "wrong-fork-browser.exe"
  Write-Json $FirstResult $WrongBrowserResult
  $Manifest.artifact_metadata.results.all = New-MetadataList @($Manifest.result_files.all)
  $InputDigest = Get-ReportInputDigest @($Manifest.result_files.all)
  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison
  Write-Json $ManifestPath $Manifest
  $WrongBrowserChecklist = Invoke-AuditAndReadChecklist
  if ($WrongBrowserChecklist -notmatch "Trusted experiment matrix manifest.*pending.*suite validation failed" -or
      $WrongBrowserChecklist -notmatch "browser_executable") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose exact result file records the wrong browser executable. Checklist: $WrongBrowserChecklist"
  }
  Write-Json $FirstResult $OriginalFirstResult
  $Manifest.artifact_metadata.results.all = New-MetadataList @($Manifest.result_files.all)
  $InputDigest = Get-ReportInputDigest @($Manifest.result_files.all)
  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison
  Write-Json $ManifestPath $Manifest

  $BadResult = Get-Content -LiteralPath $FirstResult -Raw | ConvertFrom-Json
  $BadResult.measured_seconds = 59
  Write-Json $FirstResult $BadResult
  $Manifest.artifact_metadata.results.all = New-MetadataList @($Manifest.result_files.all)
  $InputDigest = Get-ReportInputDigest @($Manifest.result_files.all)
  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison
  Write-Json $ManifestPath $Manifest
  $BadChecklist = Invoke-AuditAndReadChecklist
  if ($BadChecklist -notmatch "Trusted experiment matrix manifest.*pending.*suite validation failed" -or
      $BadChecklist -notmatch "measured_seconds") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose exact result file fails benchmark suite validation. Checklist: $BadChecklist"
  }

  Write-Json $FirstResult $OriginalFirstResult
  $ExperimentBrowserFlag = "--enable-dawn-features=skip_validation"
  $Manifest.experiments[0] | Add-Member -NotePropertyName browser_flags -NotePropertyValue @($ExperimentBrowserFlag) -Force
  $Manifest.experiments[0] | Add-Member -NotePropertyName required_browser_flags -NotePropertyValue @("--disable-software-rasterizer", $ExperimentBrowserFlag) -Force
  foreach ($ResultPath in @($Manifest.experiments[0].result_files)) {
    $FlaggedResult = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
    $FlaggedResult.browser_flags = @("--disable-software-rasterizer", $ExperimentBrowserFlag)
    Write-Json $ResultPath $FlaggedResult
  }
  $Manifest.artifact_metadata.results.all = New-MetadataList @($Manifest.result_files.all)
  $InputDigest = Get-ReportInputDigest @($Manifest.result_files.all)
  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison
  Write-Json $ManifestPath $Manifest
  $PerExperimentFlagChecklist = Invoke-AuditAndReadChecklist
  if ($PerExperimentFlagChecklist -notmatch "Trusted experiment matrix manifest.*done.*benchmark suites semantically validated") {
    throw "Artifact audit rejected a completed trusted manifest whose per-experiment required browser flags are present in raw results. Checklist: $PerExperimentFlagChecklist"
  }

  $MissingBrowserFlagResult = Get-Content -LiteralPath $FirstResult -Raw | ConvertFrom-Json
  $MissingBrowserFlagResult.browser_flags = @("--disable-software-rasterizer")
  Write-Json $FirstResult $MissingBrowserFlagResult
  $Manifest.artifact_metadata.results.all = New-MetadataList @($Manifest.result_files.all)
  $InputDigest = Get-ReportInputDigest @($Manifest.result_files.all)
  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Manifest.experiments -InputDigest $InputDigest)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison
  Write-Json $ManifestPath $Manifest
  $MissingBrowserFlagChecklist = Invoke-AuditAndReadChecklist
  if ($MissingBrowserFlagChecklist -notmatch "Trusted experiment matrix manifest.*pending.*suite validation failed" -or
      $MissingBrowserFlagChecklist -notmatch "browser_flags must include --enable-dawn-features=skip_validation") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose result omits an experiment-specific browser flag. Checklist: $MissingBrowserFlagChecklist"
  }
} finally {
  if ($HadPinRefresh) {
    Copy-Item -LiteralPath $PinRefreshBackupPath -Destination $PinRefreshPath -Force
  } elseif (Test-Path -LiteralPath $PinRefreshPath) {
    Remove-Item -LiteralPath $PinRefreshPath -Force
  }
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Trusted manifest audit semantically validates exact experiment suite files, raw-input report digests, strict summary reports, and strict comparison report content before marking matrix evidence complete."

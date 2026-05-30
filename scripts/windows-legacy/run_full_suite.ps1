[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Browser,
  [string]$Renderer = "webgl2",
  [int]$Duration = 120,
  [int]$Warmup = 20,
  [string]$Label = "baseline",
  [string]$BuildArgs = "",
  [string]$PackageDir = "",
  [string]$ForkRevision = "",
  [switch]$ViewerMode,
  [switch]$ViewerTrustedContent,
  [switch]$ViewerAggressiveGpu,
  [switch]$ViewerRelaxedWebglValidation,
  [switch]$ViewerZeroCopy,
  [switch]$ViewerInProcessGpu,
  [switch]$ViewerSingleProcess,
  [string]$ViewerForceAngleBackend = "",
  [switch]$ViewerDisableUnneededBlinkFeatures,
  [switch]$ViewerDirectGpuPresentation,
  [switch]$ViewerDeferWebgpuPipelineFlush,
  [switch]$ViewerDeferWebgpuQueueFlush,
  [switch]$ViewerDeferWebgpuSubmitFlush,
  [switch]$ViewerSkipWebgpuCanvasTextureValidation,
  [switch]$ViewerSkipWebgpuCanvasMemoryAccounting,
  [switch]$ViewerSkipWebgpuCopyExternalImageColorConversion,
  [switch]$ViewerSkipWebgpuCopyExternalImageColorSpaceValidation,
  [switch]$ViewerSkipWebgpuCopyExternalImageDestValidation,
  [switch]$ViewerSkipWebgpuCopyExternalImageSourceValidation,
  [switch]$ViewerSkipWebgpuCopyExternalImageCopySizeValidation,
  [switch]$ViewerSkipWebgpuWriteTextureLayoutValidation,
  [switch]$ViewerRejectWebgpuCpuTextureFallback,
  [switch]$ViewerSkipWebgpuUseCounters,
  [switch]$ViewerCacheWebgpuBindGroupLayouts,
  [switch]$ViewerSkipWebgpuCommandLabels,
  [switch]$ViewerSkipWebgpuResourceLabels,
  [switch]$ViewerSkipWebgpuShaderSourceNullCheck,
  [switch]$ViewerSkipWebgpuShaderMemoryAccounting,
  [switch]$ViewerSkipWebgpuRedundantPipelineSets,
  [switch]$ViewerSkipWebgpuRedundantBindGroupSets,
  [switch]$ViewerSkipWebgpuRedundantBufferSets,
  [switch]$ViewerSkipWebgpuRedundantRenderStateSets,
  [switch]$ViewerTraceWebgpuQueue,
  [string[]]$BrowserFlag = @(),
  [switch]$Precompile,
  [switch]$SettleGpuAfterWarmup,
  [int]$WebGpuPipelineQuietFrames = 0,
  [int]$WebGpuPipelineQuietMaxFrames = 30,
  [switch]$DisableGpuTiming,
  [switch]$ReuseValidResults,
  [switch]$RequireGpuMetadata,
  [int]$PrerenderFrames = 0,
  [double]$Complexity = 1.0,
  [ValidateSet("off", "static")]
  [string]$WebGpuBundleMode = "off",
  [string]$ProfileCacheKey = "",
  [string]$UserDataDirRoot = ""
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BenchmarkTmpRoot = Join-Path $Root "benchmarks\tmp"
$Scenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

function Resolve-RepoPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $Root $PathValue))
}

function Test-PathUnderDirectory {
  param(
    [string]$PathValue,
    [string]$Parent
  )

  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  return $FullPath.StartsWith($FullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-SafePathSegment {
  param([string]$Value)
  return ([string]$Value) -replace '[^A-Za-z0-9._-]', '_'
}

if ($ProfileCacheKey -and -not $UserDataDirRoot) {
  $UserDataDirRoot = Join-Path $BenchmarkTmpRoot "profile-cache"
}
if ($Complexity -le 0) {
  throw "-Complexity must be greater than zero."
}
if ($WebGpuPipelineQuietFrames -lt 0 -or $WebGpuPipelineQuietMaxFrames -lt 0) {
  throw "-WebGpuPipelineQuietFrames and -WebGpuPipelineQuietMaxFrames must be non-negative."
}
if ($WebGpuPipelineQuietFrames -gt 0 -and $Renderer -ne "webgpu") {
  throw "-WebGpuPipelineQuietFrames is only supported with -Renderer webgpu."
}
if ($WebGpuBundleMode -ne "off" -and $Renderer -ne "webgpu") {
  throw "-WebGpuBundleMode is only supported with -Renderer webgpu."
}
$ViewerWebGpuExperimentSwitches = @(
  $ViewerDeferWebgpuPipelineFlush,
  $ViewerDeferWebgpuQueueFlush,
  $ViewerDeferWebgpuSubmitFlush,
  $ViewerSkipWebgpuCanvasTextureValidation,
  $ViewerSkipWebgpuCanvasMemoryAccounting,
  $ViewerSkipWebgpuCopyExternalImageColorConversion,
  $ViewerSkipWebgpuCopyExternalImageColorSpaceValidation,
  $ViewerSkipWebgpuCopyExternalImageDestValidation,
  $ViewerSkipWebgpuCopyExternalImageSourceValidation,
  $ViewerSkipWebgpuCopyExternalImageCopySizeValidation,
  $ViewerSkipWebgpuWriteTextureLayoutValidation,
  $ViewerRejectWebgpuCpuTextureFallback,
  $ViewerSkipWebgpuUseCounters,
  $ViewerCacheWebgpuBindGroupLayouts,
  $ViewerSkipWebgpuCommandLabels,
  $ViewerSkipWebgpuResourceLabels,
  $ViewerSkipWebgpuShaderSourceNullCheck,
  $ViewerSkipWebgpuShaderMemoryAccounting,
  $ViewerSkipWebgpuRedundantPipelineSets,
  $ViewerSkipWebgpuRedundantBindGroupSets,
  $ViewerSkipWebgpuRedundantBufferSets,
  $ViewerSkipWebgpuRedundantRenderStateSets,
  $ViewerTraceWebgpuQueue
)
if (($ViewerWebGpuExperimentSwitches | Where-Object { [bool]$_ }).Count -gt 0 -and $Renderer -ne "webgpu") {
  throw "Viewer WebGPU experiment flags are only supported with -Renderer webgpu."
}
if ($UserDataDirRoot -and -not $ProfileCacheKey) {
  throw "-UserDataDirRoot requires -ProfileCacheKey so reused-profile artifacts are labeled for compatibility checks."
}
$ResolvedUserDataDirRoot = ""
if ($ProfileCacheKey) {
  $ResolvedUserDataDirRoot = Resolve-RepoPath $UserDataDirRoot
  if (-not (Test-PathUnderDirectory $ResolvedUserDataDirRoot $BenchmarkTmpRoot)) {
    throw "-UserDataDirRoot must resolve under $BenchmarkTmpRoot."
  }
}

function Get-SceneUserDataDir {
  param([string]$Scene)
  if (-not $ProfileCacheKey) {
    return ""
  }
  return Join-Path $ResolvedUserDataDirRoot (Join-Path (ConvertTo-SafePathSegment $Label) (Join-Path (ConvertTo-SafePathSegment $Renderer) (ConvertTo-SafePathSegment $Scene)))
}

function Test-ResultGpuMetadata {
  param([string]$PathValue)
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }

  foreach ($Key in @("gpu_name", "driver_version", "angle_backend")) {
    $Value = $Result.$Key
    if ($Value -is [string] -and $Value.Trim().Length -gt 0) {
      return $true
    }
  }

  return $false
}

function Test-ResultGpuTimingMode {
  param(
    [string]$PathValue,
    [bool]$ExpectedEnabled
  )
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }
  return [bool]$Result.gpu_timing_enabled -eq $ExpectedEnabled
}

function Test-ResultResourceWarmupMode {
  param(
    [string]$PathValue,
    [bool]$ExpectedPrecompile,
    [int]$ExpectedPrerenderFrames,
    [bool]$ExpectedSettleGpuAfterWarmup,
    [int]$ExpectedPipelineQuietFrames,
    [int]$ExpectedPipelineQuietMaxFrames
  )
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }

  $ExpectedEnabled = $ExpectedPrecompile -or $ExpectedPrerenderFrames -gt 0 -or $ExpectedPipelineQuietFrames -gt 0
  if ($ExpectedSettleGpuAfterWarmup) {
    $ExpectedEnabled = $true
  }
  $ActualSettleGpuAfterWarmup = if ($null -ne $Result.resource_warmup_settle_gpu) {
    [bool]$Result.resource_warmup_settle_gpu
  } else {
    $false
  }
  $ActualPipelineQuietFrames = if ($null -ne $Result.resource_warmup_pipeline_quiet_frames) {
    [int]$Result.resource_warmup_pipeline_quiet_frames
  } else {
    0
  }
  $ActualPipelineQuietMaxFrames = if ($null -ne $Result.resource_warmup_pipeline_quiet_max_frames) {
    [int]$Result.resource_warmup_pipeline_quiet_max_frames
  } else {
    0
  }
  $ExpectedPipelineQuietMaxFrames = if ($ExpectedPipelineQuietFrames -gt 0) {
    [Math]::Max($ExpectedPipelineQuietFrames, $ExpectedPipelineQuietMaxFrames)
  } else {
    0
  }
  return [bool]$Result.resource_warmup_enabled -eq $ExpectedEnabled -and `
    [bool]$Result.resource_warmup_precompile -eq $ExpectedPrecompile -and `
    [int]$Result.resource_warmup_prerender_frames -eq $ExpectedPrerenderFrames -and `
    $ActualSettleGpuAfterWarmup -eq $ExpectedSettleGpuAfterWarmup -and `
    $ActualPipelineQuietFrames -eq $ExpectedPipelineQuietFrames -and `
    $ActualPipelineQuietMaxFrames -eq $ExpectedPipelineQuietMaxFrames
}

function Test-ResultProfileCacheMode {
  param(
    [string]$PathValue,
    [string]$ExpectedProfileCacheKey
  )
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }

  if ($null -eq $Result.profile_cache_mode -or -not [string]$Result.profile_cache_mode) {
    return $false
  }
  $ActualMode = [string]$Result.profile_cache_mode
  if ($ExpectedProfileCacheKey) {
    return $ActualMode -eq "explicit-reuse" -and `
      [string]$Result.profile_cache_key -eq $ExpectedProfileCacheKey -and `
      [bool]$Result.profile_reuse_enabled -eq $true
  }
  return $ActualMode -eq "fresh-temp" -and [bool]$Result.profile_reuse_enabled -eq $false
}

function Test-ResultComplexityMode {
  param(
    [string]$PathValue,
    [double]$ExpectedComplexity
  )
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }

  if ($null -eq $Result.complexity) {
    return $false
  }

  try {
    return [Math]::Abs(([double]$Result.complexity) - $ExpectedComplexity) -lt 0.001
  } catch {
    return $false
  }
}

function Test-ResultWebGpuBundleMode {
  param(
    [string]$PathValue,
    [string]$ExpectedWebGpuBundleMode
  )
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }

  $Actual = if ($null -ne $Result.webgpu_bundle_mode -and [string]$Result.webgpu_bundle_mode) {
    [string]$Result.webgpu_bundle_mode
  } else {
    "off"
  }
  return $Actual -eq $ExpectedWebGpuBundleMode
}

$ExpectedViewerFlagMetadata = [ordered]@{
  viewer_mode = [bool]$ViewerMode
  viewer_block_external_navigation = [bool]$ViewerMode
  viewer_trusted_content = [bool]$ViewerTrustedContent
  viewer_aggressive_gpu = [bool]$ViewerAggressiveGpu
  viewer_relaxed_webgl_validation = [bool]$ViewerRelaxedWebglValidation
  viewer_zero_copy = [bool]$ViewerZeroCopy
  viewer_in_process_gpu = [bool]$ViewerInProcessGpu
  viewer_single_process = [bool]$ViewerSingleProcess
  viewer_force_angle_backend = if ($ViewerForceAngleBackend) { $ViewerForceAngleBackend } else { $null }
  requested_angle_backend = if ($ViewerForceAngleBackend) { $ViewerForceAngleBackend } else { $null }
  viewer_disable_unneeded_blink_features = [bool]$ViewerDisableUnneededBlinkFeatures
  viewer_direct_gpu_presentation = [bool]$ViewerDirectGpuPresentation
  viewer_defer_webgpu_pipeline_flush = [bool]$ViewerDeferWebgpuPipelineFlush
  viewer_defer_webgpu_queue_flush = [bool]$ViewerDeferWebgpuQueueFlush
  viewer_defer_webgpu_submit_flush = [bool]$ViewerDeferWebgpuSubmitFlush
  viewer_skip_webgpu_canvas_texture_validation = [bool]$ViewerSkipWebgpuCanvasTextureValidation
  viewer_skip_webgpu_canvas_memory_accounting = [bool]$ViewerSkipWebgpuCanvasMemoryAccounting
  viewer_skip_webgpu_copy_external_image_color_conversion = [bool]$ViewerSkipWebgpuCopyExternalImageColorConversion
  viewer_skip_webgpu_copy_external_image_color_space_validation = [bool]$ViewerSkipWebgpuCopyExternalImageColorSpaceValidation
  viewer_skip_webgpu_copy_external_image_dest_validation = [bool]$ViewerSkipWebgpuCopyExternalImageDestValidation
  viewer_skip_webgpu_copy_external_image_source_validation = [bool]$ViewerSkipWebgpuCopyExternalImageSourceValidation
  viewer_skip_webgpu_copy_external_image_copy_size_validation = [bool]$ViewerSkipWebgpuCopyExternalImageCopySizeValidation
  viewer_skip_webgpu_write_texture_layout_validation = [bool]$ViewerSkipWebgpuWriteTextureLayoutValidation
  viewer_reject_webgpu_cpu_texture_fallback = [bool]$ViewerRejectWebgpuCpuTextureFallback
  viewer_skip_webgpu_use_counters = [bool]$ViewerSkipWebgpuUseCounters
  viewer_cache_webgpu_bind_group_layouts = [bool]$ViewerCacheWebgpuBindGroupLayouts
  viewer_skip_webgpu_command_labels = [bool]$ViewerSkipWebgpuCommandLabels
  viewer_skip_webgpu_resource_labels = [bool]$ViewerSkipWebgpuResourceLabels
  viewer_skip_webgpu_shader_source_null_check = [bool]$ViewerSkipWebgpuShaderSourceNullCheck
  viewer_skip_webgpu_shader_memory_accounting = [bool]$ViewerSkipWebgpuShaderMemoryAccounting
  viewer_skip_webgpu_redundant_pipeline_sets = [bool]$ViewerSkipWebgpuRedundantPipelineSets
  viewer_skip_webgpu_redundant_bind_group_sets = [bool]$ViewerSkipWebgpuRedundantBindGroupSets
  viewer_skip_webgpu_redundant_buffer_sets = [bool]$ViewerSkipWebgpuRedundantBufferSets
  viewer_skip_webgpu_redundant_render_state_sets = [bool]$ViewerSkipWebgpuRedundantRenderStateSets
  viewer_trace_webgpu_queue = [bool]$ViewerTraceWebgpuQueue
}

function Test-ResultViewerFlagMetadata {
  param([string]$PathValue)
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }

  foreach ($Key in $ExpectedViewerFlagMetadata.Keys) {
    $Property = $Result.PSObject.Properties[$Key]
    if ($null -eq $Property) {
      return $false
    }
    $Expected = $ExpectedViewerFlagMetadata[$Key]
    if ($null -eq $Expected) {
      if ($null -ne $Property.Value) {
        return $false
      }
    } elseif ($Expected -is [bool]) {
      if ([bool]$Property.Value -ne $Expected) {
        return $false
      }
    } elseif ([string]$Property.Value -ne [string]$Expected) {
      return $false
    }
  }

  return $true
}

function Test-ResultBrowserExtraFlags {
  param([string]$PathValue)
  if (-not $BrowserFlag -or $BrowserFlag.Count -eq 0) {
    return $true
  }
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }
  if ($null -eq $Result.browser_flags) {
    return $false
  }
  $ActualFlags = @($Result.browser_flags | ForEach-Object { [string]$_ })
  foreach ($Flag in $BrowserFlag) {
    if ($ActualFlags -notcontains [string]$Flag) {
      return $false
    }
  }
  return $true
}

foreach ($Scene in $Scenes) {
  $Out = Join-Path $Root "benchmarks\raw\$Label-$Scene-$Renderer.json"
  $ExpectedGpuTimingEnabled = -not $DisableGpuTiming
  $ExpectedResourceWarmupPrecompile = [bool]$Precompile
  $ExpectedResourceWarmupPrerenderFrames = $PrerenderFrames
  $ExpectedResourceWarmupSettleGpuAfterWarmup = [bool]$SettleGpuAfterWarmup
  $ExpectedResourceWarmupPipelineQuietFrames = if ($Renderer -eq "webgpu") { $WebGpuPipelineQuietFrames } else { 0 }
  $ExpectedResourceWarmupPipelineQuietMaxFrames = if ($ExpectedResourceWarmupPipelineQuietFrames -gt 0) {
    [Math]::Max($ExpectedResourceWarmupPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames)
  } else {
    0
  }
  if ($ReuseValidResults -and (Test-Path -LiteralPath $Out)) {
    node (Join-Path $Root "scripts\validate_metrics.mjs") $Out
    if ($LASTEXITCODE -eq 0) {
      if ($RequireGpuMetadata -and -not (Test-ResultGpuMetadata $Out)) {
        Write-Host "Existing benchmark result is missing GPU metadata and will be regenerated: $Out"
      } elseif (-not (Test-ResultGpuTimingMode $Out $ExpectedGpuTimingEnabled)) {
        Write-Host "Existing benchmark result has the wrong GPU timing mode and will be regenerated: $Out"
      } elseif (-not (Test-ResultResourceWarmupMode $Out $ExpectedResourceWarmupPrecompile $ExpectedResourceWarmupPrerenderFrames $ExpectedResourceWarmupSettleGpuAfterWarmup $ExpectedResourceWarmupPipelineQuietFrames $ExpectedResourceWarmupPipelineQuietMaxFrames)) {
        Write-Host "Existing benchmark result has the wrong resource warmup mode and will be regenerated: $Out"
      } elseif (-not (Test-ResultProfileCacheMode $Out $ProfileCacheKey)) {
        Write-Host "Existing benchmark result has the wrong profile-cache mode/key and will be regenerated: $Out"
      } elseif (-not (Test-ResultComplexityMode $Out $Complexity)) {
        Write-Host "Existing benchmark result has the wrong complexity and will be regenerated: $Out"
      } elseif (-not (Test-ResultWebGpuBundleMode $Out $WebGpuBundleMode)) {
        Write-Host "Existing benchmark result has the wrong WebGPU BundleGroup mode and will be regenerated: $Out"
      } elseif (-not (Test-ResultViewerFlagMetadata $Out)) {
        Write-Host "Existing benchmark result has the wrong viewer flag metadata and will be regenerated: $Out"
      } elseif (-not (Test-ResultBrowserExtraFlags $Out)) {
        Write-Host "Existing benchmark result is missing expected extra browser flags and will be regenerated: $Out"
      } else {
        Write-Host "Reusing valid benchmark result: $Out"
        continue
      }
    }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Existing benchmark result failed validation and will be regenerated: $Out"
    }
  }

  $Command = @(
    (Join-Path $Root "scripts\run_benchmark.mjs"),
    "--browser", $Browser,
    "--variant", $Label,
    "--scene", $Scene,
    "--renderer", $Renderer,
    "--complexity", [string]$Complexity,
    "--duration", [string]$Duration,
    "--warmup", [string]$Warmup,
    "--output", $Out
  )

  if ($BuildArgs) {
    $Command += @("--buildArgs", $BuildArgs)
  }
  if ($PackageDir) {
    $Command += @("--packageDir", $PackageDir)
  }
  if ($ForkRevision) {
    $Command += @("--forkRevision", $ForkRevision)
  }
  if ($ViewerMode) {
    $Command += "--viewerMode"
  }
  if ($ViewerTrustedContent) {
    $Command += "--viewerTrustedContent"
  }
  if ($ViewerAggressiveGpu) {
    $Command += "--viewerAggressiveGpu"
  }
  if ($ViewerRelaxedWebglValidation) {
    $Command += "--viewerRelaxedWebglValidation"
  }
  if ($ViewerZeroCopy) {
    $Command += "--viewerZeroCopy"
  }
  if ($ViewerInProcessGpu) {
    $Command += "--viewerInProcessGpu"
  }
  if ($ViewerSingleProcess) {
    $Command += "--viewerSingleProcess"
  }
  if ($ViewerForceAngleBackend) {
    $Command += @("--viewerForceAngleBackend", $ViewerForceAngleBackend)
  }
  if ($ViewerDisableUnneededBlinkFeatures) {
    $Command += "--viewerDisableUnneededBlinkFeatures"
  }
  if ($ViewerDirectGpuPresentation) {
    $Command += "--viewerDirectGpuPresentation"
  }
  if ($ViewerDeferWebgpuPipelineFlush) {
    $Command += "--viewerDeferWebgpuPipelineFlush"
  }
  if ($ViewerDeferWebgpuQueueFlush) {
    $Command += "--viewerDeferWebgpuQueueFlush"
  }
  if ($ViewerDeferWebgpuSubmitFlush) {
    $Command += "--viewerDeferWebgpuSubmitFlush"
  }
  if ($ViewerSkipWebgpuCanvasTextureValidation) {
    $Command += "--viewerSkipWebgpuCanvasTextureValidation"
  }
  if ($ViewerSkipWebgpuCanvasMemoryAccounting) {
    $Command += "--viewerSkipWebgpuCanvasMemoryAccounting"
  }
  if ($ViewerSkipWebgpuCopyExternalImageColorConversion) {
    $Command += "--viewerSkipWebgpuCopyExternalImageColorConversion"
  }
  if ($ViewerSkipWebgpuCopyExternalImageColorSpaceValidation) {
    $Command += "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation"
  }
  if ($ViewerSkipWebgpuCopyExternalImageDestValidation) {
    $Command += "--viewerSkipWebgpuCopyExternalImageDestValidation"
  }
  if ($ViewerSkipWebgpuCopyExternalImageSourceValidation) {
    $Command += "--viewerSkipWebgpuCopyExternalImageSourceValidation"
  }
  if ($ViewerSkipWebgpuCopyExternalImageCopySizeValidation) {
    $Command += "--viewerSkipWebgpuCopyExternalImageCopySizeValidation"
  }
  if ($ViewerSkipWebgpuWriteTextureLayoutValidation) {
    $Command += "--viewerSkipWebgpuWriteTextureLayoutValidation"
  }
  if ($ViewerRejectWebgpuCpuTextureFallback) {
    $Command += "--viewerRejectWebgpuCpuTextureFallback"
  }
  if ($ViewerSkipWebgpuUseCounters) {
    $Command += "--viewerSkipWebgpuUseCounters"
  }
  if ($ViewerCacheWebgpuBindGroupLayouts) {
    $Command += "--viewerCacheWebgpuBindGroupLayouts"
  }
  if ($ViewerSkipWebgpuCommandLabels) {
    $Command += "--viewerSkipWebgpuCommandLabels"
  }
  if ($ViewerSkipWebgpuResourceLabels) {
    $Command += "--viewerSkipWebgpuResourceLabels"
  }
  if ($ViewerSkipWebgpuShaderSourceNullCheck) {
    $Command += "--viewerSkipWebgpuShaderSourceNullCheck"
  }
  if ($ViewerSkipWebgpuShaderMemoryAccounting) {
    $Command += "--viewerSkipWebgpuShaderMemoryAccounting"
  }
  if ($ViewerSkipWebgpuRedundantPipelineSets) {
    $Command += "--viewerSkipWebgpuRedundantPipelineSets"
  }
  if ($ViewerSkipWebgpuRedundantBindGroupSets) {
    $Command += "--viewerSkipWebgpuRedundantBindGroupSets"
  }
  if ($ViewerSkipWebgpuRedundantBufferSets) {
    $Command += "--viewerSkipWebgpuRedundantBufferSets"
  }
  if ($ViewerSkipWebgpuRedundantRenderStateSets) {
    $Command += "--viewerSkipWebgpuRedundantRenderStateSets"
  }
  if ($ViewerTraceWebgpuQueue) {
    $Command += "--viewerTraceWebgpuQueue"
  }
  if ($Precompile) {
    $Command += "--precompile"
  }
  if ($SettleGpuAfterWarmup) {
    $Command += "--settleGpuAfterWarmup"
  }
  if ($DisableGpuTiming) {
    $Command += "--disableGpuTiming"
  }
  if ($PrerenderFrames -gt 0) {
    $Command += @("--prerenderFrames", [string]$PrerenderFrames)
  }
  if ($ExpectedResourceWarmupPipelineQuietFrames -gt 0) {
    $Command += @("--pipelineQuietFrames", [string]$ExpectedResourceWarmupPipelineQuietFrames)
    $Command += @("--pipelineQuietMaxFrames", [string]$ExpectedResourceWarmupPipelineQuietMaxFrames)
  }
  if ($WebGpuBundleMode -ne "off") {
    $Command += @("--webgpuBundleMode", $WebGpuBundleMode)
  }
  if ($ProfileCacheKey) {
    $Command += @("--userDataDir", (Get-SceneUserDataDir $Scene), "--profileCacheKey", $ProfileCacheKey)
  }
  foreach ($Flag in $BrowserFlag) {
    $Command += @("--browser-flag", $Flag)
  }

  node @Command
  if ($LASTEXITCODE -ne 0) {
    throw "Benchmark failed for scene '$Scene' with renderer '$Renderer'."
  }

  node (Join-Path $Root "scripts\validate_metrics.mjs") $Out
  if ($LASTEXITCODE -ne 0) {
    throw "Benchmark output failed metric validation for scene '$Scene': $Out"
  }
  if ($RequireGpuMetadata -and -not (Test-ResultGpuMetadata $Out)) {
    throw "Benchmark output is missing GPU metadata for scene '$Scene': $Out"
  }
  if (-not (Test-ResultGpuTimingMode $Out $ExpectedGpuTimingEnabled)) {
    throw "Benchmark output has the wrong GPU timing mode for scene '$Scene': $Out"
  }
  if (-not (Test-ResultResourceWarmupMode $Out $ExpectedResourceWarmupPrecompile $ExpectedResourceWarmupPrerenderFrames $ExpectedResourceWarmupSettleGpuAfterWarmup $ExpectedResourceWarmupPipelineQuietFrames $ExpectedResourceWarmupPipelineQuietMaxFrames)) {
    throw "Benchmark output has the wrong resource warmup mode for scene '$Scene': $Out"
  }
  if (-not (Test-ResultProfileCacheMode $Out $ProfileCacheKey)) {
    throw "Benchmark output has the wrong profile-cache mode/key for scene '$Scene': $Out"
  }
  if (-not (Test-ResultComplexityMode $Out $Complexity)) {
    throw "Benchmark output has the wrong complexity for scene '$Scene': $Out"
  }
  if (-not (Test-ResultWebGpuBundleMode $Out $WebGpuBundleMode)) {
    throw "Benchmark output has the wrong WebGPU BundleGroup mode for scene '$Scene': $Out"
  }
  if (-not (Test-ResultViewerFlagMetadata $Out)) {
    throw "Benchmark output has the wrong viewer flag metadata for scene '$Scene': $Out"
  }
  if (-not (Test-ResultBrowserExtraFlags $Out)) {
    throw "Benchmark output is missing expected extra browser flags for scene '$Scene': $Out"
  }
}

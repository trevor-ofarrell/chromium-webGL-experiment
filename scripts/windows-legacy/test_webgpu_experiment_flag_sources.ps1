[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
    throw "Required file not found: $PathValue"
  }
  return Get-Content -LiteralPath $Resolved -Raw
}

function New-StringSet {
  return ,[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
}

function Add-CommaSeparatedTokens {
  param(
    [System.Collections.Generic.HashSet[string]]$Set,
    [string]$Value,
    [string]$Source
  )

  foreach ($Part in ($Value -split ",")) {
    $Token = $Part.Trim()
    if (-not $Token) {
      throw "Empty token found in $Source value '$Value'."
    }
    $Token = ($Token -split ":", 2)[0]
    $null = $Set.Add($Token)
  }
}

function Assert-SetContains {
  param(
    [System.Collections.Generic.HashSet[string]]$Set,
    [string]$Value,
    [string]$Description
  )

  if (-not $Set.Contains($Value)) {
    throw "Missing ${Description}: $Value"
  }
}

function Assert-NonEmpty {
  param(
    [System.Collections.Generic.HashSet[string]]$Set,
    [string]$Description
  )

  if ($Set.Count -le 0) {
    throw "No $Description were discovered."
  }
}

function Assert-TextContains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )

  if ($Text -notmatch $Pattern) {
    throw "Missing ${Description}. Pattern: $Pattern"
  }
}

$Matrix = Read-RepoFile "scripts\run_trusted_experiment_matrix.ps1"
$BlockerRunner = Read-RepoFile "scripts\run_blocker_experiments.ps1"
$BenchmarkRunner = Read-RepoFile "scripts\run_benchmark.mjs"
$TraceRunner = Read-RepoFile "scripts\run_trace_capture.mjs"
$ShellSwitches = Read-RepoFile "src\content\shell\common\shell_switches.h"
$ShellBrowserClient = Read-RepoFile "src\content\shell\browser\shell_content_browser_client.cc"
$WebGpuPatch = Read-RepoFile "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"
$TrustedFlagDoc = Read-RepoFile "docs\trusted_content_flags.md"
$DawnSource = Read-RepoFile "src\third_party\dawn\src\dawn\native\Toggles.cpp"
$FeatureSource = @(
  (Read-RepoFile "src\gpu\config\gpu_finch_features.cc")
  (Read-RepoFile "src\gpu\config\gpu_finch_features.h")
) -join "`n"
$ServiceUtilsSource = Read-RepoFile "src\gpu\command_buffer\service\service_utils.cc"

$MatrixDawnToggles = New-StringSet
$MatrixChromiumFeatures = New-StringSet
$MatrixWebGpuAdapters = New-StringSet
$MatrixViewerCliFlags = New-StringSet

foreach ($Match in [regex]::Matches($Matrix, '--(?:enable|disable)-dawn-features=([^"''\s\)]+)')) {
  Add-CommaSeparatedTokens -Set $MatrixDawnToggles -Value $Match.Groups[1].Value -Source "Dawn experiment flag"
}
foreach ($Match in [regex]::Matches($Matrix, '--(?:enable|disable)-features=([^"''\s\)]+)')) {
  Add-CommaSeparatedTokens -Set $MatrixChromiumFeatures -Value $Match.Groups[1].Value -Source "Chromium feature experiment flag"
}
foreach ($Match in [regex]::Matches($Matrix, '--use-webgpu-adapter=([^"''\s\)]+)')) {
  Add-CommaSeparatedTokens -Set $MatrixWebGpuAdapters -Value $Match.Groups[1].Value -Source "WebGPU adapter experiment flag"
}
foreach ($Match in [regex]::Matches($Matrix, '"(--viewer[A-Za-z0-9]+)"')) {
  $null = $MatrixViewerCliFlags.Add($Match.Groups[1].Value)
}

Assert-NonEmpty $MatrixDawnToggles "Dawn experiment toggles"
Assert-NonEmpty $MatrixChromiumFeatures "Chromium feature experiment flags"
Assert-NonEmpty $MatrixWebGpuAdapters "WebGPU adapter experiment flags"

$RegisteredDawnToggles = New-StringSet
foreach ($Match in [regex]::Matches($DawnSource, '\{"([a-z0-9_]+)"\s*,')) {
  $null = $RegisteredDawnToggles.Add($Match.Groups[1].Value)
}

$RegisteredChromiumFeatures = New-StringSet
foreach ($Match in [regex]::Matches($FeatureSource, '\bBASE_FEATURE\(\s*k([A-Za-z0-9_]+)')) {
  $null = $RegisteredChromiumFeatures.Add($Match.Groups[1].Value)
}
foreach ($Match in [regex]::Matches($FeatureSource, '\bBASE_DECLARE_FEATURE\(\s*k([A-Za-z0-9_]+)')) {
  $null = $RegisteredChromiumFeatures.Add($Match.Groups[1].Value)
}
foreach ($Match in [regex]::Matches($FeatureSource, '\bBASE_FEATURE_PARAM\([^,]+,\s*k([A-Za-z0-9_]+)')) {
  $null = $RegisteredChromiumFeatures.Add($Match.Groups[1].Value)
}

$RegisteredWebGpuAdapters = New-StringSet
foreach ($Match in [regex]::Matches($ServiceUtilsSource, '\{"([^"]+)",\s*WebGPUAdapterName::k[A-Za-z0-9_]+')) {
  if ($Match.Groups[1].Value) {
    $null = $RegisteredWebGpuAdapters.Add($Match.Groups[1].Value)
  }
}

foreach ($Toggle in $MatrixDawnToggles) {
  Assert-SetContains $RegisteredDawnToggles $Toggle "Dawn toggle registered in Toggles.cpp"
}
foreach ($Feature in $MatrixChromiumFeatures) {
  Assert-SetContains $RegisteredChromiumFeatures $Feature "Chromium GPU feature declared in gpu_finch_features"
}
foreach ($Adapter in $MatrixWebGpuAdapters) {
  Assert-SetContains $RegisteredWebGpuAdapters $Adapter "WebGPU adapter value parsed by service_utils.cc"
}

foreach ($ExpectedToggle in @(
    "d3d11_delay_flush_to_gpu",
    "d3d11_use_unmonitored_fence",
    "d3d11_disable_fence",
    "wait_is_thread_safe",
    "auto_map_backend_buffer",
    "disable_lazy_clear_for_mapped_at_creation_buffer",
    "d3d12_relax_buffer_texture_copy_pitch_and_offset_alignment",
    "use_dxc",
    "blob_cache_hash_validation",
    "skip_validation",
    "disable_robustness"
  )) {
  Assert-SetContains $MatrixDawnToggles $ExpectedToggle "targeted trusted WebGPU Dawn experiment toggle"
}

foreach ($ExpectedFeature in @(
    "RemoveGPULegacyIPC",
    "WebGPUUseHLSL2021",
    "WebGPUEnableRangeAnalysisForRobustness",
    "IncreasedCmdBufferParseSlice",
    "D3DBackingUploadWithUpdateSubresource"
  )) {
  Assert-SetContains $MatrixChromiumFeatures $ExpectedFeature "targeted trusted WebGPU Chromium feature experiment"
}

Assert-SetContains $MatrixWebGpuAdapters "d3d11" "targeted trusted WebGPU D3D11 adapter experiment"

$SourceBackedWebGpuViewerFlags = @(
  [pscustomobject]@{ Cli = "--viewerDeferWebgpuPipelineFlush"; Browser = "--viewer-defer-webgpu-pipeline-flush"; Metadata = "viewer_defer_webgpu_pipeline_flush"; PatchSwitch = "viewer-defer-webgpu-pipeline-flush" },
  [pscustomobject]@{ Cli = "--viewerCacheWebgpuBindGroupLayouts"; Browser = "--viewer-cache-webgpu-bind-group-layouts"; Metadata = "viewer_cache_webgpu_bind_group_layouts"; PatchSwitch = "viewer-cache-webgpu-bind-group-layouts" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuCommandLabels"; Browser = "--viewer-skip-webgpu-command-labels"; Metadata = "viewer_skip_webgpu_command_labels"; PatchSwitch = "viewer-skip-webgpu-command-labels" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuResourceLabels"; Browser = "--viewer-skip-webgpu-resource-labels"; Metadata = "viewer_skip_webgpu_resource_labels"; PatchSwitch = "viewer-skip-webgpu-resource-labels" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuShaderSourceNullCheck"; Browser = "--viewer-skip-webgpu-shader-source-null-check"; Metadata = "viewer_skip_webgpu_shader_source_null_check"; PatchSwitch = "viewer-skip-webgpu-shader-source-null-check" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuShaderMemoryAccounting"; Browser = "--viewer-skip-webgpu-shader-memory-accounting"; Metadata = "viewer_skip_webgpu_shader_memory_accounting"; PatchSwitch = "viewer-skip-webgpu-shader-memory-accounting" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuRedundantPipelineSets"; Browser = "--viewer-skip-webgpu-redundant-pipeline-sets"; Metadata = "viewer_skip_webgpu_redundant_pipeline_sets"; PatchSwitch = "viewer-skip-webgpu-redundant-pipeline-sets" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuRedundantBindGroupSets"; Browser = "--viewer-skip-webgpu-redundant-bind-group-sets"; Metadata = "viewer_skip_webgpu_redundant_bind_group_sets"; PatchSwitch = "viewer-skip-webgpu-redundant-bind-group-sets" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuRedundantBufferSets"; Browser = "--viewer-skip-webgpu-redundant-buffer-sets"; Metadata = "viewer_skip_webgpu_redundant_buffer_sets"; PatchSwitch = "viewer-skip-webgpu-redundant-buffer-sets" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuRedundantRenderStateSets"; Browser = "--viewer-skip-webgpu-redundant-render-state-sets"; Metadata = "viewer_skip_webgpu_redundant_render_state_sets"; PatchSwitch = "viewer-skip-webgpu-redundant-render-state-sets" },
  [pscustomobject]@{ Cli = "--viewerDeferWebgpuQueueFlush"; Browser = "--viewer-defer-webgpu-queue-flush"; Metadata = "viewer_defer_webgpu_queue_flush"; PatchSwitch = "viewer-defer-webgpu-queue-flush" },
  [pscustomobject]@{ Cli = "--viewerDeferWebgpuSubmitFlush"; Browser = "--viewer-defer-webgpu-submit-flush"; Metadata = "viewer_defer_webgpu_submit_flush"; PatchSwitch = "viewer-defer-webgpu-submit-flush" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuCanvasTextureValidation"; Browser = "--viewer-skip-webgpu-canvas-texture-validation"; Metadata = "viewer_skip_webgpu_canvas_texture_validation"; PatchSwitch = "viewer-skip-webgpu-canvas-texture-validation" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuCanvasMemoryAccounting"; Browser = "--viewer-skip-webgpu-canvas-memory-accounting"; Metadata = "viewer_skip_webgpu_canvas_memory_accounting"; PatchSwitch = "viewer-skip-webgpu-canvas-memory-accounting" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuCopyExternalImageColorConversion"; Browser = "--viewer-skip-webgpu-copy-external-image-color-conversion"; Metadata = "viewer_skip_webgpu_copy_external_image_color_conversion"; PatchSwitch = "viewer-skip-webgpu-copy-external-image-color-conversion" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation"; Browser = "--viewer-skip-webgpu-copy-external-image-color-space-validation"; Metadata = "viewer_skip_webgpu_copy_external_image_color_space_validation"; PatchSwitch = "viewer-skip-webgpu-copy-external-image-color-space-validation" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuCopyExternalImageDestValidation"; Browser = "--viewer-skip-webgpu-copy-external-image-dest-validation"; Metadata = "viewer_skip_webgpu_copy_external_image_dest_validation"; PatchSwitch = "viewer-skip-webgpu-copy-external-image-dest-validation" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuCopyExternalImageSourceValidation"; Browser = "--viewer-skip-webgpu-copy-external-image-source-validation"; Metadata = "viewer_skip_webgpu_copy_external_image_source_validation"; PatchSwitch = "viewer-skip-webgpu-copy-external-image-source-validation" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuCopyExternalImageCopySizeValidation"; Browser = "--viewer-skip-webgpu-copy-external-image-copy-size-validation"; Metadata = "viewer_skip_webgpu_copy_external_image_copy_size_validation"; PatchSwitch = "viewer-skip-webgpu-copy-external-image-copy-size-validation" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuWriteTextureLayoutValidation"; Browser = "--viewer-skip-webgpu-write-texture-layout-validation"; Metadata = "viewer_skip_webgpu_write_texture_layout_validation"; PatchSwitch = "viewer-skip-webgpu-write-texture-layout-validation" },
  [pscustomobject]@{ Cli = "--viewerRejectWebgpuCpuTextureFallback"; Browser = "--viewer-reject-webgpu-cpu-texture-fallback"; Metadata = "viewer_reject_webgpu_cpu_texture_fallback"; PatchSwitch = "viewer-reject-webgpu-cpu-texture-fallback" },
  [pscustomobject]@{ Cli = "--viewerSkipWebgpuUseCounters"; Browser = "--viewer-skip-webgpu-use-counters"; Metadata = "viewer_skip_webgpu_use_counters"; PatchSwitch = "viewer-skip-webgpu-use-counters" }
)

foreach ($Flag in $SourceBackedWebGpuViewerFlags) {
  Assert-SetContains $MatrixViewerCliFlags $Flag.Cli "trusted matrix source-backed WebGPU viewer flag"
  Assert-TextContains $Matrix ([regex]::Escape("`"$($Flag.Cli)`"")) "trusted matrix schedules $($Flag.Cli)"
  Assert-TextContains $Matrix ([regex]::Escape($Flag.Metadata)) "trusted matrix records metadata $($Flag.Metadata)"
  Assert-TextContains $BenchmarkRunner ([regex]::Escape("browserArgs.push('$($Flag.Browser)'")) "benchmark runner forwards $($Flag.Cli) as $($Flag.Browser)"
  Assert-TextContains $BenchmarkRunner ([regex]::Escape($Flag.Metadata)) "benchmark runner records metadata $($Flag.Metadata)"
  Assert-TextContains $TraceRunner ([regex]::Escape("browserArgs.push('$($Flag.Browser)'")) "trace runner forwards $($Flag.Cli) as $($Flag.Browser)"
  Assert-TextContains $TraceRunner ([regex]::Escape($Flag.Metadata)) "trace runner records metadata $($Flag.Metadata)"
  Assert-TextContains $WebGpuPatch ([regex]::Escape("`"$($Flag.PatchSwitch)`"")) "Chromium WebGPU patch defines $($Flag.Browser)"
  Assert-TextContains $TrustedFlagDoc ([regex]::Escape($Flag.Browser)) "trusted-content flag doc documents $($Flag.Browser)"
}

$SourceBackedWebGpuTraceFlags = @(
  [pscustomobject]@{ Cli = "--viewerTraceWebgpuQueue"; Browser = "--viewer-trace-webgpu-queue"; Metadata = "viewer_trace_webgpu_queue"; PatchSwitch = "viewer-trace-webgpu-queue" }
)

foreach ($Flag in $SourceBackedWebGpuTraceFlags) {
  Assert-TextContains $BlockerRunner ([regex]::Escape($Flag.Cli)) "targeted blocker trace runner schedules $($Flag.Cli)"
  Assert-TextContains $BlockerRunner ([regex]::Escape($Flag.Metadata)) "targeted blocker trace manifest records $($Flag.Metadata)"
  Assert-TextContains $TraceRunner ([regex]::Escape("browserArgs.push('$($Flag.Browser)'")) "trace runner forwards $($Flag.Cli) as $($Flag.Browser)"
  Assert-TextContains $TraceRunner ([regex]::Escape($Flag.Metadata)) "trace runner records metadata $($Flag.Metadata)"
  Assert-TextContains $BenchmarkRunner ([regex]::Escape("browserArgs.push('$($Flag.Browser)'")) "benchmark runner forwards diagnostic $($Flag.Cli) as $($Flag.Browser)"
  Assert-TextContains $BenchmarkRunner ([regex]::Escape($Flag.Metadata)) "benchmark runner records diagnostic metadata $($Flag.Metadata)"
  Assert-TextContains $WebGpuPatch ([regex]::Escape("`"$($Flag.PatchSwitch)`"")) "Chromium WebGPU patch defines $($Flag.Browser)"
  Assert-TextContains $TrustedFlagDoc ([regex]::Escape($Flag.Browser)) "trusted-content flag doc documents $($Flag.Browser)"
}

foreach ($SwitchConstant in @(
    "kViewerAppUrl",
    "kViewerTrustedContent",
    "kViewerDeferWebGPUPipelineFlush",
    "kViewerDeferWebGPUQueueFlush",
    "kViewerDeferWebGPUSubmitFlush",
    "kViewerSkipWebGPUCanvasTextureValidation",
    "kViewerSkipWebGPUCanvasMemoryAccounting",
    "kViewerSkipWebGPUCopyExternalImageColorConversion",
    "kViewerSkipWebGPUCopyExternalImageColorSpaceValidation",
    "kViewerSkipWebGPUCopyExternalImageDestValidation",
    "kViewerSkipWebGPUCopyExternalImageSourceValidation",
    "kViewerSkipWebGPUCopyExternalImageCopySizeValidation",
    "kViewerSkipWebGPUWriteTextureLayoutValidation",
    "kViewerRejectWebGPUCPUTextureFallback",
    "kViewerSkipWebGPUUseCounters",
    "kViewerCacheWebGPUBindGroupLayouts",
    "kViewerSkipWebGPUCommandLabels",
    "kViewerSkipWebGPUResourceLabels",
    "kViewerSkipWebGPUShaderSourceNullCheck",
    "kViewerSkipWebGPUShaderMemoryAccounting",
    "kViewerSkipWebGPURedundantPipelineSets",
    "kViewerSkipWebGPURedundantBindGroupSets",
    "kViewerSkipWebGPURedundantBufferSets",
    "kViewerSkipWebGPURedundantRenderStateSets",
    "kViewerTraceWebGPUQueue"
  )) {
  Assert-TextContains $ShellSwitches "inline constexpr char $SwitchConstant\[\]" "content_shell declares $SwitchConstant"
  Assert-TextContains $ShellBrowserClient "switches::$SwitchConstant" "content_shell forwards $SwitchConstant to child processes"
}

Write-Host "Trusted WebGPU experiment Dawn toggles, Chromium feature flags, adapter values, source-backed viewer flags, and trace-only diagnostics map to source registries and patch wiring."

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
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Missing benchmark flag metadata evidence: $Description. Pattern: $Pattern"
  }
}

$Runner = Read-RepoFile "scripts\run_benchmark.mjs"
$TraceRunner = Read-RepoFile "scripts\run_trace_capture.mjs"
$SuiteRunner = Read-RepoFile "scripts\run_full_suite.ps1"
$OfficialRunner = Read-RepoFile "scripts\run_official_comparison.ps1"
$PostAtlRunner = Read-RepoFile "scripts\run_post_atl_pipeline.ps1"
$Validator = Read-RepoFile "scripts\validate_metrics.mjs"
$TraceValidator = Read-RepoFile "scripts\validate_trace_result.mjs"
$SuiteValidator = Read-RepoFile "scripts\validate_benchmark_suite.mjs"

$FlagMappings = @(
  @{ Arg = "viewerMode"; Switch = "--viewer-block-external-navigation"; Field = "viewer_block_external_navigation"; Type = "boolean" },
  @{ Arg = "viewerTrustedContent"; Switch = "--viewer-trusted-content"; Field = "viewer_trusted_content"; Type = "boolean" },
  @{ Arg = "viewerAggressiveGpu"; Switch = "--viewer-aggressive-gpu"; Field = "viewer_aggressive_gpu"; Type = "boolean" },
  @{ Arg = "viewerRelaxedWebglValidation"; Switch = "--viewer-relaxed-webgl-validation"; Field = "viewer_relaxed_webgl_validation"; Type = "boolean" },
  @{ Arg = "viewerZeroCopy"; Switch = "--viewer-zero-copy"; Field = "viewer_zero_copy"; Type = "boolean" },
  @{ Arg = "viewerInProcessGpu"; Switch = "--viewer-in-process-gpu"; Field = "viewer_in_process_gpu"; Type = "boolean" },
  @{ Arg = "viewerSingleProcess"; Switch = "--viewer-single-process"; Field = "viewer_single_process"; Type = "boolean" },
  @{ Arg = "viewerForceAngleBackend"; Switch = "--viewer-force-angle-backend"; Field = "viewer_force_angle_backend"; Type = "string" },
  @{ Arg = "viewerDisableUnneededBlinkFeatures"; Switch = "--viewer-disable-unneeded-blink-features"; Field = "viewer_disable_unneeded_blink_features"; Type = "boolean" },
  @{ Arg = "viewerDirectGpuPresentation"; Switch = "--viewer-direct-gpu-presentation"; Field = "viewer_direct_gpu_presentation"; Type = "boolean" },
  @{ Arg = "viewerDeferWebgpuPipelineFlush"; Switch = "--viewer-defer-webgpu-pipeline-flush"; Field = "viewer_defer_webgpu_pipeline_flush"; Type = "boolean" },
  @{ Arg = "viewerDeferWebgpuQueueFlush"; Switch = "--viewer-defer-webgpu-queue-flush"; Field = "viewer_defer_webgpu_queue_flush"; Type = "boolean" },
  @{ Arg = "viewerDeferWebgpuSubmitFlush"; Switch = "--viewer-defer-webgpu-submit-flush"; Field = "viewer_defer_webgpu_submit_flush"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuCanvasTextureValidation"; Switch = "--viewer-skip-webgpu-canvas-texture-validation"; Field = "viewer_skip_webgpu_canvas_texture_validation"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuCanvasMemoryAccounting"; Switch = "--viewer-skip-webgpu-canvas-memory-accounting"; Field = "viewer_skip_webgpu_canvas_memory_accounting"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuCopyExternalImageColorConversion"; Switch = "--viewer-skip-webgpu-copy-external-image-color-conversion"; Field = "viewer_skip_webgpu_copy_external_image_color_conversion"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuCopyExternalImageColorSpaceValidation"; Switch = "--viewer-skip-webgpu-copy-external-image-color-space-validation"; Field = "viewer_skip_webgpu_copy_external_image_color_space_validation"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuCopyExternalImageDestValidation"; Switch = "--viewer-skip-webgpu-copy-external-image-dest-validation"; Field = "viewer_skip_webgpu_copy_external_image_dest_validation"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuCopyExternalImageSourceValidation"; Switch = "--viewer-skip-webgpu-copy-external-image-source-validation"; Field = "viewer_skip_webgpu_copy_external_image_source_validation"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuCopyExternalImageCopySizeValidation"; Switch = "--viewer-skip-webgpu-copy-external-image-copy-size-validation"; Field = "viewer_skip_webgpu_copy_external_image_copy_size_validation"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuWriteTextureLayoutValidation"; Switch = "--viewer-skip-webgpu-write-texture-layout-validation"; Field = "viewer_skip_webgpu_write_texture_layout_validation"; Type = "boolean" },
  @{ Arg = "viewerRejectWebgpuCpuTextureFallback"; Switch = "--viewer-reject-webgpu-cpu-texture-fallback"; Field = "viewer_reject_webgpu_cpu_texture_fallback"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuUseCounters"; Switch = "--viewer-skip-webgpu-use-counters"; Field = "viewer_skip_webgpu_use_counters"; Type = "boolean" },
  @{ Arg = "viewerCacheWebgpuBindGroupLayouts"; Switch = "--viewer-cache-webgpu-bind-group-layouts"; Field = "viewer_cache_webgpu_bind_group_layouts"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuCommandLabels"; Switch = "--viewer-skip-webgpu-command-labels"; Field = "viewer_skip_webgpu_command_labels"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuResourceLabels"; Switch = "--viewer-skip-webgpu-resource-labels"; Field = "viewer_skip_webgpu_resource_labels"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuShaderSourceNullCheck"; Switch = "--viewer-skip-webgpu-shader-source-null-check"; Field = "viewer_skip_webgpu_shader_source_null_check"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuShaderMemoryAccounting"; Switch = "--viewer-skip-webgpu-shader-memory-accounting"; Field = "viewer_skip_webgpu_shader_memory_accounting"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuRedundantPipelineSets"; Switch = "--viewer-skip-webgpu-redundant-pipeline-sets"; Field = "viewer_skip_webgpu_redundant_pipeline_sets"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuRedundantBindGroupSets"; Switch = "--viewer-skip-webgpu-redundant-bind-group-sets"; Field = "viewer_skip_webgpu_redundant_bind_group_sets"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuRedundantBufferSets"; Switch = "--viewer-skip-webgpu-redundant-buffer-sets"; Field = "viewer_skip_webgpu_redundant_buffer_sets"; Type = "boolean" },
  @{ Arg = "viewerSkipWebgpuRedundantRenderStateSets"; Switch = "--viewer-skip-webgpu-redundant-render-state-sets"; Field = "viewer_skip_webgpu_redundant_render_state_sets"; Type = "boolean" },
  @{ Arg = "viewerTraceWebgpuQueue"; Switch = "--viewer-trace-webgpu-queue"; Field = "viewer_trace_webgpu_queue"; Type = "boolean" }
)

foreach ($Mapping in $FlagMappings) {
  Assert-Contains $Runner ([regex]::Escape($Mapping.Arg)) "parser support for $($Mapping.Arg)"
  Assert-Contains $Runner ([regex]::Escape($Mapping.Switch)) "browser switch emission for $($Mapping.Switch)"
  Assert-Contains $Runner "result\.$([regex]::Escape($Mapping.Field))\s*=" "result metadata field $($Mapping.Field)"
  Assert-Contains $TraceRunner ([regex]::Escape($Mapping.Arg)) "trace parser support for $($Mapping.Arg)"
  Assert-Contains $TraceRunner ([regex]::Escape($Mapping.Switch)) "trace browser switch emission for $($Mapping.Switch)"
  Assert-Contains $TraceRunner "$([regex]::Escape($Mapping.Field)):\s*args\.$([regex]::Escape($Mapping.Arg))" "trace sidecar metadata field $($Mapping.Field)"
  if ($Mapping.Type -eq "boolean") {
    Assert-Contains $SuiteRunner "\[switch\]\`$$([regex]::Escape($Mapping.Arg))" "full-suite parameter support for $($Mapping.Arg)"
  } else {
    Assert-Contains $SuiteRunner "\[string\]\`$$([regex]::Escape($Mapping.Arg))" "full-suite parameter support for $($Mapping.Arg)"
  }
  Assert-Contains $SuiteRunner "--$([regex]::Escape($Mapping.Arg))" "full-suite forwarding for --$($Mapping.Arg)"
  if ($Mapping.Type -eq "boolean") {
    Assert-Contains $Validator "'$([regex]::Escape($Mapping.Field))'" "optional boolean validation for $($Mapping.Field)"
  } else {
    Assert-Contains $Validator "'$([regex]::Escape($Mapping.Field))'" "optional string validation for $($Mapping.Field)"
  }
}

$OfficialExpectedMetadataFields = @(
  "viewer_defer_webgpu_pipeline_flush",
  "viewer_defer_webgpu_queue_flush",
  "viewer_defer_webgpu_submit_flush",
  "viewer_skip_webgpu_canvas_texture_validation",
  "viewer_skip_webgpu_canvas_memory_accounting",
  "viewer_skip_webgpu_copy_external_image_color_conversion",
  "viewer_skip_webgpu_copy_external_image_color_space_validation",
  "viewer_skip_webgpu_copy_external_image_dest_validation",
  "viewer_skip_webgpu_copy_external_image_source_validation",
  "viewer_skip_webgpu_copy_external_image_copy_size_validation",
  "viewer_skip_webgpu_write_texture_layout_validation",
  "viewer_reject_webgpu_cpu_texture_fallback",
  "viewer_skip_webgpu_use_counters",
  "viewer_cache_webgpu_bind_group_layouts",
  "viewer_skip_webgpu_command_labels",
  "viewer_skip_webgpu_resource_labels",
  "viewer_skip_webgpu_shader_source_null_check",
  "viewer_skip_webgpu_shader_memory_accounting",
  "viewer_skip_webgpu_redundant_pipeline_sets",
  "viewer_skip_webgpu_redundant_bind_group_sets",
  "viewer_skip_webgpu_redundant_buffer_sets",
  "viewer_skip_webgpu_redundant_render_state_sets",
  "viewer_trace_webgpu_queue"
)

foreach ($Field in $OfficialExpectedMetadataFields) {
  Assert-Contains `
    $OfficialRunner `
    "$([regex]::Escape($Field))\s*=" `
    "official comparison expected flag metadata includes $Field"
}

Assert-Contains $SuiteRunner "Test-ResultViewerFlagMetadata" "full-suite reuse validation checks viewer flag metadata before reusing results"
Assert-Contains $SuiteRunner "Existing benchmark result has the wrong viewer flag metadata" "full-suite rejects reused results from different viewer flags"
Assert-Contains $SuiteRunner "Test-ResultBrowserExtraFlags" "full-suite reuse validation checks extra browser flags before reusing results"
Assert-Contains $OfficialRunner "\[switch\]\`$AggressiveWebGpuSourceFastPath" "official comparison exposes source-backed aggressive WebGPU suite profile"
Assert-Contains $OfficialRunner "\[switch\]\`$AggressiveWebGpuUploadFastPath" "official comparison exposes upload-focused aggressive WebGPU suite profile"
Assert-Contains $OfficialRunner "Get-AggressiveWebGpuSuiteArgs[\s\S]*ViewerDeferWebgpuPipelineFlush[\s\S]*ViewerCacheWebgpuBindGroupLayouts[\s\S]*ViewerSkipWebgpuCommandLabels" "official aggressive WebGPU source fast path forwards source-backed runner flags"
Assert-Contains $OfficialRunner "Get-AggressiveWebGpuSuiteArgs[\s\S]*ViewerSkipWebgpuResourceLabels[\s\S]*ViewerSkipWebgpuShaderSourceNullCheck[\s\S]*ViewerSkipWebgpuShaderMemoryAccounting[\s\S]*ViewerSkipWebgpuRedundantPipelineSets[\s\S]*ViewerSkipWebgpuRedundantBindGroupSets[\s\S]*ViewerSkipWebgpuRedundantBufferSets[\s\S]*ViewerSkipWebgpuRedundantRenderStateSets" "official aggressive WebGPU source fast path forwards label, shader, and redundant-state skips"
Assert-Contains $OfficialRunner "Get-AggressiveWebGpuSuiteArgs[\s\S]*ViewerSkipWebgpuCopyExternalImageColorConversion[\s\S]*ViewerRejectWebgpuCpuTextureFallback" "official aggressive WebGPU upload fast path forwards CPU-fallback-rejected upload flags"
Assert-Contains $OfficialRunner "Get-AggressiveWebGpuExpectedFlagMetadata" "official aggressive WebGPU validation derives expected metadata from selected fast-path flags"
Assert-Contains $OfficialRunner "Get-AggressiveWebGpuExpectedFlagMetadata[\s\S]*ViewerSkipWebgpuResourceLabels[\s\S]*ViewerSkipWebgpuShaderSourceNullCheck[\s\S]*ViewerSkipWebgpuShaderMemoryAccounting[\s\S]*ViewerSkipWebgpuRedundantPipelineSets[\s\S]*ViewerSkipWebgpuRedundantBindGroupSets[\s\S]*ViewerSkipWebgpuRedundantBufferSets[\s\S]*ViewerSkipWebgpuRedundantRenderStateSets" "official aggressive WebGPU source fast path validates label, shader, and redundant-state metadata"
Assert-Contains $PostAtlRunner "\[switch\]\`$AggressiveWebGpuSourceFastPath" "post-ATL pipeline exposes source-backed aggressive WebGPU suite profile"
Assert-Contains $PostAtlRunner "\[switch\]\`$AggressiveWebGpuUploadFastPath" "post-ATL pipeline exposes upload-focused aggressive WebGPU suite profile"
Assert-Contains $PostAtlRunner "-AggressiveWebGpuSourceFastPath" "post-ATL pipeline forwards source-backed aggressive WebGPU profile to official comparison"
Assert-Contains $PostAtlRunner "-AggressiveWebGpuUploadFastPath" "post-ATL pipeline forwards upload-focused aggressive WebGPU profile to official comparison"

Assert-Contains $Runner "result\.requested_angle_backend\s*=" "requested ANGLE backend metadata"
Assert-Contains $Runner "requestedAngleBackend\s*=\s*args\.angleBackend\s*\|\|\s*args\.viewerForceAngleBackend\s*\|\|\s*null" "requested ANGLE backend includes viewer force alias"
Assert-Contains $Validator "'requested_angle_backend'" "requested ANGLE backend validation"
Assert-Contains $Runner "result\.browser_flags\s*=\s*browserArgs" "effective browser flag metadata"
Assert-Contains $Runner "result\.browser_extra_flags\s*=\s*args\.browserFlag" "pass-through browser extra flag metadata"
Assert-Contains $Validator "validateOptionalStringArray\(data,\s*'browser_flags',\s*errors\)" "browser_flags array validation"
Assert-Contains $Validator "validateOptionalStringArray\(data,\s*'browser_extra_flags',\s*errors\)" "browser_extra_flags array validation"
Assert-Contains $Validator "\$\{key\} must be an array" "optional flag array validation helper"
Assert-Contains $Validator "\$\{key\}\[\$\{index\}\] must be a string" "optional flag element validation helper"
Assert-Contains $Runner "webGpuBlobCacheMetadata\(args,\s*viewerUrl\)" "benchmark runner computes WebGPU blob-cache launch metadata"
Assert-Contains $Runner "assertWebGpuBlobCacheExperimentEligible\(launchMetadata,\s*args\)" "benchmark runner rejects cache-specific WebGPU experiments when cache is unavailable"
Assert-Contains $Runner "webgpu_blob_cache_expected_available" "benchmark runner records expected WebGPU blob-cache availability"
Assert-Contains $Runner "viewer_url_scheme" "benchmark runner records viewer URL scheme for cache eligibility"
Assert-Contains $TraceRunner "webGpuBlobCacheMetadata\(args,\s*viewerUrl\)" "trace runner computes WebGPU blob-cache launch metadata"
Assert-Contains $TraceRunner "assertWebGpuBlobCacheExperimentEligible\(launchMetadata,\s*args\)" "trace runner rejects cache-specific WebGPU experiments when cache is unavailable"
Assert-Contains $TraceRunner "webgpu_blob_cache_expected_available" "trace runner records expected WebGPU blob-cache availability"
Assert-Contains $Validator "'webgpu_blob_cache_expected_available'" "metric validator recognizes WebGPU blob-cache availability metadata"
Assert-Contains $Validator "'webgpu_blob_cache_hash_validation_disabled'" "metric validator recognizes WebGPU blob-cache hash-validation metadata"
Assert-Contains $Validator "'viewer_url_scheme'" "metric validator recognizes viewer URL scheme metadata"
Assert-Contains $TraceRunner "browser_flags:\s*browserArgs" "trace sidecar effective browser flag metadata"
Assert-Contains $TraceRunner "browser_extra_flags:\s*args\.browserFlag" "trace sidecar browser extra flag metadata"
Assert-Contains $TraceValidator "validateOptionalStringArray\(errors,\s*data,\s*'browser_flags',\s*label\)" "trace browser_flags array validation"
Assert-Contains $TraceValidator "validateOptionalStringArray\(errors,\s*data,\s*'browser_extra_flags',\s*label\)" "trace browser_extra_flags array validation"
Assert-Contains $SuiteValidator "--requiredBrowserFlag" "suite required effective browser flag option"
Assert-Contains $SuiteValidator "browser_flags must include" "suite required effective browser flag validation"
Assert-Contains $TraceValidator "--requiredBrowserFlag" "trace required effective browser flag option"
Assert-Contains $TraceValidator "browser_flags must include" "trace required effective browser flag validation"
Assert-Contains $Runner "assertTrustedViewerExperimentGates\(args\)" "benchmark runner trusted experiment gate invocation"
Assert-Contains $Runner "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" "benchmark runner trusted experiment gate failure"
Assert-Contains $Runner "--enable-dawn-features" "benchmark runner gates unsafe Dawn browser flags"
Assert-Contains $Runner "--use-webgpu-adapter" "benchmark runner gates unsafe WebGPU adapter browser flags"
Assert-Contains $Runner "--enable-features" "benchmark runner gates unsafe Chromium feature browser flags"
Assert-Contains $Runner "--disable-features" "benchmark runner gates unsafe Chromium feature disable browser flags"
Assert-Contains $Runner "--enable-gpu-memory-buffer-compositor-resources" "benchmark runner gates unsafe compositor GPU-memory-buffer browser flags"
Assert-Contains $Runner "--ui-enable-zero-copy" "benchmark runner gates unsafe UI zero-copy browser flags"
Assert-Contains $Runner "--enable-gpu-rasterization" "benchmark runner gates unsafe GPU rasterization browser flags"
Assert-Contains $Runner "--disable-frame-rate-limit" "benchmark runner gates unsafe frame-rate-limit browser flags"
Assert-Contains $Runner "--disable-gpu-vsync" "benchmark runner gates unsafe GPU-vsync browser flags"
Assert-Contains $TraceRunner "assertTrustedViewerExperimentGates\(args\)" "trace runner trusted experiment gate invocation"
Assert-Contains $TraceRunner "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" "trace runner trusted experiment gate failure"
Assert-Contains $TraceRunner "--enable-dawn-features" "trace runner gates unsafe Dawn browser flags"
Assert-Contains $TraceRunner "--use-webgpu-adapter" "trace runner gates unsafe WebGPU adapter browser flags"
Assert-Contains $TraceRunner "--enable-features" "trace runner gates unsafe Chromium feature browser flags"
Assert-Contains $TraceRunner "--disable-features" "trace runner gates unsafe Chromium feature disable browser flags"
Assert-Contains $TraceRunner "--enable-gpu-memory-buffer-compositor-resources" "trace runner gates unsafe compositor GPU-memory-buffer browser flags"
Assert-Contains $TraceRunner "--ui-enable-zero-copy" "trace runner gates unsafe UI zero-copy browser flags"
Assert-Contains $TraceRunner "--enable-gpu-rasterization" "trace runner gates unsafe GPU rasterization browser flags"
Assert-Contains $TraceRunner "--disable-frame-rate-limit" "trace runner gates unsafe frame-rate-limit browser flags"
Assert-Contains $TraceRunner "--disable-gpu-vsync" "trace runner gates unsafe GPU-vsync browser flags"

Assert-Contains $Runner "webgpuBundleMode" "benchmark runner parses and forwards WebGPU BundleGroup scene mode"
Assert-Contains $TraceRunner "webgpuBundleMode" "trace runner parses and forwards WebGPU BundleGroup scene mode"
Assert-Contains $Validator "'webgpu_bundle_mode'" "metric validator recognizes WebGPU BundleGroup mode metadata"
Assert-Contains $Validator "'webgpu_bundle_groups'" "metric validator recognizes WebGPU BundleGroup count metadata"
Assert-Contains $Runner "commandEncoderInstrumentation" "benchmark runner parses and forwards WebGPU command-encoder instrumentation"
Assert-Contains $TraceRunner "commandEncoderInstrumentation" "trace runner parses and forwards WebGPU command-encoder instrumentation"
Assert-Contains $Validator "'webgpu_queue_write_texture_common_layout_count'" "metric validator recognizes WebGPU writeTexture descriptor-shape attribution"
Assert-Contains $Validator "'webgpu_queue_copy_external_image_common_origin_count'" "metric validator recognizes WebGPU copyExternalImage common-origin attribution"
Assert-Contains $Validator "'webgpu_queue_copy_external_image_explicit_common_origin_count'" "metric validator recognizes WebGPU copyExternalImage explicit common-origin attribution"
Assert-Contains $Validator "'webgpu_queue_copy_external_image_full_source_count'" "metric validator recognizes WebGPU copyExternalImage descriptor-shape attribution"
Assert-Contains $Validator "'webgpu_command_encoder_instrumentation_enabled'" "metric validator recognizes WebGPU command-encoder instrumentation state"
Assert-Contains $Validator "'webgpu_command_encoder_render_pass_clear_value_dict_count'" "metric validator recognizes WebGPU command-encoder render-pass descriptor attribution"
Assert-Contains $Validator "'webgpu_command_encoder_copy_texture_to_buffer_count'" "metric validator recognizes WebGPU command-encoder copy metric"
Assert-Contains $SuiteValidator "command-encoder instrumentation attribution" "suite validator rejects command-encoder attribution from clean evidence"
Assert-Contains $Validator "'webgpu_pipeline_descriptor_render_stack_vertex_buffer_eligible_count'" "metric validator recognizes WebGPU pipeline descriptor fast-path attribution"
Assert-Contains $Validator "'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count'" "metric validator recognizes measured WebGPU pipeline descriptor attribution"
Assert-Contains $Runner "bufferStateInstrumentation" "benchmark runner parses and forwards WebGPU buffer-state instrumentation"
Assert-Contains $TraceRunner "bufferStateInstrumentation" "trace runner parses and forwards WebGPU buffer-state instrumentation"
Assert-Contains $Validator "'webgpu_buffer_state_instrumentation_enabled'" "metric validator recognizes WebGPU buffer-state instrumentation state"
Assert-Contains $Validator "'webgpu_buffer_state_set_redundant_count'" "metric validator recognizes WebGPU redundant buffer-state metric"
Assert-Contains $SuiteValidator "buffer-state instrumentation attribution" "suite validator rejects buffer-state attribution from clean evidence"
Assert-Contains $Runner "renderStateInstrumentation" "benchmark runner parses and forwards WebGPU render-state instrumentation"
Assert-Contains $TraceRunner "renderStateInstrumentation" "trace runner parses and forwards WebGPU render-state instrumentation"
Assert-Contains $Validator "'webgpu_render_state_instrumentation_enabled'" "metric validator recognizes WebGPU render-state instrumentation state"
Assert-Contains $Validator "'webgpu_render_state_set_redundant_count'" "metric validator recognizes WebGPU redundant render-state metric"
Assert-Contains $SuiteValidator "render-state instrumentation attribution" "suite validator rejects render-state attribution from clean evidence"
Assert-Contains $Runner "immediateInstrumentation" "benchmark runner parses and forwards WebGPU immediate instrumentation"
Assert-Contains $TraceRunner "immediateInstrumentation" "trace runner parses and forwards WebGPU immediate instrumentation"
Assert-Contains $Validator "'webgpu_immediate_instrumentation_enabled'" "metric validator recognizes WebGPU immediate instrumentation state"
Assert-Contains $Validator "'webgpu_immediate_set_full_span_count'" "metric validator recognizes WebGPU immediate full-span metric"
Assert-Contains $SuiteValidator "immediate instrumentation attribution" "suite validator rejects immediate attribution from clean evidence"

function Assert-NodeFailsWith {
  param(
    [string]$ScriptPath,
    [string[]]$Arguments,
    [string]$Pattern,
    [string]$Description
  )

  $ProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $ProcessInfo.FileName = "node"
  $ProcessInfo.Arguments = (@($ScriptPath) + $Arguments | ForEach-Object {
    $Text = [string]$_
    '"' + ($Text -replace '"', '\"') + '"'
  }) -join " "
  $ProcessInfo.RedirectStandardOutput = $true
  $ProcessInfo.RedirectStandardError = $true
  $ProcessInfo.UseShellExecute = $false
  $ProcessInfo.CreateNoWindow = $true

  $Process = [System.Diagnostics.Process]::new()
  $Process.StartInfo = $ProcessInfo
  try {
    if (-not $Process.Start()) {
      throw "Unable to start node for $Description."
    }
    $Stdout = $Process.StandardOutput.ReadToEnd()
    $Stderr = $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()
    if ($Process.ExitCode -eq 0) {
      throw "Expected node command to fail for $Description."
    }
    $Text = "$Stdout`n$Stderr"
  } finally {
    $Process.Dispose()
  }
  Assert-Contains $Text $Pattern $Description
}

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerAggressiveGpu") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects unsafe viewer flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--profileCacheKey", "warm-webgpu") `
  "--profileCacheKey requires --userDataDir" `
  "benchmark runner rejects profile cache keys without an explicit profile"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--webgpuBundleMode", "static") `
  "--webgpuBundleMode is only supported for --renderer webgpu" `
  "benchmark runner rejects WebGPU BundleGroup scene mode outside WebGPU"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--userDataDir", (Join-Path $Root "outside-profile"), "--profileCacheKey", "warm-webgpu") `
  "--userDataDir must resolve under" `
  "benchmark runner rejects explicit profiles outside benchmark tmp"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--complexity", "0") `
  "--complexity must be a positive finite number" `
  "benchmark runner rejects zero complexity before browser launch"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--prerenderFrames", "1.5") `
  "--prerenderFrames must be a non-negative integer" `
  "benchmark runner rejects fractional prerender frame counts before browser launch"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgpu", "--pipelineQuietFrames", "4", "--pipelineQuietMaxFrames", "2") `
  "--pipelineQuietMaxFrames must be greater than or equal to --pipelineQuietFrames" `
  "benchmark runner rejects pipeline-quiet max frames below requested quiet window"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerAggressiveGpu") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects unsafe viewer flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerRelaxedWebglValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects relaxed WebGL validation without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--duration", "0") `
  "--duration must be a positive finite number" `
  "trace runner rejects zero duration before browser launch"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--startDelayMs", "not-a-number") `
  "--startDelayMs must be a non-negative finite number" `
  "trace runner rejects non-numeric start delay before browser launch"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgpu", "--pipelineQuietFrames", "3", "--pipelineQuietMaxFrames", "1") `
  "--pipelineQuietMaxFrames must be greater than or equal to --pipelineQuietFrames" `
  "trace runner rejects pipeline-quiet max frames below requested quiet window"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--commandEncoderInstrumentation") `
  "--commandEncoderInstrumentation is only supported for --renderer webgpu" `
  "benchmark runner rejects WebGPU command-encoder attribution for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--commandEncoderInstrumentation") `
  "--commandEncoderInstrumentation is only supported for --renderer webgpu" `
  "trace runner rejects WebGPU command-encoder attribution for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--renderStateInstrumentation") `
  "--renderStateInstrumentation is only supported for --renderer webgpu" `
  "benchmark runner rejects WebGPU render-state attribution for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--renderStateInstrumentation") `
  "--renderStateInstrumentation is only supported for --renderer webgpu" `
  "trace runner rejects WebGPU render-state attribution for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--immediateInstrumentation") `
  "--immediateInstrumentation is only supported for --renderer webgpu" `
  "benchmark runner rejects WebGPU immediate attribution for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--immediateInstrumentation") `
  "--immediateInstrumentation is only supported for --renderer webgpu" `
  "trace runner rejects WebGPU immediate attribution for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerZeroCopy") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects zero-copy without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--browser-flag", "--enable-dawn-features=skip_validation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects unsafe Dawn browser flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--browser-flag", "--enable-gpu-memory-buffer-compositor-resources") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects unsafe compositor GPU-memory-buffer flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--browser-flag", "--disable-frame-rate-limit") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects unsafe frame-rate-limit flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerDeferWebgpuQueueFlush") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU queue-flush deferral without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerDeferWebgpuPipelineFlush") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU pipeline-flush deferral without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerDeferWebgpuSubmitFlush") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU submit-flush deferral without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCanvasTextureValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU canvas texture validation skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCanvasMemoryAccounting") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU canvas memory-accounting skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCopyExternalImageColorConversion") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU copyExternalImage color-conversion setup skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU copyExternalImage color-space validation skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCopyExternalImageDestValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU copyExternalImage destination validation skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCopyExternalImageSourceValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU copyExternalImage source validation skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerRejectWebgpuCpuTextureFallback") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU CPU texture fallback rejection without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuUseCounters") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU use-counter skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerCacheWebgpuBindGroupLayouts") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU bind-group-layout cache without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCommandLabels") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU command-label skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuResourceLabels") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU resource-label skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuRedundantPipelineSets") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU redundant setPipeline skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuRedundantBindGroupSets") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU redundant setBindGroup skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuRedundantRenderStateSets") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU redundant render-state skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuResourceLabels") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU resource-label skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuRedundantPipelineSets") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU redundant setPipeline skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuRedundantBindGroupSets") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU redundant setBindGroup skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuRedundantRenderStateSets") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU redundant render-state skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerTraceWebgpuQueue") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects WebGPU queue trace diagnostics without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--browser-flag", "--enable-features=RemoveGPULegacyIPC") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects unsafe Chromium feature flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--browser-flag", "--use-webgpu-adapter=d3d11") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects unsafe WebGPU adapter flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--browser-flag", "--disable-features=WebGPUEnableRangeAnalysisForRobustness") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects unsafe Chromium feature-disable flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerDeferWebgpuQueueFlush") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU queue-flush deferral without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerDeferWebgpuPipelineFlush") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU pipeline-flush deferral without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerDeferWebgpuSubmitFlush") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU submit-flush deferral without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCanvasTextureValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU canvas texture validation skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCanvasMemoryAccounting") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU canvas memory-accounting skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCopyExternalImageColorConversion") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU copyExternalImage color-conversion setup skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU copyExternalImage color-space validation skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCopyExternalImageDestValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU copyExternalImage destination validation skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCopyExternalImageSourceValidation") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU copyExternalImage source validation skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerRejectWebgpuCpuTextureFallback") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU CPU texture fallback rejection without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuUseCounters") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU use-counter skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerCacheWebgpuBindGroupLayouts") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU bind-group-layout cache without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerSkipWebgpuCommandLabels") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU command-label skip without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerTraceWebgpuQueue") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects WebGPU queue trace diagnostics without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--browser-flag", "--ui-enable-zero-copy") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects unsafe UI zero-copy flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--browser-flag", "--disable-gpu-vsync") `
  "Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects unsafe GPU-vsync flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgpu", "--viewerMode", "--viewerTrustedContent", "--viewerZeroCopy") `
  "viewerZeroCopy is currently restricted to --renderer webgl2" `
  "benchmark runner rejects zero-copy for WebGPU"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgpu", "--viewerMode", "--viewerTrustedContent", "--viewerZeroCopy") `
  "viewerZeroCopy is currently restricted to --renderer webgl2" `
  "trace runner rejects zero-copy for WebGPU"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerDeferWebgpuQueueFlush") `
  "viewerDeferWebgpuQueueFlush is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU queue-flush deferral for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerDeferWebgpuPipelineFlush") `
  "viewerDeferWebgpuPipelineFlush is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU pipeline-flush deferral for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerDeferWebgpuQueueFlush") `
  "viewerDeferWebgpuQueueFlush is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU queue-flush deferral for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerDeferWebgpuPipelineFlush") `
  "viewerDeferWebgpuPipelineFlush is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU pipeline-flush deferral for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerDeferWebgpuSubmitFlush") `
  "viewerDeferWebgpuSubmitFlush is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU submit-flush deferral for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerDeferWebgpuSubmitFlush") `
  "viewerDeferWebgpuSubmitFlush is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU submit-flush deferral for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCanvasTextureValidation") `
  "viewerSkipWebgpuCanvasTextureValidation is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU canvas texture validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCanvasTextureValidation") `
  "viewerSkipWebgpuCanvasTextureValidation is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU canvas texture validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCanvasMemoryAccounting") `
  "viewerSkipWebgpuCanvasMemoryAccounting is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU canvas memory-accounting skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCanvasMemoryAccounting") `
  "viewerSkipWebgpuCanvasMemoryAccounting is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU canvas memory-accounting skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageColorConversion") `
  "viewerSkipWebgpuCopyExternalImageColorConversion is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU copyExternalImage color-conversion setup skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageColorConversion") `
  "viewerSkipWebgpuCopyExternalImageColorConversion is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU copyExternalImage color-conversion setup skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation") `
  "viewerSkipWebgpuCopyExternalImageColorSpaceValidation is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU copyExternalImage color-space validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation") `
  "viewerSkipWebgpuCopyExternalImageColorSpaceValidation is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU copyExternalImage color-space validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageDestValidation") `
  "viewerSkipWebgpuCopyExternalImageDestValidation is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU copyExternalImage destination validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageDestValidation") `
  "viewerSkipWebgpuCopyExternalImageDestValidation is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU copyExternalImage destination validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageSourceValidation") `
  "viewerSkipWebgpuCopyExternalImageSourceValidation is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU copyExternalImage source validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageSourceValidation") `
  "viewerSkipWebgpuCopyExternalImageSourceValidation is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU copyExternalImage source validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageCopySizeValidation") `
  "viewerSkipWebgpuCopyExternalImageCopySizeValidation is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU copyExternalImage copy-size validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageCopySizeValidation") `
  "viewerSkipWebgpuCopyExternalImageCopySizeValidation is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU copyExternalImage copy-size validation skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerRejectWebgpuCpuTextureFallback") `
  "viewerRejectWebgpuCpuTextureFallback is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU CPU texture fallback rejection for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuUseCounters") `
  "viewerSkipWebgpuUseCounters is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU use-counter skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerCacheWebgpuBindGroupLayouts") `
  "viewerCacheWebgpuBindGroupLayouts is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU bind-group-layout cache for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCommandLabels") `
  "viewerSkipWebgpuCommandLabels is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU command-label skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuResourceLabels") `
  "viewerSkipWebgpuResourceLabels is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU resource-label skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuRedundantPipelineSets") `
  "viewerSkipWebgpuRedundantPipelineSets is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU redundant setPipeline skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuRedundantBindGroupSets") `
  "viewerSkipWebgpuRedundantBindGroupSets is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU redundant setBindGroup skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuRedundantRenderStateSets") `
  "viewerSkipWebgpuRedundantRenderStateSets is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU redundant render-state skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerRejectWebgpuCpuTextureFallback") `
  "viewerRejectWebgpuCpuTextureFallback is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU CPU texture fallback rejection for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuUseCounters") `
  "viewerSkipWebgpuUseCounters is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU use-counter skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerCacheWebgpuBindGroupLayouts") `
  "viewerCacheWebgpuBindGroupLayouts is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU bind-group-layout cache for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCommandLabels") `
  "viewerSkipWebgpuCommandLabels is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU command-label skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuResourceLabels") `
  "viewerSkipWebgpuResourceLabels is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU resource-label skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuRedundantPipelineSets") `
  "viewerSkipWebgpuRedundantPipelineSets is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU redundant setPipeline skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuRedundantBindGroupSets") `
  "viewerSkipWebgpuRedundantBindGroupSets is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU redundant setBindGroup skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuRedundantRenderStateSets") `
  "viewerSkipWebgpuRedundantRenderStateSets is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU redundant render-state skip for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerTraceWebgpuQueue") `
  "viewerTraceWebgpuQueue is only valid with --renderer webgpu" `
  "benchmark runner rejects WebGPU queue trace diagnostics for WebGL2"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--renderer", "webgl2", "--viewerMode", "--viewerTrustedContent", "--viewerTraceWebgpuQueue") `
  "viewerTraceWebgpuQueue is only valid with --renderer webgpu" `
  "trace runner rejects WebGPU queue trace diagnostics for WebGL2"

$RunnerAsBrowser = Join-Path $Root "scripts\run_benchmark.mjs"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", $RunnerAsBrowser, "--renderer", "webgpu", "--viewerMode", "--viewerTrustedContent", "--viewerFileMode", "--browser-flag", "--disable-dawn-features=blob_cache_hash_validation") `
  "WebGPU blob-cache hash-validation experiments require a cache-eligible local HTTP\(S\) viewer origin" `
  "benchmark runner rejects WebGPU blob-cache hash-validation experiment in file mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", $RunnerAsBrowser, "--renderer", "webgpu", "--viewerMode", "--viewerTrustedContent", "--browser-flag", "--enable-dawn-features=disable_blob_cache", "--browser-flag", "--disable-dawn-features=blob_cache_hash_validation") `
  "Current cache eligibility: dawn-disable_blob_cache-toggle" `
  "benchmark runner rejects WebGPU blob-cache hash-validation experiment when Dawn blob cache is explicitly disabled"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", $RunnerAsBrowser, "--renderer", "webgpu", "--viewerMode", "--viewerTrustedContent", "--browser-flag", "--enable-dawn-features=disable_blob_cache", "--browser-flag", "--disable-dawn-features=blob_cache_hash_validation") `
  "Current cache eligibility: dawn-disable_blob_cache-toggle" `
  "trace runner rejects WebGPU blob-cache hash-validation trace when Dawn blob cache is explicitly disabled"

Write-Host "Benchmark runner records, validates, and gates trusted viewer/browser flag metadata."

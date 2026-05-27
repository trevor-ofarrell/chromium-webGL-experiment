[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$DocPath = Join-Path $Root "docs\trusted_content_flags.md"

if (-not (Test-Path -LiteralPath $DocPath)) {
  throw "Missing docs\trusted_content_flags.md."
}

$Text = Get-Content -LiteralPath $DocPath -Raw
foreach ($RequiredPhrase in @(
    'Unsafe behavior is gated by both `--viewer-app-url` and `--viewer-trusted-content`',
    'keeps reserved experiment gates as no-ops',
    'maps the relaxed WebGL validation experiment to Chromium''s pass-through command decoder switch',
    'Each aggressive run must be compared against stock Chromium and the fork default profile from the same Chromium revision',
    'Chromium WebGPU/Dawn launch flags are also treated as trusted experiments',
    'reject `--use-webgpu-adapter`, `--enable-dawn-features`, `--disable-dawn-features`, `--enable-features`, and `--disable-features` unless both `--viewerMode` and `--viewerTrustedContent` are present',
    'Chromium feature probes through `-Renderer webgpu -IncludeWebGpuChromiumFeatureExperiments`',
    'upload/command-buffer probes through `-Renderer webgpu -IncludeWebGpuUploadExperiments`',
    'normal benchmark runs keep this off so source trace instrumentation is not paid on the default performance path',
    'records the exact `browser_flags` and per-experiment `required_browser_flags`',
    'WebGPU trusted matrix runs can also use `-DisableGpuTiming`',
    'Raw compositor GPU-resource browser flags are also trusted-only',
    'reject `--enable-gpu-memory-buffer-compositor-resources`, `--ui-enable-zero-copy`, and `--enable-gpu-rasterization` unless both `--viewerMode` and `--viewerTrustedContent` are present'
  )) {
  if ($Text -notmatch [regex]::Escape($RequiredPhrase)) {
    throw "Trusted-content flag doc is missing required guardrail text: $RequiredPhrase"
  }
}

function Split-MarkdownRow {
  param([string]$Line)

  $Trimmed = $Line.Trim()
  if (-not $Trimmed.StartsWith("|") -or -not $Trimmed.EndsWith("|")) {
    throw "Invalid markdown table row: $Line"
  }

  return @($Trimmed.Trim("|").Split("|") | ForEach-Object { $_.Trim() })
}

$TableLines = @((Get-Content -LiteralPath $DocPath) | Where-Object { $_.Trim().StartsWith("|") })
if ($TableLines.Count -lt 3) {
  throw "Trusted-content flag doc does not contain the flag table."
}

$Header = Split-MarkdownRow $TableLines[0]
foreach ($Column in @("Viewer switch", "Current behavior", "Risk", "Status")) {
  if ($Header -notcontains $Column) {
    throw "Trusted-content flag table is missing required column '$Column'."
  }
}

$Rows = @()
foreach ($Line in @($TableLines | Select-Object -Skip 2)) {
  $Cells = Split-MarkdownRow $Line
  if ($Cells.Count -ne $Header.Count) {
    throw "Trusted-content flag table has a row with $($Cells.Count) cells; expected $($Header.Count): $Line"
  }
  $Row = [ordered]@{}
  for ($Index = 0; $Index -lt $Header.Count; $Index++) {
    $Row[$Header[$Index]] = $Cells[$Index]
  }
  $Rows += [pscustomobject]$Row
}

$RequiredSwitches = @(
  "--viewer-app-url",
  "--viewer-block-external-navigation",
  "--viewer-trusted-content",
  "--viewer-aggressive-gpu",
  "--viewer-in-process-gpu",
  "--viewer-single-process",
  "--viewer-force-angle-backend",
  "--viewer-relaxed-webgl-validation",
  "--viewer-zero-copy",
  "--viewer-disable-unneeded-blink-features",
  "--viewer-direct-gpu-presentation",
  "--viewer-defer-webgpu-pipeline-flush",
  "--viewer-cache-webgpu-bind-group-layouts",
  "--viewer-skip-webgpu-command-labels",
  "--viewer-skip-webgpu-resource-labels",
  "--viewer-skip-webgpu-shader-source-null-check",
  "--viewer-skip-webgpu-shader-memory-accounting",
  "--viewer-defer-webgpu-queue-flush",
  "--viewer-defer-webgpu-submit-flush",
  "--viewer-skip-webgpu-canvas-texture-validation",
  "--viewer-skip-webgpu-canvas-memory-accounting",
  "--viewer-skip-webgpu-copy-external-image-color-conversion",
  "--viewer-skip-webgpu-copy-external-image-color-space-validation",
  "--viewer-skip-webgpu-copy-external-image-dest-validation",
  "--viewer-skip-webgpu-copy-external-image-source-validation",
  "--viewer-skip-webgpu-copy-external-image-copy-size-validation",
  "--viewer-skip-webgpu-write-texture-layout-validation",
  "--viewer-reject-webgpu-cpu-texture-fallback",
  "--viewer-skip-webgpu-use-counters",
  "--viewer-skip-webgpu-redundant-pipeline-sets",
  "--viewer-skip-webgpu-redundant-bind-group-sets",
  "--viewer-skip-webgpu-redundant-buffer-sets",
  "--viewer-skip-webgpu-redundant-render-state-sets",
  "--viewer-trace-webgpu-queue"
)

foreach ($Switch in $RequiredSwitches) {
  $Matches = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape($Switch) })
  if ($Matches.Count -ne 1) {
    throw "Trusted-content flag table does not contain exactly one row for $Switch."
  }
  $Row = $Matches[0]
  foreach ($Column in @("Current behavior", "Risk", "Status")) {
    if ([string]::IsNullOrWhiteSpace([string]$Row.$Column)) {
      throw "Trusted-content flag row $Switch has an empty '$Column' cell."
    }
  }
  if ($Row.Risk -notmatch "Low|Medium|High|Very high") {
    throw "Trusted-content flag row $Switch has an unclassified risk: $($Row.Risk)"
  }
}

foreach ($UnsafeSwitch in @(
    "--viewer-trusted-content",
    "--viewer-aggressive-gpu",
    "--viewer-in-process-gpu",
    "--viewer-single-process",
    "--viewer-force-angle-backend",
    "--viewer-relaxed-webgl-validation",
    "--viewer-zero-copy",
    "--viewer-disable-unneeded-blink-features",
    "--viewer-direct-gpu-presentation",
    "--viewer-defer-webgpu-pipeline-flush",
    "--viewer-cache-webgpu-bind-group-layouts",
    "--viewer-skip-webgpu-command-labels",
    "--viewer-skip-webgpu-resource-labels",
    "--viewer-skip-webgpu-shader-source-null-check",
    "--viewer-skip-webgpu-shader-memory-accounting",
    "--viewer-defer-webgpu-queue-flush",
    "--viewer-defer-webgpu-submit-flush",
    "--viewer-skip-webgpu-canvas-texture-validation",
    "--viewer-skip-webgpu-canvas-memory-accounting",
    "--viewer-skip-webgpu-copy-external-image-color-conversion",
    "--viewer-skip-webgpu-copy-external-image-color-space-validation",
    "--viewer-skip-webgpu-copy-external-image-dest-validation",
    "--viewer-skip-webgpu-copy-external-image-source-validation",
    "--viewer-skip-webgpu-copy-external-image-copy-size-validation",
    "--viewer-skip-webgpu-write-texture-layout-validation",
    "--viewer-reject-webgpu-cpu-texture-fallback",
    "--viewer-skip-webgpu-use-counters",
    "--viewer-skip-webgpu-redundant-pipeline-sets",
    "--viewer-skip-webgpu-redundant-bind-group-sets",
    "--viewer-skip-webgpu-redundant-buffer-sets",
    "--viewer-skip-webgpu-redundant-render-state-sets",
    "--viewer-trace-webgpu-queue"
  )) {
  $Row = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape($UnsafeSwitch) })[0]
  if ($Row.Risk -notmatch "Medium|High|Very high") {
    throw "Unsafe trusted-content flag $UnsafeSwitch must document at least medium risk."
  }
}

foreach ($ReservedSwitch in @(
    "--viewer-disable-unneeded-blink-features",
    "--viewer-direct-gpu-presentation"
  )) {
  $Row = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape($ReservedSwitch) })[0]
  if ($Row."Current behavior" -notmatch "Reserved gate only" -or
      $Row.Status -notmatch "Reserved no-op gate") {
    throw "Reserved trusted-content flag $ReservedSwitch must remain documented as a no-op gate."
  }
}

$RelaxedWebglRow = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape("--viewer-relaxed-webgl-validation") })[0]
if ($RelaxedWebglRow."Current behavior" -notmatch [regex]::Escape("--use-cmd-decoder=passthrough") -or
    $RelaxedWebglRow.Status -notmatch "benchmark evidence") {
  throw "Trusted-content flag --viewer-relaxed-webgl-validation must document the pass-through command decoder alias and benchmark evidence status."
}

$ZeroCopyRow = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape("--viewer-zero-copy") })[0]
if ($ZeroCopyRow."Current behavior" -notmatch [regex]::Escape("--enable-zero-copy") -or
    $ZeroCopyRow."Current behavior" -notmatch "WebGL2" -or
    $ZeroCopyRow.Status -notmatch "speed-candidate") {
  throw "Trusted-content flag --viewer-zero-copy must document the zero-copy alias, WebGL2 gating, and candidate status."
}

$CommandLabelRow = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape("--viewer-skip-webgpu-command-labels") })[0]
if ($CommandLabelRow."Current behavior" -notmatch "clears JS-visible Blink wrapper labels" -or
    $CommandLabelRow."Current behavior" -match "preserving Blink wrapper labels" -or
    $CommandLabelRow.Risk -notmatch "JS-visible command-object labels") {
  throw "Trusted-content flag --viewer-skip-webgpu-command-labels must document command-object wrapper-label clearing and its JS-visible risk."
}

foreach ($MetadataField in @(
    "viewer_trusted_content",
    "viewer_block_external_navigation",
    "viewer_aggressive_gpu",
    "viewer_relaxed_webgl_validation",
    "viewer_zero_copy",
    "viewer_in_process_gpu",
    "viewer_single_process",
    "viewer_force_angle_backend",
    "viewer_disable_unneeded_blink_features",
    "viewer_direct_gpu_presentation",
    "viewer_defer_webgpu_pipeline_flush",
    "viewer_cache_webgpu_bind_group_layouts",
    "viewer_skip_webgpu_command_labels",
    "viewer_skip_webgpu_resource_labels",
    "viewer_skip_webgpu_shader_source_null_check",
    "viewer_skip_webgpu_shader_memory_accounting",
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
    "viewer_skip_webgpu_redundant_pipeline_sets",
    "viewer_skip_webgpu_redundant_bind_group_sets",
    "viewer_skip_webgpu_redundant_buffer_sets",
    "viewer_skip_webgpu_redundant_render_state_sets",
    "viewer_trace_webgpu_queue",
    "requested_angle_backend",
    "gpu_timing_enabled",
    "browser_flags",
    "browser_extra_flags",
    "required_browser_flags"
  )) {
  if ($Text -notmatch [regex]::Escape($MetadataField)) {
    throw "Trusted-content flag doc does not list benchmark metadata field $MetadataField."
  }
}

Write-Host "Trusted-content flag documentation covers gating, risk, pass-through decoder aliasing, reserved no-op gates, and benchmark metadata for $($RequiredSwitches.Count) viewer switches."

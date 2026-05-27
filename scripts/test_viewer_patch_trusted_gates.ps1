[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
$WebGpuPatchPath = Join-Path $Root "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"

if (-not (Test-Path $PatchPath)) {
  throw "Viewer patch not found: $PatchPath"
}
if (-not (Test-Path $WebGpuPatchPath)) {
  throw "WebGPU viewer patch not found: $WebGpuPatchPath"
}

$PatchText = Get-Content -LiteralPath $PatchPath -Raw
$AddedCode = ((Get-Content -LiteralPath $PatchPath) |
  Where-Object { $_.StartsWith("+") -and -not $_.StartsWith("+++") } |
  ForEach-Object { $_.Substring(1) }) -join "`n"
$WebGpuPatchText = Get-Content -LiteralPath $WebGpuPatchPath -Raw
$WebGpuAddedCode = ((Get-Content -LiteralPath $WebGpuPatchPath) |
  Where-Object { $_.StartsWith("+") -and -not $_.StartsWith("+++") } |
  ForEach-Object { $_.Substring(1) }) -join "`n"
$WebGpuQueueSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_queue.cc"
$WebGpuQueueSourceText = if (Test-Path -LiteralPath $WebGpuQueueSourcePath) {
  Get-Content -LiteralPath $WebGpuQueueSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuCommandEncoderSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_command_encoder.cc"
$WebGpuCommandEncoderSourceText = if (Test-Path -LiteralPath $WebGpuCommandEncoderSourcePath) {
  Get-Content -LiteralPath $WebGpuCommandEncoderSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuRenderBundleSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_render_bundle_encoder.cc"
$WebGpuRenderBundleSourceText = if (Test-Path -LiteralPath $WebGpuRenderBundleSourcePath) {
  Get-Content -LiteralPath $WebGpuRenderBundleSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuRenderPassSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_render_pass_encoder.cc"
$WebGpuRenderPassSourceText = if (Test-Path -LiteralPath $WebGpuRenderPassSourcePath) {
  Get-Content -LiteralPath $WebGpuRenderPassSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuComputePassSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_compute_pass_encoder.cc"
$WebGpuComputePassSourceText = if (Test-Path -LiteralPath $WebGpuComputePassSourcePath) {
  Get-Content -LiteralPath $WebGpuComputePassSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuProgrammablePassSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_programmable_pass_encoder.cc"
$WebGpuProgrammablePassSourceText = if (Test-Path -LiteralPath $WebGpuProgrammablePassSourcePath) {
  Get-Content -LiteralPath $WebGpuProgrammablePassSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuTextureSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_texture.cc"
$WebGpuTextureSourceText = if (Test-Path -LiteralPath $WebGpuTextureSourcePath) {
  Get-Content -LiteralPath $WebGpuTextureSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuDawnObjectSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\dawn_object.cc"
$WebGpuDawnObjectSourceText = if (Test-Path -LiteralPath $WebGpuDawnObjectSourcePath) {
  Get-Content -LiteralPath $WebGpuDawnObjectSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuShaderModuleSourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_shader_module.cc"
$WebGpuShaderModuleSourceText = if (Test-Path -LiteralPath $WebGpuShaderModuleSourcePath) {
  Get-Content -LiteralPath $WebGpuShaderModuleSourcePath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuRenderPassHeaderPath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_render_pass_encoder.h"
$WebGpuRenderPassHeaderText = if (Test-Path -LiteralPath $WebGpuRenderPassHeaderPath) {
  Get-Content -LiteralPath $WebGpuRenderPassHeaderPath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuCommandEncoderHeaderPath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_command_encoder.h"
$WebGpuCommandEncoderHeaderText = if (Test-Path -LiteralPath $WebGpuCommandEncoderHeaderPath) {
  Get-Content -LiteralPath $WebGpuCommandEncoderHeaderPath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuComputePassHeaderPath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_compute_pass_encoder.h"
$WebGpuComputePassHeaderText = if (Test-Path -LiteralPath $WebGpuComputePassHeaderPath) {
  Get-Content -LiteralPath $WebGpuComputePassHeaderPath -Raw
} else {
  $WebGpuPatchText
}
$WebGpuRenderBundleHeaderPath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\gpu_render_bundle_encoder.h"
$WebGpuRenderBundleHeaderText = if (Test-Path -LiteralPath $WebGpuRenderBundleHeaderPath) {
  Get-Content -LiteralPath $WebGpuRenderBundleHeaderPath -Raw
} else {
  $WebGpuPatchText
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($env:TRACE_VIEWER_PATCH_GATES) {
    Write-Host "checking: $Description"
    Add-Content -LiteralPath (Join-Path $Root "benchmarks\tmp\viewer_patch_gate_trace.log") -Value "checking: $Description"
  }
  if ($Text -notmatch $Pattern) {
    throw "Missing expected trusted-gate evidence: $Description. Pattern: $Pattern"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($env:TRACE_VIEWER_PATCH_GATES) {
    Write-Host "checking absence: $Description"
    Add-Content -LiteralPath (Join-Path $Root "benchmarks\tmp\viewer_patch_gate_trace.log") -Value "checking absence: $Description"
  }
  if ($Text -match $Pattern) {
    throw "Unexpected trusted-gate evidence: $Description. Pattern: $Pattern"
  }
}

function Get-FunctionBody {
  param(
    [string]$Text,
    [string]$FunctionName
  )

  $Start = $Text.IndexOf("void $FunctionName(")
  if ($Start -lt 0) {
    throw "Function not found in patch additions: $FunctionName"
  }

  $BraceStart = $Text.IndexOf("{", $Start)
  if ($BraceStart -lt 0) {
    throw "Opening brace not found for function: $FunctionName"
  }

  $Depth = 0
  for ($Index = $BraceStart; $Index -lt $Text.Length; $Index++) {
    $Char = $Text[$Index]
    if ($Char -eq "{") {
      $Depth += 1
    } elseif ($Char -eq "}") {
      $Depth -= 1
      if ($Depth -eq 0) {
        return $Text.Substring($BraceStart, $Index - $BraceStart + 1)
      }
    }
  }

  throw "Closing brace not found for function: $FunctionName"
}

function Get-TextSection {
  param(
    [string]$Text,
    [string]$StartNeedle,
    [string]$EndNeedle,
    [string]$Description
  )

  $Start = $Text.IndexOf($StartNeedle)
  if ($Start -lt 0) {
    throw "Section start not found: $Description"
  }

  $End = $Text.IndexOf($EndNeedle, $Start)
  if ($End -lt 0) {
    throw "Section end not found: $Description"
  }

  return $Text.Substring($Start, $End - $Start)
}

$TrustedFunction = Get-FunctionBody $AddedCode "ConfigureViewerTrustedContentSwitches"

Assert-Contains `
  $TrustedFunction `
  "if \(!command_line\.HasSwitch\(switches::kViewerAppUrl\)\s*\|\|\s*!command_line\.HasSwitch\(switches::kViewerTrustedContent\)\)\s+return;" `
  "viewer-app-url and trusted-content early return before unsafe aliases"

Assert-Contains `
  $AddedCode `
  "ConfigureViewerTrustedContentSwitches\(command_line\);" `
  "startup invokes trusted-content alias configuration"

$UnsafeNativeSwitches = @(
  "switches::kAllowFileAccessFromFiles",
  "switches::kUseANGLE",
  "switches::kUseCmdDecoder",
  "blink::switches::kEnableZeroCopy",
  "switches::kInProcessGPU",
  "switches::kSingleProcess",
  "switches::kDisableSoftwareRasterizer",
  "switches::kEnableUnsafeWebGPU",
  "switches::kEnableWebGPUDeveloperFeatures",
  "switches::kForceHighPerformanceGPU",
  "switches::kNoDelayForDX12VulkanInfoCollection"
)

foreach ($SwitchPattern in $UnsafeNativeSwitches) {
  Assert-Contains `
    $TrustedFunction `
    ([regex]::Escape($SwitchPattern)) `
    "unsafe alias $SwitchPattern remains inside ConfigureViewerTrustedContentSwitches"

  $OutsideTrustedFunction = $AddedCode.Replace($TrustedFunction, "")
  Assert-NotContains `
    $OutsideTrustedFunction `
    ([regex]::Escape($SwitchPattern)) `
    "unsafe alias $SwitchPattern outside trusted-content configuration"
}

$ViewerGateSwitches = @(
  "kViewerTrustedContent",
  "kViewerAggressiveGpu",
  "kViewerInProcessGpu",
  "kViewerSingleProcess",
  "kViewerForceAngleBackend",
  "kViewerRelaxedWebGLValidation",
  "kViewerZeroCopy",
  "kViewerDisableUnneededBlinkFeatures",
  "kViewerDirectGpuPresentation"
)

foreach ($SwitchName in $ViewerGateSwitches) {
  Assert-Contains `
    $AddedCode `
    "inline constexpr char $SwitchName\[\]" `
    "viewer switch definition $SwitchName"
}

$ReservedNoopGates = @(
  "kViewerDisableUnneededBlinkFeatures",
  "kViewerDirectGpuPresentation"
)
$AddedCodeWithoutDefinitions = $AddedCode -replace "inline constexpr char kViewerDisableUnneededBlinkFeatures\[\]\s*=\s*`n\s*`"viewer-disable-unneeded-blink-features`";", ""
$AddedCodeWithoutDefinitions = $AddedCodeWithoutDefinitions -replace "inline constexpr char kViewerDirectGpuPresentation\[\]\s*=\s*`n\s*`"viewer-direct-gpu-presentation`";", ""

Assert-Contains `
  $TrustedFunction `
  "HasSwitch\(switches::kViewerRelaxedWebGLValidation\)[\s\S]*?AppendSwitchASCIIIfAbsent\(command_line,\s*switches::kUseCmdDecoder,\s*gl::kCmdDecoderPassthroughName\)" `
  "relaxed WebGL validation gate maps to pass-through command decoder inside trusted-content configuration"

Assert-Contains `
  $AddedCode `
  'struct ViewerWebGLExperimentState \{[\s\S]*relaxed_draw_validation' `
  "WebGL relaxed validation source patch stores a cached trusted draw-validation decision"

Assert-Contains `
  $AddedCode `
  'bool IsTrustedViewerApp\(const base::CommandLine\* command_line\) \{[\s\S]*command_line->HasSwitch\(kViewerAppUrlSwitch\)[\s\S]*command_line->HasSwitch\(kViewerTrustedContentSwitch\)' `
  "WebGL relaxed draw-validation bypass requires both viewer-app-url and trusted-content"

Assert-Contains `
  $AddedCode `
  'kViewerRelaxedWebGLValidationSwitch\[\]\s*=[\s\S]{0,120}"viewer-relaxed-webgl-validation";' `
  "WebGL relaxed draw-validation bypass requires the explicit relaxed validation switch"

Assert-Contains `
  $PatchText `
  'ValidateDrawArrays\(const char\* function_name\)[\s\S]*if \(isContextLost\(\)\)[\s\S]*return false;[\s\S]*if \(ShouldRelaxWebGLDrawValidation\(\)\)[\s\S]*return true;[\s\S]*ValidateRenderingState' `
  "WebGL drawArrays validation bypass preserves the context-loss check and skips the remaining Blink draw validation only under the trusted decision"

Assert-Contains `
  $PatchText `
  'ValidateDrawElements\(const char\* function_name,[\s\S]*if \(isContextLost\(\)\)[\s\S]*return false;[\s\S]*if \(ShouldRelaxWebGLDrawValidation\(\)\)[\s\S]*return true;[\s\S]*GL_UNSIGNED_INT' `
  "WebGL drawElements validation bypass preserves the context-loss check and skips the remaining Blink draw validation only under the trusted decision"

Assert-Contains `
  $PatchText `
  'DrawWrapper[\s\S]*if \(!ShouldRelaxWebGLDrawValidation\(\) &&[\s\S]*!bound_vertex_array_object_->IsAllEnabledAttribBufferBound\(\)\)' `
  "WebGL draw wrapper skips enabled-attribute buffer validation only under the trusted relaxed validation decision"

Assert-Contains `
  $TrustedFunction `
  "HasSwitch\(switches::kViewerZeroCopy\)[\s\S]*?AppendSwitchIfAbsent\(command_line,\s*blink::switches::kEnableZeroCopy\)" `
  "zero-copy gate maps to Chromium zero-copy switch inside trusted-content configuration"

foreach ($SwitchName in $ReservedNoopGates) {
  Assert-NotContains `
    $AddedCodeWithoutDefinitions `
    "HasSwitch\(switches::$SwitchName\)|AppendSwitch(?:ASCII)?IfAbsent\(command_line,\s*switches::$SwitchName" `
    "reserved no-op gate $SwitchName has runtime behavior before a measured source experiment"
}

Assert-Contains `
  $PatchText `
  "Unsafe optimizations must\s*`r?`n\+// also require --viewer-app-url and their own explicit switches\." `
  "patch documents viewer-mode and explicit switches for unsafe optimizations"

Assert-Contains `
  $WebGpuAddedCode `
  'constexpr char kViewerAppUrlSwitch\[\] = "viewer-app-url";' `
  "WebGPU source-backed experiment patch defines the viewer app URL gate"

Assert-Contains `
  $WebGpuAddedCode `
  'bool IsTrustedViewerApp\(const base::CommandLine\* command_line\) \{[\s\S]*command_line->HasSwitch\(kViewerAppUrlSwitch\)[\s\S]*command_line->HasSwitch\(kViewerTrustedContentSwitch\)' `
  "WebGPU source-backed experiment patch requires both viewer-app-url and trusted-content"

Assert-Contains `
  $WebGpuPatchText `
  'viewer_webgpu_experiment_switches\.h[\s\S]*kViewerSkipWebGPUResourceLabelsSwitch\[\][\s\S]*"viewer-skip-webgpu-resource-labels"[\s\S]*IsTrustedViewerApp\(command_line\)[\s\S]*ShouldSkipResourceLabels' `
  "WebGPU resource-label skip helper requires viewer-app-url, trusted-content, and an explicit resource-label switch"

Assert-Contains `
  $WebGpuPatchText `
  'viewer_webgpu_experiment_switches\.h[\s\S]*kViewerSkipWebGPUUseCountersSwitch\[\][\s\S]*"viewer-skip-webgpu-use-counters"[\s\S]*IsTrustedViewerApp\(command_line\)[\s\S]*ShouldSkipUseCounters' `
  "WebGPU use-counter skip helper requires viewer-app-url, trusted-content, and an explicit use-counter switch"

Assert-Contains `
  $WebGpuPatchText `
  'viewer_webgpu_experiment_switches\.h[\s\S]*kViewerSkipWebGPUShaderSourceNullCheckSwitch\[\][\s\S]*"viewer-skip-webgpu-shader-source-null-check"[\s\S]*IsTrustedViewerApp\(command_line\)[\s\S]*ShouldSkipShaderSourceNullCheck' `
  "WebGPU shader-source NUL-check skip helper requires viewer-app-url, trusted-content, and an explicit shader-source switch"

Assert-Contains `
  $WebGpuPatchText `
  'viewer_webgpu_experiment_switches\.h[\s\S]*kViewerSkipWebGPUShaderMemoryAccountingSwitch\[\][\s\S]*"viewer-skip-webgpu-shader-memory-accounting"[\s\S]*IsTrustedViewerApp\(command_line\)[\s\S]*ShouldSkipShaderMemoryAccounting' `
  "WebGPU shader memory-accounting skip helper requires viewer-app-url, trusted-content, and an explicit shader-memory switch"

Assert-Contains `
  $WebGpuPatchText `
  'kViewerSkipWebGPURedundantPipelineSetsSwitch\[\]\s*=[\s\S]{0,120}"viewer-skip-webgpu-redundant-pipeline-sets";' `
  "WebGPU redundant setPipeline skip helper requires viewer-app-url, trusted-content, and an explicit redundant-pipeline switch"

Assert-Contains `
  $WebGpuPatchText `
  'kViewerSkipWebGPURedundantBindGroupSetsSwitch\[\]\s*=[\s\S]{0,120}"viewer-skip-webgpu-redundant-bind-group-sets";' `
  "WebGPU redundant setBindGroup skip helper requires viewer-app-url, trusted-content, and an explicit redundant-bind-group switch"

Assert-Contains `
  $WebGpuPatchText `
  'kViewerSkipWebGPURedundantBufferSetsSwitch\[\]\s*=[\s\S]{0,120}"viewer-skip-webgpu-redundant-buffer-sets";' `
  "WebGPU redundant setVertexBuffer/setIndexBuffer skip helper requires viewer-app-url, trusted-content, and an explicit redundant-buffer switch"

Assert-Contains `
  $WebGpuPatchText `
  'kViewerSkipWebGPURedundantRenderStateSetsSwitch\[\]\s*=[\s\S]{0,120}"viewer-skip-webgpu-redundant-render-state-sets";' `
  "WebGPU redundant render-state skip helper requires viewer-app-url, trusted-content, and an explicit redundant-render-state switch"

Assert-Contains `
  $WebGpuPatchText `
  'ShouldSkipRedundantPipelineSets\(\)' `
  "WebGPU redundant setPipeline skip helper is exposed from the trusted WebGPU switch state"

Assert-Contains `
  $WebGpuPatchText `
  'ShouldSkipRedundantBindGroupSets\(\)' `
  "WebGPU redundant setBindGroup skip helper is exposed from the trusted WebGPU switch state"

Assert-Contains `
  $WebGpuPatchText `
  'ShouldSkipRedundantBufferSets\(\)' `
  "WebGPU redundant setVertexBuffer/setIndexBuffer skip helper is exposed from the trusted WebGPU switch state"

Assert-Contains `
  $WebGpuPatchText `
  'ShouldSkipRedundantRenderStateSets\(\)' `
  "WebGPU redundant render-state skip helper is exposed from the trusted WebGPU switch state"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_bind_group\.cc[\s\S]*!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]*dawn_desc\.label = label\.c_str\(\);[\s\S]*gpu_render_pipeline\.cc[\s\S]*!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]*dawn_desc_info->dawn_desc\.label = dawn_desc_info->label\.c_str\(\);' `
  "WebGPU resource-label skip gates Dawn descriptor labels on representative resource and pipeline paths"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_adapter\.cc[\s\S]*const bool skip_resource_labels[\s\S]*ShouldSkipResourceLabels\(\)[\s\S]*const String& device_label[\s\S]*skip_resource_labels \? empty_label : descriptor->label\(\)[\s\S]*MakeGarbageCollected<GPUDevice>[\s\S]*device_label' `
  "WebGPU resource-label skip avoids carrying requestDevice descriptor labels into the Blink device wrapper"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_device\.cc[\s\S]*GPUDevice::Initialize[\s\S]*const String& default_queue_label[\s\S]*ShouldSkipResourceLabels\(\)[\s\S]*empty_label[\s\S]*descriptor->defaultQueue\(\)->label\(\)[\s\S]*MakeGarbageCollected<GPUQueue>[\s\S]*default_queue_label' `
  "WebGPU resource-label skip avoids carrying defaultQueue descriptor labels into the Blink queue wrapper"

Assert-Contains `
  $WebGpuDawnObjectSourceText `
  'DawnObjectBase::DawnObjectBase\([\s\S]*label_\(webgpu_viewer_experiments::ShouldSkipResourceLabels\(\) \? String\(\)[\s\S]*: label\)[\s\S]*DawnObjectBase::setLabel\(const String& value\)[\s\S]*webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}label_ = String\(\);[\s\S]{0,120}return;[\s\S]{0,160}label_ = value;[\s\S]{0,120}SetLabelImpl\(value\);' `
  "WebGPU resource-label skip drops Blink wrapper labels and avoids Dawn SetLabel propagation"

Assert-Contains `
  $WebGpuShaderModuleSourceText `
  'GPUShaderModule::Create[\s\S]*!webgpu_viewer_experiments::ShouldSkipShaderSourceNullCheck\(\)[\s\S]*wtf_wgsl_code\.contains\(''\\0''\)[\s\S]*CreateErrorShaderModule[\s\S]*CreateShaderModule' `
  "WebGPU shader source NUL scan skip bypasses only the trusted Blink pre-scan and keeps Dawn shader module creation"

Assert-Contains `
  $WebGpuShaderModuleSourceText `
  'GPUShaderModule::Create[\s\S]*if \(!webgpu_viewer_experiments::ShouldSkipShaderMemoryAccounting\(\)\) \{[\s\S]*tint_memory_estimate_\.Set[\s\S]*input_code_size \* 100[\s\S]*\}' `
  "WebGPU shader memory-accounting skip bypasses only the Tint external memory estimate behind the trusted switch"

Assert-Contains `
  $WebGpuPatchText `
  'gpu\.cc[\s\S]*#include "third_party/blink/renderer/modules/webgpu/viewer_webgpu_experiment_switches\.h"[\s\S]*GPU::RequestAdapterImpl[\s\S]*if \(!webgpu_viewer_experiments::ShouldSkipUseCounters\(\)\) \{[\s\S]*WebFeature::kWebGPUFeatureLevelCompatibility[\s\S]*if \(!webgpu_viewer_experiments::ShouldSkipUseCounters\(\)\) \{[\s\S]*WebFeature::kWebGPURequestAdapter' `
  "WebGPU requestAdapter use-counter skip is gated by the shared trusted viewer helper"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_adapter\.cc[\s\S]*GPUAdapter::OnRequestDeviceCallback[\s\S]*if \(!webgpu_viewer_experiments::ShouldSkipUseCounters\(\)\) \{[\s\S]*ukm::builders::ClientRenderingAPI[\s\S]*\.SetGPUDevice\(static_cast<int>\(true\)\)[\s\S]*\.Record\(device->GetExecutionContext\(\)->UkmRecorder\(\)\);' `
  "WebGPU requestDevice usage telemetry skip is gated by the shared trusted viewer helper"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'void GPURenderPassEncoder::setPipeline\([\s\S]{0,600}skip_redundant_pipeline_sets_[\s\S]{0,300}raw_handle == last_render_pipeline_[\s\S]{0,300}GetHandle\(\)\.SetPipeline\(handle\);' `
  "WebGPU redundant setPipeline skip is gated on render pass encoders"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'void GPURenderBundleEncoder::setPipeline\([\s\S]{0,600}skip_redundant_pipeline_sets_[\s\S]{0,300}raw_handle == last_render_pipeline_[\s\S]{0,300}GetHandle\(\)\.SetPipeline\(handle\);' `
  "WebGPU redundant setPipeline skip is gated on render bundle encoders"

Assert-Contains `
  $WebGpuComputePassSourceText `
  'void GPUComputePassEncoder::setPipeline\([\s\S]{0,600}skip_redundant_pipeline_sets_[\s\S]{0,300}raw_handle == last_compute_pipeline_[\s\S]{0,300}GetHandle\(\)\.SetPipeline\(handle\);' `
  "WebGPU redundant setPipeline skip is gated on compute pass encoders"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'GPURenderPassEncoder::GPURenderPassEncoder\([\s\S]{0,900}skip_redundant_pipeline_sets_[\s\S]{0,120}ShouldSkipRedundantPipelineSets\(\)[\s\S]{0,260}skip_redundant_bind_group_sets_[\s\S]{0,120}ShouldSkipRedundantBindGroupSets\(\)[\s\S]{0,260}skip_redundant_buffer_sets_[\s\S]{0,120}ShouldSkipRedundantBufferSets\(\)[\s\S]{0,260}skip_redundant_render_state_sets_[\s\S]{0,120}ShouldSkipRedundantRenderStateSets\(\)' `
  "WebGPU render pass caches redundant-state trusted switch decisions once per encoder"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'GPURenderBundleEncoder::GPURenderBundleEncoder\([\s\S]{0,900}skip_redundant_pipeline_sets_[\s\S]{0,120}ShouldSkipRedundantPipelineSets\(\)[\s\S]{0,260}skip_redundant_bind_group_sets_[\s\S]{0,120}ShouldSkipRedundantBindGroupSets\(\)[\s\S]{0,260}skip_redundant_buffer_sets_[\s\S]{0,120}ShouldSkipRedundantBufferSets\(\)' `
  "WebGPU render bundle caches redundant-state trusted switch decisions once per encoder"

Assert-Contains `
  $WebGpuComputePassSourceText `
  'GPUComputePassEncoder::GPUComputePassEncoder\([\s\S]{0,700}skip_redundant_pipeline_sets_[\s\S]{0,120}ShouldSkipRedundantPipelineSets\(\)[\s\S]{0,260}skip_redundant_bind_group_sets_[\s\S]{0,120}ShouldSkipRedundantBindGroupSets\(\)' `
  "WebGPU compute pass caches redundant-state trusted switch decisions once per encoder"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'void GPURenderPassEncoder::setBindGroup\([\s\S]{0,700}ShouldSkipRedundantBindGroupSet\(index, handle\.Get\(\)\)[\s\S]{0,220}GetHandle\(\)\.SetBindGroup\(index, handle, 0, nullptr\);[\s\S]{0,900}InvalidateRedundantBindGroupSet\(index\);[\s\S]{0,320}GetHandle\(\)\.SetBindGroup' `
  "WebGPU redundant zero-dynamic-offset setBindGroup skip is gated on render pass encoders and invalidated for dynamic offsets"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'void GPURenderBundleEncoder::setBindGroup\([\s\S]{0,700}ShouldSkipRedundantBindGroupSet\(index, handle\.Get\(\)\)[\s\S]{0,220}GetHandle\(\)\.SetBindGroup\(index, handle, 0, nullptr\);[\s\S]{0,900}InvalidateRedundantBindGroupSet\(index\);[\s\S]{0,320}GetHandle\(\)\.SetBindGroup' `
  "WebGPU redundant zero-dynamic-offset setBindGroup skip is gated on render bundle encoders and invalidated for dynamic offsets"

Assert-Contains `
  $WebGpuComputePassSourceText `
  'void GPUComputePassEncoder::setBindGroup\([\s\S]{0,700}ShouldSkipRedundantBindGroupSet\(index, handle\.Get\(\)\)[\s\S]{0,220}GetHandle\(\)\.SetBindGroup\(index, handle, 0, nullptr\);[\s\S]{0,900}InvalidateRedundantBindGroupSet\(index\);[\s\S]{0,320}GetHandle\(\)\.SetBindGroup' `
  "WebGPU redundant zero-dynamic-offset setBindGroup skip is gated on compute pass encoders and invalidated for dynamic offsets"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'bool GPURenderPassEncoder::ShouldSkipRedundantIndexBufferSet\([\s\S]{0,900}skip_redundant_buffer_sets_[\s\S]*void GPURenderPassEncoder::setIndexBuffer\([\s\S]{0,700}ShouldSkipRedundantIndexBufferSet\(handle\.Get\(\), dawn_format, offset' `
  "WebGPU redundant setIndexBuffer skip is gated on render pass encoders"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'bool GPURenderPassEncoder::ShouldSkipRedundantVertexBufferSet\([\s\S]{0,900}skip_redundant_buffer_sets_[\s\S]*void GPURenderPassEncoder::setVertexBuffer\([\s\S]{0,700}ShouldSkipRedundantVertexBufferSet\(slot, handle\.Get\(\), offset' `
  "WebGPU redundant setVertexBuffer skip is gated on render pass encoders"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'bool GPURenderPassEncoder::ShouldSkipRedundantViewportSet\([\s\S]{0,700}skip_redundant_render_state_sets_[\s\S]*void GPURenderPassEncoder::setViewport\([\s\S]{0,500}ShouldSkipRedundantViewportSet\(x, y, width, height, minDepth, maxDepth\)' `
  "WebGPU redundant setViewport skip is gated on render pass encoders"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'bool GPURenderPassEncoder::ShouldSkipRedundantScissorRectSet\([\s\S]{0,700}skip_redundant_render_state_sets_[\s\S]*void GPURenderPassEncoder::setScissorRect\([\s\S]{0,420}ShouldSkipRedundantScissorRectSet\(x, y, width, height\)' `
  "WebGPU redundant setScissorRect skip is gated on render pass encoders"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'bool GPURenderPassEncoder::ShouldSkipRedundantStencilReferenceSet\([\s\S]{0,700}skip_redundant_render_state_sets_[\s\S]*void GPURenderPassEncoder::setStencilReference\([\s\S]{0,300}ShouldSkipRedundantStencilReferenceSet\(reference\)' `
  "WebGPU redundant setStencilReference skip is gated on render pass encoders"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'bool GPURenderPassEncoder::ShouldSkipRedundantBlendConstantSet\([\s\S]{0,900}skip_redundant_render_state_sets_[\s\S]*void GPURenderPassEncoder::setBlendConstant\([\s\S]{0,500}ShouldSkipRedundantBlendConstantSet\(dawn_color\)' `
  "WebGPU redundant setBlendConstant skip is gated on render pass encoders"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'bool GPURenderBundleEncoder::ShouldSkipRedundantIndexBufferSet\([\s\S]{0,900}skip_redundant_buffer_sets_[\s\S]*void GPURenderBundleEncoder::setIndexBuffer\([\s\S]{0,700}ShouldSkipRedundantIndexBufferSet\(handle\.Get\(\), dawn_format, offset' `
  "WebGPU redundant setIndexBuffer skip is gated on render bundle encoders"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'bool GPURenderBundleEncoder::ShouldSkipRedundantVertexBufferSet\([\s\S]{0,900}skip_redundant_buffer_sets_[\s\S]*void GPURenderBundleEncoder::setVertexBuffer\([\s\S]{0,700}ShouldSkipRedundantVertexBufferSet\(slot, handle\.Get\(\), offset' `
  "WebGPU redundant setVertexBuffer skip is gated on render bundle encoders"

$PipelineStateSources = @(
  [pscustomobject]@{
    Text = $WebGpuRenderPassSourceText
    Name = "render pass"
  },
  [pscustomobject]@{
    Text = $WebGpuRenderBundleSourceText
    Name = "render bundle"
  },
  [pscustomobject]@{
    Text = $WebGpuComputePassSourceText
    Name = "compute pass"
  }
)

foreach ($Source in $PipelineStateSources) {
  Assert-Contains `
    $Source.Text `
    'state stays live across pipeline[\s\S]*this trusted[\s\S]*path only suppresses consecutive same-pipeline[\s\S]*raw_handle == last_(?:render|compute)_pipeline_' `
    "WebGPU redundant setPipeline skip on $($Source.Name) documents that other encoder state remains live across pipeline changes"
}

$BindGroupDynamicOffsetSources = @(
  [pscustomobject]@{
    Text = $WebGpuRenderPassSourceText
    Name = "render pass"
  },
  [pscustomobject]@{
    Text = $WebGpuRenderBundleSourceText
    Name = "render bundle"
  },
  [pscustomobject]@{
    Text = $WebGpuComputePassSourceText
    Name = "compute pass"
  }
)

foreach ($Source in $BindGroupDynamicOffsetSources) {
  Assert-Contains `
    $Source.Text `
    'setBindGroup\(\s*uint32_t index,\s*GPUBindGroup\* bindGroup[\s\S]*dynamicOffsets\.empty\(\)[\s\S]{0,180}return;[\s\S]{0,180}InvalidateRedundantBindGroupSet\(index\);[\s\S]{0,260}dynamicOffsets\.size\(\), dynamicOffsets\.data\(\)' `
    "WebGPU $($Source.Name) bind-group vector dynamic offsets invalidate the redundant no-offset cache before recording non-empty offsets"

  Assert-Contains `
    $Source.Text `
    'ValidateSetBindGroupDynamicOffsets[\s\S]*data_span\.empty\(\)[\s\S]{0,180}return;[\s\S]{0,180}InvalidateRedundantBindGroupSet\(index\);[\s\S]{0,260}data_span\.size\(\), data_span\.data\(\)' `
    "WebGPU $($Source.Name) bind-group typed-array dynamic offsets validate first, fast-path empty spans, then invalidate the redundant no-offset cache before recording non-empty offsets"
}

$RenderBufferSkipSources = @(
  [pscustomobject]@{
    Text = $WebGpuRenderPassSourceText
    Name = "render pass"
  },
  [pscustomobject]@{
    Text = $WebGpuRenderBundleSourceText
    Name = "render bundle"
  }
)

foreach ($Source in $RenderBufferSkipSources) {
  Assert-Contains `
    $Source.Text `
    'last_index_buffer_\.size_specified == size_specified[\s\S]{0,520}last_index_buffer_\.size_specified = size_specified[\s\S]*setIndexBuffer\(\s*const DawnObject<wgpu::Buffer>\* buffer,\s*const V8GPUIndexFormat& format,\s*uint64_t offset\)[\s\S]{0,460}ShouldSkipRedundantIndexBufferSet\(handle\.Get\(\), dawn_format, offset, 0,\s*false\)[\s\S]*setIndexBuffer\(\s*const DawnObject<wgpu::Buffer>\* buffer,\s*const V8GPUIndexFormat& format,\s*uint64_t offset,\s*uint64_t size\)[\s\S]{0,500}ShouldSkipRedundantIndexBufferSet\(handle\.Get\(\), dawn_format, offset, size,\s*true\)' `
    "WebGPU $($Source.Name) index-buffer redundant skip keys distinguish implicit-size and explicit-size overloads"

  Assert-Contains `
    $Source.Text `
    'last_vertex_buffer\.size_specified == size_specified[\s\S]{0,520}last_vertex_buffer\.size_specified = size_specified[\s\S]*setVertexBuffer\(\s*uint32_t slot,\s*const DawnObject<wgpu::Buffer>\* buffer,\s*uint64_t offset\)[\s\S]{0,420}ShouldSkipRedundantVertexBufferSet\(slot, handle\.Get\(\), offset, 0,\s*false\)[\s\S]*setVertexBuffer\(\s*uint32_t slot,\s*const DawnObject<wgpu::Buffer>\* buffer,\s*uint64_t offset,\s*uint64_t size\)[\s\S]{0,470}ShouldSkipRedundantVertexBufferSet\(slot, handle\.Get\(\), offset, size,\s*true\)' `
    "WebGPU $($Source.Name) vertex-buffer redundant skip keys distinguish implicit-size and explicit-size overloads"
}

Assert-Contains `
  $WebGpuAddedCode `
  'const ViewerWebGPUExperimentState& viewer_state =[\s\S]*GetViewerWebGPUExperimentState\(\)' `
  "WebGPU source-backed hot paths read the cached trusted viewer state"

Assert-Contains `
  $WebGpuAddedCode `
  'constexpr char kViewerDeferWebGPUPipelineFlushSwitch\[\]\s*=\s*"viewer-defer-webgpu-pipeline-flush";' `
  "WebGPU async pipeline flush deferral defines an explicit trusted viewer switch"

Assert-Contains `
  $WebGpuAddedCode `
  'struct ViewerWebGPUDeviceExperimentState \{[\s\S]*defer_pipeline_flush' `
  "WebGPU device source-backed experiment patch stores async pipeline flush decisions in cached state"

Assert-Contains `
  $WebGpuAddedCode `
  'ViewerWebGPUDeviceExperimentState BuildViewerWebGPUDeviceExperimentState\(\) \{[\s\S]*IsTrustedViewerApp\(command_line\)[\s\S]*kViewerDeferWebGPUPipelineFlushSwitch' `
  "WebGPU device experiment state is built from trusted viewer gates and the explicit async pipeline flush switch"

Assert-Contains `
  $WebGpuAddedCode `
  'base::NoDestructor<ViewerWebGPUDeviceExperimentState>' `
  "WebGPU device experiment state is cached instead of re-reading command-line switches on every async pipeline call"

Assert-Contains `
  $WebGpuPatchText `
  'GPUDevice::createRenderPipelineAsync[\s\S]*if \(!GetViewerWebGPUDeviceExperimentState\(\)\.defer_pipeline_flush\) \{[\s\S]*EnsureFlush\(ToEventLoop\(script_state\)\);[\s\S]*\}' `
  "WebGPU render pipeline async flush deferral is guarded by the cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'GPUDevice::createComputePipelineAsync[\s\S]*if \(!GetViewerWebGPUDeviceExperimentState\(\)\.defer_pipeline_flush\) \{[\s\S]*EnsureFlush\(ToEventLoop\(script_state\)\);[\s\S]*\}' `
  "WebGPU compute pipeline async flush deferral is guarded by the cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_device\.cc[\s\S]*#include "third_party/blink/renderer/modules/webgpu/viewer_webgpu_experiment_switches\.h"[\s\S]*GPUDevice::createRenderPipelineAsync[\s\S]*const String callback_label =[\s\S]*webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]*\? String\(\)[\s\S]*: descriptor->label\(\);[\s\S]*OnCreateRenderPipelineAsyncCallback[\s\S]*callback_label' `
  "WebGPU resource-label skip clears async render pipeline callback wrapper labels"

Assert-Contains `
  $WebGpuPatchText `
  'GPUDevice::createComputePipelineAsync[\s\S]*const String callback_label =[\s\S]*webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]*\? String\(\)[\s\S]*: descriptor->label\(\);[\s\S]*OnCreateComputePipelineAsyncCallback[\s\S]*callback_label' `
  "WebGPU resource-label skip clears async compute pipeline callback wrapper labels"

foreach ($StateField in @(
    "defer_queue_flush",
    "defer_submit_flush",
    "reject_cpu_texture_fallback",
    "skip_copy_external_image_color_conversion",
    "skip_copy_external_image_color_space_validation",
    "skip_copy_external_image_dest_validation",
    "skip_copy_external_image_source_validation",
    "skip_copy_external_image_copy_size_validation",
    "skip_write_texture_layout_validation",
    "skip_use_counters",
    "trace_queue"
  )) {
  Assert-Contains `
    $WebGpuAddedCode `
    "viewer_state\.$StateField" `
    "WebGPU source-backed experiment field $StateField is read from cached state"
}

Assert-Contains `
  $WebGpuAddedCode `
  'struct ViewerWebGPUExperimentState \{[\s\S]*defer_queue_flush[\s\S]*defer_submit_flush[\s\S]*reject_cpu_texture_fallback[\s\S]*skip_use_counters[\s\S]*trace_queue' `
  "WebGPU source-backed experiment patch stores queue experiment decisions in a single state struct"

Assert-Contains `
  $WebGpuAddedCode `
  'struct ViewerWebGPUExperimentState \{[\s\S]*defer_queue_flush[\s\S]*defer_submit_flush[\s\S]*reject_cpu_texture_fallback[\s\S]*skip_copy_external_image_color_conversion[\s\S]*skip_copy_external_image_color_space_validation[\s\S]*skip_copy_external_image_dest_validation[\s\S]*skip_use_counters[\s\S]*trace_queue' `
  "WebGPU source-backed experiment patch stores queue and copyExternalImage experiment decisions in a single state struct"

Assert-Contains `
  $WebGpuAddedCode `
  'struct ViewerWebGPUExperimentState \{[\s\S]*defer_queue_flush[\s\S]*defer_submit_flush[\s\S]*reject_cpu_texture_fallback[\s\S]*skip_copy_external_image_color_conversion[\s\S]*skip_copy_external_image_color_space_validation[\s\S]*skip_copy_external_image_dest_validation[\s\S]*skip_copy_external_image_source_validation[\s\S]*skip_copy_external_image_copy_size_validation[\s\S]*skip_use_counters[\s\S]*trace_queue' `
  "WebGPU source-backed experiment patch stores source and copy-size validation with the other copyExternalImage decisions in a single state struct"

Assert-Contains `
  $WebGpuAddedCode `
  'ViewerWebGPUExperimentState BuildViewerWebGPUExperimentState\(\) \{[\s\S]*IsTrustedViewerApp\(command_line\)[\s\S]*kViewerDeferWebGPUQueueFlushSwitch[\s\S]*kViewerDeferWebGPUSubmitFlushSwitch[\s\S]*kViewerRejectWebGPUCPUTextureFallbackSwitch[\s\S]*kViewerSkipWebGPUCopyExternalImageColorConversionSwitch[\s\S]*kViewerSkipWebGPUCopyExternalImageColorSpaceValidationSwitch[\s\S]*kViewerSkipWebGPUCopyExternalImageDestValidationSwitch[\s\S]*kViewerSkipWebGPUCopyExternalImageSourceValidationSwitch[\s\S]*kViewerSkipWebGPUCopyExternalImageCopySizeValidationSwitch[\s\S]*kViewerSkipWebGPUWriteTextureLayoutValidationSwitch[\s\S]*kViewerSkipWebGPUUseCountersSwitch[\s\S]*kViewerTraceWebGPUQueueSwitch' `
  "WebGPU source-backed experiment state is built from trusted viewer gates and explicit experiment switches"

Assert-Contains `
  $WebGpuAddedCode `
  'base::NoDestructor<ViewerWebGPUExperimentState>' `
  "WebGPU source-backed experiment state is cached instead of re-reading command-line switches on every queue operation"

Assert-Contains `
  $WebGpuPatchText `
  'constexpr char kViewerTraceWebGPUQueueSwitch\[\] = "viewer-trace-webgpu-queue";' `
  "WebGPU source-backed experiment patch defines an explicit diagnostic trace gate"

Assert-Contains `
  $WebGpuAddedCode `
  'if \(!viewer_state\.skip_use_counters\) \{[\s\S]*UseCounter::Count\(execution_context, WebFeature::kWebGPUQueueSubmit\);[\s\S]*\}' `
  "WebGPU queue submit use-counter skip is gated by the cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'constexpr wtf_size_t kViewerStackCommandBufferSubmitLimit = 4;' `
  "WebGPU queue submit stack fast path has an explicit small-batch limit"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::submit[\s\S]*if \(buffer_count == 1\) \{[\s\S]*wgpu::CommandBuffer command_buffer;[\s\S]*command_buffer = AsDawnType\(buffers\[0\]\.Get\(\)\);[\s\S]*GetHandle\(\)\.Submit\(1, &command_buffer\);[\s\S]*buffer_count <= kViewerStackCommandBufferSubmitLimit[\s\S]*stack_command_buffers\[index\] = AsDawnType\(buffers\[index\]\.Get\(\)\);[\s\S]*GetHandle\(\)\.Submit\(buffer_count, stack_command_buffers\.data\(\)\);' `
  "WebGPU queue submit avoids heap-array conversion and the small-batch loop on single-buffer submits"

Assert-Contains `
  $WebGpuProgrammablePassSourceText `
  'ValidateSetImmediatesAndSubSpan[\s\S]*const uint64_t data_element_count[\s\S]*data_element_offset == 0[\s\S]*!data_element_size\.has_value\(\)[\s\S]*data_element_size\.value\(\) == data_element_count[\s\S]*data\.size\(\) % 4 != 0[\s\S]*size, converted to bytes, must be a multiple of 4\.[\s\S]*\*out = data;[\s\S]*return true;' `
  "WebGPU setImmediates full-span fast path preserves the existing size multiple check and returns the original data span for implicit and explicit full-size calls"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_programmable_pass_encoder\.cc[\s\S]*ValidateSetImmediatesAndSubSpan[\s\S]*const uint64_t data_element_count[\s\S]*data_element_offset == 0[\s\S]*data_element_size\.value\(\) == data_element_count[\s\S]*\*out = data;[\s\S]*return true;' `
  "WebGPU setImmediates implicit and explicit full-span fast path is included in the reproducible patch series"

Assert-Contains `
  $WebGpuPatchText `
  'std::array<wgpu::CommandBuffer, kViewerStackCommandBufferSubmitLimit>[\s\S]*stack_command_buffers = \{\};[\s\S]*if \(buffers\[index\]\) \{[\s\S]*stack_command_buffers\[index\] = AsDawnType\(buffers\[index\]\.Get\(\)\);' `
  "WebGPU queue small-batch submit stack entries are zero-initialized before nullable command-buffer conversion"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_command_encoder\.cc[\s\S]*constexpr size_t kViewerStackRenderPassColorAttachmentLimit = 4;' `
  "WebGPU command encoder patch defines a stack-backed render-pass color attachment limit"

$RenderPassColorAttachmentChecks = @{
  'ConvertRenderPassColorAttachmentAt\(' = "helper exists"
  'std::string\* depth_slice_error' = "helper carries depth-slice validation error output"
  'const char\* desc_label' = "helper receives the descriptor label without forcing UTF8 work for empty labels"
  'if \(!in\[index\]\) \{[\s\S]*\*out = \{\};[\s\S]*return true;' = "helper preserves nullable color attachment semantics"
  'attachment->depthSlice\(\) == wgpu::kDepthSliceUndefined' = "helper checks the Dawn undefined depthSlice sentinel"
  'against the colorAttachment \(" << index << "\)\.' = "helper reports the offending color attachment index"
  '\*depth_slice_error = error\.str\(\);' = "helper records the depth-slice validation error during conversion"
  'return ConvertToDawn\(attachment, out, exception_state\);' = "helper still uses the normal Dawn conversion"
}

foreach ($Check in $RenderPassColorAttachmentChecks.GetEnumerator()) {
  Assert-Contains `
    $WebGpuCommandEncoderSourceText `
    $Check.Key `
    "WebGPU render-pass color attachment conversion $($Check.Value)"
}

Assert-Contains `
  $WebGpuPatchText `
  'gpu_adapter\.cc[\s\S]*const bool needs_shader_module_compilation_options[\s\S]*const bool has_required_features[\s\S]*Vector<wgpu::FeatureName> required_features;[\s\S]*if \(needs_shader_module_compilation_options \|\| has_required_features\) \{[\s\S]*HashSet<wgpu::FeatureName> required_features_set;[\s\S]*if \(has_required_features\) \{[\s\S]*for \(const V8GPUFeatureName& f : descriptor->requiredFeatures\(\)\)[\s\S]*required_features = Vector<wgpu::FeatureName>\(required_features_set\);[\s\S]*dawn_desc\.requiredFeatures = required_features\.data\(\);[\s\S]*dawn_desc\.requiredFeatureCount = required_features\.size\(\);' `
  "WebGPU requestDevice skips required-features set/vector conversion when no features are requested"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_device\.cc[\s\S]*GPUDevice::Initialize[\s\S]*adapter_info_ = adapter_->info\(\);' `
  "WebGPU device initialization reuses the adapter info object instead of rebuilding adapter metadata"

function Get-WebGpuModuleText {
  param([string]$RelativePath)

  $SourcePath = Join-Path $Root "src\third_party\blink\renderer\modules\webgpu\$RelativePath"
  if (Test-Path -LiteralPath $SourcePath) {
    return Get-Content -LiteralPath $SourcePath -Raw
  }

  return $WebGpuPatchText
}

$LabelSkipChecks = @(
  [pscustomobject]@{
    Source = "gpu_adapter.cc"
    Pattern = 'const bool skip_resource_labels[\s\S]{0,120}webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!skip_resource_labels && !descriptor->label\(\)\.empty\(\)[\s\S]{0,160}label = descriptor->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_adapter.cc"
    Pattern = 'const bool skip_resource_labels[\s\S]{0,120}webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,260}!skip_resource_labels && !descriptor->defaultQueue\(\)->label\(\)\.empty\(\)[\s\S]{0,160}queueLabel = descriptor->defaultQueue\(\)->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_bind_group.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_bind_group_layout.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_buffer.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}\*label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_command_encoder.cc"
    Pattern = 'if \(skip_command_labels \|\| webgpu_desc->label\(\)\.empty\(\)\)[\s\S]{0,260}std::string label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_command_encoder.cc"
    Pattern = '!skip_command_labels && !descriptor->label\(\)\.empty\(\)[\s\S]{0,160}label = descriptor->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_compute_pipeline.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}\*label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_pipeline_layout.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_query_set.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_render_bundle_encoder.cc"
    Pattern = 'const bool skip_labels[\s\S]{0,120}ShouldSkipCommandLabels\(\)[\s\S]{0,120}ShouldSkipResourceLabels\(\)[\s\S]{0,160}!skip_labels && !webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_sampler.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}\*label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_shader_module.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!webgpu_desc->label\(\)\.empty\(\)[\s\S]{0,160}label = webgpu_desc->label\(\)\.Utf8\(\);'
  },
  [pscustomobject]@{
    Source = "gpu_texture.cc"
    Pattern = '!webgpu_viewer_experiments::ShouldSkipResourceLabels\(\)[\s\S]{0,160}!in->label\(\)\.empty\(\)[\s\S]{0,160}\*label = in->label\(\)\.Utf8\(\);'
  }
)

foreach ($Check in $LabelSkipChecks) {
  Assert-Contains `
    (Get-WebGpuModuleText $Check.Source) `
    $Check.Pattern `
    "WebGPU common descriptor paths avoid empty-label UTF-8 conversion in $($Check.Source)"
}

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'GPUCommandEncoder::beginRenderPass[\s\S]*const bool skip_command_labels =[\s\S]*webgpu_viewer_experiments::ShouldSkipCommandLabels\(\);[\s\S]*if \(!skip_command_labels && !descriptor->label\(\)\.empty\(\)\) \{[\s\S]*label = descriptor->label\(\)\.Utf8\(\);[\s\S]*dawn_desc\.label = label\.c_str\(\);[\s\S]*const char\* desc_label = label\.empty\(\) \? nullptr : label\.c_str\(\);[\s\S]*std::array<wgpu::RenderPassColorAttachment,[\s\S]*kViewerStackRenderPassColorAttachmentLimit[\s\S]*std::string depth_slice_error;[\s\S]*dawn_desc\.colorAttachmentCount <=[\s\S]*kViewerStackRenderPassColorAttachmentLimit[\s\S]*ConvertRenderPassColorAttachmentAt\([\s\S]*&depth_slice_error, desc_label, exception_state[\s\S]*dawn_desc\.colorAttachments = stack_color_attachments\.data\(\);[\s\S]*ConvertRenderPassColorAttachments\([\s\S]*&depth_slice_error, desc_label, exception_state[\s\S]*GetHandle\(\)\.InjectValidationError\(depth_slice_error\.c_str\(\)\)' `
  "WebGPU beginRenderPass avoids heap conversion for common small color-attachment lists, keeps the heap fallback, and avoids a separate depth-slice validation pass"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'GPUCommandEncoder::beginRenderPass[\s\S]*MakeGarbageCollected<GPURenderPassEncoder>[\s\S]*skip_command_labels \? String\(\) : descriptor->label\(\)' `
  "WebGPU command-label skip clears Blink render pass wrapper labels"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'bool ConvertCommonGPUColorDict\(const V8GPUColor\* in, wgpu::Color\* out\)[\s\S]*GetContentType\(\) != V8GPUColor::ContentType::kGPUColorDict[\s\S]*dict->r\(\), dict->g\(\), dict->b\(\), dict->a\(\)[\s\S]*ConvertToDawn\(const GPURenderPassColorAttachment\* in[\s\S]*const V8GPUColor\* clear_value = in->clearValue\(\);[\s\S]*ConvertCommonGPUColorDict\(clear_value, &out->clearValue\)[\s\S]*ConvertToDawn\(clear_value, &out->clearValue, exception_state\)' `
  "WebGPU render-pass clearValue conversion fast-paths common GPUColorDict values while preserving generic fallback"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'GPUCommandEncoder::Create[\s\S]*const bool skip_command_labels =[\s\S]*webgpu_viewer_experiments::ShouldSkipCommandLabels\(\);[\s\S]*if \(skip_command_labels \|\| webgpu_desc->label\(\)\.empty\(\)\) \{[\s\S]*command_encoder_handle = device->GetHandle\(\)\.CreateCommandEncoder\(\);[\s\S]*\} else \{[\s\S]*std::string label = webgpu_desc->label\(\)\.Utf8\(\);[\s\S]*wgpu::CommandEncoderDescriptor dawn_desc = \{[\s\S]*\.label = label\.c_str\(\),[\s\S]*\};[\s\S]*command_encoder_handle =[\s\S]*device->GetHandle\(\)\.CreateCommandEncoder\(&dawn_desc\);[\s\S]*std::move\(command_encoder_handle\)[\s\S]*skip_command_labels \? String\(\) : webgpu_desc->label\(\)' `
  "WebGPU command encoder creation uses Dawn's null/default descriptor path and clears the Blink wrapper label for unlabeled or trusted label-skip command encoders"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'GPUCommandEncoder::finish[\s\S]*const bool skip_command_labels =[\s\S]*webgpu_viewer_experiments::ShouldSkipCommandLabels\(\);[\s\S]*if \(skip_command_labels \|\| descriptor->label\(\)\.empty\(\)\) \{[\s\S]*command_buffer_handle = GetHandle\(\)\.Finish\(\);[\s\S]*\} else \{[\s\S]*std::string label = descriptor->label\(\)\.Utf8\(\);[\s\S]*wgpu::CommandBufferDescriptor dawn_desc = \{[\s\S]*\.label = label\.c_str\(\),[\s\S]*\};[\s\S]*command_buffer_handle = GetHandle\(\)\.Finish\(&dawn_desc\);[\s\S]*std::move\(command_buffer_handle\)[\s\S]*skip_command_labels \? String\(\) : descriptor->label\(\)' `
  "WebGPU command encoder finish uses Dawn's null/default descriptor path and clears the Blink wrapper label for unlabeled or trusted label-skip command buffers"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'GPURenderBundleEncoder::Create[\s\S]*const bool skip_labels =[\s\S]*ShouldSkipCommandLabels\(\)[\s\S]*ShouldSkipResourceLabels\(\)[\s\S]*if \(!skip_labels && !webgpu_desc->label\(\)\.empty\(\)\)[\s\S]*label = webgpu_desc->label\(\)\.Utf8\(\);[\s\S]*CreateRenderBundleEncoder\(&dawn_desc\)[\s\S]*skip_labels \? String\(\) : webgpu_desc->label\(\)' `
  "WebGPU command-label skip clears render-bundle encoder wrapper labels and avoids encoder descriptor label conversion"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'GPURenderBundleEncoder::finish[\s\S]*const bool skip_labels =[\s\S]*ShouldSkipCommandLabels\(\)[\s\S]*ShouldSkipResourceLabels\(\)[\s\S]*if \(skip_labels \|\| webgpu_desc->label\(\)\.empty\(\)\)[\s\S]*GetHandle\(\)\.Finish\(nullptr\)[\s\S]*skip_labels \? String\(\) : webgpu_desc->label\(\)[\s\S]*std::string label = webgpu_desc->label\(\)\.Utf8\(\);[\s\S]*GetHandle\(\)\.Finish\(&dawn_desc\)' `
  "WebGPU command-label skip clears render-bundle wrapper labels and avoids finish descriptor label conversion"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'GPUCommandEncoder::beginComputePass[\s\S]*const bool skip_command_labels =[\s\S]*webgpu_viewer_experiments::ShouldSkipCommandLabels\(\);[\s\S]*if \(\(skip_command_labels \|\| descriptor->label\(\)\.empty\(\)\) &&[\s\S]*!descriptor->hasTimestampWrites\(\)\) \{[\s\S]*GetHandle\(\)\.BeginComputePass\(nullptr\)[\s\S]*skip_command_labels \? String\(\) : descriptor->label\(\)[\s\S]*if \(!skip_command_labels && !descriptor->label\(\)\.empty\(\)\) \{[\s\S]*dawn_desc\.label = label\.c_str\(\);[\s\S]*BeginComputePass\(&dawn_desc\)[\s\S]*skip_command_labels \? String\(\) : descriptor->label\(\)' `
  "WebGPU beginComputePass uses Dawn's null/default descriptor path and clears the Blink wrapper label when trusted label-skip mode is active"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'bool ConvertCommonTexelCopyBufferInfo\([\s\S]*webgpu_view->offset\(\) != 0[\s\S]*!webgpu_view->hasBytesPerRow\(\)[\s\S]*webgpu_view->hasRowsPerImage\(\)[\s\S]*bytes_per_row == wgpu::kCopyStrideUndefined[\s\S]*\.bytesPerRow = bytes_per_row[\s\S]*\.rowsPerImage = wgpu::kCopyStrideUndefined[\s\S]*\.buffer = webgpu_view->buffer\(\)->GetHandle\(\)' `
  "WebGPU command encoder has a common texel-copy buffer layout fast path for offset-zero bytesPerRow-only texture copy buffers"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'bool ConvertCommonExtent3D\(const V8GPUExtent3D\* in, wgpu::Extent3D\* out\)[\s\S]*GetContentType\(\)[\s\S]*kGPUExtent3DDict[\s\S]*dict->hasDepth\(\)[\s\S]*return false;[\s\S]*dict->width\(\), dict->height\(\), dict->depthOrArrayLayers\(\)[\s\S]*kUnsignedLongEnforceRangeSequence[\s\S]*sequence\.size\(\)[\s\S]*case 1:[\s\S]*case 2:[\s\S]*case 3:[\s\S]*default:[\s\S]*return false;[\s\S]*return false;[\s\S]*anonymous namespace' `
  "WebGPU command encoder has a common GPUExtent3D conversion fast path while preserving deprecated-depth and invalid-sequence fallback"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'GPUCommandEncoder::copyBufferToTexture[\s\S]*ConvertCommonExtent3D\(copy_size, &dawn_copy_size\)[\s\S]*ConvertToDawn\(copy_size, &dawn_copy_size, device_,[\s\S]*exception_state\)[\s\S]*ConvertCommonTexelCopyBufferInfo\(source, &dawn_source\)[\s\S]*ValidateAndConvertTexelCopyBufferInfo\(source, &error\)' `
  "WebGPU copyBufferToTexture uses common GPUExtent3D and texel-copy buffer fast paths before generic conversion"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'GPUCommandEncoder::copyTextureToBuffer[\s\S]*ConvertCommonExtent3D\(copy_size, &dawn_copy_size\)[\s\S]*ConvertToDawn\(copy_size, &dawn_copy_size, device_,[\s\S]*exception_state\)[\s\S]*ConvertCommonTexelCopyBufferInfo\(destination, &dawn_destination\)[\s\S]*ValidateAndConvertTexelCopyBufferInfo\(destination, &error\)' `
  "WebGPU copyTextureToBuffer uses common GPUExtent3D and texel-copy buffer fast paths before generic conversion"

Assert-Contains `
  $WebGpuCommandEncoderSourceText `
  'GPUCommandEncoder::copyTextureToTexture[\s\S]*ConvertCommonExtent3D\(copy_size, &dawn_copy_size\)[\s\S]*ConvertToDawn\(copy_size, &dawn_copy_size, device_,[\s\S]*exception_state\)' `
  "WebGPU copyTextureToTexture uses the common GPUExtent3D fast path before generic conversion"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_command_encoder\.cc[\s\S]*bool ConvertCommonGPUColorDict\(const V8GPUColor\* in, wgpu::Color\* out\)[\s\S]*bool ConvertCommonTexelCopyBufferInfo\([\s\S]*bool ConvertCommonExtent3D\(const V8GPUExtent3D\* in, wgpu::Extent3D\* out\)[\s\S]*GPUCommandEncoder::copyBufferToTexture[\s\S]*GPUCommandEncoder::copyTextureToBuffer[\s\S]*GPUCommandEncoder::copyTextureToTexture' `
  "WebGPU command-encoder clearValue, copy-size, and texel-copy buffer fast paths are captured in the Chromium patch series"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_sampler\.cc[\s\S]*bool IsDefaultSamplerDescriptor[\s\S]*label\(\)\.empty\(\)[\s\S]*V8GPUAddressMode::Enum::kClampToEdge[\s\S]*V8GPUFilterMode::Enum::kNearest[\s\S]*V8GPUMipmapFilterMode::Enum::kNearest[\s\S]*lodMaxClamp\(\) == 32\.0f[\s\S]*!webgpu_desc->hasCompare\(\)[\s\S]*maxAnisotropy\(\) == 1[\s\S]*GPUSampler::Create[\s\S]*IsDefaultSamplerDescriptor\(webgpu_desc\)[\s\S]*CreateSampler\(nullptr\)' `
  "WebGPU sampler creation uses Dawn's null/default descriptor path for exactly default unlabeled samplers"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_pipeline_layout\.cc[\s\S]*constexpr size_t kViewerStackPipelineBindGroupLayoutLimit = 4;' `
  "WebGPU pipeline layout patch defines a stack-backed bind-group layout limit"

Assert-Contains `
  $WebGpuPatchText `
  'GPUPipelineLayout::Create[\s\S]*std::array<wgpu::BindGroupLayout, kViewerStackPipelineBindGroupLayoutLimit>[\s\S]*bind_group_layout_count <= kViewerStackPipelineBindGroupLayoutLimit[\s\S]*stack_bind_group_layouts\[i\] =[\s\S]*AsDawnType\(bind_group_layouts_input\[i\]\.Get\(\)\)[\s\S]*stack_bind_group_layouts\[i\] = \{\};[\s\S]*dawn_bind_group_layouts = stack_bind_group_layouts\.data\(\);[\s\S]*bind_group_layouts = AsDawnType\(bind_group_layouts_input\)' `
  "WebGPU pipeline layout avoids heap conversion for common small bind-group-layout lists and keeps nullable entries plus heap fallback"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_bind_group\.cc[\s\S]*constexpr size_t kViewerStackBindGroupEntryLimit = 8;' `
  "WebGPU bind group patch defines a stack-backed bind-group entry limit"

Assert-Contains `
  $WebGpuPatchText `
  'GPUBindGroup::Create[\s\S]*std::array<wgpu::BindGroupEntry, kViewerStackBindGroupEntryLimit>[\s\S]*entry_count <= kViewerStackBindGroupEntryLimit[\s\S]*AsDawnType\(entries_input\[i\]\.Get\(\), &externalTextureBindingEntries\)[\s\S]*dawn_entries = stack_entries\.data\(\);[\s\S]*entries = AsDawnType\(entries_input, &externalTextureBindingEntries\)[\s\S]*\.entries = dawn_entries' `
  "WebGPU bind group creation avoids heap conversion for common small entry lists and keeps external-texture lifetime plus heap fallback"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_bind_group_layout\.cc[\s\S]*constexpr size_t kViewerStackBindGroupLayoutEntryLimit = 8;' `
  "WebGPU bind group layout patch defines a stack-backed bind-group layout entry limit"

Assert-Contains `
  $WebGpuPatchText `
  'GPUBindGroupLayout::Create[\s\S]*std::array<wgpu::BindGroupLayoutEntry, kViewerStackBindGroupLayoutEntryLimit>[\s\S]*entry_count <= kViewerStackBindGroupLayoutEntryLimit[\s\S]*AsDawnType\(device, entries_input\[i\]\.Get\(\),[\s\S]*&externalTextureBindingLayouts, exception_state\)[\s\S]*dawn_entries = stack_entries\.data\(\);[\s\S]*entries = AsDawnType\(device, entries_input,[\s\S]*&externalTextureBindingLayouts, exception_state\)[\s\S]*if \(exception_state\.HadException\(\)\)[\s\S]*\.entries = dawn_entries' `
  "WebGPU bind group layout creation avoids heap conversion for common small entry lists and keeps validation/external-texture lifetime plus heap fallback"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_render_pipeline\.h[\s\S]*static constexpr size_t kStackVertexBufferLimit = 4;[\s\S]*static constexpr size_t kStackVertexAttributeLimit = 8;[\s\S]*stack_buffers[\s\S]*stack_attributes[\s\S]*static constexpr size_t kStackColorTargetLimit = 4;[\s\S]*stack_targets[\s\S]*stack_blend_states' `
  "WebGPU render pipeline patch adds stack storage for common vertex and fragment descriptor lists"

Assert-Contains `
  $WebGpuPatchText `
  'AsDawnVertexBufferLayouts[\s\S]*use_stack_buffers[\s\S]*kStackVertexBufferLimit[\s\S]*kStackVertexAttributeLimit[\s\S]*dawn_desc_info->stack_buffers\[i\][\s\S]*dawn_desc_info->stack_attributes\[i\]\[attribute_index\][\s\S]*dawn_vertex->buffers = dawn_desc_info->stack_buffers\.data\(\);[\s\S]*dawn_desc_info->buffers = AsDawnType\(buffers_input\)' `
  "WebGPU render pipeline vertex conversion avoids heap conversion for common small vertex-buffer/attribute lists and keeps the heap fallback"

Assert-Contains `
  $WebGpuPatchText `
  'GPUFragmentStateAsWGPUFragmentState[\s\S]*use_stack_targets[\s\S]*kStackColorTargetLimit[\s\S]*dawn_fragment->stack_targets\[i\] = AsDawnType\(targets_input\[i\]\.Get\(\)\)[\s\S]*dawn_fragment->dawn_desc\.targets = dawn_fragment->stack_targets\.data\(\);[\s\S]*dawn_fragment->targets = AsDawnType\(targets_input\)[\s\S]*dawn_fragment->stack_blend_states\[i\] = AsDawnType\(blend_state\)[\s\S]*dawn_fragment->stack_targets\[i\]\.blend[\s\S]*dawn_fragment->blend_states\[i\] = AsDawnType\(blend_state\)' `
  "WebGPU render pipeline fragment conversion avoids heap conversion for common small color-target/blend-state lists and keeps validation plus heap fallback"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_programmable_stage\.h[\s\S]*static constexpr size_t kStackConstantLimit = 8;[\s\S]*stack_constant_keys[\s\S]*stack_constants[\s\S]*constants_data' `
  "WebGPU programmable-stage patch adds stack storage and a shared constants pointer for common small shader-constant lists"

Assert-Contains `
  $WebGpuPatchText `
  'GPUProgrammableStageAsWGPUProgrammableStage[\s\S]*constants\.size\(\) == 0[\s\S]*constants\.size\(\) <= OwnedProgrammableStage::kStackConstantLimit[\s\S]*stack_constant_keys\.emplace\(\)[\s\S]*UNSAFE_TODO\(dawn_programmable_stage->stack_constants\[i\]\)\.key[\s\S]*constants_data =[\s\S]*stack_constants\.data\(\)[\s\S]*constantKeys =[\s\S]*std::make_unique<std::string\[\]>\(constants\.size\(\)\)[\s\S]*constants_data =[\s\S]*constants\.get\(\)' `
  "WebGPU programmable-stage conversion avoids heap allocation for common small shader-constant lists and keeps the heap fallback"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_render_pipeline\.cc[\s\S]*dawn_vertex->dawn_desc->constants = dawn_vertex->constants_data[\s\S]*dawn_fragment->dawn_desc\.constants = dawn_fragment->constants_data' `
  "WebGPU render pipeline uses the programmable-stage constants pointer for stack or heap-backed constants"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_compute_pipeline\.cc[\s\S]*dawn_desc\.compute\.constants = computeStage->constants_data' `
  "WebGPU compute pipeline uses the programmable-stage constants pointer for stack or heap-backed constants"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_texture\.cc[\s\S]*constexpr size_t kViewerStackTextureViewFormatLimit = 4;[\s\S]*ConvertToDawn\([\s\S]*stack_view_formats[\s\S]*viewFormatCount = view_formats_input\.size\(\)[\s\S]*viewFormatCount <= kViewerStackTextureViewFormatLimit[\s\S]*UNSAFE_TODO\(\(\*stack_view_formats\)\[i\]\) =[\s\S]*AsDawnEnum\(view_formats_input\[i\]\)[\s\S]*out->viewFormats = stack_view_formats->data\(\)[\s\S]*\*view_formats = AsDawnEnum<wgpu::TextureFormat>\(view_formats_input\)[\s\S]*out->viewFormats = view_formats->data\(\)' `
  "WebGPU texture creation avoids heap conversion for common small view-format lists and keeps the heap fallback"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_texture\.cc[\s\S]*bool ConvertCommonExtent3D\(const V8GPUExtent3D\* in, wgpu::Extent3D\* out\)[\s\S]*kGPUExtent3DDict[\s\S]*dict->hasDepth\(\)[\s\S]*return false;[\s\S]*dict->width\(\), dict->height\(\), dict->depthOrArrayLayers\(\)[\s\S]*kUnsignedLongEnforceRangeSequence[\s\S]*case 1:[\s\S]*case 2:[\s\S]*case 3:[\s\S]*default:[\s\S]*return false;[\s\S]*return false;[\s\S]*ConvertToDawn\([\s\S]*if \(ConvertCommonExtent3D\(in->size\(\), &out->size\)\) \{[\s\S]*return true;[\s\S]*return ConvertToDawn\(in->size\(\), &out->size, device, exception_state\)' `
  "WebGPU texture creation has a common GPUExtent3D size conversion fast path while preserving deprecated-depth warnings and invalid-sequence fallback"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_texture\.h[\s\S]*GPUTexture\(GPUDevice\* device,[\s\S]*wgpu::Texture texture,[\s\S]*wgpu::TextureDimension dimension,[\s\S]*wgpu::TextureViewDimension texture_binding_view_dimension,[\s\S]*wgpu::TextureFormat format,[\s\S]*wgpu::TextureUsage usage,[\s\S]*const String& label\);' `
  "WebGPU texture header exposes a descriptor-metadata-backed wrapper constructor"

Assert-Contains `
  $WebGpuTextureSourceText `
  'ResolveTextureBindingViewDimension\([\s\S]*kCoreFeaturesAndLimits[\s\S]*TextureViewDimension::Undefined[\s\S]*TextureDimension::e2D[\s\S]*TextureViewDimension::e2DArray[\s\S]*GetTextureBindingViewDimensionFromChain\([\s\S]*chain->sType == wgpu::SType::TextureBindingViewDimension[\s\S]*textureBindingViewDimension[\s\S]*GPUTexture::Create\(GPUDevice\* device,[\s\S]*ResolveTextureBindingViewDimension\([\s\S]*dawn_desc\.dimension[\s\S]*dawn_desc\.size\.depthOrArrayLayers[\s\S]*MakeGarbageCollected<GPUTexture>\([\s\S]*CreateTexture\(&dawn_desc\),[\s\S]*dawn_desc\.dimension,[\s\S]*texture_binding_view_dimension,[\s\S]*dawn_desc\.format,[\s\S]*dawn_desc\.usage[\s\S]*GPUTexture::Create\(GPUDevice\* device,[\s\S]*const wgpu::TextureDescriptor\* desc\)[\s\S]*GetTextureBindingViewDimensionFromChain\(desc->nextInChain\)[\s\S]*CreateTexture\(desc\),[\s\S]*desc->dimension,[\s\S]*texture_binding_view_dimension,[\s\S]*desc->format,[\s\S]*desc->usage[\s\S]*GPUTexture::GPUTexture\([\s\S]*wgpu::TextureDimension dimension[\s\S]*texture_binding_view_dimension_\(texture_binding_view_dimension\)[\s\S]*format_\(format\)[\s\S]*usage_\(usage\)' `
  "WebGPU texture creation wrapper reuses known descriptor metadata instead of querying Dawn texture properties after createTexture"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_canvas_context\.cc[\s\S]*copy_to_swap_texture_required_[\s\S]*texture_ = GPUTexture::Create\(device_, &texture_descriptor_\);[\s\S]*SetBeforeDestroyCallback' `
  "WebGPU canvas copy-to-swap texture creation reuses the descriptor-backed texture wrapper fast path"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_texture\.cc[\s\S]*IsDefaultTextureViewDescriptor\([\s\S]*label\(\)\.empty\(\)[\s\S]*!webgpu_desc->hasFormat\(\)[\s\S]*!webgpu_desc->hasDimension\(\)[\s\S]*!webgpu_desc->hasUsage\(\)[\s\S]*baseMipLevel\(\) == 0[\s\S]*!webgpu_desc->hasMipLevelCount\(\)[\s\S]*baseArrayLayer\(\) == 0[\s\S]*!webgpu_desc->hasArrayLayerCount\(\)[\s\S]*V8GPUTextureAspect::Enum::kAll[\s\S]*swizzle\(\) == "rgba"[\s\S]*ValidateSwizzle[\s\S]*if \(swizzle == "rgba"\)[\s\S]*GPUTexture::createView[\s\S]*IsDefaultTextureViewDescriptor\(webgpu_desc\)[\s\S]*GetHandle\(\)\.CreateView\(\)[\s\S]*ValidateTextureFormatUsage' `
  "WebGPU texture createView fast-paths exactly-default view descriptors while keeping the existing non-default validation path"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_render_bundle_encoder\.cc[\s\S]*constexpr size_t kViewerStackRenderBundleColorFormatLimit = 4;[\s\S]*std::array<wgpu::TextureFormat, kViewerStackRenderBundleColorFormatLimit>[\s\S]*color_formats_count <= kViewerStackRenderBundleColorFormatLimit[\s\S]*color_formats_input\[i\]\.has_value\(\)[\s\S]*AsDawnEnum\(color_formats_input\[i\]\.value\(\)\)[\s\S]*static_cast<wgpu::TextureFormat>\(0\)[\s\S]*dawn_color_formats = stack_color_formats\.data\(\)[\s\S]*color_formats =[\s\S]*AsDawnEnum<wgpu::TextureFormat>\(webgpu_desc->colorFormats\(\)\)[\s\S]*dawn_color_formats = color_formats\.data\(\)[\s\S]*\.colorFormats = dawn_color_formats' `
  "WebGPU render-bundle encoder avoids heap conversion for common small nullable color-format lists and keeps the heap fallback"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'GPURenderBundleEncoder::finish[\s\S]*webgpu_desc->label\(\)\.empty\(\)[\s\S]*GetHandle\(\)\.Finish\(nullptr\)[\s\S]*GetHandle\(\)\.Finish\(&dawn_desc\)' `
  "WebGPU render-bundle finish uses Dawn's null/default descriptor path for unlabeled render bundles"

Assert-Contains `
  $WebGpuRenderBundleSourceText `
  'GPURenderBundleEncoder::setBindGroup\(\s*uint32_t index,\s*GPUBindGroup\* bindGroup[\s\S]*dynamicOffsets\.empty\(\)[\s\S]{0,180}setBindGroup\(index, bindGroup\);[\s\S]*dynamic_offsets_data_start == 0 && dynamic_offsets_data_length == 0[\s\S]{0,180}setBindGroup\(index, bind_group\);[\s\S]*ValidateSetBindGroupDynamicOffsets[\s\S]*data_span\.empty\(\)[\s\S]{0,180}setBindGroup\(index, bind_group\);' `
  "WebGPU render-bundle bind-group calls fast-path explicit empty typed-array dynamic offsets before validation"

Assert-Contains `
  $WebGpuComputePassSourceText `
  'GPUComputePassEncoder::setBindGroup\(\s*uint32_t index,\s*GPUBindGroup\* bindGroup[\s\S]*dynamicOffsets\.empty\(\)[\s\S]{0,180}setBindGroup\(index, bindGroup\);[\s\S]*dynamic_offsets_data_start == 0 && dynamic_offsets_data_length == 0[\s\S]{0,180}setBindGroup\(index, bind_group\);[\s\S]*ValidateSetBindGroupDynamicOffsets[\s\S]*data_span\.empty\(\)[\s\S]{0,180}setBindGroup\(index, bind_group\);' `
  "WebGPU compute-pass bind-group calls fast-path explicit empty typed-array dynamic offsets before validation"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'GPURenderPassEncoder::setBindGroup\(\s*uint32_t index,\s*GPUBindGroup\* bindGroup[\s\S]*dynamicOffsets\.empty\(\)[\s\S]{0,180}setBindGroup\(index, bindGroup\);[\s\S]*dynamic_offsets_data_start == 0 && dynamic_offsets_data_length == 0[\s\S]{0,180}setBindGroup\(index, bind_group\);[\s\S]*ValidateSetBindGroupDynamicOffsets[\s\S]*data_span\.empty\(\)[\s\S]{0,180}setBindGroup\(index, bind_group\);' `
  "WebGPU render-pass bind-group calls fast-path explicit empty typed-array dynamic offsets before validation"

Assert-Contains `
  $WebGpuRenderPassSourceText `
  'void GPURenderPassEncoder::setBindGroup\(\s*uint32_t index,\s*DawnObject<wgpu::BindGroup>\* bindGroup\)[\s\S]*GetHandle\(\)\.SetBindGroup\(index, handle, 0, nullptr\);' `
  "WebGPU render-pass direct bind-group overload passes explicit null dynamic-offset data"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_render_pass_encoder\.cc[\s\S]*constexpr wtf_size_t kViewerStackRenderBundleExecuteLimit = 4;[\s\S]*GPURenderPassEncoder::executeBundles[\s\S]*std::array<wgpu::RenderBundle, kViewerStackRenderBundleExecuteLimit>[\s\S]*bundle_count <= kViewerStackRenderBundleExecuteLimit[\s\S]*AsDawnType\(bundles\[i\]\.Get\(\)\)[\s\S]*UNSAFE_TODO\(stack_bundles\[i\]\) = \{\};[\s\S]*dawn_bundles_data = stack_bundles\.data\(\)[\s\S]*dawn_bundles = AsDawnType\(bundles\)[\s\S]*GetHandle\(\)\.ExecuteBundles\(bundle_count, dawn_bundles_data\)' `
  "WebGPU render pass executeBundles avoids heap conversion for common small bundle lists and keeps nullable entries plus heap fallback"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::WriteBufferImpl[\s\S]*size_t data_byte_offset = 0;[\s\S]*size_t write_byte_size = 0;[\s\S]*data_element_offset == 0 && !data_element_count\.has_value\(\)[\s\S]*write_byte_size = data\.size\(\);[\s\S]*data\.subspan\(data_byte_offset, write_byte_size\)' `
  "WebGPU writeBuffer has a spec-equivalent full-span fast path for common Three.js queue writes"

Assert-Contains `
  $WebGpuPatchText `
  'bool ComputeCommonWriteBufferRange\([\s\S]*data_element_offset != 0[\s\S]*!data_element_count\.has_value\(\)[\s\S]*data\.size\(\) % 4 != 0[\s\S]*\*write_byte_size = data\.size\(\)[\s\S]*write_element_count > element_count[\s\S]*static_cast<size_t>\(write_element_count\) \* data_bytes_per_element[\s\S]*write_byte_size_value % 4 != 0[\s\S]*\*data_byte_offset = 0;[\s\S]*\*write_byte_size = write_byte_size_value' `
  "WebGPU writeBuffer has a common zero-offset explicit-count range fast path with fallback for invalid ranges"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::WriteBufferImpl[\s\S]*ComputeCommonWriteBufferRange\(data, data_bytes_per_element,[\s\S]*data_element_offset, data_element_count,[\s\S]*&data_byte_offset, &write_byte_size\)[\s\S]*data_element_offset == 0 && !data_element_count\.has_value\(\)[\s\S]*Data offset is too large[\s\S]*Number of bytes to write is too large[\s\S]*data\.subspan\(data_byte_offset, write_byte_size\)' `
  "WebGPU writeBuffer uses the common range fast path before falling back to existing exception-preserving validation"

Assert-Contains `
  $WebGpuPatchText `
  'bool EstimateCommonWriteTextureBytesUpperBound\([\s\S]*size_t\* bytes_upper_bound[\s\S]*DCHECK\(bytes_upper_bound\)[\s\S]*extent\.depthOrArrayLayers != 1[\s\S]*wgpu::TextureFormat::RGBA8Unorm[\s\S]*wgpu::TextureFormat::BGRA8Unorm[\s\S]*if \(!row_bytes\.IsValid\(\)\) \{[\s\S]*return false;[\s\S]*row_bytes\.ValueOrDie\(\)[\s\S]*layout\.bytesPerRow == wgpu::kCopyStrideUndefined[\s\S]*\*bytes_upper_bound = row_bytes_value;[\s\S]*required_bytes \+= row_bytes_value[\s\S]*if \(!required_bytes\.IsValid\(\)\) \{[\s\S]*return false;[\s\S]*\*bytes_upper_bound = required_bytes\.ValueOrDie\(\)' `
  "WebGPU writeTexture has a common 4-byte single-layer byte-count fast path with bool fallback for unsupported layouts and overflows"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::WriteTextureImpl[\s\S]*size_t data_size_upper_bound = 0;[\s\S]*if \(!EstimateCommonWriteTextureBytesUpperBound\([\s\S]*&data_size_upper_bound[\s\S]*EstimateWriteTextureBytesUpperBound\(' `
  "WebGPU writeTexture uses the common byte-count fast path before falling back to the generic helper"

Assert-Contains `
  $WebGpuPatchText `
  'bool ConvertCommonWriteTextureLayout\([\s\S]*webgpu_layout->offset\(\) != 0[\s\S]*!webgpu_layout->hasBytesPerRow\(\)[\s\S]*webgpu_layout->hasRowsPerImage\(\)[\s\S]*bytes_per_row == wgpu::kCopyStrideUndefined[\s\S]*\.bytesPerRow = bytes_per_row[\s\S]*\.rowsPerImage = wgpu::kCopyStrideUndefined' `
  "WebGPU writeTexture has a common layout conversion fast path for offset-zero rowsPerImage-omitted DataTexture uploads"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::WriteTextureImpl[\s\S]*viewer_state\.skip_write_texture_layout_validation[\s\S]*ConvertTrustedTexelCopyBufferLayout\(data_layout\)[\s\S]*ConvertCommonWriteTextureLayout\(data_layout, &dawn_data_layout\)[\s\S]*ValidateTexelCopyBufferLayout\(data_layout, &dawn_data_layout\)' `
  "WebGPU writeTexture common layout conversion falls back to trusted and generic validation paths"

Assert-Contains `
  $WebGpuPatchText `
  'bool ConvertCommonExtent3D\([\s\S]*GetContentType\(\)[\s\S]*kGPUExtent3DDict[\s\S]*dict->hasDepth\(\)[\s\S]*return false;[\s\S]*dict->width\(\), dict->height\(\), dict->depthOrArrayLayers\(\)[\s\S]*kUnsignedLongEnforceRangeSequence[\s\S]*sequence\.size\(\)[\s\S]*case 1:[\s\S]*case 2:[\s\S]*case 3:[\s\S]*default:[\s\S]*return false;[\s\S]*return false;[\s\S]*bool ConvertCommonOrigin2D' `
  "WebGPU queue has a common GPUExtent3D conversion fast path while preserving deprecated-depth warnings and invalid-sequence fallback"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::WriteTextureImpl[\s\S]*ConvertCommonExtent3D\(write_size, &dawn_write_size\)[\s\S]*ConvertToDawn\(write_size, &dawn_write_size, device_,[\s\S]*exception_state\)' `
  "WebGPU writeTexture uses the common GPUExtent3D fast path before generic conversion"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::copyExternalImageToTexture[\s\S]*ConvertCommonExtent3D\(copy_size, &dawn_copy_size\)[\s\S]*ConvertToDawn\(copy_size, &dawn_copy_size, device_, exception_state\)' `
  "WebGPU copyExternalImage uses the common GPUExtent3D fast path before generic conversion"

Assert-Contains `
  $WebGpuPatchText `
  'dawn_conversions\.cc[\s\S]*bool ConvertCommonOrigin3D\(const V8GPUOrigin3D\* in, wgpu::Origin3D\* out\)[\s\S]*kGPUOrigin3DDict[\s\S]*dict->x\(\), dict->y\(\), dict->z\(\)[\s\S]*kUnsignedLongEnforceRangeSequence[\s\S]*case 0:[\s\S]*case 1:[\s\S]*case 2:[\s\S]*case 3:[\s\S]*default:[\s\S]*return false;[\s\S]*ConvertToDawn\(const GPUTexelCopyTextureInfo\* in,[\s\S]*if \(!in->hasOrigin\(\)\) \{[\s\S]*return true;[\s\S]*ConvertCommonOrigin3D\(in->origin\(\), &out->origin\)[\s\S]*return true;[\s\S]*return ConvertToDawn\(in->origin\(\), &out->origin, exception_state\);' `
  "WebGPU texel-copy texture conversion skips GPUOrigin3D union conversion when origin is default or a common valid explicit origin while preserving invalid-sequence fallback"

Assert-Contains `
  $WebGpuPatchText `
  'bool ConvertCommonOrigin2D\(const V8GPUOrigin2D\* in, wgpu::Origin2D\* out\)[\s\S]*kGPUOrigin2DDict[\s\S]*dict->x\(\), dict->y\(\)[\s\S]*kUnsignedLongEnforceRangeSequence[\s\S]*case 0:[\s\S]*case 1:[\s\S]*case 2:[\s\S]*default:[\s\S]*return false;' `
  "WebGPU queue has a common GPUOrigin2D conversion fast path while preserving invalid-sequence fallback"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::copyExternalImageToTexture[\s\S]*wgpu::Origin2D origin_in_external_image = \{\};[\s\S]*copyImage->hasOrigin\(\)[\s\S]*ConvertCommonOrigin2D\(copyImage->origin\(\),[\s\S]*&origin_in_external_image\)[\s\S]*ConvertToDawn\(copyImage->origin\(\), &origin_in_external_image,[\s\S]*exception_state\)' `
  "WebGPU copyExternalImage skips GPUOrigin2D union conversion when external image origin is default or a common valid explicit origin while preserving invalid-sequence fallback"

Assert-Contains `
  $WebGpuPatchText `
  'GetSourceImageSubrect[\s\S]*origin\.x == 0 && origin\.y == 0[\s\S]*width == source_image_rect\.width\(\)[\s\S]*height == source_image_rect\.height\(\)[\s\S]*return source_image_rect;' `
  "WebGPU copyExternalImage has a full-source subrect fast path for common Three.js CanvasTexture uploads"

Assert-Contains `
  $WebGpuPatchText `
  'ValidateAndConvertCopyTextureColorSpace\([\s\S]*v8_color_space\.AsEnum\(\) == V8PredefinedColorSpace::Enum::kSRGB[\s\S]*color_space = PredefinedColorSpace::kSRGB;[\s\S]*return ValidateAndConvertColorSpace\(v8_color_space, color_space,[\s\S]*exception_state\);' `
  "WebGPU copy texture color-space conversion fast-paths sRGB while preserving existing validation for non-sRGB destinations"

Assert-Contains `
  $WebGpuPatchText `
  'CreateCopyTextureForBrowserOptions\([\s\S]*ColorSpaceConversionConstants\* color_space_conversion_constants,[\s\S]*bool skip_color_conversion[\s\S]*if \(skip_color_conversion\) \{[\s\S]*options\.flipY = flipY;[\s\S]*return options;[\s\S]*\}[\s\S]*image->GetColorSpace\(\)' `
  "WebGPU copyExternalImage color-conversion setup skip returns before source color-space work"

Assert-Contains `
  $WebGpuPatchText `
  'CreateCopyTextureForBrowserOptions[\s\S]*gfx_src_color_space == gfx_dst_color_space[\s\S]*options\.flipY = flipY;[\s\S]*return options;[\s\S]*GetColorSpaceConversionConstants\(gfx_src_color_space,[\s\S]*gfx_dst_color_space\)' `
  "WebGPU copyExternalImage avoids color-conversion constant setup when source and destination color spaces already match"

Assert-Contains `
  $WebGpuPatchText `
  'std::optional<PaintImage> paint_image;[\s\S]*auto get_paint_image = \[\&\]\(\) -> const PaintImage& \{[\s\S]*paint_image\.emplace\(image->PaintImageForCurrentFrame\(\)\);[\s\S]*auto get_source_image_info = \[\&\]\(\) \{[\s\S]*return get_paint_image\(\)\.GetSkImageInfo\(\);[\s\S]*\};' `
  "WebGPU copyExternalImage lazily materializes PaintImage only for paths that need Sk image metadata"

Assert-Contains `
  $WebGpuPatchText `
  'get_paint_image\(\)\.readPixels\(' `
  "WebGPU CPU fallback readPixels uses the lazy PaintImage accessor after PaintImage became optional"

Assert-NotContains `
  $WebGpuQueueSourceText `
  'paint_image\.readPixels\(' `
  "WebGPU patch does not leave an optional PaintImage compile error in the CPU fallback path"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::CopyFromCanvasSourceImage[\s\S]*image->Size\(\)\.width\(\)[\s\S]*CreateCopyTextureForBrowserOptions\([\s\S]*image, dst_color_space, dst_premultiplied_alpha, flipY,[\s\S]*viewer_state\.skip_copy_external_image_color_conversion' `
  "WebGPU existing shared-image upload path avoids eager SkImageInfo/PaintImage setup for CopyTextureForBrowser options"

Assert-NotContains `
  $WebGpuAddedCode `
  'get_paint_image_for_color_conversion' `
  "WebGPU copyExternalImage no longer creates PaintImage only to resolve color conversion options"

Assert-Contains `
  $WebGpuPatchText `
  'CHECK\(!get_paint_image\(\)\.IsTextureBacked\(\)\);' `
  "WebGPU CPU fallback still materializes PaintImage before fallback-only texture-backed checks"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::CopyFromCanvasSourceImage[\s\S]*CreateCopyTextureForBrowserOptions\([\s\S]*viewer_state\.skip_copy_external_image_color_conversion' `
  "WebGPU CanvasTexture uploads pass the cached trusted color-conversion setup skip to CopyTextureForBrowser options"

Assert-Contains `
  $WebGpuQueueSourceText `
  '#include "third_party/blink/renderer/modules/webgpu/viewer_webgpu_experiment_switches\.h"[\s\S]*GPUQueue::CopyFromCanvasSourceImage[\s\S]*webgpu_viewer_experiments::ShouldSkipCommandLabels\(\)' `
  "WebGPU queue source reuses the shared trusted command-label skip helper for internal CanvasTexture CPU-fallback encoders"

Assert-Contains `
  $WebGpuQueueSourceText `
  'GPUQueue::CopyFromCanvasSourceImage[\s\S]*if \(webgpu_viewer_experiments::ShouldSkipCommandLabels\(\)\) \{[\s\S]*CreateCommandEncoder\(\)[\s\S]*\} else \{[\s\S]*GPUQueue::CopyFromCanvasSourceImage[\s\S]*CreateCommandEncoder\([\s\S]*&command_encoder_desc' `
  "WebGPU CanvasTexture CPU fallback omits internal command encoder labels only under the trusted command-label skip"

Assert-Contains `
  $WebGpuPatchText `
  'viewer_webgpu_experiment_switches\.h[\s\S]*kViewerSkipWebGPUCommandLabelsSwitch\[\][\s\S]*"viewer-skip-webgpu-command-labels"[\s\S]*skip_command_labels[\s\S]*ShouldSkipCommandLabels\(\)' `
  "WebGPU shared trusted experiment state exposes the command-label skip to hot inline debug marker paths"

foreach ($HeaderCase in @(
    [pscustomobject]@{ Text = $WebGpuCommandEncoderHeaderText; Description = "command encoder" },
    [pscustomobject]@{ Text = $WebGpuRenderPassHeaderText; Description = "render pass encoder" },
    [pscustomobject]@{ Text = $WebGpuRenderBundleHeaderText; Description = "render bundle encoder" },
    [pscustomobject]@{ Text = $WebGpuComputePassHeaderText; Description = "compute pass encoder" }
  )) {
  Assert-Contains `
    $HeaderCase.Text `
    'pushDebugGroup\(String groupLabel\) \{[\s\S]*ShouldSkipCommandLabels\(\)[\s\S]*return;[\s\S]*groupLabel\.Utf8\(\)[\s\S]*PushDebugGroup\(label\.c_str\(\)\)' `
    "WebGPU $($HeaderCase.Description) skips debug group push label conversion behind command-label skip"

  Assert-Contains `
    $HeaderCase.Text `
    'popDebugGroup\(\) \{[\s\S]*ShouldSkipCommandLabels\(\)[\s\S]*return;[\s\S]*PopDebugGroup\(\)' `
    "WebGPU $($HeaderCase.Description) skips debug group pop to keep skipped push/pop balanced"

  Assert-Contains `
    $HeaderCase.Text `
    'insertDebugMarker\(String markerLabel\) \{[\s\S]*ShouldSkipCommandLabels\(\)[\s\S]*return;[\s\S]*markerLabel\.Utf8\(\)[\s\S]*InsertDebugMarker\(label\.c_str\(\)\)' `
    "WebGPU $($HeaderCase.Description) skips debug marker label conversion behind command-label skip"
}

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::copyExternalImageToTexture[\s\S]*viewer_state\.skip_copy_external_image_color_space_validation[\s\S]*color_space = PredefinedColorSpace::kSRGB;[\s\S]*ValidateAndConvertCopyTextureColorSpace\([\s\S]*destination->colorSpace\(\)' `
  "WebGPU copyExternalImageToTexture color-space validation skip assumes sRGB only behind cached trusted viewer state while default sRGB still uses the safe fast path"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::copyExternalImageToTexture[\s\S]*viewer_state\.skip_copy_external_image_dest_validation[\s\S]*IsValidDestinationTexture\(destination, dawn_destination,[\s\S]*skip_destination_texture_validation\)' `
  "WebGPU copyExternalImageToTexture destination texture validation skip is guarded by cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::copyExternalImageToTexture[\s\S]*GetExternalSourceFromExternalImage\([\s\S]*viewer_state\.skip_copy_external_image_source_validation' `
  "WebGPU copyExternalImageToTexture source validation skip is guarded by cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::copyExternalImageToTexture[\s\S]*if \(!viewer_state\.skip_copy_external_image_copy_size_validation\) \{[\s\S]*copyRectOutOfBounds[\s\S]*Copy rect is out of bounds of external image[\s\S]*Copy depth is out of bounds of external image[\s\S]*CopyExternalImageToTexture\(\): It is a noop copy' `
  "WebGPU copyExternalImageToTexture copy-size validation skip bypasses only bounds/depth/no-op checks behind cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'GetExternalSourceFromExternalImage\([\s\S]*bool skip_source_validation[\s\S]*if \(!skip_source_validation\) \{[\s\S]*IsNeutered\(\)[\s\S]*IsPlaceholder\(\)[\s\S]*WouldTaintOrigin\(\)[\s\S]*CopyExternalImageToTexture doesn''t support canvas without rendering' `
  "WebGPU copyExternalImage source validation skip bypasses only trusted source checks behind the explicit source-validation flag"

Assert-Contains `
  $WebGpuAddedCode `
  'constexpr char kViewerSkipWebGPUWriteTextureLayoutValidationSwitch\[\]\s*=\s*"viewer-skip-webgpu-write-texture-layout-validation";' `
  "WebGPU writeTexture layout validation skip defines an explicit trusted viewer switch"

Assert-Contains `
  $WebGpuPatchText `
  'ConvertTrustedTexelCopyBufferLayout\([\s\S]*webgpu_layout->offset\(\)[\s\S]*webgpu_layout->hasBytesPerRow\(\)[\s\S]*wgpu::kCopyStrideUndefined[\s\S]*webgpu_layout->hasRowsPerImage\(\)' `
  "WebGPU writeTexture layout validation skip still converts offset, bytesPerRow, rowsPerImage, and undefined strides"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::WriteTextureImpl[\s\S]*viewer_state\.skip_write_texture_layout_validation[\s\S]*ConvertTrustedTexelCopyBufferLayout\(data_layout\)[\s\S]*ValidateTexelCopyBufferLayout\(data_layout, &dawn_data_layout\)' `
  "WebGPU writeTexture layout validation skip bypasses only Blink layout validation behind cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'GPUQueue::WriteTextureImpl[\s\S]*const ViewerWebGPUExperimentState& viewer_state =[\s\S]*GetViewerWebGPUExperimentState\(\);[\s\S]*viewer_state\.skip_write_texture_layout_validation[\s\S]*viewer_state\.trace_queue[\s\S]*viewer_state\.defer_queue_flush' `
  "WebGPU writeTexture hot path reads cached trusted viewer state once and reuses it through validation, tracing, and queue flush handling"

Assert-Contains `
  $WebGpuQueueSourceText `
  'GPUQueue::CopyElementImageToTextureInternal[\s\S]*ValidateAndConvertCopyTextureColorSpace\([\s\S]*destination->colorSpace\(\), color_space,[\s\S]*IsValidDestinationTexture\(destination, dawn_destination,[\s\S]*/\*skip_texture_validation=\*/\s*false\)' `
  "WebGPU element-image texture path keeps non-sRGB color-space and texture validation enabled outside the CanvasTexture experiment"

Assert-Contains `
  $WebGpuPatchText `
  'IsValidDestinationTexture\([\s\S]*ConvertToDawn\(destination,[\s\S]*dawn_destination[\s\S]*exception_state\)[\s\S]*if \(skip_texture_validation\) \{[\s\S]*return true;[\s\S]*\}[\s\S]*destination->texture\(\)->Format\(\)' `
  "WebGPU copyExternalImage destination skip preserves destination conversion before bypassing texture validation"

Assert-Contains `
  $WebGpuAddedCode `
  'struct ViewerWebGPUCanvasExperimentState \{[\s\S]*skip_canvas_texture_validation[\s\S]*skip_canvas_memory_accounting[\s\S]*skip_use_counters' `
  "WebGPU canvas source-backed experiment patch stores validation, memory-accounting, and use-counter decisions in cached state"

Assert-Contains `
  $WebGpuAddedCode `
  'ViewerWebGPUCanvasExperimentState BuildViewerWebGPUCanvasExperimentState\(\) \{[\s\S]*IsTrustedViewerApp\(command_line\)[\s\S]*kViewerSkipWebGPUCanvasTextureValidationSwitch[\s\S]*kViewerSkipWebGPUCanvasMemoryAccountingSwitch[\s\S]*kViewerSkipWebGPUUseCountersSwitch' `
  "WebGPU canvas experiment state is built from trusted viewer gates and explicit switches"

Assert-Contains `
  $WebGpuPatchText `
  'GPUCanvasContext::getCurrentTexture[\s\S]*viewer_state\.skip_canvas_texture_validation[\s\S]*ValidateTextureDescriptor\(&texture_descriptor_\)' `
  "WebGPU canvas getCurrentTexture texture descriptor validation skip is guarded by cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'GPUCanvasContext::getCurrentTexture[\s\S]*if \(!viewer_state\.skip_canvas_memory_accounting\)[\s\S]*Host\(\)->UpdateMemoryUsage\(\)' `
  "WebGPU canvas getCurrentTexture memory accounting skip is guarded by cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'GPUCanvasContext::getCurrentTexture[\s\S]*const ViewerWebGPUCanvasExperimentState& viewer_state[\s\S]*if \(!viewer_state\.skip_use_counters\)[\s\S]*WebFeature::kWebGPUCanvasContextGetCurrentTexture' `
  "WebGPU canvas getCurrentTexture use-counter call is guarded by cached trusted viewer state"

Assert-Contains `
  $WebGpuPatchText `
  'gpu_canvas_context\.cc[\s\S]*#include "third_party/blink/renderer/modules/webgpu/viewer_webgpu_experiment_switches\.h"[\s\S]*StringFromNullableUtf8Label\(const char\* label\)[\s\S]*!label \|\| !label\[0\][\s\S]*ShouldSkipResourceLabels\(\)[\s\S]*String::FromUtf8\(label\)[\s\S]*GPUCanvasContext::getCurrentTexture[\s\S]*StringFromNullableUtf8Label\(swap_texture_descriptor_\.label\)[\s\S]*texture_ = GPUTexture::Create\(device_, &texture_descriptor_\);' `
  "WebGPU canvas getCurrentTexture skips nullable, empty, and trusted resource-label UTF-8 conversion for the swap wrapper and routes copy-to-swap labels through the descriptor-backed texture wrapper"

Assert-Contains `
  $WebGpuTextureSourceText `
  'StringFromNullableUtf8Label\(const char\* label\)[\s\S]*!label \|\| !label\[0\][\s\S]*ShouldSkipResourceLabels\(\)[\s\S]*String::FromUtf8\(label\)' `
  "WebGPU texture descriptor wrappers skip nullable, empty, and trusted resource-label UTF-8 conversion"

$NormalizedWebGpuPatchText = $WebGpuPatchText -replace "`r`n", "`n"
$TexturePatchSection = Get-TextSection `
  $NormalizedWebGpuPatchText `
  "diff --git a/third_party/blink/renderer/modules/webgpu/gpu_texture.cc" `
  "diff --git a/third_party/blink/renderer/modules/webgpu/viewer_webgpu_experiment_switches.h" `
  "WebGPU texture patch section"
$NormalizedWebGpuTextureSource = $WebGpuTextureSourceText -replace "`r`n", "`n"
$TextureDescriptorCreateSection = Get-TextSection `
  $NormalizedWebGpuTextureSource `
  "GPUTexture* GPUTexture::Create(GPUDevice* device,`n                               const wgpu::TextureDescriptor* desc)" `
  "// static" `
  "GPUTexture descriptor-backed Create overload"

Assert-Contains `
  $TexturePatchSection `
  'GPUTexture::Create\(GPUDevice\* device,[\s\S]*device->GetHandle\(\)\.CreateTexture\(desc\),[\s\S]*StringFromNullableUtf8Label\(desc->label\)' `
  "WebGPU texture creation wrappers skip nullable empty-label UTF-8 conversion for Dawn descriptors"

Assert-Contains `
  $TextureDescriptorCreateSection `
  "StringFromNullableUtf8Label\(desc->label\)" `
  "WebGPU descriptor-backed texture creation uses the descriptor label and does not reference IDL descriptor state"

Assert-NotContains `
  $TextureDescriptorCreateSection `
  "webgpu_desc->label\(\)" `
  "WebGPU descriptor-backed texture creation references out-of-scope webgpu_desc"

Assert-Contains `
  $WebGpuPatchText `
  'GPUTexture::CreateError\(GPUDevice\* device,[\s\S]*device->GetHandle\(\)\.CreateErrorTexture\(desc\),[\s\S]*StringFromNullableUtf8Label\(desc->label\)' `
  "WebGPU error texture wrappers skip nullable empty-label UTF-8 conversion for Dawn descriptors"

Assert-Contains `
  $WebGpuAddedCode `
  'void TraceViewerWebGPUQueueFlushDeferred\(const char\* operation\) \{[\s\S]*if \(!GetViewerWebGPUExperimentState\(\)\.trace_queue\)[\s\S]*return;[\s\S]*GPUQueue::ViewerDeferredEnsureFlush' `
  "WebGPU queue attribution traces are gated by the explicit diagnostic switch"

Write-Host "Viewer patch trusted-content gates require viewer mode and are statically verified across the patch series."

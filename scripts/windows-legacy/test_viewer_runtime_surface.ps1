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
    throw "Missing $Description. Pattern: $Pattern"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -match $Pattern) {
    throw "Unexpected $Description. Pattern: $Pattern"
  }
}

$Main = Read-RepoFile "viewer\src\main.js"
$Metrics = Read-RepoFile "viewer\src\metrics.js"
$Renderers = Read-RepoFile "viewer\src\renderers.js"
$Scenes = Read-RepoFile "viewer\src\scenes.js"
$Runner = Read-RepoFile "scripts\run_benchmark.mjs"

Assert-Contains $Main "requestAnimationFrame\s*\(" "requestAnimationFrame frame loop"
Assert-Contains $Main "performance\.now\s*\(" "performance.now timing"
Assert-Contains $Main "addEventListener\s*\(\s*['""]resize['""]" "resize event handling"
Assert-Contains $Main "addEventListener\s*\(\s*['""]pointermove['""]" "basic pointer input handling"
Assert-Contains $Main "queueInstrumentation:\s*booleanParam\(params,\s*['""]queueInstrumentation['""]" "WebGPU queue instrumentation query flag"
Assert-Contains $Main "commandEncoderInstrumentation:\s*booleanParam\(params,\s*['""]commandEncoderInstrumentation['""]" "WebGPU command-encoder instrumentation query flag"
Assert-Contains $Main "bindGroupInstrumentation:\s*booleanParam\(params,\s*['""]bindGroupInstrumentation['""]" "WebGPU bind-group instrumentation query flag"
Assert-Contains $Main "pipelineStateInstrumentation:\s*booleanParam\(params,\s*['""]pipelineStateInstrumentation['""]" "WebGPU pipeline-state instrumentation query flag"
Assert-Contains $Main "bufferStateInstrumentation:\s*booleanParam\(params,\s*['""]bufferStateInstrumentation['""]" "WebGPU buffer-state instrumentation query flag"
Assert-Contains $Main "renderStateInstrumentation:\s*booleanParam\(params,\s*['""]renderStateInstrumentation['""]" "WebGPU render-state instrumentation query flag"
Assert-Contains $Main "immediateInstrumentation:\s*booleanParam\(params,\s*['""]immediateInstrumentation['""]" "WebGPU immediate instrumentation query flag"
Assert-Contains $Main "showHud:\s*booleanParam\(params,\s*['""]showHud['""],\s*!benchmark\)" "benchmark HUD query flag defaults off during benchmarks"
Assert-Contains $Main "hud\.hidden\s*=\s*!options\.showHud" "benchmark HUD visibility gate"
Assert-Contains $Main "if \(!options\.showHud\) return;" "benchmark HUD DOM update skip"
Assert-Contains $Main "installWebGpuQueueInstrumentation" "WebGPU queue upload/submit instrumentation helper"
Assert-Contains $Main "rendererBundle\.renderer\?\.backend\?\.device\?\.queue" "Three.js WebGPU device queue access"
Assert-Contains $Main "function\s+bytesPerElementOf\s*\(" "WebGPU queue writeBuffer typed-array byte-size helper"
Assert-Contains $Main "value\.BYTES_PER_ELEMENT" "WebGPU queue writeBuffer byte estimator reads typed-array element size"
Assert-Contains $Main "explicitElementCount \* bytesPerElement" "WebGPU queue writeBuffer explicit element count is converted to bytes"
Assert-Contains $Main "dataElementOffset \* bytesPerElement" "WebGPU queue writeBuffer element offset is converted to bytes"
Assert-Contains $Main "function\s+estimateSubmitCommandBufferCount\s*\(" "WebGPU queue submit command-buffer count helper"
Assert-Contains $Main "webgpu_queue_submit_small_batch_count" "WebGPU queue submit small-batch attribution field"
Assert-Contains $Main "commandBufferCount > 0 && commandBufferCount <= 4" "WebGPU submit attribution matches Chromium small-batch stack limit"
Assert-Contains $Main "summarizeWriteTextureDescriptor" "WebGPU writeTexture descriptor-shape attribution helper"
Assert-Contains $Main "webgpu_queue_write_texture_common_layout_count" "WebGPU writeTexture common-layout attribution field"
Assert-Contains $Main "summarizeOrigin2DShape" "WebGPU copyExternalImage origin-shape attribution helper"
Assert-Contains $Main "summarizeCopyExternalImageDescriptor" "WebGPU copyExternalImage descriptor-shape attribution helper"
Assert-Contains $Main "webgpu_queue_copy_external_image_common_origin_count" "WebGPU copyExternalImage common-origin attribution field"
Assert-Contains $Main "webgpu_queue_copy_external_image_explicit_common_origin_count" "WebGPU copyExternalImage explicit common-origin attribution field"
Assert-Contains $Main "webgpu_queue_copy_external_image_full_source_count" "WebGPU copyExternalImage full-source attribution field"
Assert-Contains $Main "installWebGpuCommandEncoderInstrumentation" "WebGPU command-encoder copy attribution helper"
Assert-Contains $Main "device\?\.createCommandEncoder" "WebGPU command-encoder creation attribution hook"
Assert-Contains $Main "summarizeRenderPassDescriptor" "WebGPU command-encoder render-pass descriptor attribution helper"
Assert-Contains $Main "webgpu_command_encoder_render_pass_clear_value_dict_count" "WebGPU command-encoder render-pass clearValue dict attribution field"
Assert-Contains $Main "copyTextureToBuffer" "WebGPU command-encoder copyTextureToBuffer attribution"
Assert-Contains $Main "webgpu_command_encoder_copy_texture_to_buffer_count" "WebGPU command-encoder texture-to-buffer attribution field"
Assert-Contains $Main "webgpu_command_encoder_copy_measured_count" "WebGPU measured command-encoder copy attribution field"
Assert-Contains $Main "webGpuCommandEncoderInstrumentation\.setPhase\(phase\)" "WebGPU command-encoder instrumentation phase follows benchmark phase"
Assert-Contains $Main "installWebGpuBindGroupInstrumentation" "WebGPU bind-group attribution helper"
Assert-Contains $Main "GPURenderPassEncoder" "WebGPU render-pass bind-group instrumentation"
Assert-Contains $Main "webgpu_bind_group_set_typed_array_empty_dynamic_offsets_count" "WebGPU typed-array empty dynamic-offset attribution field"
Assert-Contains $Main "webGpuBindGroupInstrumentation\.setPhase\(phase\)" "WebGPU bind-group instrumentation phase follows benchmark phase"
Assert-Contains $Main "installWebGpuPipelineStateInstrumentation" "WebGPU pipeline-state attribution helper"
Assert-Contains $Main "GPURenderBundleEncoder" "WebGPU render-bundle pipeline-state instrumentation"
Assert-Contains $Main "webgpu_pipeline_set_redundant_count" "WebGPU redundant setPipeline attribution field"
Assert-Contains $Main "webGpuPipelineStateInstrumentation\.setPhase\(phase\)" "WebGPU pipeline-state instrumentation phase follows benchmark phase"
Assert-Contains $Main "installWebGpuBufferStateInstrumentation" "WebGPU buffer-state attribution helper"
Assert-Contains $Main "setVertexBuffer" "WebGPU vertex-buffer state attribution"
Assert-Contains $Main "setIndexBuffer" "WebGPU index-buffer state attribution"
Assert-Contains $Main "webgpu_buffer_state_set_redundant_count" "WebGPU redundant buffer-state attribution field"
Assert-Contains $Main "webgpu_vertex_buffer_set_measured_redundant_count" "WebGPU measured redundant vertex-buffer attribution field"
Assert-Contains $Main "webgpu_index_buffer_set_measured_redundant_count" "WebGPU measured redundant index-buffer attribution field"
Assert-Contains $Main "webGpuBufferStateInstrumentation\.setPhase\(phase\)" "WebGPU buffer-state instrumentation phase follows benchmark phase"
Assert-Contains $Main "installWebGpuRenderStateInstrumentation" "WebGPU render-state attribution helper"
Assert-Contains $Main "setViewport" "WebGPU viewport state attribution"
Assert-Contains $Main "setScissorRect" "WebGPU scissor state attribution"
Assert-Contains $Main "setStencilReference" "WebGPU stencil state attribution"
Assert-Contains $Main "setBlendConstant" "WebGPU blend-constant state attribution"
Assert-Contains $Main "webgpu_render_state_set_redundant_count" "WebGPU redundant render-state attribution field"
Assert-Contains $Main "webgpu_blend_constant_set_redundant_count" "WebGPU redundant blend-constant attribution field"
Assert-Contains $Main "webgpu_viewport_set_measured_redundant_count" "WebGPU measured redundant viewport attribution field"
Assert-Contains $Main "webgpu_scissor_rect_set_measured_redundant_count" "WebGPU measured redundant scissor attribution field"
Assert-Contains $Main "webGpuRenderStateInstrumentation\.setPhase\(phase\)" "WebGPU render-state instrumentation phase follows benchmark phase"
Assert-Contains $Main "installWebGpuImmediateInstrumentation" "WebGPU setImmediates attribution helper"
Assert-Contains $Main "setImmediates" "WebGPU immediate data attribution"
Assert-Contains $Main "explicitSize \* bytesPerElement === byteLength" "WebGPU immediate attribution treats explicit full-size data as full-span"
Assert-Contains $Main "webgpu_immediate_set_full_span_count" "WebGPU full-span setImmediates attribution field"
Assert-Contains $Main "webGpuImmediateInstrumentation\.setPhase\(phase\)" "WebGPU immediate instrumentation phase follows benchmark phase"
Assert-Contains $Main "installWebGpuPipelineInstrumentation" "WebGPU pipeline creation instrumentation helper"
Assert-Contains $Main "createRenderPipelineAsync" "WebGPU async render pipeline instrumentation"
Assert-Contains $Main "createComputePipelineAsync" "WebGPU async compute pipeline instrumentation"
Assert-Contains $Main "webgpu_pipeline_create_measured_count" "measured-window WebGPU pipeline creation metric"
Assert-Contains $Main "summarizePipelineDescriptor" "WebGPU pipeline descriptor-shape attribution helper"
Assert-Contains $Main "webgpu_pipeline_descriptor_render_stack_vertex_buffer_eligible_count" "WebGPU render-pipeline stack vertex-buffer fast-path attribution field"
Assert-Contains $Main "webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count" "measured-window WebGPU pipeline descriptor fast-path attribution field"
Assert-Contains $Main "applyRuntimeShaderCompileEvidence" "runtime shader compile evidence handoff"
Assert-Contains $Main "shader_compile_event_source\s*=\s*['""]webgpu-pipeline-create-measured['""]" "WebGPU measured pipeline events feed shader-stall gate"
Assert-Contains $Main "webGpuPipelineInstrumentation\.setPhase\(phase\)" "WebGPU pipeline instrumentation phase follows benchmark phase"
Assert-Contains $Main "recordWebGpuDeviceLoss" "shared WebGPU device-loss recorder"
Assert-Contains $Main "renderer\.onDeviceLost" "Three.js WebGPU device-loss callback wrapping"
Assert-Contains $Main "renderer\?\.backend\?\.device\?\.lost" "direct GPUDevice.lost promise monitoring"
Assert-Contains $Main "webgpu_device_loss_source" "WebGPU device-loss source metric"
Assert-Contains $Main "settleStabilitySignalsBeforeResult" "final result waits for queued stability signals"
Assert-Contains $Main "setTimeout\(resolve,\s*0\)" "final result gives GPUDevice.lost callbacks one task turn before JSON emission"
Assert-NotContains $Main "if \(!result\.shader_compile_events && stats\.shaderCompileEvents\)" "scene-declared shader event fallback overwriting measured zero runtime events"
Assert-Contains $Main "function\s+isThenable\s*\(" "conditional async render-result detection"
Assert-Contains $Main "function\s+renderOnce\s*\(" "synchronous common render helper"
Assert-Contains $Main "renderResult\.then\(finishFrame,\s*failFrame\)" "promise-only render frame continuation"
Assert-Contains $Main "function\s+getCompileTargets\s*\(" "multi-target resource precompile helper"
Assert-Contains $Main "sceneBundle\.compileTargets" "scene-provided compile target list"
Assert-Contains $Main "await\s+renderer\.compileAsync\(target\.scene,\s*target\.camera\)" "async renderer precompile for each target"
Assert-NotContains $Main "async\s+function\s+renderOnce" "always-async render helper in hot loop"
Assert-NotContains $Main "async\s+function\s+frame" "always-async requestAnimationFrame callback"
Assert-NotContains $Main "renderMs\s*=\s*await\s+renderOnce" "unconditional await in frame render path"
Assert-Contains $Main "__THREE_VIEWER_BENCHMARK_RESULT__" "benchmark result export"
Assert-Contains $Main "THREE_VIEWER_RESULT" "stdout/console benchmark result marker"
Assert-Contains $Main 'console\.log\s*\(\s*`\s*THREE_VIEWER_RESULT \$\{JSON\.stringify\(result\)\}' "single-line stdout/console benchmark result payload"
Assert-Contains $Main "result\.benchmark_hud_enabled\s*=\s*options\.showHud" "benchmark result records HUD state"
Assert-Contains $Main "new BenchmarkRecorder\(\{[\s\S]*complexity:\s*options\.complexity" "benchmark recorder receives parsed complexity"

Assert-Contains $Metrics "constructor\(\{ sceneName, rendererType, warmupSeconds, measuredSeconds, complexity = null, metadata, resourceWarmup \}\)" "benchmark recorder accepts complexity"
Assert-Contains $Metrics "const numericComplexity = Number\(complexity\)" "benchmark recorder converts complexity to a number"
Assert-Contains $Metrics "this\.complexity\s*=\s*Number\.isFinite\(numericComplexity\)\s*\?\s*numericComplexity\s*:\s*null" "benchmark recorder normalizes complexity"
Assert-Contains $Metrics "complexity:\s*this\.complexity" "raw viewer result includes complexity"

Assert-Contains $Renderers "navigator\.gpu" "WebGPU availability check"
Assert-Contains $Renderers "WebGPURenderer" "Three.js WebGPU renderer path"
Assert-Contains $Renderers "getContext\s*\(\s*['""]webgl2['""]" "WebGL2 context creation"
Assert-Contains $Renderers "desynchronized\s*:\s*true" "low-latency WebGL canvas attribute"
Assert-Contains $Renderers "powerPreference\s*:\s*['""]high-performance['""]" "high-performance GPU preference"
Assert-Contains $Renderers "preserveDrawingBuffer\s*:\s*false" "GPU-resident WebGL presentation default"

Assert-Contains $Scenes "fetch\s*\(" "local asset loading through fetch"
Assert-Contains $Scenes "createImageBitmap\s*\(" "ImageBitmap texture loading path"
Assert-Contains $Scenes "TextureLoader" "texture loader fallback"
Assert-Contains $Scenes "GLTFLoader" "imported glTF loader stress path"
Assert-Contains $Scenes "async function createTextureStreaming\(\{ THREE, complexity, textureUploadMode = ['""]canvas['""], BundleGroup = null \}\)" "texture-streaming BundleGroup parameter"
Assert-Contains $Scenes "WebGPU static BundleGroup wraps the texture-streaming mesh set" "texture-streaming BundleGroup evidence note"
Assert-Contains $Scenes "createTextureStreaming\(\{ THREE, complexity, textureUploadMode, BundleGroup \}\)" "texture-streaming BundleGroup handoff from scene factory"
Assert-Contains $Scenes "bundle\.compileTargets\s*=\s*\[" "postprocessing secondary pass precompile targets"
Assert-Contains $Scenes "scene:\s*screenScene,\s*camera:\s*screenCamera" "postprocessing full-screen pass compile target"
Assert-NotContains $Scenes "bundle\.render\s*=\s*async" "per-frame async scene render callback"

foreach ($Arg in @("scene", "renderer", "duration", "warmup", "output")) {
  Assert-Contains $Runner "$Arg\s*:" "benchmark runner CLI/default option --$Arg"
}
Assert-Contains $Runner "mkdirSync\s*\(\s*path\.dirname\s*\(\s*path\.resolve\s*\(\s*args\.output\s*\)\s*\)" "benchmark runner output directory creation"
Assert-Contains $Runner "writeFileSync\s*\(\s*path\.resolve\s*\(\s*args\.output\s*\)" "benchmark runner JSON output write"
foreach ($QueryKey in @("scene", "renderer")) {
  Assert-Contains $Runner "$QueryKey\s*:\s*args\.$QueryKey" "viewer query propagation for $QueryKey"
}
Assert-Contains $Runner "duration\s*:\s*String\s*\(\s*duration\s*\)" "viewer query propagation for normalized duration"
Assert-Contains $Runner "warmup\s*:\s*String\s*\(\s*warmup\s*\)" "viewer query propagation for normalized warmup"
Assert-Contains $Runner "queueInstrumentation\s*:\s*args\.queueInstrumentation \? ['""]1['""] : ['""]0['""]" "viewer query propagation for queue instrumentation"
Assert-Contains $Runner "commandEncoderInstrumentation\s*:\s*args\.commandEncoderInstrumentation \? ['""]1['""] : ['""]0['""]" "viewer query propagation for command-encoder instrumentation"
Assert-Contains $Runner "bindGroupInstrumentation\s*:\s*args\.bindGroupInstrumentation \? ['""]1['""] : ['""]0['""]" "viewer query propagation for bind-group instrumentation"
Assert-Contains $Runner "pipelineStateInstrumentation\s*:\s*args\.pipelineStateInstrumentation \? ['""]1['""] : ['""]0['""]" "viewer query propagation for pipeline-state instrumentation"
Assert-Contains $Runner "bufferStateInstrumentation\s*:\s*args\.bufferStateInstrumentation \? ['""]1['""] : ['""]0['""]" "viewer query propagation for buffer-state instrumentation"
Assert-Contains $Runner "renderStateInstrumentation\s*:\s*args\.renderStateInstrumentation \? ['""]1['""] : ['""]0['""]" "viewer query propagation for render-state instrumentation"
Assert-Contains $Runner "immediateInstrumentation\s*:\s*args\.immediateInstrumentation \? ['""]1['""] : ['""]0['""]" "viewer query propagation for immediate instrumentation"
Assert-Contains $Runner "showHud:\s*args\.showHud \? ['""]1['""] : ['""]0['""]" "viewer query propagation for benchmark HUD state"
Assert-Contains $Runner "webgpu_queue_instrumentation_enabled" "benchmark result records queue instrumentation state"
Assert-Contains $Runner "webgpu_command_encoder_instrumentation_enabled" "benchmark result records command-encoder instrumentation state"
Assert-Contains $Runner "webgpu_bind_group_instrumentation_enabled" "benchmark result records bind-group instrumentation state"
Assert-Contains $Runner "webgpu_pipeline_state_instrumentation_enabled" "benchmark result records pipeline-state instrumentation state"
Assert-Contains $Runner "webgpu_buffer_state_instrumentation_enabled" "benchmark result records buffer-state instrumentation state"
Assert-Contains $Runner "webgpu_render_state_instrumentation_enabled" "benchmark result records render-state instrumentation state"
Assert-Contains $Runner "webgpu_immediate_instrumentation_enabled" "benchmark result records immediate instrumentation state"
Assert-Contains $Runner "benchmark_hud_enabled" "benchmark result records HUD state"
Assert-Contains $Runner "viewer-app-url" "viewer app URL handoff"
Assert-Contains $Runner "viewer-block-external-navigation" "viewer navigation lock handoff"
Assert-Contains $Runner "parseBenchmarkConsoleResult" "benchmark console result parser"
Assert-Contains $Runner "values\[0\]\s*===\s*['""]THREE_VIEWER_RESULT['""]" "two-argument benchmark console result parser"
Assert-Contains $Runner "startsWith\s*\(\s*['""]THREE_VIEWER_RESULT ['""]\s*\)" "single-string benchmark console result parser"

$ViewerSource = Get-ChildItem (Join-Path $Root "viewer\src") -Filter "*.js" -File |
  ForEach-Object { Get-Content $_.FullName -Raw } |
  Out-String
Assert-NotContains $ViewerSource "\breadPixels\b|getImageData\s*\(|toDataURL\s*\(" "CPU bitmap readback in viewer primary source"

Write-Host "Viewer runtime API surface and no-primary-readback checks passed."

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
    throw "Missing trace start-delay evidence: $Description. Pattern: $Pattern"
  }
}

function Assert-Order {
  param(
    [string]$Text,
    [string]$First,
    [string]$Second,
    [string]$Description
  )
  $FirstIndex = $Text.IndexOf($First)
  $SecondIndex = $Text.IndexOf($Second)
  if ($FirstIndex -lt 0 -or $SecondIndex -lt 0 -or $FirstIndex -ge $SecondIndex) {
    throw "Unexpected order for $Description. Expected '$First' before '$Second'."
  }
}

$Main = Read-RepoFile "viewer\src\main.js"
$TraceRunner = Read-RepoFile "scripts\run_trace_capture.mjs"

Assert-Contains $Main "startDelayMs:\s*numberParam\(params,\s*['""]startDelayMs['""]" "viewer parses startDelayMs query parameter"
Assert-Contains $Main "function delay\(ms\)" "viewer delay helper"
Assert-Contains $Main "if \(options\.startDelayMs > 0\)\s*\{\s*await delay\(options\.startDelayMs\);" "viewer waits before benchmark initialization"
Assert-Order $Main "await delay(options.startDelayMs);" "const rendererBundle = await createRenderer" "trace delay must happen before renderer/context creation"

Assert-Contains $TraceRunner "startDelayMs:\s*['""]2000['""]" "trace runner default start delay"
Assert-Contains $TraceRunner "disableGpuTiming:\s*false" "trace runner exposes WebGPU timing disable default"
Assert-Contains $TraceRunner "textureUploadMode:\s*['""]canvas['""]" "trace runner exposes texture upload mode default"
Assert-Contains $TraceRunner "queueInstrumentation:\s*false" "trace runner exposes queue instrumentation default"
Assert-Contains $TraceRunner "commandEncoderInstrumentation:\s*false" "trace runner exposes command-encoder instrumentation default"
Assert-Contains $TraceRunner "bindGroupInstrumentation:\s*false" "trace runner exposes bind-group instrumentation default"
Assert-Contains $TraceRunner "pipelineStateInstrumentation:\s*false" "trace runner exposes pipeline-state instrumentation default"
Assert-Contains $TraceRunner "bufferStateInstrumentation:\s*false" "trace runner exposes buffer-state instrumentation default"
Assert-Contains $TraceRunner "renderStateInstrumentation:\s*false" "trace runner exposes render-state instrumentation default"
Assert-Contains $TraceRunner "immediateInstrumentation:\s*false" "trace runner exposes immediate instrumentation default"
Assert-Contains $TraceRunner "showHud:\s*false" "trace runner disables benchmark HUD by default"
Assert-Contains $TraceRunner "pipelineQuietFrames:\s*['""]0['""]" "trace runner exposes WebGPU pipeline-quiet warmup default"
Assert-Contains $TraceRunner "function assertFiniteTraceNumber\(value, name" "trace runner has explicit finite numeric input validation"
Assert-Contains $TraceRunner "function assertNonNegativeIntegerTraceNumber\(value, name\)" "trace runner has explicit integer input validation"
Assert-Contains $TraceRunner "assertFiniteTraceNumber\(complexity,\s*['""]complexity['""]\)" "trace runner rejects invalid complexity before launch"
Assert-Contains $TraceRunner "assertFiniteTraceNumber\(duration,\s*['""]duration['""]\)" "trace runner rejects invalid duration before launch"
Assert-Contains $TraceRunner "assertFiniteTraceNumber\(warmup,\s*['""]warmup['""],\s*\{\s*allowZero:\s*true\s*\}\)" "trace runner accepts only finite non-negative warmup before launch"
Assert-Contains $TraceRunner "assertFiniteTraceNumber\(startDelayMs,\s*['""]startDelayMs['""],\s*\{\s*allowZero:\s*true\s*\}\)" "trace runner accepts only finite non-negative start delay before launch"
Assert-Contains $TraceRunner "assertNonNegativeIntegerTraceNumber\(prerenderFrames,\s*['""]prerenderFrames['""]\)" "trace runner rejects invalid prerender frame count before launch"
Assert-Contains $TraceRunner "assertNonNegativeIntegerTraceNumber\(pipelineQuietFrames,\s*['""]pipelineQuietFrames['""]\)" "trace runner rejects invalid WebGPU pipeline-quiet frame count before launch"
Assert-Contains $TraceRunner "assertNonNegativeIntegerTraceNumber\(pipelineQuietMaxFrames,\s*['""]pipelineQuietMaxFrames['""]\)" "trace runner rejects invalid WebGPU pipeline-quiet max frame count before launch"
Assert-Contains $TraceRunner "pipelineQuietFrames > 0 && pipelineQuietMaxFrames < pipelineQuietFrames" "trace runner rejects pipeline-quiet max frame normalization"
Assert-Contains $TraceRunner "startDelayMs:\s*String\(startDelayMs\)" "trace runner passes normalized startDelayMs query"
Assert-Contains $TraceRunner "gpuTiming:\s*args\.disableGpuTiming \? ['""]0['""] : ['""]1['""]" "trace runner can disable viewer GPU timing for WebGPU stress traces"
Assert-Contains $TraceRunner "textureUploadMode:\s*args\.textureUploadMode" "trace runner passes texture upload mode query"
Assert-Contains $TraceRunner "queueInstrumentation:\s*args\.queueInstrumentation \? ['""]1['""] : ['""]0['""]" "trace runner passes queue instrumentation query"
Assert-Contains $TraceRunner "commandEncoderInstrumentation:\s*args\.commandEncoderInstrumentation \? ['""]1['""] : ['""]0['""]" "trace runner passes command-encoder instrumentation query"
Assert-Contains $TraceRunner "bindGroupInstrumentation:\s*args\.bindGroupInstrumentation \? ['""]1['""] : ['""]0['""]" "trace runner passes bind-group instrumentation query"
Assert-Contains $TraceRunner "pipelineStateInstrumentation:\s*args\.pipelineStateInstrumentation \? ['""]1['""] : ['""]0['""]" "trace runner passes pipeline-state instrumentation query"
Assert-Contains $TraceRunner "bufferStateInstrumentation:\s*args\.bufferStateInstrumentation \? ['""]1['""] : ['""]0['""]" "trace runner passes buffer-state instrumentation query"
Assert-Contains $TraceRunner "renderStateInstrumentation:\s*args\.renderStateInstrumentation \? ['""]1['""] : ['""]0['""]" "trace runner passes render-state instrumentation query"
Assert-Contains $TraceRunner "immediateInstrumentation:\s*args\.immediateInstrumentation \? ['""]1['""] : ['""]0['""]" "trace runner passes immediate instrumentation query"
Assert-Contains $TraceRunner "showHud:\s*args\.showHud \? ['""]1['""] : ['""]0['""]" "trace runner passes benchmark HUD query"
Assert-Contains $TraceRunner "prerenderFrames:\s*String\(prerenderFrames\)" "trace runner passes normalized prerender frame count"
Assert-Contains $TraceRunner "pipelineQuietFrames:\s*String\(pipelineQuietFrames\)" "trace runner passes normalized WebGPU pipeline-quiet warmup query"
Assert-Contains $TraceRunner "pipelineQuietMaxFrames:\s*String\(pipelineQuietMaxFrames\)" "trace runner passes normalized WebGPU pipeline-quiet max frame query"
Assert-Contains $TraceRunner "parseBenchmarkConsoleResult" "robust trace benchmark console result parser"
Assert-Contains $TraceRunner "values\[0\]\s*===\s*['""]THREE_VIEWER_RESULT['""]" "two-argument trace benchmark result parser"
Assert-Contains $TraceRunner "startsWith\s*\(\s*['""]THREE_VIEWER_RESULT ['""]\s*\)" "single-string trace benchmark result parser"
Assert-Contains $TraceRunner "start_delay_ms:\s*startDelayMs" "trace result sidecar records normalized start delay"
Assert-Contains $TraceRunner "gpu_timing_enabled:\s*!args\.disableGpuTiming" "trace result sidecar records GPU timing state"
Assert-Contains $TraceRunner "texture_upload_mode:\s*args\.textureUploadMode" "trace result sidecar records texture upload mode"
Assert-Contains $TraceRunner "webgpu_queue_instrumentation_enabled:\s*args\.queueInstrumentation" "trace result sidecar records queue instrumentation state"
Assert-Contains $TraceRunner "webgpu_command_encoder_instrumentation_enabled:\s*args\.commandEncoderInstrumentation" "trace result sidecar records command-encoder instrumentation state"
Assert-Contains $TraceRunner "webgpu_bind_group_instrumentation_enabled:\s*args\.bindGroupInstrumentation" "trace result sidecar records bind-group instrumentation state"
Assert-Contains $TraceRunner "webgpu_pipeline_state_instrumentation_enabled:\s*args\.pipelineStateInstrumentation" "trace result sidecar records pipeline-state instrumentation state"
Assert-Contains $TraceRunner "webgpu_buffer_state_instrumentation_enabled:\s*args\.bufferStateInstrumentation" "trace result sidecar records buffer-state instrumentation state"
Assert-Contains $TraceRunner "webgpu_render_state_instrumentation_enabled:\s*args\.renderStateInstrumentation" "trace result sidecar records render-state instrumentation state"
Assert-Contains $TraceRunner "webgpu_immediate_instrumentation_enabled:\s*args\.immediateInstrumentation" "trace result sidecar records immediate instrumentation state"
Assert-Contains $TraceRunner "webGpuFastPathCoverageMetadata\(benchmarkResult\)" "trace result sidecar mirrors WebGPU fast-path coverage metadata from benchmark result"
Assert-Contains $TraceRunner "webgpu_queue_write_texture_common_layout_count" "trace result sidecar records writeTexture fast-path coverage metadata"
Assert-Contains $TraceRunner "webgpu_queue_copy_external_image_common_origin_count" "trace result sidecar records copyExternalImage common-origin fast-path coverage metadata"
Assert-Contains $TraceRunner "webgpu_queue_copy_external_image_explicit_common_origin_count" "trace result sidecar records copyExternalImage explicit common-origin fast-path coverage metadata"
Assert-Contains $TraceRunner "webgpu_queue_copy_external_image_full_source_count" "trace result sidecar records copyExternalImage fast-path coverage metadata"
Assert-Contains $TraceRunner "webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count" "trace result sidecar records pipeline descriptor fast-path coverage metadata"
Assert-Contains $TraceRunner "benchmark_hud_enabled:\s*args\.showHud" "trace result sidecar records benchmark HUD state"
Assert-Contains $TraceRunner "resource_warmup_enabled:\s*args\.precompile\s*\|\|\s*prerenderFrames\s*>\s*0\s*\|\|\s*args\.settleGpuAfterWarmup\s*\|\|\s*pipelineQuietFrames\s*>\s*0" "trace result sidecar records resource warmup enabled state"
Assert-Contains $TraceRunner "resource_warmup_precompile:\s*args\.precompile" "trace result sidecar records resource precompile state"
Assert-Contains $TraceRunner "resource_warmup_prerender_frames:\s*prerenderFrames" "trace result sidecar records resource prerender frame count"
Assert-Contains $TraceRunner "resource_warmup_pipeline_quiet_frames:\s*pipelineQuietFrames" "trace result sidecar records WebGPU pipeline-quiet warmup frame count"
Assert-Contains $TraceRunner "--viewer-app-url=\$\{viewerUrl\}" "trace runner still exercises viewer-mode app URL launch"
Assert-Contains $TraceRunner "Tracing\.start" "trace runner enables CDP tracing"

Write-Host "Trace capture start-delay wiring is statically verified."

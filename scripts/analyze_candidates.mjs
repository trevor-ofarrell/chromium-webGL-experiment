#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const webGpuStaticBundleScenes = new Set([
  'many-draw-calls',
  'texture-streaming',
  'gltf-loader-stress',
]);

function wildcardToRegExp(pattern) {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`^${escaped.replace(/\*/g, '.*').replace(/\?/g, '.')}$`, 'i');
}

function expandFileArg(fileArg) {
  if (!/[*?]/.test(fileArg)) return [fileArg];

  const dir = path.dirname(fileArg);
  const base = path.basename(fileArg);
  const resolvedDir = path.resolve(dir === '.' ? process.cwd() : dir);
  const matcher = wildcardToRegExp(base);
  if (!fs.existsSync(resolvedDir)) return [fileArg];

  return fs.readdirSync(resolvedDir)
    .filter((entry) => matcher.test(entry))
    .map((entry) => path.join(resolvedDir, entry));
}

function expandFileListArg(fileListArg) {
  const fileListPath = path.resolve(fileListArg);
  if (!fs.existsSync(fileListPath)) {
    throw new Error(`--fileList path not found: ${fileListArg}`);
  }
  return fs.readFileSync(fileListPath, 'utf8')
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'))
    .flatMap((line) => expandFileArg(line));
}

function splitListArg(value) {
  return String(value || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseArgs(argv) {
  const args = {
    files: [],
    output: '',
    json: '',
    minMeasuredSeconds: 30,
    minScenes: 7,
    minAvgFpsDeltaPct: 0,
    sceneRegressionPct: 1,
    p99RegressionMs: 1,
    lowRegressionFps: 0.1,
    droppedFramesRegression: 0,
    cpuFrameRegressionMs: 0.5,
    renderSubmissionRegressionMs: 0.5,
    pipelineCreateRegressionMs: 1.0,
    shaderCompileRegressionEvents: 0,
    includeAttribution: false,
    includeDiagnosticTextureModes: false,
    requireFrameTimes: false,
    requireCheckout: false,
    requirePackageSize: false,
    requiredCandidateRenderers: [],
    requiredScenes: [],
    expectedChromiumRevision: '',
    expectedForkRevision: '',
    quiet: false,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--output') {
      args.output = argv[++i];
    } else if (token === '--json') {
      args.json = argv[++i];
    } else if (token === '--minMeasuredSeconds') {
      args.minMeasuredSeconds = Number(argv[++i]);
    } else if (token === '--minScenes') {
      args.minScenes = Number(argv[++i]);
    } else if (token === '--minAvgFpsDeltaPct') {
      args.minAvgFpsDeltaPct = Number(argv[++i]);
    } else if (token === '--sceneRegressionPct') {
      args.sceneRegressionPct = Number(argv[++i]);
    } else if (token === '--p99RegressionMs') {
      args.p99RegressionMs = Number(argv[++i]);
    } else if (token === '--lowRegressionFps') {
      args.lowRegressionFps = Number(argv[++i]);
    } else if (token === '--droppedFramesRegression') {
      args.droppedFramesRegression = Number(argv[++i]);
    } else if (token === '--cpuFrameRegressionMs') {
      args.cpuFrameRegressionMs = Number(argv[++i]);
    } else if (token === '--renderSubmissionRegressionMs') {
      args.renderSubmissionRegressionMs = Number(argv[++i]);
    } else if (token === '--pipelineCreateRegressionMs') {
      args.pipelineCreateRegressionMs = Number(argv[++i]);
    } else if (token === '--shaderCompileRegressionEvents') {
      args.shaderCompileRegressionEvents = Number(argv[++i]);
    } else if (token === '--includeAttribution') {
      args.includeAttribution = true;
    } else if (token === '--includeDiagnosticTextureModes') {
      args.includeDiagnosticTextureModes = true;
    } else if (token === '--requireFrameTimes') {
      args.requireFrameTimes = true;
    } else if (token === '--requireCheckout') {
      args.requireCheckout = true;
    } else if (token === '--requirePackageSize') {
      args.requirePackageSize = true;
    } else if (token === '--requireCandidateRenderer' || token === '--requireCandidateRenderers') {
      const rawRenderers = String(argv[++i] || '');
      args.requiredCandidateRenderers.push(
        ...splitListArg(rawRenderers).map((renderer) => renderer.toLowerCase()),
      );
    } else if (token === '--requiredScene' || token === '--requiredScenes') {
      args.requiredScenes.push(...splitListArg(argv[++i]));
    } else if (token === '--expectedChromiumRevision') {
      args.expectedChromiumRevision = String(argv[++i] || '').trim();
    } else if (token === '--expectedForkRevision') {
      args.expectedForkRevision = String(argv[++i] || '').trim();
    } else if (token === '--fileList') {
      args.files.push(...expandFileListArg(argv[++i]));
    } else if (token === '--quiet') {
      args.quiet = true;
    } else {
      args.files.push(...expandFileArg(token));
    }
  }

  if (!args.files.length) {
    throw new Error('Usage: node scripts/analyze_candidates.mjs <result.json...> [--fileList inputs.txt] [--output report.md] [--json report.json] [--minMeasuredSeconds 30] [--minScenes 7] [--requiredScene many-draw-calls] [--minAvgFpsDeltaPct 0.5] [--sceneRegressionPct 1] [--droppedFramesRegression 0] [--cpuFrameRegressionMs 0.5] [--renderSubmissionRegressionMs 0.5] [--pipelineCreateRegressionMs 1.0] [--shaderCompileRegressionEvents 0] [--includeAttribution] [--includeDiagnosticTextureModes] [--requireFrameTimes] [--requireCheckout] [--requirePackageSize] [--requireCandidateRenderer webgl2] [--expectedChromiumRevision rev] [--expectedForkRevision rev+viewerpatch-hash] [--quiet]');
  }
  args.requiredCandidateRenderers = [...new Set(args.requiredCandidateRenderers)];
  args.requiredScenes = [...new Set(args.requiredScenes)];
  return args;
}

function round(value, digits = 2) {
  return Number.isFinite(value) ? value.toFixed(digits) : '';
}

function normalizeInputPath(file) {
  const resolved = path.resolve(file);
  const relative = path.relative(process.cwd(), resolved);
  const displayPath = relative && !relative.startsWith('..') && !path.isAbsolute(relative)
    ? relative
    : resolved;
  return displayPath.split(path.sep).join('/');
}

function readInputFile(file) {
  const content = fs.readFileSync(file);
  return {
    file,
    path: normalizeInputPath(file),
    sha256: crypto.createHash('sha256').update(content).digest('hex'),
    size_bytes: content.length,
    content,
  };
}

function inputDigest(entries) {
  const manifest = entries
    .map((entry) => `${entry.path}\t${entry.sha256}\t${entry.size_bytes}`)
    .sort((a, b) => a.localeCompare(b))
    .join('\n');
  return crypto.createHash('sha256').update(manifest).digest('hex');
}

function pct(value, baseline) {
  if (!Number.isFinite(value) || !Number.isFinite(baseline) || baseline === 0) return null;
  return (value / baseline) * 100;
}

function average(values) {
  const finite = values.filter((value) => Number.isFinite(value));
  if (!finite.length) return null;
  return finite.reduce((sum, value) => sum + value, 0) / finite.length;
}

function minimum(values) {
  const finite = values.filter((value) => Number.isFinite(value));
  if (!finite.length) return null;
  return Math.min(...finite);
}

function maximum(values) {
  const finite = values.filter((value) => Number.isFinite(value));
  if (!finite.length) return null;
  return Math.max(...finite);
}

function variantOf(result) {
  return result.benchmark_variant || path.basename(result.__file || '', '.json') || 'unknown';
}

function cohortOf(result) {
  const variant = variantOf(result);
  const iterMatch = variant.match(/^(iter\d+)/i);
  if (iterMatch) return iterMatch[1].toLowerCase();
  if (/baseline-content-shell|fork-viewer/i.test(variant)) return 'official';
  return variant.split('-')[0] || 'unknown';
}

function variantFamilyOf(result) {
  const variant = variantOf(result);
  const scene = result.scene_name;
  const renderer = result.renderer_type;
  const suffix = scene && renderer ? `-${scene}-${renderer}` : '';
  return suffix && variant.endsWith(suffix) ? variant.slice(0, -suffix.length) : variant;
}

function findBenchmarkUrl(result) {
  const flags = Array.isArray(result.browser_flags) ? result.browser_flags : [];
  for (const rawFlag of flags) {
    const flag = String(rawFlag);
    const value = flag.startsWith('--viewer-app-url=') ? flag.slice('--viewer-app-url='.length) : flag;
    if (!value.includes('benchmark=1')) continue;
    try {
      return new URL(value);
    } catch {
      continue;
    }
  }
  return null;
}

function flagValues(flags, switchName) {
  if (!Array.isArray(flags)) return [];
  const values = [];
  const prefix = `${switchName}=`;
  for (let index = 0; index < flags.length; index += 1) {
    const flag = String(flags[index]);
    if (flag === switchName && index + 1 < flags.length) {
      values.push(String(flags[index + 1]));
      index += 1;
    } else if (flag.startsWith(prefix)) {
      values.push(flag.slice(prefix.length));
    }
  }
  return values;
}

function flagTokenListIncludes(flags, switchName, token) {
  return flagValues(flags, switchName).some((value) => value.split(',').some((part) => {
    const normalized = part.trim().split(':', 1)[0];
    return normalized === token;
  }));
}

function queryValue(result, key) {
  const url = findBenchmarkUrl(result);
  return url ? url.searchParams.get(key) : null;
}

function complexityOf(result) {
  if (Number.isFinite(result.complexity)) return String(result.complexity);
  const query = queryValue(result, 'complexity');
  if (query) return query;
  const match = variantOf(result).match(/(?:^|-)c(\d+)(?:-|$)/i);
  return match ? match[1] : 'default';
}

function textureModeOf(result) {
  return result.texture_upload_mode || queryValue(result, 'textureUploadMode') || 'canvas';
}

function gpuTimingKeyOf(result) {
  if (typeof result.gpu_timing_enabled === 'boolean') return String(result.gpu_timing_enabled);
  const query = queryValue(result, 'gpuTiming');
  if (query === '0') return 'false';
  if (query === '1') return 'true';
  return 'unknown';
}

function queueInstrumentationEnabled(result) {
  if (typeof result.webgpu_queue_instrumentation_enabled === 'boolean') {
    return result.webgpu_queue_instrumentation_enabled;
  }
  return queryValue(result, 'queueInstrumentation') === '1';
}

function commandEncoderInstrumentationEnabled(result) {
  if (typeof result.webgpu_command_encoder_instrumentation_enabled === 'boolean') {
    return result.webgpu_command_encoder_instrumentation_enabled;
  }
  return queryValue(result, 'commandEncoderInstrumentation') === '1';
}

function bindGroupInstrumentationEnabled(result) {
  if (typeof result.webgpu_bind_group_instrumentation_enabled === 'boolean') {
    return result.webgpu_bind_group_instrumentation_enabled;
  }
  return queryValue(result, 'bindGroupInstrumentation') === '1';
}

function pipelineStateInstrumentationEnabled(result) {
  if (typeof result.webgpu_pipeline_state_instrumentation_enabled === 'boolean') {
    return result.webgpu_pipeline_state_instrumentation_enabled;
  }
  return queryValue(result, 'pipelineStateInstrumentation') === '1';
}

function bufferStateInstrumentationEnabled(result) {
  if (typeof result.webgpu_buffer_state_instrumentation_enabled === 'boolean') {
    return result.webgpu_buffer_state_instrumentation_enabled;
  }
  return queryValue(result, 'bufferStateInstrumentation') === '1';
}

function renderStateInstrumentationEnabled(result) {
  if (typeof result.webgpu_render_state_instrumentation_enabled === 'boolean') {
    return result.webgpu_render_state_instrumentation_enabled;
  }
  return queryValue(result, 'renderStateInstrumentation') === '1';
}

function immediateInstrumentationEnabled(result) {
  if (typeof result.webgpu_immediate_instrumentation_enabled === 'boolean') {
    return result.webgpu_immediate_instrumentation_enabled;
  }
  return queryValue(result, 'immediateInstrumentation') === '1';
}

function sourceQueueTraceEnabled(result) {
  return result.viewer_trace_webgpu_queue === true;
}

function webGpuPipelineInstrumentationKeyOf(result) {
  if (result.renderer_type !== 'webgpu') return 'not-webgpu';
  if (typeof result.webgpu_pipeline_instrumentation_enabled === 'boolean') {
    return String(result.webgpu_pipeline_instrumentation_enabled);
  }
  return 'unknown';
}

function benchmarkHudKeyOf(result) {
  if (typeof result.benchmark_hud_enabled === 'boolean') {
    return String(result.benchmark_hud_enabled);
  }
  const query = queryValue(result, 'showHud');
  if (query !== null) return booleanQueryKey(query);
  return 'unknown';
}

function booleanQueryKey(value) {
  const normalized = String(value).toLowerCase();
  if (normalized === '1' || normalized === 'true') return 'true';
  if (normalized === '0' || normalized === 'false') return 'false';
  return normalized || 'false';
}

function resourceWarmupPrecompileKeyOf(result) {
  if (typeof result.resource_warmup_precompile === 'boolean') {
    return String(result.resource_warmup_precompile);
  }
  const query = queryValue(result, 'precompile');
  if (query !== null) return booleanQueryKey(query);
  if (result.resource_warmup_enabled === true) return 'unknown';
  return 'false';
}

function resourceWarmupPrerenderFramesKeyOf(result) {
  if (Number.isFinite(result.resource_warmup_prerender_frames)) {
    return String(result.resource_warmup_prerender_frames);
  }
  const query = queryValue(result, 'prerenderFrames');
  if (query !== null) {
    const frames = Number(query);
    return Number.isFinite(frames) ? String(frames) : String(query);
  }
  if (result.resource_warmup_enabled === true) return 'unknown';
  return '0';
}

function resourceWarmupCompileTargetsKeyOf(result) {
  if (Number.isFinite(result.resource_warmup_compile_targets)) {
    return String(result.resource_warmup_compile_targets);
  }
  if (resourceWarmupPrecompileKeyOf(result) === 'true') {
    return 'unknown';
  }
  return '0';
}

function resourceWarmupTextureTargetsKeyOf(result) {
  if (Number.isFinite(result.resource_warmup_texture_targets)) {
    return String(result.resource_warmup_texture_targets);
  }
  if (resourceWarmupPrecompileKeyOf(result) === 'true') {
    return 'unknown';
  }
  return '0';
}

function resourceWarmupRenderTargetsKeyOf(result) {
  if (Number.isFinite(result.resource_warmup_render_targets)) {
    return String(result.resource_warmup_render_targets);
  }
  if (resourceWarmupPrecompileKeyOf(result) === 'true') {
    return 'unknown';
  }
  return '0';
}

function resourceWarmupSettleGpuKeyOf(result) {
  if (typeof result.resource_warmup_settle_gpu === 'boolean') {
    return String(result.resource_warmup_settle_gpu);
  }
  const query = queryValue(result, 'settleGpuAfterWarmup');
  if (query !== null) return booleanQueryKey(query);
  return 'false';
}

function resourceWarmupPipelineQuietFramesKeyOf(result) {
  if (Number.isFinite(result.resource_warmup_pipeline_quiet_frames)) {
    return String(result.resource_warmup_pipeline_quiet_frames);
  }
  const query = queryValue(result, 'pipelineQuietFrames');
  if (query !== null) {
    const frames = Number(query);
    return Number.isFinite(frames) ? String(frames) : String(query);
  }
  return '0';
}

function resourceWarmupPipelineQuietMaxFramesKeyOf(result) {
  if (Number.isFinite(result.resource_warmup_pipeline_quiet_max_frames)) {
    return String(result.resource_warmup_pipeline_quiet_max_frames);
  }
  const query = queryValue(result, 'pipelineQuietMaxFrames');
  if (query !== null) {
    const frames = Number(query);
    return Number.isFinite(frames) ? String(frames) : String(query);
  }
  return resourceWarmupPipelineQuietFramesKeyOf(result) === '0' ? '0' : 'unknown';
}

function profileCacheModeKeyOf(result) {
  const mode = typeof result.profile_cache_mode === 'string' ? result.profile_cache_mode.trim() : '';
  if (mode) return mode;
  return 'fresh-temp';
}

function profileCacheKeyOf(result) {
  const mode = profileCacheModeKeyOf(result);
  if (mode === 'fresh-temp') return 'fresh-temp';
  const key = typeof result.profile_cache_key === 'string' ? result.profile_cache_key.trim() : '';
  return key || 'missing-profile-cache-key';
}

function webGpuBundleModeKeyOf(result) {
  const value = typeof result.webgpu_bundle_mode === 'string' ? result.webgpu_bundle_mode.trim().toLowerCase() : '';
  if (value) return value;
  const query = queryValue(result, 'webgpuBundleMode');
  if (query !== null) {
    const normalized = String(query).trim().toLowerCase();
    return normalized || 'off';
  }
  return 'off';
}

function webGpuBundleModeInvalidReason(result) {
  const mode = webGpuBundleModeKeyOf(result);
  if (!['off', 'static'].includes(mode)) {
    return `unknown webgpu_bundle_mode=${mode}`;
  }
  if (mode === 'static' && result.renderer_type !== 'webgpu') {
    return 'webgpu_bundle_mode=static used with non-WebGPU renderer';
  }
  if (mode !== 'static' &&
      Number.isFinite(result.webgpu_bundle_groups) &&
      result.webgpu_bundle_groups > 0) {
    return 'webgpu_bundle_groups present while webgpu_bundle_mode is not static';
  }
  if (result.renderer_type === 'webgpu' &&
      mode === 'static' &&
      webGpuStaticBundleScenes.has(result.scene_name) &&
      (!Number.isInteger(result.webgpu_bundle_groups) || result.webgpu_bundle_groups <= 0)) {
    return `${result.scene_name}: webgpu_bundle_mode=static requires positive webgpu_bundle_groups`;
  }
  return '';
}

function normalizedTextKey(value, fallback) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text) return fallback;
  return text.toLowerCase().replace(/\s+/g, ' ');
}

function normalizedGpuDeviceId(value) {
  const text = typeof value === 'string' ? value : '';
  const match = text.match(/0x[0-9a-f]+/i);
  if (!match) return '';
  const parsed = Number.parseInt(match[0].slice(2), 16);
  if (!Number.isFinite(parsed)) return match[0].toLowerCase();
  return `0x${parsed.toString(16)}`;
}

function gpuDeviceKeyOf(result) {
  const id = normalizedGpuDeviceId(result.gpu_name);
  if (id) return id;
  return normalizedTextKey(result.gpu_name, 'unknown-gpu');
}

function platformKeyOf(result) {
  return normalizedTextKey(result.platform, 'unknown-platform');
}

function driverKeyOf(result) {
  return normalizedTextKey(result.driver_version, 'unknown-driver');
}

function buildArgsHashKeyOf(result) {
  return normalizedTextKey(result.build_args_hash, 'unknown-build-args');
}

function compatibilityKey(result) {
  return [
    cohortOf(result),
    result.chromium_revision || '',
    buildArgsHashKeyOf(result),
    platformKeyOf(result),
    gpuDeviceKeyOf(result),
    driverKeyOf(result),
    result.renderer_type || '',
    result.scene_name || '',
    complexityOf(result),
    result.measured_seconds,
    result.warmup_seconds,
    textureModeOf(result),
    webGpuBundleModeKeyOf(result),
    gpuTimingKeyOf(result),
    webGpuPipelineInstrumentationKeyOf(result),
    benchmarkHudKeyOf(result),
    resourceWarmupPrecompileKeyOf(result),
    resourceWarmupPrerenderFramesKeyOf(result),
    resourceWarmupCompileTargetsKeyOf(result),
    resourceWarmupTextureTargetsKeyOf(result),
    resourceWarmupRenderTargetsKeyOf(result),
    resourceWarmupSettleGpuKeyOf(result),
    resourceWarmupPipelineQuietFramesKeyOf(result),
    resourceWarmupPipelineQuietMaxFramesKeyOf(result),
    profileCacheModeKeyOf(result),
    profileCacheKeyOf(result),
  ].join('|');
}

function isBaseline(result) {
  return /baseline|stock/i.test(variantOf(result));
}

function isFork(result) {
  return /fork/i.test(variantOf(result));
}

function stabilityRunReason(result) {
  const variant = variantOf(result);
  const mode = typeof result.benchmark_mode === 'string' ? result.benchmark_mode.trim() : '';
  if (result.is_stability_run === true || result.stability_result === true) {
    return 'stability benchmark artifact';
  }
  if (/^stability$/i.test(mode) || /(?:^|-)long-stability(?:-|$)/i.test(variant)) {
    return 'stability benchmark artifact';
  }
  return '';
}

function softwareRendererReason(result) {
  const haystack = [result.gpu_name, result.driver_version, result.angle_backend]
    .filter((value) => typeof value === 'string')
    .join(' ')
    .toLowerCase();
  if (!haystack) return '';

  const patterns = [
    ['swiftshader', 'SwiftShader'],
    ['llvmpipe', 'llvmpipe'],
    ['softpipe', 'softpipe'],
    ['software rasterizer', 'software rasterizer'],
    ['software renderer', 'software renderer'],
    ['microsoft basic render driver', 'Microsoft Basic Render Driver'],
    ['microsoft basic renderer', 'Microsoft Basic Renderer'],
    ['warp', 'WARP'],
  ];
  const match = patterns.find(([pattern]) => haystack.includes(pattern));
  return match ? match[1] : '';
}

function softwareRenderingDiagnosticOptIn(result) {
  return result.allow_software_rendering === true || result.allowSoftwareRendering === true;
}

function gpuInstabilityReason(result) {
  if (typeof result.webgpu_device_lost !== 'boolean') return 'missing webgpu_device_lost';
  if (typeof result.webgl_context_currently_lost !== 'boolean') return 'missing webgl_context_currently_lost';
  if (typeof result.webgl_context_lost_count !== 'number' || !Number.isFinite(result.webgl_context_lost_count)) {
    return 'missing webgl_context_lost_count';
  }
  if (typeof result.render_error_count !== 'number' || !Number.isFinite(result.render_error_count)) {
    return 'missing render_error_count';
  }
  if (result.webgpu_device_lost === true) return 'WebGPU device loss';
  if (result.webgl_context_currently_lost === true) return 'WebGL context currently lost';
  if (result.webgl_context_lost_count > 0) {
    return `WebGL context loss count ${result.webgl_context_lost_count}`;
  }
  if (result.render_error_count > 0) {
    return `render_error_count ${result.render_error_count}`;
  }
  return '';
}

const webGpuCpuFallbackCountFields = [
  'webgpu_cpu_texture_fallback_count',
  'webgpu_cpu_texture_readback_count',
  'webgpu_forced_texture_readback_count',
  'webgpu_copy_external_image_cpu_fallback_count',
  'webgpu_copy_external_image_cpu_readback_count',
  'webgpu_copy_external_image_forced_readback_count',
];

const copyExternalImageExperimentFields = [
  'viewer_skip_webgpu_copy_external_image_color_conversion',
  'viewer_skip_webgpu_copy_external_image_color_space_validation',
  'viewer_skip_webgpu_copy_external_image_dest_validation',
  'viewer_skip_webgpu_copy_external_image_source_validation',
  'viewer_skip_webgpu_copy_external_image_copy_size_validation',
];

function isCopyExternalImageUploadExperiment(result) {
  if (result.renderer_type !== 'webgpu') return false;
  if (copyExternalImageExperimentFields.some((field) => result[field] === true)) return true;
  const variant = variantOf(result).toLowerCase();
  return variant.includes('copy-external-image') ||
    variant.includes('copy-ext-image') ||
    variant.includes('aggressive-upload-fast-path');
}

function webGpuCpuFallbackReason(result) {
  if (result.renderer_type !== 'webgpu') return '';
  if (isCopyExternalImageUploadExperiment(result) &&
      result.viewer_reject_webgpu_cpu_texture_fallback !== true) {
    return 'WebGPU copyExternalImage upload experiment missing CPU texture fallback rejection';
  }
  if (result.webgpu_cpu_texture_fallback_detected === true) {
    return 'WebGPU CPU texture fallback/readback detected';
  }
  const verdict = typeof result.webgpu_texture_copy_path_verdict === 'string'
    ? result.webgpu_texture_copy_path_verdict.trim().toLowerCase()
    : '';
  if (verdict === 'cpu-fallback-detected' || verdict === 'cpu-fallback-rejected' || verdict === 'forced-readback-detected') {
    return `WebGPU CPU texture fallback/readback verdict ${result.webgpu_texture_copy_path_verdict}`;
  }
  for (const field of webGpuCpuFallbackCountFields) {
    if (Number.isFinite(result[field]) && result[field] > 0) {
      return `WebGPU CPU texture fallback/readback ${field}=${result[field]}`;
    }
  }
  return '';
}

const trustedViewerExperimentFields = [
  'viewer_aggressive_gpu',
  'viewer_relaxed_webgl_validation',
  'viewer_zero_copy',
  'viewer_in_process_gpu',
  'viewer_single_process',
  'viewer_disable_unneeded_blink_features',
  'viewer_direct_gpu_presentation',
  'viewer_defer_webgpu_pipeline_flush',
  'viewer_defer_webgpu_queue_flush',
  'viewer_defer_webgpu_submit_flush',
  'viewer_skip_webgpu_canvas_texture_validation',
  'viewer_skip_webgpu_canvas_memory_accounting',
  'viewer_skip_webgpu_copy_external_image_color_conversion',
  'viewer_skip_webgpu_copy_external_image_color_space_validation',
  'viewer_skip_webgpu_copy_external_image_dest_validation',
  'viewer_skip_webgpu_copy_external_image_source_validation',
  'viewer_skip_webgpu_copy_external_image_copy_size_validation',
  'viewer_skip_webgpu_write_texture_layout_validation',
  'viewer_reject_webgpu_cpu_texture_fallback',
  'viewer_skip_webgpu_use_counters',
  'viewer_cache_webgpu_bind_group_layouts',
  'viewer_skip_webgpu_command_labels',
  'viewer_skip_webgpu_resource_labels',
  'viewer_skip_webgpu_shader_source_null_check',
  'viewer_skip_webgpu_shader_memory_accounting',
  'viewer_skip_webgpu_redundant_pipeline_sets',
  'viewer_skip_webgpu_redundant_bind_group_sets',
  'viewer_skip_webgpu_redundant_buffer_sets',
  'viewer_skip_webgpu_redundant_render_state_sets',
  'viewer_trace_webgpu_queue',
];

const webGpuOnlyTrustedViewerExperimentFields = [
  'viewer_defer_webgpu_pipeline_flush',
  'viewer_defer_webgpu_queue_flush',
  'viewer_defer_webgpu_submit_flush',
  'viewer_skip_webgpu_canvas_texture_validation',
  'viewer_skip_webgpu_canvas_memory_accounting',
  'viewer_skip_webgpu_copy_external_image_color_conversion',
  'viewer_skip_webgpu_copy_external_image_color_space_validation',
  'viewer_skip_webgpu_copy_external_image_dest_validation',
  'viewer_skip_webgpu_copy_external_image_source_validation',
  'viewer_skip_webgpu_copy_external_image_copy_size_validation',
  'viewer_skip_webgpu_write_texture_layout_validation',
  'viewer_reject_webgpu_cpu_texture_fallback',
  'viewer_skip_webgpu_use_counters',
  'viewer_cache_webgpu_bind_group_layouts',
  'viewer_skip_webgpu_command_labels',
  'viewer_skip_webgpu_resource_labels',
  'viewer_skip_webgpu_shader_source_null_check',
  'viewer_skip_webgpu_shader_memory_accounting',
  'viewer_skip_webgpu_redundant_pipeline_sets',
  'viewer_skip_webgpu_redundant_bind_group_sets',
  'viewer_skip_webgpu_redundant_buffer_sets',
  'viewer_skip_webgpu_redundant_render_state_sets',
  'viewer_trace_webgpu_queue',
];

const webGl2OnlyTrustedViewerExperimentFields = [
  'viewer_relaxed_webgl_validation',
  'viewer_zero_copy',
];

const trustedBrowserExperimentSwitches = [
  '--use-webgpu-adapter',
  '--enable-dawn-features',
  '--disable-dawn-features',
  '--enable-features',
  '--disable-features',
  '--enable-gpu-memory-buffer-compositor-resources',
  '--ui-enable-zero-copy',
  '--enable-gpu-rasterization',
  '--disable-frame-rate-limit',
  '--disable-gpu-vsync',
];

function hasSwitchValue(result, field) {
  const value = result[field];
  if (typeof value !== 'string') return false;
  const normalized = value.trim().toLowerCase();
  return normalized.length > 0 && normalized !== 'default' && normalized !== 'null';
}

function trustedBrowserExperimentFlags(result) {
  if (!Array.isArray(result.browser_flags)) return [];
  return result.browser_flags.filter((rawFlag) => {
    const flag = String(rawFlag);
    return trustedBrowserExperimentSwitches.some((switchName) => (
      flag === switchName || flag.startsWith(`${switchName}=`)
    ));
  });
}

function trustedExperimentInvalidReason(result) {
  const enabledMetadata = trustedViewerExperimentFields.filter((field) => result[field] === true);
  if (hasSwitchValue(result, 'viewer_force_angle_backend')) {
    enabledMetadata.push('viewer_force_angle_backend');
  }
  const enabledBrowserFlags = trustedBrowserExperimentFlags(result);
  if (!enabledMetadata.length && !enabledBrowserFlags.length) return '';

  const enabled = [...enabledMetadata, ...enabledBrowserFlags];
  if (result.viewer_mode !== true || result.viewer_trusted_content !== true) {
    return `trusted experiment requires viewer_mode=true and viewer_trusted_content=true (${enabled.join(', ')})`;
  }

  const webGpuOnly = webGpuOnlyTrustedViewerExperimentFields.find((field) => result[field] === true);
  if (webGpuOnly && result.renderer_type !== 'webgpu') {
    return `WebGPU trusted experiment ${webGpuOnly} used with renderer_type=${result.renderer_type}`;
  }
  const webGl2Only = webGl2OnlyTrustedViewerExperimentFields.find((field) => result[field] === true);
  if (webGl2Only && result.renderer_type !== 'webgl2') {
    return `WebGL2 trusted experiment ${webGl2Only} used with renderer_type=${result.renderer_type}`;
  }
  return '';
}

function webGpuPipelineQuietWarmupReason(result) {
  const requestedFrames = Number(resourceWarmupPipelineQuietFramesKeyOf(result));
  if (!Number.isFinite(requestedFrames) || requestedFrames <= 0) return '';
  if (result.renderer_type !== 'webgpu') {
    return 'WebGPU pipeline-quiet warmup requested for non-WebGPU result';
  }
  if (typeof result.resource_warmup_pipeline_quiet_achieved !== 'boolean') {
    return 'WebGPU pipeline-quiet warmup missing achieved telemetry';
  }
  if (result.resource_warmup_pipeline_quiet_achieved !== true) {
    return 'WebGPU pipeline-quiet warmup not achieved';
  }
  if (!Number.isFinite(result.resource_warmup_pipeline_quiet_actual_frames)) {
    return 'WebGPU pipeline-quiet warmup missing actual-frame telemetry';
  }
  if (result.resource_warmup_pipeline_quiet_actual_frames < requestedFrames) {
    return `WebGPU pipeline-quiet warmup actual frames ${result.resource_warmup_pipeline_quiet_actual_frames} below requested ${requestedFrames}`;
  }
  if (typeof result.resource_warmup_pipeline_quiet_error === 'string' &&
      result.resource_warmup_pipeline_quiet_error.trim().length > 0) {
    return `WebGPU pipeline-quiet warmup error: ${result.resource_warmup_pipeline_quiet_error}`;
  }
  if (result.webgpu_pipeline_instrumentation_available !== true) {
    return 'WebGPU pipeline-quiet warmup missing available pipeline instrumentation';
  }
  if (!Number.isFinite(result.webgpu_pipeline_create_measured_count)) {
    return 'WebGPU pipeline-quiet warmup missing measured-window pipeline creation telemetry';
  }
  if (result.webgpu_pipeline_create_measured_count > 0) {
    return `WebGPU pipeline-quiet warmup measured-window pipeline creates ${result.webgpu_pipeline_create_measured_count}`;
  }
  return '';
}

function resourceWarmupInitErrorReason(result) {
  for (const field of ['resource_warmup_texture_init_error', 'resource_warmup_render_target_init_error']) {
    const value = result[field];
    if (typeof value === 'string' && value.trim().length > 0) {
      return `${field}: ${value}`;
    }
  }
  return '';
}

function forkProvenanceReason(result) {
  if (!isFork(result) || isBaseline(result)) return '';
  const forkRevision = typeof result.fork_revision === 'string' ? result.fork_revision.trim() : '';
  const chromiumRevision = typeof result.chromium_revision === 'string' ? result.chromium_revision.trim() : '';
  if (!forkRevision) return 'missing fork_revision';
  if (chromiumRevision && forkRevision === chromiumRevision) {
    return 'fork_revision does not identify viewer patch';
  }
  if (chromiumRevision && !forkRevision.startsWith(`${chromiumRevision}+`)) {
    return 'fork_revision does not match chromium_revision';
  }
  return '';
}

function isWebGpuBlobCacheHashValidationExperiment(result) {
  if (result.renderer_type !== 'webgpu') return false;
  if (result.webgpu_blob_cache_hash_validation_disabled === true) return true;
  if (/blob-cache-hash-validation/i.test(variantOf(result))) return true;
  return flagTokenListIncludes(result.browser_flags, '--disable-dawn-features', 'blob_cache_hash_validation');
}

function webGpuBlobCacheInvalidReason(result) {
  if (!isWebGpuBlobCacheHashValidationExperiment(result)) return '';
  if (result.webgpu_blob_cache_expected_available !== true) {
    return 'WebGPU blob-cache hash-validation experiment missing webgpu_blob_cache_expected_available=true';
  }
  if (result.webgpu_blob_cache_origin_eligible !== true) {
    return 'WebGPU blob-cache hash-validation experiment missing webgpu_blob_cache_origin_eligible=true';
  }
  if (result.webgpu_blob_cache_disabled_by_explicit_toggle === true ||
      flagTokenListIncludes(result.browser_flags, '--enable-dawn-features', 'disable_blob_cache')) {
    return 'WebGPU blob-cache hash-validation experiment has Dawn disable_blob_cache enabled';
  }
  if (!['http', 'https'].includes(result.viewer_url_scheme)) {
    return 'WebGPU blob-cache hash-validation experiment missing HTTP(S) viewer_url_scheme';
  }
  if (typeof result.viewer_origin !== 'string' || result.viewer_origin.trim().length === 0) {
    return 'WebGPU blob-cache hash-validation experiment missing viewer_origin';
  }
  return '';
}

function profileCacheInvalidReason(result) {
  const mode = profileCacheModeKeyOf(result);
  if (!['fresh-temp', 'explicit-reuse'].includes(mode)) {
    return `unknown profile_cache_mode=${mode}`;
  }
  if (mode === 'explicit-reuse') {
    if (result.profile_reuse_enabled !== true) {
      return 'explicit profile-cache run missing profile_reuse_enabled=true';
    }
    if (profileCacheKeyOf(result) === 'missing-profile-cache-key') {
      return 'explicit profile-cache run missing profile_cache_key';
    }
  }
  return '';
}

const requiredTextEvidenceFields = [
  'chromium_revision',
  'build_args_hash',
  'platform',
  'gpu_name',
  'driver_version',
  'angle_backend',
  'renderer_type',
  'scene_name',
];

const requiredFiniteEvidenceFields = [
  'warmup_seconds',
  'measured_seconds',
  'complexity',
  'avg_fps',
  'p50_frame_ms',
  'p95_frame_ms',
  'p99_frame_ms',
  'one_percent_low_fps',
  'point_one_percent_low_fps',
  'avg_cpu_frame_ms',
  'avg_js_frame_ms',
  'avg_render_submission_ms',
  'max_frame_ms',
  'dropped_frames',
  'draw_calls',
  'triangles',
  'texture_upload_mb',
  'buffer_upload_mb',
  'shader_compile_events',
  'process_rss_mb',
  'startup_ms_to_first_frame',
  'browser_binary_size_mb',
  'viewer_bundle_size_mb',
];

const requiredNullableEvidenceFields = [
  'avg_gpu_frame_ms',
  'avg_compositor_latency_ms',
  'avg_presentation_latency_ms',
  'js_heap_mb',
  'gpu_memory_mb',
  'package_size_mb',
];

function requiredBenchmarkEvidenceInvalidReason(result) {
  for (const field of requiredTextEvidenceFields) {
    if (typeof result[field] !== 'string' || result[field].trim().length === 0) {
      return `missing evidence ${field}`;
    }
  }
  for (const field of requiredFiniteEvidenceFields) {
    if (!Number.isFinite(result[field])) {
      return `missing evidence ${field}`;
    }
    if (field === 'complexity' && result[field] <= 0) {
      return `non-positive evidence ${field}`;
    }
    if (result[field] < 0) {
      return `negative evidence ${field}`;
    }
  }
  for (const field of requiredNullableEvidenceFields) {
    if (!Object.prototype.hasOwnProperty.call(result, field)) {
      return `missing evidence ${field}`;
    }
    if (result[field] !== null && !Number.isFinite(result[field])) {
      return `invalid evidence ${field}`;
    }
    if (Number.isFinite(result[field]) && result[field] < 0) {
      return `negative evidence ${field}`;
    }
  }
  if (typeof result.gpu_timing_enabled !== 'boolean') {
    return 'missing evidence gpu_timing_enabled';
  }
  if (!['webgl2', 'webgpu'].includes(result.renderer_type)) {
    return `unsupported renderer_type ${result.renderer_type}`;
  }
  return '';
}

function evidenceClassOf(result) {
  return profileCacheModeKeyOf(result) === 'explicit-reuse'
    ? 'warm-profile-attribution'
    : 'fresh-profile-evidence';
}

function invalidReason(result, args) {
  if (!Number.isFinite(result.avg_fps)) return 'missing avg_fps';
  const stabilityRun = stabilityRunReason(result);
  if (stabilityRun) return stabilityRun;
  if (!Number.isFinite(result.measured_seconds) || result.measured_seconds < args.minMeasuredSeconds) {
    return `measured_seconds ${result.measured_seconds} below ${args.minMeasuredSeconds}`;
  }
  if (args.expectedChromiumRevision && result.chromium_revision !== args.expectedChromiumRevision) {
    return `chromium_revision ${result.chromium_revision || 'missing'} does not match expected ${args.expectedChromiumRevision}`;
  }
  if (args.requireFrameTimes && (!Array.isArray(result.frame_times_ms) || result.frame_times_ms.length === 0)) {
    return 'missing frame_times_ms';
  }
  const missingEvidence = requiredBenchmarkEvidenceInvalidReason(result);
  if (missingEvidence) return missingEvidence;
  if (args.requireCheckout && result.browser_is_from_checkout !== true) {
    return 'browser_is_from_checkout not true';
  }
  if (args.requirePackageSize && (!Number.isFinite(result.package_size_mb) || result.package_size_mb <= 0)) {
    return 'package_size_mb missing or non-positive';
  }
  const software = softwareRendererReason(result);
  if (software) return `software renderer: ${software}`;
  if (softwareRenderingDiagnosticOptIn(result)) {
    return 'diagnostic software-rendering opt-in';
  }
  const instability = gpuInstabilityReason(result);
  if (instability) return instability;
  const webGpuCpuFallback = webGpuCpuFallbackReason(result);
  if (webGpuCpuFallback) return webGpuCpuFallback;
  const webGpuPipelineQuietWarmup = webGpuPipelineQuietWarmupReason(result);
  if (webGpuPipelineQuietWarmup) return webGpuPipelineQuietWarmup;
  const resourceWarmupInitError = resourceWarmupInitErrorReason(result);
  if (resourceWarmupInitError) return resourceWarmupInitError;
  const webGpuBundleMode = webGpuBundleModeInvalidReason(result);
  if (webGpuBundleMode) return webGpuBundleMode;
  const forkProvenance = forkProvenanceReason(result);
  if (forkProvenance) return forkProvenance;
  const webGpuBlobCache = webGpuBlobCacheInvalidReason(result);
  if (webGpuBlobCache) return webGpuBlobCache;
  const profileCache = profileCacheInvalidReason(result);
  if (profileCache) return profileCache;
  if (args.expectedForkRevision && isFork(result) && result.fork_revision !== args.expectedForkRevision) {
    return `fork_revision ${result.fork_revision || 'missing'} does not match expected ${args.expectedForkRevision}`;
  }
  if (!args.includeAttribution && queueInstrumentationEnabled(result)) {
    return 'queue instrumentation attribution run';
  }
  if (!args.includeAttribution && commandEncoderInstrumentationEnabled(result)) {
    return 'command-encoder instrumentation attribution run';
  }
  if (!args.includeAttribution && bindGroupInstrumentationEnabled(result)) {
    return 'bind-group instrumentation attribution run';
  }
  if (!args.includeAttribution && pipelineStateInstrumentationEnabled(result)) {
    return 'pipeline-state instrumentation attribution run';
  }
  if (!args.includeAttribution && bufferStateInstrumentationEnabled(result)) {
    return 'buffer-state instrumentation attribution run';
  }
  if (!args.includeAttribution && renderStateInstrumentationEnabled(result)) {
    return 'render-state instrumentation attribution run';
  }
  if (!args.includeAttribution && immediateInstrumentationEnabled(result)) {
    return 'immediate instrumentation attribution run';
  }
  if (!args.includeAttribution && sourceQueueTraceEnabled(result)) {
    return 'source WebGPU queue trace attribution run';
  }
  const trustedExperiment = trustedExperimentInvalidReason(result);
  if (trustedExperiment) return trustedExperiment;
  if (!args.includeDiagnosticTextureModes && textureModeOf(result) !== 'canvas') {
    return `diagnostic texture_upload_mode=${textureModeOf(result)}`;
  }
  return '';
}

function delta(candidate, baseline, field) {
  const left = candidate[field];
  const right = baseline[field];
  return Number.isFinite(left) && Number.isFinite(right) ? left - right : null;
}

function compare(candidate, baseline) {
  const avgFpsDelta = delta(candidate, baseline, 'avg_fps');
  const profileCacheMode = profileCacheModeKeyOf(candidate);
  const profileCacheKey = profileCacheKeyOf(candidate);
  return {
    cohort: cohortOf(candidate),
    renderer: candidate.renderer_type,
    scene: candidate.scene_name,
    baseline_variant: variantOf(baseline),
    candidate_variant: variantOf(candidate),
    baseline_family: variantFamilyOf(baseline),
    candidate_family: variantFamilyOf(candidate),
    evidence_class: evidenceClassOf(candidate),
    profile_cache_mode: profileCacheMode,
    profile_cache_key: profileCacheKey,
    avg_fps_delta: avgFpsDelta,
    avg_fps_delta_pct: pct(avgFpsDelta, baseline.avg_fps),
    one_percent_low_fps_delta: delta(candidate, baseline, 'one_percent_low_fps'),
    point_one_percent_low_fps_delta: delta(candidate, baseline, 'point_one_percent_low_fps'),
    p95_frame_ms_delta: delta(candidate, baseline, 'p95_frame_ms'),
    p99_frame_ms_delta: delta(candidate, baseline, 'p99_frame_ms'),
    max_frame_ms_delta: delta(candidate, baseline, 'max_frame_ms'),
    avg_cpu_frame_ms_delta: delta(candidate, baseline, 'avg_cpu_frame_ms'),
    avg_render_submission_ms_delta: delta(candidate, baseline, 'avg_render_submission_ms'),
    dropped_frames_delta: delta(candidate, baseline, 'dropped_frames'),
    shader_compile_events_delta: delta(candidate, baseline, 'shader_compile_events'),
    webgpu_pipeline_create_measured_ms_delta:
      delta(candidate, baseline, 'webgpu_pipeline_create_measured_ms'),
    startup_ms_to_first_frame_delta: delta(candidate, baseline, 'startup_ms_to_first_frame'),
    process_rss_mb_delta: delta(candidate, baseline, 'process_rss_mb'),
  };
}

function selectBaselineForCompatibilityGroup(group) {
  const baselines = group.filter(isBaseline);
  if (!baselines.length) return null;

  const selected = baselines
    .slice()
    .sort((a, b) => (b.avg_fps ?? -Infinity) - (a.avg_fps ?? -Infinity) ||
      variantOf(a).localeCompare(variantOf(b)))[0];
  const baselineFamilies = [...new Set(baselines.map(variantFamilyOf))];
  return {
    selected,
    family: baselineFamilies.length > 1 ? 'strongest-compatible-baseline' : variantFamilyOf(selected),
    selection: baselines.length > 1 ? 'fastest-compatible-baseline' : 'single-compatible-baseline',
    compatible_count: baselines.length,
    compatible_variants: baselines.map(variantOf).sort((a, b) => a.localeCompare(b)),
  };
}

function compareWithSelectedBaseline(candidate, baselineInfo) {
  const row = compare(candidate, baselineInfo.selected);
  row.baseline_family = baselineInfo.family;
  row.baseline_selection = baselineInfo.selection;
  row.compatible_baseline_count = baselineInfo.compatible_count;
  row.compatible_baseline_variants = baselineInfo.compatible_variants;
  return row;
}

function sceneNamesForRows(rows) {
  return [...new Set(rows.map((row) => row.scene).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b));
}

function missingRequiredScenes(sceneNames, args) {
  const available = new Set(sceneNames);
  return args.requiredScenes.filter((scene) => !available.has(scene));
}

function numberForSort(value, fallback) {
  return Number.isFinite(value) ? value : fallback;
}

function compareSceneRowsConservatively(a, b) {
  return numberForSort(a.avg_fps_delta_pct, Infinity) - numberForSort(b.avg_fps_delta_pct, Infinity) ||
    numberForSort(a.one_percent_low_fps_delta, Infinity) - numberForSort(b.one_percent_low_fps_delta, Infinity) ||
    numberForSort(a.point_one_percent_low_fps_delta, Infinity) - numberForSort(b.point_one_percent_low_fps_delta, Infinity) ||
    numberForSort(b.p99_frame_ms_delta, -Infinity) - numberForSort(a.p99_frame_ms_delta, -Infinity) ||
    numberForSort(b.p95_frame_ms_delta, -Infinity) - numberForSort(a.p95_frame_ms_delta, -Infinity) ||
    numberForSort(b.avg_cpu_frame_ms_delta, -Infinity) - numberForSort(a.avg_cpu_frame_ms_delta, -Infinity) ||
    numberForSort(b.avg_render_submission_ms_delta, -Infinity) - numberForSort(a.avg_render_submission_ms_delta, -Infinity) ||
    numberForSort(b.shader_compile_events_delta, -Infinity) - numberForSort(a.shader_compile_events_delta, -Infinity) ||
    numberForSort(b.webgpu_pipeline_create_measured_ms_delta, -Infinity) -
      numberForSort(a.webgpu_pipeline_create_measured_ms_delta, -Infinity) ||
    a.candidate_variant.localeCompare(b.candidate_variant);
}

function representativeRowsByScene(rows) {
  const byScene = new Map();
  for (const row of rows) {
    const scene = row.scene || '';
    if (!byScene.has(scene)) byScene.set(scene, []);
    byScene.get(scene).push(row);
  }
  return [...byScene.values()]
    .map((sceneRows) => sceneRows.slice().sort(compareSceneRowsConservatively)[0])
    .sort((a, b) => String(a.scene || '').localeCompare(String(b.scene || '')));
}

function hasLowOrTailRegression(row, args) {
  return (
    (Number.isFinite(row.one_percent_low_fps_delta) && row.one_percent_low_fps_delta < -args.lowRegressionFps) ||
    (Number.isFinite(row.point_one_percent_low_fps_delta) && row.point_one_percent_low_fps_delta < -args.lowRegressionFps) ||
    (Number.isFinite(row.p95_frame_ms_delta) && row.p95_frame_ms_delta > args.p99RegressionMs) ||
    (Number.isFinite(row.p99_frame_ms_delta) && row.p99_frame_ms_delta > args.p99RegressionMs)
  );
}

function hasShaderCompileRegression(row, args) {
  return Number.isFinite(row.shader_compile_events_delta) &&
    row.shader_compile_events_delta > args.shaderCompileRegressionEvents;
}

function hasPipelineCreateRegression(row, args) {
  return Number.isFinite(row.webgpu_pipeline_create_measured_ms_delta) &&
    row.webgpu_pipeline_create_measured_ms_delta > args.pipelineCreateRegressionMs;
}

function hasDroppedFramesRegression(row, args) {
  return Number.isFinite(row.dropped_frames_delta) &&
    row.dropped_frames_delta > args.droppedFramesRegression;
}

function hasCpuFrameRegression(row, args) {
  return Number.isFinite(row.avg_cpu_frame_ms_delta) &&
    row.avg_cpu_frame_ms_delta > args.cpuFrameRegressionMs;
}

function hasRenderSubmissionRegression(row, args) {
  return Number.isFinite(row.avg_render_submission_ms_delta) &&
    row.avg_render_submission_ms_delta > args.renderSubmissionRegressionMs;
}

function classifyFamily(summary, args) {
  if (!Number.isFinite(summary.avg_fps_delta_pct) || summary.avg_fps_delta_pct <= 0) {
    return 'not useful';
  }
  if (summary.missing_required_scenes?.length) {
    return 'needs-suite';
  }
  if (summary.scenes < args.minScenes) {
    return 'needs-suite';
  }
  if (Number.isFinite(summary.min_fps_delta_pct) && summary.min_fps_delta_pct < -args.sceneRegressionPct) {
    return 'blocked-throughput';
  }
  if (summary.avg_fps_delta_pct < args.minAvgFpsDeltaPct) {
    return 'weak-throughput';
  }
  if (
    (Number.isFinite(summary.max_shader_compile_events_delta) &&
      summary.max_shader_compile_events_delta > args.shaderCompileRegressionEvents) ||
    (Number.isFinite(summary.max_webgpu_pipeline_create_measured_ms_delta) &&
      summary.max_webgpu_pipeline_create_measured_ms_delta > args.pipelineCreateRegressionMs) ||
    summary.scene_rows.some((row) => hasShaderCompileRegression(row, args) ||
      hasPipelineCreateRegression(row, args))
  ) {
    return 'blocked-shader-stalls';
  }
  if (
    (Number.isFinite(summary.max_dropped_frames_delta) &&
      summary.max_dropped_frames_delta > args.droppedFramesRegression) ||
    summary.scene_rows.some((row) => hasDroppedFramesRegression(row, args))
  ) {
    return 'blocked-dropped-frames';
  }
  if (
    (Number.isFinite(summary.max_avg_cpu_frame_ms_delta) &&
      summary.max_avg_cpu_frame_ms_delta > args.cpuFrameRegressionMs) ||
    (Number.isFinite(summary.max_avg_render_submission_ms_delta) &&
      summary.max_avg_render_submission_ms_delta > args.renderSubmissionRegressionMs) ||
    summary.scene_rows.some((row) =>
      hasCpuFrameRegression(row, args) || hasRenderSubmissionRegression(row, args))
  ) {
    return 'blocked-cpu-overhead';
  }
  const lowRegression =
    (Number.isFinite(summary.one_percent_low_fps_delta) && summary.one_percent_low_fps_delta < -args.lowRegressionFps) ||
    (Number.isFinite(summary.point_one_percent_low_fps_delta) && summary.point_one_percent_low_fps_delta < -args.lowRegressionFps);
  const tailRegression =
    (Number.isFinite(summary.p95_frame_ms_delta) && summary.p95_frame_ms_delta > args.p99RegressionMs) ||
    (Number.isFinite(summary.p99_frame_ms_delta) && summary.p99_frame_ms_delta > args.p99RegressionMs);
  if (lowRegression || tailRegression || summary.scene_rows.some((row) => hasLowOrTailRegression(row, args))) {
    return 'blocked-tail';
  }
  return summary.evidence_class === 'warm-profile-attribution'
    ? 'cache-attribution'
    : 'candidate';
}

function summarizeFamilies(rows, args) {
  const byFamily = new Map();
  for (const row of rows) {
    const key = JSON.stringify([
      row.cohort,
      row.renderer,
      row.baseline_family,
      row.candidate_family,
      row.evidence_class,
      row.profile_cache_mode,
      row.profile_cache_key,
    ]);
    if (!byFamily.has(key)) byFamily.set(key, []);
    byFamily.get(key).push(row);
  }

  return [...byFamily.entries()]
    .map(([key, familyRows]) => {
      const [
        cohort,
        renderer,
        baselineFamily,
        candidateFamily,
        evidenceClass,
        profileCacheMode,
        profileCacheKey,
      ] = JSON.parse(key);
      const sceneRows = representativeRowsByScene(familyRows);
      const sceneNames = sceneNamesForRows(sceneRows);
      const summary = {
        cohort,
        renderer,
        baseline_family: baselineFamily,
        candidate_family: candidateFamily,
        evidence_class: evidenceClass,
        profile_cache_mode: profileCacheMode,
        profile_cache_key: profileCacheKey,
        scenes: sceneNames.length,
        scene_names: sceneNames,
        missing_required_scenes: missingRequiredScenes(sceneNames, args),
        duplicate_scene_rows_collapsed: familyRows.length - sceneRows.length,
        avg_fps_delta_pct: average(sceneRows.map((row) => row.avg_fps_delta_pct)),
        min_fps_delta_pct: minimum(sceneRows.map((row) => row.avg_fps_delta_pct)),
        avg_fps_delta: average(sceneRows.map((row) => row.avg_fps_delta)),
        one_percent_low_fps_delta: average(sceneRows.map((row) => row.one_percent_low_fps_delta)),
        min_one_percent_low_fps_delta: minimum(sceneRows.map((row) => row.one_percent_low_fps_delta)),
        point_one_percent_low_fps_delta: average(sceneRows.map((row) => row.point_one_percent_low_fps_delta)),
        min_point_one_percent_low_fps_delta: minimum(sceneRows.map((row) => row.point_one_percent_low_fps_delta)),
        p95_frame_ms_delta: average(sceneRows.map((row) => row.p95_frame_ms_delta)),
        max_p95_frame_ms_delta: maximum(sceneRows.map((row) => row.p95_frame_ms_delta)),
        p99_frame_ms_delta: average(sceneRows.map((row) => row.p99_frame_ms_delta)),
        max_p99_frame_ms_delta: maximum(sceneRows.map((row) => row.p99_frame_ms_delta)),
        max_frame_ms_delta: average(sceneRows.map((row) => row.max_frame_ms_delta)),
        avg_cpu_frame_ms_delta: average(sceneRows.map((row) => row.avg_cpu_frame_ms_delta)),
        max_avg_cpu_frame_ms_delta: maximum(sceneRows.map((row) => row.avg_cpu_frame_ms_delta)),
        avg_render_submission_ms_delta: average(sceneRows.map((row) => row.avg_render_submission_ms_delta)),
        max_avg_render_submission_ms_delta: maximum(sceneRows.map((row) => row.avg_render_submission_ms_delta)),
        dropped_frames_delta: average(sceneRows.map((row) => row.dropped_frames_delta)),
        max_dropped_frames_delta: maximum(sceneRows.map((row) => row.dropped_frames_delta)),
        shader_compile_events_delta: average(sceneRows.map((row) => row.shader_compile_events_delta)),
        max_shader_compile_events_delta: maximum(sceneRows.map((row) => row.shader_compile_events_delta)),
        webgpu_pipeline_create_measured_ms_delta:
          average(sceneRows.map((row) => row.webgpu_pipeline_create_measured_ms_delta)),
        max_webgpu_pipeline_create_measured_ms_delta:
          maximum(sceneRows.map((row) => row.webgpu_pipeline_create_measured_ms_delta)),
        startup_ms_to_first_frame_delta: average(sceneRows.map((row) => row.startup_ms_to_first_frame_delta)),
        process_rss_mb_delta: average(sceneRows.map((row) => row.process_rss_mb_delta)),
        scene_rows: sceneRows,
      };
      summary.status = classifyFamily(summary, args);
      return summary;
    })
    .sort((a, b) => {
      const statusRank = { candidate: 0, 'cache-attribution': 1, 'needs-suite': 2, 'weak-throughput': 3, 'blocked-throughput': 4, 'blocked-shader-stalls': 5, 'blocked-dropped-frames': 6, 'blocked-cpu-overhead': 7, 'blocked-tail': 8, 'not useful': 9 };
      return (statusRank[a.status] ?? 9) - (statusRank[b.status] ?? 9) ||
        (b.avg_fps_delta_pct ?? -Infinity) - (a.avg_fps_delta_pct ?? -Infinity);
    });
}

function markdownTable(rows) {
  if (!rows.length) return ['No comparable candidate families found.'];
  return [
    '| Cohort | Renderer | Baseline | Candidate | Evidence | Profile Cache | Scenes | Status | Avg FPS Delta % | Min FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms | Startup Delta ms | RSS Delta MB |',
    '| --- | --- | --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    ...rows.map((row) => `| ${row.cohort} | ${row.renderer} | ${row.baseline_family} | ${row.candidate_family} | ${row.evidence_class} | ${row.profile_cache_mode}/${row.profile_cache_key} | ${row.scenes} | ${row.status} | ${round(row.avg_fps_delta_pct, 2)} | ${round(row.min_fps_delta_pct, 2)} | ${round(row.one_percent_low_fps_delta, 2)} | ${round(row.point_one_percent_low_fps_delta, 2)} | ${round(row.p95_frame_ms_delta, 2)} | ${round(row.p99_frame_ms_delta, 2)} | ${round(row.dropped_frames_delta, 2)} | ${round(row.shader_compile_events_delta, 2)} | ${round(row.webgpu_pipeline_create_measured_ms_delta, 2)} | ${round(row.avg_cpu_frame_ms_delta, 2)} | ${round(row.avg_render_submission_ms_delta, 2)} | ${round(row.startup_ms_to_first_frame_delta, 1)} | ${round(row.process_rss_mb_delta, 1)} |`),
  ];
}

function metricScore(value, threshold, direction) {
  if (!Number.isFinite(value)) return 0;
  if (direction === 'below') {
    if (!(value < -threshold)) return 0;
    return threshold > 0 ? (-value - threshold) / threshold : -value;
  }
  if (!(value > threshold)) return 0;
  return threshold > 0 ? (value - threshold) / threshold : value;
}

function primaryBlockerForScene(row, args) {
  const candidates = [
    {
      label: `1% low ${round(row.one_percent_low_fps_delta, 2)} FPS`,
      score: metricScore(row.one_percent_low_fps_delta, args.lowRegressionFps, 'below'),
    },
    {
      label: `0.1% low ${round(row.point_one_percent_low_fps_delta, 2)} FPS`,
      score: metricScore(row.point_one_percent_low_fps_delta, args.lowRegressionFps, 'below'),
    },
    {
      label: `p95 ${round(row.p95_frame_ms_delta, 2)} ms`,
      score: metricScore(row.p95_frame_ms_delta, args.p99RegressionMs, 'above'),
    },
    {
      label: `p99 ${round(row.p99_frame_ms_delta, 2)} ms`,
      score: metricScore(row.p99_frame_ms_delta, args.p99RegressionMs, 'above'),
    },
  ].sort((a, b) => b.score - a.score);
  return candidates[0]?.score > 0 ? candidates[0] : null;
}

function primaryShaderBlockerForScene(row, args) {
  const candidates = [
    {
      label: `shader compile events +${round(row.shader_compile_events_delta, 0)}`,
      score: metricScore(row.shader_compile_events_delta, args.shaderCompileRegressionEvents, 'above'),
    },
    {
      label: `WebGPU pipeline create +${round(row.webgpu_pipeline_create_measured_ms_delta, 2)} ms`,
      score: metricScore(row.webgpu_pipeline_create_measured_ms_delta, args.pipelineCreateRegressionMs, 'above'),
    },
  ].sort((a, b) => b.score - a.score);
  return candidates[0]?.score > 0 ? candidates[0] : null;
}

function primaryDroppedFramesBlockerForScene(row, args) {
  const score = metricScore(row.dropped_frames_delta, args.droppedFramesRegression, 'above');
  return score > 0
    ? { label: `dropped frames +${round(row.dropped_frames_delta, 0)}`, score }
    : null;
}

function primaryCpuOverheadBlockerForScene(row, args) {
  const candidates = [
    {
      label: `CPU frame +${round(row.avg_cpu_frame_ms_delta, 2)} ms`,
      score: metricScore(row.avg_cpu_frame_ms_delta, args.cpuFrameRegressionMs, 'above'),
    },
    {
      label: `render submission +${round(row.avg_render_submission_ms_delta, 2)} ms`,
      score: metricScore(row.avg_render_submission_ms_delta, args.renderSubmissionRegressionMs, 'above'),
    },
  ].sort((a, b) => b.score - a.score);
  return candidates[0]?.score > 0 ? candidates[0] : null;
}

function worstSceneBy(rows, scoreFn) {
  let worst = null;
  for (const row of rows) {
    const score = scoreFn(row);
    if (!worst || score > worst.score) {
      worst = { row, score };
    }
  }
  return worst;
}

function blockerDiagnostic(summary, args) {
  if (summary.status === 'candidate') return null;
  if (summary.status === 'needs-suite') {
    const missing = summary.missing_required_scenes || [];
    return {
      cohort: summary.cohort,
      renderer: summary.renderer,
      baseline_family: summary.baseline_family,
      candidate_family: summary.candidate_family,
      status: summary.status,
      scene: missing.length ? `missing ${missing.length}/${args.requiredScenes.length}` : `coverage ${summary.scenes}/${args.minScenes}`,
      primary_blocker: missing.length
        ? `needs required scene(s): ${missing.join(', ')}`
        : `needs ${Math.max(0, args.minScenes - summary.scenes)} more comparable scene(s)`,
      avg_fps_delta_pct: summary.avg_fps_delta_pct,
      one_percent_low_fps_delta: summary.one_percent_low_fps_delta,
      point_one_percent_low_fps_delta: summary.point_one_percent_low_fps_delta,
      p95_frame_ms_delta: summary.p95_frame_ms_delta,
      p99_frame_ms_delta: summary.p99_frame_ms_delta,
      dropped_frames_delta: summary.dropped_frames_delta,
      shader_compile_events_delta: summary.shader_compile_events_delta,
      webgpu_pipeline_create_measured_ms_delta: summary.webgpu_pipeline_create_measured_ms_delta,
      avg_cpu_frame_ms_delta: summary.avg_cpu_frame_ms_delta,
      avg_render_submission_ms_delta: summary.avg_render_submission_ms_delta,
    };
  }

  if (summary.status === 'weak-throughput') {
    return {
      cohort: summary.cohort,
      renderer: summary.renderer,
      baseline_family: summary.baseline_family,
      candidate_family: summary.candidate_family,
      status: summary.status,
      scene: 'suite average',
      primary_blocker: `avg FPS ${round(summary.avg_fps_delta_pct, 2)}% below required ${round(args.minAvgFpsDeltaPct, 2)}%`,
      avg_fps_delta_pct: summary.avg_fps_delta_pct,
      one_percent_low_fps_delta: summary.one_percent_low_fps_delta,
      point_one_percent_low_fps_delta: summary.point_one_percent_low_fps_delta,
      p95_frame_ms_delta: summary.p95_frame_ms_delta,
      p99_frame_ms_delta: summary.p99_frame_ms_delta,
      dropped_frames_delta: summary.dropped_frames_delta,
      shader_compile_events_delta: summary.shader_compile_events_delta,
      webgpu_pipeline_create_measured_ms_delta: summary.webgpu_pipeline_create_measured_ms_delta,
      avg_cpu_frame_ms_delta: summary.avg_cpu_frame_ms_delta,
      avg_render_submission_ms_delta: summary.avg_render_submission_ms_delta,
    };
  }

  if (summary.status === 'cache-attribution') {
    return {
      cohort: summary.cohort,
      renderer: summary.renderer,
      baseline_family: summary.baseline_family,
      candidate_family: summary.candidate_family,
      status: summary.status,
      scene: `${summary.profile_cache_mode}/${summary.profile_cache_key}`,
      primary_blocker: 'requires matching fresh-profile official run before retained speed claim',
      avg_fps_delta_pct: summary.avg_fps_delta_pct,
      one_percent_low_fps_delta: summary.one_percent_low_fps_delta,
      point_one_percent_low_fps_delta: summary.point_one_percent_low_fps_delta,
      p95_frame_ms_delta: summary.p95_frame_ms_delta,
      p99_frame_ms_delta: summary.p99_frame_ms_delta,
      dropped_frames_delta: summary.dropped_frames_delta,
      shader_compile_events_delta: summary.shader_compile_events_delta,
      webgpu_pipeline_create_measured_ms_delta: summary.webgpu_pipeline_create_measured_ms_delta,
      avg_cpu_frame_ms_delta: summary.avg_cpu_frame_ms_delta,
      avg_render_submission_ms_delta: summary.avg_render_submission_ms_delta,
    };
  }

  if (summary.status === 'blocked-shader-stalls') {
    const worst = worstSceneBy(summary.scene_rows, (row) => primaryShaderBlockerForScene(row, args)?.score || 0);
    const row = worst?.row || summary.scene_rows[0];
    const blocker = row ? primaryShaderBlockerForScene(row, args) : null;
    return {
      cohort: summary.cohort,
      renderer: summary.renderer,
      baseline_family: summary.baseline_family,
      candidate_family: summary.candidate_family,
      status: summary.status,
      scene: row?.scene || '',
      primary_blocker: blocker?.label || 'shader compile event or WebGPU pipeline-create timing regression',
      avg_fps_delta_pct: row?.avg_fps_delta_pct ?? summary.avg_fps_delta_pct,
      one_percent_low_fps_delta: row?.one_percent_low_fps_delta ?? summary.one_percent_low_fps_delta,
      point_one_percent_low_fps_delta: row?.point_one_percent_low_fps_delta ?? summary.point_one_percent_low_fps_delta,
      p95_frame_ms_delta: row?.p95_frame_ms_delta ?? summary.p95_frame_ms_delta,
      p99_frame_ms_delta: row?.p99_frame_ms_delta ?? summary.p99_frame_ms_delta,
      dropped_frames_delta: row?.dropped_frames_delta ?? summary.dropped_frames_delta,
      shader_compile_events_delta: row?.shader_compile_events_delta ?? summary.shader_compile_events_delta,
      webgpu_pipeline_create_measured_ms_delta:
        row?.webgpu_pipeline_create_measured_ms_delta ?? summary.webgpu_pipeline_create_measured_ms_delta,
      avg_cpu_frame_ms_delta: row?.avg_cpu_frame_ms_delta ?? summary.avg_cpu_frame_ms_delta,
      avg_render_submission_ms_delta: row?.avg_render_submission_ms_delta ?? summary.avg_render_submission_ms_delta,
    };
  }

  if (summary.status === 'blocked-dropped-frames') {
    const worst = worstSceneBy(summary.scene_rows, (row) => primaryDroppedFramesBlockerForScene(row, args)?.score || 0);
    const row = worst?.row || summary.scene_rows[0];
    const blocker = row ? primaryDroppedFramesBlockerForScene(row, args) : null;
    return {
      cohort: summary.cohort,
      renderer: summary.renderer,
      baseline_family: summary.baseline_family,
      candidate_family: summary.candidate_family,
      status: summary.status,
      scene: row?.scene || '',
      primary_blocker: blocker?.label || 'dropped frame regression',
      avg_fps_delta_pct: row?.avg_fps_delta_pct ?? summary.avg_fps_delta_pct,
      one_percent_low_fps_delta: row?.one_percent_low_fps_delta ?? summary.one_percent_low_fps_delta,
      point_one_percent_low_fps_delta: row?.point_one_percent_low_fps_delta ?? summary.point_one_percent_low_fps_delta,
      p95_frame_ms_delta: row?.p95_frame_ms_delta ?? summary.p95_frame_ms_delta,
      p99_frame_ms_delta: row?.p99_frame_ms_delta ?? summary.p99_frame_ms_delta,
      dropped_frames_delta: row?.dropped_frames_delta ?? summary.dropped_frames_delta,
      shader_compile_events_delta: row?.shader_compile_events_delta ?? summary.shader_compile_events_delta,
      webgpu_pipeline_create_measured_ms_delta:
        row?.webgpu_pipeline_create_measured_ms_delta ?? summary.webgpu_pipeline_create_measured_ms_delta,
      avg_cpu_frame_ms_delta: row?.avg_cpu_frame_ms_delta ?? summary.avg_cpu_frame_ms_delta,
      avg_render_submission_ms_delta: row?.avg_render_submission_ms_delta ?? summary.avg_render_submission_ms_delta,
    };
  }

  if (summary.status === 'blocked-cpu-overhead') {
    const worst = worstSceneBy(summary.scene_rows, (row) => primaryCpuOverheadBlockerForScene(row, args)?.score || 0);
    const row = worst?.row || summary.scene_rows[0];
    const blocker = row ? primaryCpuOverheadBlockerForScene(row, args) : null;
    return {
      cohort: summary.cohort,
      renderer: summary.renderer,
      baseline_family: summary.baseline_family,
      candidate_family: summary.candidate_family,
      status: summary.status,
      scene: row?.scene || '',
      primary_blocker: blocker?.label || 'CPU/render submission overhead regression',
      avg_fps_delta_pct: row?.avg_fps_delta_pct ?? summary.avg_fps_delta_pct,
      one_percent_low_fps_delta: row?.one_percent_low_fps_delta ?? summary.one_percent_low_fps_delta,
      point_one_percent_low_fps_delta: row?.point_one_percent_low_fps_delta ?? summary.point_one_percent_low_fps_delta,
      p95_frame_ms_delta: row?.p95_frame_ms_delta ?? summary.p95_frame_ms_delta,
      p99_frame_ms_delta: row?.p99_frame_ms_delta ?? summary.p99_frame_ms_delta,
      dropped_frames_delta: row?.dropped_frames_delta ?? summary.dropped_frames_delta,
      shader_compile_events_delta: row?.shader_compile_events_delta ?? summary.shader_compile_events_delta,
      webgpu_pipeline_create_measured_ms_delta:
        row?.webgpu_pipeline_create_measured_ms_delta ?? summary.webgpu_pipeline_create_measured_ms_delta,
      avg_cpu_frame_ms_delta: row?.avg_cpu_frame_ms_delta ?? summary.avg_cpu_frame_ms_delta,
      avg_render_submission_ms_delta: row?.avg_render_submission_ms_delta ?? summary.avg_render_submission_ms_delta,
    };
  }

  if (summary.status === 'blocked-tail') {
    const worst = worstSceneBy(summary.scene_rows, (row) => primaryBlockerForScene(row, args)?.score || 0);
    const row = worst?.row || summary.scene_rows[0];
    const blocker = row ? primaryBlockerForScene(row, args) : null;
    return {
      cohort: summary.cohort,
      renderer: summary.renderer,
      baseline_family: summary.baseline_family,
      candidate_family: summary.candidate_family,
      status: summary.status,
      scene: row?.scene || '',
      primary_blocker: blocker?.label || 'tail/low-FPS regression',
      avg_fps_delta_pct: row?.avg_fps_delta_pct ?? summary.avg_fps_delta_pct,
      one_percent_low_fps_delta: row?.one_percent_low_fps_delta ?? summary.one_percent_low_fps_delta,
      point_one_percent_low_fps_delta: row?.point_one_percent_low_fps_delta ?? summary.point_one_percent_low_fps_delta,
      p95_frame_ms_delta: row?.p95_frame_ms_delta ?? summary.p95_frame_ms_delta,
      p99_frame_ms_delta: row?.p99_frame_ms_delta ?? summary.p99_frame_ms_delta,
      dropped_frames_delta: row?.dropped_frames_delta ?? summary.dropped_frames_delta,
      shader_compile_events_delta: row?.shader_compile_events_delta ?? summary.shader_compile_events_delta,
      webgpu_pipeline_create_measured_ms_delta:
        row?.webgpu_pipeline_create_measured_ms_delta ?? summary.webgpu_pipeline_create_measured_ms_delta,
      avg_cpu_frame_ms_delta: row?.avg_cpu_frame_ms_delta ?? summary.avg_cpu_frame_ms_delta,
      avg_render_submission_ms_delta: row?.avg_render_submission_ms_delta ?? summary.avg_render_submission_ms_delta,
    };
  }

  if (summary.status === 'blocked-throughput') {
    const worst = worstSceneBy(summary.scene_rows, (row) => Number.isFinite(row.avg_fps_delta_pct) ? -row.avg_fps_delta_pct : 0);
    const row = worst?.row || summary.scene_rows[0];
    return {
      cohort: summary.cohort,
      renderer: summary.renderer,
      baseline_family: summary.baseline_family,
      candidate_family: summary.candidate_family,
      status: summary.status,
      scene: row?.scene || '',
      primary_blocker: `avg FPS ${round(row?.avg_fps_delta_pct ?? summary.min_fps_delta_pct, 2)}%`,
      avg_fps_delta_pct: row?.avg_fps_delta_pct ?? summary.avg_fps_delta_pct,
      one_percent_low_fps_delta: row?.one_percent_low_fps_delta ?? summary.one_percent_low_fps_delta,
      point_one_percent_low_fps_delta: row?.point_one_percent_low_fps_delta ?? summary.point_one_percent_low_fps_delta,
      p95_frame_ms_delta: row?.p95_frame_ms_delta ?? summary.p95_frame_ms_delta,
      p99_frame_ms_delta: row?.p99_frame_ms_delta ?? summary.p99_frame_ms_delta,
      dropped_frames_delta: row?.dropped_frames_delta ?? summary.dropped_frames_delta,
      shader_compile_events_delta: row?.shader_compile_events_delta ?? summary.shader_compile_events_delta,
      webgpu_pipeline_create_measured_ms_delta:
        row?.webgpu_pipeline_create_measured_ms_delta ?? summary.webgpu_pipeline_create_measured_ms_delta,
      avg_cpu_frame_ms_delta: row?.avg_cpu_frame_ms_delta ?? summary.avg_cpu_frame_ms_delta,
      avg_render_submission_ms_delta: row?.avg_render_submission_ms_delta ?? summary.avg_render_submission_ms_delta,
    };
  }

  const worst = worstSceneBy(summary.scene_rows, (row) => Number.isFinite(row.avg_fps_delta_pct) ? -row.avg_fps_delta_pct : 0);
  const row = worst?.row || summary.scene_rows[0];
  return {
    cohort: summary.cohort,
    renderer: summary.renderer,
    baseline_family: summary.baseline_family,
    candidate_family: summary.candidate_family,
    status: summary.status,
    scene: row?.scene || '',
    primary_blocker: `avg FPS ${round(row?.avg_fps_delta_pct ?? summary.avg_fps_delta_pct, 2)}%`,
    avg_fps_delta_pct: row?.avg_fps_delta_pct ?? summary.avg_fps_delta_pct,
    one_percent_low_fps_delta: row?.one_percent_low_fps_delta ?? summary.one_percent_low_fps_delta,
    point_one_percent_low_fps_delta: row?.point_one_percent_low_fps_delta ?? summary.point_one_percent_low_fps_delta,
    p95_frame_ms_delta: row?.p95_frame_ms_delta ?? summary.p95_frame_ms_delta,
    p99_frame_ms_delta: row?.p99_frame_ms_delta ?? summary.p99_frame_ms_delta,
    dropped_frames_delta: row?.dropped_frames_delta ?? summary.dropped_frames_delta,
    shader_compile_events_delta: row?.shader_compile_events_delta ?? summary.shader_compile_events_delta,
    webgpu_pipeline_create_measured_ms_delta:
      row?.webgpu_pipeline_create_measured_ms_delta ?? summary.webgpu_pipeline_create_measured_ms_delta,
    avg_cpu_frame_ms_delta: row?.avg_cpu_frame_ms_delta ?? summary.avg_cpu_frame_ms_delta,
    avg_render_submission_ms_delta: row?.avg_render_submission_ms_delta ?? summary.avg_render_submission_ms_delta,
  };
}

function buildBlockerDiagnostics(families, args) {
  return families
    .map((summary) => blockerDiagnostic(summary, args))
    .filter(Boolean);
}

function blockerDiagnosticsMarkdown(rows) {
  if (!rows.length) {
    return [
      '## Blocker Diagnostics',
      '',
      'No non-candidate families need blocker diagnostics.',
      '',
    ];
  }
  return [
    '## Blocker Diagnostics',
    '',
    'Primary blocker is the worst scene-level issue for each non-candidate family, so the next iteration can target the scene and metric that prevents retention.',
    '',
    '| Cohort | Renderer | Candidate | Status | Blocking Scene | Primary Blocker | FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms |',
    '| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    ...rows.map((row) => `| ${row.cohort} | ${row.renderer} | ${row.candidate_family} | ${row.status} | ${row.scene} | ${row.primary_blocker} | ${round(row.avg_fps_delta_pct, 2)} | ${round(row.one_percent_low_fps_delta, 2)} | ${round(row.point_one_percent_low_fps_delta, 2)} | ${round(row.p95_frame_ms_delta, 2)} | ${round(row.p99_frame_ms_delta, 2)} | ${round(row.dropped_frames_delta, 2)} | ${round(row.shader_compile_events_delta, 2)} | ${round(row.webgpu_pipeline_create_measured_ms_delta, 2)} | ${round(row.avg_cpu_frame_ms_delta, 2)} | ${round(row.avg_render_submission_ms_delta, 2)} |`),
    '',
  ];
}

function describeFamily(row) {
  if (!row) return 'no comparable fork-over-baseline family';
  return `${row.candidate_family} vs ${row.baseline_family}: status=${row.status}, scenes=${row.scenes}, avg_fps_delta_pct=${round(row.avg_fps_delta_pct, 2)}, p99_delta_ms=${round(row.p99_frame_ms_delta, 2)}`;
}

function buildRequiredCandidateGate(families, requiredRenderers) {
  const rendererRows = requiredRenderers.map((renderer) => {
    const rows = families.filter((row) => String(row.renderer).toLowerCase() === renderer);
    const candidates = rows.filter((row) => row.status === 'candidate');
    const best = rows[0] || null;
    return {
      renderer,
      ok: candidates.length > 0,
      candidate_count: candidates.length,
      best_status: best ? best.status : 'missing',
      best_candidate_family: best ? best.candidate_family : '',
      best_baseline_family: best ? best.baseline_family : '',
      best_scenes: best ? best.scenes : 0,
      best_avg_fps_delta_pct: best ? best.avg_fps_delta_pct : null,
      best_min_fps_delta_pct: best ? best.min_fps_delta_pct : null,
      best_p99_frame_ms_delta: best ? best.p99_frame_ms_delta : null,
      best_dropped_frames_delta: best ? best.dropped_frames_delta : null,
      best_shader_compile_events_delta: best ? best.shader_compile_events_delta : null,
      best_webgpu_pipeline_create_measured_ms_delta:
        best ? best.webgpu_pipeline_create_measured_ms_delta : null,
      best_avg_cpu_frame_ms_delta: best ? best.avg_cpu_frame_ms_delta : null,
      best_avg_render_submission_ms_delta: best ? best.avg_render_submission_ms_delta : null,
      failure: candidates.length ? '' : `${renderer}: ${describeFamily(best)}`,
      candidate_families: candidates.map((row) => ({
        cohort: row.cohort,
        baseline_family: row.baseline_family,
        candidate_family: row.candidate_family,
        evidence_class: row.evidence_class,
        profile_cache_mode: row.profile_cache_mode,
        profile_cache_key: row.profile_cache_key,
        scenes: row.scenes,
        scene_names: row.scene_names,
        avg_fps_delta_pct: row.avg_fps_delta_pct,
        min_fps_delta_pct: row.min_fps_delta_pct,
        p99_frame_ms_delta: row.p99_frame_ms_delta,
        dropped_frames_delta: row.dropped_frames_delta,
        shader_compile_events_delta: row.shader_compile_events_delta,
        webgpu_pipeline_create_measured_ms_delta: row.webgpu_pipeline_create_measured_ms_delta,
      })),
    };
  });
  return {
    required_renderers: requiredRenderers,
    ok: rendererRows.every((row) => row.ok),
    renderers: rendererRows,
    failures: rendererRows.filter((row) => !row.ok).map((row) => row.failure),
  };
}

function requiredCandidateGateMarkdown(gate) {
  if (!gate.required_renderers.length) return [];
  return [
    '## Required Speedup Claim Gate',
    '',
    `Required renderers: ${gate.required_renderers.join(', ')}`,
    `Status: ${gate.ok ? 'pass' : 'fail'}`,
    '',
    '| Renderer | Candidate Families | Best Status | Best Candidate | Scenes | Avg FPS Delta % | Min FPS Delta % | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms |',
    '| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    ...gate.renderers.map((row) => `| ${row.renderer} | ${row.candidate_count} | ${row.best_status} | ${row.best_candidate_family || ''} | ${row.best_scenes} | ${round(row.best_avg_fps_delta_pct, 2)} | ${round(row.best_min_fps_delta_pct, 2)} | ${round(row.best_p99_frame_ms_delta, 2)} | ${round(row.best_dropped_frames_delta, 2)} | ${round(row.best_shader_compile_events_delta, 2)} | ${round(row.best_webgpu_pipeline_create_measured_ms_delta, 2)} |`),
    '',
    ...(gate.failures.length ? ['Failures:', ...gate.failures.map((failure) => `- ${failure}`), ''] : []),
  ];
}

function buildBaselineSelectionDiagnostics(rows) {
  const byKey = new Map();
  for (const row of rows) {
    if (!(row.compatible_baseline_count > 1)) continue;
    const key = [
      row.cohort,
      row.renderer,
      row.scene,
      row.baseline_variant,
      row.baseline_family,
      ...(row.compatible_baseline_variants || []),
    ].join('|');
    if (byKey.has(key)) continue;
    byKey.set(key, {
      cohort: row.cohort,
      renderer: row.renderer,
      scene: row.scene,
      baseline_family: row.baseline_family,
      selected_baseline_variant: row.baseline_variant,
      compatible_baseline_count: row.compatible_baseline_count,
      compatible_baseline_variants: row.compatible_baseline_variants || [],
    });
  }
  return [...byKey.values()]
    .sort((a, b) => a.cohort.localeCompare(b.cohort) ||
      a.renderer.localeCompare(b.renderer) ||
      a.scene.localeCompare(b.scene) ||
      a.selected_baseline_variant.localeCompare(b.selected_baseline_variant));
}

function baselineSelectionMarkdown(rows) {
  if (!rows.length) return [];
  return [
    '## Baseline Selection',
    '',
    'When multiple compatible stock baselines exist for the same exact renderer, scene, revision, duration, warmup, texture mode, GPU timing mode, WebGPU pipeline-instrumentation mode, profile-cache mode/key, and resource-warmup setting, this analyzer compares fork candidates against the fastest valid stock baseline. This is intentionally conservative for speedup claims.',
    '',
    '| Cohort | Renderer | Scene | Baseline Family | Selected Baseline | Compatible Baselines |',
    '| --- | --- | --- | --- | --- | --- |',
    ...rows.map((row) => `| ${row.cohort} | ${row.renderer} | ${row.scene} | ${row.baseline_family} | ${row.selected_baseline_variant} | ${row.compatible_baseline_variants.join(', ')} |`),
    '',
  ];
}

function reasonCounts(filtered) {
  const counts = new Map();
  for (const item of filtered) {
    counts.set(item.reason, (counts.get(item.reason) || 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([reason, count]) => ({ reason, count }));
}

const args = parseArgs(process.argv);
const inputFiles = args.files.map(readInputFile);
const inputFileDigest = inputDigest(inputFiles);
const loaded = inputFiles.map((entry) => {
  const result = JSON.parse(entry.content.toString('utf8').replace(/^\uFEFF/, ''));
  result.__file = entry.file;
  return result;
});

const accepted = [];
const filtered = [];
for (const result of loaded) {
  const reason = invalidReason(result, args);
  if (reason) {
    filtered.push({ file: result.__file, variant: variantOf(result), reason });
  } else {
    accepted.push(result);
  }
}

const byCompatibility = new Map();
for (const result of accepted) {
  const key = compatibilityKey(result);
  if (!byCompatibility.has(key)) byCompatibility.set(key, []);
  byCompatibility.get(key).push(result);
}

const sceneRows = [];
for (const group of byCompatibility.values()) {
  const baselineInfo = selectBaselineForCompatibilityGroup(group);
  if (!baselineInfo) continue;
  for (const candidate of group.filter((result) => isFork(result) && !isBaseline(result))) {
    sceneRows.push(compareWithSelectedBaseline(candidate, baselineInfo));
  }
}

const families = summarizeFamilies(sceneRows, args);
const blockerDiagnostics = buildBlockerDiagnostics(families, args);
const reasonRows = reasonCounts(filtered);
const requiredCandidateGate = buildRequiredCandidateGate(families, args.requiredCandidateRenderers);
const baselineSelectionDiagnostics = buildBaselineSelectionDiagnostics(sceneRows);

const optionSummary = {
  min_measured_seconds: args.minMeasuredSeconds,
  min_scenes: args.minScenes,
  p99_regression_ms: args.p99RegressionMs,
  min_avg_fps_delta_pct: args.minAvgFpsDeltaPct,
  scene_regression_pct: args.sceneRegressionPct,
  low_regression_fps: args.lowRegressionFps,
  dropped_frames_regression: args.droppedFramesRegression,
  cpu_frame_regression_ms: args.cpuFrameRegressionMs,
  render_submission_regression_ms: args.renderSubmissionRegressionMs,
  pipeline_create_regression_ms: args.pipelineCreateRegressionMs,
  shader_compile_regression_events: args.shaderCompileRegressionEvents,
  include_attribution: args.includeAttribution,
  include_diagnostic_texture_modes: args.includeDiagnosticTextureModes,
  require_frame_times: args.requireFrameTimes,
  require_checkout: args.requireCheckout,
  require_package_size: args.requirePackageSize,
  required_candidate_renderers: args.requiredCandidateRenderers,
  required_scenes: args.requiredScenes,
  expected_chromium_revision: args.expectedChromiumRevision,
  expected_fork_revision: args.expectedForkRevision,
  build_args_compatibility_policy: 'same-build-args-hash',
  environment_compatibility_policy: 'same-platform-driver-gpu-device',
  complexity_compatibility_policy: 'same-explicit-benchmark-complexity',
  webgpu_bundle_mode_compatibility_policy: 'same-webgpu-bundle-mode',
  webgpu_pipeline_instrumentation_compatibility_policy: 'same-webgpu-pipeline-instrumentation-mode',
  resource_warmup_compatibility_policy: 'same-precompile-prerender-compile-texture-render-target-count-gpu-settle-and-webgpu-pipeline-quiet-mode',
  profile_cache_compatibility_policy: 'same-profile-cache-mode-and-key',
  warm_profile_speed_claim_policy: 'explicit-reuse-is-cache-attribution-not-retained-candidate',
  required_benchmark_evidence_policy: 'candidate-analysis-filters-missing-required-metric-fields',
  gpu_timing_evidence_policy: 'candidate-analysis-requires-explicit-gpu-timing-mode',
  stability_evidence_policy: 'candidate-analysis-filters-stability-artifacts',
  trace_instrumentation_policy: 'candidate-analysis-filters-viewer-and-source-webgpu-attribution-runs',
  trusted_experiment_metadata_policy: 'candidate-analysis-filters-unsafe-experiments-missing-viewer-trusted-content-metadata',
  webgpu_cpu_fallback_policy: 'candidate-analysis-filters-webgpu-cpu-texture-fallback-and-missing-copyexternalimage-rejection',
  webgpu_pipeline_quiet_success_policy: 'candidate-analysis-filters-unachieved-or-measured-pipeline-create-webgpu-pipeline-quiet-warmup',
  shader_compile_stall_policy: 'candidate-analysis-blocks-shader-compile-event-and-webgpu-pipeline-create-time-regressions',
  dropped_frame_regression_policy: 'candidate-analysis-blocks-dropped-frame-regressions',
  cpu_submission_regression_policy: 'candidate-analysis-blocks-cpu-frame-and-render-submission-regressions',
  package_size_speed_claim_policy: 'require-package-size-when-enabled',
  baseline_selection_policy: 'fastest-compatible-baseline',
};

const report = {
  generated_at: new Date().toISOString(),
  options: optionSummary,
  params: optionSummary,
  input_file_digest: inputFileDigest,
  input_files: inputFiles.map(({ path: inputPath, sha256, size_bytes: sizeBytes }) => ({
    path: inputPath,
    sha256,
    size_bytes: sizeBytes,
  })),
  input_count: loaded.length,
  accepted_count: accepted.length,
  filtered_count: filtered.length,
  filtered_reason_counts: reasonRows,
  baseline_selection_diagnostics: baselineSelectionDiagnostics,
  required_candidate_gate: requiredCandidateGate,
  blocker_diagnostics: blockerDiagnostics,
  families,
};

const lines = [
  '# Candidate Speed Analysis',
  '',
  `Generated: ${report.generated_at}`,
  '',
  `Input results: ${loaded.length}`,
  `Input file digest: \`${inputFileDigest}\``,
  `Accepted results: ${accepted.length}`,
  `Filtered results: ${filtered.length}`,
  '',
  `Decision rule: a family is a \`candidate\` only when at least ${args.minScenes} distinct scenes are covered${args.requiredScenes.length ? `, all required scenes are present (${args.requiredScenes.join(', ')})` : ''}, average FPS improves by at least ${round(args.minAvgFpsDeltaPct, 2)}%, no individual scene has a material average-FPS regression, average low-FPS/tail-latency deltas do not materially regress, dropped frames do not increase by more than ${round(args.droppedFramesRegression, 0)} on any scene, CPU frame time does not increase by more than ${round(args.cpuFrameRegressionMs, 2)} ms on any scene, render submission time does not increase by more than ${round(args.renderSubmissionRegressionMs, 2)} ms on any scene, shader compile events do not increase by more than ${round(args.shaderCompileRegressionEvents, 0)} on any scene, WebGPU measured-window pipeline creation time does not increase by more than ${round(args.pipelineCreateRegressionMs, 2)} ms on any scene, required benchmark evidence fields, including explicit positive benchmark complexity and explicit GPU-timing mode, are present, stability artifacts are filtered out, viewer-side WebGPU queue attribution, viewer-side WebGPU command-encoder attribution, viewer-side WebGPU bind-group attribution, viewer-side WebGPU pipeline-state attribution, viewer-side WebGPU buffer-state attribution, viewer-side WebGPU render-state attribution, viewer-side WebGPU immediate-data attribution, and source-added WebGPU queue trace attribution runs are filtered out, explicit WebGPU CPU texture fallback/readback evidence and copyExternalImage upload experiments without CPU-fallback rejection are filtered out, trusted-only experiment metadata or browser flags require viewer_mode=true and viewer_trusted_content=true, WebGPU pipeline-quiet warmup runs are filtered out unless the requested quiet window was achieved and no pipelines were created during the measured window, and the result is fresh-profile evidence. Positive average FPS with incomplete scene coverage is \`needs-suite\`; positive average FPS below the minimum suite threshold is \`weak-throughput\`; positive average FPS with a material scene throughput regression is \`blocked-throughput\`; positive average FPS with shader compile event or WebGPU pipeline-create timing regression is \`blocked-shader-stalls\`; positive average FPS with dropped-frame regression is \`blocked-dropped-frames\`; positive average FPS with CPU frame or render submission regression is \`blocked-cpu-overhead\`; positive average FPS with low-FPS or p95/p99 regression is \`blocked-tail\`; explicit profile-reuse wins are \`cache-attribution\` and require a matching fresh-profile official run before retained speed claims. Duplicate rows for the same family, profile-cache mode/key, and scene are collapsed to the most conservative representative row. Comparisons require the same build-args hash, platform, driver, GPU device identity, explicit benchmark complexity and explicit GPU-timing mode, WebGPU BundleGroup/render-bundle scene mode, WebGPU pipeline-instrumentation mode, requested resource warmup mode, resource precompile target count, preinitialized texture/render-target count, GPU-settle warmup mode, WebGPU pipeline-quiet warmup mode, and profile-cache mode/key while leaving backend choice available as an optimization variable. If multiple compatible stock baselines are present, the comparison uses the fastest valid stock baseline for that exact compatibility group.${args.requireCheckout ? ' Accepted artifacts must report browser_is_from_checkout=true.' : ''}${args.requirePackageSize ? ' Accepted artifacts must include positive package_size_mb evidence.' : ''}`,
  '',
  ...baselineSelectionMarkdown(baselineSelectionDiagnostics),
  '## Candidate Families',
  '',
  ...markdownTable(families),
  '',
  ...blockerDiagnosticsMarkdown(blockerDiagnostics),
  ...requiredCandidateGateMarkdown(requiredCandidateGate),
  '## Filtered Inputs',
  '',
  '| Reason | Count |',
  '| --- | ---: |',
  ...(reasonRows.length ? reasonRows.map((row) => `| ${row.reason.replaceAll('|', '\\|')} | ${row.count} |`) : ['| None | 0 |']),
  '',
];

const markdown = lines.join('\n');
if (args.output) {
  fs.mkdirSync(path.dirname(args.output), { recursive: true });
  fs.writeFileSync(args.output, markdown);
  console.log(`Wrote ${args.output}`);
} else if (!args.quiet) {
  console.log(markdown);
}

if (args.json) {
  fs.mkdirSync(path.dirname(args.json), { recursive: true });
  fs.writeFileSync(args.json, JSON.stringify(report, null, 2));
  console.log(`Wrote ${args.json}`);
}

if (!requiredCandidateGate.ok) {
  console.error(`Required speedup claim gate failed: ${requiredCandidateGate.failures.join('; ')}`);
  process.exitCode = 1;
}

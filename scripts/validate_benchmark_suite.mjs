#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const defaultScenes = [
  'many-draw-calls',
  'instancing',
  'shader-heavy',
  'texture-streaming',
  'postprocessing',
  'large-static',
  'gltf-loader-stress',
];

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

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
  if (!fs.existsSync(resolvedDir)) return [];

  return fs.readdirSync(resolvedDir)
    .filter((entry) => matcher.test(entry))
    .map((entry) => path.join(resolvedDir, entry));
}

function parseArgs(argv) {
  const args = {
    files: [],
    renderer: '',
    variant: '',
    expectedScenes: defaultScenes,
    requireCheckout: false,
    requireBuildArgs: false,
    expectedBuildArgsHash: '',
    expectedChromiumRevision: '',
    expectedBrowser: '',
    requireForkRevision: false,
    expectedForkRevision: '',
    forbidSmoke: false,
    rejectSoftwareRendering: false,
    rejectGpuInstability: false,
    requireGpuMetadata: false,
    requirePackageSize: false,
    requireFrameTimes: false,
    expectedMeasuredSeconds: null,
    expectedWarmupSeconds: null,
    expectedComplexity: null,
    expectedFlagMetadata: [],
    requiredBrowserFlag: [],
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--renderer') {
      args.renderer = argv[++i];
    } else if (token === '--variant') {
      args.variant = argv[++i];
    } else if (token === '--expectedScenes') {
      args.expectedScenes = argv[++i].split(',').map((item) => item.trim()).filter(Boolean);
    } else if (token === '--requireCheckout') {
      args.requireCheckout = true;
    } else if (token === '--requireBuildArgs') {
      args.requireBuildArgs = true;
    } else if (token === '--expectedBuildArgsHash') {
      args.expectedBuildArgsHash = argv[++i].toLowerCase();
    } else if (token === '--expectedChromiumRevision') {
      args.expectedChromiumRevision = argv[++i];
    } else if (token === '--expectedBrowser') {
      args.expectedBrowser = argv[++i];
    } else if (token === '--requireForkRevision') {
      args.requireForkRevision = true;
    } else if (token === '--expectedForkRevision') {
      args.expectedForkRevision = argv[++i];
    } else if (token === '--forbidSmoke') {
      args.forbidSmoke = true;
    } else if (token === '--rejectSoftwareRendering') {
      args.rejectSoftwareRendering = true;
    } else if (token === '--rejectGpuInstability') {
      args.rejectGpuInstability = true;
    } else if (token === '--requireGpuMetadata') {
      args.requireGpuMetadata = true;
    } else if (token === '--requirePackageSize') {
      args.requirePackageSize = true;
    } else if (token === '--requireFrameTimes') {
      args.requireFrameTimes = true;
    } else if (token === '--expectedMeasuredSeconds') {
      args.expectedMeasuredSeconds = Number(argv[++i]);
    } else if (token === '--expectedWarmupSeconds') {
      args.expectedWarmupSeconds = Number(argv[++i]);
    } else if (token === '--expectedComplexity') {
      args.expectedComplexity = Number(argv[++i]);
    } else if (token === '--expectedFlagMetadata') {
      args.expectedFlagMetadata.push(argv[++i]);
    } else if (token === '--requiredBrowserFlag') {
      args.requiredBrowserFlag.push(argv[++i]);
    } else {
      args.files.push(...expandFileArg(token));
    }
  }

  if (!args.renderer) {
    throw new Error('Missing --renderer');
  }
  if (!['webgl2', 'webgpu'].includes(args.renderer)) {
    throw new Error('--renderer must be webgl2 or webgpu');
  }
  if (!args.expectedScenes.length) {
    throw new Error('--expectedScenes must contain at least one scene');
  }
  if (new Set(args.expectedScenes).size !== args.expectedScenes.length) {
    throw new Error('--expectedScenes contains duplicate scene names');
  }
  if (!args.files.length) {
    throw new Error('No benchmark result files matched.');
  }
  for (const [name, value] of [
    ['--expectedMeasuredSeconds', args.expectedMeasuredSeconds],
    ['--expectedWarmupSeconds', args.expectedWarmupSeconds],
    ['--expectedComplexity', args.expectedComplexity],
  ]) {
    if (value !== null && (!Number.isFinite(value) || value < 0 || (name === '--expectedComplexity' && value <= 0))) {
      throw new Error(name === '--expectedComplexity' ? `${name} must be greater than zero` : `${name} must be a non-negative number`);
    }
  }
  return args;
}

function parseExpectedValue(raw) {
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  if (raw === 'null') return null;
  if (/^-?\d+(\.\d+)?$/.test(raw)) return Number(raw);
  return raw;
}

function parseExpectedFlagMetadata(entries) {
  return entries.map((entry) => {
    const separator = entry.indexOf('=');
    if (separator <= 0) {
      throw new Error(`--expectedFlagMetadata must use key=value form: ${entry}`);
    }
    return {
      key: entry.slice(0, separator),
      expected: parseExpectedValue(entry.slice(separator + 1)),
    };
  });
}

function validateMetrics(files) {
  const validator = path.join(__dirname, 'validate_metrics.mjs');
  const result = spawnSync(process.execPath, [validator, ...files], {
    encoding: 'utf8',
    shell: false,
  });
  if (result.status !== 0) {
    const output = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
    throw new Error(output || 'validate_metrics.mjs failed');
  }
}

function variantOf(result) {
  return result.benchmark_variant || 'unknown';
}

function softwareRendererReason(result) {
  const haystack = [
    result.gpu_name,
    result.driver_version,
    result.angle_backend,
  ]
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

function hasGpuMetadata(result) {
  return [result.gpu_name, result.driver_version, result.angle_backend]
    .some((value) => typeof value === 'string' && value.trim().length > 0);
}

function numericEquals(actual, expected) {
  return typeof actual === 'number' && Number.isFinite(actual) && Math.abs(actual - expected) < 0.001;
}

function metadataValueMatches(actual, expected) {
  if (typeof expected === 'number') return numericEquals(actual, expected);
  return actual === expected;
}

function normalizeBrowserPath(value) {
  const normalized = path.resolve(String(value));
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function sameBrowserPath(actual, expected) {
  return normalizeBrowserPath(actual) === normalizeBrowserPath(expected);
}

function formatValue(value) {
  return value === undefined ? 'missing' : JSON.stringify(value);
}

function validateRequiredBrowserFlags(errors, result, label, requiredFlags) {
  if (!requiredFlags.length) {
    return;
  }
  if (!Array.isArray(result.browser_flags)) {
    errors.push(`${label}: browser_flags must be an array when --requiredBrowserFlag is set`);
    return;
  }
  for (const flag of requiredFlags) {
    if (!result.browser_flags.includes(flag)) {
      errors.push(`${label}: browser_flags must include ${flag}`);
    }
  }
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

function isWebGpuBlobCacheHashValidationExperiment(result) {
  if (result.renderer_type !== 'webgpu') return false;
  if (result.webgpu_blob_cache_hash_validation_disabled === true) return true;
  if (/blob-cache-hash-validation/i.test(variantOf(result))) return true;
  return flagTokenListIncludes(result.browser_flags, '--disable-dawn-features', 'blob_cache_hash_validation');
}

function validateWebGpuBlobCacheEligibility(errors, result, label) {
  if (!isWebGpuBlobCacheHashValidationExperiment(result)) {
    return;
  }

  if (result.webgpu_blob_cache_expected_available !== true) {
    errors.push(`${label}: WebGPU blob-cache hash-validation experiment requires webgpu_blob_cache_expected_available=true`);
  }
  if (result.webgpu_blob_cache_origin_eligible !== true) {
    errors.push(`${label}: WebGPU blob-cache hash-validation experiment requires webgpu_blob_cache_origin_eligible=true`);
  }
  if (result.webgpu_blob_cache_disabled_by_explicit_toggle === true ||
      flagTokenListIncludes(result.browser_flags, '--enable-dawn-features', 'disable_blob_cache')) {
    errors.push(`${label}: WebGPU blob-cache hash-validation experiment cannot enable Dawn disable_blob_cache`);
  }
  if (!['http', 'https'].includes(result.viewer_url_scheme)) {
    errors.push(`${label}: WebGPU blob-cache hash-validation experiment requires an HTTP(S) viewer_url_scheme`);
  }
  if (typeof result.viewer_origin !== 'string' || result.viewer_origin.trim().length === 0) {
    errors.push(`${label}: WebGPU blob-cache hash-validation experiment requires a non-empty viewer_origin`);
  }
}

function validateRequiredFrameTimes(errors, result) {
  if (!Array.isArray(result.frame_times_ms) || result.frame_times_ms.length === 0) {
    errors.push(`${result.scene_name}: frame_times_ms must be a non-empty array when --requireFrameTimes is set`);
    return;
  }

  result.frame_times_ms.forEach((value, index) => {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
      errors.push(`${result.scene_name}: frame_times_ms[${index}] must be a non-negative finite number`);
    }
  });
}

function validateGpuStability(errors, result) {
  if (typeof result.webgpu_device_lost !== 'boolean') {
    errors.push(`${result.scene_name}: webgpu_device_lost must be a boolean when --rejectGpuInstability is set`);
  }
  if (typeof result.webgl_context_currently_lost !== 'boolean') {
    errors.push(`${result.scene_name}: webgl_context_currently_lost must be a boolean when --rejectGpuInstability is set`);
  }
  if (typeof result.webgl_context_lost_count !== 'number' || !Number.isFinite(result.webgl_context_lost_count)) {
    errors.push(`${result.scene_name}: webgl_context_lost_count must be a finite number when --rejectGpuInstability is set`);
  }
  if (typeof result.render_error_count !== 'number' || !Number.isFinite(result.render_error_count)) {
    errors.push(`${result.scene_name}: render_error_count must be a finite number when --rejectGpuInstability is set`);
  }
  if (result.webgpu_device_lost === true) {
    errors.push(`${result.scene_name}: WebGPU device loss is not allowed in performance evidence`);
  }
  if (result.webgl_context_currently_lost === true) {
    errors.push(`${result.scene_name}: WebGL context is currently lost`);
  }
  if (typeof result.webgl_context_lost_count === 'number' && Number.isFinite(result.webgl_context_lost_count) && result.webgl_context_lost_count > 0) {
    errors.push(`${result.scene_name}: WebGL context loss count must be zero`);
  }
  if (typeof result.render_error_count === 'number' && Number.isFinite(result.render_error_count) && result.render_error_count > 0) {
    errors.push(`${result.scene_name}: render_error_count must be zero`);
  }
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

function validateWebGpuCpuFallback(errors, result) {
  if (result.renderer_type !== 'webgpu') {
    return;
  }
  if (isCopyExternalImageUploadExperiment(result) &&
      result.viewer_reject_webgpu_cpu_texture_fallback !== true) {
    errors.push(`${result.scene_name}: WebGPU copyExternalImage upload experiment requires viewer_reject_webgpu_cpu_texture_fallback=true`);
  }
  if (result.webgpu_cpu_texture_fallback_detected === true) {
    errors.push(`${result.scene_name}: WebGPU CPU texture fallback/readback is not allowed in performance evidence`);
  }
  const verdict = typeof result.webgpu_texture_copy_path_verdict === 'string'
    ? result.webgpu_texture_copy_path_verdict.trim().toLowerCase()
    : '';
  if (verdict === 'cpu-fallback-detected' || verdict === 'cpu-fallback-rejected' || verdict === 'forced-readback-detected') {
    errors.push(`${result.scene_name}: WebGPU CPU texture fallback/readback verdict is ${result.webgpu_texture_copy_path_verdict}`);
  }
  for (const field of webGpuCpuFallbackCountFields) {
    if (Number.isFinite(result[field]) && result[field] > 0) {
      errors.push(`${result.scene_name}: WebGPU CPU texture fallback/readback ${field} must be zero`);
    }
  }
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

function validateTrustedExperimentMetadata(errors, result) {
  const enabledMetadata = trustedViewerExperimentFields.filter((field) => result[field] === true);
  if (hasSwitchValue(result, 'viewer_force_angle_backend')) {
    enabledMetadata.push('viewer_force_angle_backend');
  }
  const enabledBrowserFlags = trustedBrowserExperimentFlags(result);
  if (!enabledMetadata.length && !enabledBrowserFlags.length) return;

  const enabled = [...enabledMetadata, ...enabledBrowserFlags];
  if (result.viewer_mode !== true || result.viewer_trusted_content !== true) {
    errors.push(`${result.scene_name}: trusted experiment requires viewer_mode=true and viewer_trusted_content=true (${enabled.join(', ')})`);
  }

  const webGpuOnly = webGpuOnlyTrustedViewerExperimentFields.find((field) => result[field] === true);
  if (webGpuOnly && result.renderer_type !== 'webgpu') {
    errors.push(`${result.scene_name}: WebGPU trusted experiment ${webGpuOnly} used with renderer_type=${result.renderer_type}`);
  }
  const webGl2Only = webGl2OnlyTrustedViewerExperimentFields.find((field) => result[field] === true);
  if (webGl2Only && result.renderer_type !== 'webgl2') {
    errors.push(`${result.scene_name}: WebGL2 trusted experiment ${webGl2Only} used with renderer_type=${result.renderer_type}`);
  }
}

function validateWebGpuPipelineQuietWarmup(errors, result) {
  const requestedFrames = Number(result.resource_warmup_pipeline_quiet_frames);
  if (!Number.isFinite(requestedFrames) || requestedFrames <= 0) {
    return;
  }
  if (result.renderer_type !== 'webgpu') {
    errors.push(`${result.scene_name}: WebGPU pipeline-quiet warmup is only valid for WebGPU performance evidence`);
    return;
  }
  if (result.resource_warmup_pipeline_quiet_achieved !== true) {
    errors.push(`${result.scene_name}: WebGPU pipeline-quiet warmup did not achieve the requested quiet window`);
  }
  if (!Number.isFinite(result.resource_warmup_pipeline_quiet_actual_frames)) {
    errors.push(`${result.scene_name}: WebGPU pipeline-quiet warmup requires resource_warmup_pipeline_quiet_actual_frames`);
  } else if (result.resource_warmup_pipeline_quiet_actual_frames < requestedFrames) {
    errors.push(`${result.scene_name}: WebGPU pipeline-quiet warmup actual frames ${result.resource_warmup_pipeline_quiet_actual_frames} below requested ${requestedFrames}`);
  }
  if (typeof result.resource_warmup_pipeline_quiet_error === 'string' &&
      result.resource_warmup_pipeline_quiet_error.trim().length > 0) {
    errors.push(`${result.scene_name}: WebGPU pipeline-quiet warmup reported error: ${result.resource_warmup_pipeline_quiet_error}`);
  }
  if (result.webgpu_pipeline_instrumentation_available !== true) {
    errors.push(`${result.scene_name}: WebGPU pipeline-quiet warmup requires available pipeline instrumentation`);
  }
  if (!Number.isFinite(result.webgpu_pipeline_create_measured_count)) {
    errors.push(`${result.scene_name}: WebGPU pipeline-quiet warmup requires measured-window pipeline creation telemetry`);
  } else if (result.webgpu_pipeline_create_measured_count > 0) {
    errors.push(`${result.scene_name}: WebGPU pipeline-quiet warmup still created ${result.webgpu_pipeline_create_measured_count} pipelines during the measured window`);
  }
}

function validateResourceWarmupInit(errors, result) {
  for (const field of ['resource_warmup_texture_init_error', 'resource_warmup_render_target_init_error']) {
    const value = result[field];
    if (typeof value === 'string' && value.trim().length > 0) {
      errors.push(`${result.scene_name}: resource warmup reported ${field}: ${value}`);
    }
  }
}

function validateAttributionInstrumentation(errors, result) {
  if (result.webgpu_queue_instrumentation_enabled === true) {
    errors.push(`${result.scene_name}: WebGPU queue instrumentation attribution is not allowed in performance evidence`);
  }
  if (result.webgpu_command_encoder_instrumentation_enabled === true) {
    errors.push(`${result.scene_name}: WebGPU command-encoder instrumentation attribution is not allowed in performance evidence`);
  }
  if (result.webgpu_bind_group_instrumentation_enabled === true) {
    errors.push(`${result.scene_name}: WebGPU bind-group instrumentation attribution is not allowed in performance evidence`);
  }
  if (result.webgpu_pipeline_state_instrumentation_enabled === true) {
    errors.push(`${result.scene_name}: WebGPU pipeline-state instrumentation attribution is not allowed in performance evidence`);
  }
  if (result.webgpu_buffer_state_instrumentation_enabled === true) {
    errors.push(`${result.scene_name}: WebGPU buffer-state instrumentation attribution is not allowed in performance evidence`);
  }
  if (result.webgpu_render_state_instrumentation_enabled === true) {
    errors.push(`${result.scene_name}: WebGPU render-state instrumentation attribution is not allowed in performance evidence`);
  }
  if (result.webgpu_immediate_instrumentation_enabled === true) {
    errors.push(`${result.scene_name}: WebGPU immediate instrumentation attribution is not allowed in performance evidence`);
  }
  if (result.viewer_trace_webgpu_queue === true) {
    errors.push(`${result.scene_name}: source WebGPU queue trace instrumentation is not allowed in performance evidence`);
  }
}

function validateSuite(results, args) {
  const errors = [];
  const expected = new Set(args.expectedScenes);
  const expectedFlagMetadata = parseExpectedFlagMetadata(args.expectedFlagMetadata);
  const seen = new Map();

  for (const result of results) {
    if (result.renderer_type !== args.renderer) {
      errors.push(`${result.scene_name}: renderer_type is ${result.renderer_type}, expected ${args.renderer}`);
    }
    if (args.variant && variantOf(result) !== args.variant) {
      errors.push(`${result.scene_name}: benchmark_variant is ${variantOf(result)}, expected ${args.variant}`);
    }
    if (args.requireCheckout && result.browser_is_from_checkout !== true) {
      errors.push(`${result.scene_name}: browser_is_from_checkout must be true`);
    }
    if (args.requireCheckout && !result.chromium_revision) {
      errors.push(`${result.scene_name}: chromium_revision is required for checkout-built results`);
    }
    if (args.expectedChromiumRevision && result.chromium_revision !== args.expectedChromiumRevision) {
      errors.push(`${result.scene_name}: chromium_revision is ${result.chromium_revision || 'missing'}, expected ${args.expectedChromiumRevision}`);
    }
    if (args.expectedBrowser) {
      if (typeof result.browser_executable !== 'string' || result.browser_executable.trim().length === 0) {
        errors.push(`${result.scene_name}: browser_executable is required when --expectedBrowser is set`);
      } else if (!sameBrowserPath(result.browser_executable, args.expectedBrowser)) {
        errors.push(`${result.scene_name}: browser_executable is ${result.browser_executable}, expected ${args.expectedBrowser}`);
      }
    }
    if (args.requireBuildArgs && !result.build_args_hash) {
      errors.push(`${result.scene_name}: build_args_hash is required`);
    }
    if (args.expectedBuildArgsHash && result.build_args_hash !== args.expectedBuildArgsHash) {
      errors.push(`${result.scene_name}: build_args_hash is ${result.build_args_hash || 'missing'}, expected ${args.expectedBuildArgsHash}`);
    }
    if (args.requireForkRevision && !result.fork_revision) {
      errors.push(`${result.scene_name}: fork_revision is required`);
    }
    if (args.expectedForkRevision && result.fork_revision !== args.expectedForkRevision) {
      errors.push(`${result.scene_name}: fork_revision is ${result.fork_revision || 'missing'}, expected ${args.expectedForkRevision}`);
    }
    if (args.forbidSmoke && /smoke|installed/i.test(variantOf(result))) {
      errors.push(`${result.scene_name}: smoke/installed variant is not allowed (${variantOf(result)})`);
    }
    if (args.rejectSoftwareRendering) {
      if (softwareRenderingDiagnosticOptIn(result)) {
        errors.push(`${result.scene_name}: diagnostic software-rendering opt-in is not allowed in performance evidence`);
      }
      const reason = softwareRendererReason(result);
      if (reason) {
        errors.push(`${result.scene_name}: known software-rendered GPU path is not allowed (${reason})`);
      }
    }
    if (args.rejectGpuInstability) {
      validateGpuStability(errors, result);
    }
    validateAttributionInstrumentation(errors, result);
    validateWebGpuCpuFallback(errors, result);
    validateTrustedExperimentMetadata(errors, result);
    validateWebGpuPipelineQuietWarmup(errors, result);
    validateResourceWarmupInit(errors, result);
    validateWebGpuBlobCacheEligibility(errors, result, result.scene_name);
    if (args.requireGpuMetadata && !hasGpuMetadata(result)) {
      errors.push(`${result.scene_name}: GPU metadata is required for official/trusted performance evidence`);
    }
    if (args.requirePackageSize && (
      typeof result.package_size_mb !== 'number' ||
      !Number.isFinite(result.package_size_mb) ||
      result.package_size_mb <= 0
    )) {
      errors.push(`${result.scene_name}: package_size_mb must be a positive number when package size evidence is required`);
    }
    if (args.requireFrameTimes) {
      validateRequiredFrameTimes(errors, result);
    }
    if (args.expectedMeasuredSeconds !== null && !numericEquals(result.measured_seconds, args.expectedMeasuredSeconds)) {
      errors.push(`${result.scene_name}: measured_seconds is ${result.measured_seconds}, expected ${args.expectedMeasuredSeconds}`);
    }
    if (args.expectedWarmupSeconds !== null && !numericEquals(result.warmup_seconds, args.expectedWarmupSeconds)) {
      errors.push(`${result.scene_name}: warmup_seconds is ${result.warmup_seconds}, expected ${args.expectedWarmupSeconds}`);
    }
    if (args.expectedComplexity !== null && !numericEquals(result.complexity, args.expectedComplexity)) {
      errors.push(`${result.scene_name}: complexity is ${formatValue(result.complexity)}, expected ${args.expectedComplexity}`);
    }
    validateRequiredBrowserFlags(errors, result, result.scene_name, args.requiredBrowserFlag);
    for (const { key, expected: expectedValue } of expectedFlagMetadata) {
      if (!metadataValueMatches(result[key], expectedValue)) {
        errors.push(`${result.scene_name}: ${key} is ${formatValue(result[key])}, expected ${formatValue(expectedValue)}`);
      }
    }
    if (!expected.has(result.scene_name)) {
      errors.push(`unexpected scene: ${result.scene_name}`);
    }
    if (seen.has(result.scene_name)) {
      errors.push(`duplicate scene: ${result.scene_name}`);
    }
    seen.set(result.scene_name, result);
  }

  for (const scene of expected) {
    if (!seen.has(scene)) {
      errors.push(`missing scene: ${scene}`);
    }
  }

  if (seen.size !== expected.size) {
    errors.push(`scene count mismatch: got ${seen.size}, expected ${expected.size}`);
  }

  return errors;
}

const args = parseArgs(process.argv);
const files = args.files.map((file) => path.resolve(file));
validateMetrics(files);
const results = files.map((file) => readJson(file));
const errors = validateSuite(results, args);

if (errors.length) {
  console.error('FAIL: benchmark suite validation failed');
  for (const error of errors) {
    console.error(`  ${error}`);
  }
  process.exit(1);
}

console.log(`OK: ${files.length} ${args.renderer} result files form a complete benchmark suite.`);

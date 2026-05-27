#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const webGpuStaticBundleScenes = new Set([
  'many-draw-calls',
  'texture-streaming',
  'gltf-loader-stress',
]);

const webGpuFastPathCoverageFields = [
  'webgpu_queue_write_texture_common_layout_count',
  'webgpu_queue_write_texture_common_extent_count',
  'webgpu_queue_copy_external_image_default_origin_count',
  'webgpu_queue_copy_external_image_common_origin_count',
  'webgpu_queue_copy_external_image_explicit_common_origin_count',
  'webgpu_queue_copy_external_image_srgb_destination_count',
  'webgpu_queue_copy_external_image_full_source_count',
  'webgpu_pipeline_descriptor_stack_fast_path_eligible_count',
  'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count',
];

function parseArgs(argv) {
  const args = {
    files: [],
    expectedScene: '',
    expectedRenderer: '',
    expectedBrowser: '',
    expectedDuration: null,
    expectedWarmup: null,
    expectedStartDelayMs: null,
    expectedFlagMetadata: [],
    requiredBrowserFlag: [],
    rejectSoftwareRendering: false,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--expectedScene') {
      args.expectedScene = argv[++i];
    } else if (token === '--expectedRenderer') {
      args.expectedRenderer = argv[++i];
    } else if (token === '--expectedBrowser') {
      args.expectedBrowser = argv[++i];
    } else if (token === '--expectedDuration') {
      args.expectedDuration = Number(argv[++i]);
    } else if (token === '--expectedWarmup') {
      args.expectedWarmup = Number(argv[++i]);
    } else if (token === '--expectedStartDelayMs') {
      args.expectedStartDelayMs = Number(argv[++i]);
    } else if (token === '--expectedFlagMetadata') {
      args.expectedFlagMetadata.push(argv[++i]);
    } else if (token === '--requiredBrowserFlag') {
      args.requiredBrowserFlag.push(argv[++i]);
    } else if (token === '--rejectSoftwareRendering') {
      args.rejectSoftwareRendering = true;
    } else if (token.startsWith('--')) {
      throw new Error(`Unknown argument: ${token}`);
    } else {
      args.files.push(token);
    }
  }

  if (!args.files.length) {
    throw new Error('Usage: node scripts/validate_trace_result.mjs [options] <trace.result.json...>');
  }
  for (const [name, value] of [
    ['--expectedDuration', args.expectedDuration],
    ['--expectedWarmup', args.expectedWarmup],
    ['--expectedStartDelayMs', args.expectedStartDelayMs],
  ]) {
    if (value !== null && (!Number.isFinite(value) || value < 0)) {
      throw new Error(`${name} must be a non-negative number`);
    }
  }
  return args;
}

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function normalizeBrowserPath(value) {
  const normalized = path.resolve(String(value));
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function sameBrowserPath(actual, expected) {
  return normalizeBrowserPath(actual) === normalizeBrowserPath(expected);
}

function numericEquals(actual, expected) {
  return isFiniteNumber(actual) && Math.abs(actual - expected) < 0.001;
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

function metadataValueMatches(actual, expected) {
  if (typeof expected === 'number') return numericEquals(actual, expected);
  return actual === expected;
}

function formatValue(value) {
  return value === undefined ? 'missing' : JSON.stringify(value);
}

function validateOptionalStringArray(errors, data, key, label) {
  if (!(key in data)) {
    return;
  }
  if (!Array.isArray(data[key])) {
    errors.push(`${label}: ${key} must be an array when present`);
    return;
  }
  data[key].forEach((value, index) => {
    if (typeof value !== 'string') {
      errors.push(`${label}: ${key}[${index}] must be a string`);
    }
  });
}

function validateRequiredBrowserFlags(errors, data, label, requiredFlags) {
  if (!requiredFlags.length) {
    return;
  }
  if (!Array.isArray(data.browser_flags)) {
    errors.push(`${label}: browser_flags must be an array when --requiredBrowserFlag is set`);
    return;
  }
  for (const flag of requiredFlags) {
    if (!data.browser_flags.includes(flag)) {
      errors.push(`${label}: browser_flags must include ${flag}`);
    }
  }
}

function softwareRendererReason(metadata) {
  const haystack = [
    metadata?.gpu_name,
    metadata?.driver_version,
    metadata?.angle_backend,
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

function validateNoSoftwareRenderer(errors, data, benchmark, label, rejectSoftwareRendering) {
  if (!rejectSoftwareRendering) return;

  if (data.allow_software_rendering === true || data.allowSoftwareRendering === true) {
    errors.push(`${label}: diagnostic software-rendering opt-in is not allowed in trace evidence`);
  }

  const sidecarReason = softwareRendererReason(data);
  if (sidecarReason) {
    errors.push(`${label}: known software-rendered GPU path is not allowed (${sidecarReason})`);
  }

  if (benchmark && typeof benchmark === 'object' && !Array.isArray(benchmark)) {
    if (benchmark.allow_software_rendering === true || benchmark.allowSoftwareRendering === true) {
      errors.push(`${label}: benchmark_result uses diagnostic software-rendering opt-in`);
    }
    const benchmarkReason = softwareRendererReason(benchmark);
    if (benchmarkReason) {
      errors.push(`${label}: benchmark_result uses known software-rendered GPU path (${benchmarkReason})`);
    }
  }
}

function normalizeBundleMode(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function validateBundleRecord(errors, record, label, scene, renderer, owner) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return;
  const mode = normalizeBundleMode(record.webgpu_bundle_mode);
  const groups = record.webgpu_bundle_groups;
  if (!mode && groups === undefined) return;

  if (mode && !['off', 'static'].includes(mode)) {
    errors.push(`${label}: ${owner}.webgpu_bundle_mode must be off or static when present`);
  }
  if (mode === 'static' && renderer !== 'webgpu') {
    errors.push(`${label}: ${owner}.webgpu_bundle_mode=static is only valid with renderer=webgpu`);
  }
  if (mode !== 'static' && isFiniteNumber(groups) && groups > 0) {
    errors.push(`${label}: ${owner}.webgpu_bundle_groups must be zero unless webgpu_bundle_mode=static`);
  }
  if (renderer === 'webgpu' &&
      mode === 'static' &&
      webGpuStaticBundleScenes.has(scene) &&
      (!Number.isInteger(groups) || groups <= 0)) {
    errors.push(`${label}: ${owner}.webgpu_bundle_mode=static requires a positive webgpu_bundle_groups count for ${scene}`);
  }
}

function validateWebGpuBundleMetadata(errors, data, benchmark, label) {
  validateBundleRecord(errors, data, label, data.scene, data.renderer, 'sidecar');
  if (benchmark && typeof benchmark === 'object' && !Array.isArray(benchmark)) {
    validateBundleRecord(
      errors,
      benchmark,
      label,
      benchmark.scene_name || data.scene,
      benchmark.renderer_type || data.renderer,
      'benchmark_result',
    );

    const sidecarMode = normalizeBundleMode(data.webgpu_bundle_mode);
    const benchmarkMode = normalizeBundleMode(benchmark.webgpu_bundle_mode);
    if (sidecarMode && benchmarkMode && sidecarMode !== benchmarkMode) {
      errors.push(`${label}: benchmark_result.webgpu_bundle_mode is ${benchmarkMode}, expected sidecar mode ${sidecarMode}`);
    }
  }
}

function validateWebGpuFastPathCoverageMetadata(errors, data, benchmark, label) {
  for (const field of webGpuFastPathCoverageFields) {
    if (!Object.prototype.hasOwnProperty.call(data, field)) continue;

    const value = data[field];
    if (value !== null && (!Number.isFinite(value) || value < 0)) {
      errors.push(`${label}: ${field} must be null or a non-negative finite number when present`);
      continue;
    }

    if (!benchmark || typeof benchmark !== 'object' || Array.isArray(benchmark)) continue;
    const benchmarkValue = benchmark[field];
    if (Number.isFinite(benchmarkValue) && !numericEquals(value, benchmarkValue)) {
      errors.push(`${label}: ${field} is ${formatValue(value)}, expected benchmark_result.${field} ${formatValue(benchmarkValue)}`);
    } else if (value !== null && benchmarkValue !== undefined && !Number.isFinite(benchmarkValue)) {
      errors.push(`${label}: benchmark_result.${field} must be finite when sidecar ${field} is recorded`);
    }
  }
}

function validateSidecar(data, file, args) {
  const errors = [];
  const label = path.basename(file);
  const benchmark = data.benchmark_result;
  const expectedFlagMetadata = parseExpectedFlagMetadata(args.expectedFlagMetadata);

  if (typeof data.generated_at !== 'string' || !data.generated_at) {
    errors.push(`${label}: generated_at must be a non-empty string`);
  }
  if (typeof data.platform !== 'string' || !data.platform) {
    errors.push(`${label}: platform must be a non-empty string`);
  }
  if (typeof data.browser !== 'string' || !data.browser) {
    errors.push(`${label}: browser must be a non-empty string`);
  } else if (args.expectedBrowser && !sameBrowserPath(data.browser, args.expectedBrowser)) {
    errors.push(`${label}: browser is ${data.browser}, expected ${args.expectedBrowser}`);
  }
  if (typeof data.scene !== 'string' || !data.scene) {
    errors.push(`${label}: scene must be a non-empty string`);
  }
  if (!['webgl2', 'webgpu'].includes(data.renderer)) {
    errors.push(`${label}: renderer must be webgl2 or webgpu`);
  }
  if (!isFiniteNumber(data.duration_seconds) || data.duration_seconds <= 0) {
    errors.push(`${label}: duration_seconds must be a positive finite number`);
  }
  if (!isFiniteNumber(data.warmup_seconds) || data.warmup_seconds < 0) {
    errors.push(`${label}: warmup_seconds must be a non-negative finite number`);
  }
  if (!isFiniteNumber(data.start_delay_ms) || data.start_delay_ms < 0) {
    errors.push(`${label}: start_delay_ms must be a non-negative finite number`);
  }
  if (typeof data.categories !== 'string' || !data.categories) {
    errors.push(`${label}: categories must be a non-empty string`);
  }
  validateOptionalStringArray(errors, data, 'browser_flags', label);
  validateOptionalStringArray(errors, data, 'browser_extra_flags', label);
  validateRequiredBrowserFlags(errors, data, label, args.requiredBrowserFlag);
  if (!benchmark || typeof benchmark !== 'object' || Array.isArray(benchmark)) {
    errors.push(`${label}: benchmark_result must be an object`);
  }
  validateNoSoftwareRenderer(errors, data, benchmark, label, args.rejectSoftwareRendering);
  validateWebGpuBundleMetadata(errors, data, benchmark, label);
  validateWebGpuFastPathCoverageMetadata(errors, data, benchmark, label);

  if (args.expectedScene && data.scene !== args.expectedScene) {
    errors.push(`${label}: scene is ${data.scene}, expected ${args.expectedScene}`);
  }
  if (args.expectedRenderer && data.renderer !== args.expectedRenderer) {
    errors.push(`${label}: renderer is ${data.renderer}, expected ${args.expectedRenderer}`);
  }
  if (args.expectedDuration !== null && !numericEquals(data.duration_seconds, args.expectedDuration)) {
    errors.push(`${label}: duration_seconds is ${data.duration_seconds}, expected ${args.expectedDuration}`);
  }
  if (args.expectedWarmup !== null && !numericEquals(data.warmup_seconds, args.expectedWarmup)) {
    errors.push(`${label}: warmup_seconds is ${data.warmup_seconds}, expected ${args.expectedWarmup}`);
  }
  if (args.expectedStartDelayMs !== null && !numericEquals(data.start_delay_ms, args.expectedStartDelayMs)) {
    errors.push(`${label}: start_delay_ms is ${data.start_delay_ms}, expected ${args.expectedStartDelayMs}`);
  }
  for (const { key, expected } of expectedFlagMetadata) {
    if (!metadataValueMatches(data[key], expected)) {
      errors.push(`${label}: ${key} is ${formatValue(data[key])}, expected ${formatValue(expected)}`);
    }
  }

  if (benchmark && typeof benchmark === 'object' && !Array.isArray(benchmark)) {
    if (benchmark.scene_name !== data.scene) {
      errors.push(`${label}: benchmark_result.scene_name is ${benchmark.scene_name}, expected sidecar scene ${data.scene}`);
    }
    if (benchmark.renderer_type !== data.renderer) {
      errors.push(`${label}: benchmark_result.renderer_type is ${benchmark.renderer_type}, expected sidecar renderer ${data.renderer}`);
    }
    if (!numericEquals(benchmark.measured_seconds, data.duration_seconds)) {
      errors.push(`${label}: benchmark_result.measured_seconds is ${benchmark.measured_seconds}, expected ${data.duration_seconds}`);
    }
    if (!numericEquals(benchmark.warmup_seconds, data.warmup_seconds)) {
      errors.push(`${label}: benchmark_result.warmup_seconds is ${benchmark.warmup_seconds}, expected ${data.warmup_seconds}`);
    }
    if ('complexity' in data && !numericEquals(benchmark.complexity, data.complexity)) {
      errors.push(`${label}: benchmark_result.complexity is ${formatValue(benchmark.complexity)}, expected ${data.complexity}`);
    }
    if (!isFiniteNumber(benchmark.avg_fps) || benchmark.avg_fps <= 0) {
      errors.push(`${label}: benchmark_result.avg_fps must be positive`);
    }
    if (!isFiniteNumber(benchmark.startup_ms_to_first_frame) || benchmark.startup_ms_to_first_frame < 0) {
      errors.push(`${label}: benchmark_result.startup_ms_to_first_frame must be non-negative`);
    }
  }

  return errors;
}

const args = parseArgs(process.argv);
const allErrors = [];
for (const file of args.files) {
  const resolved = path.resolve(file);
  let data = null;
  try {
    data = JSON.parse(fs.readFileSync(resolved, 'utf8').replace(/^\uFEFF/, ''));
  } catch (error) {
    allErrors.push(`${path.basename(file)}: invalid JSON (${error.message})`);
    continue;
  }
  allErrors.push(...validateSidecar(data, resolved, args));
}

if (allErrors.length) {
  console.error('FAIL: trace result sidecar validation failed');
  for (const error of allErrors) {
    console.error(`  ${error}`);
  }
  process.exit(1);
}

console.log(`OK: ${args.files.length} trace result sidecar file(s) validated.`);

#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const args = {
    file: '',
    maxRssDeltaMb: null,
    maxRendererResourceDelta: null,
    minMeasuredSeconds: null,
    minWarmupSeconds: null,
    expectedRenderer: '',
    expectedScene: '',
    expectedVariant: '',
    requireCheckout: false,
    requireBuildArgs: false,
    expectedBuildArgsHash: '',
    expectedChromiumRevision: '',
    expectedBrowser: '',
    requireForkRevision: false,
    expectedForkRevision: '',
    rejectSoftwareRendering: false,
    requireGpuMetadata: false,
    requirePackageSize: false,
    pinRefreshManifest: '',
    expectedFlagMetadata: [],
    requiredBrowserFlag: [],
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--maxRssDeltaMb') {
      args.maxRssDeltaMb = Number(argv[++i]);
    } else if (token === '--maxRendererResourceDelta') {
      args.maxRendererResourceDelta = Number(argv[++i]);
    } else if (token === '--minMeasuredSeconds') {
      args.minMeasuredSeconds = Number(argv[++i]);
    } else if (token === '--minWarmupSeconds') {
      args.minWarmupSeconds = Number(argv[++i]);
    } else if (token === '--expectedRenderer') {
      args.expectedRenderer = argv[++i];
    } else if (token === '--expectedScene') {
      args.expectedScene = argv[++i];
    } else if (token === '--expectedVariant') {
      args.expectedVariant = argv[++i];
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
    } else if (token === '--rejectSoftwareRendering') {
      args.rejectSoftwareRendering = true;
    } else if (token === '--requireGpuMetadata') {
      args.requireGpuMetadata = true;
    } else if (token === '--requirePackageSize') {
      args.requirePackageSize = true;
    } else if (token === '--pinRefreshManifest') {
      args.pinRefreshManifest = argv[++i];
    } else if (token === '--expectedFlagMetadata') {
      args.expectedFlagMetadata.push(argv[++i]);
    } else if (token === '--requiredBrowserFlag') {
      args.requiredBrowserFlag.push(argv[++i]);
    } else if (!args.file) {
      args.file = token;
    } else {
      throw new Error(`Unexpected argument: ${token}`);
    }
  }

  if (!args.file) {
    throw new Error('Usage: node scripts/validate_stability_result.mjs <result.json> [--maxRssDeltaMb N] [--maxRendererResourceDelta N] [--expectedBrowser PATH] [--expectedBuildArgsHash SHA256]');
  }
  for (const [name, value] of [
    ['--maxRssDeltaMb', args.maxRssDeltaMb],
    ['--maxRendererResourceDelta', args.maxRendererResourceDelta],
    ['--minMeasuredSeconds', args.minMeasuredSeconds],
    ['--minWarmupSeconds', args.minWarmupSeconds],
  ]) {
    if (value !== null && (!Number.isFinite(value) || value < 0)) {
      throw new Error(`${name} must be a non-negative number`);
    }
  }
  return args;
}

function readJson(pathValue) {
  return JSON.parse(fs.readFileSync(pathValue, 'utf8').replace(/^\uFEFF/, ''));
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

function finiteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function variantOf(data) {
  return data.benchmark_variant || 'unknown';
}

function hasGpuMetadata(data) {
  return [data.gpu_name, data.driver_version, data.angle_backend]
    .some((value) => typeof value === 'string' && value.trim().length > 0);
}

function softwareRendererReason(data) {
  const haystack = [data.gpu_name, data.driver_version, data.angle_backend]
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

function softwareRenderingDiagnosticOptIn(data) {
  return data.allow_software_rendering === true || data.allowSoftwareRendering === true;
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

function validateRequiredBrowserFlags(errors, data, requiredFlags) {
  if (!requiredFlags.length) {
    return;
  }
  if (!Array.isArray(data.browser_flags)) {
    errors.push('browser_flags must be an array when --requiredBrowserFlag is set');
    return;
  }
  for (const flag of requiredFlags) {
    if (!data.browser_flags.includes(flag)) {
      errors.push(`browser_flags must include ${flag}`);
    }
  }
}

function validatePinRefresh(data, manifestPath) {
  const errors = [];
  let pinRefresh;
  try {
    pinRefresh = readJson(manifestPath);
  } catch (error) {
    return [`pin refresh manifest is missing or invalid: ${manifestPath}`];
  }

  if (pinRefresh.target_revision !== data.chromium_revision) {
    errors.push(`pin refresh target_revision is ${pinRefresh.target_revision || 'missing'}, expected result chromium_revision ${data.chromium_revision || 'missing'}`);
  }
  if (pinRefresh.selected_from_upstream_head !== true) {
    errors.push(`pin refresh selected_from_upstream_head is ${formatValue(pinRefresh.selected_from_upstream_head)}, expected true`);
  }

  const generatedAt = Date.parse(data.generated_at);
  const selectedAt = Date.parse(pinRefresh.selected_at);
  if (!Number.isFinite(generatedAt) || !Number.isFinite(selectedAt)) {
    errors.push('generated_at and pin refresh selected_at must be valid timestamps');
  } else if (generatedAt < selectedAt) {
    errors.push(`generated_at ${data.generated_at} predates pin refresh selected_at ${pinRefresh.selected_at}`);
  }

  return errors;
}

function validate(data, args) {
  const errors = [];
  const expectedFlagMetadata = parseExpectedFlagMetadata(args.expectedFlagMetadata);

  if (!finiteNumber(data.avg_fps) || data.avg_fps <= 0) {
    errors.push('avg_fps must be a positive finite number');
  }
  if (!Array.isArray(data.frame_times_ms) || data.frame_times_ms.length < 1) {
    errors.push('frame_times_ms must contain measured frame samples');
  } else {
    data.frame_times_ms.forEach((value, index) => {
      if (!finiteNumber(value) || value < 0) {
        errors.push(`frame_times_ms[${index}] must be a non-negative finite number`);
      }
    });
  }

  if (args.expectedRenderer && data.renderer_type !== args.expectedRenderer) {
    errors.push(`renderer_type is ${data.renderer_type}, expected ${args.expectedRenderer}`);
  }
  if (args.expectedScene && data.scene_name !== args.expectedScene) {
    errors.push(`scene_name is ${data.scene_name}, expected ${args.expectedScene}`);
  }
  if (args.expectedVariant && variantOf(data) !== args.expectedVariant) {
    errors.push(`benchmark_variant is ${variantOf(data)}, expected ${args.expectedVariant}`);
  }
  if (args.minMeasuredSeconds !== null) {
    if (!finiteNumber(data.measured_seconds)) {
      errors.push('measured_seconds is required when --minMeasuredSeconds is set');
    } else if (data.measured_seconds < args.minMeasuredSeconds) {
      errors.push(`measured_seconds ${data.measured_seconds} is below minimum ${args.minMeasuredSeconds}`);
    }
  }
  if (args.minWarmupSeconds !== null) {
    if (!finiteNumber(data.warmup_seconds)) {
      errors.push('warmup_seconds is required when --minWarmupSeconds is set');
    } else if (data.warmup_seconds < args.minWarmupSeconds) {
      errors.push(`warmup_seconds ${data.warmup_seconds} is below minimum ${args.minWarmupSeconds}`);
    }
  }
  if (args.requireCheckout && data.browser_is_from_checkout !== true) {
    errors.push('browser_is_from_checkout must be true');
  }
  if (args.requireCheckout && !data.chromium_revision) {
    errors.push('chromium_revision is required for checkout-built stability evidence');
  }
  if (args.expectedChromiumRevision && data.chromium_revision !== args.expectedChromiumRevision) {
    errors.push(`chromium_revision is ${data.chromium_revision || 'missing'}, expected ${args.expectedChromiumRevision}`);
  }
  if (args.expectedBrowser) {
    if (typeof data.browser_executable !== 'string' || data.browser_executable.trim().length === 0) {
      errors.push('browser_executable is required when --expectedBrowser is set');
    } else if (!sameBrowserPath(data.browser_executable, args.expectedBrowser)) {
      errors.push(`browser_executable is ${data.browser_executable}, expected ${args.expectedBrowser}`);
    }
  }
  if (args.requireBuildArgs && !data.build_args_hash) {
    errors.push('build_args_hash is required');
  }
  const actualBuildArgsHash = typeof data.build_args_hash === 'string'
    ? data.build_args_hash.toLowerCase()
    : data.build_args_hash;
  if (args.expectedBuildArgsHash && actualBuildArgsHash !== args.expectedBuildArgsHash) {
    errors.push(`build_args_hash is ${data.build_args_hash || 'missing'}, expected ${args.expectedBuildArgsHash}`);
  }
  if (args.requireForkRevision && !data.fork_revision) {
    errors.push('fork_revision is required');
  }
  if (args.expectedForkRevision && data.fork_revision !== args.expectedForkRevision) {
    errors.push(`fork_revision is ${data.fork_revision || 'missing'}, expected ${args.expectedForkRevision}`);
  }
  if (args.requireGpuMetadata && !hasGpuMetadata(data)) {
    errors.push('GPU metadata is required for stability evidence');
  }
  if (args.requirePackageSize && (
    !finiteNumber(data.package_size_mb) ||
    data.package_size_mb <= 0
  )) {
    errors.push('package_size_mb must be a positive number when package size evidence is required');
  }
  if (args.pinRefreshManifest) {
    errors.push(...validatePinRefresh(data, args.pinRefreshManifest));
  }
  if (args.rejectSoftwareRendering) {
    if (softwareRenderingDiagnosticOptIn(data)) {
      errors.push('diagnostic software-rendering opt-in is not allowed in stability evidence');
    }
    const reason = softwareRendererReason(data);
    if (reason) {
      errors.push(`known software-rendered GPU path is not allowed (${reason})`);
    }
  }
  for (const { key, expected } of expectedFlagMetadata) {
    if (!metadataValueMatches(data[key], expected)) {
      errors.push(`${key} is ${formatValue(data[key])}, expected ${formatValue(expected)}`);
    }
  }
  validateRequiredBrowserFlags(errors, data, args.requiredBrowserFlag);

  if (args.maxRssDeltaMb !== null) {
    if (!finiteNumber(data.process_rss_delta_mb)) {
      errors.push('process_rss_delta_mb is required when --maxRssDeltaMb is set');
    } else if (data.process_rss_delta_mb > args.maxRssDeltaMb) {
      errors.push(`process_rss_delta_mb ${data.process_rss_delta_mb} exceeded threshold ${args.maxRssDeltaMb}`);
    }
  }

  if (args.maxRendererResourceDelta !== null) {
    for (const key of [
      'renderer_memory_geometries_delta',
      'renderer_memory_textures_delta',
      'renderer_programs_delta',
    ]) {
      if (!finiteNumber(data[key])) {
        errors.push(`${key} is required when --maxRendererResourceDelta is set`);
      } else if (data[key] > args.maxRendererResourceDelta) {
        errors.push(`${key} ${data[key]} exceeded threshold ${args.maxRendererResourceDelta}`);
      }
    }
  }

  return errors;
}

let args;
try {
  args = parseArgs(process.argv);
} catch (error) {
  console.error(error.message);
  process.exit(2);
}

let data;
try {
  data = readJson(args.file);
} catch (error) {
  console.error(`FAIL: ${args.file}`);
  console.error(`  ${error.message}`);
  process.exit(1);
}

const errors = validate(data, args);
if (errors.length) {
  console.error(`FAIL: ${args.file}`);
  for (const error of errors) {
    console.error(`  ${error}`);
  }
  process.exit(1);
}

console.log(`OK: ${args.file} passes stability thresholds.`);

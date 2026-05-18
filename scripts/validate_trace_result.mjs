#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

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

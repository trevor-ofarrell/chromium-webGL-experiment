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
    expectedChromiumRevision: '',
    expectedBrowser: '',
    requireForkRevision: false,
    expectedForkRevision: '',
    forbidSmoke: false,
    rejectSoftwareRendering: false,
    requireGpuMetadata: false,
    requirePackageSize: false,
    expectedMeasuredSeconds: null,
    expectedWarmupSeconds: null,
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
    } else if (token === '--requireGpuMetadata') {
      args.requireGpuMetadata = true;
    } else if (token === '--requirePackageSize') {
      args.requirePackageSize = true;
    } else if (token === '--expectedMeasuredSeconds') {
      args.expectedMeasuredSeconds = Number(argv[++i]);
    } else if (token === '--expectedWarmupSeconds') {
      args.expectedWarmupSeconds = Number(argv[++i]);
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
  ]) {
    if (value !== null && (!Number.isFinite(value) || value < 0)) {
      throw new Error(`${name} must be a non-negative number`);
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
      const reason = softwareRendererReason(result);
      if (reason) {
        errors.push(`${result.scene_name}: known software-rendered GPU path is not allowed (${reason})`);
      }
    }
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
    if (args.expectedMeasuredSeconds !== null && !numericEquals(result.measured_seconds, args.expectedMeasuredSeconds)) {
      errors.push(`${result.scene_name}: measured_seconds is ${result.measured_seconds}, expected ${args.expectedMeasuredSeconds}`);
    }
    if (args.expectedWarmupSeconds !== null && !numericEquals(result.warmup_seconds, args.expectedWarmupSeconds)) {
      errors.push(`${result.scene_name}: warmup_seconds is ${result.warmup_seconds}, expected ${args.expectedWarmupSeconds}`);
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
const results = files.map((file) => JSON.parse(fs.readFileSync(file, 'utf8')));
const errors = validateSuite(results, args);

if (errors.length) {
  console.error('FAIL: benchmark suite validation failed');
  for (const error of errors) {
    console.error(`  ${error}`);
  }
  process.exit(1);
}

console.log(`OK: ${files.length} ${args.renderer} result files form a complete benchmark suite.`);

#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function parseArgs(argv) {
  const args = { baseline: [], fork: [], aggressive: [] };
  for (let i = 2; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith('--')) throw new Error(`Unexpected argument: ${key}`);
    const name = key.slice(2);
    if (['baseline', 'fork', 'aggressive'].includes(name)) {
      args[name].push(argv[++i]);
    } else {
      args[name] = argv[++i];
    }
  }
  return args;
}

function metadata(file) {
  if (!file || !fs.existsSync(file)) return null;
  const data = fs.readFileSync(file);
  return {
    path: file,
    sha256: crypto.createHash('sha256').update(data).digest('hex'),
    size: data.length,
  };
}

function directoryMetadata(dir) {
  if (!dir || !fs.existsSync(dir)) return null;
  let count = 0;
  let size = 0;
  const stack = [dir];
  while (stack.length) {
    const current = stack.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) stack.push(full);
      else if (entry.isFile()) {
        count += 1;
        size += fs.statSync(full).size;
      }
    }
  }
  return { path: dir, file_count: count, size };
}

const args = parseArgs(process.argv);
const manifest = {
  generated_at: new Date().toISOString(),
  host_platform: 'wsl-linux',
  host_os_type: os.type(),
  host_os_release: os.release(),
  host_arch: os.arch(),
  renderer: args.renderer || 'webgl2',
  options: {
    duration: Number(args.duration || 120),
    warmup: Number(args.warmup || 20),
    complexity: Number(args.complexity || 2),
    include_webgpu: false,
    include_aggressive_gpu: args.includeAggressiveGpu === 'true',
    wsl_first_target: 'build-plus-hardware-webgl2',
  },
  browsers: {
    baseline: args.baselineBrowser || null,
    fork: args.forkBrowser || null,
  },
  build_args: {
    baseline: metadata(args.baselineBuildArgs),
    fork: metadata(args.forkBuildArgs),
  },
  packages: {
    baseline: directoryMetadata(args.baselinePackageDir),
    fork: directoryMetadata(args.forkPackageDir),
  },
  result_files: {
    baseline_webgl2: args.baseline.map(metadata).filter(Boolean),
    fork_default_webgl2: args.fork.map(metadata).filter(Boolean),
    aggressive_webgl2: args.aggressive.map(metadata).filter(Boolean),
  },
  reports: {
    official_webgl2_comparison: args.officialWebgl2Comparison || null,
  },
  platform_compatibility_policy: 'do-not-compare-windows-and-wsl-evidence',
};

fs.mkdirSync(path.dirname(args.output), { recursive: true });
fs.writeFileSync(args.output, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Wrote ${args.output}`);

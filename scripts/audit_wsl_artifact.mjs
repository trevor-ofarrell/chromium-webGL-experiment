#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith('--')) throw new Error(`Unexpected argument: ${key}`);
    args[key.slice(2)] = argv[++i];
  }
  return args;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function exists(file) {
  return fs.existsSync(file);
}

function executable(file) {
  try {
    fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

let displayPath = '';

function display(file) {
  return displayPath || file;
}

function readJson(file) {
  if (!exists(file)) fail(`missing ${display(file)}`);
  try {
    const text = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
    return JSON.parse(text);
  } catch (error) {
    fail(`invalid JSON in ${display(file)}: ${error.message}`);
  }
}

function containsWindowsEvidence(value) {
  if (typeof value === 'string') {
    return /[A-Za-z]:\\|\\\\|content_shell\.exe|run_viewer\.ps1|\\build\\gn_args\\|\\src\\out\\|D3D11|D3D12|WARP/i.test(value);
  }
  if (Array.isArray(value)) return value.some((entry) => containsWindowsEvidence(entry));
  if (value && typeof value === 'object') {
    return Object.values(value).some((entry) => containsWindowsEvidence(entry));
  }
  return false;
}

function requireNoWindowsEvidence(value) {
  if (containsWindowsEvidence(value)) {
    fail('contains Windows-specific paths or GPU backend evidence');
  }
}

function requireBasename(file, expected) {
  if (path.basename(file || '') !== expected) {
    fail(`expected ${expected}, got ${file || 'missing'}`);
  }
}

function checkBuildProvenance(file) {
  const data = readJson(file);
  if (data.host_platform !== 'wsl-linux') fail('host_platform must be wsl-linux');
  if (data.host_filesystem_policy !== 'linux-filesystem') fail('host_filesystem_policy must be linux-filesystem');
  if (data.target_executable_name !== 'content_shell') fail('target_executable_name must be content_shell');
  requireBasename(data.target_artifact, 'content_shell');
  if (!String(data.source_args || '').includes('/build/gn_args/linux/')) {
    fail('source_args must use build/gn_args/linux');
  }
  if (Array.isArray(data.common_build_patch_series) && data.common_build_patch_series.length !== 0) {
    fail('common_build_patch_series must be empty on WSL');
  }
  requireNoWindowsEvidence(data);
}

function checkOfficialManifest(file) {
  const data = readJson(file);
  if (data.host_platform !== 'wsl-linux') fail('host_platform must be wsl-linux');
  if (data.platform_compatibility_policy !== 'do-not-compare-windows-and-wsl-evidence') {
    fail('platform compatibility policy must prevent Windows/WSL evidence mixing');
  }
  if (data.renderer !== 'webgl2') fail('renderer must be webgl2 for the first WSL gate');
  if (data.options?.include_webgpu !== false) fail('include_webgpu must be false for the first WSL gate');
  requireBasename(data.browsers?.baseline, 'content_shell');
  requireBasename(data.browsers?.fork, 'content_shell');
  if ((data.result_files?.baseline_webgl2 || []).length !== 7) fail('baseline_webgl2 must contain exactly seven scene files');
  if ((data.result_files?.fork_default_webgl2 || []).length !== 7) fail('fork_default_webgl2 must contain exactly seven scene files');
  requireNoWindowsEvidence(data);
}

function checkOfficialReport(file) {
  if (!exists(file)) fail(`missing ${display(file)}`);
  const text = fs.readFileSync(file, 'utf8');
  if (/content_shell\.exe|run_viewer\.ps1|[A-Za-z]:\\|D3D11|D3D12|WARP/i.test(text)) {
    fail('report contains Windows-specific evidence');
  }
}

function checkPackageLauncher(file) {
  if (!executable(file)) fail(`missing executable ${display(file)}`);
  const text = fs.readFileSync(file, 'utf8');
  if (/content_shell\.exe|run_viewer\.ps1|powershell/i.test(text)) {
    fail('launcher contains Windows package commands');
  }
}

const args = parseArgs(process.argv);
const root = path.resolve(args.root || path.join(path.dirname(new URL(import.meta.url).pathname), '..'));
const file = path.resolve(root, args.path || '');
displayPath = args.path || file;

switch (args.type) {
  case 'exists':
    if (!exists(file)) fail(`missing ${display(file)}`);
    break;
  case 'executable':
    if (!executable(file)) fail(`missing executable ${display(file)}`);
    break;
  case 'linux-content-shell':
    if (!executable(file)) fail(`missing executable ${display(file)}`);
    requireBasename(file, 'content_shell');
    break;
  case 'package-launcher':
    checkPackageLauncher(file);
    break;
  case 'build-provenance':
    checkBuildProvenance(file);
    break;
  case 'official-manifest':
    checkOfficialManifest(file);
    break;
  case 'official-report':
    checkOfficialReport(file);
    break;
  default:
    fail(`unknown audit type: ${args.type || 'missing'}`);
}

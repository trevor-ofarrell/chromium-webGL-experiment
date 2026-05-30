#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith('--')) throw new Error(`Unexpected argument: ${key}`);
    args[key.slice(2)] = argv[++i];
  }
  return args;
}

function sha256File(file) {
  if (!file || !fs.existsSync(file)) return '';
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function commandText(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', shell: false });
  return result.status === 0 ? result.stdout.trim() : '';
}

function patchState(root, src, relativePath) {
  const patchPath = path.join(root, relativePath);
  const exists = fs.existsSync(patchPath);
  const applies = exists && spawnSync('git', ['-C', src, 'apply', '--check', patchPath], { stdio: 'ignore' }).status === 0;
  const reverse = exists && spawnSync('git', ['-C', src, 'apply', '--reverse', '--check', patchPath], { stdio: 'ignore' }).status === 0;
  return {
    path: relativePath,
    exists,
    sha256: sha256File(patchPath),
    applies_cleanly: applies,
    already_applied: reverse,
  };
}

const args = parseArgs(process.argv);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(args.root || path.join(__dirname, '..'));
const src = path.join(root, 'src');
const outAbs = path.resolve(src, args.outDir);
const targetArtifact = path.resolve(args.targetArtifact);
const argsDest = path.join(outAbs, 'args.gn');
const sourceArgs = path.resolve(root, args.sourceArgs);
const viewerPatchSeries = [
  'chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch',
  'chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch',
];

if (!fs.existsSync(targetArtifact)) {
  throw new Error(`Expected build output was not produced: ${targetArtifact}`);
}

const osRelease = fs.existsSync('/etc/os-release') ? fs.readFileSync('/etc/os-release', 'utf8') : '';
const provenance = {
  generated_at: new Date().toISOString(),
  build_started_at: args.startedAt || null,
  chromium_revision: commandText('git', ['rev-parse', 'HEAD'], src),
  out_dir: args.outDir,
  target: args.target,
  target_artifact: targetArtifact,
  target_artifact_sha256: sha256File(targetArtifact),
  args_gn: argsDest,
  args_gn_sha256: sha256File(argsDest),
  source_args: sourceArgs,
  source_args_sha256: sha256File(sourceArgs),
  build_jobs: Number(args.jobs || 0),
  allow_viewer_patch_applied: args.allowViewerPatchApplied === 'true',
  baseline_source_guard_enabled: args.baselineSourceGuardEnabled === 'true',
  viewer_patch_applies_cleanly: patchState(root, src, viewerPatchSeries[0]).applies_cleanly,
  viewer_patch_already_applied: patchState(root, src, viewerPatchSeries[0]).already_applied,
  viewer_patch_series: viewerPatchSeries.map((entry) => patchState(root, src, entry)),
  common_build_patch_series: [],
  host_platform: 'wsl-linux',
  host_os_type: os.type(),
  host_os_release: os.release(),
  host_arch: os.arch(),
  host_kernel: os.release(),
  host_distro: osRelease.split('\n').find((line) => line.startsWith('PRETTY_NAME='))?.split('=')[1]?.replace(/^"|"$/g, '') || null,
  host_filesystem_policy: root.startsWith('/mnt/') ? 'windows-mount-unsupported' : 'linux-filesystem',
  target_executable_name: path.basename(targetArtifact),
};

const provenancePath = path.join(outAbs, 'three_browser_build_provenance.json');
fs.writeFileSync(provenancePath, `${JSON.stringify(provenance, null, 2)}\n`);
console.log(`Wrote build provenance ${provenancePath}`);

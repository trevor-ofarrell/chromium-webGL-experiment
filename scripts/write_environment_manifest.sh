#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="benchmarks/reports/prebuild-environment.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./scripts/write_environment_manifest.sh [--output benchmarks/reports/prebuild-environment.json]"
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

node - "$ROOT" "$output" <<'NODE'
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = process.argv[2];
const output = path.resolve(root, process.argv[3]);
function exists(p) { return fs.existsSync(path.resolve(root, p)); }
function executable(p) {
  try { fs.accessSync(path.resolve(root, p), fs.constants.X_OK); return true; } catch { return false; }
}
function text(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8' });
  return result.status === 0 ? result.stdout.trim() : '';
}

const osRelease = fs.existsSync('/etc/os-release') ? fs.readFileSync('/etc/os-release', 'utf8') : '';
const manifest = {
  generated_at: new Date().toISOString(),
  host_platform: 'wsl-linux',
  node_version: process.version,
  os_type: os.type(),
  os_release: os.release(),
  os_arch: os.arch(),
  distro: osRelease,
  repo_path: root,
  repo_filesystem_policy: root.startsWith('/mnt/') ? 'windows-mount-unsupported' : 'linux-filesystem',
  chromium_revision_expected: exists('.chromium_revision') ? fs.readFileSync(path.resolve(root, '.chromium_revision'), 'utf8').trim() : null,
  chromium_revision_actual: exists('src/.git') ? text('git', ['-C', path.resolve(root, 'src'), 'rev-parse', 'HEAD']) : null,
  checks: {
    depot_tools: exists('tools/depot_tools/gclient.py'),
    viewer_dist: exists('viewer/dist/index.html'),
    baseline_content_shell: executable('src/out/ReleaseBaseline/content_shell'),
    fork_content_shell: executable('src/out/ReleaseViewerDefault/content_shell'),
    wslg_display: Boolean(process.env.DISPLAY || process.env.WAYLAND_DISPLAY),
    wsl_gpu_device: fs.existsSync('/dev/dxg'),
  },
};
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Wrote ${output}`);
NODE

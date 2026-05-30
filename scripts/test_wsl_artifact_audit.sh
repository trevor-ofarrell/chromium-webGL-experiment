#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$ROOT/benchmarks/tmp/wsl-artifact-audit-test"

rm -rf "$tmp"
mkdir -p "$tmp"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

write_json() {
  local path_value="$1"
  local body="$2"
  printf '%s\n' "$body" > "$path_value"
}

expect_fail() {
  local description="$1"
  shift
  if "$@" >/tmp/three-browser-wsl-audit-test.out 2>&1; then
    echo "expected failure: $description" >&2
    exit 1
  fi
}

expect_pass() {
  local description="$1"
  shift
  if ! "$@" >/tmp/three-browser-wsl-audit-test.out 2>&1; then
    cat /tmp/three-browser-wsl-audit-test.out >&2
    echo "expected pass: $description" >&2
    exit 1
  fi
}

windows_provenance="$tmp/windows-provenance.json"
wsl_provenance="$tmp/wsl-provenance.json"
windows_manifest="$tmp/windows-manifest.json"
wsl_manifest="$tmp/wsl-manifest.json"
report="$tmp/report.md"

write_json "$windows_provenance" '{
  "host_platform": "windows",
  "host_filesystem_policy": "windows-filesystem",
  "target_executable_name": "content_shell.exe",
  "target_artifact": "C:\\repo\\src\\out\\ReleaseBaseline\\content_shell.exe",
  "source_args": "C:\\repo\\build\\gn_args\\baseline_content_shell.gn",
  "common_build_patch_series": [{"path": "chromium_patches\\0000-draft-win-clang-build-workarounds.patch"}]
}'

write_json "$wsl_provenance" '{
  "host_platform": "wsl-linux",
  "host_filesystem_policy": "linux-filesystem",
  "target_executable_name": "content_shell",
  "target_artifact": "/home/test/code/three-browser/src/out/ReleaseBaseline/content_shell",
  "source_args": "/home/test/code/three-browser/build/gn_args/linux/baseline_content_shell.gn",
  "common_build_patch_series": []
}'

write_json "$windows_manifest" '{
  "renderer": "webgl2",
  "options": {"include_webgpu": true},
  "browsers": {
    "baseline": "C:\\repo\\src\\out\\ReleaseBaseline\\content_shell.exe",
    "fork": "C:\\repo\\src\\out\\ReleaseViewerDefault\\content_shell.exe"
  },
  "result_files": {"baseline_webgl2": [], "fork_default_webgl2": []}
}'

write_json "$wsl_manifest" '{
  "host_platform": "wsl-linux",
  "platform_compatibility_policy": "do-not-compare-windows-and-wsl-evidence",
  "renderer": "webgl2",
  "options": {"include_webgpu": false},
  "browsers": {
    "baseline": "/home/test/code/three-browser/src/out/ReleaseBaseline/content_shell",
    "fork": "/home/test/code/three-browser/src/out/ReleaseViewerDefault/content_shell"
  },
  "result_files": {
    "baseline_webgl2": [1, 2, 3, 4, 5, 6, 7],
    "fork_default_webgl2": [1, 2, 3, 4, 5, 6, 7]
  }
}'

printf 'WSL WebGL2 comparison\n' > "$report"

expect_fail "Windows build provenance" node "$ROOT/scripts/audit_wsl_artifact.mjs" --type build-provenance --path "$windows_provenance" --root "$ROOT"
expect_pass "WSL build provenance" node "$ROOT/scripts/audit_wsl_artifact.mjs" --type build-provenance --path "$wsl_provenance" --root "$ROOT"
expect_fail "Windows official manifest" node "$ROOT/scripts/audit_wsl_artifact.mjs" --type official-manifest --path "$windows_manifest" --root "$ROOT"
expect_pass "WSL official manifest" node "$ROOT/scripts/audit_wsl_artifact.mjs" --type official-manifest --path "$wsl_manifest" --root "$ROOT"
expect_pass "WSL report" node "$ROOT/scripts/audit_wsl_artifact.mjs" --type official-report --path "$report" --root "$ROOT"

printf 'WSL artifact audit test passed.\n'

#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$ROOT/benchmarks/tmp/wsl-stage-test"
package="$ROOT/benchmarks/packages/wsl-stage-test"

cleanup() {
  rm -rf -- "$tmp" "$package"
}
trap cleanup EXIT

cleanup
mkdir -p "$tmp/out/locales" "$tmp/viewer"
printf 'fake executable\n' > "$tmp/out/content_shell"
chmod +x "$tmp/out/content_shell"
printf 'fake shared object\n' > "$tmp/out/libfake.so"
printf 'fake pak\n' > "$tmp/out/resources.pak"
printf '<!doctype html>\n' > "$tmp/viewer/index.html"
printf 'stale\n' > "$tmp/out/locales/en-US.pak"

"$ROOT/scripts/stage_viewer_package.sh" \
  --chromium-out-dir "$tmp/out" \
  --viewer-dist "$tmp/viewer" \
  --package-dir "$package" \
  --clean >/tmp/three-browser-stage-test.out

[[ -x "$package/content_shell" ]] || { echo "staged content_shell is missing or not executable" >&2; exit 1; }
[[ -f "$package/libfake.so" ]] || { echo "shared object was not staged" >&2; exit 1; }
[[ -f "$package/resources.pak" ]] || { echo "pak file was not staged" >&2; exit 1; }
[[ -f "$package/viewer/index.html" ]] || { echo "viewer bundle was not staged" >&2; exit 1; }
[[ -x "$package/run_viewer.sh" ]] || { echo "run_viewer.sh was not generated as executable" >&2; exit 1; }

if grep -q 'content_shell.exe\|run_viewer.ps1' "$package/run_viewer.sh"; then
  echo "Linux package launcher contains Windows artifact names" >&2
  exit 1
fi

echo "Linux package staging test passed."

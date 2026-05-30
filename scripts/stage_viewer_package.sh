#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/wsl_common.sh
. "$ROOT/scripts/lib/wsl_common.sh"

chromium_out_dir="./src/out/ReleaseViewerDefault"
viewer_dist="./viewer/dist"
package_dir="./benchmarks/packages/viewer-default"
clean=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chromium-out-dir) chromium_out_dir="$2"; shift 2 ;;
    --viewer-dist) viewer_dist="$2"; shift 2 ;;
    --package-dir) package_dir="$2"; shift 2 ;;
    --clean) clean=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./scripts/stage_viewer_package.sh --chromium-out-dir ./src/out/ReleaseViewerDefault --package-dir ./benchmarks/packages/viewer-default [--clean]
USAGE
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

chromium_out_dir="$(cd "$(dirname "$chromium_out_dir")" && pwd)/$(basename "$chromium_out_dir")"
viewer_dist="$(cd "$(dirname "$viewer_dist")" && pwd)/$(basename "$viewer_dist")"
mkdir -p "$(dirname "$package_dir")"
package_parent="$(cd "$(dirname "$package_dir")" && pwd)"
package_dir="$package_parent/$(basename "$package_dir")"

[[ -x "$chromium_out_dir/content_shell" ]] || die "content_shell not found or not executable under $chromium_out_dir"
[[ -f "$viewer_dist/index.html" ]] || die "viewer dist not found under $viewer_dist"

mkdir -p "$ROOT/benchmarks/packages"
packages_root="$(cd "$ROOT/benchmarks/packages" && pwd)"
if [[ "$clean" -eq 1 && -e "$package_dir" ]]; then
  case "$package_dir" in
    "$packages_root"/*) rm -rf -- "$package_dir" ;;
    *) die "refusing to clean package dir outside benchmarks/packages: $package_dir" ;;
  esac
fi

mkdir -p "$package_dir"

copy_pattern() {
  local pattern="$1"
  shopt -s nullglob
  local matches=("$chromium_out_dir"/$pattern)
  shopt -u nullglob
  for file in "${matches[@]}"; do
    [[ -f "$file" ]] && cp -f "$file" "$package_dir/"
  done
}

copy_pattern "content_shell"
copy_pattern "*.so"
copy_pattern "*.pak"
copy_pattern "*.bin"
copy_pattern "*.dat"
copy_pattern "*.json"

for dir_name in locales swiftshader angledata MEIPreload; do
  if [[ -d "$chromium_out_dir/$dir_name" ]]; then
    rm -rf -- "$package_dir/$dir_name"
    cp -a "$chromium_out_dir/$dir_name" "$package_dir/$dir_name"
  fi
done

rm -rf -- "$package_dir/viewer"
cp -a "$viewer_dist" "$package_dir/viewer"

cat > "$package_dir/run_viewer.sh" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
benchmark=0
scene="many-draw-calls"
renderer="webgl2"
duration=30
warmup=5
complexity=1
precompile=0
prerender_frames=0
disable_gpu_timing=0
start_delay_ms=0
unsafe_full_size_window=0
extra_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --benchmark) benchmark=1; shift ;;
    --scene) scene="$2"; shift 2 ;;
    --renderer) renderer="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --warmup) warmup="$2"; shift 2 ;;
    --complexity) complexity="$2"; shift 2 ;;
    --precompile) precompile=1; shift ;;
    --prerender-frames) prerender_frames="$2"; shift 2 ;;
    --disable-gpu-timing) disable_gpu_timing=1; shift ;;
    --start-delay-ms) start_delay_ms="$2"; shift 2 ;;
    --unsafe-full-size-window) unsafe_full_size_window=1; shift ;;
    --) shift; extra_args+=("$@"); break ;;
    *) extra_args+=("$1"); shift ;;
  esac
done

viewer="$ROOT/viewer/index.html"
exe="$ROOT/content_shell"
profile_dir="$ROOT/profile"
mkdir -p "$profile_dir"

viewer_url="$(python3 - "$viewer" <<'PY'
import pathlib, sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
)"

if [[ "$benchmark" -eq 1 ]]; then
  query="$(python3 - "$scene" "$renderer" "$duration" "$warmup" "$complexity" "$precompile" "$prerender_frames" "$disable_gpu_timing" "$start_delay_ms" <<'PY'
import sys, urllib.parse
keys = ["scene", "renderer", "duration", "warmup", "complexity", "precompile", "prerenderFrames", "gpuTimingDisabled", "startDelayMs"]
values = dict(zip(keys, sys.argv[1:]))
query = {
  "benchmark": "1",
  "scene": values["scene"],
  "renderer": values["renderer"],
  "complexity": values["complexity"],
  "duration": values["duration"],
  "warmup": values["warmup"],
  "precompile": values["precompile"],
  "prerenderFrames": values["prerenderFrames"],
  "gpuTiming": "0" if values["gpuTimingDisabled"] == "1" else "1",
  "startDelayMs": values["startDelayMs"],
}
print(urllib.parse.urlencode(query))
PY
)"
  viewer_url="${viewer_url}?${query}"
fi

viewer_args=(
  "--user-data-dir=$profile_dir"
  "--no-first-run"
  "--disable-default-apps"
  "--disable-background-networking"
  "--disable-component-update"
  "--disable-sync"
  "--disable-extensions"
  "--disable-popup-blocking"
  "--disable-software-rasterizer"
  "--viewer-app-url=$viewer_url"
  "--viewer-block-external-navigation"
  "--viewer-trusted-content"
  "--enable-unsafe-webgpu"
  "--enable-webgpu-developer-features"
  "--autoplay-policy=no-user-gesture-required"
  "--disable-renderer-backgrounding"
  "--disable-background-timer-throttling"
  "--disable-features=Translate,OptimizationHints,AutofillServerCommunication"
)

if [[ "$unsafe_full_size_window" -eq 0 ]]; then
  viewer_args+=(
    "--force-high-performance-gpu"
    "--window-size=640,480"
    "--window-position=40,40"
    "--force-device-scale-factor=1"
  )
fi

exec "$exe" "${viewer_args[@]}" "${extra_args[@]}"
LAUNCHER
chmod +x "$package_dir/run_viewer.sh"

size_bytes="$(find "$package_dir" -type f -printf '%s\n' | awk '{sum += $1} END {print sum + 0}')"
awk -v bytes="$size_bytes" -v dir="$package_dir" 'BEGIN { printf "Staged viewer package: %s\npackage_size_mb=%.2f\n", dir, bytes / 1048576 }'

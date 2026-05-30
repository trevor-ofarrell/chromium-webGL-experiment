#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

browser=""
renderer="webgl2"
scene="instancing"
duration=3600
warmup=30
label="fork-viewer-default-long-stability"
output=""
build_args=""
package_dir=""
expected_browser=""
max_rss_delta_mb=128
max_renderer_resource_delta=0
viewer_mode=0
viewer_trusted_content=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --browser) browser="$2"; shift 2 ;;
    --renderer) renderer="$2"; shift 2 ;;
    --scene) scene="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --warmup) warmup="$2"; shift 2 ;;
    --label) label="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --build-args) build_args="$2"; shift 2 ;;
    --package-dir) package_dir="$2"; shift 2 ;;
    --expected-browser) expected_browser="$2"; shift 2 ;;
    --max-rss-delta-mb) max_rss_delta_mb="$2"; shift 2 ;;
    --max-renderer-resource-delta) max_renderer_resource_delta="$2"; shift 2 ;;
    --viewer-mode) viewer_mode=1; shift ;;
    --viewer-trusted-content) viewer_trusted_content=1; shift ;;
    -h|--help)
      echo "Usage: ./scripts/run_long_stability.sh --browser ./src/out/ReleaseViewerDefault/content_shell [--viewer-mode --viewer-trusted-content]"
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$browser" ]] || { echo "--browser is required" >&2; exit 1; }
[[ -x "$browser" ]] || { echo "browser is not executable: $browser" >&2; exit 1; }
[[ -n "$output" ]] || output="$ROOT/benchmarks/raw/$label-$scene-$renderer.json"

cmd=(node "$ROOT/scripts/run_benchmark.mjs"
  --browser "$browser"
  --variant "$label"
  --scene "$scene"
  --renderer "$renderer"
  --duration "$duration"
  --warmup "$warmup"
  --output "$output")
[[ -n "$build_args" ]] && cmd+=(--buildArgs "$build_args")
[[ -n "$package_dir" ]] && cmd+=(--packageDir "$package_dir")
[[ "$viewer_mode" -eq 1 ]] && cmd+=(--viewerMode)
[[ "$viewer_trusted_content" -eq 1 ]] && cmd+=(--viewerTrustedContent)

"${cmd[@]}"

validate=(node "$ROOT/scripts/validate_stability_result.mjs" "$output"
  --maxRssDeltaMb "$max_rss_delta_mb"
  --maxRendererResourceDelta "$max_renderer_resource_delta")
[[ -n "$expected_browser" ]] && validate+=(--expectedBrowser "$expected_browser")
"${validate[@]}"

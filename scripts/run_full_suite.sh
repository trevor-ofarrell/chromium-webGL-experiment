#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/wsl_common.sh
. "$ROOT/scripts/lib/wsl_common.sh"

browser=""
label="baseline-content-shell"
renderer="webgl2"
duration=120
warmup=20
complexity=2
viewer_dir="$ROOT/viewer/dist"
output_dir="$ROOT/benchmarks/raw"
build_args=""
package_dir=""
viewer_mode=0
viewer_trusted_content=0
viewer_aggressive_gpu=0
viewer_relaxed_webgl_validation=0
viewer_zero_copy=0
viewer_in_process_gpu=0
viewer_single_process=0
viewer_force_angle_backend=""
reuse_valid_results=0
dry_run=0

browser_flags=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --browser) browser="$2"; shift 2 ;;
    --label) label="$2"; shift 2 ;;
    --renderer) renderer="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --warmup) warmup="$2"; shift 2 ;;
    --complexity) complexity="$2"; shift 2 ;;
    --viewer-dir) viewer_dir="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --build-args) build_args="$2"; shift 2 ;;
    --package-dir) package_dir="$2"; shift 2 ;;
    --viewer-mode) viewer_mode=1; shift ;;
    --viewer-trusted-content) viewer_trusted_content=1; shift ;;
    --viewer-aggressive-gpu) viewer_aggressive_gpu=1; shift ;;
    --viewer-relaxed-webgl-validation) viewer_relaxed_webgl_validation=1; shift ;;
    --viewer-zero-copy) viewer_zero_copy=1; shift ;;
    --viewer-in-process-gpu) viewer_in_process_gpu=1; shift ;;
    --viewer-single-process) viewer_single_process=1; shift ;;
    --viewer-force-angle-backend) viewer_force_angle_backend="$2"; shift 2 ;;
    --browser-flag) browser_flags+=("$2"); shift 2 ;;
    --reuse-valid-results) reuse_valid_results=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./scripts/run_full_suite.sh --browser ./src/out/ReleaseBaseline/content_shell --label baseline-content-shell [--renderer webgl2]
USAGE
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$renderer" == "webgl2" ]] || die "WSL first port supports retained WebGL2 suites only; requested renderer=$renderer"
[[ -n "$browser" ]] || die "--browser is required"
[[ -x "$browser" ]] || die "browser is not executable: $browser"
[[ -f "$viewer_dir/index.html" ]] || die "viewer bundle missing: $viewer_dir/index.html"

mkdir -p "$output_dir"
scenes=(many-draw-calls large-static instancing shader-heavy postprocessing texture-streaming gltf-loader-stress)
result_files=()

for scene in "${scenes[@]}"; do
  out="$output_dir/${label}-${scene}-${renderer}.json"
  result_files+=("$out")
  if [[ "$reuse_valid_results" -eq 1 && -f "$out" ]]; then
    info "Reusing existing result $out"
    continue
  fi

  cmd=(node "$ROOT/scripts/run_benchmark.mjs"
    --browser "$browser"
    --variant "$label"
    --scene "$scene"
    --renderer "$renderer"
    --duration "$duration"
    --warmup "$warmup"
    --complexity "$complexity"
    --viewerDir "$viewer_dir"
    --output "$out")

  [[ -n "$build_args" ]] && cmd+=(--buildArgs "$build_args")
  [[ -n "$package_dir" ]] && cmd+=(--packageDir "$package_dir")
  [[ "$viewer_mode" -eq 1 ]] && cmd+=(--viewerMode)
  [[ "$viewer_trusted_content" -eq 1 ]] && cmd+=(--viewerTrustedContent)
  [[ "$viewer_aggressive_gpu" -eq 1 ]] && cmd+=(--viewerAggressiveGpu)
  [[ "$viewer_relaxed_webgl_validation" -eq 1 ]] && cmd+=(--viewerRelaxedWebglValidation)
  [[ "$viewer_zero_copy" -eq 1 ]] && cmd+=(--viewerZeroCopy)
  [[ "$viewer_in_process_gpu" -eq 1 ]] && cmd+=(--viewerInProcessGpu)
  [[ "$viewer_single_process" -eq 1 ]] && cmd+=(--viewerSingleProcess)
  [[ -n "$viewer_force_angle_backend" ]] && cmd+=(--viewerForceAngleBackend "$viewer_force_angle_backend")
  for flag in "${browser_flags[@]}"; do
    cmd+=(--browser-flag "$flag")
  done

  if [[ "$dry_run" -eq 1 ]]; then
    printf '%q ' "${cmd[@]}"
    printf '\n'
  else
    "${cmd[@]}"
    node "$ROOT/scripts/validate_metrics.mjs" "$out"
  fi
done

if [[ "$dry_run" -eq 0 ]]; then
  printf '%s\n' "${result_files[@]}"
fi

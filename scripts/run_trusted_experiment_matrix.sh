#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

browser=""
renderer="webgl2"
duration=120
warmup=20
complexity=2
include_default=0
include_aggressive_gpu=0
include_zero_copy=0
angle_backend=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --browser) browser="$2"; shift 2 ;;
    --renderer) renderer="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --warmup) warmup="$2"; shift 2 ;;
    --complexity) complexity="$2"; shift 2 ;;
    --include-default) include_default=1; shift ;;
    --include-aggressive-gpu) include_aggressive_gpu=1; shift ;;
    --include-zero-copy) include_zero_copy=1; shift ;;
    --angle-backend) angle_backend="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./scripts/run_trusted_experiment_matrix.sh --browser ./src/out/ReleaseViewerDefault/content_shell --include-default --include-aggressive-gpu"
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ "$renderer" == "webgl2" ]] || { echo "WSL trusted matrix currently supports WebGL2 only; WebGPU parity is not migrated yet" >&2; exit 1; }
[[ -x "$browser" ]] || { echo "browser is not executable: $browser" >&2; exit 1; }
if [[ "$include_default" -eq 0 && "$include_aggressive_gpu" -eq 0 && "$include_zero_copy" -eq 0 && -z "$angle_backend" ]]; then
  echo "select at least one experiment family" >&2
  exit 1
fi

files=()
run_suite() {
  local label="$1"
  shift
  "$ROOT/scripts/run_full_suite.sh" --browser "$browser" --label "$label" --renderer "$renderer" --duration "$duration" --warmup "$warmup" --complexity "$complexity" --viewer-mode --viewer-trusted-content "$@"
  for scene in many-draw-calls large-static instancing shader-heavy postprocessing texture-streaming gltf-loader-stress; do
    files+=("$ROOT/benchmarks/raw/$label-$scene-$renderer.json")
  done
}

[[ "$include_default" -eq 1 ]] && run_suite "fork-viewer-trusted-default"
[[ "$include_aggressive_gpu" -eq 1 ]] && run_suite "fork-viewer-exp-aggressive-gpu" --viewer-aggressive-gpu
[[ "$include_zero_copy" -eq 1 ]] && run_suite "fork-viewer-exp-zero-copy" --viewer-zero-copy
if [[ -n "$angle_backend" ]]; then
  run_suite "fork-viewer-exp-angle-$angle_backend" --viewer-force-angle-backend "$angle_backend"
fi

mkdir -p "$ROOT/benchmarks/reports"
node "$ROOT/scripts/compare_results.mjs" "${files[@]}" --strictEvidence --output "$ROOT/benchmarks/reports/trusted-experiment-matrix-webgl2-comparison.md"

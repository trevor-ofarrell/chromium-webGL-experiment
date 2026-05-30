#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

baseline_browser=""
fork_browser=""
renderer="webgl2"
duration=120
warmup=20
complexity=2
label_prefix="alternating-pair"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline-browser) baseline_browser="$2"; shift 2 ;;
    --fork-browser) fork_browser="$2"; shift 2 ;;
    --renderer) renderer="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --warmup) warmup="$2"; shift 2 ;;
    --complexity) complexity="$2"; shift 2 ;;
    --label-prefix) label_prefix="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./scripts/run_alternating_pair_suite.sh --baseline-browser ./src/out/ReleaseBaseline/content_shell --fork-browser ./src/out/ReleaseViewerDefault/content_shell"
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ "$renderer" == "webgl2" ]] || { echo "WSL alternating pair currently supports WebGL2 only" >&2; exit 1; }
[[ -x "$baseline_browser" ]] || { echo "baseline browser is not executable: $baseline_browser" >&2; exit 1; }
[[ -x "$fork_browser" ]] || { echo "fork browser is not executable: $fork_browser" >&2; exit 1; }

mkdir -p "$ROOT/benchmarks/raw" "$ROOT/benchmarks/reports"
scenes=(many-draw-calls large-static instancing shader-heavy postprocessing texture-streaming gltf-loader-stress)
files=()
index=0
for scene in "${scenes[@]}"; do
  if (( index % 2 == 0 )); then
    order=(baseline fork)
  else
    order=(fork baseline)
  fi
  for side in "${order[@]}"; do
    if [[ "$side" == baseline ]]; then
      browser="$baseline_browser"
      variant="$label_prefix-baseline"
      extra=()
    else
      browser="$fork_browser"
      variant="$label_prefix-fork"
      extra=(--viewerMode --viewerTrustedContent)
    fi
    out="$ROOT/benchmarks/raw/$variant-$scene-$renderer.json"
    files+=("$out")
    node "$ROOT/scripts/run_benchmark.mjs" --browser "$browser" --variant "$variant" --scene "$scene" --renderer "$renderer" --duration "$duration" --warmup "$warmup" --complexity "$complexity" --output "$out" "${extra[@]}"
  done
  index=$((index + 1))
done

node "$ROOT/scripts/compare_results.mjs" "${files[@]}" --strictEvidence --output "$ROOT/benchmarks/reports/$label_prefix-$renderer-comparison.md"

#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/wsl_common.sh
. "$ROOT/scripts/lib/wsl_common.sh"

baseline_browser="./src/out/ReleaseBaseline/content_shell"
fork_browser="./src/out/ReleaseViewerDefault/content_shell"
baseline_build_args="./src/out/ReleaseBaseline/args.gn"
fork_build_args="./src/out/ReleaseViewerDefault/args.gn"
baseline_package_dir=""
fork_package_dir=""
renderer="webgl2"
duration=120
warmup=20
complexity=2
include_aggressive_gpu=0
aggressive_angle_backend=""
aggressive_relaxed_webgl_validation=0
aggressive_zero_copy=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline-browser) baseline_browser="$2"; shift 2 ;;
    --fork-browser) fork_browser="$2"; shift 2 ;;
    --baseline-build-args) baseline_build_args="$2"; shift 2 ;;
    --fork-build-args) fork_build_args="$2"; shift 2 ;;
    --baseline-package-dir) baseline_package_dir="$2"; shift 2 ;;
    --fork-package-dir) fork_package_dir="$2"; shift 2 ;;
    --renderer) renderer="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --warmup) warmup="$2"; shift 2 ;;
    --complexity) complexity="$2"; shift 2 ;;
    --include-aggressive-gpu) include_aggressive_gpu=1; shift ;;
    --aggressive-angle-backend) aggressive_angle_backend="$2"; shift 2 ;;
    --aggressive-webgl2-relaxed-validation) aggressive_relaxed_webgl_validation=1; shift ;;
    --aggressive-webgl2-zero-copy) aggressive_zero_copy=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./scripts/run_official_comparison.sh --baseline-browser ./src/out/ReleaseBaseline/content_shell --fork-browser ./src/out/ReleaseViewerDefault/content_shell --renderer webgl2
USAGE
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$renderer" == "webgl2" ]] || die "WSL first port supports official WebGL2 comparison only"

baseline_browser="$(abs_path "$baseline_browser")"
fork_browser="$(abs_path "$fork_browser")"
[[ -x "$baseline_browser" ]] || die "baseline browser is not executable: $baseline_browser"
[[ -x "$fork_browser" ]] || die "fork browser is not executable: $fork_browser"

report_dir="$ROOT/benchmarks/reports"
raw_dir="$ROOT/benchmarks/raw"
mkdir -p "$report_dir" "$raw_dir"

baseline_label="baseline-content-shell"
fork_label="fork-viewer-default"
scenes=(many-draw-calls large-static instancing shader-heavy postprocessing texture-streaming gltf-loader-stress)

baseline_cmd=("$ROOT/scripts/run_full_suite.sh"
  --browser "$baseline_browser"
  --label "$baseline_label"
  --renderer "$renderer"
  --duration "$duration"
  --warmup "$warmup"
  --complexity "$complexity"
  --build-args "$baseline_build_args")
[[ -n "$baseline_package_dir" ]] && baseline_cmd+=(--package-dir "$baseline_package_dir")
"${baseline_cmd[@]}"

fork_cmd=("$ROOT/scripts/run_full_suite.sh"
  --browser "$fork_browser"
  --label "$fork_label"
  --renderer "$renderer"
  --duration "$duration"
  --warmup "$warmup"
  --complexity "$complexity"
  --build-args "$fork_build_args"
  --viewer-mode
  --viewer-trusted-content)
[[ -n "$fork_package_dir" ]] && fork_cmd+=(--package-dir "$fork_package_dir")
"${fork_cmd[@]}"

aggressive_files=()
aggressive_label=""
if [[ "$include_aggressive_gpu" -eq 1 ]]; then
  aggressive_label="fork-viewer-aggressive-gpu"
  [[ -n "$aggressive_angle_backend" ]] && aggressive_label="$aggressive_label-$aggressive_angle_backend"
  cmd=("$ROOT/scripts/run_full_suite.sh"
    --browser "$fork_browser"
    --label "$aggressive_label"
    --renderer "$renderer"
    --duration "$duration"
    --warmup "$warmup"
    --complexity "$complexity"
    --build-args "$fork_build_args"
    --viewer-mode
    --viewer-trusted-content
    --viewer-aggressive-gpu)
  [[ -n "$fork_package_dir" ]] && cmd+=(--package-dir "$fork_package_dir")
  [[ -n "$aggressive_angle_backend" ]] && cmd+=(--viewer-force-angle-backend "$aggressive_angle_backend")
  [[ "$aggressive_relaxed_webgl_validation" -eq 1 ]] && cmd+=(--viewer-relaxed-webgl-validation)
  [[ "$aggressive_zero_copy" -eq 1 ]] && cmd+=(--viewer-zero-copy)
  "${cmd[@]}"
fi

baseline_files=()
fork_files=()
for scene in "${scenes[@]}"; do
  baseline_files+=("$raw_dir/$baseline_label-$scene-$renderer.json")
  fork_files+=("$raw_dir/$fork_label-$scene-$renderer.json")
  if [[ -n "$aggressive_label" ]]; then
    aggressive_files+=("$raw_dir/$aggressive_label-$scene-$renderer.json")
  fi
done

node "$ROOT/scripts/compare_results.mjs" "${baseline_files[@]}" --strictEvidence --output "$report_dir/$baseline_label-webgl2-summary.md"
node "$ROOT/scripts/compare_results.mjs" "${fork_files[@]}" --strictEvidence --output "$report_dir/$fork_label-webgl2-summary.md"
node "$ROOT/scripts/compare_results.mjs" "${baseline_files[@]}" "${fork_files[@]}" "${aggressive_files[@]}" --strictSameRevision --strictEvidence --output "$report_dir/official-webgl2-comparison.md"

manifest_args=(node "$ROOT/scripts/write_official_manifest.mjs"
  --output "$report_dir/official-comparison-manifest.json"
  --renderer "$renderer"
  --duration "$duration"
  --warmup "$warmup"
  --complexity "$complexity"
  --baselineBrowser "$baseline_browser"
  --forkBrowser "$fork_browser"
  --baselineBuildArgs "$baseline_build_args"
  --forkBuildArgs "$fork_build_args"
  --baselinePackageDir "$baseline_package_dir"
  --forkPackageDir "$fork_package_dir"
  --includeAggressiveGpu "$([[ "$include_aggressive_gpu" -eq 1 ]] && echo true || echo false)"
  --officialWebgl2Comparison "$report_dir/official-webgl2-comparison.md")

for file in "${baseline_files[@]}"; do manifest_args+=(--baseline "$file"); done
for file in "${fork_files[@]}"; do manifest_args+=(--fork "$file"); done
for file in "${aggressive_files[@]}"; do manifest_args+=(--aggressive "$file"); done
"${manifest_args[@]}"

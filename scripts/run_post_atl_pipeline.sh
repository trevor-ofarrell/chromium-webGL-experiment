#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

refresh_chromium_pin=0
refresh_revision=""
build_jobs=0
duration=120
warmup=20
complexity=2
skip_build=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh-chromium-pin) refresh_chromium_pin=1; shift ;;
    --refresh-revision) refresh_revision="$2"; shift 2 ;;
    --build-jobs) build_jobs="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --warmup) warmup="$2"; shift 2 ;;
    --complexity) complexity="$2"; shift 2 ;;
    --skip-build) skip_build=1; shift ;;
    -h|--help)
      echo "Usage: ./scripts/run_post_atl_pipeline.sh [--refresh-chromium-pin] [--refresh-revision SHA] [--build-jobs N] [--skip-build]"
      exit 0
      ;;
    *) echo "error: unknown/unsupported WSL pipeline argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$refresh_chromium_pin" -eq 1 ]]; then
  if [[ -n "$refresh_revision" ]]; then
    "$ROOT/scripts/refresh_chromium_pin.sh" --revision "$refresh_revision"
  else
    "$ROOT/scripts/refresh_chromium_pin.sh"
  fi
fi

"$ROOT/scripts/check_prereqs.sh"

if [[ "$skip_build" -eq 0 ]]; then
  build_args=()
  [[ "$build_jobs" -gt 0 ]] && build_args+=(--jobs "$build_jobs")
  "$ROOT/scripts/build_chromium.sh" --out-dir out/ReleaseBaseline --args-file build/gn_args/linux/baseline_content_shell.gn --target content_shell "${build_args[@]}"
  "$ROOT/scripts/build_viewer_fork.sh" --apply-patch --out-dir out/ReleaseViewerDefault --args-file build/gn_args/linux/fork_safe_content_shell.gn --target content_shell "${build_args[@]}"
fi

"$ROOT/scripts/stage_viewer_package.sh" --chromium-out-dir "$ROOT/src/out/ReleaseBaseline" --package-dir "$ROOT/benchmarks/packages/baseline-content-shell" --clean
"$ROOT/scripts/stage_viewer_package.sh" --chromium-out-dir "$ROOT/src/out/ReleaseViewerDefault" --package-dir "$ROOT/benchmarks/packages/viewer-default" --clean

"$ROOT/scripts/run_official_comparison.sh" \
  --baseline-browser "$ROOT/src/out/ReleaseBaseline/content_shell" \
  --fork-browser "$ROOT/src/out/ReleaseViewerDefault/content_shell" \
  --baseline-build-args "$ROOT/src/out/ReleaseBaseline/args.gn" \
  --fork-build-args "$ROOT/src/out/ReleaseViewerDefault/args.gn" \
  --baseline-package-dir "$ROOT/benchmarks/packages/baseline-content-shell" \
  --fork-package-dir "$ROOT/benchmarks/packages/viewer-default" \
  --renderer webgl2 \
  --duration "$duration" \
  --warmup "$warmup" \
  --complexity "$complexity"

"$ROOT/scripts/audit_artifacts.sh" --fail-on-incomplete --output "$ROOT/docs/prompt_to_artifact_checklist.md"

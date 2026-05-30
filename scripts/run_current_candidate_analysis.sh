#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$ROOT/benchmarks/reports/current-candidate-analysis.md"
json="$ROOT/benchmarks/reports/current-candidate-analysis.json"
inputs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --json) json="$2"; shift 2 ;;
    --input) inputs+=("$2"); shift 2 ;;
    --file-list) inputs+=(--fileList "$2"); shift 2 ;;
    -h|--help)
      echo "Usage: ./scripts/run_current_candidate_analysis.sh --input result.json [--input result2.json] [--output report.md] [--json report.json]"
      exit 0
      ;;
    *) inputs+=("$1"); shift ;;
  esac
done

[[ "${#inputs[@]}" -gt 0 ]] || { echo "at least one input result or --file-list is required" >&2; exit 1; }
node "$ROOT/scripts/analyze_candidates.mjs" "${inputs[@]}" --output "$output" --json "$json"

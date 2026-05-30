#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
candidate_json=""
output="$ROOT/benchmarks/reports/targeted-suite-promotion-plan.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --candidate-analysis-json) candidate_json="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./scripts/plan_suite_promotion.sh --candidate-analysis-json report.json [--output plan.json]"
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$candidate_json" ]] || { echo "--candidate-analysis-json is required" >&2; exit 1; }
node - "$candidate_json" "$output" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [candidateJson, output] = process.argv.slice(2);
const analysis = JSON.parse(fs.readFileSync(candidateJson, 'utf8'));
const plan = {
  generated_at: new Date().toISOString(),
  host_platform: 'wsl-linux',
  candidate_analysis_json: candidateJson,
  promotion_policy: 'rerun-full-seven-scene-webgl2-suite-before-retained-claim',
  recommended_commands: [
    './scripts/run_official_comparison.sh --baseline-browser ./src/out/ReleaseBaseline/content_shell --fork-browser ./src/out/ReleaseViewerDefault/content_shell --renderer webgl2',
  ],
  source_summary: analysis.summary || null,
};
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, `${JSON.stringify(plan, null, 2)}\n`);
console.log(`Wrote ${output}`);
NODE

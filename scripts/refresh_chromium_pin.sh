#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/wsl_common.sh
. "$ROOT/scripts/lib/wsl_common.sh"

revision=""
dry_run=0
output="benchmarks/reports/chromium-pin-refresh.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revision) revision="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --output) output="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./scripts/refresh_chromium_pin.sh [--revision SHA] [--dry-run] [--output benchmarks/reports/chromium-pin-refresh.json]"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ -z "$revision" ]]; then
  require_command git
  revision="$(git ls-remote https://chromium.googlesource.com/chromium/src.git HEAD | awk '{print $1}')"
fi
[[ -n "$revision" ]] || die "unable to determine Chromium revision"

previous="$(expected_chromium_revision "$ROOT")"
if [[ "$dry_run" -eq 0 ]]; then
  printf '%s\n' "$revision" > "$ROOT/.chromium_revision"
fi

mkdir -p "$ROOT/$(dirname "$output")"
node - "$ROOT" "$output" "$previous" "$revision" "$dry_run" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [root, output, previous, revision, dryRun] = process.argv.slice(2);
const out = path.resolve(root, output);
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify({
  generated_at: new Date().toISOString(),
  previous_revision: previous,
  target_revision: revision,
  dry_run: dryRun === '1',
  source: 'wsl-refresh-script',
}, null, 2)}\n`);
console.log(`Wrote ${out}`);
NODE

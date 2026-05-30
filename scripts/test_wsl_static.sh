#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "$ROOT/.gitattributes" ]] || fail ".gitattributes is missing"
grep -q '\*.sh text eol=lf' "$ROOT/.gitattributes" || fail ".gitattributes does not force LF for Bash"

for script in bootstrap_wsl check_prereqs build_chromium build_viewer_fork stage_viewer_package run_full_suite run_official_comparison verify_prebuild audit_artifacts; do
  [[ -f "$ROOT/scripts/$script.sh" ]] || fail "scripts/$script.sh is missing"
done

if find "$ROOT/scripts" -maxdepth 1 -name '*.ps1' | grep -q .; then
  fail "PowerShell scripts remain in the supported scripts root"
fi

[[ -d "$ROOT/scripts/windows-legacy" ]] || fail "scripts/windows-legacy is missing"
[[ -f "$ROOT/docs/wsl.md" ]] || fail "docs/wsl.md is missing"
[[ -f "$ROOT/docs/windows-legacy/README.md" ]] || fail "docs/windows-legacy/README.md is missing"

if grep -In 'powershell.exe\|\.\\scripts\\.*\.ps1' "$ROOT/README.md" "$ROOT/docs/build.md" "$ROOT/docs/wsl.md"; then
  fail "primary WSL docs still advertise PowerShell commands"
fi

echo "WSL static structure test passed."

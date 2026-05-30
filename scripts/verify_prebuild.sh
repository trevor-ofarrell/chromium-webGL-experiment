#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skip_host_check=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-host-check) skip_host_check=1; shift ;;
    -h|--help)
      echo "Usage: ./scripts/verify_prebuild.sh [--skip-host-check]"
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$skip_host_check" -eq 0 ]]; then
  "$ROOT/scripts/check_prereqs.sh"
fi

echo "Checking Bash syntax..."
while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT/scripts" -maxdepth 2 -name '*.sh' -not -path '*/windows-legacy/*' | sort)

if command -v shellcheck >/dev/null 2>&1; then
  echo "Running shellcheck..."
  while IFS= read -r script; do
    shellcheck "$script"
  done < <(find "$ROOT/scripts" -maxdepth 2 -name '*.sh' -not -path '*/windows-legacy/*' | sort)
else
  echo "shellcheck not installed; skipping shellcheck."
fi

echo "Checking Node scripts..."
while IFS= read -r script; do
  node --check "$script"
done < <(find "$ROOT/scripts" -maxdepth 1 -name '*.mjs' | sort)

echo "Running WSL Bash regression tests..."
while IFS= read -r script; do
  "$script"
done < <(find "$ROOT/scripts" -maxdepth 1 -name 'test_*.sh' | sort)

if [[ "$skip_host_check" -eq 0 ]]; then
  echo "Writing environment manifest..."
  "$ROOT/scripts/write_environment_manifest.sh" --output benchmarks/reports/prebuild-environment.json
else
  echo "Skipping environment manifest because --skip-host-check was requested."
fi

echo "Checking primary WSL documentation no longer advertises PowerShell..."
if grep -In 'powershell.exe\|\.\\scripts\\.*\.ps1' "$ROOT/README.md" "$ROOT/docs/build.md" "$ROOT/docs/wsl.md" >/tmp/three-browser-ps1-docs.txt; then
  cat /tmp/three-browser-ps1-docs.txt >&2
  echo "PowerShell primary-command references remain in supported docs." >&2
  exit 1
fi

echo "Prebuild verification complete."

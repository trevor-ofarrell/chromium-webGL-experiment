#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="$ROOT/src/content/shell/BUILD.gn"

[[ -f "$target_file" ]] || { echo "Chromium content shell BUILD.gn missing: $target_file" >&2; exit 1; }

echo "Chromium content shell target:"
grep -n 'content_shell' "$target_file" | head -n 20

echo
echo "Expected source roots:"
for dir in content/shell/app content/shell/browser content/shell/common; do
  if [[ -d "$ROOT/src/$dir" ]]; then
    echo "ok  $dir"
  else
    echo "missing  $dir"
  fi
done

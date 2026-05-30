#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for profile in baseline_content_shell fork_safe_content_shell fork_trusted_aggressive; do
  file="$ROOT/build/gn_args/linux/$profile.gn"
  [[ -f "$file" ]] || { echo "missing Linux GN profile: $file" >&2; exit 1; }
  grep -q '^is_debug = false$' "$file" || { echo "$file missing release-style is_debug setting" >&2; exit 1; }
  grep -q '^is_component_build = false$' "$file" || { echo "$file missing component-build setting" >&2; exit 1; }
  if grep -q 'disable_llvm_machine_scheduler\|enable_ubsan_hardening' "$file"; then
    echo "$file contains Windows clang workaround settings" >&2
    exit 1
  fi
done

echo "Linux GN profile test passed."

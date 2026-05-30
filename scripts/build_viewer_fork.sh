#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/wsl_common.sh
. "$ROOT/scripts/lib/wsl_common.sh"

out_dir="out/ReleaseViewerDefault"
args_file="build/gn_args/linux/fork_safe_content_shell.gn"
target="content_shell"
jobs=0
apply_patch=0
overwrite_args=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) out_dir="$2"; shift 2 ;;
    --args-file) args_file="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --apply-patch) apply_patch=1; shift ;;
    --overwrite-args) overwrite_args=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./scripts/build_viewer_fork.sh [--apply-patch] [--out-dir out/ReleaseViewerDefault] [--args-file build/gn_args/linux/fork_safe_content_shell.gn] [--target content_shell]
USAGE
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

src="$ROOT/src"
patch_series=(
  "chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch"
  "chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch"
)

"$ROOT/scripts/check_prereqs.sh"

git_apply_check() {
  local patch_path="$1"
  local reverse="${2:-0}"
  if [[ "$reverse" == "1" ]]; then
    git -C "$src" apply --reverse --check "$patch_path" >/dev/null 2>&1
  else
    git -C "$src" apply --check "$patch_path" >/dev/null 2>&1
  fi
}

if [[ "$apply_patch" -eq 1 ]]; then
  for rel in "${patch_series[@]}"; do
    patch="$ROOT/$rel"
    [[ -f "$patch" ]] || die "viewer patch not found: $patch"
    if git_apply_check "$patch"; then
      git -C "$src" apply "$patch"
      info "Applied viewer patch $rel."
    elif git_apply_check "$patch" 1; then
      info "Viewer patch is already applied: $rel"
    else
      die "viewer patch cannot be applied cleanly and is not already applied: $rel"
    fi
  done
fi

cmd=("$ROOT/scripts/build_chromium.sh" --out-dir "$out_dir" --target "$target" --args-file "$args_file" --allow-viewer-patch-applied)
if [[ "$jobs" -gt 0 ]]; then
  cmd+=(--jobs "$jobs")
fi
if [[ "$overwrite_args" -eq 1 ]]; then
  cmd+=(--overwrite-args)
fi
"${cmd[@]}"

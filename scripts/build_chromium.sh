#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/wsl_common.sh
. "$ROOT/scripts/lib/wsl_common.sh"

out_dir="out/ReleaseBaseline"
target="content_shell"
args_file="build/gn_args/linux/baseline_content_shell.gn"
jobs=0
overwrite_args=0
gen_only=0
allow_viewer_patch_applied=0
skip_prereq_check=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) out_dir="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --args-file) args_file="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --overwrite-args) overwrite_args=1; shift ;;
    --gen-only) gen_only=1; shift ;;
    --allow-viewer-patch-applied) allow_viewer_patch_applied=1; shift ;;
    --skip-prereq-check) skip_prereq_check=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./scripts/build_chromium.sh [--out-dir out/ReleaseBaseline] [--args-file build/gn_args/linux/baseline_content_shell.gn] [--target content_shell] [--jobs N] [--overwrite-args] [--gen-only]
USAGE
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

src="$ROOT/src"
source_args="$ROOT/$args_file"
out_abs="$src/$out_dir"
args_dest="$out_abs/args.gn"
patch_series=(
  "chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch"
  "chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch"
)

[[ -d "$src" ]] || die "Chromium checkout not found at $src. Run ./scripts/bootstrap_wsl.sh first."
[[ -f "$src/content/shell/BUILD.gn" ]] || die "Chromium checkout is incomplete: content/shell/BUILD.gn is missing."
[[ -d "$ROOT/tools/depot_tools" ]] || die "depot_tools not found. Run ./scripts/bootstrap_wsl.sh first."
[[ -f "$source_args" ]] || die "GN args file not found: $source_args"

prepend_depot_tools "$ROOT"

if [[ "$skip_prereq_check" -eq 0 ]]; then
  "$ROOT/scripts/check_prereqs.sh"
fi

test_git_apply() {
  local patch_path="$1"
  local reverse="${2:-0}"
  if [[ "$reverse" == "1" ]]; then
    git -C "$src" apply --reverse --check "$patch_path" >/dev/null 2>&1
  else
    git -C "$src" apply --check "$patch_path" >/dev/null 2>&1
  fi
}

is_baseline_profile() {
  local normalized_out="${out_dir//\\//}"
  [[ "$(cd "$(dirname "$source_args")" && pwd)/$(basename "$source_args")" == "$ROOT/build/gn_args/linux/baseline_content_shell.gn" ]] ||
    [[ "$normalized_out" == */ReleaseBaseline || "$normalized_out" == ReleaseBaseline ]]
}

if [[ "$allow_viewer_patch_applied" -eq 0 ]] && is_baseline_profile; then
  for rel in "${patch_series[@]}"; do
    patch="$ROOT/$rel"
    [[ -f "$patch" ]] || die "cannot audit viewer patch state because $patch is missing"
    if test_git_apply "$patch" 1; then
      die "cannot build stock baseline while viewer patch is applied: $rel"
    fi
  done
fi

mkdir -p "$out_abs"
if [[ ! -f "$args_dest" || "$overwrite_args" -eq 1 ]]; then
  cp "$source_args" "$args_dest"
elif [[ "$(sha256_file "$source_args")" != "$(sha256_file "$args_dest")" ]]; then
  die "existing args.gn differs from $source_args; pass --overwrite-args to refresh it"
fi

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
(cd "$src" && gn gen "$out_dir")

if [[ "$gen_only" -eq 1 ]]; then
  info "Generated GN files for $out_dir without invoking autoninja."
  exit 0
fi

ninja_args=(-C "$out_dir")
if [[ "$jobs" -gt 0 ]]; then
  ninja_args+=(-j "$jobs")
fi
ninja_args+=("$target")
(cd "$src" && autoninja "${ninja_args[@]}")

target_artifact="$out_abs/$target"
node "$ROOT/scripts/write_build_provenance.mjs" \
  --root "$ROOT" \
  --outDir "$out_dir" \
  --target "$target" \
  --targetArtifact "$target_artifact" \
  --sourceArgs "$args_file" \
  --startedAt "$started_at" \
  --jobs "$jobs" \
  --allowViewerPatchApplied "$([[ "$allow_viewer_patch_applied" -eq 1 ]] && echo true || echo false)" \
  --baselineSourceGuardEnabled "$([[ "$allow_viewer_patch_applied" -eq 0 ]] && is_baseline_profile && echo true || echo false)"

#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/wsl_common.sh
. "$ROOT/scripts/lib/wsl_common.sh"

revision=""
skip_sync=0
skip_hooks=0
skip_apt=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revision)
      revision="${2:-}"
      shift 2
      ;;
    --skip-sync)
      skip_sync=1
      shift
      ;;
    --skip-hooks)
      skip_hooks=1
      shift
      ;;
    --skip-apt)
      skip_apt=1
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./scripts/bootstrap_wsl.sh [--revision SHA] [--skip-sync] [--skip-hooks] [--skip-apt]
USAGE
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

require_wsl
require_supported_ubuntu
require_linux_filesystem "$ROOT"

if [[ -z "$revision" ]]; then
  revision="$(expected_chromium_revision "$ROOT")"
fi
[[ -n "$revision" ]] || die "Chromium revision is missing"

if [[ "$skip_apt" -eq 0 ]]; then
  run_checked "Installing base packages" sudo apt-get update
  run_checked "Installing WSL/Chromium bootstrap dependencies" sudo apt-get install -y \
    ca-certificates curl file git lsb-release nodejs npm python3 python3-dev python3-venv \
    pkg-config build-essential xz-utils shellcheck
fi

if [[ ! -d "$ROOT/tools/depot_tools/.git" ]]; then
  mkdir -p "$ROOT/tools"
  run_checked "Cloning depot_tools" git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$ROOT/tools/depot_tools"
fi

prepend_depot_tools "$ROOT"
require_command gclient
run_checked "Updating depot_tools" update_depot_tools

if [[ "$skip_sync" -eq 1 ]]; then
  info "Skipping Chromium sync. depot_tools is ready at $ROOT/tools/depot_tools"
else
  if [[ ! -f "$ROOT/.gclient" ]]; then
    (cd "$ROOT" && gclient config https://chromium.googlesource.com/chromium/src.git)
  fi

  sync_args=(sync --no-history --revision "src@$revision")
  if [[ "$skip_hooks" -eq 1 ]]; then
    sync_args+=(--nohooks)
  fi
  run_checked "Syncing Chromium $revision" gclient "${sync_args[@]}"

  if [[ -x "$ROOT/src/build/install-build-deps.sh" && "$skip_apt" -eq 0 ]]; then
    run_checked "Installing Chromium Linux build dependencies" "$ROOT/src/build/install-build-deps.sh" --no-prompt
  fi

  if [[ "$skip_hooks" -eq 0 ]]; then
    run_checked "Running Chromium hooks" gclient runhooks
  fi
fi

run_checked "Installing viewer dependencies" npm --prefix "$ROOT/viewer" ci
run_checked "Building viewer bundle" npm --prefix "$ROOT/viewer" run build

info "WSL bootstrap complete"

#!/usr/bin/env bash

set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s\n' "$script_dir"
}

abs_path() {
  local path_value="$1"
  if [[ "$path_value" = /* ]]; then
    printf '%s\n' "$path_value"
  else
    printf '%s\n' "$(cd "$(dirname "$path_value")" 2>/dev/null && pwd)/$(basename "$path_value")"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

is_wsl() {
  grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null ||
    grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

require_wsl() {
  is_wsl || die "this command is intended to run inside Ubuntu 22.04 or 24.04 on WSL2"
}

require_linux_filesystem() {
  local root="$1"
  case "$root" in
    /mnt/*)
      die "repo is under $root; clone into /home/<user>/code/three-browser for WSL build performance"
      ;;
  esac
}

ubuntu_version_id() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf '%s\n' "${VERSION_ID:-}"
  fi
}

require_supported_ubuntu() {
  local version
  version="$(ubuntu_version_id)"
  [[ "$version" == "22.04" || "$version" == "24.04" ]] || die "Ubuntu 22.04 or 24.04 is required for this WSL port; detected VERSION_ID=${version:-unknown}"
}

prepend_depot_tools() {
  local root="$1"
  export PATH="$root/tools/depot_tools:$PATH"
}

sha256_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf '\n'
    return
  fi
  sha256sum "$file" | awk '{print tolower($1)}'
}

expected_chromium_revision() {
  local root="$1"
  tr -d '[:space:]' < "$root/.chromium_revision"
}

actual_chromium_revision() {
  local root="$1"
  if [[ -d "$root/src/.git" ]]; then
    git -C "$root/src" rev-parse HEAD 2>/dev/null || true
  fi
}

run_checked() {
  local label="$1"
  shift
  info "$label"
  "$@"
}

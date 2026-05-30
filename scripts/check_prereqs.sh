#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/wsl_common.sh
. "$ROOT/scripts/lib/wsl_common.sh"

allow_non_wsl=0
allow_wrong_ubuntu=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-non-wsl)
      allow_non_wsl=1
      shift
      ;;
    --allow-wrong-ubuntu)
      allow_wrong_ubuntu=1
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./scripts/check_prereqs.sh [--allow-non-wsl] [--allow-wrong-ubuntu]
USAGE
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

checks=()
failures=0

add_check() {
  local name="$1"
  local ok="$2"
  local detail="$3"
  checks+=("$name|$ok|$detail")
  if [[ "$ok" != "ok" ]]; then
    failures=$((failures + 1))
  fi
}

if [[ "$allow_non_wsl" -eq 1 ]] || is_wsl; then
  add_check "wsl2" "ok" "$(uname -r)"
else
  add_check "wsl2" "fail" "not running under WSL; use Ubuntu 22.04 or 24.04 WSL2"
fi

ubuntu_version="$(ubuntu_version_id)"
if [[ "$allow_wrong_ubuntu" -eq 1 || "$ubuntu_version" == "22.04" || "$ubuntu_version" == "24.04" ]]; then
  add_check "ubuntu_lts" "ok" "VERSION_ID=${ubuntu_version:-unknown}"
else
  add_check "ubuntu_lts" "fail" "VERSION_ID=${ubuntu_version:-unknown}; expected 22.04 or 24.04"
fi

case "$ROOT" in
  /mnt/*) add_check "linux_filesystem" "fail" "$ROOT is under /mnt; clone into /home/<user>/code/three-browser" ;;
  *) add_check "linux_filesystem" "ok" "$ROOT" ;;
esac

for cmd in git node npm python3 sha256sum; do
  if command -v "$cmd" >/dev/null 2>&1; then
    add_check "$cmd" "ok" "$(command -v "$cmd")"
  else
    add_check "$cmd" "fail" "missing"
  fi
done

prepend_depot_tools "$ROOT"
if [[ -f "$ROOT/tools/depot_tools/gclient.py" ]]; then
  add_check "depot_tools" "ok" "$ROOT/tools/depot_tools"
else
  add_check "depot_tools" "fail" "run ./scripts/bootstrap_wsl.sh"
fi

if command -v gclient >/dev/null 2>&1; then
  add_check "gclient" "ok" "$(command -v gclient)"
else
  add_check "gclient" "fail" "missing from PATH"
fi

expected="$(expected_chromium_revision "$ROOT")"
actual="$(actual_chromium_revision "$ROOT")"
if [[ -n "$expected" && "$actual" == "$expected" ]]; then
  add_check "chromium_revision" "ok" "expected=$expected actual=$actual"
else
  add_check "chromium_revision" "fail" "expected=$expected actual=${actual:-missing}"
fi

if [[ -x "$ROOT/src/buildtools/linux64/gn" ]]; then
  add_check "gn" "ok" "${ROOT}/src/buildtools/linux64/gn"
else
  add_check "gn" "fail" "missing ${ROOT}/src/buildtools/linux64/gn; sync Chromium and run hooks"
fi

if [[ -x "$ROOT/src/third_party/ninja/ninja" ]]; then
  add_check "ninja" "ok" "${ROOT}/src/third_party/ninja/ninja"
else
  add_check "ninja" "fail" "missing ${ROOT}/src/third_party/ninja/ninja; sync Chromium and run hooks"
fi

if [[ -f "$ROOT/viewer/dist/index.html" ]]; then
  add_check "viewer_dist" "ok" "$ROOT/viewer/dist/index.html"
else
  add_check "viewer_dist" "fail" "run npm --prefix viewer ci && npm --prefix viewer run build"
fi

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  add_check "wslg_display" "ok" "DISPLAY=${DISPLAY:-}; WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
else
  add_check "wslg_display" "fail" "DISPLAY or WAYLAND_DISPLAY is required for content_shell GPU benchmarks"
fi

if [[ -e /dev/dxg ]]; then
  add_check "wsl_gpu_device" "ok" "/dev/dxg"
else
  add_check "wsl_gpu_device" "fail" "/dev/dxg missing; WSLg GPU acceleration is not available"
fi

printf '%-34s %-6s %s\n' "Check" "OK" "Detail"
printf '%-34s %-6s %s\n' "-----" "--" "------"
for row in "${checks[@]}"; do
  IFS='|' read -r name ok detail <<<"$row"
  printf '%-34s %-6s %s\n' "$name" "$ok" "$detail"
done

if [[ "$failures" -gt 0 ]]; then
  echo
  echo "$failures prerequisite check(s) failed." >&2
  exit 1
fi

#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$ROOT/docs/prompt_to_artifact_checklist.md"
fail_on_incomplete=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --fail-on-incomplete) fail_on_incomplete=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./scripts/audit_artifacts.sh [--fail-on-incomplete] [--output docs/prompt_to_artifact_checklist.md]
USAGE
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

rows=()
incomplete=0

add_row() {
  local area="$1"
  local requirement="$2"
  local path_value="$3"
  local remaining="$4"
  local type="${5:-exists}"
  local status="pending"
  local detail="$remaining"
  local audit_output=""
  if audit_output="$(node "$ROOT/scripts/audit_wsl_artifact.mjs" --root "$ROOT" --type "$type" --path "$path_value" 2>&1)"; then
    status="done"
  else
    detail="$remaining $(printf '%s' "$audit_output" | tr '\n' ' ')"
    incomplete=$((incomplete + 1))
  fi
  rows+=("| $area | $requirement | $status | \`$path_value\` | $detail |")
}

add_executable_row() {
  local area="$1"
  local requirement="$2"
  local path_value="$3"
  local remaining="$4"
  local type="${5:-executable}"
  add_row "$area" "$requirement" "$path_value" "$remaining" "$type"
}

add_row "WSL setup" "LF attributes" ".gitattributes" "Add repository line-ending policy."
add_row "WSL setup" "WSL migration guide" "docs/wsl.md" "Document fresh clone and excluded Windows artifacts."
add_row "Build" "Linux baseline GN profile" "build/gn_args/linux/baseline_content_shell.gn" "Create Linux baseline profile."
add_row "Build" "Linux fork GN profile" "build/gn_args/linux/fork_safe_content_shell.gn" "Create Linux fork profile."
add_executable_row "Automation" "Bootstrap script" "scripts/bootstrap_wsl.sh" "Add executable bootstrap_wsl.sh."
add_executable_row "Automation" "Prerequisite checker" "scripts/check_prereqs.sh" "Add executable check_prereqs.sh."
add_executable_row "Automation" "Chromium builder" "scripts/build_chromium.sh" "Add executable build_chromium.sh."
add_executable_row "Automation" "Fork builder" "scripts/build_viewer_fork.sh" "Add executable build_viewer_fork.sh."
add_executable_row "Automation" "Package staging" "scripts/stage_viewer_package.sh" "Add executable stage_viewer_package.sh."
add_executable_row "Automation" "Official comparison" "scripts/run_official_comparison.sh" "Add executable run_official_comparison.sh."
add_executable_row "Automation" "Prebuild verifier" "scripts/verify_prebuild.sh" "Add executable verify_prebuild.sh."
add_executable_row "Automation" "Artifact audit" "scripts/audit_artifacts.sh" "Add executable audit_artifacts.sh."
add_executable_row "Build output" "Stock Linux content_shell" "src/out/ReleaseBaseline/content_shell" "Build the stock baseline in WSL." "linux-content-shell"
add_executable_row "Build output" "Fork Linux content_shell" "src/out/ReleaseViewerDefault/content_shell" "Build the patched fork in WSL." "linux-content-shell"
add_row "Build output" "Stock WSL provenance" "src/out/ReleaseBaseline/three_browser_build_provenance.json" "Run build_chromium.sh on WSL." "build-provenance"
add_row "Build output" "Fork WSL provenance" "src/out/ReleaseViewerDefault/three_browser_build_provenance.json" "Run build_viewer_fork.sh on WSL." "build-provenance"
add_executable_row "Package" "Fork Linux package launcher" "benchmarks/packages/viewer-default/run_viewer.sh" "Stage the fork package on WSL." "package-launcher"
add_row "Performance" "Official WSL WebGL2 comparison manifest" "benchmarks/reports/official-comparison-manifest.json" "Run run_official_comparison.sh on WSL." "official-manifest"
add_row "Performance" "Official WSL WebGL2 report" "benchmarks/reports/official-webgl2-comparison.md" "Run run_official_comparison.sh on WSL." "official-report"

mkdir -p "$(dirname "$output")"
{
  echo "# Prompt To Artifact Checklist"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "| Area | Requirement | Status | Artifact | Remaining Work |"
  echo "| --- | --- | --- | --- | --- |"
  printf '%s\n' "${rows[@]}"
} > "$output"

echo "Wrote $output"
if [[ "$fail_on_incomplete" -eq 1 && "$incomplete" -gt 0 ]]; then
  echo "$incomplete checklist row(s) are incomplete." >&2
  exit 1
fi

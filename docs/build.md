# Build Guide

This guide describes the supported WSL/Linux build flow. The old Windows PowerShell flow is archived under `scripts/windows-legacy/`.

## Host

- Ubuntu 22.04 on WSL2 as the pinned target; Ubuntu 24.04 is accepted for current-host validation.
- Repository path under `/home/<user>/code/three-browser`.
- WSLg display available through `DISPLAY` or `WAYLAND_DISPLAY`.
- GPU acceleration available through `/dev/dxg`.

Run the bootstrap from a fresh clone:

```bash
./scripts/bootstrap_wsl.sh
```

The bootstrap installs base packages, clones or updates `tools/depot_tools`, syncs the pinned Chromium revision, runs Chromium Linux dependency setup and hooks, and builds `viewer/dist`.

## Prerequisites

```bash
./scripts/check_prereqs.sh
```

The checker verifies WSL/Ubuntu, Linux filesystem placement, `depot_tools`, `gclient`, Linux GN/Ninja, the pinned Chromium revision, viewer output, WSLg display variables, and `/dev/dxg`.

## Build Stock Baseline

```bash
./scripts/build_chromium.sh \
  --out-dir out/ReleaseBaseline \
  --args-file build/gn_args/linux/baseline_content_shell.gn \
  --target content_shell
```

Expected outputs:

- `src/out/ReleaseBaseline/content_shell`
- `src/out/ReleaseBaseline/args.gn`
- `src/out/ReleaseBaseline/three_browser_build_provenance.json`

Stock baseline builds require an unpatched Chromium `src` tree. The Linux builder refuses baseline-profile builds when any viewer patch series entry is already applied.

## Build Fork

```bash
./scripts/build_viewer_fork.sh \
  --apply-patch \
  --out-dir out/ReleaseViewerDefault \
  --args-file build/gn_args/linux/fork_safe_content_shell.gn \
  --target content_shell
```

Expected outputs:

- `src/out/ReleaseViewerDefault/content_shell`
- `src/out/ReleaseViewerDefault/args.gn`
- `src/out/ReleaseViewerDefault/three_browser_build_provenance.json`

The WSL profiles do not apply the old host-specific clang workaround patch. That patch remains archived for the previous Windows host only.

## Stage Packages

```bash
./scripts/stage_viewer_package.sh --chromium-out-dir ./src/out/ReleaseBaseline --package-dir ./benchmarks/packages/baseline-content-shell --clean
./scripts/stage_viewer_package.sh --chromium-out-dir ./src/out/ReleaseViewerDefault --package-dir ./benchmarks/packages/viewer-default --clean
```

Each Linux package contains `content_shell`, shared libraries/resources, `viewer/index.html`, and `run_viewer.sh`.

## Official WSL Evidence

The first supported WSL target is WebGL2:

```bash
./scripts/run_official_comparison.sh \
  --baseline-browser ./src/out/ReleaseBaseline/content_shell \
  --fork-browser ./src/out/ReleaseViewerDefault/content_shell \
  --baseline-package-dir ./benchmarks/packages/baseline-content-shell \
  --fork-package-dir ./benchmarks/packages/viewer-default \
  --renderer webgl2
```

Outputs:

- `benchmarks/reports/official-comparison-manifest.json`
- `benchmarks/reports/official-webgl2-comparison.md`
- `benchmarks/raw/*-webgl2.json`

The benchmark runner rejects software renderers such as SwiftShader and llvmpipe unless a diagnostic run explicitly opts out of retained evidence rules.

## Final Gate

```bash
./scripts/audit_artifacts.sh --fail-on-incomplete --output ./docs/prompt_to_artifact_checklist.md
```

Archived platform artifacts do not satisfy WSL gates. Rebuild and rerun evidence on WSL before making Linux performance claims.

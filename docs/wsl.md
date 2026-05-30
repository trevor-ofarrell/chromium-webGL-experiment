# WSL Port

This repository is Linux/WSL-primary for new builds. Use a fresh Ubuntu 22.04 WSL2 checkout in the Linux filesystem:

```bash
mkdir -p ~/code
cd ~/code
git clone <repo-url> three-browser
cd three-browser
./scripts/bootstrap_wsl.sh
```

Do not build from `/mnt/c`, `/mnt/d`, or another mounted Windows path. Chromium builds do a large amount of small-file I/O, and the Windows mount path is materially slower and more fragile than the WSL ext4 filesystem.

## What Not To Copy

When moving from the old Windows tree, copy Git history or clone fresh. Do not copy generated or host-specific directories:

- `src/`
- `tools/depot_tools/`
- `.cipd/`
- `viewer/node_modules/`
- `viewer/dist/`
- `benchmarks/tmp/`
- `benchmarks/packages/`
- `benchmarks/traces/`

Windows benchmark results remain historical evidence only. WSL evidence must be rebuilt from the pinned Chromium revision and must report Linux/WSL platform metadata.

## Primary WSL Commands

```bash
./scripts/check_prereqs.sh
./scripts/build_chromium.sh --out-dir out/ReleaseBaseline --args-file build/gn_args/linux/baseline_content_shell.gn --target content_shell
./scripts/build_viewer_fork.sh --apply-patch --out-dir out/ReleaseViewerDefault --args-file build/gn_args/linux/fork_safe_content_shell.gn --target content_shell
./scripts/stage_viewer_package.sh --chromium-out-dir ./src/out/ReleaseBaseline --package-dir ./benchmarks/packages/baseline-content-shell --clean
./scripts/stage_viewer_package.sh --chromium-out-dir ./src/out/ReleaseViewerDefault --package-dir ./benchmarks/packages/viewer-default --clean
./scripts/run_official_comparison.sh --baseline-browser ./src/out/ReleaseBaseline/content_shell --fork-browser ./src/out/ReleaseViewerDefault/content_shell --renderer webgl2
./scripts/audit_artifacts.sh --fail-on-incomplete --output ./docs/prompt_to_artifact_checklist.md
```

The first supported WSL target is build plus hardware WebGL2 evidence. WebGPU and backend-specific trusted matrices are intentionally not promoted as WSL parity in this port.

## Host Expectations

- Ubuntu 22.04 under WSL2 is the pinned target; Ubuntu 24.04 is accepted by the checker for current-host validation.
- Repo path under `/home/<user>/...`.
- WSLg display environment available through `DISPLAY` or `WAYLAND_DISPLAY`.
- WSL GPU device available at `/dev/dxg`.
- Hardware renderer evidence from benchmark JSON. The runner rejects SwiftShader, llvmpipe, WARP, and other software renderers unless explicitly launched as a non-retained diagnostic.

The setup follows Chromium's Linux build flow, Microsoft's WSL filesystem guidance, and Microsoft's WSLg GPU/GUI app requirements.

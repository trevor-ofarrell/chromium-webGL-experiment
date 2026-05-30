# Three Browser

Experimental Chromium fork for a single-purpose Three.js/WebGL/WebGPU 3D viewer runtime.

This repository is being prepared for Linux/WSL-first development. New builds should use Ubuntu 22.04 on WSL2 from the Linux filesystem, for example `/home/<user>/code/three-browser`, not `/mnt/c`.

## WSL Build

Fresh setup:

```bash
./scripts/bootstrap_wsl.sh
```

Prerequisite check:

```bash
./scripts/check_prereqs.sh
./scripts/verify_prebuild.sh
```

Build stock `content_shell`:

```bash
./scripts/build_chromium.sh --out-dir out/ReleaseBaseline --args-file build/gn_args/linux/baseline_content_shell.gn --target content_shell
```

Build the patched viewer fork:

```bash
./scripts/build_viewer_fork.sh --apply-patch --out-dir out/ReleaseViewerDefault --args-file build/gn_args/linux/fork_safe_content_shell.gn --target content_shell
```

Stage Linux runtime packages:

```bash
./scripts/stage_viewer_package.sh --chromium-out-dir ./src/out/ReleaseBaseline --package-dir ./benchmarks/packages/baseline-content-shell --clean
./scripts/stage_viewer_package.sh --chromium-out-dir ./src/out/ReleaseViewerDefault --package-dir ./benchmarks/packages/viewer-default --clean
```

Run the first supported WSL evidence target, hardware WebGL2:

```bash
./scripts/run_official_comparison.sh --baseline-browser ./src/out/ReleaseBaseline/content_shell --fork-browser ./src/out/ReleaseViewerDefault/content_shell --renderer webgl2
```

Final WSL artifact audit:

```bash
./scripts/audit_artifacts.sh --fail-on-incomplete --output ./docs/prompt_to_artifact_checklist.md
```

## Migration Notes

See [docs/wsl.md](docs/wsl.md) for the WSL migration rules, excluded Windows artifacts, and host expectations.

The historical Windows PowerShell harness has moved to `scripts/windows-legacy/`; see [docs/windows-legacy/README.md](docs/windows-legacy/README.md). It remains useful for understanding older platform-specific evidence, but it is not the supported path for new WSL builds.

## Viewer Benchmark

The bundled viewer lives under `viewer/` and emits JSON with FPS, percentile frame times, CPU time, GPU time where supported, JS time, render submission time, draw calls, triangles, upload sizes, shader events, process RSS, package size, launch flags, GPU metadata, and stability counters.

Run a single Linux benchmark after building:

```bash
node ./scripts/run_benchmark.mjs --browser ./src/out/ReleaseViewerDefault/content_shell --variant fork-viewer-default --scene many-draw-calls --renderer webgl2 --duration 120 --warmup 20 --viewerMode --viewerTrustedContent --output ./benchmarks/raw/manual-many-draw-calls-webgl2.json
```

The WSL port intentionally starts with build plus hardware WebGL2 evidence. WebGPU and backend-specific trusted matrices require separate Linux-oriented validation before they can be treated as parity evidence.

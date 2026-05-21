# Three Browser

Experimental Chromium fork for a single-purpose Three.js/WebGL/WebGPU 3D viewer runtime.

The project builds stock Chromium `content_shell` and a patched viewer fork from the same Chromium revision, runs a bundled Three.js benchmark viewer, and writes machine-readable and human-readable performance evidence.

## Current Evidence Set

- Pin file: `.chromium_revision`
- Chromium revision: `3a94d90ec3c04556622c56944796dd76753e0581`
- Fork revision stamp: `3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-cca4b9171b07`
- Stock binary: `src/out/ReleaseBaseline/content_shell.exe`
- Fork binary: `src/out/ReleaseViewerDefault/content_shell.exe`
- Official manifest: `benchmarks/reports/official-comparison-manifest.json`
- Trusted matrix manifest: `benchmarks/reports/trusted-experiment-matrix-manifest.json`
- WebGL2 report: `benchmarks/reports/official-webgl2-comparison.md`
- WebGPU report: `benchmarks/reports/official-webgpu-comparison.md`
- Stability artifacts:
  - `benchmarks/raw/baseline-content-shell-long-stability-instancing-webgl2.json`
  - `benchmarks/raw/fork-viewer-default-long-stability-instancing-webgl2.json`

## Build

Prerequisites are checked with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_prereqs.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_prebuild.ps1
```

If Visual Studio lacks the C++ ATL component, use the elevated helper before building:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_vs_atl.ps1
```

Build stock `content_shell`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_chromium.ps1 -OutDir .\src\out\ReleaseBaseline -ArgsFile .\build\gn_args\baseline_content_shell.gn -Target content_shell
```

Build the fork:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_viewer_fork.ps1 -ApplyPatch -OutDir .\src\out\ReleaseViewerDefault -ArgsFile .\build\gn_args\fork_safe_content_shell.gn -Target content_shell
```

The higher-level reproducible workflow is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -RefreshRevision 3a94d90ec3c04556622c56944796dd76753e0581 -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming -RunTrustedExperimentMatrix -TrustedMatrixInProcessGpu -TrustedMatrixSingleProcess -TrustedMatrixAngleBackend d3d11 -TrustedMatrixReservedNoopGates -RunLongStability -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FinalGate
```

For a new evidence cycle, omit `-RefreshRevision` and keep `-RefreshChromiumPin` so the helper selects a fresh upstream Chromium revision before building. Installed browser smoke output is useful for harness development, but it is not the official same-revision Chromium baseline for this fork.

## Viewer Benchmark

The bundled viewer lives under `viewer/` and emits JSON with FPS, percentile frame times, CPU time, GPU time where supported, JS time, render submission time, draw calls, triangles, upload sizes, shader events, process RSS, package size, launch flags, GPU metadata, and stability counters.

Run a single benchmark:

```powershell
node .\scripts\run_benchmark.mjs --browser .\src\out\ReleaseViewerDefault\content_shell.exe --variant fork-viewer-default --scene many-draw-calls --renderer webgl2 --duration 120 --warmup 20 --viewerMode --viewerTrustedContent --output .\benchmarks\raw\manual-many-draw-calls-webgl2.json
```

Run official comparison:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_official_comparison.ps1 -BaselineBrowser .\src\out\ReleaseBaseline\content_shell.exe -ForkBrowser .\src\out\ReleaseViewerDefault\content_shell.exe -BaselineBuildArgs .\src\out\ReleaseBaseline\args.gn -ForkBuildArgs .\src\out\ReleaseViewerDefault\args.gn -BaselinePackageDir .\benchmarks\packages\baseline-content-shell -ForkPackageDir .\benchmarks\packages\viewer-default -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming
```

## Result Highlights

- WebGL2 fork default versus stock: package -130.3 MB, average startup -220 ms, average p99 -28.8 ms, average CPU frame -0.06 ms, average render submission -0.05 ms, average FPS -1.3%.
- WebGPU fork default versus stock: package -130.3 MB, average startup -12 ms, average RSS -15.3 MB, average FPS -24.6%, average p99 +135.9 ms.
- Trusted D3D11 WebGL2 experiment versus trusted default: average FPS +20.0%, p99 -34.6 ms, CPU -0.44 ms.
- One-hour WebGL2 stability passed for stock and fork with NVIDIA ANGLE D3D11, zero WebGL context loss, zero render errors, RSS delta under 128 MB, and zero renderer geometry/texture/program growth.

## Final Gate

Generate the prompt-to-artifact checklist:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_artifacts.ps1 -Output .\docs\prompt_to_artifact_checklist.md
```

Fail the shell on any incomplete row:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_artifacts.ps1 -FailOnIncomplete -Output .\docs\prompt_to_artifact_checklist.md
```

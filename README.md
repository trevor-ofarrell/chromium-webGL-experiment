# Three Browser

Experimental Chromium fork for a single-purpose Three.js/WebGL/WebGPU 3D viewer runtime.

The project builds stock Chromium `content_shell` and a patched viewer fork from the same Chromium revision, runs a bundled Three.js benchmark viewer, and writes machine-readable and human-readable performance evidence.

## Current Evidence Set

- Pin file: `.chromium_revision`
- Chromium revision: `3a94d90ec3c04556622c56944796dd76753e0581`
- Fork revision stamp: `3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-43dbf0b6871e`
- Stock binary: `src/out/ReleaseBaseline/content_shell.exe`
- Fork binary: `src/out/ReleaseViewerDefault/content_shell.exe`
- Official manifest: `benchmarks/reports/official-comparison-manifest.json`
- Trusted matrix manifest: `benchmarks/reports/trusted-experiment-matrix-manifest.json`
- Current candidate-analysis handoff: `benchmarks/reports/post-atl-current-candidate-analysis.json` must match the current official/trusted raw-input digest before targeted blocker planning is accepted.
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_chromium.ps1 -OutDir out\ReleaseBaseline -ArgsFile build\gn_args\baseline_content_shell.gn -Target content_shell
```

Stock baseline builds require an unpatched Chromium `src` tree. `scripts\build_chromium.ps1` rejects baseline-profile builds when any viewer patch series entry is already applied, so same-revision stock evidence cannot accidentally be collected from forked source.

Build the fork:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_viewer_fork.ps1 -ApplyPatch -OutDir out\ReleaseViewerDefault -ArgsFile build\gn_args\fork_safe_content_shell.gn -Target content_shell
```

`-ApplyPatch` applies the current Chromium patch series in order, including the minimal viewer entrypoint patch and the WebGPU queue trace-attribution / small-batch submit allocation skip / trusted flush-deferral / label-propagation skips / shader-module source and memory-accounting skips / canvas validation skip / canvas memory-accounting skip / copyExternalImage sRGB color-conversion setup skip / copyExternalImage sRGB color-space validation skip / copyExternalImage destination/source/copy-size validation skips / writeTexture layout-validation skip / use-counter skip / CPU fallback diagnostic patch.

The higher-level reproducible workflow is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -RefreshRevision 3a94d90ec3c04556622c56944796dd76753e0581 -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -AggressiveWebGl2RelaxedValidation -AggressiveWebGpuSourceFastPath -AggressiveWebGpuUploadFastPath -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming -RunTrustedExperimentMatrix -RunTrustedWebGpuDawnMatrix -RunTargetedBlockerExperiments -TrustedMatrixZeroCopy -TrustedMatrixWebGlCompositorExperiments -TrustedMatrixWebGpuChromiumFeatureExperiments -TrustedMatrixWebGpuUploadExperiments -TrustedMatrixInProcessGpu -TrustedMatrixSingleProcess -TrustedMatrixAngleBackend d3d11 -TrustedMatrixReservedNoopGates -RunLongStability -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FinalGate
```

For a new evidence cycle, omit `-RefreshRevision` and keep `-RefreshChromiumPin` so the helper selects a fresh upstream Chromium revision before building. Installed browser smoke output is useful for harness development, but it is not the official same-revision Chromium baseline for this fork.

The completion command runs the official WebGL2 aggressive profile with D3D11 plus `-AggressiveWebGl2RelaxedValidation`, while keeping that relaxed-validation profile out of WebGPU. It now also runs the official WebGPU aggressive profile with the source-backed WebGPU hot-path skips selected by `-AggressiveWebGpuSourceFastPath` and the CPU-fallback-rejected CanvasTexture upload skips selected by `-AggressiveWebGpuUploadFastPath`; reused suite results are rejected when their viewer/WebGPU flag metadata does not match. It also runs the WebGL2 trusted matrix and a separate WebGPU Dawn/browser-flag matrix. The WebGL2 pass includes `-TrustedMatrixWebGlCompositorExperiments` so the next run tests GPU-memory-buffer compositor resources and UI zero-copy both alone and paired with `-TrustedMatrixZeroCopy`. The WebGPU Dawn pass includes D3D11 adapter, delayed-flush, unmonitored-fence, DiscardView, CPU-upload-buffer, MapOnDefaultBuffers, skip-validation, disable-robustness, and D3D12 toggle probes. It also includes `-TrustedMatrixWebGpuChromiumFeatureExperiments` to test `RemoveGPULegacyIPC`, `WebGPUUseHLSL2021`, and their combination against the upload/submit-heavy WebGPU suite, plus `-TrustedMatrixWebGpuUploadExperiments` to test `IncreasedCmdBufferParseSlice`, the D3D backing upload path, Blink queue/submit flush deferral, the source-backed WebGPU canvas texture-validation skip row, the source-backed WebGPU canvas memory-accounting skip row, the source-backed copyExternalImage sRGB color-conversion setup skip row, the source-backed copyExternalImage sRGB color-space validation skip row, the source-backed copyExternalImage destination/source/copy-size validation skip rows, the combined copyExternalImage trusted fast-path row, the source-backed writeTexture layout-validation skip row, the source-backed WebGPU use-counter skip row, and the source-backed shader-module source-scan and memory-accounting skip rows. Before focused blocker iteration, the post-ATL helper now regenerates `post-atl-current-candidate-analysis.json` from the just-built official/trusted manifests, so `-RunTargetedBlockerExperiments` follows current same-revision evidence instead of stale historical analysis. `-FinalGate` refuses completion runs shorter than the documented `-Duration 120 -Warmup 20` window, requires WebGPU timestamp timing to stay disabled for stock and fork, and refuses targeted blocker complexity overrides that do not match the official suite. For focused standalone iteration after a comparison report, run `run_current_candidate_analysis.ps1` first, then use `run_blocker_experiments.ps1 -AnalyzeAfterRun -PlanSuitePromotionAfterTriage`. For a standalone WebGPU-only pass, use `-RunTrustedExperimentMatrix -TrustedMatrixRenderer webgpu -TrustedMatrixWebGpuDawnExperiments -TrustedMatrixWebGpuChromiumFeatureExperiments -TrustedMatrixWebGpuUploadExperiments` and omit the WebGL2-only `-TrustedMatrixZeroCopy` switch. Trusted matrix duration/warmup default to the official comparison settings, and renderer-specific trusted manifests are included by the final speedup gate only when they match the official revision and timing.

## Viewer Benchmark

The bundled viewer lives under `viewer/` and emits JSON with FPS, percentile frame times, CPU time, GPU time where supported, JS time, render submission time, draw calls, triangles, upload sizes, shader events, process RSS, package size, launch flags, GPU metadata, and stability counters.

Run a single benchmark:

```powershell
node .\scripts\run_benchmark.mjs --browser .\src\out\ReleaseViewerDefault\content_shell.exe --variant fork-viewer-default --scene many-draw-calls --renderer webgl2 --duration 120 --warmup 20 --viewerMode --viewerTrustedContent --output .\benchmarks\raw\manual-many-draw-calls-webgl2.json
```

Run official comparison:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_official_comparison.ps1 -BaselineBrowser .\src\out\ReleaseBaseline\content_shell.exe -ForkBrowser .\src\out\ReleaseViewerDefault\content_shell.exe -BaselineBuildArgs .\src\out\ReleaseBaseline\args.gn -ForkBuildArgs .\src\out\ReleaseViewerDefault\args.gn -BaselinePackageDir .\benchmarks\packages\baseline-content-shell -ForkPackageDir .\benchmarks\packages\viewer-default -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -AggressiveWebGl2RelaxedValidation -AggressiveWebGpuSourceFastPath -AggressiveWebGpuUploadFastPath -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming
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

# Iteration 001 Status

Date: 2026-05-16

Status: historical log. Current completion state is tracked in `docs/completion_audit.md`, and the generated requirement checklist is `docs/prompt_to_artifact_checklist.md`.

## Completed

- Cloned `depot_tools` into `tools/depot_tools`.
- Initial pinned upstream Chromium revision `1f78222a42e9e78c10d37637869509117303d23f`; active pin is now tracked in `.chromium_revision`.
- Started Chromium sync into `src/`; the sync timed out before completion and is resumable.
- Verified partial `src/BUILD.gn` references `//content/shell:content_shell`.
- Verified `src/content/shell/BUILD.gn` is present after the partial sync.
- Created the bundled Three.js benchmark viewer.
- Built the viewer with Three.js `0.184.0` and Vite `8.0.13`.
- Implemented the CDP benchmark runner and metric schema validation.
- Captured harness smoke results with installed Chrome for all WebGL2 scenes and one WebGPU scene.

## Blockers

- Historical iteration-001 blocker resolved: Chromium sync completed, `.gclient_entries` exists, and GN/Ninja are present.
- Current blocker: the checkout can generate GN metadata, but Chromium `content_shell` compile is blocked until Visual Studio ATL/MFC headers are installed. The failing include is `atldef.h`, provided by component `Microsoft.VisualStudio.Component.VC.ATLMFC`.
- Fork source patching still waits until the stock baseline binary is built, so same-revision stock evidence is not contaminated by viewer patch changes.

## Iteration 002 Update

- Chromium sync initially completed at `1f78222a42e9e78c10d37637869509117303d23f`; the active pin is now tracked in `.chromium_revision`.
- `.gclient_entries`, `gn.exe`, and `ninja.exe` are present.
- `gclient runhooks` succeeded after setting `DEPOT_TOOLS_WIN_TOOLCHAIN=0`.
- Installed Windows SDK Debugging Tools through winget; `C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbghelp.dll` is now present.
- `gn gen out\ReleaseBaseline` succeeds.
- `autoninja -C out\ReleaseBaseline content_shell` started and failed on missing ATL header:
  - failing file: `base/win/atl_throw.cc`
  - missing header: `atldef.h`
  - required VS component: `Microsoft.VisualStudio.Component.VC.ATLMFC`
- Attempting to add the VS component from the current unelevated shell failed. VS Installer log exit code: `5007`, "Commands with --quiet or --passive should be run elevated from the beginning."

## Resume Commands

```powershell
.\scripts\verify_prebuild.ps1 -AllowMissingAtl
```

From an elevated shell, install ATL/MFC and then resume:

```powershell
.\scripts\install_vs_atl.ps1
.\scripts\verify_prebuild.ps1
.\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -AggressiveWebGl2RelaxedValidation -AggressiveWebGpuSourceFastPath -AggressiveWebGpuUploadFastPath -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming -RunTrustedExperimentMatrix -RunTrustedWebGpuDawnMatrix -RunTargetedBlockerExperiments -TrustedMatrixZeroCopy -TrustedMatrixWebGlCompositorExperiments -TrustedMatrixWebGpuChromiumFeatureExperiments -TrustedMatrixWebGpuUploadExperiments -TrustedMatrixInProcessGpu -TrustedMatrixSingleProcess -TrustedMatrixAngleBackend d3d11 -TrustedMatrixReservedNoopGates -RunLongStability -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FinalGate
```

## Iteration 003 Update

- Benchmark metric schema now validates 37 required fields plus renderer/scene names, numeric sanity, optional timing/stability fields, frame-time arrays, JS frame time, render submission time, compositor/presentation latency placeholders, process-tree RSS, executable size, viewer bundle size, and optional package size.
- Refreshed installed-Chrome smoke artifacts with corrected metadata:
  - `benchmarks/reports/smoke-installed-chrome-v6-benchmark-summary.md`
  - `benchmarks/raw/smoke-installed-chrome-v6-*-webgl2.json`
  - `benchmarks/raw/smoke-installed-chrome-v6-instancing-webgpu.json`
- Added `scripts/run_smoke_tests.mjs` for runtime feature smoke coverage and validated it against installed Chrome in `benchmarks/raw/smoke-installed-chrome-v5-runtime-smoke.json`.
- Added `scripts/run_long_stability.ps1` and validated the wrapper with a short installed-Chrome run in `benchmarks/raw/smoke-installed-chrome-v6-short-stability-instancing-webgl2.json`.
- These smoke results are harness validation only. Same-revision stock/fork comparisons remain blocked until the baseline Chromium build completes.

## Iteration 004 Update

- Added graphics-loss instrumentation to the viewer benchmark output for WebGL context loss/restoration, WebGPU device loss, and render exceptions.
- Updated runtime smoke coverage so `benchmarks/raw/smoke-installed-chrome-v11-stability-smoke.json` validates WebGL context-loss event delivery, WebGPU device-loss signal delivery, and the existing runtime smoke cases.
- Captured `benchmarks/raw/smoke-installed-chrome-v11-stability-fields-many-draw-calls-webgl2.json`, which validates the required benchmark schema and records zero graphics-loss events on the normal benchmark path.
- Same-revision stock/fork stability remains blocked until the ATL/MFC build prerequisite is installed and Chromium binaries exist.

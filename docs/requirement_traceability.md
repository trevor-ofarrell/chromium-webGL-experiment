# Requirement Traceability

Date: 2026-05-21

| Requirement | Evidence |
| --- | --- |
| Start from current Chromium source | `.chromium_revision`, `benchmarks/reports/chromium-pin-refresh.json`, `src` HEAD at `3a94d90ec3c04556622c56944796dd76753e0581` |
| Preserve V8 and enough Blink for Three.js | Runtime smoke, viewer source, official WebGL2/WebGPU scene suites |
| Preserve Canvas, WebGL2, WebGPU, GPU acceleration | `fork-viewer-default-runtime-smoke.json`, official scene suites, GPU metadata in raw JSON |
| Avoid software rendering | Primary launchers use `--disable-software-rasterizer`; validators reject SwiftShader/WARP/llvmpipe/software-rendered metadata |
| Launch directly into bundled viewer | Viewer patch, `--viewer-app-url`, packaged viewer, fork runtime smoke |
| Remove visible browser chrome | Viewer patch hides content-shell toolbar in viewer mode |
| Block arbitrary browser navigation | `fork-viewer-default-navigation-lock.json`, `fork-viewer-default-file-navigation-lock.json` |
| Include real Three.js stress scenes | Seven-scene suite in `viewer/src/scenes.js`; official reports include all scene names |
| Compare stock, fork default, and trusted aggressive modes | `official-comparison-manifest.json`, official WebGL2/WebGPU reports, trusted matrix manifest |
| Collect required metrics | `scripts/validate_metrics.mjs`, raw benchmark JSON, official reports |
| Machine-readable JSON and human-readable reports | `benchmarks/raw/*.json`, `benchmarks/reports/*.md`, manifest hashes |
| Document removed/disabled subsystems | `docs/removed_subsystems.md` |
| Document optimization outcomes | `docs/optimization_log.md` |
| Gate unsafe optimizations | `docs/trusted_content_flags.md`, trusted flags in patch, trusted matrix evidence |
| One-hour stability | Stock and fork long-stability JSON artifacts |
| GPU/context/device loss behavior | `docs/stability_behavior.md`, stability fields in JSON |
| Rebase strategy | `docs/rebase_strategy.md`, patch notes, source investigation map |
| Prompt-to-artifact audit | `scripts/audit_artifacts.ps1`, `docs/prompt_to_artifact_checklist.md` |

## Benchmark Artifacts

The stock and fork benchmark artifacts are tied to the same Chromium revision through the official manifest, GN args hashes, expected browser paths, and raw JSON metadata.

- Official manifest: `benchmarks/reports/official-comparison-manifest.json`
- Trusted matrix manifest: `benchmarks/reports/trusted-experiment-matrix-manifest.json`
- WebGL2 report: `benchmarks/reports/official-webgl2-comparison.md`
- WebGPU report: `benchmarks/reports/official-webgpu-comparison.md`
- Trusted report: `benchmarks/reports/trusted-experiment-matrix-webgl2-comparison.md`

## Reproduction Commands

Build:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_chromium.ps1 -OutDir .\src\out\ReleaseBaseline -ArgsFile .\build\gn_args\baseline_content_shell.gn -Target content_shell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_viewer_fork.ps1 -ApplyPatch -OutDir .\src\out\ReleaseViewerDefault -ArgsFile .\build\gn_args\fork_safe_content_shell.gn -Target content_shell
```

Official evidence:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_official_comparison.ps1 -BaselineBrowser .\src\out\ReleaseBaseline\content_shell.exe -ForkBrowser .\src\out\ReleaseViewerDefault\content_shell.exe -BaselineBuildArgs .\src\out\ReleaseBaseline\args.gn -ForkBuildArgs .\src\out\ReleaseViewerDefault\args.gn -BaselinePackageDir .\benchmarks\packages\baseline-content-shell -ForkPackageDir .\benchmarks\packages\viewer-default -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming
```

Full evidence pipeline:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -RefreshRevision 3a94d90ec3c04556622c56944796dd76753e0581 -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming -RunTrustedExperimentMatrix -TrustedMatrixInProcessGpu -TrustedMatrixSingleProcess -TrustedMatrixAngleBackend d3d11 -TrustedMatrixReservedNoopGates -RunLongStability -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FinalGate
```

Final audit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_artifacts.ps1 -FailOnIncomplete -Output .\docs\prompt_to_artifact_checklist.md
```

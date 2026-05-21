# Build Guide

This guide reproduces the stock Chromium baseline and the patched Three.js viewer fork for the current evidence set.

## Revision And Profiles

- Chromium revision: `3a94d90ec3c04556622c56944796dd76753e0581`
- Fork revision stamp: `3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-cca4b9171b07`
- Stock GN args: `build/gn_args/baseline_content_shell.gn`
- Fork GN args: `build/gn_args/fork_safe_content_shell.gn`
- Trusted experiment GN args: `build/gn_args/fork_trusted_aggressive.gn`

The generated stock and fork `args.gn` files in `src/out/ReleaseBaseline` and `src/out/ReleaseViewerDefault` hash to the checked-in profile template used by the official benchmark evidence.

## Prerequisites

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_prereqs.ps1
```

The checker verifies depot_tools, `gclient`, GN, Ninja, Visual Studio Build Tools, the Visual C++ ATL component, Windows SDK debugger tools, Chromium revision, viewer build output, and current Windows Code Integrity state for Chromium Rust host-tool DLL loading.

The required Visual Studio component is `Microsoft.VisualStudio.Component.VC.ATLMFC`. If the checker reports that the component is absent, install it from an elevated PowerShell session with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_vs_atl.ps1
```

The environment manifest is written by:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_prebuild.ps1
```

Output:

- `benchmarks/reports/prebuild-environment.json`

## Build Stock Baseline

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_chromium.ps1 -OutDir .\src\out\ReleaseBaseline -ArgsFile .\build\gn_args\baseline_content_shell.gn -Target content_shell
```

Expected outputs:

- `src/out/ReleaseBaseline/content_shell.exe`
- `src/out/ReleaseBaseline/args.gn`
- `src/out/ReleaseBaseline/three_browser_build_provenance.json`

## Build Fork

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_viewer_fork.ps1 -ApplyPatch -OutDir .\src\out\ReleaseViewerDefault -ArgsFile .\build\gn_args\fork_safe_content_shell.gn -Target content_shell
```

Expected outputs:

- `src/out/ReleaseViewerDefault/content_shell.exe`
- `src/out/ReleaseViewerDefault/args.gn`
- `src/out/ReleaseViewerDefault/three_browser_build_provenance.json`

The build provenance JSON records Chromium revision, target hash, generated GN args hash, source GN args hash, and viewer-patch state. Skipped build resumes must validate this receipt before benchmark evidence is reused.

## Stage Packages

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stage_viewer_package.ps1 -ChromiumOutDir .\src\out\ReleaseBaseline -PackageDir .\benchmarks\packages\baseline-content-shell -Clean
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stage_viewer_package.ps1 -ChromiumOutDir .\src\out\ReleaseViewerDefault -PackageDir .\benchmarks\packages\viewer-default -Clean
```

Expected package roots:

- `benchmarks/packages/baseline-content-shell`
- `benchmarks/packages/viewer-default`

Each package contains `content_shell.exe`, runtime DLL/assets, `viewer/index.html`, and `run_viewer.ps1`. Package metadata is validated in official and trusted manifests.

## Complete Evidence Run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -RefreshRevision 3a94d90ec3c04556622c56944796dd76753e0581 -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming -RunTrustedExperimentMatrix -TrustedMatrixInProcessGpu -TrustedMatrixSingleProcess -TrustedMatrixAngleBackend d3d11 -TrustedMatrixReservedNoopGates -RunLongStability -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FinalGate
```

The command sequence invokes `refresh_chromium_pin.ps1`, verifies prerequisites, builds or validates stock and fork outputs, stages packages, runs official WebGL2/WebGPU comparisons, runs trace capture, runs the trusted WebGL2 experiment matrix, runs one-hour stock/fork stability, and executes the final artifact audit.

Use `-BuildJobs <n>` to reduce local compile parallelism on unstable hosts. This changes only build scheduling; GN args and benchmark metadata remain unchanged.

## Validation Commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_artifacts.ps1 -FailOnIncomplete -Output .\docs\prompt_to_artifact_checklist.md
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_gn_args_profiles.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_binary_audit_rows.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_post_atl_pipeline_dry_run.ps1
```

The final checklist maps build, runtime, benchmark, optimization, stability, and documentation requirements to concrete artifacts.

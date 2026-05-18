# Baseline Build Status

Date: 2026-05-18

## Target

- Chromium revision: see `.chromium_revision`
- GN output dir: `src/out/ReleaseBaseline`
- Target: `content_shell`
- GN args file: `build/gn_args/baseline_content_shell.gn`

## Completed

- `gclient sync --no-history --revision src@<contents of .chromium_revision>`
- `gclient runhooks` with `DEPOT_TOOLS_WIN_TOOLCHAIN=0`
- Windows SDK Debugging Tools installed; `Debuggers/x64/dbghelp.dll` exists.
- `gn gen out\ReleaseBaseline` succeeds.
- `gn gen out\ReleaseViewerDefault` succeeds.
- `gn gen out\ReleaseViewerTrustedAggressive` succeeds.

## Current Blocker

`autoninja -C out\ReleaseBaseline content_shell` fails compiling `base/win/atl_throw.cc`:

```text
base/win/atl_throw.h(35,10): fatal error: 'atldef.h' file not found
```

The local Visual Studio Build Tools installation lacks ATL/MFC headers. The required component is:

```text
Microsoft.VisualStudio.Component.VC.ATLMFC
```

Attempting a quiet VS Installer modify from the current shell failed because the process is not elevated. Relevant installer log message:

```text
Exit Code: 5007
Commands with --quiet or --passive should be run elevated from the beginning.
```

## Resume

Run from an elevated shell:

```powershell
.\scripts\install_vs_atl.ps1
```

Then resume:

```powershell
.\scripts\verify_prebuild.ps1
.\scripts\build_chromium.ps1 -OutDir out\ReleaseBaseline -Target content_shell
```

Or run the full completion-oriented post-ATL build/benchmark pipeline:

```powershell
.\scripts\run_post_atl_pipeline.ps1 `
  -RefreshChromiumPin `
  -IncludeWebGPU `
  -IncludeAggressiveGpu `
  -AggressiveAngleBackend d3d11 `
  -CaptureTrace `
  -RunTrustedExperimentMatrix `
  -TrustedMatrixInProcessGpu `
  -TrustedMatrixSingleProcess `
  -TrustedMatrixAngleBackend d3d11 `
  -TrustedMatrixReservedNoopGates `
  -RunLongStability `
  -MaxRssDeltaMb 128 `
  -MaxRendererResourceDelta 0 `
  -FinalGate
```

This is the same handoff shape used by `README.md`, `docs/build.md`, and the generated artifact audit. It refreshes the Chromium pin before stock/fork evidence, stages stock and fork packages, runs official WebGL2/WebGPU comparisons, captures traces, runs the trusted-content experiment matrix, runs one-hour stock/fork stability loops, and finishes with the strict artifact gate.

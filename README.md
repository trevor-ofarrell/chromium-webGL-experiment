# Three Browser

Experimental Chromium fork workspace for a single-purpose Three.js/WebGL/WebGPU 3D viewer runtime.

Current pinned upstream Chromium revision is stored in `.chromium_revision`.

This repository is the orchestration layer around a Chromium checkout in `src/`. The checkout itself is intentionally ignored because it is very large and should be reproduced with depot_tools.

Primary paths:

- `viewer/` - bundled Three.js benchmark viewer app.
- `scripts/` - Chromium bootstrap/build helpers and benchmark runner.
- `docs/` - architecture, build, benchmarking, optimization, and rebase notes.
- `chromium_patches/` - fork patch notes and generated patch staging area.
- `benchmarks/` - machine-readable results and human-readable reports.

Start with the prebuild verifier:

```powershell
.\scripts\bootstrap_chromium.ps1
cd viewer
npm install
npm run build
cd ..
.\scripts\verify_prebuild.ps1
```

To refresh the pin to the currently observed Chromium `origin HEAD`, sync hooks, regenerate GN metadata, rewrite the prebuild environment manifest, and restamp the source-investigation map after validating it:

```powershell
.\scripts\refresh_chromium_pin.ps1
```

If the verifier reports missing ATL/MFC headers, run this from elevated PowerShell:

```powershell
cd "C:\Users\trevo\code\three-browser"
.\scripts\install_vs_atl.ps1
.\scripts\verify_prebuild.ps1
```

The ATL installer script verifies both the `atldef.h` header under the Visual Studio Build Tools MSVC tree and the `vswhere -requires Microsoft.VisualStudio.Component.VC.ATLMFC` component registration before it prints the post-install pipeline.

After ATL/MFC is installed, the completion-oriented build and benchmark handoff is:

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

Use `.\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -DryRun` to inspect the command graph without building or refreshing the checkout.

Current workspace status:

- `depot_tools` is installed in `tools/depot_tools`.
- Chromium sync and hooks have completed at the pinned revision. The prebuild environment manifest records whether that pin still matches the observed upstream `origin HEAD`; the post-ATL pipeline refreshes the pin again before final stock/fork builds when `-RefreshChromiumPin` is used.
- `gn gen` succeeds for `out\ReleaseBaseline`, `out\ReleaseViewerDefault`, and `out\ReleaseViewerTrustedAggressive`; their generated `args.gn` files match the checked-in GN arg templates.
- Baseline `content_shell` compile is blocked in the current shell by a missing Visual Studio ATL/MFC component (`atldef.h`). Run `.\scripts\check_prereqs.ps1` to verify host prerequisites.
- The deterministic viewer builds successfully with Three.js `0.184.0`.
- Harness smoke results using installed Chrome are in `benchmarks/raw/` and summarized under `benchmarks/reports/`. These are not the official same-revision Chromium baseline.
- `.\scripts\verify_prebuild.ps1 -AllowMissingAtl` passes all non-build checks and writes `benchmarks/reports/prebuild-environment.json`.
- `docs/prompt_to_artifact_checklist.md` is the current prompt-to-artifact audit. It intentionally remains incomplete until the stock/fork binaries, official benchmark reports, trusted experiment matrix, and one-hour stability results exist.

# Build

## Prerequisites

Windows primary target:

- Visual Studio 2022 with Desktop development with C++ workload.
- Visual Studio 2022 Build Tools component `Microsoft.VisualStudio.Component.VC.ATLMFC` or equivalent ATL headers. Chromium's Windows `base` target includes `<atldef.h>`.
- Windows 10/11 SDK compatible with current Chromium.
- Windows SDK 10.0.26100 Debugging Tools. Chromium's toolchain setup expects `C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbghelp.dll`.
- Git.
- Python 3.
- Node.js 22 or newer for the benchmark viewer and runner.
- At least several hundred GB free disk space for Chromium source, build outputs, and symbols.

## Bootstrap Chromium

From repository root:

```powershell
.\scripts\bootstrap_chromium.ps1
```

This uses local `tools/depot_tools` when present or clones it, then syncs Chromium into `src/` at the revision pinned in `.chromium_revision`.
On Windows, the script sets `DEPOT_TOOLS_WIN_TOOLCHAIN=0` by default so Chromium uses the locally installed Visual Studio Build Tools instead of the authenticated Google Storage toolchain bundle. If `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` exists, the scripts also set `vs2022_install` to that path for Chromium's Visual Studio detection.

If ATL is missing, run this from an elevated shell:

```powershell
.\scripts\install_vs_atl.ps1
```

That script installs Visual Studio component `Microsoft.VisualStudio.Component.VC.ATLMFC` into the detected Build Tools path, then verifies both `atldef.h` under `VC\Tools\MSVC` and the `vswhere -requires Microsoft.VisualStudio.Component.VC.ATLMFC` component registration before printing the next commands. The next verification step is:

```powershell
.\scripts\verify_prebuild.ps1
```

Current pinned revision is stored in `.chromium_revision`.

To refresh the pin to the currently observed Chromium `origin HEAD`, sync dependencies/hooks, regenerate the three GN metadata profiles, rewrite `benchmarks/reports/prebuild-environment.json`, verify the viewer patch still applies, and restamp `docs/source_investigation.md` only after the documented paths and sentinel symbols validate against the refreshed checkout:

```powershell
.\scripts\refresh_chromium_pin.ps1
```

Use `-DryRun` to inspect the refresh sequence without mutating `.chromium_revision`, the Chromium checkout, the pin-refresh manifest, or the source-investigation document.

## Build Baseline Content Shell

```powershell
.\scripts\build_chromium.ps1 -OutDir out\ReleaseBaseline -Target content_shell
```

The script generates `src/out/ReleaseBaseline/args.gn` from `build/gn_args/baseline_content_shell.gn` unless an args file already exists.
If an existing generated `args.gn` differs from the checked-in args file, the build script stops instead of silently using stale build settings. Pass `-OverwriteArgs` only when you intentionally want to refresh the generated output args from the checked-in template.
The build scripts run `check_prereqs.ps1` before mutating build outputs or applying the fork patch, so missing ATL/MFC fails fast.
For GN metadata only, use `-GenOnly`; with `-SkipPrereqCheck` this can refresh `args.gn` and `build.ninja` for audit purposes without invoking `autoninja` or applying the viewer patch. It is not build evidence and does not produce a binary.

The trusted/aggressive GN profile is metadata for experimental build arguments only; unsafe behavior is still controlled by explicit trusted-content runtime flags. To generate its `args.gn` without compiling:

```powershell
.\scripts\build_chromium.ps1 -OutDir out\ReleaseViewerTrustedAggressive -Target content_shell -ArgsFile build\gn_args\fork_trusted_aggressive.gn -SkipPrereqCheck -GenOnly
```

Before building, `verify_prebuild.ps1` checks host prerequisites, viewer bundle output, script syntax, benchmark artifact schemas, metric schema consistency across runner/validator/audit/docs, viewer patch trusted-content gating, viewer patch navigation-lock structure, viewer runtime API surface, runtime smoke coverage, smoke detail validation, optimization tracking coverage, ATL remediation handoff, prebuild environment manifest coverage including non-loopback IPv4 state for external navigation smoke, GN generation-only behavior, post-ATL dry-run orchestration, the final artifact-audit gate, official/trusted dry-run manifest structure, official manifest runtime, trace, suite-validation setting, and exact-suite semantic evidence, trusted manifest flag, suite-validation setting, and exact-suite semantic evidence, suite-level and report-level software-renderer rejection, and whether the viewer patch either applies cleanly or is already applied:

```powershell
.\scripts\verify_prebuild.ps1
```

Use `-AllowMissingAtl` before the ATL/MFC component is installed to continue the non-build checks. That allowance is intentionally narrow: after `prebuild-environment.json` is written, `verify_prebuild.ps1` permits only the `visual_studio_atl` and `visual_studio_atl_component` checks to fail under `-AllowMissingAtl`; any other failing manifest check stops the verifier. The dry-run orchestration check verifies that `run_post_atl_pipeline.ps1 -DryRun` carries official comparison, trusted experiment matrix, long-stability, final-audit options, and the patched-source baseline-build guard through to the nested workflows without executing build steps or mutating the Chromium checkout. The final-gate check verifies that `audit_artifacts.ps1 -FailOnIncomplete` rejects the current incomplete artifact set.

The verifier writes a machine-readable host/build snapshot to:

```text
benchmarks/reports/prebuild-environment.json
```

You can regenerate only that snapshot with:

```powershell
.\scripts\write_environment_manifest.ps1
```

The manifest records the pinned Chromium revision, current `src` status, observed upstream `origin HEAD` revision and whether it matched the pin when checked, Visual Studio/ATL state, tool paths, viewer patch state, non-loopback IPv4 addresses for external navigation-lock smoke, GN arg hashes, expected stock/fork binary paths, and Siso failed-target evidence from stock/fork output directories when a Chromium build has failed. Build-failure entries include log and GN-output timestamps, plus freshness booleans so an old failure captured before a later `gn gen` is reported as stale instead of being treated as the latest build attempt. The upstream HEAD probe is diagnostic because Chromium can move during long build and benchmark runs; `scripts\refresh_chromium_pin.ps1` also writes `benchmarks\reports\chromium-pin-refresh.json`, which records when `.chromium_revision` was selected from upstream HEAD so the final audit can distinguish real stale pins from normal upstream drift after a refresh. If the current upstream probe is unavailable, freshness remains pending until completed official same-revision evidence exists for the refreshed pin. Same-revision stock/fork evidence remains tied to `.chromium_revision`. `ok: false` is expected until ATL/MFC is installed and all host/runtime prerequisites pass.

After ATL/MFC is installed, the full resumable build/benchmark handoff is:

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

Use `-DryRun` to print the sequence without refreshing the checkout or building. `-RefreshChromiumPin` runs the reproducible pin-refresh helper before verification, build, and benchmark steps; add `-RefreshRevision <sha>` to target a specific Chromium revision instead of the observed upstream `origin HEAD`. The refresh helper also keeps the source-investigation verification marker aligned with the refreshed checkout, restoring the previous document text if the source-path regression fails. The completion-oriented command includes `-AggressiveAngleBackend d3d11` so the official aggressive WebGL2 and WebGPU suites record an explicit Windows ANGLE backend when WebGPU is included, and includes `-RunLongStability` for the required one-hour stock and fork stability loops. `run_post_atl_pipeline.ps1` and `run_long_stability.ps1` default to `-MaxRssDeltaMb 128` as the process-RSS growth threshold after warmup and `-MaxRendererResourceDelta 0` for the default stable scene. Omit long stability only for short build smoke runs. Use a different RSS or renderer-resource threshold only with documented rationale, and use `-FinalGate` once every required artifact is expected to exist.
`-RunTrustedExperimentMatrix` runs fork-only per-flag experiments after the official stock/fork comparison; the post-ATL pipeline defaults to a D3D11 ANGLE backend experiment on Windows and the completion command passes `-TrustedMatrixAngleBackend d3d11` explicitly. Use `-TrustedMatrixInProcessGpu`, `-TrustedMatrixSingleProcess`, additional `-TrustedMatrixAngleBackend` values, and `-TrustedMatrixReservedNoopGates` to choose additional risky variants. The trusted experiment runner requires `-BuildArgs`, validates the browser executable and GN args as non-empty files, validates each experiment suite before writing summaries, preflights a supplied `-PackageDir` before real benchmark execution, verifies the package executable matches the fork browser under test, and writes a completed manifest only after the selected result JSON and reports exist.
By default the post-ATL pipeline stages both `benchmarks\packages\baseline-content-shell` and `benchmarks\packages\viewer-default`, passes them as `-BaselinePackageDir` and `-ForkPackageDir` to the official comparison, and passes the matching package directory into stock and fork long-stability runs. The trusted experiment matrix uses only the fork package directory.
If `src` already has the viewer patch applied, `run_post_atl_pipeline.ps1` refuses to build the stock baseline unless `-SkipBaselineBuild` is supplied. Use that skip only when `src/out/ReleaseBaseline/content_shell.exe` was already built from an unmodified checkout; otherwise revert the viewer patch before producing stock baseline evidence. Non-dry resume skips are preflighted: `-SkipBaselineBuild` requires an existing non-empty stock binary and `args.gn`, `-SkipForkBuild` requires the matching fork binary and `args.gn`, and `-SkipPackage` requires both build skips plus existing staged package directories whose `content_shell.exe` hashes match the reused stock/fork browser executables when official comparison, trusted experiments, or long stability would consume them. `-RefreshChromiumPin` uses the refresh helper's clean-checkout guard, so omit it only when intentionally resuming from an already-patched checkout with existing unmodified baseline evidence.

## Build Viewer Fork

Build the unmodified baseline first. After baseline artifacts are captured, apply the draft viewer entrypoint patch and build the fork profile:

```powershell
.\scripts\build_viewer_fork.ps1 -ApplyPatch
```

This builds `src/out/ReleaseViewerDefault/content_shell.exe` from `build/gn_args/fork_safe_content_shell.gn`.
The patch application step is idempotent: if the viewer patch is already present in `src`, the script reports that state and continues to build. `verify_prebuild.ps1` accepts both clean pre-apply and already-applied patch states, so it can be used before the baseline build and again while iterating on the fork checkout.
Do not build or refresh `out\ReleaseBaseline` while the viewer patch is applied. That output is reserved for stock Chromium evidence and must come from an unmodified checkout at the pinned revision.

The audit also accepts both patch states. To regression-test that behavior without patching `src`, the focused test writes temporary `benchmarks/tmp` evidence and runs a patch-state-only audit:

```powershell
.\scripts\test_patch_state_audit.ps1
```

To regression-test the stale `args.gn` guard without starting a Chromium build:

```powershell
.\scripts\test_build_args_guard.ps1
```

To regression-test GN generation without compiling Chromium:

```powershell
.\scripts\test_gn_gen_only.ps1
```

Launch it directly into the bundled viewer:

```powershell
.\src\out\ReleaseViewerDefault\content_shell.exe `
  --viewer-app-url="$PWD\viewer\dist\index.html" `
  --viewer-block-external-navigation `
  --enable-unsafe-webgpu
```

Stage a runnable package directory after the fork build:

```powershell
.\scripts\stage_viewer_package.ps1 `
  -ChromiumOutDir .\src\out\ReleaseViewerDefault `
  -ViewerDist .\viewer\dist `
  -PackageDir .\benchmarks\packages\viewer-default `
  -Clean
```

The staging path can be regression-tested before the fork binary exists with synthetic inputs:

```powershell
.\scripts\test_stage_viewer_package.ps1
```

The post-ATL pipeline also stages `benchmarks\packages\baseline-content-shell` from `ReleaseBaseline` so stock runs have comparable `package_size_mb` evidence. The fork package includes `run_viewer.ps1`; it opens the bundled viewer directly by default, and can also launch a deterministic benchmark URL without hand-editing `--viewer-app-url`:

```powershell
.\benchmarks\packages\viewer-default\run_viewer.ps1 `
  -Benchmark `
  -Scene many-draw-calls `
  -Renderer webgl2 `
  -Duration 120 `
  -Warmup 20
```

The viewer writes the completed benchmark payload to the page console as a single line starting with `THREE_VIEWER_RESULT `. The draft fork patch forwards that marker line to stdout in viewer mode for packaged/manual launches, but `scripts/run_benchmark.mjs` remains the official path for collecting the payload into JSON and attaching browser, build, package, memory, and GPU metadata.

## Build Viewer App

```powershell
cd viewer
npm install
npm run build
cd ..
```

The output is `viewer/dist/`.

## Run Baseline Benchmark

```powershell
node .\scripts\run_benchmark.mjs `
  --browser .\src\out\ReleaseBaseline\content_shell.exe `
  --variant baseline-content-shell `
  --scene many-draw-calls `
  --renderer webgl2 `
  --duration 30 `
  --warmup 5 `
  --buildArgs .\src\out\ReleaseBaseline\args.gn `
  --output .\benchmarks\raw\baseline-many-draw-calls-webgl2.json
```

For the full WebGL2 suite:

```powershell
.\scripts\run_full_suite.ps1 `
  -Browser .\src\out\ReleaseBaseline\content_shell.exe `
  -Renderer webgl2 `
  -Duration 120 `
  -Warmup 20 `
  -Label baseline-content-shell `
  -BuildArgs .\src\out\ReleaseBaseline\args.gn
```

If a staged package directory exists, pass `-PackageDir` so `package_size_mb` is populated.

Use the same Chromium revision and GN args for stock and fork builds when comparing performance.

For the default fork profile, launch through the viewer entrypoint switches:

```powershell
.\scripts\run_full_suite.ps1 `
  -Browser .\src\out\ReleaseViewerDefault\content_shell.exe `
  -Renderer webgl2 `
  -Duration 120 `
  -Warmup 20 `
  -Label fork-viewer-default `
  -BuildArgs .\src\out\ReleaseViewerDefault\args.gn `
  -ViewerMode `
  -ViewerTrustedContent
```

For a single aggressive experiment, add only the flag under test, for example:

```powershell
.\scripts\run_full_suite.ps1 `
  -Browser .\src\out\ReleaseViewerDefault\content_shell.exe `
  -Renderer webgl2 `
  -Duration 120 `
  -Warmup 20 `
  -Label fork-viewer-aggressive-gpu-d3d11 `
  -BuildArgs .\src\out\ReleaseViewerDefault\args.gn `
  -ViewerMode `
  -ViewerTrustedContent `
  -ViewerAggressiveGpu `
  -ViewerForceAngleBackend d3d11
```

The complete post-build workflow is wrapped by:

```powershell
.\scripts\run_official_comparison.ps1 `
  -Duration 120 `
  -Warmup 20 `
  -IncludeWebGPU `
  -IncludeAggressiveGpu `
  -AggressiveAngleBackend d3d11 `
  -BaselinePackageDir .\benchmarks\packages\baseline-content-shell `
  -ForkPackageDir .\benchmarks\packages\viewer-default `
  -CaptureTrace `
  -TraceScene many-draw-calls `
  -TraceRenderer webgl2
```

In real official comparison runs, the workflow fails before benchmark execution if a supplied browser executable or GN args path is missing or empty. When `-BaselinePackageDir` or `-ForkPackageDir` is provided, it also fails before benchmark execution if the supplied package directory is missing, does not contain `content_shell.exe`, `viewer\index.html`, and `run_viewer.ps1`, or packages a `content_shell.exe` whose SHA-256 does not match the corresponding browser executable being benchmarked.

For fork benchmark suites, the workflow writes `fork_revision` as the pinned Chromium commit plus a short SHA-256 hash of `chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch`, for example:

```text
<chromium_revision>+viewerpatch-<patch_hash>
```

This keeps stock/fork comparisons tied to the exact draft patch content even while the checkout itself remains at the upstream Chromium revision.
The workflow also writes `benchmarks/reports/official-comparison-manifest.json`, which records the selected binaries, build args, fork revision, options, exact raw result files, reports, trace paths, and SHA-256 metadata for completed real runs. The final audit validates those exact manifest result files with `validate_benchmark_suite.mjs` before accepting the manifest as completed evidence. When `-RunTrustedExperimentMatrix` is enabled, `benchmarks/reports/trusted-experiment-matrix-manifest.json` records the fork-only experiment labels, flags, expected flag metadata, exact per-scene outputs, summary/comparison reports, and artifact hashes needed to audit each risky trusted-content flag independently. The final audit also validates each trusted experiment's exact result files before accepting the matrix manifest.

For a named resource-warmup experiment, add:

```powershell
-Precompile -PrerenderFrames 3
```

Before the binaries exist, inspect the command graph with:

```powershell
.\scripts\run_official_comparison.ps1 -Duration 1 -Warmup 1 -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -DryRun
```

To reproduce the minimal-target source inspection used for the fork base decision:

```powershell
.\scripts\inspect_chromium_target.ps1
```

The higher-level post-ATL pipeline can also be dry-run:

```powershell
.\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -Duration 1 -Warmup 1 -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -RunTrustedExperimentMatrix -TrustedMatrixInProcessGpu -TrustedMatrixSingleProcess -TrustedMatrixAngleBackend d3d11 -TrustedMatrixReservedNoopGates -RunLongStability -LongStabilityDuration 1 -LongStabilityWarmup 1 -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FinalGate -DryRun
```

Validate and summarize results:

```powershell
Get-ChildItem .\benchmarks\raw\baseline-content-shell-*.json | ForEach-Object {
  node .\scripts\validate_metrics.mjs $_.FullName
}

node .\scripts\summarize_results.mjs .\benchmarks\raw\baseline-content-shell-*.json `
  --output .\benchmarks\reports\baseline-content-shell-summary.md
```

## Trace Capture

Capture a short trace for GPU-path investigation:

```powershell
node .\scripts\run_trace_capture.mjs `
  --browser .\src\out\ReleaseBaseline\content_shell.exe `
  --scene many-draw-calls `
  --renderer webgl2 `
  --duration 10 `
  --warmup 2 `
  --output .\benchmarks\traces\baseline-many-draw-calls-webgl2-trace.json

node .\scripts\summarize_trace.mjs `
  .\benchmarks\traces\baseline-many-draw-calls-webgl2-trace.json `
  --output .\benchmarks\reports\baseline-many-draw-calls-webgl2-trace-summary.md
```

`run_trace_capture.mjs` defaults to `--startDelayMs 2000`, passed through to the viewer as a query parameter before renderer creation. `run_official_comparison.ps1` exposes this as `-TraceStartDelayMs`. Keep that delay for fork viewer-mode traces unless you are intentionally measuring the trace tooling itself; it gives CDP tracing time to attach before startup GPU work begins.

## Runtime Smoke Tests

```powershell
node .\scripts\run_smoke_tests.mjs `
  --browser .\src\out\ReleaseBaseline\content_shell.exe `
  --output .\benchmarks\raw\baseline-content-shell-runtime-smoke.json
```

For fork builds, add `--browser .\src\out\ReleaseViewerDefault\content_shell.exe`.

## Navigation Lock Tests

Run this only against a fork build that includes the viewer-entrypoint patch:

```powershell
node .\scripts\run_navigation_lock_tests.mjs `
  --browser .\src\out\ReleaseViewerDefault\content_shell.exe `
  --output .\benchmarks\raw\fork-viewer-default-navigation-lock.json

node .\scripts\run_file_navigation_lock_tests.mjs `
  --browser .\src\out\ReleaseViewerDefault\content_shell.exe `
  --output .\benchmarks\raw\fork-viewer-default-file-navigation-lock.json
```

The test launches the browser with `--viewer-app-url` and `--viewer-block-external-navigation`, then verifies startup URL loading, same-origin navigation, loopback cross-origin navigation blocking, external HTTP navigation blocking, and `window.open` blocking.
The file-mode test launches with a raw local path and verifies that navigation is confined to the viewer directory, not all local `file://` URLs.

## Long-Run Stability

The required stability gate is a one-hour benchmark loop:

```powershell
.\scripts\run_long_stability.ps1 `
  -Browser .\src\out\ReleaseViewerDefault\content_shell.exe `
  -Renderer webgl2 `
  -Scene instancing `
  -Duration 3600 `
  -Warmup 30 `
  -Label fork-viewer-default-long-stability `
  -BuildArgs .\src\out\ReleaseViewerDefault\args.gn `
  -ViewerMode `
  -ViewerTrustedContent `
  -MaxRssDeltaMb 128 `
  -MaxRendererResourceDelta 0
```

The default stability threshold is `process_rss_delta_mb <= 128` after warmup plus zero geometry, texture, and program growth for stable scenes such as `instancing`; these are also the default parameters in `run_long_stability.ps1`. Before launching the benchmark, `run_long_stability.ps1` verifies the browser executable and any supplied GN args path are non-empty files. When `-PackageDir` is supplied, it also verifies the staged package shape and package executable hash before launch, then requires positive `package_size_mb` in the result. Relax either threshold only for a deliberately growing resource-stress scene with documented rationale.

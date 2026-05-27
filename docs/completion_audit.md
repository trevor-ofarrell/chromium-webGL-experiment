# Completion Audit

Date: 2026-05-24

This document records the current completion state for the Chromium-derived
Three.js viewer runtime. It is intentionally fail-closed: historical smoke
artifacts and dry-run manifests are not treated as final evidence until the
same-revision stock and fork Chromium builds run successfully on this host.

## Deliverables

| Deliverable | Current evidence | Status |
| --- | --- | --- |
| Runnable Chromium-derived viewer binary | Expected path: `src/out/ReleaseViewerDefault/content_shell.exe` with `three_browser_build_provenance.json`; current Chromium rebuild is blocked by Windows application control rejecting generated Rust host tools under `src/out`. | blocked |
| Stock Chromium baseline binary | Expected path: `src/out/ReleaseBaseline/content_shell.exe` with `three_browser_build_provenance.json`; same blocker applies. | blocked |
| Patch series | `chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch`, `chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch`, `chromium_patches/README.md`, `chromium_patches/minimal_viewer_entrypoint.md`. | in progress |
| Bundled Three.js benchmark viewer | `viewer/src/*`, `viewer/dist/index.html`, and package staging scripts exist. | in progress |
| Machine-readable benchmark results | `benchmarks/raw/*.json` contains historical and diagnostic results; strict candidate analysis currently accepts zero retained performance candidates. | blocked |
| Human-readable reports | `benchmarks/reports/*` includes official, trusted-matrix, blocker, and candidate-analysis reports; current reports are diagnostic until rebuilt evidence exists. | blocked |
| Optimization decision table | `docs/optimization_log.md`. Entries marked `blocked` are not retained optimizations. | in progress |
| Removed-subsystem register | `docs/removed_subsystems.md`. | in progress |
| Stability behavior | `docs/stability_behavior.md`; one-hour stability artifacts must be regenerated after the rebuild blocker is cleared. | blocked |
| Reproduction guide | `README.md`, `docs/build.md`, `docs/benchmark_methodology.md`. | in progress |

## Build Completion

Build completion is blocked. The current handoff in `docs/build.md` records
`OSError: [WinError 4551] An Application Control policy has blocked this file`
while Chromium/Siso runs generated Rust host build scripts from
`src/out/.../win_clang_x64_for_rust_host_build_tools`.

Required before this section can move to complete:

- Re-run the post-ATL pipeline after the Windows application-control policy is
  adjusted or the build directory is otherwise allowed.
- Produce stock and fork `content_shell.exe` binaries from the same Chromium
  revision.
- Regenerate build provenance, package manifests, GN args hashes, and patch
  series hashes from the rebuilt checkout.

## Runtime Completion

Runtime completion is blocked by the missing rebuilt binaries. The source patch
still targets a direct `--viewer-app-url` launch, no browser chrome, local
viewer loading, external navigation refusal, WebGL2, WebGPU where available,
Canvas, `requestAnimationFrame`, local `fetch`, `performance.now`, texture
loading, shader material rendering, and basic input events.

These claims must be revalidated with rebuilt stock/fork binaries before they
can be used as final evidence.

## Performance Completion

Performance completion is not achieved. The latest strict candidate analysis
for the current patch state reports zero accepted candidates for the required
WebGL2 and WebGPU renderer gate. Historical results, installed-Chrome smokes,
short diagnostics, dry-run manifests, trace-instrumented runs, stale revision
artifacts, software-rendered results, and WebGPU device-loss-contaminated runs
must remain filtered out.

Required before any speed claim:

- Same-revision stock Chromium baseline, fork default, and fork trusted
  aggressive suites must run at the required duration, warmup, complexity, and
  GPU-timing mode.
- WebGL2 and WebGPU must each pass the required candidate gate with no material
  scene regression, dropped-frame regression, shader/pipeline-stall regression,
  software rendering, CPU texture fallback, or device loss.
- Results must be written to machine-readable JSON and human-readable reports.

## Stability Completion

Stability completion is blocked. One-hour stock and fork stability artifacts
must be regenerated from the rebuilt binaries and must satisfy the current
thresholds for crash behavior, WebGL context loss, WebGPU device loss, process
RSS growth, renderer geometry/texture/program growth, shader/program/texture
growth, and GPU restart behavior.

## Remaining Bottlenecks

- Windows application control currently blocks the Chromium rebuild needed for
  official evidence.
- WebGPU is not yet proven faster than stock Chromium; prior WebGPU losses were
  associated with driver/pipeline stalls, and at least one apparent aggressive
  win was contaminated by device loss.
- WebGL2 has plausible trusted fast paths through D3D11 and relaxed validation,
  but the retained speedup gate still needs rebuilt same-revision evidence.
- Direct GPU presentation and Blink module trimming remain reserved/no-op gates
  until implemented and measured.

## Final Gate

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_artifacts.ps1 -FailOnIncomplete -Output .\docs\prompt_to_artifact_checklist.md
```

The generated checklist is the prompt-to-artifact map for the objective. A
passing documentation structure test is not a performance claim; only a passing
final gate with rebuilt same-revision official evidence can close the project.

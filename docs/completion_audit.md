# Completion Audit

Date: 2026-05-24

This document records the current completion state for the Chromium-derived
Three.js viewer runtime. It is intentionally fail-closed: historical smoke
artifacts and dry-run manifests are not treated as final evidence until the
same-revision stock and fork Chromium builds run successfully on this host.

## Deliverables

| Deliverable | Current evidence | Status |
| --- | --- | --- |
| Runnable Chromium-derived viewer binary | `src/out/ReleaseViewerDefault/content_shell.exe` exists with current `three_browser_build_provenance.json` for Chromium `3a94d90ec3c04556622c56944796dd76753e0581` and fork stamp `viewerpatch-1e2ab6bffef9`. | in progress |
| Stock Chromium baseline binary | `src/out/ReleaseBaseline/content_shell.exe` exists with stock-source provenance for the same Chromium revision. | in progress |
| Patch series | `chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch`, `chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch`, `chromium_patches/README.md`, `chromium_patches/minimal_viewer_entrypoint.md`. | in progress |
| Bundled Three.js benchmark viewer | `viewer/src/*`, `viewer/dist/index.html`, and package staging scripts exist. | in progress |
| Machine-readable benchmark results | `benchmarks/raw/*.json` now includes post-policy alternating WebGPU paired evidence; strict candidate analysis still rejects retained WebGPU speed claims. | blocked |
| Human-readable reports | `benchmarks/reports/*` includes official, trusted-matrix, blocker, candidate-analysis, and alternating paired reports; final-duration reports are still pending. | in progress |
| Optimization decision table | `docs/optimization_log.md`. Entries marked `blocked` are not retained optimizations. | in progress |
| Removed-subsystem register | `docs/removed_subsystems.md`. | in progress |
| Stability behavior | `docs/stability_behavior.md`; one-hour stability artifacts must be regenerated after the rebuild blocker is cleared. | blocked |
| Reproduction guide | `README.md`, `docs/build.md`, `docs/benchmark_methodology.md`. | in progress |

## Build Completion

Build completion is no longer blocked by the earlier WDAC/Application Control
failure on this host. `scripts/check_prereqs.ps1` now reports ATL/MFC present and
no current Code Integrity block from the Chromium generated-file probe. Same-
revision stock and fork `content_shell.exe` binaries exist with build
provenance.

Required before this section can move to complete:

- Run the full post-ATL final gate at the documented final duration/warmup.
- Regenerate package manifests and final reports from that final-gate run.
- Confirm the final audit passes with `-FailOnIncomplete`.

## Runtime Completion

Runtime completion is partially revalidated with rebuilt stock/fork binaries.
The fork still targets a direct `--viewer-app-url` launch, no browser chrome,
local viewer loading, external navigation refusal, WebGL2, WebGPU where
available, Canvas, `requestAnimationFrame`, local `fetch`, `performance.now`,
texture loading, shader material rendering, and basic input events.

These claims still need the final-gate smoke/navigation/stability artifacts
before they can be marked complete.

## Performance Completion

Performance completion is not achieved. Current WebGL2 alternating evidence has
a retained-candidate shape in `benchmarks/reports/alt-colorspace-candidate-analysis.md`
at +2.99% average FPS with improved p99, CPU, and render-submission metrics.
WebGPU still has no retained candidate: the default alternating control improved
average FPS by +2.37% but failed the tail gate, the matched warmup run failed on
glTF dropped-frame-rate and CPU/submission regressions, and the full-duration
color-conversion confirmations improved average FPS/p99 but still failed on
glTF CPU/render-submission overhead. Later canvas-memory/color-conversion and
bind-group-layout/color-conversion probes improved focused blocker scenes, but
their confirmation or triage runs regressed average FPS, draw-call throughput,
texture p99, or instancing low-FPS metrics, so they are rejected or blocked.
The latest texture-streaming tail diagnostic shows the combined
bind-group-layout/color-conversion profile regressing p99 frame time far more
than CPU, JS, or render-submission p99, so the next WebGPU blocker is
texture-upload/presentation or driver frame-pacing attribution rather than more
JS/submission flag stacking. Viewer-side queue attribution confirms that the
current texture-streaming WebGPU path is `queue.copyExternalImageToTexture`
heavy; the source queue trace did not surface those events yet, so source trace
visibility itself remains a diagnostic gap. A source fix now forwards trusted
WebGPU viewer switches to renderer child processes, but the required fork
rebuild is blocked by disk space (`no space on device`, 4.09 GB free).
Historical results, installed-Chrome smokes, short diagnostics, dry-run
manifests, trace-instrumented runs, stale revision artifacts, software-rendered
results, and WebGPU device-loss-contaminated runs must remain filtered out.

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

- WebGPU is not yet proven faster than stock Chromium; color-conversion,
  warmup, BundleGroup, canvas-memory, bind-group-layout cache, and combined
  bind-group-layout/color-conversion probes still leave full-suite throughput,
  glTF CPU/submission, texture-tail, or capped-scene low-FPS regressions.
- Texture-streaming WebGPU tails need deeper GPU/upload/presentation
  attribution because the new per-frame CPU/JS/submission diagnostics do not
  explain the full p99 frame regression.
- Source-added WebGPU queue trace visibility needs repair or category
  adjustment before it can replace viewer-side queue instrumentation for
  CanvasTexture/copyExternal upload blockers.
- The fork must be rebuilt after the child-process switch-forwarding fix before
  previous source-flag WebGPU rows can be considered representative of active
  renderer-side flags.
- Stability artifacts still need final regeneration from the rebuilt packages
  under the current metric and artifact gates.
- The final artifact audit still needs to pass after WebGPU has a retained
  candidate and the stability suite is refreshed.
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

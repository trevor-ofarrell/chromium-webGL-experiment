# Completion Audit

Date: 2026-05-21

This document summarizes the concrete deliverables for the Chromium-derived Three.js viewer runtime.

## Deliverables

| Deliverable | Evidence |
| --- | --- |
| Runnable Chromium-derived viewer binary | `src/out/ReleaseViewerDefault/content_shell.exe` with `three_browser_build_provenance.json` |
| Stock Chromium baseline binary | `src/out/ReleaseBaseline/content_shell.exe` with `three_browser_build_provenance.json` |
| Patch series | `chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch`, `chromium_patches/README.md`, `chromium_patches/minimal_viewer_entrypoint.md` |
| Bundled Three.js benchmark viewer | `viewer/src/*`, `viewer/dist/index.html`, package copies under `benchmarks/packages/*/viewer` |
| Machine-readable benchmark results | `benchmarks/raw/*.json` |
| Human-readable reports | `benchmarks/reports/official-webgl2-comparison.md`, `benchmarks/reports/official-webgpu-comparison.md`, trusted matrix reports, trace summaries |
| Optimization decision table | `docs/optimization_log.md` |
| Removed-subsystem register | `docs/removed_subsystems.md` |
| Stability behavior | `docs/stability_behavior.md` plus one-hour JSON artifacts |
| Reproduction guide | `README.md`, `docs/build.md`, `docs/benchmark_methodology.md` |

## Build Completion

- Stock and fork `content_shell.exe` binaries exist under `src/out`.
- GN args are reproducible and hash-checked against checked-in profiles.
- Build provenance files bind binaries to Chromium revision, target hash, source GN args hash, generated GN args hash, and viewer-patch state.
- Staged packages exist for stock and fork, with package hashes recorded in manifests.

## Runtime Completion

- Fork runtime launches directly into the bundled viewer through `--viewer-app-url`.
- Browser chrome is suppressed in viewer mode.
- Runtime smoke validates WebGL2, WebGPU when requested, Canvas, `requestAnimationFrame`, local `fetch`, `performance.now`, texture loading, shader material render, and basic input events.
- Navigation smoke validates same-origin/file confinement and external navigation refusal.

## Performance Completion

- Official WebGL2 and WebGPU reports compare stock, fork default, and fork aggressive D3D11 profiles from the same Chromium revision.
- Reports include average FPS, low FPS, frame-time percentiles, CPU/JS/submission time, GPU timing where supported, draw calls, triangles, upload sizes, memory, startup, binary size, viewer size, and package size.
- Trusted WebGL2 matrix compares default, aggressive GPU, in-process GPU, single-process, D3D11, relaxed WebGL validation, Blink-disable reserved gate, and direct-presentation reserved gate.

## Stability Completion

- Stock one-hour WebGL2 `instancing` stability: `benchmarks/raw/baseline-content-shell-long-stability-instancing-webgl2.json`
- Fork one-hour WebGL2 `instancing` stability: `benchmarks/raw/fork-viewer-default-long-stability-instancing-webgl2.json`
- Both runs used NVIDIA ANGLE D3D11, recorded zero WebGL context loss, zero render errors, RSS delta under 128 MB, and zero renderer geometry/texture/program growth after warmup.

## Remaining Bottlenecks

- Default fork WebGPU is slower than stock in the current official suite, especially shader-heavy, postprocessing, and large-static cases.
- Default fork WebGL2 improves p99/startup/package size but does not improve average FPS.
- Process-collapse trusted modes are fast but too risky for default operation.
- WebGPU timestamp queries are unstable for stress timing on this host and remain disabled for official WebGPU runs.
- Direct GPU presentation and Blink module trimming need real source implementations before they can be useful.

## Final Gate

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_artifacts.ps1 -FailOnIncomplete -Output .\docs\prompt_to_artifact_checklist.md
```

The generated checklist is the prompt-to-artifact map for the objective.

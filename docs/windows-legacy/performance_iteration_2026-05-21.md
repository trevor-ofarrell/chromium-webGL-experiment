# Performance Iteration - 2026-05-21

Goal: improve WebGL2 and WebGPU performance versus same-revision stock Chromium evidence while rejecting invalid GPU/device-loss runs.

## Changes

- Viewer hot loop now uses `renderer.render(scene, camera)` after WebGPU renderer initialization instead of awaiting deprecated `renderer.renderAsync()`.
- Viewer frame loop now avoids an unconditional per-frame `async`/`await` path. `renderOnce` stays synchronous for normal WebGL2/WebGPU `renderer.render(...)` calls and only attaches a promise continuation if a scene-specific render path returns a thenable.
- Benchmark suite validation accepts a new `--rejectGpuInstability` gate.
- Strict official comparisons reject results with WebGPU device loss, WebGL context loss, or render errors.
- Official and trusted matrix runners now pass the GPU-instability rejection gate and record `reject_gpu_instability = true` in generated manifests.
- Low-level benchmark runs now derive checkout-built fork result metadata as `chromium_revision+viewerpatch-<patch-series hash>` when `--forkRevision` is not explicitly supplied, so strict comparisons reject stale or incomplete fork provenance instead of silently comparing Chromium-only revision stamps.
- The viewer and benchmark runner now support `textureUploadMode=canvas|data` for the texture-streaming scene. `canvas` remains the default and preserves the original CanvasTexture stress case; `data` uses deterministic `THREE.DataTexture` updates to exercise WebGPU `queue.writeTexture`/WebGL typed-array texture uploads without changing the rest of the scene.
- The viewer and benchmark/trace runners now support opt-in WebGPU queue attribution through `queueInstrumentation=1` / `--queueInstrumentation`. This wraps `renderer.backend.device.queue` methods in the viewer and records `writeBuffer`, `writeTexture`, `copyExternalImageToTexture`, `copyElementImageToTexture`, and `submit` counts/timing in JSON results.
- A draft Chromium source trace patch now instruments Blink WebGPU queue hot paths in `third_party/blink/renderer/modules/webgpu/gpu_queue.cc`. It also avoids the temporary heap array allocation for single-command-buffer and small-batch `GPUQueue.submit` paths up to four command buffers, and attributes the `CopyFromCanvasSourceImage` path so rebuilt traces can distinguish existing shared-image, static-mailbox, forced-readback, CPU-fallback, CPU readPixels, and rejected-fallback cases. It is captured as `chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch` and requires a rebuilt fork before trace evidence can use the new slices or benchmark evidence can prove the submit allocation change.

## Quick Local Evidence

These are short safe-window iteration checks, not replacement official 120s reports.

| Case | Baseline | Fork/experiment | Result |
| --- | ---: | ---: | --- |
| WebGL2 many-draw-calls | 86.19 FPS | 91.27 FPS with trusted D3D11 + relaxed WebGL validation | +5.9% FPS, p99 20.9 ms -> 14.2 ms, submit 10.02 ms -> 9.48 ms |
| WebGPU large-static | 143.76 FPS | 143.91 FPS with render-loop fix | tied FPS, submit 0.97 ms -> 0.85 ms, RSS -14.5 MB |
| WebGPU shader-heavy | 144.01 FPS | 144.00 FPS with render-loop fix | vsync-capped/tied, no device loss |
| WebGPU texture-streaming | 11.26 FPS | 10.21 FPS with trusted in-process GPU | still slower; memory improved 653.3 MB -> 593.7 MB |
| WebGPU many-draw-calls | 75.40 FPS | 77.86 FPS with trusted single-process | +3.3% FPS, p95 20.8 ms -> 14.0 ms, RSS 697.3 MB -> 391.4 MB |

## Extended Local Evidence

Additional 10s/3s short-suite checks were run after the validation gate was tightened. These are iteration evidence only; they are not official 120s completion evidence.

| Case | Result |
| --- | --- |
| WebGPU default trusted viewer suite | -0.33% average FPS versus stock content_shell, average p99 unchanged, average submit +0.20 ms. Not a speed win. |
| WebGPU trusted single-process suite | +0.41% average FPS, average p95 -1.06 ms, average RSS -322.9 MB, but average p99 +0.94 ms because texture-streaming p99 worsened. Candidate only; not enough for final retention without longer official evidence. |
| WebGPU trusted in-process GPU suite | -0.10% average FPS, average p99 flat, RSS -63.6 MB. Memory win only. |
| WebGPU single-process texture-streaming, 30s/5s | 9.7 -> 10.3 FPS (+6.2%), p95 131.8 -> 124.9 ms, but p99 187.4 -> 194.5 ms. Average improves, tail still needs attention. |
| WebGPU Canvas/GPU raster flags | Isolated texture p99 improved, but the full short suite regressed -6.97% average FPS and p99 +6.89 ms. Rejected. |
| WebGPU D3D11 adapter and D3D12 Dawn toggles | Helped or tied draw-call stress in probes but hurt texture-streaming or full-suite stability/performance. Rejected for now. |
| WebGPU `--disable-gpu-driver-bug-workarounds` | Initial probe was positive, full suite regressed -2.61% average FPS and p99 +1.94 ms. Rejected. |
| WebGL2 D3D11 + relaxed validation suite | Latest full short suite was -1.11% average FPS versus stock content_shell, but RSS improved and some lows improved. Not a current average-FPS win versus stock. |
| WebGL2 many-draw-calls, 30s/5s | 92.0 -> 91.1 FPS (-1.0%), but 1% low +2.6 FPS, 0.1% low +10.9 FPS, p99 -0.1 ms, max -6.8 ms, dropped frames 3 -> 0. Frame pacing win, not throughput win. |
| WebGL2 ANGLE Vulkan | Texture-streaming probe was much faster, but the full suite recorded WebGL context loss in every scene and is invalid under `--rejectGpuInstability`. Rejected. |
| WebGL2 ANGLE GL | Valid but -31.6% FPS on many-draw-calls with many dropped frames. Rejected. |

## Complexity-2 Follow-up

Additional 30s/5s safe-window checks were run at `--complexity 2` to reduce vsync/noise in draw-call and upload-heavy scenes. All rows below passed `validate_benchmark_suite.mjs` with `--rejectSoftwareRendering`, `--rejectGpuInstability`, GPU metadata, frame times, checkout provenance, build args hash, and patch-series-derived fork revision where applicable.

| Candidate | Scenes | Result |
| --- | --- | --- |
| WebGL2 zero-copy only (`--enable-zero-copy`) | many-draw-calls, glTF-loader stress, texture-streaming | Average FPS improved in all three checked scenes: +3.1%, +4.1%, and +3.2%. CPU/render submission improved by 0.36-0.56 ms. Texture-streaming p95/p99 regressed despite max frame time improving, so this is a candidate, not final default retention. |
| WebGL2 relaxed validation only | many-draw-calls | Regressed -7.7% average FPS and worsened lows/tails. Do not keep as a default WebGL2 speed profile. |
| WebGL2 relaxed validation + zero-copy | many-draw-calls | Only +0.2% average FPS. It improved p95 and startup but was worse than zero-copy-only. Do not keep this combination as the current WebGL2 candidate. |
| WebGL2 relaxed validation + ANGLE Vulkan | many-draw-calls | Invalid: WebGL context loss count was 1. Rejected under the tightened GPU-instability gate. |
| WebGPU single-process, GPU timing disabled | many-draw-calls, glTF-loader stress, texture-streaming | Improved draw-call and glTF average FPS (+2.6%, +3.0%), lows, p99/max, CPU/submit, startup, and RSS. Texture-streaming average FPS regressed -5.0%, although p99/max improved. Candidate for CPU-bound WebGPU scenes only; not a full WebGPU suite win yet. |
| WebGPU single-process + zero-copy, GPU timing disabled | many-draw-calls, texture-streaming | Regressed draw-call average FPS (-6.4%). On texture-streaming it was still -3.7% average FPS but improved p99/max. Rejected as a default WebGPU profile. |
| WebGPU zero-copy only, GPU timing disabled | texture-streaming | Regressed -11.9% average FPS and worsened tails. Rejected. |

The remaining complexity-2 scenes were then completed for the active candidates. `compare_results.mjs` now writes an aggregate-average section so suite-level deltas are recorded in the generated report instead of being hand-derived from per-scene rows.

| Full-suite candidate | Aggregate result |
| --- | --- |
| WebGL2 zero-copy only (`--enable-zero-copy`) | Full seven-scene complexity-2 suite averaged +0.7% FPS, CPU -0.20 ms, submit -0.18 ms, startup -194 ms, and dropped frames -8.0 versus stock content_shell. It is still blocked for retention because average 1% low was -0.28 FPS, 0.1% low -3.91 FPS, p95 +11.93 ms, p99 +2.00 ms, and RSS +9.34 MB. |
| WebGPU default viewer, GPU timing disabled | Full seven-scene complexity-2 suite averaged -0.2% FPS versus stock. Tails improved on average (p95 -2.01 ms, p99 -8.97 ms, max -14.89 ms), but 1%/0.1% lows regressed and draw-call/glTF rows were slower. Not a throughput win. |
| WebGPU single-process, GPU timing disabled | Full seven-scene complexity-2 suite averaged +0.1% FPS with RSS -326.29 MB and startup -344.81 ms, but 1% low -8.01 FPS, 0.1% low -5.36 FPS, p95 +3.91 ms, and max +1.97 ms. Not a clean WebGPU suite speedup. |
| WebGPU in-process GPU, GPU timing disabled | Decisive-scene probe averaged +3.7% FPS across many-draw-calls, glTF-loader stress, and texture-streaming, but texture-streaming itself regressed -18.4% FPS and p95 +69.4 ms. Rejected for expansion to the full suite. |

Additional texture-path isolation was run with the new deterministic DataTexture upload mode:

| Texture-path probe | Result |
| --- | --- |
| WebGPU DataTexture, stock vs fork default vs fork single-process | Stock measured 78.7 FPS, fork default 78.2 FPS (-0.7%), and fork single-process 70.2 FPS (-10.8%). DataTexture removes the severe CanvasTexture bottleneck for both browsers, but it does not produce a fork speed win. |
| WebGPU DataTexture + Dawn `skip_validation` | Fork default with `--enable-dawn-features=skip_validation` measured 74.9 FPS (-4.9%), and single-process + skip validation measured 67.4 FPS (-14.3%). Rejected. |
| WebGPU DataTexture browser-mode isolation | Fork browser-mode measured 75.4 FPS (-4.2%) while fork viewer-mode measured 78.2 FPS (-0.7%), so viewer-mode launch policy is not the source of the remaining WebGPU texture delta. |
| WebGL2 DataTexture + zero-copy | Stock measured 103.7 FPS and fork zero-copy measured 101.7 FPS (-2.0%). DataTexture improves absolute WebGL2 texture throughput versus CanvasTexture, but it does not fix the zero-copy candidate's texture-streaming throughput risk. |

Additional WebGPU queue attribution was then run at complexity 2 with GPU timing disabled and `--queueInstrumentation` enabled. This is attribution-only evidence, not clean final FPS evidence, because the JS queue wrappers add overhead to both stock and fork.

| Queue-attribution probe | Result |
| --- | --- |
| WebGPU CanvasTexture queue attribution | Stock measured 5.33 FPS and fork default 5.10 FPS (-4.3%). The scene issued 17,481 stock / 16,626 fork `copyExternalImageToTexture` calls and zero `writeTexture` calls, with 17,849 stock / 16,976 fork queue submits. CanvasTexture is therefore a `copyExternalImageToTexture` and submit/flush problem, not a `writeTexture` problem. |
| WebGPU DataTexture queue attribution | Stock measured 74.00 FPS and fork default 72.32 FPS (-2.3%). The scene issued 235,315 stock / 229,235 fork `writeTexture` calls and about 4.9k queue submits, confirming the deterministic DataTexture path isolates the `writeTexture` upload route. |
| WebGPU D3D11 delayed-flush smoke | Fork-only 5s smoke with `--use-webgpu-adapter=d3d11 --enable-dawn-features=d3d11_delay_flush_to_gpu` measured 72.20 FPS on DataTexture. Not expanded because it did not beat prior stock/default evidence. |
| WebGPU Dawn `disable_robustness` smoke | Fork-only 5s smoke measured 68.99 FPS on DataTexture. Rejected. |
| WebGPU D3D12 heap/render-pass/root-signature toggles smoke | Fork-only 5s smoke measured 68.28 FPS on DataTexture. Rejected. |

WebGPU texture-streaming traces were captured with WebGPU timing disabled:

- `benchmarks/traces/iter3-c2-webgpu-texture-baseline-trace.json`
- `benchmarks/traces/iter3-c2-webgpu-texture-singleprocess-trace.json`
- `benchmarks/reports/iter3-c2-webgpu-texture-baseline-trace-summary.md`
- `benchmarks/reports/iter3-c2-webgpu-texture-singleprocess-trace-summary.md`

Under trace, stock texture-streaming measured 5.04 FPS, p99 215.3 ms, CPU 53.1 ms, and submit 50.5 ms. Single-process measured 4.07 FPS, p99 298.7 ms, CPU 67.8 ms, and submit 64.2 ms. The trace summaries show most time under `GpuChannel::ExecuteDeferredRequest`, `CommandBuffer::Flush`, `WebGPU`, and requestAnimationFrame callbacks; the name-based classifier does not expose the CanvasTexture upload path as explicit texture-upload slices, so the next investigation needs deeper Dawn/CanvasTexture instrumentation or more targeted Perfetto categories.

New reports:

- `benchmarks/reports/iter3-c2-webgl2-zero-copy-isolation-comparison.md`
- `benchmarks/reports/iter3-c2-webgl2-zerocopy-problem-scenes-comparison.md`
- `benchmarks/reports/iter3-c2-webgl2-zerocopy-full-suite-comparison.md`
- `benchmarks/reports/iter3-c2-many-draw-calls-expanded-comparison.md`
- `benchmarks/reports/iter3-c2-webgpu-default-vs-singleprocess-full-suite-comparison.md`
- `benchmarks/reports/iter3-c2-webgpu-process-probe-decisive-scenes-comparison.md`
- `benchmarks/reports/iter3-c2-webgpu-singleprocess-problem-scenes-comparison.md`
- `benchmarks/reports/iter3-c2-webgpu-texture-process-zero-copy-isolation-comparison.md`
- `benchmarks/reports/iter4-c2-webgpu-texture-datatexture-process-comparison.md`
- `benchmarks/reports/iter4-c2-webgpu-texture-datatexture-dawnskip-comparison.md`
- `benchmarks/reports/iter4-c2-webgpu-texture-datatexture-viewermode-isolation-comparison.md`
- `benchmarks/reports/iter4-c2-webgl2-texture-datatexture-zerocopy-comparison.md`
- `benchmarks/reports/iter5-c2-webgpu-texture-queue-attribution-canvas-comparison.md`
- `benchmarks/reports/iter5-c2-webgpu-texture-queue-attribution-data-comparison.md`
- `benchmarks/reports/iter5-c2-webgpu-queue-attribution-summary.md`
- `benchmarks/reports/iter6-existing-candidate-analysis.md`
- `benchmarks/reports/iter6-existing-candidate-analysis.json`

Raw results:

- `benchmarks/raw/iter1-baseline-many-draw-calls-webgl2.json`
- `benchmarks/raw/iter1-fork-fast-many-draw-calls-webgl2.json`
- `benchmarks/raw/iter1-baseline-short-many-draw-calls-webgpu.json`
- `benchmarks/raw/iter1-fork-singleprocess-short-many-draw-calls-webgpu.json`
- `benchmarks/raw/iter1-baseline-short-texture-streaming-webgpu.json`
- `benchmarks/raw/iter1-fork-inprocess-texture-streaming-webgpu.json`

Reports:

- `benchmarks/reports/iter1-local-comparison.md`
- `benchmarks/reports/iter1-webgpu-many-draw-calls-comparison.md`
- `benchmarks/reports/iter1-webgpu-texture-inprocess-comparison.md`
- `benchmarks/reports/iter2-webgpu-suite-singleprocess-notiming-comparison.md`
- `benchmarks/reports/iter2-webgpu-suite-default-vs-singleprocess-notiming-comparison.md`
- `benchmarks/reports/iter2-webgpu-suite-canvasgpu-notiming-comparison.md`
- `benchmarks/reports/iter2-webgl2-suite-fast-comparison.md`
- `benchmarks/reports/iter2-webgl2-many-draw-calls-long-comparison.md`

## Decision

- Keep the WebGPU render-loop fix; it lowers measured submit/CPU cost and avoids deprecated API use.
- Keep GPU-instability rejection in validators; old aggressive WebGPU evidence is now rejected because it included device-loss runs.
- Treat WebGL2 zero-copy-only as blocked rather than retained. It now has a full seven-scene complexity-2 average-FPS win, but the low-FPS and p95/p99 regressions are material enough to require either a tail fix or a separate official-duration decision.
- Do not keep WebGL2 relaxed validation as the current candidate. It regressed complexity-2 draw-call throughput, and Vulkan-backed relaxed validation was invalid due WebGL context loss.
- Keep WebGPU single-process only as a candidate trusted experiment for CPU-bound WebGPU scenes. Full-suite complexity-2 evidence is approximately flat on average FPS and regresses lows/tails, while texture-streaming remains the blocker.
- Reject WebGPU in-process GPU as a full-suite candidate for now because it worsened texture-streaming more severely than single-process despite helping draw-call/glTF stress.
- Reject ANGLE Vulkan WebGL2 evidence because the stricter validator catches WebGL context loss even when the FPS row looks attractive.
- Reject WebGPU Canvas/GPU raster, D3D11 adapter, D3D12 Dawn toggle, and disabled-driver-workaround profiles until they can pass full-suite evidence without tail-latency regressions.
- Reject WebGPU zero-copy as a default profile. At complexity 2 it worsened WebGPU draw-call throughput and texture-streaming average FPS, even when it improved some texture tail metrics.
- Reject Dawn `skip_validation` for WebGPU texture streaming on this host. It is unsafe for arbitrary content and the trusted-content probe worsened both average FPS and lows on the deterministic DataTexture upload path.
- Do not replace the official CanvasTexture stress case with DataTexture as a speed claim. DataTexture is useful attribution coverage, but both WebGPU and WebGL2 probes still failed to produce a retained fork-over-stock texture win.
- Keep WebGPU queue instrumentation as an opt-in attribution mode only. It showed CanvasTexture maps to `copyExternalImageToTexture` and high submit counts, while DataTexture maps to `writeTexture`. Do not use queue-instrumented runs for final clean FPS claims.
- Reject the new WebGPU Dawn smoke flags from this iteration: D3D11 delayed flush was not promising enough to expand, `disable_robustness` regressed, and the prior D3D12 heap/render-pass/root-signature toggles regressed the DataTexture smoke.
- Keep `scripts/analyze_candidates.mjs` as the guardrail for existing-result triage. The latest `iter9` candidate-analysis report still has no retained suite speedup: the required-gate WebGL2 path is the one-scene relaxed-validation plus zero-copy signal, which remains `needs-suite`; the existing seven-scene WebGL2 zero-copy family remains `blocked-tail` on postprocessing 0.1% low FPS; WebGPU default is `blocked-throughput` on glTF-loader stress average FPS; and WebGPU single-process remains `not useful`. The analyzer emits blocker diagnostics so the next iteration can target the scene and metric blocking retention rather than rerunning broad profiles.
- Add `scripts/run_blocker_experiments.ps1` for the next speed iteration. It consumes those blocker diagnostics, expands `needs-suite` rows to the full seven-scene renderer pass, and otherwise launches focused WebGL2/WebGPU trusted matrices for only the blocker scenes before any official-duration rerun. The WebGL2 trusted matrix now includes the combined relaxed-validation plus zero-copy row required to expand the current one-scene relaxed+zero-copy signal, plus an isolated D3D11 plus zero-copy row so the current zero-copy tail issue can be measured without relaxed-validation contamination.
- Add targeted WebGPU trace capture to the blocker loop. `scripts/run_blocker_experiments.ps1 -CaptureTargetedTrace` now schedules matched stock and fork WebGPU traces for every planned WebGPU blocker scene, validates raw trace JSON and sidecar metadata, summarizes queue/path slices, and records trace artifacts in `targeted-blocker-experiment-plan.json`; post-ATL runs pass this through automatically when official trace capture and WebGPU coverage are enabled.
- The final artifact audit now runs the analyzer as a hard speedup-claim gate for both `webgl2` and `webgpu`. A completed official manifest can still exist for provenance, but `-FinalGate` remains pending until both renderers have retained candidate families instead of missing evidence, `needs-suite`, `blocked-tail`, or `not useful` rows.
- The post-ATL handoff now supports `-RunTrustedWebGpuDawnMatrix`, so the completion command can generate WebGL2 and WebGPU renderer-specific trusted manifests in one run instead of relying on a manual second pass for Dawn/WebGPU experiments.
- The post-ATL final-gate preflight now also requires `-RunTargetedBlockerExperiments`, so a completion-oriented run cannot skip the focused blocker loop that targets the current WebGL2 suite-expansion/tail issue and WebGPU glTF-loader throughput issue before the final audit.
- The trusted experiment matrix now supports `-DisableGpuTiming`; the post-ATL WebGPU Dawn pass uses it when WebGPU timing is disabled for official evidence, preventing trusted WebGPU candidate runs from reintroducing timestamp-query device-loss contamination.
- Add `-IncludeWebGlCompositorExperiments` / `-TrustedMatrixWebGlCompositorExperiments` for the next WebGL2 iteration. It will test GPU-memory-buffer compositor resources, UI zero-copy, and GPU rasterization both alone and paired with `--viewer-zero-copy`, because the current WebGL2 average-FPS win is blocked specifically by low-FPS and p95/p99 tails.
- Add trusted frame-pacing experiments for `--disable-frame-rate-limit`, `--disable-gpu-vsync`, and the combined pair. These are now included in the targeted blocker planner for WebGL2 tail/needs-suite expansion and WebGPU draw-call/glTF/large-pass blockers, so the next rebuilt run can test whether FPS caps or presentation pacing are limiting throughput or tail metrics. They are not default optimizations and must pass the same p95/p99 and per-scene throughput gates as every other candidate.
- Add `-IncludeWebGpuChromiumFeatureExperiments` / `-TrustedMatrixWebGpuChromiumFeatureExperiments` for the next WebGPU iteration. It will test `RemoveGPULegacyIPC`, `WebGPUUseHLSL2021`, `WebGPUEnableRangeAnalysisForRobustness` disablement, and the combined IPC/HLSL `--enable-features` row as command-buffer IPC, shader-path, and robustness range-analysis candidates, with raw feature flags gated to trusted viewer runs.
- Add `-IncludeWebGpuUploadExperiments` / `-TrustedMatrixWebGpuUploadExperiments` for the next WebGPU iteration. It will test `IncreasedCmdBufferParseSlice`, disabling `D3DBackingUploadWithUpdateSubresource`, Dawn `d3d12_relax_buffer_texture_copy_pitch_and_offset_alignment`, Blink queue/submit flush deferral, Blink canvas texture-validation skip, Blink canvas memory-accounting skip, Blink `copyExternalImageToTexture` sRGB color-conversion setup skip, Blink `copyExternalImageToTexture` sRGB color-space validation skip, Blink `copyExternalImageToTexture` destination-validation skip, Blink `copyExternalImageToTexture` source-validation skip, Blink `copyExternalImageToTexture` copy-size validation skip, a combined copyExternalImage trusted fast-path row, Blink `writeTexture` layout-validation skip, Blink use-counter skip, and interaction rows as command-buffer parse, D3D upload-path, D3D12 buffer-texture copy-alignment, submit/presentation, validation, canvas accounting, DataTexture layout validation, and CanvasTexture copy conversion/validation-overhead candidates for the current many-draw-calls and texture-streaming blockers.
- Expand `-IncludeWebGpuDawnExperiments` with source-derived D3D11 Dawn toggles from this Chromium checkout: `d3d11_use_unmonitored_fence`, `d3d11_use_discard_view`, `d3d11_disable_cpu_buffers`, and `d3d11_disable_map_on_default_buffers`. These target CPU/GPU wait overhead, discarded render-pass attachment work, and D3D11 upload-path behavior for the current WebGPU blockers.
- Keep the synchronous common-case viewer render loop as a candidate source optimization. The WebGL2 blocker-scene postprocessing render-target pass now avoids an unnecessary per-frame Promise continuation as well, but do not claim a performance win until the post-WDAC stock/fork rerun measures JS frame time, render submission time, average FPS, and p95/p99 across both renderers.
- Extend viewer resource precompile to scene-provided compile targets. The postprocessing scene now exposes both the render-target scene and the full-screen pass as compile targets, so warmed blocker runs with `-Precompile` can precompile both passes instead of relying on prerender frames alone to discover the second pass. This is a source-side warmup candidate only; it still needs same-revision stock/fork measurement before any speed claim.
- Add `--viewer-zero-copy` as the explicit trusted alias for Chromium `--enable-zero-copy`. The benchmark and trace runners reject it for WebGPU by default because prior WebGPU zero-copy evidence regressed; use it only for WebGL2 candidate reruns until new evidence says otherwise.
- Require official/trusted suite validation and candidate analysis to match resource-warmup mode (`precompile` and `prerenderFrames`) and resource precompile target count. Warmup can be useful for shader/pipeline stall reduction, but it is not valid evidence if a warmed run is compared against an unwarmed baseline or a legacy warmed baseline that did not report the same compile-target coverage.
- Regenerate `benchmarks/reports/targeted-blocker-experiment-plan.json` with `-Precompile -PrerenderFrames 2 -SettleGpuAfterWarmup` for the next post-WDAC blocker pass. The current handoff now schedules matched warmed and GPU-settled stock baselines, a seven-scene WebGL2 expansion for zero-copy / compositor / frame-pacing / isolated D3D11-plus-zero-copy / D3D11 relaxed-validation candidates, and focused warmed WebGPU matrices for glTF-loader and large-static blockers covering process, frame-pacing, D3D11/Dawn, submit/flush, validation/accounting, IPC, command-slice, DXC/HLSL shader-codegen, Dawn blob-cache hash-validation disablement, WebGPU robustness range-analysis disablement, D3D12 pipeline/backend toggles, D3D11 DXC/fence/flush interactions, the D3D11 DXC/IPC/HLSL2021/command-slice/range-analysis interaction probe, and unsafe trusted-validation probes.

## Next Work

- Unblock the Chromium rebuild host. `siso ninja -offline -re_exec_enable=false -C out\ReleaseViewerDefault content_shell` now fails before compiling the WebGPU trace patch because Windows Application Control blocks a generated Chromium Rust build-script EXE with `WinError 4551`. `scripts/check_prereqs.ps1`, `scripts/write_environment_manifest.ps1`, and the build-state audit now catch this as `windows_code_integrity_chromium_rust = False` with `current_siso_blocks=1`.
- After WDAC is cleared, run the regenerated warmed targeted blocker plan first, then promote only clean one-scene triage wins through `targeted-suite-promotion-plan.json` before making any WebGL2/WebGPU retained-speed claim.
- Rebuild the fork with the full `chromium_patches` series; `scripts/build_viewer_fork.ps1 -ApplyPatch` now applies both the viewer entrypoint patch and `chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch`. Then recapture WebGPU texture-streaming traces to attribute Blink `copyExternalImageToTexture`, `CopyFromCanvasSourceImage`, `writeTexture`, `writeBuffer`, `submit`, flush cost, and GPU-resident versus CPU-fallback texture-copy path in Chromium trace slices. `scripts/summarize_trace.mjs` now emits a focused WebGPU queue-event table for those rebuilt traces, and trusted diagnostic traces can pass `--viewerRejectWebgpuCpuTextureFallback` to fail instead of silently accepting CPU readback/upload fallback.
- Investigate trusted-only Blink/Dawn batching or flush changes for `copyExternalImageToTexture` only after the rebuilt trace proves where the time is spent. The current source-backed trusted experiments separately cover `writeBuffer`/`writeTexture` flush deferral, `GPUQueue.submit` immediate-flush deferral, `GPUCanvasContext.getCurrentTexture` texture-descriptor validation skip, `GPUCanvasContext.getCurrentTexture` canvas memory-accounting skip, `GPUQueue.copyExternalImageToTexture` sRGB color-conversion setup skip, `GPUQueue.copyExternalImageToTexture` sRGB color-space validation skip, `GPUQueue.copyExternalImageToTexture` destination-validation skip, `GPUQueue.copyExternalImageToTexture` source-validation skip, `GPUQueue.copyExternalImageToTexture` copy-size validation skip, the combined copyExternalImage trusted fast path, `GPUQueue.writeTexture` layout-validation skip, and use-counter skip so queue-write, submit/presentation, validation, canvas accounting, DataTexture layout validation, CanvasTexture copy conversion/validation, and telemetry effects can be kept distinct.
- Investigate a WebGPU profile split only as a benchmark-analysis tool; a real retained runtime still needs a coherent default/aggressive mode rather than per-scene process flags.
- Look for a WebGL2 zero-copy tail fix before official-duration promotion.
- Measure the synchronous common-case render-loop, postprocessing render-callback change, and multi-target postprocessing precompile against the same revision stock baseline; they should help only if per-frame promise overhead or uncompiled second-pass shader/pipeline work was visible in JS/submission metrics or postprocessing tail variance.
- Re-run official 120s stock/fork comparison only after the retained profile improves average FPS without material p99 regression across the suite.

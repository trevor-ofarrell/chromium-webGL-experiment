# Candidate Speed Analysis

Generated: 2026-05-29T01:55:23.943Z

Input results: 14
Input file digest: `b4c83e457ea969f949df2f58a8a01626f2415e7e7052a464569b59c07a28cbb0`
Accepted results: 0
Filtered results: 14

Decision rule: a family is a `candidate` only when at least 7 distinct scenes are covered, average FPS improves by at least 0.50%, no individual scene has a material average-FPS regression, average low-FPS/tail-latency deltas do not materially regress, dropped-frame rate does not increase by more than 0.50 percentage points on any scene, CPU frame time does not increase by more than 0.50 ms on any scene, render submission time does not increase by more than 0.50 ms on any scene, shader compile events do not increase by more than 0 on any scene, WebGPU measured-window pipeline creation time does not increase by more than 1.00 ms on any scene, required benchmark evidence fields, including explicit positive benchmark complexity and explicit GPU-timing mode, are present, stability artifacts are filtered out, viewer-side WebGPU queue attribution, viewer-side WebGPU command-encoder attribution, viewer-side WebGPU bind-group attribution, viewer-side WebGPU pipeline-state attribution, viewer-side WebGPU buffer-state attribution, viewer-side WebGPU render-state attribution, viewer-side WebGPU immediate-data attribution, and source-added WebGPU queue trace attribution runs are filtered out, explicit WebGPU CPU texture fallback/readback evidence and copyExternalImage upload experiments without CPU-fallback rejection are filtered out, trusted-only experiment metadata or browser flags require viewer_mode=true and viewer_trusted_content=true, WebGPU pipeline-quiet warmup runs are filtered out unless the requested quiet window was achieved and no pipelines were created during the measured window, and the result is fresh-profile evidence. Raw dropped-frame counts remain reported, and the analyzer falls back to raw-count gating only when a dropped-frame rate cannot be derived. Positive average FPS with incomplete scene coverage is `needs-suite`; positive average FPS below the minimum suite threshold is `weak-throughput`; positive average FPS with a material scene throughput regression is `blocked-throughput`; positive average FPS with shader compile event or WebGPU pipeline-create timing regression is `blocked-shader-stalls`; positive average FPS with dropped-frame-rate regression is `blocked-dropped-frames`; positive average FPS with CPU frame or render submission regression is `blocked-cpu-overhead`; positive average FPS with low-FPS or p95/p99 regression is `blocked-tail`; explicit profile-reuse wins are `cache-attribution` and require a matching fresh-profile official run before retained speed claims. Duplicate rows for the same family, profile-cache mode/key, and scene are collapsed to the most conservative representative row. Comparisons require the same build-args hash, platform, driver, GPU device identity, explicit benchmark complexity and explicit GPU-timing mode, WebGPU BundleGroup/render-bundle scene mode, WebGPU pipeline-instrumentation mode, requested resource warmup mode, resource precompile target count, preinitialized texture/render-target count, GPU-settle warmup mode, WebGPU pipeline-quiet warmup mode, and profile-cache mode/key while leaving backend choice available as an optimization variable. If multiple compatible stock baselines are present, the comparison uses the fastest valid stock baseline for that exact compatibility group. Accepted artifacts must report browser_is_from_checkout=true. Accepted artifacts must include positive package_size_mb evidence.

## Candidate Families

No comparable candidate families found.

## Blocker Diagnostics

No non-candidate families need blocker diagnostics.

## Required Speedup Claim Gate

Required renderers: webgpu
Status: fail

| Renderer | Candidate Families | Best Status | Best Candidate | Scenes | Avg FPS Delta % | Min FPS Delta % | P99 Delta ms | Dropped Frames Delta | Dropped Frame Rate Delta pp | Shader Events Delta | Pipeline Create Delta ms |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgpu | 0 | missing |  | 0 |  |  |  |  |  |  |  |

Failures:
- webgpu: no comparable fork-over-baseline family

## Filtered Inputs

| Reason | Count |
| --- | ---: |
| diagnostic texture_upload_mode=data | 14 |

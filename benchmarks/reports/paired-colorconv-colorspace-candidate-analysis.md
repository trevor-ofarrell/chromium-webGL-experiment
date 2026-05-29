# Candidate Speed Analysis

Generated: 2026-05-28T23:43:01.130Z

Input results: 28
Input file digest: `42ac7a3fd3a6dd0b739816d1d7080aa215a9088c27bbdcd731af777588de4521`
Accepted results: 28
Filtered results: 0

Decision rule: a family is a `candidate` only when at least 7 distinct scenes are covered, average FPS improves by at least 0.50%, no individual scene has a material average-FPS regression, average low-FPS/tail-latency deltas do not materially regress, dropped-frame rate does not increase by more than 0.50 percentage points on any scene, CPU frame time does not increase by more than 0.50 ms on any scene, render submission time does not increase by more than 0.50 ms on any scene, shader compile events do not increase by more than 0 on any scene, WebGPU measured-window pipeline creation time does not increase by more than 1.00 ms on any scene, required benchmark evidence fields, including explicit positive benchmark complexity and explicit GPU-timing mode, are present, stability artifacts are filtered out, viewer-side WebGPU queue attribution, viewer-side WebGPU command-encoder attribution, viewer-side WebGPU bind-group attribution, viewer-side WebGPU pipeline-state attribution, viewer-side WebGPU buffer-state attribution, viewer-side WebGPU render-state attribution, viewer-side WebGPU immediate-data attribution, and source-added WebGPU queue trace attribution runs are filtered out, explicit WebGPU CPU texture fallback/readback evidence and copyExternalImage upload experiments without CPU-fallback rejection are filtered out, trusted-only experiment metadata or browser flags require viewer_mode=true and viewer_trusted_content=true, WebGPU pipeline-quiet warmup runs are filtered out unless the requested quiet window was achieved and no pipelines were created during the measured window, and the result is fresh-profile evidence. Raw dropped-frame counts remain reported, and the analyzer falls back to raw-count gating only when a dropped-frame rate cannot be derived. Positive average FPS with incomplete scene coverage is `needs-suite`; positive average FPS below the minimum suite threshold is `weak-throughput`; positive average FPS with a material scene throughput regression is `blocked-throughput`; positive average FPS with shader compile event or WebGPU pipeline-create timing regression is `blocked-shader-stalls`; positive average FPS with dropped-frame-rate regression is `blocked-dropped-frames`; positive average FPS with CPU frame or render submission regression is `blocked-cpu-overhead`; positive average FPS with low-FPS or p95/p99 regression is `blocked-tail`; explicit profile-reuse wins are `cache-attribution` and require a matching fresh-profile official run before retained speed claims. Duplicate rows for the same family, profile-cache mode/key, and scene are collapsed to the most conservative representative row. Comparisons require the same build-args hash, platform, driver, GPU device identity, explicit benchmark complexity and explicit GPU-timing mode, WebGPU BundleGroup/render-bundle scene mode, WebGPU pipeline-instrumentation mode, requested resource warmup mode, resource precompile target count, preinitialized texture/render-target count, GPU-settle warmup mode, WebGPU pipeline-quiet warmup mode, and profile-cache mode/key while leaving backend choice available as an optimization variable. If multiple compatible stock baselines are present, the comparison uses the fastest valid stock baseline for that exact compatibility group. Accepted artifacts must report browser_is_from_checkout=true. Accepted artifacts must include positive package_size_mb evidence.

## Candidate Families

| Cohort | Renderer | Baseline | Candidate | Evidence | Profile Cache | Scenes | Status | Avg FPS Delta % | Min FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Dropped Frame Rate Delta pp | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms | Startup Delta ms | RSS Delta MB |
| --- | --- | --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgl2 | baseline-content-shell | fork-viewer-default | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | candidate | 2.99 | -0.00 | 1.24 | 8.46 | -7.14 | -42.87 | 2.71 | -0.03 | 0.00 | 0.00 | -0.14 | -0.12 | -228.9 | -9.8 |
| official | webgpu | baseline-content-shell-webgpu-paired-colorconv | fork-viewer-exp-webgpu-colorconv-colorspace-paired | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | blocked-cpu-overhead | 1.05 | -0.17 | -1.46 | -3.23 | 0.00 | 0.04 | -4.86 | -0.70 | 0.00 | 0.00 | -0.06 | -0.05 | 461.1 | -10.8 |

## Blocker Diagnostics

Primary blocker is the worst scene-level issue for each non-candidate family, so the next iteration can target the scene and metric that prevents retention.

| Cohort | Renderer | Candidate | Status | Blocking Scene | Primary Blocker | FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Dropped Frame Rate Delta pp | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgpu | fork-viewer-exp-webgpu-colorconv-colorspace-paired | blocked-cpu-overhead | gltf-loader-stress | render submission +0.65 ms | -0.17 | -8.41 | -27.44 | 0.00 | 0.00 | 3.00 | -0.70 | 0.00 | 0.00 | 0.64 | 0.65 |

## Required Speedup Claim Gate

Required renderers: webgl2, webgpu
Status: fail

| Renderer | Candidate Families | Best Status | Best Candidate | Scenes | Avg FPS Delta % | Min FPS Delta % | P99 Delta ms | Dropped Frames Delta | Dropped Frame Rate Delta pp | Shader Events Delta | Pipeline Create Delta ms |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgl2 | 1 | candidate | fork-viewer-default | 7 | 2.99 | -0.00 | -42.87 | 2.71 | -0.03 | 0.00 | 0.00 |
| webgpu | 0 | blocked-cpu-overhead | fork-viewer-exp-webgpu-colorconv-colorspace-paired | 7 | 1.05 | -0.17 | 0.04 | -4.86 | -0.70 | 0.00 | 0.00 |

Failures:
- webgpu: fork-viewer-exp-webgpu-colorconv-colorspace-paired vs baseline-content-shell-webgpu-paired-colorconv: status=blocked-cpu-overhead, scenes=7, avg_fps_delta_pct=1.05, p99_delta_ms=0.04

## Filtered Inputs

| Reason | Count |
| --- | ---: |
| None | 0 |

# Candidate Speed Analysis

Generated: 2026-05-28T22:56:31.564Z

Input results: 49
Input file digest: `4c4d00e09d80b206105bdd16a6444510655471dbfd7a7b8c5ac589c3fc6f2dbf`
Accepted results: 49
Filtered results: 0

Decision rule: a family is a `candidate` only when at least 7 distinct scenes are covered, average FPS improves by at least 0.50%, no individual scene has a material average-FPS regression, average low-FPS/tail-latency deltas do not materially regress, dropped-frame rate does not increase by more than 0.50 percentage points on any scene, CPU frame time does not increase by more than 0.50 ms on any scene, render submission time does not increase by more than 0.50 ms on any scene, shader compile events do not increase by more than 0 on any scene, WebGPU measured-window pipeline creation time does not increase by more than 1.00 ms on any scene, required benchmark evidence fields, including explicit positive benchmark complexity and explicit GPU-timing mode, are present, stability artifacts are filtered out, viewer-side WebGPU queue attribution, viewer-side WebGPU command-encoder attribution, viewer-side WebGPU bind-group attribution, viewer-side WebGPU pipeline-state attribution, viewer-side WebGPU buffer-state attribution, viewer-side WebGPU render-state attribution, viewer-side WebGPU immediate-data attribution, and source-added WebGPU queue trace attribution runs are filtered out, explicit WebGPU CPU texture fallback/readback evidence and copyExternalImage upload experiments without CPU-fallback rejection are filtered out, trusted-only experiment metadata or browser flags require viewer_mode=true and viewer_trusted_content=true, WebGPU pipeline-quiet warmup runs are filtered out unless the requested quiet window was achieved and no pipelines were created during the measured window, and the result is fresh-profile evidence. Raw dropped-frame counts remain reported, and the analyzer falls back to raw-count gating only when a dropped-frame rate cannot be derived. Positive average FPS with incomplete scene coverage is `needs-suite`; positive average FPS below the minimum suite threshold is `weak-throughput`; positive average FPS with a material scene throughput regression is `blocked-throughput`; positive average FPS with shader compile event or WebGPU pipeline-create timing regression is `blocked-shader-stalls`; positive average FPS with dropped-frame-rate regression is `blocked-dropped-frames`; positive average FPS with CPU frame or render submission regression is `blocked-cpu-overhead`; positive average FPS with low-FPS or p95/p99 regression is `blocked-tail`; explicit profile-reuse wins are `cache-attribution` and require a matching fresh-profile official run before retained speed claims. Duplicate rows for the same family, profile-cache mode/key, and scene are collapsed to the most conservative representative row. Comparisons require the same build-args hash, platform, driver, GPU device identity, explicit benchmark complexity and explicit GPU-timing mode, WebGPU BundleGroup/render-bundle scene mode, WebGPU pipeline-instrumentation mode, requested resource warmup mode, resource precompile target count, preinitialized texture/render-target count, GPU-settle warmup mode, WebGPU pipeline-quiet warmup mode, and profile-cache mode/key while leaving backend choice available as an optimization variable. If multiple compatible stock baselines are present, the comparison uses the fastest valid stock baseline for that exact compatibility group. Accepted artifacts must report browser_is_from_checkout=true. Accepted artifacts must include positive package_size_mb evidence.

## Candidate Families

| Cohort | Renderer | Baseline | Candidate | Evidence | Profile Cache | Scenes | Status | Avg FPS Delta % | Min FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Dropped Frame Rate Delta pp | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms | Startup Delta ms | RSS Delta MB |
| --- | --- | --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgl2 | baseline-content-shell | fork-viewer-default | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | candidate | 2.99 | -0.00 | 1.24 | 8.46 | -7.14 | -42.87 | 2.71 | -0.03 | 0.00 | 0.00 | -0.14 | -0.12 | -228.9 | -9.8 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-aggressive-gpu-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | blocked-throughput | 1.54 | -22.05 | 10.32 | 15.67 | -16.63 | -12.04 | 52.57 | 4.65 | 0.00 | 0.00 | 0.42 | 0.44 | 141.2 | -6.7 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-default-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | blocked-throughput | 1.20 | -3.64 | 11.14 | 14.72 | -11.86 | -4.87 | 13.43 | 0.77 | 0.00 | 0.00 | 0.15 | 0.16 | -259.0 | 0.8 |
| official | webgl2 | baseline-content-shell | fork-viewer-aggressive-gpu-d3d11-relaxed | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | blocked-tail | 1.15 | -0.00 | 1.09 | 7.70 | -2.37 | -40.47 | 0.86 | -0.02 | 0.00 | 0.00 | -0.14 | -0.14 | -160.2 | -10.0 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | not useful | -0.81 | -8.96 | 12.31 | 19.34 | -4.73 | -2.46 | 16.00 | 1.52 | 0.00 | 0.00 | 0.46 | 0.45 | 378.6 | -6.8 |

## Blocker Diagnostics

Primary blocker is the worst scene-level issue for each non-candidate family, so the next iteration can target the scene and metric that prevents retention.

| Cohort | Renderer | Candidate | Status | Blocking Scene | Primary Blocker | FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Dropped Frame Rate Delta pp | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgpu | fork-viewer-aggressive-gpu-webgpu | blocked-throughput | many-draw-calls | avg FPS -22.05% | -22.05 | -9.81 | -9.84 | 0.20 | 16.50 | 318.00 | 4.65 | 0.00 | 0.00 | 5.50 | 5.44 |
| official | webgpu | fork-viewer-default-webgpu | blocked-throughput | gltf-loader-stress | avg FPS -3.64% | -3.64 | -6.27 | 9.67 | 0.10 | 16.40 | 66.00 | 0.77 | 0.00 | 0.00 | 1.53 | 1.53 |
| official | webgl2 | fork-viewer-aggressive-gpu-d3d11-relaxed | blocked-tail | postprocessing | 0.1% low -2.64 FPS | 0.00 | -0.33 | -2.64 | 0.00 | 0.00 | 0.00 | -0.02 | 0.00 | 0.00 | -0.00 | -0.00 |
| official | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | not useful | many-draw-calls | avg FPS -8.96% | -8.96 | -3.91 | -9.80 | 0.00 | 0.10 | 132.00 | 1.52 | 0.00 | 0.00 | 1.89 | 1.88 |

## Required Speedup Claim Gate

Required renderers: webgl2, webgpu
Status: fail

| Renderer | Candidate Families | Best Status | Best Candidate | Scenes | Avg FPS Delta % | Min FPS Delta % | P99 Delta ms | Dropped Frames Delta | Dropped Frame Rate Delta pp | Shader Events Delta | Pipeline Create Delta ms |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgl2 | 1 | candidate | fork-viewer-default | 7 | 2.99 | -0.00 | -42.87 | 2.71 | -0.03 | 0.00 | 0.00 |
| webgpu | 0 | blocked-throughput | fork-viewer-aggressive-gpu-webgpu | 7 | 1.54 | -22.05 | -12.04 | 52.57 | 4.65 | 0.00 | 0.00 |

Failures:
- webgpu: fork-viewer-aggressive-gpu-webgpu vs baseline-content-shell-webgpu: status=blocked-throughput, scenes=7, avg_fps_delta_pct=1.54, p99_delta_ms=-12.04

## Filtered Inputs

| Reason | Count |
| --- | ---: |
| None | 0 |

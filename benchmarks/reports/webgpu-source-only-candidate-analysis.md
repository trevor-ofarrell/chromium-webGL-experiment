# Candidate Speed Analysis

Generated: 2026-05-28T21:40:40.991Z

Input results: 28
Input file digest: `11d6080a6aa02b5205adf92bf1ee2f3db66306b71d454d733054476074a13e9d`
Accepted results: 28
Filtered results: 0

Decision rule: a family is a `candidate` only when at least 7 distinct scenes are covered, all required scenes are present (many-draw-calls, instancing, shader-heavy, texture-streaming, postprocessing, large-static, gltf-loader-stress), average FPS improves by at least 0.50%, no individual scene has a material average-FPS regression, average low-FPS/tail-latency deltas do not materially regress, dropped frames do not increase by more than 0 on any scene, CPU frame time does not increase by more than 0.50 ms on any scene, render submission time does not increase by more than 0.50 ms on any scene, shader compile events do not increase by more than 0 on any scene, WebGPU measured-window pipeline creation time does not increase by more than 1.00 ms on any scene, required benchmark evidence fields, including explicit positive benchmark complexity and explicit GPU-timing mode, are present, stability artifacts are filtered out, viewer-side WebGPU queue attribution, viewer-side WebGPU command-encoder attribution, viewer-side WebGPU bind-group attribution, viewer-side WebGPU pipeline-state attribution, viewer-side WebGPU buffer-state attribution, viewer-side WebGPU render-state attribution, viewer-side WebGPU immediate-data attribution, and source-added WebGPU queue trace attribution runs are filtered out, explicit WebGPU CPU texture fallback/readback evidence and copyExternalImage upload experiments without CPU-fallback rejection are filtered out, trusted-only experiment metadata or browser flags require viewer_mode=true and viewer_trusted_content=true, WebGPU pipeline-quiet warmup runs are filtered out unless the requested quiet window was achieved and no pipelines were created during the measured window, and the result is fresh-profile evidence. Positive average FPS with incomplete scene coverage is `needs-suite`; positive average FPS below the minimum suite threshold is `weak-throughput`; positive average FPS with a material scene throughput regression is `blocked-throughput`; positive average FPS with shader compile event or WebGPU pipeline-create timing regression is `blocked-shader-stalls`; positive average FPS with dropped-frame regression is `blocked-dropped-frames`; positive average FPS with CPU frame or render submission regression is `blocked-cpu-overhead`; positive average FPS with low-FPS or p95/p99 regression is `blocked-tail`; explicit profile-reuse wins are `cache-attribution` and require a matching fresh-profile official run before retained speed claims. Duplicate rows for the same family, profile-cache mode/key, and scene are collapsed to the most conservative representative row. Comparisons require the same build-args hash, platform, driver, GPU device identity, explicit benchmark complexity and explicit GPU-timing mode, WebGPU BundleGroup/render-bundle scene mode, WebGPU pipeline-instrumentation mode, requested resource warmup mode, resource precompile target count, preinitialized texture/render-target count, GPU-settle warmup mode, WebGPU pipeline-quiet warmup mode, and profile-cache mode/key while leaving backend choice available as an optimization variable. If multiple compatible stock baselines are present, the comparison uses the fastest valid stock baseline for that exact compatibility group. Accepted artifacts must report browser_is_from_checkout=true. Accepted artifacts must include positive package_size_mb evidence.

## Candidate Families

| Cohort | Renderer | Baseline | Candidate | Evidence | Profile Cache | Scenes | Status | Avg FPS Delta % | Min FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms | Startup Delta ms | RSS Delta MB |
| --- | --- | --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-default-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | weak-throughput | 0.36 | -0.00 | 0.67 | 5.48 | -0.01 | -2.39 | -0.14 | 0.00 | 0.00 | -0.10 | -0.10 | -166.1 | -4.4 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-aggressive-gpu-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | blocked-dropped-frames | 1.98 | -0.00 | 0.39 | 5.49 | -0.10 | 2.33 | -10.43 | 0.00 | 0.00 | -0.46 | -0.44 | -137.1 | -3.3 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-aggressive-source-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | not useful | -18.65 | -53.61 | -5.62 | -1.39 | 30.93 | 28.64 | 138.00 | 0.00 | 0.00 | 5.29 | 5.17 | 6574.9 | -5.8 |

## Blocker Diagnostics

Primary blocker is the worst scene-level issue for each non-candidate family, so the next iteration can target the scene and metric that prevents retention.

| Cohort | Renderer | Candidate | Status | Blocking Scene | Primary Blocker | FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgpu | fork-viewer-default-webgpu | weak-throughput | suite average | avg FPS 0.36% below required 0.50% | 0.36 | 0.67 | 5.48 | -0.01 | -2.39 | -0.14 | 0.00 | 0.00 | -0.10 | -0.10 |
| official | webgpu | fork-viewer-aggressive-gpu-webgpu | blocked-dropped-frames | texture-streaming | dropped frames +17 | 8.03 | -0.19 | -0.33 | -0.30 | 16.50 | 17.00 | 0.00 | 0.00 | -1.19 | -1.07 |
| official | webgpu | fork-viewer-aggressive-source-webgpu | not useful | texture-streaming | avg FPS -53.61% | -53.61 | -1.95 | -1.76 | 183.00 | 166.70 | -110.00 | 0.00 | 0.00 | 8.72 | 8.11 |

## Required Speedup Claim Gate

Required renderers: webgpu
Status: fail

| Renderer | Candidate Families | Best Status | Best Candidate | Scenes | Avg FPS Delta % | Min FPS Delta % | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgpu | 0 | weak-throughput | fork-viewer-default-webgpu | 7 | 0.36 | -0.00 | -2.39 | -0.14 | 0.00 | 0.00 |

Failures:
- webgpu: fork-viewer-default-webgpu vs baseline-content-shell-webgpu: status=weak-throughput, scenes=7, avg_fps_delta_pct=0.36, p99_delta_ms=-2.39

## Filtered Inputs

| Reason | Count |
| --- | ---: |
| None | 0 |

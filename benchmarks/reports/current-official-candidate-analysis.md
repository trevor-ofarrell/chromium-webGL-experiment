# Candidate Speed Analysis

Generated: 2026-05-28T20:58:00.397Z

Input results: 42
Input file digest: `ba93c878f6be2067eaacdeef47ae1d0942e2d07f6010933dc038b299e815ad4f`
Accepted results: 42
Filtered results: 0

Decision rule: a family is a `candidate` only when at least 7 distinct scenes are covered, all required scenes are present (many-draw-calls, instancing, shader-heavy, texture-streaming, postprocessing, large-static, gltf-loader-stress), average FPS improves by at least 0.50%, no individual scene has a material average-FPS regression, average low-FPS/tail-latency deltas do not materially regress, dropped frames do not increase by more than 0 on any scene, CPU frame time does not increase by more than 0.50 ms on any scene, render submission time does not increase by more than 0.50 ms on any scene, shader compile events do not increase by more than 0 on any scene, WebGPU measured-window pipeline creation time does not increase by more than 1.00 ms on any scene, required benchmark evidence fields, including explicit positive benchmark complexity and explicit GPU-timing mode, are present, stability artifacts are filtered out, viewer-side WebGPU queue attribution, viewer-side WebGPU command-encoder attribution, viewer-side WebGPU bind-group attribution, viewer-side WebGPU pipeline-state attribution, viewer-side WebGPU buffer-state attribution, viewer-side WebGPU render-state attribution, viewer-side WebGPU immediate-data attribution, and source-added WebGPU queue trace attribution runs are filtered out, explicit WebGPU CPU texture fallback/readback evidence and copyExternalImage upload experiments without CPU-fallback rejection are filtered out, trusted-only experiment metadata or browser flags require viewer_mode=true and viewer_trusted_content=true, WebGPU pipeline-quiet warmup runs are filtered out unless the requested quiet window was achieved and no pipelines were created during the measured window, and the result is fresh-profile evidence. Positive average FPS with incomplete scene coverage is `needs-suite`; positive average FPS below the minimum suite threshold is `weak-throughput`; positive average FPS with a material scene throughput regression is `blocked-throughput`; positive average FPS with shader compile event or WebGPU pipeline-create timing regression is `blocked-shader-stalls`; positive average FPS with dropped-frame regression is `blocked-dropped-frames`; positive average FPS with CPU frame or render submission regression is `blocked-cpu-overhead`; positive average FPS with low-FPS or p95/p99 regression is `blocked-tail`; explicit profile-reuse wins are `cache-attribution` and require a matching fresh-profile official run before retained speed claims. Duplicate rows for the same family, profile-cache mode/key, and scene are collapsed to the most conservative representative row. Comparisons require the same build-args hash, platform, driver, GPU device identity, explicit benchmark complexity and explicit GPU-timing mode, WebGPU BundleGroup/render-bundle scene mode, WebGPU pipeline-instrumentation mode, requested resource warmup mode, resource precompile target count, preinitialized texture/render-target count, GPU-settle warmup mode, WebGPU pipeline-quiet warmup mode, and profile-cache mode/key while leaving backend choice available as an optimization variable. If multiple compatible stock baselines are present, the comparison uses the fastest valid stock baseline for that exact compatibility group. Accepted artifacts must report browser_is_from_checkout=true. Accepted artifacts must include positive package_size_mb evidence.

## Candidate Families

| Cohort | Renderer | Baseline | Candidate | Evidence | Profile Cache | Scenes | Status | Avg FPS Delta % | Min FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms | Startup Delta ms | RSS Delta MB |
| --- | --- | --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-default-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | weak-throughput | 0.36 | -0.00 | 0.67 | 5.48 | -0.01 | -2.39 | -0.14 | 0.00 | 0.00 | -0.10 | -0.10 | -166.1 | -4.4 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-aggressive-gpu-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | blocked-dropped-frames | 1.98 | -0.00 | 0.39 | 5.49 | -0.10 | 2.33 | -10.43 | 0.00 | 0.00 | -0.46 | -0.44 | -137.1 | -3.3 |
| official | webgl2 | baseline-content-shell | fork-viewer-default | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | not useful | -0.54 | -4.34 | 3.69 | 8.78 | 0.03 | -0.01 | -2.29 | 0.00 | 0.00 | -0.01 | -0.00 | -155.8 | -15.2 |
| official | webgl2 | baseline-content-shell | fork-viewer-aggressive-gpu-d3d11-relaxed | fresh-profile-evidence | fresh-temp/fresh-temp | 7 | not useful | -0.66 | -5.17 | 3.71 | 8.66 | 0.00 | -9.51 | -2.14 | 0.00 | 0.00 | 0.13 | 0.13 | -120.1 | -10.9 |

## Blocker Diagnostics

Primary blocker is the worst scene-level issue for each non-candidate family, so the next iteration can target the scene and metric that prevents retention.

| Cohort | Renderer | Candidate | Status | Blocking Scene | Primary Blocker | FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgpu | fork-viewer-default-webgpu | weak-throughput | suite average | avg FPS 0.36% below required 0.50% | 0.36 | 0.67 | 5.48 | -0.01 | -2.39 | -0.14 | 0.00 | 0.00 | -0.10 | -0.10 |
| official | webgpu | fork-viewer-aggressive-gpu-webgpu | blocked-dropped-frames | texture-streaming | dropped frames +17 | 8.03 | -0.19 | -0.33 | -0.30 | 16.50 | 17.00 | 0.00 | 0.00 | -1.19 | -1.07 |
| official | webgl2 | fork-viewer-default | not useful | texture-streaming | avg FPS -4.34% | -4.34 | 0.07 | 0.12 | 0.20 | 0.10 | -5.00 | 0.00 | 0.00 | 0.05 | 0.08 |
| official | webgl2 | fork-viewer-aggressive-gpu-d3d11-relaxed | not useful | texture-streaming | avg FPS -5.17% | -5.17 | 0.54 | 0.25 | 0.00 | -66.50 | -4.00 | 0.00 | 0.00 | 0.07 | 0.10 |

## Required Speedup Claim Gate

Required renderers: webgl2, webgpu
Status: fail

| Renderer | Candidate Families | Best Status | Best Candidate | Scenes | Avg FPS Delta % | Min FPS Delta % | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgl2 | 0 | not useful | fork-viewer-default | 7 | -0.54 | -4.34 | -0.01 | -2.29 | 0.00 | 0.00 |
| webgpu | 0 | weak-throughput | fork-viewer-default-webgpu | 7 | 0.36 | -0.00 | -2.39 | -0.14 | 0.00 | 0.00 |

Failures:
- webgl2: fork-viewer-default vs baseline-content-shell: status=not useful, scenes=7, avg_fps_delta_pct=-0.54, p99_delta_ms=-0.01
- webgpu: fork-viewer-default-webgpu vs baseline-content-shell-webgpu: status=weak-throughput, scenes=7, avg_fps_delta_pct=0.36, p99_delta_ms=-2.39

## Filtered Inputs

| Reason | Count |
| --- | ---: |
| None | 0 |

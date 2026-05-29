# Candidate Speed Analysis

Generated: 2026-05-28T22:20:15.702Z

Input results: 47
Input file digest: `272f6af3961554f500e02ac7a38ac52ed26193c8220a444daf132d7dc25e38fa`
Accepted results: 44
Filtered results: 3

Decision rule: a family is a `candidate` only when at least 7 distinct scenes are covered, all required scenes are present (many-draw-calls, instancing, shader-heavy, texture-streaming, postprocessing, large-static, gltf-loader-stress), average FPS improves by at least 0.50%, no individual scene has a material average-FPS regression, average low-FPS/tail-latency deltas do not materially regress, dropped frames do not increase by more than 0 on any scene, CPU frame time does not increase by more than 0.50 ms on any scene, render submission time does not increase by more than 0.50 ms on any scene, shader compile events do not increase by more than 0 on any scene, WebGPU measured-window pipeline creation time does not increase by more than 1.00 ms on any scene, required benchmark evidence fields, including explicit positive benchmark complexity and explicit GPU-timing mode, are present, stability artifacts are filtered out, viewer-side WebGPU queue attribution, viewer-side WebGPU command-encoder attribution, viewer-side WebGPU bind-group attribution, viewer-side WebGPU pipeline-state attribution, viewer-side WebGPU buffer-state attribution, viewer-side WebGPU render-state attribution, viewer-side WebGPU immediate-data attribution, and source-added WebGPU queue trace attribution runs are filtered out, explicit WebGPU CPU texture fallback/readback evidence and copyExternalImage upload experiments without CPU-fallback rejection are filtered out, trusted-only experiment metadata or browser flags require viewer_mode=true and viewer_trusted_content=true, WebGPU pipeline-quiet warmup runs are filtered out unless the requested quiet window was achieved and no pipelines were created during the measured window, and the result is fresh-profile evidence. Positive average FPS with incomplete scene coverage is `needs-suite`; positive average FPS below the minimum suite threshold is `weak-throughput`; positive average FPS with a material scene throughput regression is `blocked-throughput`; positive average FPS with shader compile event or WebGPU pipeline-create timing regression is `blocked-shader-stalls`; positive average FPS with dropped-frame regression is `blocked-dropped-frames`; positive average FPS with CPU frame or render submission regression is `blocked-cpu-overhead`; positive average FPS with low-FPS or p95/p99 regression is `blocked-tail`; explicit profile-reuse wins are `cache-attribution` and require a matching fresh-profile official run before retained speed claims. Duplicate rows for the same family, profile-cache mode/key, and scene are collapsed to the most conservative representative row. Comparisons require the same build-args hash, platform, driver, GPU device identity, explicit benchmark complexity and explicit GPU-timing mode, WebGPU BundleGroup/render-bundle scene mode, WebGPU pipeline-instrumentation mode, requested resource warmup mode, resource precompile target count, preinitialized texture/render-target count, GPU-settle warmup mode, WebGPU pipeline-quiet warmup mode, and profile-cache mode/key while leaving backend choice available as an optimization variable. If multiple compatible stock baselines are present, the comparison uses the fastest valid stock baseline for that exact compatibility group. Accepted artifacts must report browser_is_from_checkout=true. Accepted artifacts must include positive package_size_mb evidence.

## Baseline Selection

When multiple compatible stock baselines exist for the same exact renderer, scene, revision, duration, warmup, texture mode, GPU timing mode, WebGPU pipeline-instrumentation mode, profile-cache mode/key, and resource-warmup setting, this analyzer compares fork candidates against the fastest valid stock baseline. This is intentionally conservative for speedup claims.

| Cohort | Renderer | Scene | Baseline Family | Selected Baseline | Compatible Baselines |
| --- | --- | --- | --- | --- | --- |
| official | webgl2 | texture-streaming | strongest-compatible-baseline | baseline-content-shell-rerun | baseline-content-shell, baseline-content-shell-rerun |
| official | webgpu | texture-streaming | strongest-compatible-baseline | baseline-content-shell-webgpu-rerun-now | baseline-content-shell-webgpu, baseline-content-shell-webgpu-rerun-now |

## Candidate Families

| Cohort | Renderer | Baseline | Candidate | Evidence | Profile Cache | Scenes | Status | Avg FPS Delta % | Min FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms | Startup Delta ms | RSS Delta MB |
| --- | --- | --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-default-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 6 | needs-suite | 0.59 | -3.64 | 12.93 | 17.11 | 0.02 | 2.68 | 14.33 | 0.00 | 0.00 | 0.30 | 0.30 | -153.5 | 1.3 |
| official | webgl2 | strongest-compatible-baseline | fork-viewer-default | fresh-profile-evidence | fresh-temp/fresh-temp | 1 | needs-suite | 0.52 | 0.52 | 0.37 | 0.80 | -16.40 | 16.40 | 1.00 | 0.00 | 0.00 | -0.00 | 0.01 | -201.4 | -13.5 |
| official | webgl2 | baseline-content-shell | fork-viewer-default | fresh-profile-evidence | fresh-temp/fresh-temp | 6 | needs-suite | 0.02 | -0.00 | 1.11 | 9.53 | -0.02 | -0.02 | -0.33 | 0.00 | 0.00 | -0.06 | -0.06 | -228.5 | -9.7 |
| official | webgl2 | baseline-content-shell | fork-viewer-aggressive-gpu-d3d11-relaxed | fresh-profile-evidence | fresh-temp/fresh-temp | 6 | needs-suite | 0.02 | -0.00 | 1.01 | 8.77 | 0.00 | -0.02 | -0.33 | 0.00 | 0.00 | -0.11 | -0.11 | -166.2 | -9.8 |
| official | webgpu | strongest-compatible-baseline | fork-viewer-aggressive-gpu-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 1 | not useful | -0.39 | -0.39 | -0.00 | 0.00 | 0.00 | 0.10 | -1.00 | 0.00 | 0.00 | -0.19 | -0.17 | -800.7 | 0.1 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-aggressive-gpu-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 6 | not useful | -2.29 | -22.05 | 11.60 | 17.84 | 0.03 | 5.40 | 54.00 | 0.00 | 0.00 | 0.89 | 0.88 | 306.3 | -11.3 |
| official | webgl2 | strongest-compatible-baseline | fork-viewer-aggressive-gpu-d3d11-relaxed | fresh-profile-evidence | fresh-temp/fresh-temp | 1 | not useful | -10.21 | -10.21 | -0.08 | 0.00 | 16.90 | 33.20 | -12.00 | 0.00 | 0.00 | 0.30 | 0.26 | -94.8 | -14.2 |
| official | webgpu | strongest-compatible-baseline | fork-viewer-default-webgpu | fresh-profile-evidence | fresh-temp/fresh-temp | 1 | not useful | -16.12 | -16.12 | -2.25 | -2.25 | 33.50 | 66.60 | -37.00 | 0.00 | 0.00 | 1.47 | 1.32 | -843.2 | -22.9 |

## Blocker Diagnostics

Primary blocker is the worst scene-level issue for each non-candidate family, so the next iteration can target the scene and metric that prevents retention.

| Cohort | Renderer | Candidate | Status | Blocking Scene | Primary Blocker | FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms | CPU Delta ms | Submit Delta ms |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| official | webgpu | fork-viewer-default-webgpu | needs-suite | missing 1/7 | needs required scene(s): texture-streaming | 0.59 | 12.93 | 17.11 | 0.02 | 2.68 | 14.33 | 0.00 | 0.00 | 0.30 | 0.30 |
| official | webgl2 | fork-viewer-default | needs-suite | missing 6/7 | needs required scene(s): many-draw-calls, instancing, shader-heavy, postprocessing, large-static, gltf-loader-stress | 0.52 | 0.37 | 0.80 | -16.40 | 16.40 | 1.00 | 0.00 | 0.00 | -0.00 | 0.01 |
| official | webgl2 | fork-viewer-default | needs-suite | missing 1/7 | needs required scene(s): texture-streaming | 0.02 | 1.11 | 9.53 | -0.02 | -0.02 | -0.33 | 0.00 | 0.00 | -0.06 | -0.06 |
| official | webgl2 | fork-viewer-aggressive-gpu-d3d11-relaxed | needs-suite | missing 1/7 | needs required scene(s): texture-streaming | 0.02 | 1.01 | 8.77 | 0.00 | -0.02 | -0.33 | 0.00 | 0.00 | -0.11 | -0.11 |
| official | webgpu | fork-viewer-aggressive-gpu-webgpu | not useful | texture-streaming | avg FPS -0.39% | -0.39 | -0.00 | 0.00 | 0.00 | 0.10 | -1.00 | 0.00 | 0.00 | -0.19 | -0.17 |
| official | webgpu | fork-viewer-aggressive-gpu-webgpu | not useful | many-draw-calls | avg FPS -22.05% | -22.05 | -9.81 | -9.84 | 0.20 | 16.50 | 318.00 | 0.00 | 0.00 | 5.50 | 5.44 |
| official | webgl2 | fork-viewer-aggressive-gpu-d3d11-relaxed | not useful | texture-streaming | avg FPS -10.21% | -10.21 | -0.08 | 0.00 | 16.90 | 33.20 | -12.00 | 0.00 | 0.00 | 0.30 | 0.26 |
| official | webgpu | fork-viewer-default-webgpu | not useful | texture-streaming | avg FPS -16.12% | -16.12 | -2.25 | -2.25 | 33.50 | 66.60 | -37.00 | 0.00 | 0.00 | 1.47 | 1.32 |

## Required Speedup Claim Gate

Required renderers: webgl2, webgpu
Status: fail

| Renderer | Candidate Families | Best Status | Best Candidate | Scenes | Avg FPS Delta % | Min FPS Delta % | P99 Delta ms | Dropped Frames Delta | Shader Events Delta | Pipeline Create Delta ms |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgl2 | 0 | needs-suite | fork-viewer-default | 1 | 0.52 | 0.52 | 16.40 | 1.00 | 0.00 | 0.00 |
| webgpu | 0 | needs-suite | fork-viewer-default-webgpu | 6 | 0.59 | -3.64 | 2.68 | 14.33 | 0.00 | 0.00 |

Failures:
- webgl2: fork-viewer-default vs strongest-compatible-baseline: status=needs-suite, scenes=1, avg_fps_delta_pct=0.52, p99_delta_ms=16.40
- webgpu: fork-viewer-default-webgpu vs baseline-content-shell-webgpu: status=needs-suite, scenes=6, avg_fps_delta_pct=0.59, p99_delta_ms=2.68

## Filtered Inputs

| Reason | Count |
| --- | ---: |
| stability benchmark artifact | 3 |

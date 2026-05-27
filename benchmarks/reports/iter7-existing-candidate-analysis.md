# Candidate Speed Analysis

Generated: 2026-05-22T13:28:33.116Z

Input results: 413
Accepted results: 159
Filtered results: 254

Decision rule: a family is a `candidate` only when at least 7 scenes are covered, average FPS improves, no individual scene has a material average-FPS regression, and average low-FPS/tail-latency deltas do not materially regress. Positive average FPS with fewer scenes is `needs-suite`; positive average FPS with a material scene throughput regression is `blocked-throughput`; positive average FPS with low-FPS or p95/p99 regression is `blocked-tail`, not retained evidence.

## Candidate Families

| Cohort | Renderer | Baseline | Candidate | Scenes | Status | Avg FPS Delta % | Min FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | CPU Delta ms | Submit Delta ms | Startup Delta ms | RSS Delta MB |
| --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| iter3 | webgl2 | iter3-baseline-c2 | iter3-fork-relaxed-zerocopy-c2 | 1 | needs-suite | 0.17 | 0.17 | 0.53 | 0.08 | -6.60 | -0.10 | 0.01 | 0.00 | -220.8 | -10.2 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-default-c2-notiming | 7 | blocked-throughput | 0.21 | -1.20 | -3.06 | -1.94 | -2.01 | -8.97 | 0.04 | 0.05 | -102.0 | -7.9 |
| iter3 | webgl2 | iter3-baseline-c2 | iter3-fork-zerocopy-only-c2 | 7 | blocked-tail | 1.48 | -0.02 | -0.28 | -3.91 | 11.93 | 2.00 | -0.20 | -0.18 | -194.1 | 9.3 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-singleprocess-c2-notiming | 7 | not useful | -0.09 | -5.03 | -8.01 | -5.36 | 3.91 | -2.01 | 0.34 | 0.32 | -344.8 | -326.3 |
| official | webgl2 | baseline-content-shell | fork-viewer-default | 7 | not useful | -1.30 | -3.80 | 1.06 | 0.41 | -19.83 | -28.77 | -0.06 | -0.05 | -220.3 | 10.4 |
| official | webgl2 | baseline-content-shell | fork-viewer-aggressive-gpu-d3d11 | 7 | not useful | -1.92 | -5.12 | 1.14 | 0.48 | -17.84 | -29.81 | -0.04 | -0.04 | -163.4 | -6.6 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-inprocess-c2-notiming | 3 | not useful | -3.05 | -18.40 | 1.14 | 1.34 | 23.10 | 3.73 | -0.44 | -0.47 | -473.3 | -76.7 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-singleprocess-zerocopy-c2-notiming | 2 | not useful | -5.06 | -6.44 | -1.64 | -1.29 | 3.40 | -24.35 | 2.32 | 2.24 | -204.6 | -321.8 |
| iter3 | webgl2 | iter3-baseline-c2 | iter3-fork-relaxed-only-c2 | 1 | not useful | -7.69 | -7.69 | -4.90 | -4.61 | 0.20 | 6.80 | 1.50 | 1.47 | -74.1 | -13.3 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-zerocopy-only-c2-notiming | 1 | not useful | -11.88 | -11.88 | -0.50 | -0.50 | 83.50 | 97.20 | 7.83 | 7.55 | 47.7 | -4.1 |
| official | webgl2 | baseline-content-shell-long-stability | fork-viewer-default-long-stability | 2 | not useful | -19.90 | -39.79 | -0.79 | -0.40 | 31.15 | 27.85 | 0.00 | 0.00 | -117.4 | -11.7 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-aggressive-gpu-d3d11-webgpu | 5 | not useful | -21.44 | -46.45 | -0.15 | 0.13 | 5.54 | 190.32 | 0.45 | 0.45 | 145.7 | -26.0 |
| official | webgpu | baseline-content-shell-webgpu | fork-viewer-default-webgpu | 7 | not useful | -24.56 | -57.29 | -0.13 | 0.00 | 1.00 | 135.91 | 0.22 | 0.22 | -12.5 | -15.3 |

## Blocker Diagnostics

Primary blocker is the worst scene-level issue for each non-candidate family, so the next iteration can target the scene and metric that prevents retention.

| Cohort | Renderer | Candidate | Status | Blocking Scene | Primary Blocker | FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| iter3 | webgl2 | iter3-fork-relaxed-zerocopy-c2 | needs-suite | coverage 1/7 | needs 6 more comparable scene(s) | 0.17 | 0.53 | 0.08 | -6.60 | -0.10 |
| iter3 | webgpu | iter3-fork-default-c2-notiming | blocked-throughput | gltf-loader-stress | avg FPS -1.20% | -1.20 | 0.27 | 2.81 | 0.00 | -0.00 |
| iter3 | webgl2 | iter3-fork-zerocopy-only-c2 | blocked-tail | postprocessing | 0.1% low -29.28 FPS | -0.02 | -3.98 | -29.28 | 0.00 | 0.00 |
| iter3 | webgpu | iter3-fork-singleprocess-c2-notiming | not useful | texture-streaming | avg FPS -5.03% | -5.03 | 0.06 | 0.06 | 27.90 | -7.10 |
| official | webgl2 | fork-viewer-default | not useful | postprocessing | avg FPS -3.80% | -3.80 | 0.61 | 0.05 | -20.80 | -27.90 |
| official | webgl2 | fork-viewer-aggressive-gpu-d3d11 | not useful | gltf-loader-stress | avg FPS -5.12% | -5.12 | 0.90 | -0.41 | -20.80 | -34.60 |
| iter3 | webgpu | iter3-fork-inprocess-c2-notiming | not useful | texture-streaming | avg FPS -18.40% | -18.40 | 0.41 | 0.41 | 69.40 | 13.80 |
| iter3 | webgpu | iter3-fork-singleprocess-zerocopy-c2-notiming | not useful | many-draw-calls | avg FPS -6.44% | -6.44 | -3.45 | -2.75 | 6.80 | 6.90 |
| iter3 | webgl2 | iter3-fork-relaxed-only-c2 | not useful | many-draw-calls | avg FPS -7.69% | -7.69 | -4.90 | -4.61 | 0.20 | 6.80 |
| iter3 | webgpu | iter3-fork-zerocopy-only-c2-notiming | not useful | texture-streaming | avg FPS -11.88% | -11.88 | -0.50 | -0.50 | 83.50 | 97.20 |
| official | webgl2 | fork-viewer-default-long-stability | not useful | instancing | avg FPS -39.79% | -39.79 | -1.58 | -0.81 | 62.30 | 55.70 |
| official | webgpu | fork-viewer-aggressive-gpu-d3d11-webgpu | not useful | large-static | avg FPS -46.45% | -46.45 | -0.99 | -0.11 | 6.80 | 7.00 |
| official | webgpu | fork-viewer-default-webgpu | not useful | large-static | avg FPS -57.29% | -57.29 | -1.08 | -0.10 | 0.10 | 13.70 |

## Required Speedup Claim Gate

Required renderers: webgl2, webgpu
Status: fail

| Renderer | Candidate Families | Best Status | Best Candidate | Scenes | Avg FPS Delta % | Min FPS Delta % | P99 Delta ms |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: |
| webgl2 | 0 | needs-suite | iter3-fork-relaxed-zerocopy-c2 | 1 | 0.17 | 0.17 | -0.10 |
| webgpu | 0 | blocked-throughput | iter3-fork-default-c2-notiming | 7 | 0.21 | -1.20 | -8.97 |

Failures:
- webgl2: iter3-fork-relaxed-zerocopy-c2 vs iter3-baseline-c2: status=needs-suite, scenes=1, avg_fps_delta_pct=0.17, p99_delta_ms=-0.10
- webgpu: iter3-fork-default-c2-notiming vs iter3-baseline-c2-notiming: status=blocked-throughput, scenes=7, avg_fps_delta_pct=0.21, p99_delta_ms=-8.97

## Filtered Inputs

| Reason | Count |
| --- | ---: |
| measured_seconds 10 below 30 | 130 |
| measured_seconds 1 below 30 | 39 |
| fork_revision does not identify viewer patch | 28 |
| measured_seconds 2 below 30 | 18 |
| diagnostic texture_upload_mode=data | 8 |
| measured_seconds 20 below 30 | 6 |
| missing avg_fps | 6 |
| measured_seconds 5 below 30 | 5 |
| measured_seconds 15 below 30 | 4 |
| queue instrumentation attribution run | 4 |
| measured_seconds 3 below 30 | 3 |
| WebGPU device loss | 2 |
| WebGL context loss count 1 | 1 |

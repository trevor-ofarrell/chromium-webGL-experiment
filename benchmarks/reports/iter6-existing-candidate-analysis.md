# Candidate Speed Analysis

Generated: 2026-05-22T10:09:18.199Z

Input results: 44
Accepted results: 43
Filtered results: 1

Decision rule: a family is a `candidate` only when at least 7 scenes are covered, average FPS improves, no individual scene has a material average-FPS regression, and average low-FPS/tail-latency deltas do not materially regress. Positive average FPS with fewer scenes is `needs-suite`; positive average FPS with a material scene throughput regression is `blocked-throughput`; positive average FPS with low-FPS or p95/p99 regression is `blocked-tail`, not retained evidence.

## Candidate Families

| Cohort | Renderer | Baseline | Candidate | Scenes | Status | Avg FPS Delta % | Min FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms | CPU Delta ms | Submit Delta ms | Startup Delta ms | RSS Delta MB |
| --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| iter3 | webgl2 | iter3-baseline-c2 | iter3-fork-relaxed-zerocopy-c2 | 1 | needs-suite | 0.17 | 0.17 | 0.53 | 0.08 | -6.60 | -0.10 | 0.01 | 0.00 | -220.8 | -10.2 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-default-c2-notiming | 7 | blocked-throughput | 0.21 | -1.20 | -3.06 | -1.94 | -2.01 | -8.97 | 0.04 | 0.05 | -102.0 | -7.9 |
| iter3 | webgl2 | iter3-baseline-c2 | iter3-fork-zerocopy-only-c2 | 7 | blocked-tail | 1.48 | -0.02 | -0.28 | -3.91 | 11.93 | 2.00 | -0.20 | -0.18 | -194.1 | 9.3 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-singleprocess-c2-notiming | 7 | not useful | -0.09 | -5.03 | -8.01 | -5.36 | 3.91 | -2.01 | 0.34 | 0.32 | -344.8 | -326.3 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-inprocess-c2-notiming | 3 | not useful | -3.05 | -18.40 | 1.14 | 1.34 | 23.10 | 3.73 | -0.44 | -0.47 | -473.3 | -76.7 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-singleprocess-zerocopy-c2-notiming | 2 | not useful | -5.06 | -6.44 | -1.64 | -1.29 | 3.40 | -24.35 | 2.32 | 2.24 | -204.6 | -321.8 |
| iter3 | webgl2 | iter3-baseline-c2 | iter3-fork-relaxed-only-c2 | 1 | not useful | -7.69 | -7.69 | -4.90 | -4.61 | 0.20 | 6.80 | 1.50 | 1.47 | -74.1 | -13.3 |
| iter3 | webgpu | iter3-baseline-c2-notiming | iter3-fork-zerocopy-only-c2-notiming | 1 | not useful | -11.88 | -11.88 | -0.50 | -0.50 | 83.50 | 97.20 | 7.83 | 7.55 | 47.7 | -4.1 |

## Blocker Diagnostics

Primary blocker is the worst scene-level issue for each non-candidate family, so the next iteration can target the scene and metric that prevents retention.

| Cohort | Renderer | Candidate | Status | Blocking Scene | Primary Blocker | FPS Delta % | 1% Low Delta | 0.1% Low Delta | P95 Delta ms | P99 Delta ms |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| iter3 | webgl2 | iter3-fork-relaxed-zerocopy-c2 | needs-suite | coverage 1/7 | needs 6 more comparable scene(s) | 0.17 | 0.53 | 0.08 | -6.60 | -0.10 |
| iter3 | webgpu | iter3-fork-default-c2-notiming | blocked-throughput | gltf-loader-stress | avg FPS -1.20% | -1.20 | 0.27 | 2.81 | 0.00 | -0.00 |
| iter3 | webgl2 | iter3-fork-zerocopy-only-c2 | blocked-tail | postprocessing | 0.1% low -29.28 FPS | -0.02 | -3.98 | -29.28 | 0.00 | 0.00 |
| iter3 | webgpu | iter3-fork-singleprocess-c2-notiming | not useful | texture-streaming | avg FPS -5.03% | -5.03 | 0.06 | 0.06 | 27.90 | -7.10 |
| iter3 | webgpu | iter3-fork-inprocess-c2-notiming | not useful | texture-streaming | avg FPS -18.40% | -18.40 | 0.41 | 0.41 | 69.40 | 13.80 |
| iter3 | webgpu | iter3-fork-singleprocess-zerocopy-c2-notiming | not useful | many-draw-calls | avg FPS -6.44% | -6.44 | -3.45 | -2.75 | 6.80 | 6.90 |
| iter3 | webgl2 | iter3-fork-relaxed-only-c2 | not useful | many-draw-calls | avg FPS -7.69% | -7.69 | -4.90 | -4.61 | 0.20 | 6.80 |
| iter3 | webgpu | iter3-fork-zerocopy-only-c2-notiming | not useful | texture-streaming | avg FPS -11.88% | -11.88 | -0.50 | -0.50 | 83.50 | 97.20 |

## Filtered Inputs

| Reason | Count |
| --- | ---: |
| WebGL context loss count 1 | 1 |

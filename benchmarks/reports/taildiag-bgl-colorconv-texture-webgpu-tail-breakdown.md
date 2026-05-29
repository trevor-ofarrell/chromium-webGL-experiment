# Tail Breakdown: texture-streaming / webgpu

Baseline: `benchmarks\raw\baseline-content-shell-webgpu-taildiag-bgl-colorconv-texture-streaming-webgpu.json`
Candidate: `benchmarks\raw\fork-viewer-exp-webgpu-taildiag-bgl-colorconv-texture-streaming-webgpu.json`

Average FPS delta: -10.512%
Worst p99 delta series: frame_times_ms (99.800 ms)

| Series | Samples | Avg delta ms | p50 delta ms | p95 delta ms | p99 delta ms | Max delta ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Frame | 115 -> 103 | 20.172 | 16.500 | 66.600 | 99.800 | 83.400 |
| CPU frame | 116 -> 104 | 1.267 | 0.400 | 5.000 | 6.500 | 8.400 |
| JS/update | 116 -> 104 | 0.055 | 0.100 | 0.000 | 0.100 | -0.400 |
| Render submission | 116 -> 104 | 1.205 | 0.400 | 5.100 | 6.300 | 7.800 |
| GPU frame | n/a | n/a | n/a | n/a | n/a | n/a |

Positive millisecond deltas mean the candidate is slower for that timing series.

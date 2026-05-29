# Benchmark Summary

Generated from 9 result file(s).
Input file digest: `d22b927058aab1c172dc0b2d2db6502c8ff2b8273b536703b219fbaeb97d82a4`
Strict summary evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, positive package-size evidence, and no attribution instrumentation before this report is written.

| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| texture-streaming | webgl2 | fork-viewer-exp-angle-d3d11 | 7.5 | 2.6 | 2.5 | 16.90 | 266.80 | 283.40 | 399.90 | 5.25 | 133.764 | 1.008 | 4.19 |  |  | 110 | 96 | 192 | 3500.2 | 0.0 | 0 | 5.3 |  | 432 | 518 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-exp-angle-d3d11-relaxed-webgl-validation | 7.4 | 2.4 | 2.4 | 16.90 | 283.30 | 300.10 | 416.70 | 5.15 | 134.050 | 1.010 | 4.10 |  |  | 109 | 96 | 192 | 3486.8 | 0.0 | 0 | 5.6 |  | 430 | 545 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy | 7.6 | 3.1 | 2.7 | 16.90 | 266.70 | 283.40 | 366.60 | 4.98 | 132.050 | 0.959 | 3.98 |  |  | 112 | 96 | 192 | 3526.9 | 0.0 | 0 | 5.4 |  | 434 | 511 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-exp-angle-d3d11-zero-copy | 7.5 | 3.5 | 3.5 | 16.90 | 266.70 | 266.90 | 283.50 | 4.98 | 132.204 | 0.958 | 3.97 |  |  | 112 | 96 | 192 | 3513.5 | 0.0 | 0 | 6.0 |  | 429 | 513 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-exp-default | 7.7 | 2.8 | 2.6 | 16.90 | 266.60 | 283.30 | 383.30 | 5.01 | 129.727 | 0.971 | 4.00 |  |  | 114 | 96 | 192 | 3607.0 | 0.0 | 0 | 5.3 |  | 434 | 580 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-exp-relaxed-webgl-validation-gate | 7.6 | 2.7 | 2.6 | 16.90 | 266.70 | 283.40 | 383.30 | 5.08 | 132.053 | 0.955 | 4.09 |  |  | 110 | 96 | 192 | 3526.9 | 0.0 | 0 | 5.4 |  | 431 | 542 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-exp-webgl2-gpu-compositor-resources | 7.4 | 2.4 | 2.4 | 16.90 | 267.00 | 299.90 | 416.70 | 5.02 | 133.050 | 0.964 | 4.02 |  |  | 110 | 96 | 192 | 3473.4 | 0.0 | 0 | 5.3 |  | 432 | 520 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources | 7.3 | 3.0 | 2.7 | 16.90 | 283.40 | 300.00 | 366.70 | 5.37 | 137.905 | 1.031 | 4.30 |  |  | 106 | 96 | 192 | 3246.3 | 0.0 | 0 | 5.2 |  | 438 | 846 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-exp-zero-copy | 7.5 | 2.6 | 2.6 | 16.90 | 266.70 | 283.50 | 383.30 | 5.16 | 132.698 | 1.005 | 4.11 |  |  | 109 | 96 | 192 | 3513.5 | 0.0 | 0 | 5.9 |  | 432 | 536 | 201.5 | 1.4 | 452.0 |

## WebGPU Fast-Path Coverage

These counters are diagnostic attribution only. They show whether WebGPU queue and pipeline descriptors match source fast paths; they are not standalone speed evidence.

| Scene | Renderer | Variant | WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| texture-streaming | webgl2 | fork-viewer-exp-angle-d3d11 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-exp-angle-d3d11-relaxed-webgl-validation | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-exp-angle-d3d11-zero-copy | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-exp-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-exp-relaxed-webgl-validation-gate | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-exp-webgl2-gpu-compositor-resources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-exp-zero-copy | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Unavailable metrics are intentionally blank.

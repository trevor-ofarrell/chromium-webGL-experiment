# Benchmark Summary

Generated from 7 result file(s).
Input file digest: `f2b5c649db033c80677cc16925d6dd39bc05d7b71ab13ff9db99a286b65e058e`
Strict summary evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, positive package-size evidence, and no attribution instrumentation before this report is written.

| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgl2 | baseline-content-shell | 60.0 | 55.7 | 30.4 | 16.70 | 16.90 | 17.00 | 32.90 | 6.38 | 0.878 | 0.166 | 6.19 |  |  | 1 | 2944.017787659811 | 35328.213451917734 | 0.0 | 0.0 | 0 | 12.2 |  | 414 | 735 | 201.4 | 1.4 | 644.0 |
| instancing | webgl2 | baseline-content-shell | 60.0 | 58.8 | 58.1 | 16.70 | 16.90 | 16.90 | 17.20 | 0.15 | 2.153 | 0.017 | 0.12 |  |  | 0 | 1 | 1560000 | 0.0 | 9.4 | 0 | 14.0 |  | 413 | 805 | 201.4 | 1.4 | 644.0 |
| large-static | webgl2 | baseline-content-shell | 60.0 | 58.5 | 57.1 | 16.70 | 16.90 | 17.00 | 17.50 | 0.15 | 0.626 | 0.015 | 0.11 |  |  | 0 | 1 | 518162 | 0.0 | 14.9 | 0 | 19.3 |  | 432 | 800 | 201.4 | 1.4 | 644.0 |
| many-draw-calls | webgl2 | baseline-content-shell | 60.0 | 55.8 | 30.0 | 16.70 | 16.90 | 16.90 | 33.30 | 10.53 | 1.636 | 0.265 | 10.23 |  |  | 1 | 4059.518888888889 | 48714.22666666667 | 0.0 | 0.6 | 0 | 17.2 |  | 425 | 778 | 201.4 | 1.4 | 644.0 |
| postprocessing | webgl2 | baseline-content-shell | 60.0 | 59.1 | 58.8 | 16.70 | 16.90 | 16.90 | 17.00 | 0.21 | 2.276 | 0.020 | 0.17 |  |  | 0 | 2 | 22528002 | 0.0 | 2.7 | 0 | 7.6 |  | 404 | 791 | 201.4 | 1.4 | 644.0 |
| shader-heavy | webgl2 | baseline-content-shell | 60.0 | 58.4 | 56.8 | 16.70 | 16.90 | 17.00 | 17.60 | 0.14 | 0.028 | 0.021 | 0.10 |  |  | 0 | 1 | 720 | 0.0 | 0.0 | 0 | 4.5 |  | 389 | 687 | 201.4 | 1.4 | 644.0 |
| texture-streaming | webgl2 | baseline-content-shell | 6.9 | 1.5 | 1.5 | 17.20 | 283.40 | 566.60 | 683.30 | 5.43 | 144.604 | 1.038 | 4.35 |  |  | 102 | 96 | 192 | 3259.7 | 0.0 | 0 | 5.2 |  | 441 | 735 | 201.4 | 1.4 | 644.0 |

## WebGPU Fast-Path Coverage

These counters are diagnostic attribution only. They show whether WebGPU queue and pipeline descriptors match source fast paths; they are not standalone speed evidence.

| Scene | Renderer | Variant | WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgl2 | baseline-content-shell | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| instancing | webgl2 | baseline-content-shell | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| large-static | webgl2 | baseline-content-shell | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| many-draw-calls | webgl2 | baseline-content-shell | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| postprocessing | webgl2 | baseline-content-shell | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| shader-heavy | webgl2 | baseline-content-shell | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | baseline-content-shell | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Unavailable metrics are intentionally blank.

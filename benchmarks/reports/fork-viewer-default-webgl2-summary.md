# Benchmark Summary

Generated from 7 result file(s).
Input file digest: `60698a3c673cdd97c398c28ede6217bbf27e94cd36c096ea4c277d82b8bc796f`
Strict summary evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, positive package-size evidence, and no attribution instrumentation before this report is written.

| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgl2 | fork-viewer-default | 60.0 | 58.7 | 58.1 | 16.70 | 16.90 | 17.00 | 17.20 | 5.60 | 0.892 | 0.155 | 5.42 |  |  | 0 | 2941.9133333333334 | 35302.96 | 0.0 | 0.0 | 0 | 15.9 |  | 404 | 488 | 201.5 | 1.4 | 452.0 |
| instancing | webgl2 | fork-viewer-default | 60.0 | 58.7 | 57.1 | 16.70 | 16.90 | 16.90 | 17.50 | 0.16 | 2.071 | 0.017 | 0.12 |  |  | 0 | 1 | 1560000 | 0.0 | 9.4 | 0 | 14.0 |  | 405 | 604 | 201.5 | 1.4 | 452.0 |
| large-static | webgl2 | fork-viewer-default | 60.0 | 58.8 | 58.5 | 16.70 | 16.90 | 17.00 | 17.10 | 0.14 | 0.626 | 0.014 | 0.10 |  |  | 0 | 1 | 518162 | 0.0 | 14.9 | 0 | 19.3 |  | 422 | 534 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgl2 | fork-viewer-default | 60.0 | 58.9 | 58.5 | 16.70 | 16.90 | 16.90 | 17.10 | 11.00 | 2.235 | 0.289 | 10.68 |  |  | 0 | 4049.2744444444443 | 48591.293333333335 | 0.0 | 0.6 | 0 | 14.3 |  | 409 | 587 | 201.5 | 1.4 | 452.0 |
| postprocessing | webgl2 | fork-viewer-default | 60.0 | 59.0 | 58.8 | 16.70 | 16.80 | 16.90 | 17.00 | 0.19 | 2.336 | 0.018 | 0.16 |  |  | 0 | 2 | 22528002 | 0.0 | 2.7 | 0 | 7.5 |  | 399 | 527 | 201.5 | 1.4 | 452.0 |
| shader-heavy | webgl2 | fork-viewer-default | 60.0 | 58.8 | 57.5 | 16.70 | 16.90 | 16.90 | 17.40 | 0.14 | 0.026 | 0.019 | 0.10 |  |  | 0 | 1 | 720 | 0.0 | 0.0 | 0 | 4.6 |  | 380 | 486 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgl2 | fork-viewer-default | 8.3 | 3.5 | 3.5 | 17.00 | 233.50 | 266.60 | 283.40 | 4.79 | 119.716 | 0.931 | 3.83 |  |  | 123 | 96 | 192 | 3887.6 | 0.0 | 0 | 5.8 |  | 430 | 504 | 201.5 | 1.4 | 452.0 |

## WebGPU Fast-Path Coverage

These counters are diagnostic attribution only. They show whether WebGPU queue and pipeline descriptors match source fast paths; they are not standalone speed evidence.

| Scene | Renderer | Variant | WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgl2 | fork-viewer-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| instancing | webgl2 | fork-viewer-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| large-static | webgl2 | fork-viewer-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| many-draw-calls | webgl2 | fork-viewer-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| postprocessing | webgl2 | fork-viewer-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| shader-heavy | webgl2 | fork-viewer-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| texture-streaming | webgl2 | fork-viewer-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Unavailable metrics are intentionally blank.

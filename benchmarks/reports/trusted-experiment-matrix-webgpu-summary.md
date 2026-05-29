# Benchmark Summary

Generated from 7 result file(s).
Input file digest: `fd065a410dd0aaa4b5859e95022ff84c5604a8dda1fe154aa55c2b7f19c1a99d`
Strict summary evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, positive package-size evidence, and no attribution instrumentation before this report is written.

| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 60.0 | 55.7 | 30.3 | 16.70 | 16.90 | 16.90 | 33.00 | 13.27 |  | 0.208 | 13.06 |  |  | 1 | 2328 | 35296.56197887715 | 0.0 | 0.0 | 0 | 36.3 |  | 582 | 1115 | 201.5 | 1.4 | 452.0 |
| instancing | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 60.0 | 58.4 | 57.1 | 16.70 | 16.80 | 17.00 | 17.50 | 0.64 |  | 0.029 | 0.60 |  |  | 0 | 2331 | 1560001 | 0.0 | 9.4 | 0 | 17.9 |  | 528 | 1037 | 201.5 | 1.4 | 452.0 |
| large-static | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 60.0 | 58.0 | 54.9 | 16.70 | 16.90 | 17.00 | 18.20 | 0.61 |  | 0.027 | 0.58 |  |  | 0 | 2337 | 518163 | 0.0 | 14.9 | 0 | 22.3 |  | 528 | 1098 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 44.3 | 25.0 | 19.9 | 16.80 | 33.50 | 33.60 | 50.20 | 21.98 |  | 0.288 | 21.68 |  |  | 464 | 1672 | 48567.07674943566 | 0.0 | 0.6 | 0 | 100.7 |  | 654 | 1331 | 201.5 | 1.4 | 452.0 |
| postprocessing | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 60.0 | 57.8 | 54.9 | 16.70 | 16.90 | 17.10 | 18.20 | 0.85 |  | 0.033 | 0.81 |  |  | 0 | 3523.5 | 22528003 | 0.0 | 2.7 | 0 | 11.7 |  | 508 | 842 | 201.5 | 1.4 | 452.0 |
| shader-heavy | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 60.0 | 58.8 | 58.5 | 16.70 | 16.90 | 16.90 | 17.10 | 0.57 |  | 0.029 | 0.53 |  |  | 0 | 2377 | 721 | 0.0 | 0.0 | 0 | 8.3 |  | 489 | 767 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 5.6 | 4.0 | 4.0 | 183.20 | 216.80 | 233.40 | 250.10 | 17.19 |  | 1.277 | 15.89 |  |  | 167 | 229 | 193 | 2645.2 | 0.0 | 0 | 7.9 |  | 540 | 850 | 201.5 | 1.4 | 452.0 |

## WebGPU Fast-Path Coverage

These counters are diagnostic attribution only. They show whether WebGPU queue and pipeline descriptors match source fast paths; they are not standalone speed evidence.

| Scene | Renderer | Variant | WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| instancing | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| large-static | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| postprocessing | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| shader-heavy | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |

Unavailable metrics are intentionally blank.

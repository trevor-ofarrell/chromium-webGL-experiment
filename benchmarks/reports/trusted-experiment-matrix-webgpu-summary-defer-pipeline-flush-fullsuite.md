# Benchmark Summary

Generated from 7 result file(s).
Input file digest: `4b3b0197f2a9040387eb6d143f7bec31849693e33dce1ecbf26ccd2cb4e29133`
Strict summary evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, positive package-size evidence, and no attribution instrumentation before this report is written.

| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 59.4 | 29.9 | 29.8 | 16.70 | 16.90 | 33.20 | 33.60 | 14.36 |  | 0.208 | 14.15 |  |  | 19 | 2297 | 35297.38876404495 | 0.0 | 0.0 | 0 | 47.5 |  | 591 | 1018 | 201.5 | 1.4 | 452.0 |
| instancing | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 60.0 | 57.6 | 52.9 | 16.70 | 16.90 | 17.00 | 18.90 | 0.66 |  | 0.030 | 0.62 |  |  | 0 | 2345 | 1560001 | 0.0 | 9.4 | 0 | 18.3 |  | 533 | 876 | 201.5 | 1.4 | 452.0 |
| large-static | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 60.0 | 58.1 | 51.0 | 16.70 | 16.90 | 17.00 | 19.60 | 0.59 |  | 0.024 | 0.56 |  |  | 0 | 2345 | 518163 | 0.0 | 14.9 | 0 | 22.6 |  | 521 | 870 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 46.1 | 25.9 | 20.0 | 16.80 | 33.40 | 33.60 | 50.10 | 21.13 |  | 0.267 | 20.86 |  |  | 413 | 1672 | 48567.69848156182 | 0.0 | 0.6 | 0 | 36.8 |  | 620 | 1646 | 201.5 | 1.4 | 452.0 |
| postprocessing | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 60.0 | 58.3 | 56.2 | 16.70 | 16.90 | 17.00 | 17.80 | 0.71 |  | 0.026 | 0.68 |  |  | 0 | 3529.5 | 22528003 | 0.0 | 2.7 | 0 | 11.9 |  | 506 | 751 | 201.5 | 1.4 | 452.0 |
| shader-heavy | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 60.0 | 58.4 | 57.5 | 16.70 | 16.90 | 17.00 | 17.40 | 0.58 |  | 0.032 | 0.54 |  |  | 0 | 2373 | 721 | 0.0 | 0.0 | 0 | 8.3 |  | 497 | 745 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 5.6 | 3.7 | 3.7 | 166.70 | 233.60 | 250.00 | 266.90 | 16.77 |  | 1.276 | 15.47 |  |  | 167 | 229 | 193 | 2645.2 | 0.0 | 0 | 7.6 |  | 541 | 5168 | 201.5 | 1.4 | 452.0 |

## WebGPU Fast-Path Coverage

These counters are diagnostic attribution only. They show whether WebGPU queue and pipeline descriptors match source fast paths; they are not standalone speed evidence.

| Scene | Renderer | Variant | WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| instancing | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| large-static | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| postprocessing | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| shader-heavy | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush-fullsuite | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |

Unavailable metrics are intentionally blank.

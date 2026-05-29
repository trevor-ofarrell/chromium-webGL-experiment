# Benchmark Summary

Generated from 30 result file(s).
Input file digest: `ad020e04ec1384a1a5506c48440baeadacbefd9bb49f8b4c1532db9d96575636`
Strict summary evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, positive package-size evidence, and no attribution instrumentation before this report is written.

| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgpu | fork-viewer-exp-default-texturetriage | 60.0 | 58.8 | 58.1 | 16.70 | 16.90 | 16.90 | 17.20 | 12.54 |  | 0.208 | 12.33 |  |  | 0 | 2331 | 35298.32666666667 | 0.0 | 0.0 | 0 | 38.3 |  | 579 | 1001 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload-texturetriage | 59.8 | 43.7 | 29.8 | 16.70 | 16.90 | 17.00 | 33.60 | 13.10 |  | 0.203 | 12.89 |  |  | 6 | 2317 | 35295.66220735786 | 0.0 | 0.0 | 0 | 47.3 |  | 574 | 1167 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path-texturetriage | 59.7 | 40.4 | 29.9 | 16.70 | 16.90 | 17.00 | 33.50 | 13.20 |  | 0.217 | 12.98 |  |  | 8 | 2319 | 35296.89732142857 | 0.0 | 0.0 | 0 | 32.3 |  | 581 | 1050 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-d3d-staging-upload-texturetriage | 59.7 | 38.9 | 29.8 | 16.70 | 16.90 | 17.00 | 33.60 | 12.98 |  | 0.215 | 12.75 |  |  | 9 | 2313 | 35298.80580357143 | 0.0 | 0.0 | 0 | 32.6 |  | 589 | 1033 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-increased-cmd-buffer-slice-texturetriage | 60.0 | 58.7 | 57.1 | 16.70 | 16.90 | 16.90 | 17.50 | 13.34 |  | 0.211 | 13.12 |  |  | 0 | 2331 | 35298.23333333333 | 0.0 | 0.0 | 0 | 27.8 |  | 579 | 998 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-texturetriage | 60.0 | 58.9 | 58.1 | 16.70 | 16.90 | 16.90 | 17.20 | 12.39 |  | 0.213 | 12.17 |  |  | 0 | 2324 | 35298.42365352582 | 0.0 | 0.0 | 0 | 39.7 |  | 584 | 1055 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation-texturetriage | 60.0 | 55.3 | 29.9 | 16.70 | 16.90 | 17.00 | 33.40 | 13.52 |  | 0.209 | 13.30 |  |  | 1 | 2326 | 35299.29016120067 | 0.0 | 0.0 | 0 | 32.5 |  | 589 | 964 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation-texturetriage | 58.7 | 29.9 | 29.2 | 16.70 | 16.90 | 33.30 | 34.20 | 14.36 |  | 0.211 | 14.14 |  |  | 38 | 2265 | 35296.895573212256 | 0.0 | 0.0 | 0 | 41.7 |  | 591 | 1165 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation-texturetriage | 59.9 | 47.7 | 29.9 | 16.70 | 16.90 | 17.00 | 33.50 | 12.98 |  | 0.207 | 12.77 |  |  | 4 | 2315 | 35297.042316258354 | 0.0 | 0.0 | 0 | 36.1 |  | 584 | 1066 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-source-validation-texturetriage | 58.5 | 29.8 | 29.6 | 16.70 | 16.90 | 33.40 | 33.80 | 15.03 |  | 0.204 | 14.81 |  |  | 45 | 2262 | 35295.153846153844 | 0.0 | 0.0 | 0 | 38.9 |  | 591 | 1085 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-default-texturetriage | 50.0 | 29.8 | 29.8 | 16.70 | 33.40 | 33.50 | 33.60 | 19.51 |  | 0.264 | 19.24 |  |  | 301 | 1894 | 48556.04202801868 | 0.0 | 0.6 | 0 | 104.4 |  | 667 | 1263 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload-texturetriage | 46.2 | 25.0 | 19.9 | 16.70 | 33.50 | 33.60 | 50.20 | 21.12 |  | 0.279 | 20.83 |  |  | 410 | 1758 | 48585.43032490975 | 0.0 | 0.6 | 0 | 38.0 |  | 649 | 1480 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path-texturetriage | 44.7 | 27.7 | 20.0 | 16.80 | 33.50 | 33.60 | 50.10 | 21.84 |  | 0.288 | 21.54 |  |  | 458 | 1691 | 48566.32537313433 | 0.0 | 0.6 | 0 | 85.2 |  | 656 | 1366 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-d3d-staging-upload-texturetriage | 44.4 | 28.7 | 20.0 | 16.80 | 33.50 | 33.60 | 49.90 | 21.93 |  | 0.295 | 21.63 |  |  | 466 | 1675 | 48560.54054054054 | 0.0 | 0.6 | 0 | 83.7 |  | 651 | 1287 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-increased-cmd-buffer-slice-texturetriage | 48.5 | 29.8 | 29.5 | 16.70 | 33.40 | 33.50 | 33.90 | 20.10 |  | 0.270 | 19.82 |  |  | 345 | 1819 | 48549.00274725275 | 0.0 | 0.6 | 0 | 98.2 |  | 660 | 1335 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-texturetriage | 51.5 | 29.8 | 29.7 | 16.70 | 33.40 | 33.50 | 33.70 | 18.91 |  | 0.254 | 18.65 |  |  | 254 | 1934 | 48556.48737864078 | 0.0 | 0.6 | 0 | 82.0 |  | 667 | 1272 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation-texturetriage | 50.3 | 28.8 | 20.0 | 16.70 | 33.40 | 33.50 | 50.10 | 19.35 |  | 0.263 | 19.08 |  |  | 289 | 1895 | 48557.656953642385 | 0.0 | 0.6 | 0 | 84.9 |  | 659 | 1272 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation-texturetriage | 41.2 | 20.0 | 20.0 | 16.80 | 33.50 | 49.80 | 50.10 | 23.66 |  | 0.310 | 23.35 |  |  | 551 | 1568 | 48567.574898785424 | 0.0 | 0.6 | 0 | 80.1 |  | 645 | 1398 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation-texturetriage | 43.2 | 19.8 | 19.1 | 16.80 | 33.50 | 50.10 | 52.30 | 22.56 |  | 0.291 | 22.26 |  |  | 469 | 1696 | 48662.47335907336 | 0.0 | 0.6 | 0 | 75.5 |  | 649 | 1232 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-source-validation-texturetriage | 45.0 | 26.7 | 19.9 | 16.80 | 33.50 | 33.60 | 50.20 | 21.63 |  | 0.290 | 21.34 |  |  | 446 | 1698 | 48563.81865284974 | 0.0 | 0.6 | 0 | 90.0 |  | 655 | 1373 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-default-texturetriage | 6.9 | 6.0 | 6.0 | 149.90 | 166.60 | 166.80 | 166.90 | 14.36 |  | 1.050 | 13.30 |  |  | 207 | 275 | 193 | 3219.6 | 0.0 | 0 | 7.6 |  | 535 | 794 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload-texturetriage | 4.2 | 2.4 | 2.4 | 216.80 | 350.00 | 383.50 | 416.60 | 21.32 |  | 1.521 | 19.79 |  |  | 124 | 190 | 193 | 2097.4 | 0.0 | 0 | 7.9 |  | 526 | 828 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path-texturetriage | 5.8 | 3.7 | 3.7 | 166.70 | 216.60 | 250.00 | 266.70 | 16.42 |  | 1.204 | 15.20 |  |  | 175 | 237 | 193 | 2752.0 | 0.0 | 0 | 8.3 |  | 553 | 1046 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-d3d-staging-upload-texturetriage | 5.9 | 4.0 | 4.0 | 166.70 | 200.10 | 216.90 | 250.10 | 16.95 |  | 1.220 | 15.71 |  |  | 177 | 235 | 193 | 2752.0 | 0.0 | 0 | 7.8 |  | 538 | 816 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-increased-cmd-buffer-slice-texturetriage | 6.8 | 4.1 | 3.8 | 149.90 | 166.80 | 183.50 | 266.50 | 14.93 |  | 1.086 | 13.83 |  |  | 204 | 272 | 193 | 3179.5 | 0.0 | 0 | 7.6 |  | 535 | 824 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-texturetriage | 7.3 | 6.0 | 6.0 | 133.40 | 166.60 | 166.70 | 166.80 | 14.13 |  | 1.021 | 13.10 |  |  | 218 | 290 | 193 | 3393.3 | 0.0 | 0 | 7.7 |  | 595 | 821 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation-texturetriage | 6.7 | 5.2 | 5.0 | 150.00 | 166.80 | 183.40 | 200.00 | 14.81 |  | 1.046 | 13.75 |  |  | 201 | 269 | 193 | 3139.5 | 0.0 | 0 | 8.3 |  | 533 | 809 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation-texturetriage | 5.8 | 4.0 | 4.0 | 166.70 | 216.70 | 249.80 | 250.00 | 16.82 |  | 1.228 | 15.58 |  |  | 174 | 230 | 193 | 2698.6 | 0.0 | 0 | 8.0 |  | 532 | 903 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation-texturetriage | 5.5 | 4.3 | 4.3 | 183.30 | 216.80 | 233.30 | 233.40 | 17.59 |  | 1.333 | 16.24 |  |  | 165 | 219 | 193 | 2565.0 | 0.0 | 0 | 7.5 |  | 536 | 938 | 201.5 | 1.4 | 452.0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-source-validation-texturetriage | 6.0 | 3.8 | 3.8 | 166.60 | 216.70 | 233.40 | 266.60 | 16.54 |  | 1.213 | 15.32 |  |  | 178 | 240 | 193 | 2792.1 | 0.0 | 0 | 7.7 |  | 538 | 821 | 201.5 | 1.4 | 452.0 |

## WebGPU Fast-Path Coverage

These counters are diagnostic attribution only. They show whether WebGPU queue and pipeline descriptors match source fast paths; they are not standalone speed evidence.

| Scene | Renderer | Variant | WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgpu | fork-viewer-exp-default-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-d3d-staging-upload-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-increased-cmd-buffer-slice-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-source-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-default-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-d3d-staging-upload-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-increased-cmd-buffer-slice-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-source-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-default-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-d3d-staging-upload-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-increased-cmd-buffer-slice-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| texture-streaming | webgpu | fork-viewer-exp-webgpu-skip-copy-external-image-source-validation-texturetriage | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |

Unavailable metrics are intentionally blank.

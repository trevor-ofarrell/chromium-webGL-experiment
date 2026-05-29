# Benchmark Summary

Generated from 34 result file(s).
Input file digest: `8ce64a8d9555d9c2ea87b4c8154d36c71fbb96f5355c6c38c6a56a0805fa6a1f`
Strict summary evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, positive package-size evidence, and no attribution instrumentation before this report is written.

| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgpu | fork-viewer-exp-default | 60.0 | 58.9 | 58.1 | 16.70 | 16.90 | 16.90 | 17.20 | 12.36 |  | 0.196 | 12.15 |  |  | 0 | 2335 | 35299.36 | 0.0 | 0.0 | 0 | 35.6 |  | 588 | 945 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-cache-bind-group-layouts | 59.4 | 30.0 | 29.8 | 16.70 | 16.90 | 17.10 | 33.60 | 12.99 |  | 0.211 | 12.77 |  |  | 17 | 2299 | 35298.49551569507 | 0.0 | 0.0 | 0 | 32.1 |  | 582 | 969 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush | 60.0 | 58.8 | 57.5 | 16.70 | 16.90 | 16.90 | 17.40 | 11.87 |  | 0.206 | 11.65 |  |  | 0 | 2333 | 35299.473333333335 | 0.0 | 0.0 | 0 | 22.7 |  | 574 | 940 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-defer-queue-flush | 58.3 | 29.8 | 27.9 | 16.70 | 16.90 | 33.30 | 35.90 | 14.27 |  | 0.213 | 14.04 |  |  | 52 | 2266 | 35291.75814751286 | 0.0 | 0.0 | 0 | 41.7 |  | 590 | 1118 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-defer-submit-flush | 59.9 | 50.1 | 29.9 | 16.70 | 16.90 | 17.00 | 33.50 | 13.93 |  | 0.215 | 13.70 |  |  | 3 | 2324 | 35297.82804674457 | 0.0 | 0.0 | 0 | 43.8 |  | 589 | 1022 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-canvas-memory-accounting | 60.0 | 58.7 | 57.1 | 16.70 | 16.90 | 16.90 | 17.50 | 13.66 |  | 0.221 | 13.43 |  |  | 0 | 2329 | 35299.05333333334 | 0.0 | 0.0 | 0 | 39.1 |  | 581 | 990 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-canvas-texture-validation | 57.5 | 29.8 | 29.2 | 16.70 | 17.00 | 33.40 | 34.20 | 15.23 |  | 0.216 | 15.01 |  |  | 74 | 2147 | 35292.402085747395 | 0.0 | 0.0 | 0 | 46.2 |  | 592 | 1091 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-command-labels | 59.4 | 30.0 | 29.8 | 16.70 | 16.90 | 17.20 | 33.60 | 14.20 |  | 0.213 | 13.98 |  |  | 17 | 2289 | 35295.973094170404 | 0.0 | 0.0 | 0 | 20.3 |  | 582 | 1128 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-redundant-bind-group-sets | 55.8 | 29.8 | 29.7 | 16.70 | 33.30 | 33.50 | 33.70 | 16.92 |  | 0.209 | 16.71 |  |  | 125 | 2119 | 35299.23627684964 | 0.0 | 0.0 | 0 | 46.3 |  | 580 | 1227 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-redundant-buffer-sets | 54.7 | 29.8 | 29.5 | 16.70 | 33.30 | 33.50 | 33.90 | 17.05 |  | 0.217 | 16.82 |  |  | 160 | 2119 | 35298.678048780486 | 0.0 | 0.0 | 0 | 43.0 |  | 591 | 1217 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-redundant-pipeline-sets | 60.0 | 55.6 | 30.1 | 16.70 | 16.90 | 16.90 | 33.20 | 12.75 |  | 0.209 | 12.53 |  |  | 1 | 2328 | 35298.32295719844 | 0.0 | 0.0 | 0 | 44.3 |  | 584 | 1005 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-redundant-render-state-sets | 59.8 | 43.8 | 29.8 | 16.70 | 16.90 | 17.00 | 33.60 | 12.87 |  | 0.204 | 12.66 |  |  | 6 | 2316 | 35298.02061281337 | 0.0 | 0.0 | 0 | 32.9 |  | 594 | 1010 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-resource-labels | 59.6 | 36.2 | 29.8 | 16.70 | 16.90 | 17.00 | 33.60 | 14.36 |  | 0.215 | 14.14 |  |  | 11 | 2298 | 35297.29290106204 | 0.0 | 0.0 | 0 | 49.0 |  | 587 | 1128 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-shader-memory-accounting | 59.8 | 41.8 | 29.9 | 16.70 | 16.90 | 17.00 | 33.40 | 13.19 |  | 0.211 | 12.97 |  |  | 7 | 2316 | 35298.15337423313 | 0.0 | 0.0 | 0 | 27.8 |  | 593 | 1041 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-shader-source-null-check | 59.8 | 43.7 | 29.9 | 16.70 | 16.90 | 17.00 | 33.40 | 14.07 |  | 0.205 | 13.85 |  |  | 6 | 2314 | 35298.14094707521 | 0.0 | 0.0 | 0 | 28.6 |  | 589 | 1078 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-use-counters | 59.3 | 30.0 | 29.8 | 16.70 | 16.90 | 33.20 | 33.60 | 14.14 |  | 0.207 | 13.93 |  |  | 20 | 2197 | 35274.582022471914 | 0.0 | 0.0 | 0 | 35.1 |  | 581 | 2250 | 201.5 | 1.4 | 452.0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-write-texture-layout-validation | 56.3 | 29.8 | 29.7 | 16.70 | 33.30 | 33.50 | 33.70 | 14.94 |  | 0.209 | 14.72 |  |  | 112 | 2219 | 35308.78909952607 | 0.0 | 0.0 | 0 | 62.9 |  | 590 | 993 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-default | 52.5 | 29.8 | 29.8 | 16.70 | 33.40 | 33.50 | 33.60 | 18.59 |  | 0.245 | 18.35 |  |  | 226 | 1978 | 48557.64589955499 | 0.0 | 0.6 | 0 | 86.6 |  | 669 | 1283 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-cache-bind-group-layouts | 49.6 | 29.7 | 29.5 | 16.70 | 33.40 | 33.50 | 33.90 | 19.66 |  | 0.269 | 19.38 |  |  | 313 | 1888 | 48559.6738399462 | 0.0 | 0.6 | 0 | 96.2 |  | 663 | 1301 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush | 54.0 | 29.8 | 29.2 | 16.70 | 33.30 | 33.50 | 34.20 | 18.03 |  | 0.254 | 17.77 |  |  | 180 | 2045 | 48564.4 | 0.0 | 0.6 | 0 | 98.9 |  | 664 | 1231 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-defer-queue-flush | 43.1 | 27.5 | 19.8 | 16.80 | 33.50 | 33.60 | 50.40 | 22.65 |  | 0.305 | 22.33 |  |  | 505 | 1580 | 48558.763341067286 | 0.0 | 0.6 | 0 | 83.0 |  | 652 | 1457 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-defer-submit-flush | 48.4 | 28.7 | 19.9 | 16.70 | 33.40 | 33.60 | 50.20 | 20.12 |  | 0.266 | 19.85 |  |  | 346 | 1836 | 48557.93048864418 | 0.0 | 0.6 | 0 | 106.5 |  | 661 | 1280 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-canvas-memory-accounting | 49.0 | 29.8 | 29.4 | 16.70 | 33.40 | 33.50 | 34.00 | 19.88 |  | 0.267 | 19.61 |  |  | 329 | 1848 | 48535.322229775666 | 0.0 | 0.6 | 0 | 88.4 |  | 661 | 1316 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-canvas-texture-validation | 47.1 | 29.8 | 29.8 | 16.70 | 33.40 | 33.50 | 33.60 | 20.73 |  | 0.268 | 20.45 |  |  | 388 | 1769 | 48562.65439093485 | 0.0 | 0.6 | 0 | 83.9 |  | 672 | 1382 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-command-labels | 41.1 | 19.9 | 19.8 | 16.80 | 33.60 | 50.10 | 50.40 | 23.68 |  | 0.299 | 23.38 |  |  | 536 | 1603 | 48597.48946515397 | 0.0 | 0.6 | 0 | 81.7 |  | 652 | 1548 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-redundant-bind-group-sets | 44.8 | 27.7 | 19.9 | 16.80 | 33.40 | 33.50 | 50.20 | 21.74 |  | 0.289 | 21.45 |  |  | 453 | 1706 | 48562.02007434944 | 0.0 | 0.6 | 0 | 44.9 |  | 615 | 1539 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-redundant-buffer-sets | 40.0 | 22.7 | 19.9 | 17.00 | 33.50 | 33.70 | 50.20 | 24.35 |  | 0.320 | 24.02 |  |  | 591 | 1479 | 48551.62 | 0.0 | 0.6 | 0 | 51.4 |  | 622 | 1534 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-redundant-pipeline-sets | 47.4 | 29.8 | 29.8 | 16.70 | 33.40 | 33.50 | 33.60 | 20.59 |  | 0.272 | 20.31 |  |  | 378 | 1774 | 48567.575650950035 | 0.0 | 0.6 | 0 | 103.0 |  | 657 | 1311 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-redundant-render-state-sets | 46.5 | 25.0 | 20.0 | 16.70 | 33.40 | 33.60 | 50.10 | 20.95 |  | 0.287 | 20.66 |  |  | 400 | 1598 | 48483.58924731183 | 0.0 | 0.6 | 0 | 48.0 |  | 620 | 1969 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-resource-labels | 43.9 | 27.6 | 20.0 | 16.80 | 33.50 | 33.60 | 50.00 | 22.22 |  | 0.280 | 21.93 |  |  | 481 | 1661 | 48584.29286798179 | 0.0 | 0.6 | 0 | 88.7 |  | 652 | 1346 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-shader-memory-accounting | 47.0 | 28.7 | 19.9 | 16.70 | 33.40 | 33.60 | 50.20 | 20.74 |  | 0.265 | 20.47 |  |  | 390 | 1756 | 48558.41660752307 | 0.0 | 0.6 | 0 | 77.1 |  | 654 | 1309 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-shader-source-null-check | 47.1 | 28.7 | 20.0 | 16.70 | 33.50 | 33.60 | 50.00 | 20.70 |  | 0.276 | 20.42 |  |  | 386 | 1760 | 48562.265392781315 | 0.0 | 0.6 | 0 | 96.6 |  | 656 | 1347 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-use-counters | 32.6 | 19.0 | 15.0 | 33.30 | 50.00 | 50.30 | 66.80 | 29.83 |  | 0.368 | 29.45 |  |  | 727 | 1306 | 48570.57625383828 | 0.0 | 0.6 | 0 | 63.3 |  | 644 | 1278 | 201.5 | 1.4 | 452.0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-write-texture-layout-validation | 47.0 | 29.8 | 29.7 | 16.70 | 33.40 | 33.50 | 33.70 | 20.71 |  | 0.279 | 20.42 |  |  | 389 | 1767 | 48539.01983002833 | 0.0 | 0.6 | 0 | 92.6 |  | 656 | 1323 | 201.5 | 1.4 | 452.0 |

## WebGPU Fast-Path Coverage

These counters are diagnostic attribution only. They show whether WebGPU queue and pipeline descriptors match source fast paths; they are not standalone speed evidence.

| Scene | Renderer | Variant | WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gltf-loader-stress | webgpu | fork-viewer-exp-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-cache-bind-group-layouts | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-defer-queue-flush | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-defer-submit-flush | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-canvas-memory-accounting | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-canvas-texture-validation | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-command-labels | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-redundant-bind-group-sets | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-redundant-buffer-sets | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-redundant-pipeline-sets | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-redundant-render-state-sets | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-resource-labels | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-shader-memory-accounting | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-shader-source-null-check | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-use-counters | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| gltf-loader-stress | webgpu | fork-viewer-exp-webgpu-skip-write-texture-layout-validation | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-default | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-cache-bind-group-layouts | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-defer-pipeline-flush | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-defer-queue-flush | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-defer-submit-flush | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-canvas-memory-accounting | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-canvas-texture-validation | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-command-labels | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-redundant-bind-group-sets | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-redundant-buffer-sets | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-redundant-pipeline-sets | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-redundant-render-state-sets | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-resource-labels | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-shader-memory-accounting | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-shader-source-null-check | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-use-counters | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |
| many-draw-calls | webgpu | fork-viewer-exp-webgpu-skip-write-texture-layout-validation | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 |

Unavailable metrics are intentionally blank.

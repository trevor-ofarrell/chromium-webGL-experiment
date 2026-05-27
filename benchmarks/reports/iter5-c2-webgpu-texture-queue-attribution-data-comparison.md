# Benchmark Comparison

Generated from 2 result file(s). Baseline per scene/renderer is the first variant whose name contains stock or baseline, falling back to the first result.
Strict official input validation was enabled: all inputs must come from checkout-built binaries, share one Chromium revision, include build-args hashes, include patch-derived fork revisions for fork variants, contain baseline plus fork variants for every scene/renderer, use matching measured/warmup seconds per case, include GPU/backend metadata, and avoid known software-rendered GPU paths.

| Scene | Renderer | Variant | Avg FPS | FPS Delta | FPS Delta % | 1% Low | 1% Low Delta | 0.1% Low | 0.1% Low Delta | P50 ms | P50 Delta | P95 ms | P95 Delta | P99 ms | P99 Delta | Max ms | Max Delta | CPU ms | CPU Delta | JS ms | JS Delta | Submit ms | Submit Delta | Compositor ms | Compositor Delta | Present ms | Present Delta | GPU ms | GPU Delta | Dropped | Dropped Delta | Startup ms | Startup Delta | RSS MB | RSS Delta | JS heap MB | JS heap Delta | GPU memory MB | GPU memory Delta | Draw calls | Draw calls Delta | Triangles | Triangles Delta | Texture MB | Texture Delta | Buffer MB | Buffer Delta | Shader events | Shader events Delta | Binary MB | Binary Delta | Viewer MB | Viewer Delta | Package MB | Package Delta |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| texture-streaming | webgpu | iter5-baseline-c2-data-queueinst-notiming-texture-streaming-webgpu | 74.0 | 0.0 | 0.0% | 40.0 | 0.0 | 28.9 | 0.0 | 13.90 | 0.00 | 20.80 | 0.00 | 21.00 | 0.00 | 34.70 | 0.00 | 11.81 | 0.00 | 2.47 | 0.00 | 9.29 | 0.00 |  |  |  |  |  |  | 11 | 0 | 1160 | 0 | 712.1 | 0.0 | 25.3 | 0.0 |  |  | 2733 | 0 | 193 | 0 | 33077.8 | 0.0 | 0.0 | 0.0 | 0 | 0 | 288.4 | 0.0 | 1.4 | 0.0 |  |  |
| texture-streaming | webgpu | iter5-fork-default-c2-data-queueinst-notiming-texture-streaming-webgpu | 72.3 | -1.7 | -2.3% | 43.9 | 3.9 | 35.8 | 6.9 | 13.90 | 0.00 | 20.90 | 0.10 | 21.10 | 0.10 | 28.00 | -6.70 | 12.08 | 0.27 | 2.52 | 0.05 | 9.51 | 0.22 |  |  |  |  |  |  | 5 | -6 | 1268 | 109 | 711.1 | -1.0 | 29.7 | 4.4 |  |  | 2655 | -78 | 193 | 0 | 32222.8 | -855.0 | 0.0 | 0.0 | 0 | 0 | 288.4 | 0.0 | 1.4 | 0.0 |  |  |

## Aggregate Averages

Averages are arithmetic means across the scene rows included in this report. Delta columns are relative to each scene/renderer baseline before averaging.

| Renderer | Variant | Scenes | Avg FPS | Avg FPS Delta | Avg FPS Delta % | Avg 1% Low Delta | Avg 0.1% Low Delta | Avg P95 Delta ms | Avg P99 Delta ms | Avg Max Delta ms | Avg CPU Delta ms | Avg JS Delta ms | Avg Submit Delta ms | Avg Dropped Delta | Avg Startup Delta ms | Avg RSS Delta MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgpu | iter5-baseline-c2-data-queueinst-notiming | 1 | 74.00 | 0.00 | 0.0% | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| webgpu | iter5-fork-default-c2-data-queueinst-notiming | 1 | 72.32 | -1.68 | -2.3% | 3.90 | 6.92 | 0.10 | 0.10 | -6.70 | 0.27 | 0.05 | 0.22 | -6.00 | 108.50 | -1.03 |

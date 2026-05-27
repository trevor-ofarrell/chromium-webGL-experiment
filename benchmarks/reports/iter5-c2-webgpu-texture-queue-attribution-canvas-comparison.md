# Benchmark Comparison

Generated from 2 result file(s). Baseline per scene/renderer is the first variant whose name contains stock or baseline, falling back to the first result.
Strict official input validation was enabled: all inputs must come from checkout-built binaries, share one Chromium revision, include build-args hashes, include patch-derived fork revisions for fork variants, contain baseline plus fork variants for every scene/renderer, use matching measured/warmup seconds per case, include GPU/backend metadata, and avoid known software-rendered GPU paths.

| Scene | Renderer | Variant | Avg FPS | FPS Delta | FPS Delta % | 1% Low | 1% Low Delta | 0.1% Low | 0.1% Low Delta | P50 ms | P50 Delta | P95 ms | P95 Delta | P99 ms | P99 Delta | Max ms | Max Delta | CPU ms | CPU Delta | JS ms | JS Delta | Submit ms | Submit Delta | Compositor ms | Compositor Delta | Present ms | Present Delta | GPU ms | GPU Delta | Dropped | Dropped Delta | Startup ms | Startup Delta | RSS MB | RSS Delta | JS heap MB | JS heap Delta | GPU memory MB | GPU memory Delta | Draw calls | Draw calls Delta | Triangles | Triangles Delta | Texture MB | Texture Delta | Buffer MB | Buffer Delta | Shader events | Shader events Delta | Binary MB | Binary Delta | Viewer MB | Viewer Delta | Package MB | Package Delta |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| texture-streaming | webgpu | iter5-baseline-c2-queueinst-notiming-texture-streaming-webgpu | 5.3 | 0.0 | 0.0% | 3.9 | 0.0 | 3.9 | 0.0 | 187.50 | 0.00 | 215.30 | 0.00 | 222.30 | 0.00 | 256.90 | 0.00 | 40.58 | 0.00 | 2.27 | 0.00 | 38.28 | 0.00 |  |  |  |  |  |  | 159 | 0 | 1816 | 0 | 702.3 | 0.0 | 9.3 | 0.0 |  |  | 207 | 0 | 193 | 0 | 2444.8 | 0.0 | 0.0 | 0.0 | 0 | 0 | 288.4 | 0.0 | 1.4 | 0.0 |  |  |
| texture-streaming | webgpu | iter5-fork-default-c2-queueinst-notiming-texture-streaming-webgpu | 5.1 | -0.2 | -4.3% | 3.6 | -0.3 | 3.6 | -0.3 | 194.50 | 7.00 | 222.30 | 7.00 | 236.20 | 13.90 | 277.70 | 20.80 | 40.53 | -0.05 | 2.31 | 0.05 | 38.18 | -0.10 |  |  |  |  |  |  | 152 | -7 | 1274 | -542 | 690.2 | -12.1 | 8.5 | -0.8 |  |  | 196 | -11 | 193 | 0 | 2324.5 | -120.2 | 0.0 | 0.0 | 0 | 0 | 288.4 | 0.0 | 1.4 | 0.0 |  |  |

## Aggregate Averages

Averages are arithmetic means across the scene rows included in this report. Delta columns are relative to each scene/renderer baseline before averaging.

| Renderer | Variant | Scenes | Avg FPS | Avg FPS Delta | Avg FPS Delta % | Avg 1% Low Delta | Avg 0.1% Low Delta | Avg P95 Delta ms | Avg P99 Delta ms | Avg Max Delta ms | Avg CPU Delta ms | Avg JS Delta ms | Avg Submit Delta ms | Avg Dropped Delta | Avg Startup Delta ms | Avg RSS Delta MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgpu | iter5-baseline-c2-queueinst-notiming | 1 | 5.33 | 0.00 | 0.0% | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| webgpu | iter5-fork-default-c2-queueinst-notiming | 1 | 5.10 | -0.23 | -4.3% | -0.29 | -0.29 | 7.00 | 13.90 | 20.80 | -0.05 | 0.05 | -0.10 | -7.00 | -541.50 | -12.10 |

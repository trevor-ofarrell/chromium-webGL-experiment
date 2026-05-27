# Benchmark Comparison

Generated from 2 result file(s). Baseline per scene/renderer is the first variant whose name contains stock or baseline, falling back to the first result.
Strict official input validation was enabled: all inputs must come from checkout-built binaries, share one Chromium revision, include build-args hashes, include patch-derived fork revisions for fork variants, contain baseline plus fork variants for every scene/renderer, use matching measured/warmup seconds per case, include GPU/backend metadata, and avoid known software-rendered GPU paths.

| Scene | Renderer | Variant | Avg FPS | FPS Delta | FPS Delta % | 1% Low | 1% Low Delta | 0.1% Low | 0.1% Low Delta | P50 ms | P50 Delta | P95 ms | P95 Delta | P99 ms | P99 Delta | Max ms | Max Delta | CPU ms | CPU Delta | JS ms | JS Delta | Submit ms | Submit Delta | Compositor ms | Compositor Delta | Present ms | Present Delta | GPU ms | GPU Delta | Dropped | Dropped Delta | Startup ms | Startup Delta | RSS MB | RSS Delta | JS heap MB | JS heap Delta | GPU memory MB | GPU memory Delta | Draw calls | Draw calls Delta | Triangles | Triangles Delta | Texture MB | Texture Delta | Buffer MB | Buffer Delta | Shader events | Shader events Delta | Binary MB | Binary Delta | Viewer MB | Viewer Delta | Package MB | Package Delta |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| texture-streaming | webgl2 | iter4-baseline-c2-data-texture-streaming-webgl2 | 103.7 | 0.0 | 0.0% | 47.3 | 0.0 | 42.9 | 0.0 | 7.00 | 0.00 | 14.10 | 0.00 | 20.80 | 0.00 | 27.60 | 0.00 | 7.93 | 0.00 | 2.68 | 0.00 | 5.16 | 0.00 |  |  |  |  | 4.900 | 0.000 | 1 | 0 | 1733 | 0 | 616.9 | 0.0 | 19.7 | 0.0 |  |  | 96 | 0 | 192 | 0 | 47612.8 | 0.0 | 0.0 | 0.0 | 0 | 0 | 288.4 | 0.0 | 1.4 | 0.0 |  |  |
| texture-streaming | webgl2 | iter4-fork-zerocopy-only-c2-data-texture-streaming-webgl2 | 101.7 | -2.0 | -2.0% | 48.4 | 1.1 | 42.9 | -0.1 | 7.00 | 0.00 | 14.10 | 0.00 | 14.30 | -6.50 | 27.80 | 0.20 | 8.08 | 0.15 | 2.71 | 0.03 | 5.28 | 0.12 |  |  |  |  | 4.775 | -0.126 | 1 | 0 | 895 | -838 | 609.8 | -7.1 | 22.1 | 2.4 |  |  | 96 | 0 | 192 | 0 | 46063.1 | -1549.7 | 0.0 | 0.0 | 0 | 0 | 288.4 | 0.0 | 1.4 | 0.0 |  |  |

## Aggregate Averages

Averages are arithmetic means across the scene rows included in this report. Delta columns are relative to each scene/renderer baseline before averaging.

| Renderer | Variant | Scenes | Avg FPS | Avg FPS Delta | Avg FPS Delta % | Avg 1% Low Delta | Avg 0.1% Low Delta | Avg P95 Delta ms | Avg P99 Delta ms | Avg Max Delta ms | Avg CPU Delta ms | Avg JS Delta ms | Avg Submit Delta ms | Avg Dropped Delta | Avg Startup Delta ms | Avg RSS Delta MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| webgl2 | iter4-baseline-c2-data | 1 | 103.72 | 0.00 | 0.0% | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| webgl2 | iter4-fork-zerocopy-only-c2-data | 1 | 101.68 | -2.03 | -2.0% | 1.06 | -0.06 | 0.00 | -6.50 | 0.20 | 0.15 | 0.03 | 0.12 | 0.00 | -837.80 | -7.07 |

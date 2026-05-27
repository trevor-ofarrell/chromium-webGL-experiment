# Iteration 5 WebGPU Queue Attribution

Date: 2026-05-21

Purpose: explain the remaining WebGPU texture-streaming regression before attempting deeper Chromium changes. All non-smoke comparison rows below used 30s measured / 5s warmup, complexity 2, safe 640x480 window, GPU timestamp timing disabled, checkout-built stock and fork `content_shell`, matching build args, GPU metadata, frame-time arrays, and `--rejectGpuInstability`.

## Viewer Instrumentation

The viewer now has an opt-in `queueInstrumentation=1` benchmark query flag, exposed by `scripts/run_benchmark.mjs` as `--queueInstrumentation`. When enabled on WebGPU, it wraps `renderer.backend.device.queue` methods and records JS-visible call counts and wall-clock time for:

- `writeBuffer`
- `writeTexture`
- `copyExternalImageToTexture`
- `copyElementImageToTexture`
- `submit`

This is attribution-only evidence. It is not used for final clean FPS claims because the wrapper adds some JS overhead to both stock and fork runs.

## CanvasTexture Path

Artifacts:

- `benchmarks/raw/iter5-baseline-c2-queueinst-notiming-texture-streaming-webgpu.json`
- `benchmarks/raw/iter5-fork-default-c2-queueinst-notiming-texture-streaming-webgpu.json`
- `benchmarks/reports/iter5-c2-webgpu-texture-queue-attribution-canvas-comparison.md`

| Variant | FPS | P99 ms | CPU ms | Submit ms | copyExternal count | copyExternal ms | copyExternal MB | writeTexture count | queue.submit count | queue.submit ms | Startup ms | RSS MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Stock baseline | 5.33 | 222.3 | 40.58 | 38.28 | 17,481 | 2,464.2 | 2,458.4 | 0 | 17,849 | 804.4 | 1815.5 | 702.3 |
| Fork default | 5.10 | 236.2 | 40.53 | 38.18 | 16,626 | 2,347.7 | 2,338.1 | 0 | 16,976 | 775.7 | 1274.0 | 690.2 |

Result: fork default is -4.3% FPS and p99 is +13.9 ms versus stock in this attribution run. CanvasTexture does not hit `queue.writeTexture`; it primarily hits `queue.copyExternalImageToTexture`, and each measured frame issues many queue submits. Startup and RSS still improve, but this path is not a WebGPU throughput win.

## DataTexture Path

Artifacts:

- `benchmarks/raw/iter5-baseline-c2-data-queueinst-notiming-texture-streaming-webgpu.json`
- `benchmarks/raw/iter5-fork-default-c2-data-queueinst-notiming-texture-streaming-webgpu.json`
- `benchmarks/reports/iter5-c2-webgpu-texture-queue-attribution-data-comparison.md`

| Variant | FPS | P99 ms | CPU ms | Submit ms | writeTexture count | writeTexture ms | writeTexture MB | writeBuffer count | writeBuffer ms | queue.submit count | queue.submit ms | Startup ms | RSS MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Stock baseline | 74.00 | 21.0 | 11.81 | 9.29 | 235,315 | 9,656.8 | 33,091.2 | 470,930 | 2,124.7 | 4,955 | 301.0 | 1159.9 | 712.1 |
| Fork default | 72.32 | 21.1 | 12.08 | 9.51 | 229,235 | 9,595.5 | 32,236.2 | 458,770 | 2,095.8 | 4,827 | 308.5 | 1268.4 | 711.1 |

Result: fork default is -2.3% FPS and p99 is +0.1 ms versus stock in this attribution run. DataTexture shifts the bottleneck to `queue.writeTexture`; the fork does not improve that path.

## Dawn Toggle Smokes

These were 5s / 1s fork-only smoke probes on DataTexture, not final comparisons. None beat the prior clean stock/fork DataTexture evidence enough to justify expansion.

| Candidate | FPS | P99 ms | CPU ms | Submit ms | Device lost | Status |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| D3D11 adapter + `d3d11_delay_flush_to_gpu` | 72.20 | 21.1 | 12.09 | 9.12 | false | Not expanded |
| Dawn `disable_robustness` | 68.99 | 21.1 | 12.62 | 9.82 | false | Rejected |
| D3D12 heap/render-pass/root-signature toggles | 68.28 | 21.1 | 12.71 | 9.89 | false | Rejected |

## Source Trace Patch

Added patch-series entry:

- `chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch`

Applied source file:

- `src/third_party/blink/renderer/modules/webgpu/gpu_queue.cc`

The patch adds `TRACE_EVENT` scopes for:

- `GPUQueue::submit`
- `GPUQueue::WriteBufferImpl`
- `GPUQueue::WriteTextureImpl`
- `GPUQueue::copyExternalImageToTexture`
- `GPUQueue::CopyFromCanvasSourceImage`
- `GPUQueue::CopyFromCanvasSourceImage::SubmitIntermediate`

Next step after rebuilding `ReleaseViewerDefault`: capture texture-streaming traces again and verify whether the high-count CanvasTexture path is GPU-process submit/flush dominated, image extraction dominated, or Dawn copy dominated.

## Decision

Keep the queue instrumentation as opt-in benchmark attribution. Do not keep any new WebGPU performance flag from this iteration. The current WebGPU bottleneck still needs a source-level change, most likely around Blink/Dawn copy batching or flush behavior for trusted local content, before a valid fork-over-stock WebGPU texture-streaming win is plausible.

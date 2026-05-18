# Stability Behavior

Date: 2026-05-16

The viewer now reports graphics loss state in every benchmark result.

## WebGL Context Loss

The viewer listens for `webglcontextlost` and `webglcontextrestored` on the primary canvas.

On loss:

- `event.preventDefault()` is called so restoration remains possible.
- `webgl_context_lost_count` is incremented.
- `webgl_context_currently_lost` is set.
- render submission is skipped while the context is marked lost.

On restore:

- `webgl_context_restored_count` is incremented.
- `webgl_context_currently_lost` is cleared.

## WebGPU Device Loss

Three.js `WebGPURenderer` exposes `onDeviceLost`. The viewer wraps that callback and records:

- `webgpu_device_lost`
- `webgpu_device_loss_reason`
- `webgpu_device_loss_message`

The original Three.js callback is still invoked so upstream renderer behavior is preserved.

## GPU Process Crash/Restart

The fork has not yet produced official GPU process crash/restart evidence because the Chromium binaries are still blocked by the ATL/MFC host prerequisite. The final stability documentation must be updated after the stock and fork one-hour runs to state whether the GPU process stayed alive, restarted cleanly, or caused a benchmark failure. Until that evidence exists, GPU process crash/restart behavior is treated as pending runtime evidence rather than completed documentation.

## Benchmark Fields

Optional stability fields emitted by the viewer:

- `webgl_context_lost_count`
- `webgl_context_restored_count`
- `webgl_context_currently_lost`
- `webgl_last_context_loss_ms`
- `webgpu_device_lost`
- `webgpu_device_loss_reason`
- `webgpu_device_loss_message`
- `render_error_count`
- `last_render_error`

These fields are diagnostic and not part of the required metric schema.

## Resource Growth Fields

During the measured window, the benchmark also records renderer resource counters from `renderer.info`:

- `renderer_memory_geometries_start`
- `renderer_memory_geometries_end`
- `renderer_memory_geometries_peak`
- `renderer_memory_geometries_delta`
- `renderer_memory_textures_start`
- `renderer_memory_textures_end`
- `renderer_memory_textures_peak`
- `renderer_memory_textures_delta`
- `renderer_programs_start`
- `renderer_programs_end`
- `renderer_programs_peak`
- `renderer_programs_delta`

The short v18 smoke validates these fields for WebGL2 and WebGPU instancing and records zero measured deltas. The required one-hour stock/fork stability loop must still use these fields together with RSS delta to check for resource growth after warmup. For stable scenes such as `instancing`, use the default gate `-MaxRssDeltaMb 128 -MaxRendererResourceDelta 0`. The artifact audit accepts the one-hour stability rows only when `validate_stability_result.mjs` confirms at least 3600 measured seconds, at least 30 warmup seconds, checkout/build metadata, pinned Chromium revision, hardware GPU metadata, the expected `instancing`/`webgl2` long-stability variant labels `baseline-content-shell-long-stability` and `fork-viewer-default-long-stability`, stock/fork viewer launch metadata, fork revision for the fork run, `process_rss_delta_mb <= 128`, and zero renderer resource growth.

## Current Smoke Evidence

Installed-Chrome smoke artifact:

- `benchmarks/raw/smoke-installed-chrome-v11-stability-smoke.json`
- `benchmarks/raw/smoke-installed-chrome-v11-stability-fields-many-draw-calls-webgl2.json`
- `benchmarks/raw/smoke-installed-chrome-v18-renderer-resource-counters-instancing-webgl2.json`
- `benchmarks/raw/smoke-installed-chrome-v18-renderer-resource-counters-instancing-webgpu.json`

It validates:

- WebGL2 context creation.
- `WEBGL_lose_context` event delivery and restoration signal.
- WebGPU adapter/device creation.
- `GPUDevice.lost` signal delivery on explicit device destroy.
- The normal benchmark path emits stability fields with zero loss events.
- The normal benchmark path emits renderer geometry, texture, and program start/end/peak/delta counters.
- `validate_stability_result.mjs` enforces positive FPS, measured frame samples, RSS delta thresholds, renderer geometry/texture/program delta thresholds, expected viewer flag metadata, and final-audit gates for one-hour duration, warmup, checkout/build provenance, pinned Chromium revision, expected renderer/scene/variant labels, fork revision, GPU metadata, and software-renderer rejection.

The required one-hour stock/fork stability runs remain pending until Chromium binaries build.

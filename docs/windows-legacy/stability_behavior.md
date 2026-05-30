# Stability Behavior

Date: 2026-05-21

The viewer records graphics-loss, render-error, process-memory, and renderer-resource state in benchmark JSON. One-hour WebGL2 `instancing` stability evidence now exists for both same-revision stock `content_shell` and the fork viewer executable.

## One-Hour Evidence

| Variant | Artifact | Duration | GPU path | RSS delta | Renderer resources | Context/device loss |
| --- | --- | ---: | --- | ---: | --- | --- |
| `baseline-content-shell-long-stability` | `benchmarks/raw/baseline-content-shell-long-stability-instancing-webgl2.json` | 3600s measured, 30s warmup | NVIDIA ANGLE D3D11 | 114.26 MB | zero renderer resource growth | WebGL context loss 0, render errors 0 |
| `fork-viewer-default-long-stability` | `benchmarks/raw/fork-viewer-default-long-stability-instancing-webgl2.json` | 3600s measured, 30s warmup | NVIDIA ANGLE D3D11 | 105.98 MB | zero renderer resource growth | WebGL context loss 0, render errors 0 |

The fork one-hour run used the friendly stability window flags `--window-size=640,480`, `--window-position=40,40`, and `--force-device-scale-factor=1` to avoid saturating the desktop compositor while still requiring hardware GPU metadata and rejecting known software-rendered paths. Treat this as stability evidence, not as a stock-versus-fork FPS comparison.

The stability gate is `process_rss_delta_mb <= 128` and zero renderer resource growth for geometry, texture, and program deltas after warmup. Both one-hour artifacts passed `scripts/validate_metrics.mjs` and `scripts/validate_stability_result.mjs` with checkout build metadata, exact GN args hash, pinned Chromium revision, expected executable path, package-size evidence, GPU metadata, software-renderer rejection, launch-flag checks, and viewer flag metadata.

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

The one-hour WebGL2 stock and fork runs recorded `webgl_context_lost_count=0`.

## WebGPU Device Loss

Three.js `WebGPURenderer` exposes `onDeviceLost`, and the underlying `GPUDevice` exposes the `device.lost` promise. The viewer records both paths so performance evidence does not depend on Three.js forwarding the loss callback:

- `webgpu_device_lost`
- `webgpu_device_loss_reason`
- `webgpu_device_loss_message`
- `webgpu_device_loss_source`

The original Three.js callback is still invoked so upstream renderer behavior is preserved. Before emitting final benchmark JSON, the viewer waits one microtask/task turn so already queued `GPUDevice.lost` callbacks can stamp the result instead of racing the final `THREE_VIEWER_RESULT` line. WebGPU stress measurements disable timestamp-query GPU timing because timestamp queries caused device loss during suite investigation; WebGPU device-loss fields remain present in benchmark results and the suite/candidate gates reject device-loss-contaminated performance evidence.

## GPU Process Crash/Restart

The one-hour stability artifacts completed normally and no browser-side benchmark crash was reported. If the GPU process exits before a benchmark result, `scripts/run_benchmark.mjs` fails the run with `Browser exited before benchmark result`; the failed fork attempt before the friendly-window profile is retained in `benchmarks/tmp/build-logs/long-stability-fork-v1.err.log` as the example failure mode.

GPU process crash/restart behavior for this fork is therefore documented as fail-closed for benchmark evidence: a crash or early browser exit does not produce accepted stability JSON. The completed one-hour stock and fork runs did not record WebGL context loss, WebGPU device loss, or render errors.

## Benchmark Fields

Optional stability fields emitted by the viewer:

- `webgl_context_lost_count`
- `webgl_context_restored_count`
- `webgl_context_currently_lost`
- `webgl_last_context_loss_ms`
- `webgpu_device_lost`
- `webgpu_device_loss_reason`
- `webgpu_device_loss_message`
- `webgpu_device_loss_source`
- `render_error_count`
- `last_render_error`

These fields are diagnostic and are validated when present.

## Resource Growth Fields

During the measured window, the benchmark records renderer resource counters from `renderer.info`:

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

For the completed one-hour runs, geometry, texture, and program deltas are all zero after warmup.

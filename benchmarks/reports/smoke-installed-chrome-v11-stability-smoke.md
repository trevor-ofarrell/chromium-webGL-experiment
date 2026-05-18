# Runtime And Stability Smoke Summary

Browser: installed Chrome `148.0.7778.168`

Artifact: `benchmarks/raw/smoke-installed-chrome-v11-stability-smoke.json`

Status: pass

| Test | Status | Evidence |
| --- | --- | --- |
| Viewer launch | pass | Viewer loaded with canvas, HUD, and module script |
| WebGL2 context | pass | ANGLE D3D11 WebGL2 context created on NVIDIA GeForce RTX 5060 Ti |
| Web platform basics | pass | `requestAnimationFrame`, `performance.now`, Canvas 2D, and local `fetch` succeeded |
| Basic input events | pass | Pointer down/move/up, wheel, and keydown handlers received synthetic DOM events |
| WebGL context loss | pass | `WEBGL_lose_context` delivered one loss and one restoration event |
| WebGPU adapter/device | pass | Adapter and device created; reported WebGPU feature set |
| WebGPU device loss | pass | Explicit device destroy resolved `GPUDevice.lost` with reason `destroyed` |
| Three.js WebGPU render | pass | `WebGPURenderer` initialized with `WebGPUBackend` and rendered a 64x64 scene |
| Three.js cube render | pass | Center pixel readback returned nonblank green pixel |
| Texture load | pass | Local checker texture loaded and rendered; `createImageBitmap` is supported |
| Shader material | pass | Custom `ShaderMaterial` rendered expected blue channel |
| Benchmark run | pass | `many-draw-calls` WebGL2 benchmark emitted `THREE_VIEWER_RESULT` |

This is smoke evidence for the harness and stability signal plumbing only. It is not same-revision Chromium baseline evidence for performance claims.

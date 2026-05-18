# Runtime Smoke Summary

Browser: installed Chrome `148.0.7778.168`

Artifact: `benchmarks/raw/smoke-installed-chrome-v5-runtime-smoke.json`

Status: pass

| Test | Status | Evidence |
| --- | --- | --- |
| Viewer launch | pass | Viewer iframe loaded with canvas and HUD |
| WebGL2 context | pass | ANGLE D3D11 WebGL2 context created on NVIDIA GeForce RTX 5060 Ti |
| WebGPU adapter/device | pass | Adapter and device created; reported WebGPU feature set |
| Three.js cube render | pass | Center pixel readback returned nonblank green pixel |
| Texture load | pass | Local checker texture loaded and rendered; `createImageBitmap` is supported |
| Shader material | pass | Custom `ShaderMaterial` rendered expected blue channel |
| Benchmark run | pass | `many-draw-calls` WebGL2 benchmark emitted `THREE_VIEWER_RESULT` |

This is smoke evidence for the test harness only, not same-revision Chromium baseline evidence.

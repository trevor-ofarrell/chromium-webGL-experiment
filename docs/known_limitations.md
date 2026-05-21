# Known Limitations

Date: 2026-05-21

- The fork is an experimental content-shell-derived runtime for trusted local/bundled Three.js content. It is not a general browser.
- Only the Windows NVIDIA ANGLE D3D11 path is measured in the current evidence set. Vulkan, GL/EGL, and Metal require separate platform runs.
- WebGPU GPU timestamp timing is disabled in the official WebGPU suite because timestamp queries caused device loss during stress runs. WebGPU CPU-side metrics, adapter/device metadata, and scene coverage remain recorded.
- The default fork improves package size and WebGL2 p99/startup, but it does not improve average WebGL2 FPS in the official default profile and it regresses average WebGPU FPS in this evidence set.
- In-process GPU and single-process experiments show very large WebGL2 FPS gains in the trusted matrix, but they reduce crash isolation and can saturate the desktop. They remain explicit trusted-only experiments.
- Direct GPU presentation and Blink-disable gates are reserved switches only in this revision. Their measured rows are treated as no-op or negative evidence, not retained source optimizations.
- The one-hour fork stability run uses a smaller friendly window to avoid desktop saturation while still requiring NVIDIA ANGLE D3D11 metadata and rejecting software-rendered evidence. Do not compare its FPS against full-size official scene-suite runs.
- The viewer keeps Blink core DOM/layout/event loop, V8, Canvas, WebGL, WebGPU/Dawn, ANGLE, Viz, image decode, `createImageBitmap`, local fetch, and CDP automation because they are required by the benchmark viewer and test harness.
- Official WebGPU shader/postprocessing parity is practical rather than byte-identical to WebGL2 shader source. See `docs/webgpu_scene_coverage.md`.

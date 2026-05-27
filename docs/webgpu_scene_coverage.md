# WebGPU Scene Coverage

Date: 2026-05-21

The official WebGPU suite runs the same seven scene names as WebGL2 through Three.js `WebGPURenderer` where supported by the current Three.js path.

Official artifacts:

- `benchmarks/reports/official-webgpu-comparison.md`
- `benchmarks/reports/official-comparison-manifest.json`
- `benchmarks/raw/baseline-content-shell-webgpu-*-webgpu.json`
- `benchmarks/raw/fork-viewer-default-webgpu-*-webgpu.json`
- `benchmarks/raw/fork-viewer-aggressive-gpu-webgpu-*-webgpu.json`

| Scene | WebGPU coverage | Notes |
| --- | --- | --- |
| `many-draw-calls` | Supported | Uses many mesh submissions through WebGPU-compatible material paths. |
| `instancing` | Supported | Uses instanced geometry and records draw/triangle counts. |
| `shader-heavy` | Supported with approximate shader parity | Uses a Three.js WebGPU node material with a WGSL function and the same loop count as the WebGL GLSL scene. |
| `texture-streaming` | Supported | Exercises texture upload/streaming counters and frame-time variance; `webgpuBundleMode=static` wraps the stable mesh/material set while texture contents continue updating. |
| `postprocessing` | Supported with approximate effect parity | Uses a WebGPU-compatible `RenderTarget` plus full-screen pass to exercise render-target and presentation flow. |
| `large-static` | Supported | Exercises large static geometry and memory footprint. |
| `gltf-loader-stress` | Supported | Uses `GLTFLoader` to load the bundled glTF asset, then renders many mesh nodes through WebGPU-compatible material paths. |

WebGPU GPU timestamp timing is disabled in official stress runs because timestamp queries caused device loss during earlier stress cases. The official WebGPU artifacts still record adapter/device metadata, CPU frame time, JS time, render submission time, frame-time percentiles, draw calls, triangles, memory fields, startup, package size, and launch metadata.

# WebGPU Scene Coverage

Date: 2026-05-16

Current WebGPU smoke evidence is from installed Chrome only:

- Current raw JSON: `benchmarks/raw/smoke-installed-chrome-v17-webgpu-current-*-webgpu.json`
- Current summary: `benchmarks/reports/smoke-installed-chrome-v17-webgpu-current-summary.md`
- Earlier scene-name smoke: `benchmarks/raw/smoke-installed-chrome-v7-webgpu-*.json`
- Timestamp smoke: `benchmarks/raw/smoke-installed-chrome-v14-webgpu-timestamp-instancing-webgpu.json`
- Render-target postprocessing smoke: `benchmarks/raw/smoke-installed-chrome-v15-webgpu-postprocessing-render-target-webgpu.json`
- WGSL shader-heavy smoke: `benchmarks/raw/smoke-installed-chrome-v16-webgpu-shader-heavy-wgsl-webgpu.json`

These results validate that the harness can drive all scene names through `renderer=webgpu`. They are not same-revision stock/fork performance evidence.

| Scene | WebGPU status | Notes |
| --- | --- | --- |
| `many-draw-calls` | Supported smoke path | Uses the same object layout and material family through Three.js WebGPU support. Draw-call counts reported by Three.js WebGPU are not directly equivalent to WebGL renderer counters. |
| `instancing` | Supported smoke path | Uses `InstancedMesh` through Three.js WebGPU. |
| `shader-heavy` | Supported smoke path, partial shader parity | Uses a Three.js WebGPU node material with a WGSL function and the same loop count as the WebGL GLSL scene. It is not byte-identical shader code. |
| `texture-streaming` | Supported smoke path | Uses `CanvasTexture`/texture updates through Three.js WebGPU. Further validation should inspect upload path and memory growth under longer duration. |
| `postprocessing` | Supported smoke path, partial effect parity | Uses a WebGPU-compatible `RenderTarget` plus full-screen `MeshBasicMaterial` pass. It now exercises render-target and presentation flow, but does not yet match the WebGL custom blur/scanline shader. |
| `large-static` | Supported smoke path | Uses the same generated large indexed geometry through Three.js WebGPU. |
| `gltf-loader-stress` | Supported smoke path | Uses `GLTFLoader` to load the bundled glTF asset, then renders many `Mesh` nodes through Three.js WebGPU-compatible material paths. Installed-Chrome v12 smoke validates the path; same-revision stock/fork evidence is pending. |

## Required Follow-Up

Before claiming WebGPU performance parity or improvement:

1. Replace the WebGPU postprocessing copy pass with a custom WGSL/TSL effect shader if exact effect parity is needed.
2. Decide whether WebGL and WebGPU draw-call counters should be reported in separate fields or normalized through an explicit renderer-specific interpretation.
3. Re-run this suite against stock Chromium and the fork from the same pinned revision.

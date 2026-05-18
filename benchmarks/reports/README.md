# Benchmark Reports

Installed-Chrome smoke reports validate the benchmark harness only. They are not used for performance claims against the fork because the project requires stock Chromium and forked Chromium built from the same pinned revision.

Current preferred benchmark smoke artifacts:

- `smoke-installed-chrome-v6-benchmark-summary.md`
- `benchmarks/raw/smoke-installed-chrome-v6-*-webgl2.json`
- `benchmarks/raw/smoke-installed-chrome-v6-instancing-webgpu.json`

Current full WebGPU scene-name smoke artifacts:

- `smoke-installed-chrome-v17-webgpu-current-summary.md`
- `benchmarks/raw/smoke-installed-chrome-v17-webgpu-current-*-webgpu.json`
- Earlier suite: `smoke-installed-chrome-v7-webgpu-summary.md`
- Equivalence notes: `docs/webgpu_scene_coverage.md`

Current runtime smoke artifacts:

- `smoke-installed-chrome-v11-stability-smoke.md`
- `benchmarks/raw/smoke-installed-chrome-v11-stability-smoke.json`

The current runtime smoke covers viewer launch, WebGL2, `requestAnimationFrame`, Canvas, local `fetch`, `performance.now`, basic pointer/wheel/keyboard input events, WebGPU adapter/device and device-loss signals, a Three.js `WebGPURenderer` draw when WebGPU is available, texture loading, shader material rendering, and deterministic benchmark-result capture.

Current benchmark stability-field artifact:

- `benchmarks/raw/smoke-installed-chrome-v11-stability-fields-many-draw-calls-webgl2.json`

Current short stability wrapper validation:

- `smoke-installed-chrome-v6-short-stability.md`
- `benchmarks/raw/smoke-installed-chrome-v6-short-stability-instancing-webgl2.json`

Current trace capture smoke artifacts:

- `smoke-installed-chrome-v9-many-draw-calls-webgl2-trace-summary.md`
- `benchmarks/traces/smoke-installed-chrome-v9-many-draw-calls-webgl2-trace.json`
- `benchmarks/traces/smoke-installed-chrome-v9-many-draw-calls-webgl2-trace.result.json`

Current resource warmup smoke artifact:

- `benchmarks/raw/smoke-installed-chrome-v10-resource-warmup-shader-heavy-webgl2.json`

Current glTF loader stress smoke artifacts:

- `smoke-installed-chrome-v12-gltf-loader-stress-summary.md`
- `benchmarks/raw/smoke-installed-chrome-v12-gltf-loader-stress-webgl2.json`
- `benchmarks/raw/smoke-installed-chrome-v12-gltf-loader-stress-webgpu.json`

Current file-mode package smoke artifact:

- `smoke-installed-chrome-v13-file-gltf-loader-stress-summary.md`
- `benchmarks/raw/smoke-installed-chrome-v13-file-gltf-loader-stress-webgl2-allow-file-access.json`
- `benchmarks/raw/smoke-installed-chrome-v13-file-gltf-loader-stress-webgpu-allow-file-access.json`

Current WebGPU timestamp smoke artifact:

- `smoke-installed-chrome-v14-webgpu-timestamp-summary.md`
- `benchmarks/raw/smoke-installed-chrome-v14-webgpu-timestamp-instancing-webgpu.json`

Current WebGPU render-target postprocessing smoke artifact:

- `smoke-installed-chrome-v15-webgpu-postprocessing-render-target-summary.md`
- `benchmarks/raw/smoke-installed-chrome-v15-webgpu-postprocessing-render-target-webgpu.json`

Current WebGPU WGSL shader-heavy smoke artifact:

- `smoke-installed-chrome-v16-webgpu-shader-heavy-wgsl-summary.md`
- `benchmarks/raw/smoke-installed-chrome-v16-webgpu-shader-heavy-wgsl-webgpu.json`

Current renderer resource counter smoke artifacts:

- `smoke-installed-chrome-v18-renderer-resource-counters-summary.md`
- `benchmarks/raw/smoke-installed-chrome-v18-renderer-resource-counters-instancing-webgl2.json`
- `benchmarks/raw/smoke-installed-chrome-v18-renderer-resource-counters-instancing-webgpu.json`

Current artifact audit:

- `docs/prompt_to_artifact_checklist.md`
- Generated with `.\scripts\audit_artifacts.ps1`

Earlier installed-Chrome smoke reports are retained for continuity but predate the stricter metadata and size fields or the corrected `fork_revision` handling.

Official reports should use labels that identify the same-revision build variant, for example:

- `baseline-content-shell`
- `fork-viewer-default`
- `fork-viewer-trusted`

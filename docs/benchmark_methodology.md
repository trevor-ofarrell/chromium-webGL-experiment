# Benchmark Methodology

Date: 2026-05-21

The benchmark system compares stock Chromium `content_shell`, the default viewer fork, and trusted viewer experiments built from the same Chromium revision.

## Required Scene Suite

Implemented viewer scene names:

The viewer runs seven deterministic scenes:

- `many-draw-calls`
- `instancing`
- `shader-heavy`
- `texture-streaming`
- `postprocessing`
- `large-static`
- `gltf-loader-stress`

Renderer modes:

Each scene is exercised through WebGL2. WebGPU is exercised for the same scene names where Three.js WebGPU support is available.

## Runtime Surface

Runtime smoke validation covers:

- direct viewer launch
- WebGL2 context creation
- WebGPU adapter/device and Three.js `WebGPURenderer` creation when WebGPU suites are requested
- `requestAnimationFrame`
- Canvas
- local `fetch`
- `performance.now`
- texture loading and shader material smoke
- basic pointer, wheel, and keyboard input events
- WebGL context-loss and WebGPU device-loss signal recording
- navigation lock and file-navigation confinement for the fork

Official manifest smoke hashes:

- `benchmarks/raw/baseline-content-shell-runtime-smoke.json`
- `benchmarks/raw/fork-viewer-default-runtime-smoke.json`
- `benchmarks/raw/fork-viewer-default-navigation-lock.json`
- `benchmarks/raw/fork-viewer-default-file-navigation-lock.json`

## Metric Schema

Each JSON result must include:

- `chromium_revision`
- `fork_revision`
- `build_args_hash`
- `platform`
- `gpu_name`
- `driver_version`
- `angle_backend`
- `renderer_type`
- `scene_name`
- `warmup_seconds`
- `measured_seconds`
- `avg_fps`
- `p50_frame_ms`
- `p95_frame_ms`
- `p99_frame_ms`
- `one_percent_low_fps`
- `point_one_percent_low_fps`
- `avg_cpu_frame_ms`
- `avg_gpu_frame_ms`
- `avg_js_frame_ms`
- `avg_render_submission_ms`
- `avg_compositor_latency_ms`
- `avg_presentation_latency_ms`
- `max_frame_ms`
- `dropped_frames`
- `draw_calls`
- `triangles`
- `texture_upload_mb`
- `buffer_upload_mb`
- `shader_compile_events`
- `js_heap_mb`
- `gpu_memory_mb`
- `process_rss_mb`
- `startup_ms_to_first_frame`
- `browser_binary_size_mb`
- `viewer_bundle_size_mb`
- `package_size_mb`

Unavailable metrics are recorded as `null` rather than omitted.

Every benchmark JSON is validated by `scripts/validate_metrics.mjs`.

The harness enriches viewer-emitted metrics with checkout provenance, browser executable metadata, build args hash, package metadata, creates the output directory, and writes the final machine-readable JSON file. Fork benchmark results must identify the actual fork patch content through the fork revision stamp.

WebGPU GPU timestamp timing is disabled in the official WebGPU suite because timestamp queries caused device loss in stress runs. WebGPU adapter/device metadata and CPU-side frame metrics remain valid.

## Official Comparison

Command shape:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_official_comparison.ps1 -BaselineBrowser .\src\out\ReleaseBaseline\content_shell.exe -ForkBrowser .\src\out\ReleaseViewerDefault\content_shell.exe -BaselineBuildArgs .\src\out\ReleaseBaseline\args.gn -ForkBuildArgs .\src\out\ReleaseViewerDefault\args.gn -BaselinePackageDir .\benchmarks\packages\baseline-content-shell -ForkPackageDir .\benchmarks\packages\viewer-default -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming
```

Validation gates:

- exact expected browser executable paths
- exact expected GN args hashes
- exact expected Chromium revision
- exact expected fork revision for fork variants
- complete scene set for each renderer/variant
- matching duration and warmup
- hardware GPU metadata
- software-renderer rejection
- required raw frame-time samples
- required browser launch flags
- package-size evidence for packaged runs
- strict comparison report validation

Official reports:

- `benchmarks/reports/official-webgl2-comparison.md`
- `benchmarks/reports/official-webgpu-comparison.md`
- `benchmarks/reports/official-comparison-manifest.json`

Human-readable official comparison reports summarize FPS, low-FPS, frame-time, CPU/GPU/JS/submission, memory, startup, draw/triangle/upload, shader-event, binary, viewer, and package metrics.

## Trusted Experiment Matrix

Trusted experiments are fork-only runs behind `--viewer-trusted-content`. The current matrix includes:

- default trusted profile
- aggressive GPU profile
- in-process GPU
- single-process
- force ANGLE D3D11
- relaxed WebGL validation / pass-through command decoder
- reserved Blink-disable gate
- reserved direct-presentation gate

Trusted reports:

- `benchmarks/reports/trusted-experiment-matrix-webgl2-summary.md`
- `benchmarks/reports/trusted-experiment-matrix-webgl2-comparison.md`
- `benchmarks/reports/trusted-experiment-matrix-manifest.json`

Unsafe flags are evaluated one at a time where possible, documented with risk, and not promoted to default launch policy without matching stability evidence.

## Stability

One-hour stability uses:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_long_stability.ps1 -Browser .\src\out\ReleaseViewerDefault\content_shell.exe -Renderer webgl2 -Scene instancing -Duration 3600 -Warmup 30 -Label fork-viewer-default-long-stability -BuildArgs .\src\out\ReleaseViewerDefault\args.gn -PackageDir .\benchmarks\packages\viewer-default -ExpectedChromiumRevision 3a94d90ec3c04556622c56944796dd76753e0581 -ForkRevision 3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-cca4b9171b07 -ViewerMode -ViewerTrustedContent -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FriendlyWindow
```

Stability acceptance:

- at least 3600 measured seconds
- at least 30 warmup seconds
- expected browser executable and GN args hash
- pinned Chromium revision and fork revision where applicable
- package-size evidence
- hardware GPU metadata and software-renderer rejection
- `process_rss_delta_mb <= 128`
- zero geometry, texture, and program growth after warmup
- no accepted JSON from early browser exit or crash

Completed artifacts:

- `benchmarks/raw/baseline-content-shell-long-stability-instancing-webgl2.json`
- `benchmarks/raw/fork-viewer-default-long-stability-instancing-webgl2.json`

## Trace Capture

Official trace capture records Chrome trace JSON and benchmark sidecars for representative WebGL2 `many-draw-calls` runs. Trace sidecars are validated against browser path, scene, renderer, duration, warmup, start delay, launch flags, and embedded benchmark metadata.

Trace summaries:

- `benchmarks/reports/baseline-content-shell-many-draw-calls-webgl2-trace-summary.md`
- `benchmarks/reports/fork-viewer-default-many-draw-calls-webgl2-trace-summary.md`

## Reporting Rule

Performance claims must cite the official manifest and report path. Trusted experiment claims must cite the trusted matrix manifest and raw experiment files. Stability claims must cite the one-hour stability JSON and the stability validator result.

# Benchmark Methodology

Date: 2026-05-24

The benchmark system compares stock Chromium `content_shell`, the default viewer fork, and trusted viewer experiments built from the same Chromium revision. Fork benchmark results must identify the actual fork patch-series content through the fork revision stamp.

Current source revision:

- Chromium revision: `3a94d90ec3c04556622c56944796dd76753e0581`
- Fork revision stamp: `3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-1e2ab6bffef9`

## Required Scene Suite

The viewer runs seven deterministic scenes:

- `many-draw-calls`
- `instancing`
- `shader-heavy`
- `texture-streaming`
- `postprocessing`
- `large-static`
- `gltf-loader-stress`

Renderer modes:

- WebGL2 is exercised for every scene.
- WebGPU is exercised for the same scene names where Three.js WebGPU support is available.
- WebGPU `webgpuBundleMode` / BundleGroup render-bundle mode is part of the compatibility key for comparisons.

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
- `complexity`
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

Unavailable metrics are recorded as `null` rather than omitted. Every benchmark JSON is validated by `scripts/validate_metrics.mjs`.

Newer viewer builds also emit optional diagnostic fields that are not part of the required schema: `dropped_frame_rate`; `p95_cpu_frame_ms`, `p99_cpu_frame_ms`, `p95_js_frame_ms`, `p99_js_frame_ms`, `p95_render_submission_ms`, `p99_render_submission_ms`, `p95_gpu_frame_ms`, and `p99_gpu_frame_ms`; and per-frame timing series `cpu_frame_times_ms`, `js_frame_times_ms`, `render_submission_times_ms`, and `gpu_frame_times_ms` when available. Use `scripts/analyze_tail_breakdown.mjs` on matched baseline/fork JSON pairs to attribute p95/p99 regressions to frame pacing, JS/update, render submission, or GPU timing.

The harness enriches viewer-emitted metrics with checkout provenance, browser executable metadata, build args hash, package metadata, creates the output directory, and writes the final machine-readable JSON file.

Compatibility metadata includes GPU-settle warmup mode, WebGPU pipeline-quiet warmup settings, WebGPU BundleGroup mode, and profile-cache mode/key so cached, warmed, and bundle-mode runs are not mixed with fresh default evidence.

WebGPU GPU timestamp timing is disabled in the official WebGPU suite because timestamp queries caused device loss in stress runs. WebGPU adapter/device metadata and CPU-side frame metrics remain valid.

## Attribution Metrics

Viewer-side attribution modes are diagnostic only. They can explain where time is going, but they add JavaScript wrappers and cannot be promoted as clean performance evidence.

Supported attribution modes:

- `--queueInstrumentation` / `queueInstrumentation=1`: wraps WebGPU queue calls and records `writeBuffer`, `writeTexture`, `copyExternalImageToTexture`, `copyElementImageToTexture`, and `submit` counts/timing. Results also record descriptor-shape counts for common `writeTexture` layout/extent inputs and `copyExternalImageToTexture` default-origin, common-origin, explicit-common-origin, sRGB-destination, full-source, and common-extent inputs that map to the WebGPU upload fast paths.
- `--commandEncoderInstrumentation` / `commandEncoderInstrumentation=1`: wraps `GPUDevice.createCommandEncoder` plus command-encoder `beginRenderPass`, `beginComputePass`, `finish`, `copyBufferToBuffer`, `copyBufferToTexture`, `copyTextureToBuffer`, and `copyTextureToTexture` calls. Results record counts, wall-clock timing, render-pass color/depth/clearValue descriptor shape counts, estimated copy MB, and measured-window copy counts.
- WebGPU pipeline creation telemetry wraps `createRenderPipeline`, `createRenderPipelineAsync`, `createComputePipeline`, and `createComputePipelineAsync`; it records creation timing plus descriptor-shape counts for render-pipeline vertex buffers/attributes, fragment color targets/blend states, programmable-stage constants, and whether those descriptors are eligible for the source stack-conversion fast paths.
- bind-group, pipeline-state, buffer-state, render-state, and immediate-data attribution modes where present in the viewer and runner.
- source-added WebGPU queue trace attribution when the Chromium patch is built.

Candidate analysis and final suite validation reject attribution runs unless explicitly requested for investigation. Clean retained speed claims must filter out viewer-side WebGPU queue attribution, command-encoder attribution, bind-group attribution, pipeline-state attribution, buffer-state attribution, render-state attribution, immediate-data attribution, and source-added WebGPU queue trace attribution.

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

Human-readable official comparison reports summarize FPS, low-FPS, frame-time, CPU/GPU/JS/submission, memory, startup, draw/triangle/upload, shader-event, binary, viewer, and package metrics. Summary reports also include an optional WebGPU fast-path coverage section when queue or pipeline descriptor-shape attribution fields are present. Summary and comparison reports include an `Input file digest` so raw JSON inputs can be tied back to the rendered report.

## Alternating Paired Runs

When WebGPU results show run-order or thermal/state drift, use `scripts\run_alternating_pair_suite.ps1` before promoting a WebGPU speed claim. The runner executes stock and fork results scene-by-scene, alternating which side launches first, and writes a manifest plus analyzer input list. This avoids comparing an all-stock block against a later all-fork block when GPU driver state changes during the suite.

Example color-space-validation probe:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_alternating_pair_suite.ps1 `
  -BaselineBrowser .\src\out\ReleaseBaseline\content_shell.exe `
  -ForkBrowser .\src\out\ReleaseViewerDefault\content_shell.exe `
  -BaselineBuildArgs .\src\out\ReleaseBaseline\args.gn `
  -ForkBuildArgs .\src\out\ReleaseViewerDefault\args.gn `
  -BaselinePackageDir .\benchmarks\packages\baseline-content-shell `
  -ForkPackageDir .\benchmarks\packages\viewer-default `
  -Renderer webgpu -Duration 30 -Warmup 5 -Complexity 2 `
  -BaselineLabel baseline-content-shell-webgpu-alt-colorspace `
  -ForkLabel fork-viewer-exp-webgpu-colorspace-alt `
  -ForkRevision 3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-1e2ab6bffef9 `
  -ForkBenchmarkArg @("--viewerMode", "--viewerTrustedContent", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerRejectWebgpuCpuTextureFallback") `
  -DisableGpuTiming -RequireCheckout -RequireBuildArgs -RequireGpuMetadata -RequirePackageSize -RequireFrameTimes -RejectSoftwareRendering -RejectGpuInstability
```

For `-Repeats 1`, the output labels are directly compatible with `scripts\analyze_candidates.mjs`. For multiple repeats, treat each repeat label as a separate paired sample until an aggregate paired-analysis gate is used; do not collapse repeated runs by hand into retained evidence.

Post-policy WebGPU paired controls are recorded in `benchmarks/reports/alt-default-webgpu-manifest.json` and `benchmarks/reports/alt-warmup-webgpu-manifest.json`. The default paired run is useful triage evidence but not retained: it averaged +2.37% FPS and lower CPU/submission versus stock, then failed the strict gate on instancing 0.1% low FPS. The matched resource-warmup run is also not retained because glTF-loader-stress regressed in FPS, dropped-frame rate, and CPU/submission time.

Full-duration WebGPU color-conversion confirmations are recorded in `benchmarks/reports/alt-colorconv-webgpu-120-manifest.json` and `benchmarks/reports/alt-colorconv-webgpu-120b-manifest.json`. Both improved suite average FPS and p99 frame time, but neither is retained because glTF-loader-stress still tripped the CPU/render-submission overhead gate.

The later canvas-memory plus color-conversion pass is recorded in `benchmarks/reports/canvasmem-colorconv-120-webgpu-manifest.json`. Its focused glTF/texture probe passed, but the full seven-scene confirmation is not retained because average FPS regressed and glTF-loader-stress again tripped the full-suite blocker.

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

## Texture Upload Modes

The texture-streaming scene supports:

- `textureUploadMode=canvas`
- `textureUploadMode=data`

The DataTexture mode increases absolute texture-streaming throughput and exercises WebGPU queue/write paths differently from the canvas path. It is part of the comparison compatibility key and must not be mixed with canvas-mode results for retained claims.

DataTexture mode is diagnostic for upload-path attribution. Candidate analysis filters it from retained evidence by default; use `--includeDiagnosticTextureModes` only when explicitly investigating upload-mode behavior.

## Stability

One-hour stability uses:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_long_stability.ps1 -Browser .\src\out\ReleaseViewerDefault\content_shell.exe -Renderer webgl2 -Scene instancing -Duration 3600 -Warmup 30 -Label fork-viewer-default-long-stability -BuildArgs .\src\out\ReleaseViewerDefault\args.gn -PackageDir .\benchmarks\packages\viewer-default -ExpectedChromiumRevision 3a94d90ec3c04556622c56944796dd76753e0581 -ForkRevision 3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-1e2ab6bffef9 -ViewerMode -ViewerTrustedContent -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FriendlyWindow
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
- final JSON emission waits one microtask/task turn for queued WebGPU device-loss callbacks before stability fields are stamped

Completed artifacts:

- `benchmarks/raw/baseline-content-shell-long-stability-instancing-webgl2.json`
- `benchmarks/raw/fork-viewer-default-long-stability-instancing-webgl2.json`

## Trace Capture

Official trace capture records Chrome trace JSON and benchmark sidecars for representative WebGL2 runs. WebGPU diagnostic traces may enable `--queueInstrumentation` and `--commandEncoderInstrumentation` to attribute queue and command-encoder work, but those sidecars are attribution evidence only and are excluded from retained FPS claims. Reports and strict validators reject attribution-instrumented results as clean speed evidence.

Trace sidecars are validated against browser path, scene, renderer, duration, warmup, start delay, launch flags, embedded benchmark metadata, and mirrored WebGPU fast-path coverage counters when present. Trace summaries automatically read the sibling `.result.json` sidecar and add WebGPU queue/pipeline fast-path coverage when finite counters are available.

Trace summaries:

- `benchmarks/reports/baseline-content-shell-many-draw-calls-webgl2-trace-summary.md`
- `benchmarks/reports/fork-viewer-default-many-draw-calls-webgl2-trace-summary.md`

## Current Chromium Patch Classes

The current patch series documents or implements:

- minimal viewer entrypoint and trusted local navigation policy
- WebGPU queue attribution traces
- common WebGPU buffer descriptor conversion fast paths
- common WebGPU bind-group entry and bind-group descriptor conversion fast paths
- WebGPU render-pass clearValue GPUColor-dict conversion fast path
- WebGPU command-encoder descriptorless creation fast path
- WebGPU command-encoder `GPUExtent3D` conversion fast path for copy commands
- WebGPU command-encoder texel-copy buffer layout conversion fast path for common `{ buffer, bytesPerRow }` layouts
- WebGPU render-pipeline vertex/fragment descriptor stack conversion fast paths
- WebGPU programmable-stage shader-constant stack conversion fast path

All source-level WebGPU changes remain blocked from retained evidence until WDAC/App Control allows rebuilt Chromium artifacts to run.

## Reporting Rule

Performance claims must cite the official manifest and report path. Trusted experiment claims must cite the trusted matrix manifest and raw experiment files. Stability claims must cite the one-hour stability JSON and the stability validator result.

Do not claim a speed improvement from installed Chrome, stale binaries, attribution runs, software rendering, device-loss-contaminated runs, or runs that do not match the current Chromium revision and fork patch stamp.

# Known Limitations

Date: 2026-05-21

- The fork is an experimental content-shell-derived runtime for trusted local/bundled Three.js content. It is not a general browser.
- Historical evidence measured a Windows-specific ANGLE path. The WSL port starts over with Linux hardware WebGL2 evidence; Vulkan/GL/EGL/WebGPU parity requires separate platform runs.
- WebGPU GPU timestamp timing is disabled in the official WebGPU suite because timestamp queries caused device loss during stress runs. WebGPU CPU-side metrics, adapter/device metadata, and scene coverage remain recorded.
- The default fork improves package size and WebGL2 p99/startup, but it does not improve average WebGL2 FPS in the official default profile and it regresses average WebGPU FPS in this evidence set.
- The current WebGL2 speed candidate is zero-copy-only (`--viewer-zero-copy`, aliasing `--enable-zero-copy`). Full complexity-2 evidence improves average FPS, CPU/submit, dropped frames, and startup, but average lows and p95/p99 regress, so it cannot yet be retained as a default profile.
- The current follow-up WebGPU process candidates are not retained full-suite speedups. Single-process improves some CPU-bound scenes and greatly reduces RSS/startup, but the full complexity-2 suite is only +0.1% average FPS and regresses lows/tails. Default viewer mode improves texture-streaming tails but averages -0.2% FPS. In-process GPU helps draw-call/glTF probes but severely regresses texture-streaming.
- Deterministic DataTexture texture-streaming attribution does not currently rescue the WebGPU profile. It raises absolute texture-streaming throughput, but stock remains slightly faster than fork default, single-process is much slower, and Dawn `skip_validation` worsens the result on this host.
- WebGPU queue instrumentation is currently viewer-side and attribution-only. It identified CanvasTexture as a `copyExternalImageToTexture`/high-submit-count path and DataTexture as a `writeTexture` path, but its JavaScript wrappers add overhead and should not be used for final clean FPS claims.
- WebGL2 relaxed validation/pass-through is not currently a default retained speed profile. The patch now also adds a trusted Blink per-draw validation bypass under the same flag, so it requires a rebuilt full-suite retest before it can be promoted beyond experiment status.
- Current published trace summaries do not expose WebGPU CanvasTexture upload as explicit texture-upload events. A draft Chromium trace patch now adds Blink WebGPU queue events and `CopyFromCanvasSourceImage` path attribution for GPU-resident versus CPU-fallback texture copies, but a rebuilt fork and new traces are still required before source-level attribution can replace the viewer-side queue wrappers.
- The previous Windows build host blocked generated Chromium Rust build-script EXEs through Windows Application Control (`WinError 4551`). The WSL port avoids that host policy by rebuilding under Ubuntu 22.04 WSL2.
- In-process GPU and single-process experiments show very large WebGL2 FPS gains in the trusted matrix, but they reduce crash isolation and can saturate the desktop. They remain explicit trusted-only experiments.
- Direct GPU presentation and Blink-disable gates are reserved switches only in this revision. Their measured rows are treated as no-op or negative evidence, not retained source optimizations.
- Historical one-hour stability runs used a smaller friendly window to avoid desktop saturation while still rejecting software-rendered evidence. Do not compare historical FPS against new WSL scene-suite runs.
- The viewer keeps Blink core DOM/layout/event loop, V8, Canvas, WebGL, WebGPU/Dawn, ANGLE, Viz, image decode, `createImageBitmap`, local fetch, and CDP automation because they are required by the benchmark viewer and test harness.
- Official WebGPU shader/postprocessing parity is practical rather than byte-identical to WebGL2 shader source. See `docs/webgpu_scene_coverage.md`.

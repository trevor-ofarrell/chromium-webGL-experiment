# Future Work

Date: 2026-05-21

1. Re-run the full official and trusted suites on additional GPUs and drivers, especially Vulkan and GL/EGL on Windows and Metal on macOS.
2. Add a source-level direct presentation prototype only after a platform design identifies the native surface ownership and synchronization model.
3. Split content-shell service stubbing into single-purpose patches, each with smoke, trace, package-size, and scene-suite evidence.
4. Add WebGPU pipeline cache and shader warmup experiments that compare default and warmup modes with identical scene suites.
5. Improve WebGPU shader/postprocessing scene parity with custom WebGPU-compatible shader nodes or WGSL/TSL passes.
6. Add latency instrumentation for compositor/presentation timing where Chromium exposes stable trace or metric surfaces.
7. Build a smaller release package by removing unused runtime files from staged packages after hash and smoke validation.
8. Automate rebase checks so the viewer patch, source investigation map, GN args, and final docs are refreshed together.

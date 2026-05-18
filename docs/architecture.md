# Architecture

## Goal

Create a Chromium-derived runtime that launches directly into a trusted bundled Three.js viewer and keeps only the browser infrastructure needed for V8, Blink, Canvas, WebGL2, WebGPU, GPU acceleration, input, and local asset loading.

## Current Baseline Target

The first target is Chromium `content_shell`:

- GN target: `//content/shell:content_shell`
- Reason: it exercises Blink/V8/GPU/Viz without Chrome product UI, extensions, sync, profile UI, downloads UI, bookmarks UI, or tab strip.
- Limitation: it is still a testing shell, not yet a purpose-built viewer executable.

## Runtime Shape

Planned fork process model:

- Browser process owns one native window and one `WebContents`.
- Renderer process runs the bundled viewer app.
- GPU process remains enabled by default.
- Utility processes are kept only where Chromium requires them for graphics or local resource loading.

Trusted-content aggressive modes are opt-in and must remain behind explicit switches.

## Viewer App

The viewer is a bundled local Three.js application in `viewer/`.

It supports:

- WebGL2 renderer path.
- WebGPU renderer path when `navigator.gpu` and Three.js WebGPU support are available.
- Deterministic benchmark mode through URL parameters.
- JSON metric emission through console output for CDP capture.
- Local asset loading through the bundled static server or future Chromium embedded resource handler.

## Benchmark Control Plane

`scripts/run_benchmark.mjs` launches a Chromium executable with remote debugging enabled, serves the viewer locally, captures the viewer JSON result from the console, enriches it with host-side metadata, validates the schema, and writes a JSON artifact.

This runner is used for:

- Stock Chromium/content_shell baseline.
- Fork default-safe optimization profile.
- Fork trusted-content aggressive optimization profile.

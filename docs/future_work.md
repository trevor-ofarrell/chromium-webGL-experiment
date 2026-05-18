# Future Work

This list is intentionally limited to work that should follow the first same-revision stock-vs-fork comparison.

1. Build the stock `content_shell` baseline after ATL/MFC is installed.
2. Apply the viewer entrypoint patch and build `ReleaseViewerDefault`.
3. Run the WebGL2 and WebGPU benchmark suites against stock and fork binaries.
4. Run the HTTP and file navigation-lock smoke tests against the fork binary; they now cover same-origin HTTP, loopback cross-origin blocking, deterministic external HTTP blocking, packaged file-directory confinement, and file escape attempts.
5. Stage stock and fork package directories from real binaries, populate baseline/fork `package_size_mb`, and verify the packaged fork launcher.
6. Add larger imported real-world Three.js scenes with GLTF/texture assets.
7. Improve WebGPU shader/effect parity where useful, especially custom postprocessing WGSL/TSL effects.
8. Capture Chromium traces for WebGL and WebGPU paths, then classify renderer, GPU, Viz, ANGLE, Dawn, shader compile, and texture upload costs.
9. Implement or benchmark trusted-only aggressive flags one at a time:
   - `--viewer-aggressive-gpu`
   - `--viewer-relaxed-webgl-validation` pass-through command decoder alias
   - `--viewer-in-process-gpu`
   - `--viewer-single-process`
   - `--viewer-force-angle-backend`
   - `--viewer-disable-unneeded-blink-features`
   - `--viewer-direct-gpu-presentation`
10. Run one-hour stock and fork stability loops with an agreed RSS growth threshold.
11. Convert kept patch experiments into clear commits and document rebase conflicts against a newer Chromium revision.

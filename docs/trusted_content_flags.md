# Trusted-Content Flags

These switches are part of the draft content-shell-derived viewer patch. Unsafe behavior is gated by both `--viewer-app-url` and `--viewer-trusted-content`; the browser should not apply aggressive aliases outside viewer mode or without the trusted-content switch.

`scripts/test_viewer_patch_trusted_gates.ps1` statically verifies the draft patch keeps unsafe Chromium switch aliases inside the trusted-content configuration function, requires the `--viewer-app-url` plus `--viewer-trusted-content` early return guard, maps the relaxed WebGL validation experiment to Chromium's pass-through command decoder switch, and keeps unimplemented reserved experiment gates as no-ops until a measured source experiment is implemented.

The primary benchmark, smoke, trace, and package launchers include `--disable-software-rasterizer` even outside `--viewer-aggressive-gpu` so primary evidence fails closed rather than using Chromium's software rasterizer. The aggressive GPU alias still includes the same native switch because packaged/manual launches may use the viewer patch directly without the harness defaults; benchmark and stability validators also reject SwiftShader, WARP, llvmpipe, software rasterizer, and software renderer metadata.

| Viewer switch | Current behavior | Risk | Status |
| --- | --- | --- | --- |
| `--viewer-app-url=<url-or-path>` | Loads the viewer URL/path at startup and hides the content-shell toolbar | Low for local viewer, not a browser mode | Draft patch applies, build pending |
| `--viewer-block-external-navigation` | Adds a navigation throttle that allows the viewer HTTP origin or the local viewer directory for file-mode launch, and blocks other top-level navigations; blocks non-current-tab opens | Medium if the allowed origin/directory is too broad | Draft patch applies, runtime test pending |
| `--viewer-trusted-content` | Enables trusted-only switch aliasing only when `--viewer-app-url` is also present. When `--viewer-app-url` is a local path or `file://` URL, it also aliases to Chromium's `--allow-file-access-from-files` so bundled modules and assets can load from the local package. | High if used for arbitrary web content; file access is only acceptable for the trusted local package mode | Draft patch applies; installed-Chrome v13 smoke shows file-mode glTF loading requires this class of file access |
| `--viewer-aggressive-gpu` | With trusted content, aliases to `--disable-software-rasterizer`, `--enable-unsafe-webgpu`, `--enable-webgpu-developer-features`, `--force-high-performance-gpu`, and `--no-delay-for-dx12-vulkan-info-collection` | High: changes GPU fallback/blocklist behavior and WebGPU exposure | Draft patch applies, benchmark pending |
| `--viewer-in-process-gpu` | With trusted content, aliases to `--in-process-gpu` | High: reduces process isolation and can increase crash blast radius | Draft patch applies, benchmark pending |
| `--viewer-single-process` | With trusted content, aliases to `--single-process` | High: reduces process isolation and may be unstable | Draft patch applies, benchmark pending |
| `--viewer-force-angle-backend=<backend>` | With trusted content and non-`default` value, aliases to `--use-angle=<backend>` | Medium to high: backend-dependent correctness and stability risk | Draft patch applies, benchmark pending |
| `--viewer-relaxed-webgl-validation` | With trusted content, aliases to `--use-cmd-decoder=passthrough` for a measured WebGL command-decoder validation-overhead experiment | Very high: reduces Chromium's validating command-decoder coverage and can expose driver correctness or stability issues | Draft patch applies, benchmark pending |
| `--viewer-disable-unneeded-blink-features` | Reserved gate only; no Blink feature removal yet | Medium to high compatibility risk | Pending source experiment |
| `--viewer-direct-gpu-presentation` | Reserved gate only; no compositor/presentation bypass yet | High correctness and platform risk | Pending source experiment |

## Benchmark Runner Support

`scripts/run_benchmark.mjs` supports fork viewer launch through:

```powershell
node .\scripts\run_benchmark.mjs `
  --browser .\src\out\ReleaseViewerDefault\content_shell.exe `
  --variant fork-viewer-default `
  --viewerMode `
  --viewerTrustedContent `
  --scene many-draw-calls `
  --renderer webgl2 `
  --duration 120 `
  --warmup 20 `
  --buildArgs .\src\out\ReleaseViewerDefault\args.gn `
  --output .\benchmarks\raw\fork-viewer-default-many-draw-calls-webgl2.json
```

Aggressive runs add only the explicit experimental switches being measured:

```powershell
--viewerAggressiveGpu --viewerForceAngleBackend d3d11
```

Each aggressive run must be compared against stock Chromium and the fork default profile from the same Chromium revision before it can be kept.

Raw benchmark JSON records the requested trusted viewer flags so each per-scene result remains self-describing outside the matrix manifest:

- `viewer_trusted_content`
- `viewer_block_external_navigation`
- `viewer_aggressive_gpu`
- `viewer_relaxed_webgl_validation`
- `viewer_in_process_gpu`
- `viewer_single_process`
- `viewer_force_angle_backend`
- `viewer_disable_unneeded_blink_features`
- `viewer_direct_gpu_presentation`
- `requested_angle_backend`
- `browser_flags`
- `browser_extra_flags`

`browser_flags` is the complete effective browser launch argument list assembled by the benchmark, smoke, or trace harness; `browser_extra_flags` is only the caller-provided pass-through additions. Official/trusted suite, smoke, trace, and long-stability validation can require specific effective flags, currently `--disable-software-rasterizer`, before accepting final evidence. `requested_angle_backend` is populated from either the direct harness `--angleBackend` path or the trusted viewer `--viewerForceAngleBackend` alias. This keeps aggressive ANGLE backend runs auditable even when the fork patch, rather than the harness, forwards the native Chromium `--use-angle` switch.

`scripts/test_benchmark_flag_metadata.ps1` verifies the runner emits these fields, rejects unsafe viewer experiment flags unless both `--viewerMode` and `--viewerTrustedContent` are present, and `scripts/validate_metrics.mjs` accepts their types.
`scripts/validate_benchmark_suite.mjs --expectedFlagMetadata key=value` is used by the official and trusted matrix workflows to reject suite results whose recorded flag metadata does not match the intended stock/fork/trusted profile.

## File-Mode Package Launch

The viewer bundle is built with relative asset paths so `viewer/dist/index.html` can be opened as a local file. Stock Chrome required `--allow-file-access-from-files` for the `gltf-loader-stress` file-mode smoke in both WebGL2 and WebGPU modes:

```powershell
node .\scripts\run_benchmark.mjs `
  --browser "C:\Program Files\Google\Chrome\Application\chrome.exe" `
  --variant smoke-installed-chrome-v13-file-gltf-allow-file-access `
  --scene gltf-loader-stress `
  --renderer webgl2 `
  --viewerFileMode `
  --browser-flag --allow-file-access-from-files `
  --output .\benchmarks\raw\smoke-installed-chrome-v13-file-gltf-loader-stress-webgl2-allow-file-access.json
```

The fork patch applies the equivalent file-access switch only when `--viewer-trusted-content` is present and `--viewer-app-url` is a local file/path.

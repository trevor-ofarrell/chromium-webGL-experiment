# Trusted Content Flags

Date: 2026-05-21

Unsafe behavior is gated by both `--viewer-app-url` and `--viewer-trusted-content`. The fork keeps reserved experiment gates as no-ops unless a source implementation exists, and maps the relaxed WebGL validation experiment to Chromium's pass-through command decoder switch. Each aggressive run must be compared against stock Chromium and the fork default profile from the same Chromium revision.

| Viewer switch | Current behavior | Risk | Status |
| --- | --- | --- | --- |
| `--viewer-app-url=<url-or-path>` | Loads the viewer URL/path at startup and hides the content-shell toolbar | Low for local viewer, not a browser mode | Kept default viewer entrypoint |
| `--viewer-block-external-navigation` | Adds a navigation throttle that allows the viewer HTTP origin or local viewer directory for file-mode launch, and blocks other top-level navigations and non-current-tab opens | Medium if the allowed origin/directory is too broad | Kept default viewer policy |
| `--viewer-trusted-content` | Enables trusted-only aliases for GPU/process experiments when viewer mode is active | Medium: weakens assumptions suitable only for bundled content | Required gate for unsafe flags |
| `--viewer-aggressive-gpu` | With trusted content, aliases GPU/WebGPU enablement and high-performance GPU selection flags | High: changes GPU fallback and WebGPU exposure | Kept trusted experiment |
| `--viewer-in-process-gpu` | With trusted content, aliases to `--in-process-gpu` | High: reduces GPU crash isolation | Kept trusted experiment |
| `--viewer-single-process` | With trusted content, aliases to `--single-process` | High: reduces process isolation and can destabilize the host session | Kept trusted experiment |
| `--viewer-force-angle-backend=<backend>` | With trusted content and non-`default` value, aliases to `--use-angle=<backend>` | Medium to high: backend correctness and performance depend on driver/platform | Kept trusted experiment; D3D11 is measured useful on Windows |
| `--viewer-relaxed-webgl-validation` | With trusted content, aliases to `--use-cmd-decoder=passthrough` for command-decoder validation-overhead testing | Very high: reduces Chromium validating-command-decoder coverage | Kept trusted experiment with benchmark evidence |
| `--viewer-disable-unneeded-blink-features` | Reserved gate only; no Blink feature removal source change in this revision | Medium to high compatibility risk | Reserved no-op gate with measured matrix row |
| `--viewer-direct-gpu-presentation` | Reserved gate only; no compositor/presentation bypass source change in this revision | High correctness and platform risk | Reserved no-op gate with negative matrix evidence |

Benchmark metadata fields used to audit these flags:

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

Trusted matrix evidence:

- `benchmarks/reports/trusted-experiment-matrix-manifest.json`
- `benchmarks/reports/trusted-experiment-matrix-webgl2-comparison.md`
- `benchmarks/reports/trusted-experiment-matrix-webgl2-summary.md`

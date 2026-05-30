# Minimal Viewer Entrypoint Patch

The minimal viewer entrypoint patch turns Chromium content shell into a single-purpose local Three.js viewer runtime while preserving Blink, V8, Canvas, WebGL2, WebGPU/Dawn, ANGLE, GPU process infrastructure, Viz/compositor plumbing, native window creation, and CDP automation support.

Patch file:

- `chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch`

Touched Chromium source files:

- `content/shell/app/shell_main_delegate.cc`
- `content/shell/browser/shell.cc`
- `content/shell/browser/shell_browser_main_parts.cc`
- `content/shell/browser/shell_content_browser_client.cc`
- `content/shell/common/shell_switches.h`
- `third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc`
- `third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.h`

Viewer switches:

- `--viewer-app-url=<file-or-local-url>`
- `--viewer-trusted-content`
- `--viewer-block-external-navigation`
- `--viewer-force-angle-backend=<default|d3d11|vulkan|gl|metal>`
- `--viewer-aggressive-gpu`
- `--viewer-in-process-gpu`
- `--viewer-single-process`
- `--viewer-relaxed-webgl-validation`
- `--viewer-zero-copy`
- `--viewer-disable-unneeded-blink-features`
- `--viewer-direct-gpu-presentation`

Implemented behavior:

1. `--viewer-app-url` has launch precedence over positional URLs and the content shell default startup URL.
2. Absolute local paths supplied to `--viewer-app-url` are normalized as `file://` viewer launches before generic `GURL` handling, which covers Windows paths such as `C:\...\viewer\index.html`.
3. Content shell toolbar UI is hidden when viewer mode is active.
4. `--viewer-block-external-navigation` installs a navigation throttle that confines URL launches to the configured origin and file launches to the viewer file or files beneath the viewer app directory.
5. New-window and tab creation are denied in viewer navigation-lock mode.
6. Viewer-mode console messages beginning with `THREE_VIEWER_RESULT` are forwarded to stdout for packaged/manual launch evidence.
7. Trusted aliases are applied only when `--viewer-app-url` and `--viewer-trusted-content` are both present.

Trusted aliases and risk:

- `--viewer-force-angle-backend` maps to Chromium/ANGLE backend selection. WSL evidence starts with the platform default hardware WebGL2 path and only treats explicit backend probes as trusted experiments after host support is verified.
- `--viewer-relaxed-webgl-validation` maps to Chromium pass-through command decoder behavior and skips Blink WebGL per-draw validation checks for trusted local content. The trusted matrix shows WebGL2 gains for the pre-source alias, but the deeper Blink draw-validation bypass still requires a rebuilt fork retest before any additional speed claim.
- `--viewer-zero-copy` maps to Chromium `--enable-zero-copy` for trusted WebGL2 throughput experiments. It remains a candidate rather than a retained default because the current full-suite evidence improves average FPS but regresses low-FPS/tail metrics, and WebGPU zero-copy evidence regressed.
- `--viewer-aggressive-gpu`, `--viewer-in-process-gpu`, and `--viewer-single-process` are trusted-only process/GPU experiments. In-process and single-process modes show large WebGL2 FPS gains and high crash-isolation risk, so they are not default launch policy.
- `--viewer-disable-unneeded-blink-features` and `--viewer-direct-gpu-presentation` are reserved gates. Their current measured matrix rows are treated as no-op or negative-evidence rows, not retained source optimizations.

Evidence:

- Static patch tests cover switch definitions, launch precedence, toolbar suppression, navigation lock wiring, file confinement, stdout result forwarding, and trusted gate requirements.
- Runtime artifacts include `fork-viewer-default-runtime-smoke.json`, `fork-viewer-default-navigation-lock.json`, and `fork-viewer-default-file-navigation-lock.json`.
- Official stock/fork comparison artifacts are recorded under `benchmarks/reports/official-comparison-manifest.json`.
- Trusted experiment artifacts are recorded under `benchmarks/reports/trusted-experiment-matrix-manifest.json`.
- Subsystem decisions and risk are tracked in `docs/removed_subsystems.md`.
- Final optimization outcomes are tracked in `docs/optimization_log.md`.

Rebase notes:

- Keep deeper Blink changes small, explicitly trusted-gated, and tied to benchmark evidence before promoting them beyond experiment status.
- Re-run `scripts/verify_prebuild.sh` after each patch refresh, then rebuild stock and fork outputs from the same Chromium revision before claiming performance effects.
- Rebuild stock and fork outputs from the same Chromium revision before claiming performance effects.

# Minimal Viewer Entrypoint Plan

Status: draft patch created and `git apply --check` passes against the synced `src` checkout. It is not applied yet because the same checkout is still needed for the unmodified stock baseline build.

Use Chromium's content shell as the first fork base because it already preserves Blink, V8, Canvas, WebGL, WebGPU/Dawn, ANGLE, the GPU process, Viz/compositor plumbing, and native window creation without Chrome's browser product UI.

Candidate source areas to inspect after checkout:

- `content/shell/BUILD.gn`
- `content/shell/app/`
- `content/shell/browser/shell.cc`
- `content/shell/browser/shell_browser_main_parts.*`
- `content/shell/browser/shell_content_browser_client.*`
- `content/shell/common/shell_switches.*`
- `content/public/browser/navigation_throttle.*`
- `content/public/browser/content_browser_client.*`

First fork entrypoint behavior:

1. Add viewer switches:
   - `--viewer-app-url=<file-or-local-url>`
   - `--viewer-trusted-content`
   - `--viewer-block-external-navigation`
   - `--viewer-force-angle-backend=<default|d3d11|vulkan|gl|metal>`
   - `--viewer-aggressive-gpu`
   - `--viewer-in-process-gpu`
   - `--viewer-single-process`
   - `--viewer-relaxed-webgl-validation`
   - `--viewer-disable-unneeded-blink-features`
   - `--viewer-direct-gpu-presentation`
2. On startup, create exactly one shell/window and load `--viewer-app-url`.
3. Suppress URL entry, new-window affordances, and any debug UI not explicitly requested.
4. Add a navigation throttle that allows only the configured local trusted origin and blocks everything else.
5. Preserve DevTools remote debugging only for benchmark automation.
6. Forward the viewer benchmark completion marker to stdout so packaged/manual launches can surface results without CDP.
7. Emit startup milestone timing to stdout where possible.

Draft patch:

- `chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch`

Patch source files:

- `content/shell/app/shell_main_delegate.cc`
- `content/shell/browser/shell.cc`
- `content/shell/browser/shell_browser_main_parts.cc`
- `content/shell/browser/shell_content_browser_client.cc`
- `content/shell/common/shell_switches.h`

Patch behavior:

- Adds `--viewer-app-url`.
- Hides the content shell toolbar automatically when `--viewer-app-url` is present.
- Adds `--viewer-block-external-navigation`.
- Blocks new-window/tab creation in viewer navigation lock mode.
- Adds a navigation throttle that allows same-origin viewer navigations for URL launch, allows only the viewer file or files under the viewer app directory for file launch, and blocks external top-level navigations.
- Adds viewer-mode trusted-only aliases for `--viewer-force-angle-backend`, `--viewer-relaxed-webgl-validation`, `--viewer-aggressive-gpu`, `--viewer-in-process-gpu`, and `--viewer-single-process`; the aliases require both `--viewer-app-url` and `--viewer-trusted-content`.
- Normalizes absolute local paths passed to `--viewer-app-url` with `GetSwitchValuePath` before generic `GURL` handling so Windows paths such as `C:\...\viewer\index.html` are treated as `file://` viewer launches.
- In viewer mode, forwards console messages beginning with `THREE_VIEWER_RESULT` to stdout and leaves other console messages on content shell's default path.
- Reserves explicit no-op gates for Blink feature disabling and direct GPU presentation. The relaxed WebGL validation gate now maps to Chromium's existing pass-through command decoder switch and still requires measurement before it can be kept.
- Does not yet implement stdout startup milestones; those remain separate experiments after the baseline/fork comparison is working.

Risk notes:

- Content shell changes are less invasive than editing Chrome browser code, but still depend on content shell internals that can shift during upstream rebases.
- Blocking navigation in `WebContentsDelegate` alone is insufficient because renderer-initiated and redirect navigations need throttling before commit.
- WebGPU availability still depends on Chromium feature flags, platform GPU blocklists, Dawn backend support, and OS/driver state.

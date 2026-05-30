# Removed Or Disabled Subsystems

Date: 2026-05-21

This register documents what the Chromium viewer fork removes, avoids, disables, keeps, or rejects for this revision. The fork is based on `content_shell`, with the viewer patch recorded in `chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch` and measured through the official and trusted benchmark artifacts.

## Final Register

| Subsystem or feature | Decision | Rationale | Regression risk | Current evidence |
| --- | --- | --- | --- | --- |
| Chrome browser frame, tab strip, omnibox, and toolbar | Kept out of the runtime through the content-shell target and viewer toolbar suppression | The viewer needs one native window and one `WebContents`, not a general browser UI | Medium: content shell is not Chrome product UI and arbitrary browsing is outside scope | `official-comparison-manifest.json`; `official-webgl2-comparison.md`; `content/shell/browser/shell.cc` patch notes |
| Chrome extensions | Disabled/avoided | Trusted bundled scenes do not need extension installation, extension messaging, or extension UI | Low for viewer; high for browsing | Launch flags in raw results include `--disable-extensions`; official suites completed |
| Chrome sync | Disabled/avoided | No signed-in profile or cross-device state is needed | Low for viewer | Launch flags include `--disable-sync`; official suites completed |
| Autofill server communication | Disabled | No form-fill workflow exists in the viewer | Low for viewer | Launch flags include `--disable-features=...AutofillServerCommunication`; official suites completed |
| Translate UI | Disabled/avoided | Local trusted scenes do not need page translation | Low for viewer | Launch flags include `Translate` disablement; official suites completed |
| Bookmarks and history UI | Avoided | The runtime does not expose browsing state or tab workflows | Low for viewer | Content-shell target plus no browser chrome; package is 130.3 MB smaller than stock package |
| Password manager and payments UI | Avoided | No credential or checkout workflow is present | Low for viewer | Content-shell target and navigation lock evidence |
| Downloads UI and arbitrary download flow | Avoided in viewer flow | The runtime loads bundled/local assets and blocks arbitrary external navigation | Medium: incorrectly classified asset responses could touch download code | `fork-viewer-default-navigation-lock.json`; `fork-viewer-default-file-navigation-lock.json` |
| Background networking and component updates | Disabled in launch profile | Benchmark and viewer packages must run without remote dependency | Low for bundled content | Raw benchmark `browser_flags`; official and trusted manifests |
| Safe Browsing product service surface | Avoided by target and local navigation policy | Trusted bundled content does not need remote URL reputation services | Medium if remote navigation is added later | Navigation lock artifacts and content-shell target evidence |
| Browser profile product services | Minimized by content shell; deeper stubs deferred to source-size work | The viewer needs a lightweight context but still needs storage, fetch, and GPU/content plumbing | Medium: content-shell delegates support tests and diagnostics | `docs/source_investigation.md`; official runtime smoke and suites |
| New-window and tab creation | Disabled in viewer mode | The viewer owns exactly one surface | Low for viewer | Viewer patch notes and `fork-viewer-default-navigation-lock.json` |
| External top-level navigation | Disabled in viewer mode | Prevents leaving the trusted viewer origin | Medium: strict policy can break legitimate local asset paths if configured incorrectly | `fork-viewer-default-navigation-lock.json` |
| File URL escape outside packaged viewer directory | Disabled in file viewer mode | File packages need local assets but not arbitrary local-file traversal | Medium: file URL policy is security-sensitive | `fork-viewer-default-file-navigation-lock.json` |
| DevTools/CDP | Kept | Benchmark harness, smoke tests, traces, and result capture require CDP | Medium if removed | `run_benchmark.mjs`; `run_trace_capture.mjs`; official trace summaries |
| V8 | Kept | Required by the objective and by Three.js | High if changed | Runtime smoke and scene suites execute module JS through V8 |
| Blink DOM/layout/event loop | Kept | Three.js viewer needs module loading, canvas placement, input events, fetch, `requestAnimationFrame`, and `performance.now` | High | `fork-viewer-default-runtime-smoke.json`; `docs/source_investigation.md` |
| Canvas/WebGL/WebGPU/Dawn/ANGLE/GPU process/Viz | Kept | Required render infrastructure | High | Official WebGL2/WebGPU suites and stability GPU metadata |
| Image decode, `ImageBitmap`, and local asset loading | Kept | Texture loaders, glTF stress, and streaming scenes need these APIs | High | Runtime smoke and texture/gltf benchmark scenes |
| Media playback | No source removal in this revision | Image and texture paths can share media/image infrastructure; no size win was proven by source removal | Medium | `docs/source_investigation.md`; official texture and glTF scenes |
| WebRTC | No source removal in this revision | It is unrelated to bundled scenes, but source removal was not part of the measured patch set | Medium for build graph churn | `docs/source_investigation.md`; no retained source patch |
| PDF and printing | No source removal in this revision | Not used by viewer workflow; source trim left for a later size-only branch | Low for viewer, medium for Chromium build churn | `docs/source_investigation.md`; no retained source patch |
| Accessibility | Kept | Removing accessibility has product and test consequences and was not necessary for measured wins | High | No retained source patch |
| Spellcheck | No source removal in this revision | No text editing workflow exists, but no measured source trim was retained | Low for viewer | Optimization decision table marks it not useful for this revision |
| ANGLE backend forcing | Kept as trusted experiment | D3D11 backend choice improved the trusted WebGL2 matrix | Medium: driver/platform dependent | `trusted-experiment-matrix-webgl2-comparison.md` |
| Pass-through command decoder / relaxed WebGL validation | Kept as trusted experiment | Trusted matrix showed WebGL2 FPS and p99 gains | High: validation/security tradeoff | `fork-viewer-exp-relaxed-webgl-validation-gate-*.json`; trusted report |
| In-process GPU and single-process | Kept as trusted experiments only | Large FPS gains in WebGL2 trusted matrix, with crash isolation and desktop-saturation risk | Very high | `trusted-experiment-matrix-webgl2-comparison.md`; one-hour default stability remains normal process mode |
| Direct GPU presentation/compositor bypass | Rejected for this revision | Reserved gate showed no useful measured benefit and no source implementation is retained | Very high | `fork-viewer-exp-direct-gpu-presentation-gate-*.json`; trusted report |
| Unused Blink module removal | Rejected for this revision | Reserved gate had no source implementation and the viewer still depends on broad Blink runtime APIs | High | Runtime smoke, source investigation, trusted matrix |
| Layout/style/DOM feature removal | Rejected for this revision | Required APIs are part of the viewer runtime surface | High | Runtime smoke and viewer source |
| V8 flag tuning | Rejected for this revision | No retained V8 flag showed a measured benefit in official or trusted evidence | Medium | Official manifest and optimization log |
| Memory allocator changes | Rejected for this revision | No allocator change was included in the measured patch set | High | Official manifest and optimization log |

## Prompt Optimization Class Tracking

| Optimization class | Register decision |
| --- | --- |
| remove Chrome browser UI layer | Kept through content-shell target and viewer chrome suppression |
| minimal content shell style entrypoint | Kept through the viewer entrypoint patch |
| single local trusted origin | Kept through viewer URL, external navigation lock, and file confinement |
| disable extensions | Kept through target choice and launch flag |
| disable sync | Kept through target choice and launch flag |
| disable autofill | Kept through launch feature disablement |
| disable translate | Kept through launch feature disablement |
| disable spellcheck | Rejected as a source trim for this revision |
| disable safe browsing services not needed for local trusted content | Kept through local navigation policy and content-shell target |
| disable downloads UI | Kept by removing the viewer workflow path to arbitrary downloads |
| disable history/bookmarks UI | Kept through content-shell target |
| disable unnecessary profile services | Minimized through content shell; deeper source work deferred |
| disable unnecessary background networking | Kept through launch flags |
| reduce renderer process overhead where possible | Kept as trusted process-model experiments |
| evaluate single-process/in-process GPU | Kept as trusted flags only |
| evaluate ANGLE backend choices | Kept; D3D11 is the measured Windows backend |
| evaluate Vulkan, D3D11, OpenGL/EGL, and Metal path implications | Kept for Windows D3D11 evidence; other platforms require separate runs |
| evaluate passthrough command decoder | Kept as trusted experiment |
| evaluate WebGL validation overhead | Kept as trusted experiment |
| evaluate shader compilation strategy | Kept through scene coverage, warmup controls, and trace support |
| evaluate WebGPU pipeline caching/warmup | Kept through WebGPU scene coverage and timing-mode controls |
| evaluate compositor bypass or simplified presentation path | Rejected for this revision |
| evaluate direct GPU texture presentation/export | Rejected for this revision |
| evaluate removing unused Blink modules | Rejected for this revision |
| evaluate disabling layout/style/DOM features not required by the viewer | Rejected for this revision |
| evaluate disabling media, printing, PDF, WebRTC, accessibility, password manager, payments, and other unrelated features | Product UI pieces are avoided; deeper source removals are not retained in this revision |
| evaluate V8 flags relevant to startup and steady-state JS performance | Rejected for this revision |
| evaluate memory allocator and process model choices | Process-model experiments kept as trusted flags; allocator changes rejected |

## Subsystems Explicitly Kept For Now

| Subsystem | Kept because | Notes |
| --- | --- | --- |
| V8 | Required by the objective | Three.js, loaders, and benchmark harness scripts execute through V8 |
| Blink core DOM/layout/event loop | Required for viewer APIs | Includes module loading, canvas sizing, events, `fetch`, `requestAnimationFrame`, and `performance.now` |
| Canvas/WebGL/WebGPU/Dawn/ANGLE/GPU process/Viz | Required render path | The primary path stays GPU-resident and software-rendered evidence is rejected |
| Image decoding and `createImageBitmap` | Required for textures and glTF assets | Covered by runtime smoke and scene suites |
| Local fetch and static resource loading | Required for bundled scenes | Covered by loopback and file package tests |
| CDP remote debugging | Required for automation | Used for smoke, metrics, trace capture, and benchmark result collection |

## Update Rule

When changing a subsystem decision:

1. Record the source patch or runtime flag.
2. Build the fork and retain build provenance.
3. Run runtime smoke, navigation lock tests, and a relevant benchmark subset.
4. Compare against stock Chromium from the same revision and GN args profile.
5. Record raw JSON artifacts, reports, and regression risk.
6. Update this register and `docs/optimization_log.md` in the same change.

# Removed Or Disabled Subsystems

Date: 2026-05-16

Status: no Chromium subsystem has been physically removed from `src` yet. The upstream checkout is intentionally left pristine until the stock baseline binary is built from the pinned revision. The draft viewer entrypoint patch is stored in `chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch` and passes clean-apply validation.

This document is a removal/disable register. Rows marked pending are not accepted as completed optimization work until a fork binary builds, smoke tests pass, benchmark evidence exists, and the result is recorded in `docs/optimization_log.md`.

## Already Avoided By Starting From Content Shell

Using `//content/shell:content_shell` avoids a large part of Chrome product UI before any source removal. This is a target-selection property, not a measured fork optimization yet.

| Subsystem | Current status | Rationale | Regression risk | Current evidence |
| --- | --- | --- | --- | --- |
| Chrome tab strip and browser frame UI | Avoided by target; toolbar hidden by draft patch in viewer mode | The viewer needs one native window and one `WebContents`, not Chrome browser chrome | Low for trusted viewer, high for browsing | `content_shell` target; draft patch changes `Shell::ShouldHideToolbar`; runtime verification pending |
| Chrome extensions UI/runtime | Avoided by target; runner also passes `--disable-extensions` | No extension install or execution path is needed | Low for viewer | No Chrome extensions product layer in content shell; same-revision measurement pending |
| Chrome sync | Avoided by target; runner also passes `--disable-sync` | No signed-in profile or sync transport is needed | Low for viewer | Content shell does not initialize Chrome sync services; same-revision measurement pending |
| Chrome autofill UI and server communication | Avoided by target; runner disables autofill server communication feature | No forms workflow is needed | Low for viewer | Runner flag only; source-level measurement pending |
| Translate UI | Avoided by target; runner disables `Translate` feature | No arbitrary page translation | Low for viewer | Runner flag only; source-level measurement pending |
| Bookmarks UI | Avoided by target | No user browsing state | Low for viewer | Content shell has no Chrome bookmarks UI; benchmark pending |
| History UI | Avoided by target | No arbitrary browsing workflow | Low for viewer | Content shell has no Chrome history UI; benchmark pending |
| Password manager UI | Avoided by target | No login or credential workflow | Low for viewer | Content shell has no Chrome password manager UI; benchmark pending |
| Payments UI | Avoided by target | No checkout/payment workflow | Low for viewer | Content shell has no Chrome payments UI; benchmark pending |

## Draft Viewer Entrypoint Behavior

| Subsystem or behavior | Planned status | Rationale | Regression risk | Current evidence |
| --- | --- | --- | --- | --- |
| Arbitrary top-level navigation | Block in viewer mode | Trusted local viewer should not navigate to arbitrary sites | Medium if legitimate asset loads are accidentally blocked | Static patch regression test verifies throttle registration and same-origin/file confinement; HTTP/file navigation lock runtime tests exist, including deterministic external HTTP blocking; fork runtime result pending |
| New-window and tab creation | Block in viewer mode | Viewer owns exactly one surface | Low for viewer | Draft patch blocks non-current-tab opens; runtime verification pending |
| File URL escape from packaged viewer directory | Block in file viewer mode | Trusted package may need local assets but not arbitrary local file navigation | Medium: file URL rules are security-sensitive | Static patch regression test verifies viewer-file-or-child-only logic; file navigation lock runtime test exists; fork runtime result pending |
| Trusted local file access relaxation | Allow only behind `--viewer-app-url`, `--viewer-trusted-content`, and local file viewer launch | File-mode glTF/assets require file access relaxation | High outside trusted local package mode | Installed-Chrome v13 smoke shows file glTF needs file-access class of switch; fork alias pending runtime validation |

## Content Shell Services Still Present

These are the first content-shell-specific removal candidates after the baseline/fork comparison exists.

| Subsystem | Planned status | Rationale | Regression risk | Source areas | Current evidence |
| --- | --- | --- | --- | --- | --- |
| Download manager/delegate | Disable or stub in viewer mode | Viewer blocks arbitrary navigation and should not download | Low to medium: some asset responses might still touch download classification | `content/shell/browser/shell_download_manager_delegate.*`, `ShellBrowserContext::GetDownloadManagerDelegate` | Pending fork build and navigation/file tests |
| Permissions UI/delegate | Keep minimal, then evaluate deny-by-default for unrelated permissions | WebGL/WebGPU/canvas need no permission prompt; future WebGPU policies may still matter | Medium: overblocking can break device/GPU APIs or tests | `content/shell/browser/shell_permission_manager.h`, `ShellBrowserContext::GetPermissionControllerDelegate` | Pending |
| Platform notifications/push/background fetch/background sync/content index | Disable/stub | Not needed for local viewer | Low for viewer, medium for content shell tests | `content/shell/browser/shell_browser_context.cc` | Pending |
| Geolocation test permission manager | Disable/stub | Not needed for viewer | Low for viewer | `content/shell/browser/shell_content_browser_client.cc` | Pending |
| DevTools frontend/manager | Keep remote debugging for benchmark automation; evaluate hiding UI paths | CDP is required for harness result capture and trace capture | Medium: removing too much breaks benchmark automation | `content/shell/browser/shell_devtools_*` | Keep initially |
| Custom protocol/file helpers | Keep until packaged local asset loading is verified | Viewer needs local asset loading | Medium | `content/shell/browser/shell.cc`, `shell_file_select_helper.*`, protocol helpers | Pending |

## Web Platform Feature Removal Candidates

These must not be removed until the viewer scenes and smoke tests prove the required APIs still work.

| Subsystem | Planned status | Rationale | Regression risk | Current evidence |
| --- | --- | --- | --- | --- |
| Media playback stack | Evaluate removal only after texture/image path audit | Three.js texture loaders need image decode, but not video/audio/WebRTC for current scenes | Medium: media service wiring may share image/video texture paths | Source map identifies media service wiring in content shell; pending build |
| WebRTC | Evaluate disable | Not needed for local scenes | Low for viewer, high for browsing | Pending |
| PDF and printing | Evaluate disable | Not needed for viewer | Low for viewer | Pending |
| Accessibility | Evaluate trusted experiment only | Could reduce overhead, but it is a product requirement outside the experiment | High | Pending |
| Spellcheck | Disable/evaluate | No text editing workflow | Low | Pending |
| Layout/style/DOM features | Mostly keep initially | Three.js still needs DOM, canvas, events, CSS sizing, script module loading, and local asset APIs | High if removed aggressively | Pending |
| Blink modules unrelated to viewer | Evaluate one-by-one behind build flags where possible | Reduce binary size and service startup only if safe | High: hidden dependencies are common | Pending |

## GPU And Process Experiments

These are unsafe or platform-sensitive and must remain behind trusted-content switches.

| Experiment | Planned status | Rationale | Regression risk | Current evidence |
| --- | --- | --- | --- | --- |
| ANGLE backend forcing | Evaluate `d3d11`, `vulkan`, `gl`, platform default | Backend choice may dominate frame pacing and CPU overhead | Medium: backend availability varies by GPU/driver | Draft `--viewer-force-angle-backend` alias exists; measurements pending |
| Passthrough command decoder behavior | Evaluate, do not assume | Could affect WebGL CPU overhead | High: validation/security and driver stability | Source map identifies GLES decoder paths; pending trace evidence |
| Relaxed WebGL validation | Trusted pass-through command decoder experiment | Potential CPU win in trusted local mode by selecting Chromium's existing `--use-cmd-decoder=passthrough` path | High security/correctness risk; can change WebGL validation and driver exposure behavior | Draft `--viewer-relaxed-webgl-validation` alias exists; benchmark pending |
| In-process GPU | Trusted experiment only | May reduce IPC and process overhead | High: crash isolation and stability risk | Draft alias exists; benchmark pending |
| Single-process | Trusted experiment only | May reduce process overhead | Very high: changes browser architecture assumptions | Draft alias exists; benchmark pending |
| Direct GPU presentation/compositor bypass | Reserved no-op gate only | Could reduce latency more than average FPS | Very high and platform-specific | `--viewer-direct-gpu-presentation` exists as no-op; design pending |
| WebGPU pipeline/cache warmup | Evaluate with Dawn cache and viewer warmup | May reduce p99/pipeline stalls | Medium: can move cost to startup or hide hitches | Viewer warmup and WebGPU timestamp metrics exist; stock/fork evidence pending |

## Prompt Optimization Class Tracking

This table is a coverage register for every optimization class named in the original objective. These rows are tracking entries only. They do not count as measured optimization outcomes until the fork builds and the stock/fork benchmark gates pass.

| Optimization class | Tracking status |
| --- | --- |
| Remove Chrome browser UI layer | Tracked through the `content_shell` target choice, toolbar-hiding draft patch, and required runtime smoke after fork build |
| Minimal content shell style entrypoint | Tracked through the content-shell-derived viewer entrypoint patch |
| Single local trusted origin | Tracked through `--viewer-app-url`, `--viewer-block-external-navigation`, same-origin HTTP confinement, external HTTP blocking, and file-directory confinement |
| Disable extensions | Tracked as already avoided by content shell and by runner flags |
| Disable sync | Tracked as already avoided by content shell and by runner flags |
| Disable autofill | Tracked as avoided UI plus runner-side autofill server communication disablement |
| Disable translate | Tracked as avoided UI plus runner-side `Translate` feature disablement |
| Disable spellcheck | Tracked as a web platform feature removal candidate |
| Disable Safe Browsing services not needed for local trusted content | Tracked as a pending Chrome-product service removal candidate; content shell avoids Chrome Safe Browsing UI/services, but any remaining network/service hooks must be measured before removal |
| Disable downloads UI | Tracked through download manager/delegate removal candidates |
| Disable history/bookmarks UI | Tracked as already avoided by content shell |
| Disable unnecessary profile services | Tracked through content-shell browser context and service delegate candidates |
| Disable unnecessary background networking | Tracked through runner flags and pending content-shell service audit |
| Reduce renderer process overhead where possible | Tracked through process-model experiments and trace-guided renderer/GPU IPC analysis |
| Evaluate single-process/in-process GPU | Tracked as trusted-content experiments behind `--viewer-single-process` and `--viewer-in-process-gpu` |
| Evaluate ANGLE backend choices | Tracked through `--viewer-force-angle-backend` and benchmark matrix support |
| Evaluate Vulkan, D3D11, OpenGL/EGL, and Metal path implications | Tracked as platform GPU backend experiments; Windows starts with D3D11/Vulkan/GL where available, while Metal remains a non-Windows rebase target |
| Evaluate passthrough command decoder | Tracked through WebGL source investigation and trace requirements |
| Evaluate WebGL validation overhead | Tracked through the trusted `--viewer-relaxed-webgl-validation` pass-through command decoder alias and WebGL validation source map |
| Evaluate shader compilation strategy | Tracked through shader-heavy scenes, shader compile counters, trace categories, and resource warmup controls |
| Evaluate WebGPU pipeline caching/warmup | Tracked through WebGPU timestamp support, Dawn cache source map, and viewer warmup controls |
| Evaluate compositor bypass or simplified presentation path | Tracked through Viz source map, trace requirements, and reserved direct-presentation gate |
| Evaluate direct GPU texture presentation/export | Tracked through the reserved `--viewer-direct-gpu-presentation` gate |
| Evaluate removing unused Blink modules | Tracked through Blink module removal candidates and the required runtime API surface regression |
| Evaluate disabling layout/style/DOM features not required by the viewer | Tracked as high-risk Blink minimization work; DOM/layout/style remain required until smoke and scene coverage prove otherwise |
| Evaluate disabling media, printing, PDF, WebRTC, accessibility, password manager, payments, and other unrelated features | Tracked through web platform and Chrome-product removal candidate rows |
| Evaluate V8 flags relevant to startup and steady-state JS performance | Tracked as a pending runtime flag experiment; V8 itself is explicitly kept |
| Evaluate memory allocator and process model choices | Tracked as a pending build/runtime experiment after baseline/fork binaries exist |

## Subsystems Explicitly Kept For Now

| Subsystem | Kept because | Notes |
| --- | --- | --- |
| V8 | Required by objective | No native-engine replacement path is allowed |
| Blink core DOM/layout/event loop | Required for Three.js module execution, canvas placement, input, fetch, and animation | Minimize only after API-level smoke coverage passes |
| Canvas/WebGL/WebGPU/Dawn/ANGLE/GPU process/Viz | Required by objective | Optimization is allowed; removal is not |
| Image decoding and `createImageBitmap` | Required for texture loader coverage | The glTF and texture-streaming scenes depend on asset loading paths |
| Local fetch/static resource loading | Required for bundled scenes | File-mode and loopback modes are both tested |
| CDP remote debugging | Required for benchmark harness and trace capture | Can be hidden from user-facing runtime but not removed from test builds yet |

## Update Rule

When a row moves from pending to kept/reverted/blocked/not useful:

1. Record the patch or runtime flag.
2. Build the fork.
3. Run smoke tests.
4. Run a relevant benchmark subset against stock and fork from the same Chromium revision.
5. Record JSON artifacts and a human-readable report.
6. Update this file and `docs/optimization_log.md` with measured effect and risk.

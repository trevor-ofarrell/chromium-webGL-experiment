# Chromium Source Investigation Map

Date: 2026-05-18

Status: source inspection only. These are the concrete files/classes to use for the post-ATL optimization loop. No source-level optimization in this map is considered implemented or measured until the fork binary builds and the stock/fork benchmark gates pass.

Current checkout verification: `scripts\test_source_investigation_paths.ps1` resolves the documented `src/...` paths and sentinel symbols against the live Chromium checkout. Last local verification was at pinned Chromium revision `e39c315b5d5d0b0cf9963bf00130a98d13cfec51`; rerun the script after any Chromium pin refresh.

## Minimal Viewer Entrypoint

Primary files:

- `src/content/shell/browser/shell.cc`
- `src/content/shell/browser/shell.h`
- `src/content/shell/browser/shell_browser_main_parts.cc`
- `src/content/shell/browser/shell_content_browser_client.cc`
- `src/content/shell/common/shell_switches.cc`
- `src/content/shell/common/shell_switches.h`
- `src/content/shell/browser/shell_platform_delegate_views.cc`

Relevant classes/functions observed:

- `content::Shell`
- `Shell::CreateNewWindow`
- `Shell::LoadURL`
- `Shell::OpenURLFromTab`
- `Shell::ShouldHideToolbar`
- `ShellBrowserMainParts::InitializeBrowserContexts`
- `ShellBrowserMainParts::PreMainMessageLoopRun`
- `ShellContentBrowserClient::CreateThrottlesForNavigation`

First fork patch already targets this area: startup URL selection, toolbar suppression, navigation throttling, new-window blocking, and trusted-content switch aliases.

## WebGL Path

Primary files:

- `src/third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc`
- `src/third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.h`
- `src/third_party/blink/renderer/modules/webgl/webgl2_rendering_context_base.cc`
- `src/third_party/blink/renderer/modules/webgl/webgl2_rendering_context_base.h`
- `src/third_party/blink/renderer/platform/graphics/gpu/drawing_buffer.cc`
- `src/gpu/ipc/service/gles2_command_buffer_stub.cc`
- `src/gpu/command_buffer/service/gles2_cmd_decoder_passthrough.cc`
- `src/gpu/command_buffer/service/gles2_cmd_decoder.cc`
- `src/gpu/command_buffer/service/feature_info.cc`
- `src/gpu/command_buffer/common/context_creation_attribs.cc`

Relevant classes/functions observed:

- `WebGLRenderingContextBase`
- `WebGL2RenderingContextBase`
- `WebGLRenderingContextBase::ValidateDrawArrays`
- `WebGLRenderingContextBase::ValidateDrawElements`
- `WebGLRenderingContextBase::ValidateTexFuncParameters`
- `WebGLRenderingContextBase::ValidateImageBitmap`
- `WebGLRenderingContextBase::OnBeforeDrawCall`
- `WebGLRenderingContextBase::ForceLostContext`
- `WebGLRenderingContextBase::DispatchContextLostEvent`
- `gpu::IsWebGLContextType`
- `gpu::FeatureInfo::IsWebGLContext`

Initial investigation focus:

- Measure validation and decoder overhead before any relaxation experiment.
- Keep `--viewer-relaxed-webgl-validation` as a trusted-only pass-through command decoder experiment until trace evidence and stock/fork benchmark results decide whether to keep or revert it.
- Watch texture upload paths from `texImage2D`/`texSubImage2D` and `ImageBitmap` inputs; avoid any optimization that introduces CPU readback in the primary render path.

## WebGPU Path

Primary files:

- `src/third_party/blink/renderer/modules/webgpu/gpu.cc`
- `src/third_party/blink/renderer/modules/webgpu/gpu_adapter.cc`
- `src/third_party/blink/renderer/modules/webgpu/gpu_device.cc`
- `src/third_party/blink/renderer/modules/webgpu/gpu_canvas_context.cc`
- `src/gpu/command_buffer/service/webgpu_decoder_impl.cc`
- `src/gpu/command_buffer/service/webgpu_decoder.h`
- `src/gpu/command_buffer/service/dawn_context_provider.cc`
- `src/gpu/command_buffer/service/dawn_context_provider.h`
- `src/gpu/command_buffer/service/dawn_caching_interface.cc`
- `src/gpu/command_buffer/service/dawn_caching_interface.h`

Relevant classes/functions observed:

- `GPUDevice`
- `GPUCanvasContext`
- `WebGPUDecoderImpl`
- `WebGPUDecoderImpl::RequestAdapterImpl`
- `WebGPUDecoderImpl::RequestDeviceImpl`
- `WebGPUDecoderImpl::CreatePreferredAdapter`
- `WebGPUDecoderImpl::HandleDawnCommands`
- `WebGPUDecoderImpl::AssociateMailboxDawn`
- `DawnContextProvider`
- `DawnCachingInterface`
- `DawnCachingInterfaceFactory`

Initial investigation focus:

- Use WebGPU timestamp metrics and traces to separate JavaScript, command encoding, decoder, Dawn, and presentation costs.
- Evaluate pipeline/cache behavior through Dawn cache interfaces before attempting runtime-side warmup changes.
- Treat device-loss behavior as a stability gate, not only a smoke-test signal.

## Canvas, ImageBitmap, And Texture Sources

Primary files:

- `src/third_party/blink/renderer/core/html/canvas/html_canvas_element.cc`
- `src/third_party/blink/renderer/modules/canvas/htmlcanvas/html_canvas_element_module.cc`
- `src/third_party/blink/renderer/modules/canvas/imagebitmap/image_bitmap_factories.cc`
- `src/third_party/blink/renderer/modules/canvas/imagebitmap/image_bitmap_rendering_context.cc`
- `src/third_party/blink/renderer/modules/canvas/offscreencanvas/offscreen_canvas_module.cc`
- `src/third_party/blink/renderer/platform/graphics/canvas_resource_provider.cc`

Relevant classes/functions observed:

- `HTMLCanvasElement`
- `HTMLCanvasElementModule::getContext`
- `HTMLCanvasElementModule::transferControlToOffscreen`
- `ImageBitmapFactories`
- `ImageBitmapRenderingContext`
- `CanvasResourceProvider`

Initial investigation focus:

- Preserve `HTMLCanvasElement`, WebGL/WebGPU context creation, `createImageBitmap`, and local image/texture loaders.
- Do not remove image decoding or canvas resource provider paths until glTF and texture-streaming benchmark scenes pass on both WebGL2 and WebGPU.

## Compositor And Presentation Path

Primary files:

- `src/components/viz/service/frame_sinks/compositor_frame_sink_support.cc`
- `src/components/viz/service/display/surface_aggregator.cc`
- `src/components/viz/service/display_embedder/skia_output_surface_impl.cc`
- `src/components/viz/service/display_embedder/output_presenter*.cc`
- `src/components/viz/service/display/display.cc`
- `src/components/viz/common/quads/compositor_frame*.h`

Relevant concepts/classes:

- `CompositorFrameSinkSupport`
- `SurfaceAggregator`
- `SkiaOutputSurfaceImpl`
- `OutputPresenter`
- `CompositorFrame`
- `BeginFrame`
- swap/ack timing through Viz and platform presenters

Initial investigation focus:

- Measure compositor and presentation latency with traces before attempting compositor bypass.
- Keep `--viewer-direct-gpu-presentation` as a no-op gate until a platform-specific design exists.
- Avoid CPU readback; candidate experiments must stay GPU-resident.

## GPU Process, ANGLE, And Backend Choice

Primary files:

- `src/content/browser/gpu/gpu_process_host.cc`
- `src/content/browser/gpu/browser_gpu_channel_host_factory.cc`
- `src/gpu/config/gpu_switches.cc`
- `src/gpu/config/gpu_preferences.cc`
- `src/gpu/ipc/service/gpu_init.cc`
- `src/gpu/command_buffer/service/shared_context_state.cc`
- `src/third_party/angle/`
- `src/third_party/dawn/`

Relevant classes/functions observed:

- `GpuProcessHost`
- `GpuProcessHost::Get`
- `GpuProcessHost::LaunchGpuProcess`
- `GpuProcessHost::OnProcessCrashed`
- `GpuProcessHost::GetGpuCrashCount`
- `BrowserGpuChannelHostFactory`

Initial investigation focus:

- Evaluate `--viewer-force-angle-backend` by benchmark, not assumption.
- Run in-process GPU and single-process only as trusted-content experiments.
- Document GPU crash/restart behavior from `GpuProcessHost` and viewer stability fields after one-hour runs.

## Content Shell Services And Feature Removal Candidates

Primary files:

- `src/content/shell/browser/shell_browser_context.cc`
- `src/content/shell/browser/shell_browser_context.h`
- `src/content/shell/browser/shell_download_manager_delegate.cc`
- `src/content/shell/browser/shell_permission_manager.h`
- `src/content/shell/browser/shell_content_browser_client.cc`
- `src/content/shell/browser/shell_devtools_manager_delegate.cc`

Relevant classes/functions observed:

- `ShellBrowserContext`
- `ShellDownloadManagerDelegate`
- `ShellPermissionManager`
- `ShellContentBrowserClient`
- `ShellDevToolsManagerDelegate`

Initial investigation focus:

- Content shell already avoids Chrome tab strip, extensions, sync, autofill UI, translate UI, bookmarks UI, history UI, payments UI, and password manager UI.
- Remaining content-shell delegates still include downloads, permissions, notifications, geolocation test plumbing, media service wiring, DevTools plumbing, and protocol/file helpers.
- Remove or disable one category at a time only after stock/fork binaries exist; every removal needs build, smoke, benchmark subset, and documentation in `docs/removed_subsystems.md`.

## Commands Used For This Map

Representative inspection commands:

```powershell
.\scripts\inspect_chromium_target.ps1
.\scripts\test_source_investigation_paths.ps1
rg -n "class WebGLRenderingContextBase|ValidateDraw|texImage|OnBeforeDrawCall" src\third_party\blink\renderer\modules\webgl
rg -n "class WebGPUDecoderImpl|RequestAdapterImpl|RequestDeviceImpl|DawnCachingInterface" src\gpu\command_buffer\service
rg -n "HTMLCanvasElement|ImageBitmap|CanvasResourceProvider" src\third_party\blink\renderer
rg -n "FrameSink|SurfaceAggregator|SkiaOutputSurface|OutputPresenter|BeginFrame" src\components\viz
rg -n "Shell::CreateNewWindow|Shell::LoadURL|CreateThrottlesForNavigation|ShellBrowserContext" src\content\shell
rg -n "GpuProcessHost|BrowserGpuChannelHostFactory" src\content\browser\gpu
```

## Next Evidence Required

- Build stock `content_shell.exe` and patched fork `content_shell.exe`.
- Capture stock/fork traces for at least `many-draw-calls` WebGL2 and one WebGPU scene.
- Use trace categories and benchmark deltas to pick the first source-level optimization.
- Keep all unsafe changes behind viewer-specific trusted flags.

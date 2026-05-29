# Trace Summary

Trace: `C:\Users\trevo\code\three-browser\benchmarks\traces\fork-viewer-default-many-draw-calls-webgl2-trace.json`
Sidecar: `C:\Users\trevo\code\three-browser\benchmarks\traces\fork-viewer-default-many-draw-calls-webgl2-trace.result.json`

Total events: 581347

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| other | 275606 | 73800.47 |
| javascript | 5527 | 25083.98 |
| gpu_command | 248361 | 11827.57 |
| shader_or_pipeline | 34408 | 9219.40 |
| presentation | 17442 | 1236.29 |
| texture_upload | 3 | 0.31 |

## Focused WebGPU Queue Events

| Event | Count | Total ms | Max ms | Bytes MiB | Pixels | Command buffers |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| No focused WebGPU queue events found | 0 | 0.00 | 0.00 |  |  |  |

## WebGPU Texture Copy Path Verdict

Status: `no-webgpu-texture-copy-path-observed`

| Path | Events | Bytes MiB | Pixels |
| --- | ---: | ---: | ---: |
| GPU-resident shared image/mailbox copy | 0 |  |  |
| CPU fallback/readback copy | 0 |  |  |
| Rejected CPU fallback attempt | 0 |  |  |

## WebGPU Fast-Path Coverage

These sidecar counters are viewer-side diagnostic attribution. They show whether queue and pipeline descriptors matched source fast paths during the traced benchmark.

| WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

## Top Duration Events

| Event | Count | Total ms | Max ms |
| --- | ---: | ---: | ---: |
| RunTask | 57682 | 25267.62 | 126.25 |
| ProxyMain::BeginMainFrame | 729 | 8522.47 | 125.59 |
| AsyncTask Run | 714 | 8379.98 | 124.25 |
| v8.callFunction | 713 | 8339.66 | 124.20 |
| WebFrameWidgetImpl::BeginMainFrame | 729 | 8320.10 | 124.30 |
| Blink.Animate.UpdateTime | 729 | 8310.50 | 124.29 |
| PageAnimator::serviceScriptedAnimations | 729 | 8300.98 | 124.28 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 712 | 8273.03 | 124.25 |
| FireAnimationFrame | 711 | 8269.65 | 124.25 |
| FunctionCall | 713 | 8235.03 | 124.17 |
| Scheduler::RunTask | 12090 | 2772.01 | 51.18 |
| GpuChannel::ExecuteDeferredRequest | 11352 | 2281.24 | 51.17 |
| GPUTask | 11395 | 2216.38 | 51.16 |
| WebGL | 11337 | 1919.60 | 51.05 |
| CommandBuffer::Flush | 11341 | 1898.34 | 51.05 |
| CommandBufferStub::OnAsyncFlush | 11341 | 1882.35 | 51.05 |
| CommandBufferService:PutChanged | 11341 | 1829.86 | 51.04 |
| Graphics.Pipeline | 9421 | 815.98 | 15.17 |
| D3DImageBacking::PresentSwapChain | 714 | 417.58 | 2.13 |
| SkiaOutputSurfaceImplOnGpu::SwapBuffers | 712 | 385.54 | 8.39 |
| DCompPresenter::Present | 712 | 351.23 | 8.20 |
| CommandBufferHelper::Flush | 10971 | 309.24 | 0.36 |
| CommandBufferProxyImpl::Flush | 10967 | 253.45 | 0.35 |
| GpuChannelMessageFilter::FlushDeferredRequests | 10958 | 187.90 | 0.28 |
| DisplayScheduler::OnBeginFrameDeadline | 719 | 176.43 | 15.18 |
| CanvasResourceDispatcher::DispatchFrame | 711 | 176.26 | 0.50 |
| DisplayScheduler::DrawAndSwap | 712 | 173.98 | 15.18 |
| Display::DrawAndSwap | 712 | 171.83 | 15.17 |
| CanvasResourceDispatcher::PrepareFrame | 711 | 144.86 | 0.46 |
| CanvasResource::PrepareTransferableResource | 711 | 137.21 | 0.45 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

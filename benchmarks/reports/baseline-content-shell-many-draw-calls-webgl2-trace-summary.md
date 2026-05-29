# Trace Summary

Trace: `C:\Users\trevo\code\three-browser\benchmarks\traces\baseline-content-shell-many-draw-calls-webgl2-trace.json`
Sidecar: `C:\Users\trevo\code\three-browser\benchmarks\traces\baseline-content-shell-many-draw-calls-webgl2-trace.result.json`

Total events: 571763

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| other | 272915 | 73223.76 |
| javascript | 5422 | 24232.81 |
| gpu_command | 241441 | 13049.69 |
| shader_or_pipeline | 34582 | 8883.34 |
| presentation | 17400 | 1256.17 |
| texture_upload | 3 | 0.33 |

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
| RunTask | 57420 | 25454.55 | 180.57 |
| ProxyMain::BeginMainFrame | 737 | 8191.67 | 120.25 |
| AsyncTask Run | 718 | 8030.07 | 119.13 |
| WebFrameWidgetImpl::BeginMainFrame | 737 | 7987.52 | 119.18 |
| v8.callFunction | 714 | 7981.04 | 119.08 |
| Blink.Animate.UpdateTime | 737 | 7977.25 | 119.17 |
| PageAnimator::serviceScriptedAnimations | 737 | 7967.96 | 119.17 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 714 | 7941.17 | 119.14 |
| FireAnimationFrame | 712 | 7938.11 | 119.13 |
| FunctionCall | 714 | 7875.71 | 119.06 |
| Scheduler::RunTask | 11785 | 2990.52 | 180.55 |
| GpuChannel::ExecuteDeferredRequest | 11034 | 2533.36 | 180.54 |
| GPUTask | 11080 | 2467.13 | 180.53 |
| CommandBuffer::Flush | 11009 | 2153.11 | 180.49 |
| CommandBufferStub::OnAsyncFlush | 11009 | 2137.68 | 180.49 |
| CommandBufferService:PutChanged | 11009 | 2084.87 | 180.48 |
| WebGL | 10994 | 1962.06 | 50.53 |
| Graphics.Pipeline | 9507 | 810.95 | 8.34 |
| D3DImageBacking::PresentSwapChain | 715 | 457.49 | 2.40 |
| SkiaOutputSurfaceImplOnGpu::SwapBuffers | 715 | 372.02 | 8.38 |
| DCompPresenter::Present | 715 | 339.95 | 7.21 |
| CommandBufferHelper::Flush | 10616 | 309.26 | 0.33 |
| CommandBufferProxyImpl::Flush | 10606 | 252.90 | 0.31 |
| BrowserRasterWorker | 14 | 211.83 | 180.49 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 7 | 206.29 | 179.35 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 7 | 206.07 | 179.29 |
| GpuChannelMessageFilter::FlushDeferredRequests | 10595 | 180.43 | 0.27 |
| CanvasResourceDispatcher::DispatchFrame | 712 | 179.02 | 0.51 |
| DisplayScheduler::OnBeginFrameDeadline | 725 | 173.69 | 0.70 |
| DisplayScheduler::DrawAndSwap | 715 | 171.32 | 0.69 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

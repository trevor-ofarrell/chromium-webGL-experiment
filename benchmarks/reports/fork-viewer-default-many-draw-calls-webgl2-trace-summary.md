# Trace Summary

Trace: `C:\Users\trevo\code\three-browser\benchmarks\traces\fork-viewer-default-many-draw-calls-webgl2-trace.json`

Total events: 253820

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| other | 124637 | 73038.45 |
| gpu_command | 100608 | 52143.49 |
| javascript | 2102 | 11079.13 |
| presentation | 7842 | 10642.67 |
| shader_or_pipeline | 18628 | 5353.47 |
| texture_upload | 3 | 0.44 |

## Top Duration Events

| Event | Count | Total ms | Max ms |
| --- | ---: | ---: | ---: |
| RunTask | 21138 | 28998.81 | 239.14 |
| Scheduler::RunTask | 5402 | 11573.57 | 239.13 |
| GpuChannel::ExecuteDeferredRequest | 5120 | 10181.10 | 239.12 |
| GPUTask | 5168 | 10142.36 | 239.11 |
| CommandBuffer::Flush | 5107 | 9899.14 | 239.06 |
| CommandBufferStub::OnAsyncFlush | 5107 | 9889.19 | 239.06 |
| CommandBufferService:PutChanged | 5107 | 9858.61 | 239.05 |
| WebGL | 5046 | 9656.91 | 61.36 |
| D3DImageBacking::PresentSwapChain | 265 | 8954.95 | 61.15 |
| AsyncTask Run | 267 | 3712.93 | 196.10 |
| ProxyMain::BeginMainFrame | 296 | 3703.61 | 207.87 |
| v8.callFunction | 264 | 3609.73 | 196.03 |
| WebFrameWidgetImpl::BeginMainFrame | 296 | 3482.97 | 196.28 |
| Blink.Animate.UpdateTime | 296 | 3476.93 | 196.26 |
| PageAnimator::serviceScriptedAnimations | 296 | 3471.72 | 196.25 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 264 | 3453.49 | 196.16 |
| FireAnimationFrame | 263 | 3451.27 | 196.16 |
| FunctionCall | 264 | 3341.87 | 193.39 |
| Graphics.Pipeline | 4203 | 1717.12 | 105.99 |
| SkiaOutputSurfaceImplOnGpu::SwapBuffers | 206 | 1284.50 | 106.02 |
| DCompPresenter::Present | 206 | 1266.81 | 105.97 |
| DCLayerTree::CommitAndClearPendingOverlays | 206 | 879.21 | 58.44 |
| DCLayerTree::CommitAndClearPendingOverlays::Commit | 26 | 871.94 | 58.41 |
| RendererRasterWorker | 61 | 254.99 | 239.06 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 23 | 243.41 | 237.81 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 23 | 242.67 | 237.71 |
| CommandBufferHelper::Flush | 4667 | 187.21 | 0.36 |
| TimerBase::run | 3 | 181.79 | 181.74 |
| TimerFire | 1 | 181.71 | 181.71 |
| ExternalBeginFrameSource::OnBeginFrame | 1052 | 167.01 | 1.47 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

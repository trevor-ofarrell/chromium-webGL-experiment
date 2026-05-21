# Trace Summary

Trace: `C:\Users\trevo\code\three-browser\benchmarks\traces\baseline-content-shell-many-draw-calls-webgl2-trace.json`

Total events: 254889

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| other | 126256 | 75592.07 |
| gpu_command | 100468 | 49731.65 |
| javascript | 2134 | 11148.74 |
| presentation | 7793 | 10623.09 |
| shader_or_pipeline | 18235 | 6204.78 |
| texture_upload | 3 | 0.48 |

## Top Duration Events

| Event | Count | Total ms | Max ms |
| --- | ---: | ---: | ---: |
| RunTask | 21807 | 29760.68 | 247.03 |
| Scheduler::RunTask | 5557 | 11818.04 | 247.01 |
| GpuChannel::ExecuteDeferredRequest | 5263 | 9420.24 | 247.01 |
| GPUTask | 5317 | 9376.73 | 247.00 |
| CommandBuffer::Flush | 5231 | 9128.32 | 246.96 |
| CommandBufferStub::OnAsyncFlush | 5231 | 9118.11 | 246.96 |
| CommandBufferService:PutChanged | 5231 | 9086.87 | 246.95 |
| WebGL | 5157 | 8643.06 | 78.15 |
| D3DImageBacking::PresentSwapChain | 254 | 7962.22 | 77.80 |
| AsyncTask Run | 259 | 3610.61 | 212.69 |
| ProxyMain::BeginMainFrame | 287 | 3557.91 | 224.75 |
| v8.callFunction | 253 | 3491.22 | 212.63 |
| WebFrameWidgetImpl::BeginMainFrame | 287 | 3345.07 | 212.82 |
| Blink.Animate.UpdateTime | 287 | 3339.45 | 212.80 |
| PageAnimator::serviceScriptedAnimations | 287 | 3334.52 | 212.79 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 254 | 3316.61 | 212.70 |
| FireAnimationFrame | 252 | 3315.13 | 212.69 |
| FunctionCall | 253 | 3204.78 | 210.55 |
| Graphics.Pipeline | 4094 | 2702.13 | 138.45 |
| SkiaOutputSurfaceImplOnGpu::SwapBuffers | 202 | 2308.96 | 138.48 |
| DCompPresenter::Present | 202 | 2293.94 | 138.40 |
| DCLayerTree::CommitAndClearPendingOverlays | 202 | 1922.99 | 138.28 |
| DCLayerTree::CommitAndClearPendingOverlays::Commit | 28 | 1914.09 | 138.24 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 31 | 478.25 | 245.90 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 31 | 477.16 | 245.81 |
| RendererRasterWorker | 61 | 263.57 | 246.96 |
| BrowserRasterWorker | 19 | 234.31 | 197.74 |
| GpuChannelHost::CreateViewCommandBuffer | 6 | 215.02 | 194.13 |
| CommandBufferProxyImpl::Initialize | 6 | 214.92 | 194.13 |
| LayerTreeHostImpl::InitializeFrameSink | 5 | 199.35 | 195.09 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

# Trace Summary

Trace: `benchmarks\traces\fork-viewer-exp-webgpu-taildiag-bgl-colorconv-queue-trace-texture-streaming-trace.json`
Sidecar: `C:\Users\trevo\code\three-browser\benchmarks\traces\fork-viewer-exp-webgpu-taildiag-bgl-colorconv-queue-trace-texture-streaming-trace.result.json`

Total events: 320011

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| gpu_command | 173635 | 57061.41 |
| other | 139417 | 51422.55 |
| javascript | 1027 | 6043.61 |
| shader_or_pipeline | 3959 | 2068.36 |
| presentation | 1935 | 183.45 |
| texture_upload | 38 | 0.89 |

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
| 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |

## Top Duration Events

| Event | Count | Total ms | Max ms |
| --- | ---: | ---: | ---: |
| RunTask | 23230 | 24497.97 | 200.10 |
| Scheduler::RunTask | 7563 | 10566.51 | 175.92 |
| GpuChannel::ExecuteDeferredRequest | 7414 | 10364.25 | 175.91 |
| GPUTask | 7248 | 10264.49 | 175.91 |
| CommandBuffer::Flush | 7198 | 9984.88 | 175.89 |
| CommandBufferStub::OnAsyncFlush | 7198 | 9966.98 | 175.87 |
| CommandBufferService:PutChanged | 7198 | 9875.51 | 175.86 |
| WebGPU | 3499 | 5689.98 | 175.89 |
| RendererMainThread | 3706 | 4321.97 | 13.86 |
| v8.callFunction | 80 | 1922.47 | 198.61 |
| ProxyMain::BeginMainFrame | 52 | 1919.25 | 199.72 |
| AsyncTask Run | 81 | 1916.11 | 198.64 |
| FunctionCall | 80 | 1904.04 | 198.58 |
| WebFrameWidgetImpl::BeginMainFrame | 52 | 1884.20 | 198.82 |
| Blink.Animate.UpdateTime | 52 | 1881.40 | 198.82 |
| PageAnimator::serviceScriptedAnimations | 52 | 1879.98 | 198.81 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 41 | 1875.21 | 198.75 |
| FireAnimationFrame | 77 | 1874.89 | 198.65 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 3427 | 443.95 | 1.48 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 3427 | 365.66 | 1.45 |
| RasterDecoderImpl::DoRasterCHROMIUM | 3427 | 258.08 | 3.02 |
| RasterDecoderImpl::DoBeginRasterCHROMIUM | 3427 | 252.63 | 0.96 |
| RasterDecoderImpl::DoRasterCHROMIUM::Deserializing | 3427 | 234.95 | 3.00 |
| CommandBufferHelper::Flush | 4026 | 227.36 | 2.31 |
| CommandBufferProxyImpl::Flush | 3984 | 206.00 | 2.31 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

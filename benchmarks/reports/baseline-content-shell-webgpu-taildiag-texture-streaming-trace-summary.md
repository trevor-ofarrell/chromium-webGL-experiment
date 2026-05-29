# Trace Summary

Trace: `benchmarks\traces\baseline-content-shell-webgpu-taildiag-texture-streaming-trace.json`
Sidecar: `C:\Users\trevo\code\three-browser\benchmarks\traces\baseline-content-shell-webgpu-taildiag-texture-streaming-trace.result.json`

Total events: 545457

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| gpu_command | 300202 | 56752.94 |
| other | 235153 | 51650.89 |
| javascript | 1214 | 5862.99 |
| shader_or_pipeline | 5568 | 1919.96 |
| presentation | 3255 | 130.69 |
| texture_upload | 65 | 0.47 |

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
| RunTask | 38165 | 24644.54 | 193.80 |
| Scheduler::RunTask | 13050 | 10436.93 | 193.79 |
| GpuChannel::ExecuteDeferredRequest | 12814 | 10276.95 | 193.78 |
| GPUTask | 12649 | 10188.31 | 193.77 |
| CommandBuffer::Flush | 12586 | 9920.87 | 193.73 |
| CommandBufferStub::OnAsyncFlush | 12586 | 9903.01 | 193.73 |
| CommandBufferService:PutChanged | 12586 | 9814.71 | 193.72 |
| WebGPU | 6100 | 5494.12 | 143.16 |
| RendererMainThread | 6479 | 4228.35 | 10.44 |
| ProxyMain::BeginMainFrame | 87 | 1793.74 | 189.46 |
| AsyncTask Run | 140 | 1773.03 | 188.25 |
| v8.callFunction | 134 | 1754.64 | 188.20 |
| WebFrameWidgetImpl::BeginMainFrame | 87 | 1751.65 | 188.44 |
| Blink.Animate.UpdateTime | 87 | 1750.25 | 188.43 |
| PageAnimator::serviceScriptedAnimations | 87 | 1748.99 | 188.41 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 69 | 1745.69 | 188.38 |
| FireAnimationFrame | 131 | 1745.21 | 188.25 |
| FunctionCall | 134 | 1736.91 | 188.17 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 5995 | 651.17 | 192.60 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 5995 | 572.18 | 192.53 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

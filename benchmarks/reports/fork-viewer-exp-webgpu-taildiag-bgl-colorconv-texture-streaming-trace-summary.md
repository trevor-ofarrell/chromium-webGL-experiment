# Trace Summary

Trace: `benchmarks\traces\fork-viewer-exp-webgpu-taildiag-bgl-colorconv-texture-streaming-trace.json`
Sidecar: `C:\Users\trevo\code\three-browser\benchmarks\traces\fork-viewer-exp-webgpu-taildiag-bgl-colorconv-texture-streaming-trace.result.json`

Total events: 549094

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| gpu_command | 303420 | 55007.33 |
| other | 235417 | 49109.40 |
| javascript | 1610 | 5563.21 |
| shader_or_pipeline | 5410 | 1895.20 |
| presentation | 3171 | 166.68 |
| texture_upload | 66 | 0.45 |

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
| RunTask | 37766 | 23620.44 | 183.31 |
| Scheduler::RunTask | 13127 | 10183.36 | 143.98 |
| GpuChannel::ExecuteDeferredRequest | 12898 | 9999.08 | 143.97 |
| GPUTask | 12733 | 9910.55 | 143.97 |
| CommandBuffer::Flush | 12681 | 9642.14 | 143.94 |
| CommandBufferStub::OnAsyncFlush | 12681 | 9623.95 | 143.94 |
| CommandBufferService:PutChanged | 12681 | 9539.36 | 143.93 |
| WebGPU | 6157 | 5498.59 | 143.94 |
| RendererMainThread | 6532 | 4168.58 | 10.34 |
| ProxyMain::BeginMainFrame | 83 | 1755.79 | 182.94 |
| v8.callFunction | 135 | 1748.85 | 181.84 |
| AsyncTask Run | 136 | 1744.94 | 181.88 |
| FunctionCall | 135 | 1730.59 | 181.81 |
| WebFrameWidgetImpl::BeginMainFrame | 83 | 1716.28 | 182.11 |
| Blink.Animate.UpdateTime | 83 | 1714.48 | 182.10 |
| PageAnimator::serviceScriptedAnimations | 83 | 1713.17 | 182.09 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 68 | 1709.13 | 182.06 |
| FireAnimationFrame | 132 | 1708.77 | 181.88 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 6044 | 424.72 | 0.98 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 6044 | 346.38 | 0.96 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

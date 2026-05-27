# Trace Summary

Trace: `.\benchmarks\traces\iter3-c2-webgpu-texture-baseline-trace.json`

Total events: 449521

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| other | 200834 | 61909.97 |
| gpu_command | 236794 | 55069.05 |
| javascript | 957 | 10587.54 |
| shader_or_pipeline | 8036 | 3377.12 |
| presentation | 2851 | 175.47 |
| texture_upload | 49 | 1.04 |

## Top Duration Events

| Event | Count | Total ms | Max ms |
| --- | ---: | ---: | ---: |
| RunTask | 32018 | 26267.72 | 447.03 |
| Scheduler::RunTask | 10835 | 10222.48 | 250.44 |
| GpuChannel::ExecuteDeferredRequest | 10629 | 10046.62 | 250.42 |
| GPUTask | 10477 | 9949.53 | 250.40 |
| CommandBuffer::Flush | 10393 | 9643.14 | 250.33 |
| CommandBufferStub::OnAsyncFlush | 10393 | 9625.22 | 250.33 |
| CommandBufferService:PutChanged | 10393 | 9548.58 | 250.33 |
| WebGPU | 4649 | 4890.21 | 144.28 |
| RendererMainThread | 5691 | 4289.07 | 30.55 |
| ProxyMain::BeginMainFrame | 99 | 3207.76 | 446.33 |
| AsyncTask Run | 109 | 3167.51 | 433.90 |
| v8.callFunction | 103 | 3100.99 | 433.86 |
| WebFrameWidgetImpl::BeginMainFrame | 98 | 3089.52 | 434.17 |
| Blink.Animate.UpdateTime | 98 | 3087.20 | 434.15 |
| PageAnimator::serviceScriptedAnimations | 98 | 3085.25 | 434.14 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 55 | 3079.62 | 434.09 |
| FireAnimationFrame | 101 | 3079.25 | 433.93 |
| FunctionCall | 103 | 3039.10 | 431.89 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 4532 | 1030.08 | 247.84 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 4532 | 928.48 | 247.78 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

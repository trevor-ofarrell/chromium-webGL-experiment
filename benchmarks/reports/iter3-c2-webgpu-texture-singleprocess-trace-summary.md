# Trace Summary

Trace: `.\benchmarks\traces\iter3-c2-webgpu-texture-singleprocess-trace.json`

Total events: 382718

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| gpu_command | 198218 | 53486.16 |
| other | 173969 | 50060.23 |
| javascript | 975 | 10571.90 |
| shader_or_pipeline | 7197 | 3528.75 |
| presentation | 2317 | 217.82 |
| texture_upload | 42 | 1.09 |

## Top Duration Events

| Event | Count | Total ms | Max ms |
| --- | ---: | ---: | ---: |
| RunTask | 35049 | 15380.51 | 487.33 |
| Scheduler::RunTask | 8750 | 9981.77 | 150.39 |
| GpuChannel::ExecuteDeferredRequest | 8625 | 9788.71 | 150.39 |
| GPUTask | 8461 | 9688.67 | 150.37 |
| CommandBuffer::Flush | 8411 | 9395.85 | 150.34 |
| CommandBufferStub::OnAsyncFlush | 8411 | 9377.17 | 150.33 |
| CommandBufferService:PutChanged | 8411 | 9294.34 | 150.33 |
| WebGPU | 4106 | 4921.23 | 117.39 |
| RendererMainThread | 4265 | 4339.72 | 29.76 |
| ProxyMain::BeginMainFrame | 78 | 3325.37 | 486.54 |
| AsyncTask Run | 93 | 3278.72 | 479.84 |
| v8.callFunction | 90 | 3235.17 | 479.79 |
| WebFrameWidgetImpl::BeginMainFrame | 78 | 3220.33 | 480.11 |
| Blink.Animate.UpdateTime | 78 | 3218.51 | 480.10 |
| PageAnimator::serviceScriptedAnimations | 78 | 3217.07 | 480.08 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 48 | 3212.02 | 480.03 |
| FireAnimationFrame | 88 | 3211.58 | 479.86 |
| FunctionCall | 90 | 3173.31 | 476.83 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 3946 | 743.35 | 149.81 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 3946 | 628.93 | 149.76 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

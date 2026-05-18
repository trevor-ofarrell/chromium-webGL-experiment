# Trace Summary

Trace: `.\benchmarks\traces\smoke-installed-chrome-v9-many-draw-calls-webgl2-trace.json`

Total events: 170148

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| other | 89424 | 19309.73 |
| javascript | 2145 | 7408.86 |
| gpu_command | 55859 | 5968.65 |
| shader_or_pipeline | 14395 | 1981.74 |
| presentation | 8310 | 351.53 |
| texture_upload | 15 | 1.06 |

## Top Duration Events

| Event | Count | Total ms | Max ms |
| --- | ---: | ---: | ---: |
| RunTask | 17474 | 6370.89 | 428.02 |
| AsyncTask Run | 263 | 2106.29 | 426.92 |
| ProxyMain::BeginMainFrame | 262 | 1695.66 | 126.15 |
| WebFrameWidgetImpl::BeginMainFrame | 261 | 1630.34 | 124.89 |
| Blink.Animate.UpdateTime | 261 | 1628.55 | 124.89 |
| PageAnimator::serviceScriptedAnimations | 261 | 1626.92 | 124.88 |
| FrameRequestCallbackCollection::ExecuteFrameCallbacks | 259 | 1621.05 | 124.86 |
| FireAnimationFrame | 258 | 1620.29 | 124.85 |
| v8.callFunction | 258 | 1612.77 | 124.80 |
| FunctionCall | 258 | 1585.58 | 124.37 |
| Scheduler::RunTask | 3145 | 1101.30 | 110.98 |
| GpuChannel::ExecuteDeferredRequest | 2789 | 915.66 | 110.97 |
| GPUTask | 2843 | 885.50 | 110.97 |
| CommandBuffer::Flush | 2740 | 799.99 | 110.96 |
| CommandBufferStub::OnAsyncFlush | 2740 | 796.27 | 110.96 |
| CommandBufferService:PutChanged | 2740 | 782.76 | 110.95 |
| HTMLDocumentParser::NotifyScriptLoaded | 2 | 488.70 | 427.95 |
| HTMLParserScriptRunner::executeScriptsWaitingForParsing | 5 | 487.17 | 426.96 |
| HTMLParserScriptRunner ExecuteScript | 2 | 487.11 | 426.94 |
| PendingScript::ExecuteScriptBlock | 2 | 487.09 | 426.93 |
| CommandBufferHelper::Finish | 55 | 433.54 | 288.00 |
| ImplementationBase::WaitForCmd | 54 | 433.24 | 288.00 |
| CommandBufferProxyImpl::WaitForGetOffset | 53 | 432.05 | 287.87 |
| v8.evaluateModule | 2 | 431.86 | 394.92 |
| WebGL | 2646 | 429.54 | 63.70 |
| RasterDecoderImpl::DoEndRasterCHROMIUM | 59 | 360.12 | 110.18 |
| RasterDecoderImpl::DoEndRasterCHROMIUM::Flush | 59 | 359.43 | 110.08 |
| BrowserRasterWorker | 90 | 342.70 | 110.96 |
| ImplementationBase::GetBucketContents | 37 | 338.11 | 288.01 |
| GLES2::GetString | 26 | 311.90 | 288.07 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.

# Prompt-To-Artifact Checklist

Generated: 2026-05-23 06:02:10 -07:00

Objective: fork Chromium into a single-purpose Three.js/WebGL/WebGPU viewer runtime with benchmark viewer, same-revision stock/fork measurements, documented optimizations, and reproducible build/run workflow.

This checklist is evidence-oriented. Installed-Chrome smoke artifacts validate harness behavior only; they are not accepted as stock/fork performance evidence.

## Summary

- done: 2
- pending: 4
- incomplete: 4

## Checklist

| Area | Requirement | Status | Evidence | Remaining work |
| --- | --- | --- | --- | --- |
| Official performance | Official comparison required options | pending | benchmarks\reports\official-comparison-manifest.json missing required option evidence: aggressive_webgl2_relaxed_validation | Regenerate with -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -AggressiveWebGl2RelaxedValidation -CaptureTrace -BaselinePackageDir and -ForkPackageDir. |
| Official performance | Official comparison manifest | pending | benchmarks\reports\official-comparison-manifest.json does not follow the current Chromium pin refresh: manifest generated_at=2026-05-21T01:14:12.5944462Z predates pin refresh selected_at=2026-05-22T12:34:31.2710451Z | Regenerate via scripts/run_post_atl_pipeline.ps1 -RefreshChromiumPin so official stock/fork evidence follows the current upstream-head pin refresh. |
| Official performance | Required WebGL2/WebGPU speedup claim gate | pending | benchmarks\reports\official-comparison-manifest.json does not follow the current Chromium pin refresh: manifest generated_at=2026-05-21T01:14:12.5944462Z predates pin refresh selected_at=2026-05-22T12:34:31.2710451Z | Regenerate official stock/fork evidence after the current upstream-head Chromium pin refresh before claiming speedups. |
| Official performance | Targeted blocker experiment plan manifest | done | benchmarks\reports\targeted-blocker-experiment-plan.json records focused WebGL2/WebGPU blocker scenes, source candidate-analysis policy and input digest checks, current official/trusted seed digest checks when current completed manifests are available, scoped analyzer inputs with completed-run digest and exact input-file metadata checks, checkout-built browser gating, package-size evidence, frame-time requirements, exact revision filters, seven-scene retention gates, WebGL2/WebGPU renderer gates, blocked-tail diagnostics, targeted WebGPU trace capture with CPU-fallback and software-renderer rejection, and suite-promotion handoff | Run the planned commands after checkout-built Chromium binaries are available, then promote only analyzer-retained profiles. |
| Official performance | Targeted suite-promotion plan manifest | done | benchmarks\reports\targeted-suite-promotion-plan.json records no promotable triage profiles, zero generated analyzer inputs, all required scenes, renderer gates, strict analysis thresholds, checkout-built browser gating, and package-size evidence requirements | Run targeted blocker experiments again after the Chromium build blocker is cleared. |
| Official performance | Trusted experiment matrix manifest | pending | benchmarks\reports\trusted-experiment-matrix-manifest.json does not follow the current Chromium pin refresh: manifest generated_at=2026-05-21T02:37:06.8500118Z predates pin refresh selected_at=2026-05-22T12:34:31.2710451Z | Regenerate via scripts/run_post_atl_pipeline.ps1 -RefreshChromiumPin so trusted evidence follows the current upstream-head pin refresh. |

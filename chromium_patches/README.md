# Chromium Patch Area

This directory tracks the Chromium fork patch series and the notes used to reapply or rebase it.

Active patch series:

- `0000-draft-win-clang-build-workarounds.patch` (common build-support gates for the Windows host compiler crashes; applied identically to stock and fork builds and not counted as viewer optimizations)
- `0001-draft-minimal-three-viewer-entrypoint.patch` (content-shell viewer entrypoint plus trusted WebGL2 relaxed-validation draw-path experiment)
- `0002-draft-webgpu-queue-trace-attribution.patch` (trace attribution plus default WebGPU `requestDevice` empty required-features fast path, default device `adapterInfo` reuse, default small-batch submit allocation skip, default writeBuffer full-span and zero-offset explicit-count range fast paths, default `setImmediates` implicit/explicit full-span validation fast path, default empty-label UTF-8 conversion skip across common WebGPU descriptors, descriptor-backed texture wrappers, and canvas current-texture wrappers, default bind-group empty-dynamic-offset fast path across direct render-pass, render-bundle, compute-pass, and typed-array dynamic-offset encoder calls, default render-pass color-attachment stack conversion, render-pass clearValue GPUColor-dict conversion, and merged depth-slice validation, default pipeline-layout bind-group-layout stack conversion, default bind-group entry stack conversion, default bind-group-layout entry stack conversion, default render-pipeline vertex/fragment descriptor stack conversion, default programmable-stage shader-constant stack conversion, default texture size `GPUExtent3D` conversion fast path, texture view-format stack conversion, descriptor-metadata-backed texture wrapper construction for `GPUDevice.createTexture` and descriptor-backed internal/canvas copy-to-swap textures, default texture-view default descriptor fast path, default sampler default-descriptor fast path, default render-bundle color-format stack conversion, default render-pass executeBundles stack conversion, default command-encoder creation, compute-pass begin, command-buffer finish, and render-bundle finish default-descriptor fast paths, default texel-copy texture default/common-origin conversion fast path, default external-image source default/common-origin conversion fast path, default common `writeTexture` layout, byte-count, and `GPUExtent3D` conversion fast paths, default full-source `copyExternalImageToTexture` subrect and `GPUExtent3D` conversion fast paths, default command-encoder texture-copy `GPUExtent3D` and texel-copy buffer layout conversion fast paths, default sRGB destination color-space validation fast path, default source-color-space metadata fast path, default same-color-space `copyExternalImageToTexture` conversion-constant fast path, trusted WebGPU async pipeline/queue/submit flush deferral, command-label skip coverage for pass/command debug groups, debug markers, render-bundle encoder and bundle labels, and the internal CanvasTexture CPU-fallback command encoder, resource-label propagation skip, shader-module NUL-scan and memory-accounting skips, canvas validation skip, canvas memory-accounting skip, copyExternalImage sRGB color-conversion setup skip, copyExternalImage sRGB color-space validation skip, copyExternalImage destination/source/copy-size validation skips, writeTexture layout-validation skip, hot-path use-counter skip, and CPU texture-fallback rejection diagnostics)

Patch status for this evidence set:

- Pinned Chromium revision: `3a94d90ec3c04556622c56944796dd76753e0581`
- Fork revision stamp: `3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-43dbf0b6871e`
- Baseline target: `//content/shell:content_shell`
- Fork target: content-shell-derived viewer runtime with one `WebContents`, local viewer launch, hidden browser chrome, and viewer navigation lock.

Primary evidence:

- Official comparison manifest: `benchmarks/reports/official-comparison-manifest.json`
- Trusted experiment manifest: `benchmarks/reports/trusted-experiment-matrix-manifest.json`
- Removed-subsystem register: `docs/removed_subsystems.md`
- Optimization decision log: `docs/optimization_log.md`

Patch policy:

- Unsafe runtime changes stay behind viewer-specific switches and `--viewer-trusted-content`.
- The stock baseline and fork evidence must come from the same Chromium revision and matching GN args hash.
- The common build-support patch must be present, and `dcheck_always_on = false`, `enable_expensive_dchecks = false`, `enable_ubsan_hardening = false`, plus `disable_llvm_machine_scheduler = true` must be identical across stock and fork evidence until the host clang crashes are resolved.
- Any subsystem removal or retained experiment must be reflected in `docs/removed_subsystems.md` and `docs/optimization_log.md`.
- Future rebases should apply this patch series in order, run static patch tests, build stock and fork outputs, rerun smoke/navigation suites, rerun official and trusted benchmark suites, and refresh the reports.

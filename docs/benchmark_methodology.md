# Benchmark Methodology

WSL evidence starts with hardware WebGL2 stock-versus-fork comparisons built from the same pinned Chromium revision.

## Rules

- Build stock and fork `content_shell` under Ubuntu 22.04 WSL2 from the Linux filesystem.
- Use `src/out/ReleaseBaseline/content_shell` for stock and `src/out/ReleaseViewerDefault/content_shell` for the fork.
- Run the seven-scene WebGL2 suite through `scripts/run_official_comparison.sh`.
- Reject software renderers such as SwiftShader and llvmpipe for retained evidence.
- Treat Windows artifacts and archived D3D results as historical only.
- Keep WebGPU evidence out of retained WSL claims until a Linux/Vulkan-oriented matrix is added and validated.

## Primary Command

```bash
./scripts/run_official_comparison.sh \
  --baseline-browser ./src/out/ReleaseBaseline/content_shell \
  --fork-browser ./src/out/ReleaseViewerDefault/content_shell \
  --baseline-package-dir ./benchmarks/packages/baseline-content-shell \
  --fork-package-dir ./benchmarks/packages/viewer-default \
  --renderer webgl2
```

The runner writes raw JSON under `benchmarks/raw/`, summary/comparison reports under `benchmarks/reports/`, and an official manifest with WSL platform metadata.

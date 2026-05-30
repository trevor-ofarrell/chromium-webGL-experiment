# Trusted Content Flags

Trusted viewer flags remain opt-in and require local viewer mode plus trusted content. The WSL-supported retained path starts with default hardware WebGL2; backend-specific probes are experiments only.

| Flag | WSL status |
| --- | --- |
| `--viewer-trusted-content` | Required for fork-only trusted aliases. |
| `--viewer-aggressive-gpu` | Trusted WebGL2 experiment only. |
| `--viewer-force-angle-backend=<backend>` | Use only after verifying the backend exists on the WSL host; default hardware path is preferred. |
| `--viewer-relaxed-webgl-validation` | Trusted experiment only; must pass full WebGL2 suite before any retained claim. |
| `--viewer-zero-copy` | Trusted experiment only; must not be mixed with WebGPU claims. |
| WebGPU/Dawn D3D flags | Archived Windows evidence only; not WSL parity. |

The runner records browser flags and WSL host metadata in benchmark JSON so incompatible evidence is not silently mixed.

#!/usr/bin/env bash

set -euo pipefail

cat >&2 <<'MSG'
The Windows targeted blocker matrix has been archived.

For the completed WSL migration, run:
  ./scripts/run_current_candidate_analysis.sh --input <result.json> ...
  ./scripts/run_trusted_experiment_matrix.sh --browser ./src/out/ReleaseViewerDefault/content_shell --renderer webgl2 --include-default --include-aggressive-gpu

WebGPU/D3D blocker experiments are not WSL parity and intentionally fail closed.
MSG
exit 2

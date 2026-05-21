# Chromium Patch Area

This directory tracks the Chromium fork patch series and the notes used to reapply or rebase it.

Active patch:

- `0001-draft-minimal-three-viewer-entrypoint.patch`

Patch status for this evidence set:

- Pinned Chromium revision: `3a94d90ec3c04556622c56944796dd76753e0581`
- Fork revision stamp: `3a94d90ec3c04556622c56944796dd76753e0581+viewerpatch-cca4b9171b07`
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
- Any subsystem removal or retained experiment must be reflected in `docs/removed_subsystems.md` and `docs/optimization_log.md`.
- Future rebases should apply this patch, run static patch tests, build stock and fork outputs, rerun smoke/navigation suites, rerun official and trusted benchmark suites, and refresh the reports.

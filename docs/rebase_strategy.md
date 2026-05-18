# Rebase Strategy

1. Keep the upstream Chromium revision pinned in `.chromium_revision`.
   - Treat `benchmarks/reports/prebuild-environment.json` as the freshness record: it captures the observed upstream `origin HEAD` and whether it matched the active pin when checked.
   - For completion evidence, run the post-ATL pipeline with `-RefreshChromiumPin` immediately before compiling stock and fork binaries, then keep that refreshed revision fixed for the full stock/fork benchmark cycle.
2. Keep viewer/runtime work in a small patch series on top of `src/main`.
3. Prefer changes under a new viewer target or content-shell-derived embedder path over broad edits in shared Blink/GPU code.
4. Gate unsafe experiments with viewer-specific switches and keep default behavior close to upstream.
5. Rebase procedure:
   - Run `.\scripts\refresh_chromium_pin.ps1` from the repository root, or manually update `.chromium_revision` to the target upstream commit. The helper restamps `docs/source_investigation.md` only after its documented source paths and sentinel symbols validate against the refreshed checkout.
   - If refreshing manually: `cd src`, `git fetch origin main`, `git checkout <new_revision>`, then run `gclient sync --no-history`.
   - Re-apply `chromium_patches` or rebase the fork branch if the patch has already been applied.
   - Build stock baseline and fork from the same revision.
   - Run smoke tests and benchmark subset before full suite.
6. If an upstream change breaks a patch, split the fix into a rebase compatibility commit separate from new optimization work.

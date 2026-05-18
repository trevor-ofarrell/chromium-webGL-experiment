# Chromium Patch Area

This directory tracks fork patches and patch notes applied to `src/`, the Chromium checkout.

Initial target selection:

- Baseline target: `//content/shell:content_shell`
- Fork starting point: a content-shell-derived one-view executable that creates one `WebContents`, loads the local viewer URL, and blocks navigation outside the trusted viewer origin.

The workspace has a synced `src/` checkout at the revision pinned in `.chromium_revision`. Keep it pristine for stock baseline builds until those artifacts are captured.

Current draft patch:

- `0001-draft-minimal-three-viewer-entrypoint.patch`

Apply and build the fork profile after baseline capture:

```powershell
.\scripts\build_viewer_fork.ps1 -ApplyPatch
```

Patch policy:

- Every unsafe optimization must be gated behind a viewer-specific build arg or runtime switch.
- Every subsystem removal must be listed in `docs/removed_subsystems.md`.
- Every kept/reverted experiment must be recorded in `docs/optimization_log.md` with benchmark evidence.

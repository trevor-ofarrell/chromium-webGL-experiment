# Prompt To Artifact Checklist

Generated: 2026-05-30T19:02:48Z

| Area | Requirement | Status | Artifact | Remaining Work |
| --- | --- | --- | --- | --- |
| WSL setup | LF attributes | done | `.gitattributes` | Add repository line-ending policy. |
| WSL setup | WSL migration guide | done | `docs/wsl.md` | Document fresh clone and excluded Windows artifacts. |
| Build | Linux baseline GN profile | done | `build/gn_args/linux/baseline_content_shell.gn` | Create Linux baseline profile. |
| Build | Linux fork GN profile | done | `build/gn_args/linux/fork_safe_content_shell.gn` | Create Linux fork profile. |
| Automation | Bootstrap script | done | `scripts/bootstrap_wsl.sh` | Add executable bootstrap_wsl.sh. |
| Automation | Prerequisite checker | done | `scripts/check_prereqs.sh` | Add executable check_prereqs.sh. |
| Automation | Chromium builder | done | `scripts/build_chromium.sh` | Add executable build_chromium.sh. |
| Automation | Fork builder | done | `scripts/build_viewer_fork.sh` | Add executable build_viewer_fork.sh. |
| Automation | Package staging | done | `scripts/stage_viewer_package.sh` | Add executable stage_viewer_package.sh. |
| Automation | Official comparison | done | `scripts/run_official_comparison.sh` | Add executable run_official_comparison.sh. |
| Automation | Prebuild verifier | done | `scripts/verify_prebuild.sh` | Add executable verify_prebuild.sh. |
| Automation | Artifact audit | done | `scripts/audit_artifacts.sh` | Add executable audit_artifacts.sh. |
| Build output | Stock Linux content_shell | pending | `src/out/ReleaseBaseline/content_shell` | Build the stock baseline in WSL. missing executable src/out/ReleaseBaseline/content_shell |
| Build output | Fork Linux content_shell | pending | `src/out/ReleaseViewerDefault/content_shell` | Build the patched fork in WSL. missing executable src/out/ReleaseViewerDefault/content_shell |
| Build output | Stock WSL provenance | pending | `src/out/ReleaseBaseline/three_browser_build_provenance.json` | Run build_chromium.sh on WSL. host_platform must be wsl-linux |
| Build output | Fork WSL provenance | pending | `src/out/ReleaseViewerDefault/three_browser_build_provenance.json` | Run build_viewer_fork.sh on WSL. host_platform must be wsl-linux |
| Package | Fork Linux package launcher | pending | `benchmarks/packages/viewer-default/run_viewer.sh` | Stage the fork package on WSL. missing executable benchmarks/packages/viewer-default/run_viewer.sh |
| Performance | Official WSL WebGL2 comparison manifest | pending | `benchmarks/reports/official-comparison-manifest.json` | Run run_official_comparison.sh on WSL. host_platform must be wsl-linux |
| Performance | Official WSL WebGL2 report | pending | `benchmarks/reports/official-webgl2-comparison.md` | Run run_official_comparison.sh on WSL. report contains Windows-specific evidence |

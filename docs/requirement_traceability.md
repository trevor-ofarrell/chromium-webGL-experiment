# Requirement Traceability

| Requirement | WSL Artifact |
| --- | --- |
| Fresh Linux filesystem checkout | `docs/wsl.md` |
| Linux line endings | `.gitattributes` |
| Ubuntu/WSL prerequisite checks | `scripts/check_prereqs.sh` |
| Chromium bootstrap | `scripts/bootstrap_wsl.sh` |
| Stock Chromium build | `scripts/build_chromium.sh`, `build/gn_args/linux/baseline_content_shell.gn` |
| Fork Chromium build | `scripts/build_viewer_fork.sh`, `build/gn_args/linux/fork_safe_content_shell.gn` |
| Linux package staging | `scripts/stage_viewer_package.sh` |
| Hardware WebGL2 evidence | `scripts/run_official_comparison.sh` |
| Final artifact checklist | `scripts/audit_artifacts.sh`, `docs/prompt_to_artifact_checklist.md` |
| Static migration regression tests | `scripts/verify_prebuild.sh`, `scripts/test_*.sh` |

Historical Windows traceability is archived in `docs/windows-legacy/requirement_traceability.md`.

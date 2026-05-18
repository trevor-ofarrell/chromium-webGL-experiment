[CmdletBinding()]
param(
  [switch]$AllowMissingAtl
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Test-GitApply {
  param(
    [string]$SourceDir,
    [string]$PatchPath,
    [switch]$Reverse
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Args = @("-C", $SourceDir, "apply")
    if ($Reverse) {
      $Args += "--reverse"
    }
    $Args += @("--check", $PatchPath)
    & git @Args *>$null
    return ($LASTEXITCODE -eq 0)
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Assert-EnvironmentManifestChecks {
  param(
    [string]$ManifestPath,
    [bool]$AllowAtlFailures
  )

  $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  $FailingChecks = @($Manifest.checks | Where-Object { -not $_.ok })
  if ($FailingChecks.Count -eq 0) {
    return
  }

  $AllowedWhenAtlBlocked = @(
    "visual_studio_atl",
    "visual_studio_atl_component"
  )
  $UnexpectedFailures = @($FailingChecks | Where-Object {
      -not ($AllowAtlFailures -and ($AllowedWhenAtlBlocked -contains $_.name))
    })

  if ($UnexpectedFailures.Count -gt 0) {
    $Details = @($UnexpectedFailures | ForEach-Object { "$($_.name): $($_.detail)" }) -join "; "
    throw "Prebuild environment manifest has failing checks: $Details"
  }
}

Write-Host "Checking host and checkout prerequisites..."
& (Join-Path $Root "scripts\check_prereqs.ps1")
$PrereqExit = $LASTEXITCODE
if ($PrereqExit -ne 0 -and -not $AllowMissingAtl) {
  throw "Prerequisite check failed. Use -AllowMissingAtl only to continue non-build verification while ATL is blocked."
}

Write-Host "Checking Chromium viewer patch applicability..."
$Src = Join-Path $Root "src"
$Patch = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
if (Test-GitApply $Src $Patch) {
  Write-Host "Viewer patch applies cleanly to the current checkout."
} else {
  if (Test-GitApply $Src $Patch -Reverse) {
    Write-Host "Viewer patch is already applied to the current checkout."
  } else {
    throw "Draft viewer patch does not apply cleanly and is not already applied."
  }
}

Write-Host "Checking Chromium patch notes consistency..."
& (Join-Path $Root "scripts\test_patch_notes_consistency.ps1")

Write-Host "Checking Chromium patch notes completion audit..."
& (Join-Path $Root "scripts\test_patch_notes_completion_audit.ps1")

Write-Host "Checking viewer patch entrypoint..."
& (Join-Path $Root "scripts\test_viewer_patch_entrypoint.ps1")

Write-Host "Checking viewer patch trusted-content gates..."
& (Join-Path $Root "scripts\test_viewer_patch_trusted_gates.ps1")

Write-Host "Checking viewer patch navigation lock..."
& (Join-Path $Root "scripts\test_viewer_patch_navigation_lock.ps1")

Write-Host "Checking viewer patch stdout result forwarding..."
& (Join-Path $Root "scripts\test_viewer_patch_stdout_result.ps1")

Write-Host "Checking viewer runtime API surface..."
& (Join-Path $Root "scripts\test_viewer_runtime_surface.ps1")

Write-Host "Checking viewer bundle integrity..."
& (Join-Path $Root "scripts\test_viewer_bundle_integrity.ps1")

Write-Host "Checking metric schema consistency..."
& (Join-Path $Root "scripts\test_metric_schema_consistency.ps1")

Write-Host "Checking scene coverage consistency..."
& (Join-Path $Root "scripts\test_scene_coverage_consistency.ps1")

Write-Host "Checking benchmark flag metadata coverage..."
& (Join-Path $Root "scripts\test_benchmark_flag_metadata.ps1")

Write-Host "Checking benchmark metadata enrichment..."
& (Join-Path $Root "scripts\test_benchmark_metadata_enrichment.ps1")

Write-Host "Checking report metric coverage..."
& (Join-Path $Root "scripts\test_report_metric_coverage.ps1")

Write-Host "Checking trusted-content flag documentation..."
& (Join-Path $Root "scripts\test_trusted_content_flags_doc.ps1")

Write-Host "Checking hardware-GPU launch flags..."
& (Join-Path $Root "scripts\test_hardware_gpu_launch_flags.ps1")

Write-Host "Checking runtime smoke coverage..."
& (Join-Path $Root "scripts\test_smoke_coverage.ps1")

Write-Host "Checking trace capture start-delay coverage..."
& (Join-Path $Root "scripts\test_trace_capture_start_delay.ps1")

Write-Host "Checking trace file validation..."
& (Join-Path $Root "scripts\test_trace_file_validation.ps1")

Write-Host "Checking trace result sidecar validation..."
& (Join-Path $Root "scripts\test_trace_result_validation.ps1")

Write-Host "Checking smoke detail validation..."
& (Join-Path $Root "scripts\test_smoke_detail_validation.ps1")

Write-Host "Checking optimization tracking coverage..."
& (Join-Path $Root "scripts\test_optimization_tracking.ps1")

Write-Host "Checking optimization decision audit..."
& (Join-Path $Root "scripts\test_optimization_decision_audit.ps1")

Write-Host "Checking removed subsystem register structure..."
& (Join-Path $Root "scripts\test_removed_subsystems_register.ps1")

Write-Host "Checking removed subsystem completion audit..."
& (Join-Path $Root "scripts\test_removed_subsystems_completion_audit.ps1")

Write-Host "Checking source investigation path map..."
& (Join-Path $Root "scripts\test_source_investigation_paths.ps1")

Write-Host "Checking source investigation revision guard..."
& (Join-Path $Root "scripts\test_source_investigation_revision_guard.ps1")

Write-Host "Checking documentation structure..."
& (Join-Path $Root "scripts\test_documentation_structure.ps1")

Write-Host "Checking documentation completion audit..."
& (Join-Path $Root "scripts\test_documentation_completion_audit.ps1")

Write-Host "Checking performance claim guard..."
& (Join-Path $Root "scripts\test_performance_claim_guard.ps1")

Write-Host "Checking Chromium-only scope guard..."
& (Join-Path $Root "scripts\test_chromium_scope_guard.ps1")

Write-Host "Checking reproduction handoff audit..."
& (Join-Path $Root "scripts\test_reproduction_handoff_audit.ps1")

Write-Host "Checking ATL remediation handoff..."
& (Join-Path $Root "scripts\test_atl_remediation_handoff.ps1")

Write-Host "Checking ATL blocker audit evidence..."
& (Join-Path $Root "scripts\test_atl_blocker_audit.ps1")

Write-Host "Checking binary artifact audit rows..."
& (Join-Path $Root "scripts\test_binary_audit_rows.ps1")

Write-Host "Checking script syntax..."
$PowerShellScripts = @(
  "audit_artifacts.ps1",
  "build_chromium.ps1",
  "build_viewer_fork.ps1",
  "check_prereqs.ps1",
  "inspect_chromium_target.ps1",
  "install_vs_atl.ps1",
  "refresh_chromium_pin.ps1",
  "run_full_suite.ps1",
  "run_long_stability.ps1",
  "run_official_comparison.ps1",
  "run_post_atl_pipeline.ps1",
  "run_trusted_experiment_matrix.ps1",
  "stage_viewer_package.ps1",
  "test_atl_blocker_audit.ps1",
  "test_atl_remediation_handoff.ps1",
  "test_audit_manifest_override_guard.ps1",
  "test_benchmark_flag_metadata.ps1",
  "test_benchmark_metadata_enrichment.ps1",
  "test_binary_audit_rows.ps1",
  "test_audit_fail_on_incomplete.ps1",
  "test_audit_official_suite_validation_gates.ps1",
  "test_benchmark_suite_duration_validation.ps1",
  "test_benchmark_suite_flag_metadata.ps1",
  "test_benchmark_suite_package_validation.ps1",
  "test_benchmark_suite_rejects_software_rendering.ps1",
  "test_revision_validation.ps1",
  "test_build_args_guard.ps1",
  "test_chromium_scope_guard.ps1",
  "test_dry_run_manifests.ps1",
  "test_documentation_completion_audit.ps1",
  "test_documentation_structure.ps1",
  "test_environment_manifest_coverage.ps1",
  "test_gn_args_profiles.ps1",
  "test_gn_gen_only.ps1",
  "test_hardware_gpu_launch_flags.ps1",
  "test_manifest_artifact_path_audit.ps1",
  "test_manifest_package_audit.ps1",
  "test_metric_schema_consistency.ps1",
  "test_official_manifest_provenance_audit.ps1",
  "test_official_manifest_suite_semantics_audit.ps1",
  "test_official_manifest_aggressive_audit.ps1",
  "test_official_manifest_webgpu_audit.ps1",
  "test_official_manifest_report_audit.ps1",
  "test_official_manifest_required_options_audit.ps1",
  "test_official_manifest_runtime_audit.ps1",
  "test_official_manifest_trace_audit.ps1",
  "test_official_report_file_content_audit.ps1",
  "test_optimization_decision_audit.ps1",
  "test_optimization_tracking.ps1",
  "test_patch_notes_completion_audit.ps1",
  "test_patch_notes_consistency.ps1",
  "test_performance_claim_guard.ps1",
  "test_post_atl_pipeline_dry_run.ps1",
  "test_patch_state_audit.ps1",
  "test_refresh_chromium_pin_dry_run.ps1",
  "test_reproduction_handoff_audit.ps1",
  "test_removed_subsystems_register.ps1",
  "test_report_metric_coverage.ps1",
  "test_scene_coverage_consistency.ps1",
  "test_smoke_detail_validation.ps1",
  "test_smoke_coverage.ps1",
  "test_stage_viewer_package.ps1",
  "test_stability_result_thresholds.ps1",
  "test_source_investigation_paths.ps1",
  "test_source_investigation_revision_guard.ps1",
  "test_strict_official_rejects_software_rendering.ps1",
  "test_trace_capture_start_delay.ps1",
  "test_trace_file_validation.ps1",
  "test_trace_result_validation.ps1",
  "test_trusted_manifest_flag_audit.ps1",
  "test_trusted_manifest_provenance_audit.ps1",
  "test_trusted_manifest_required_options_audit.ps1",
  "test_trusted_manifest_suite_semantics_audit.ps1",
  "test_trusted_content_flags_doc.ps1",
  "test_upstream_freshness_audit.ps1",
  "test_verify_prebuild_manifest_gate.ps1",
  "test_viewer_bundle_integrity.ps1",
  "test_viewer_patch_entrypoint.ps1",
  "test_viewer_patch_navigation_lock.ps1",
  "test_viewer_patch_stdout_result.ps1",
  "test_viewer_patch_trusted_gates.ps1",
  "test_viewer_runtime_surface.ps1",
  "verify_prebuild.ps1",
  "write_environment_manifest.ps1"
)
foreach ($Script in $PowerShellScripts) {
  $ScriptPath = Join-Path $Root "scripts\$Script"
  $null = [scriptblock]::Create((Get-Content $ScriptPath -Raw))
}

$NodeScripts = @(
  "compare_results.mjs",
  "run_file_navigation_lock_tests.mjs",
  "run_benchmark.mjs",
  "run_navigation_lock_tests.mjs",
  "run_smoke_tests.mjs",
  "run_trace_capture.mjs",
  "summarize_trace.mjs",
  "summarize_results.mjs",
  "validate_metrics.mjs",
  "validate_benchmark_suite.mjs",
  "validate_trace_file.mjs",
  "validate_trace_result.mjs",
  "validate_stability_result.mjs",
  "validate_smoke_result.mjs"
)
foreach ($Script in $NodeScripts) {
  node --check (Join-Path $Root "scripts\$Script")
  if ($LASTEXITCODE -ne 0) {
    throw "Node syntax check failed for $Script."
  }
}

Write-Host "Writing prebuild environment manifest..."
$EnvironmentManifestPath = Join-Path $Root "benchmarks\reports\prebuild-environment.json"
& (Join-Path $Root "scripts\write_environment_manifest.ps1") -Output "benchmarks\reports\prebuild-environment.json"
Assert-EnvironmentManifestChecks -ManifestPath $EnvironmentManifestPath -AllowAtlFailures ([bool]$AllowMissingAtl)

Write-Host "Checking environment manifest coverage..."
& (Join-Path $Root "scripts\test_environment_manifest_coverage.ps1")

Write-Host "Checking prebuild manifest failure gate..."
& (Join-Path $Root "scripts\test_verify_prebuild_manifest_gate.ps1")

Write-Host "Checking generated GN args stale-file guard..."
& (Join-Path $Root "scripts\test_build_args_guard.ps1")

Write-Host "Checking GN args profile policy..."
& (Join-Path $Root "scripts\test_gn_args_profiles.ps1")

Write-Host "Checking GN generation-only mode..."
& (Join-Path $Root "scripts\test_gn_gen_only.ps1")

Write-Host "Checking post-ATL dry-run orchestration..."
& (Join-Path $Root "scripts\test_post_atl_pipeline_dry_run.ps1")

Write-Host "Checking patch-state audit regression..."
& (Join-Path $Root "scripts\test_patch_state_audit.ps1")

Write-Host "Checking Chromium pin refresh dry-run..."
& (Join-Path $Root "scripts\test_refresh_chromium_pin_dry_run.ps1")

Write-Host "Checking upstream freshness audit..."
& (Join-Path $Root "scripts\test_upstream_freshness_audit.ps1")

Write-Host "Checking viewer package staging..."
& (Join-Path $Root "scripts\test_stage_viewer_package.ps1")

Write-Host "Checking artifact audit final gate..."
& (Join-Path $Root "scripts\test_audit_fail_on_incomplete.ps1")

Write-Host "Checking artifact audit official suite validation gates..."
& (Join-Path $Root "scripts\test_audit_official_suite_validation_gates.ps1")

Write-Host "Checking dry-run manifest structure..."
& (Join-Path $Root "scripts\test_dry_run_manifests.ps1")

Write-Host "Checking artifact audit manifest override guard..."
& (Join-Path $Root "scripts\test_audit_manifest_override_guard.ps1")

Write-Host "Checking manifest package metadata audit gate..."
& (Join-Path $Root "scripts\test_manifest_package_audit.ps1")

Write-Host "Checking manifest artifact path/hash audit gate..."
& (Join-Path $Root "scripts\test_manifest_artifact_path_audit.ps1")

Write-Host "Checking official manifest provenance audit gate..."
& (Join-Path $Root "scripts\test_official_manifest_provenance_audit.ps1")

Write-Host "Checking official manifest exact-suite semantic audit gate..."
& (Join-Path $Root "scripts\test_official_manifest_suite_semantics_audit.ps1")

Write-Host "Checking official manifest aggressive audit gate..."
& (Join-Path $Root "scripts\test_official_manifest_aggressive_audit.ps1")

Write-Host "Checking official manifest WebGPU audit gate..."
& (Join-Path $Root "scripts\test_official_manifest_webgpu_audit.ps1")

Write-Host "Checking official manifest report audit gate..."
& (Join-Path $Root "scripts\test_official_manifest_report_audit.ps1")

Write-Host "Checking official report file content audit gate..."
& (Join-Path $Root "scripts\test_official_report_file_content_audit.ps1")

Write-Host "Checking official manifest required-options audit gate..."
& (Join-Path $Root "scripts\test_official_manifest_required_options_audit.ps1")

Write-Host "Checking official manifest runtime audit gate..."
& (Join-Path $Root "scripts\test_official_manifest_runtime_audit.ps1")

Write-Host "Checking official manifest trace audit gate..."
& (Join-Path $Root "scripts\test_official_manifest_trace_audit.ps1")

Write-Host "Checking trusted manifest flag audit gate..."
& (Join-Path $Root "scripts\test_trusted_manifest_flag_audit.ps1")

Write-Host "Checking trusted manifest provenance audit gate..."
& (Join-Path $Root "scripts\test_trusted_manifest_provenance_audit.ps1")

Write-Host "Checking trusted manifest required-options audit gate..."
& (Join-Path $Root "scripts\test_trusted_manifest_required_options_audit.ps1")

Write-Host "Checking trusted manifest exact-suite semantic audit gate..."
& (Join-Path $Root "scripts\test_trusted_manifest_suite_semantics_audit.ps1")

Write-Host "Checking strict official software-renderer rejection..."
& (Join-Path $Root "scripts\test_strict_official_rejects_software_rendering.ps1")

Write-Host "Checking benchmark suite software-renderer rejection..."
& (Join-Path $Root "scripts\test_benchmark_suite_rejects_software_rendering.ps1")

Write-Host "Checking benchmark suite duration validation..."
& (Join-Path $Root "scripts\test_benchmark_suite_duration_validation.ps1")

Write-Host "Checking benchmark suite flag metadata validation..."
& (Join-Path $Root "scripts\test_benchmark_suite_flag_metadata.ps1")

Write-Host "Checking benchmark suite package-size validation..."
& (Join-Path $Root "scripts\test_benchmark_suite_package_validation.ps1")

Write-Host "Checking benchmark and stability Chromium revision validation..."
& (Join-Path $Root "scripts\test_revision_validation.ps1")

Write-Host "Checking stability result threshold validation..."
& (Join-Path $Root "scripts\test_stability_result_thresholds.ps1")

Write-Host "Building viewer bundle..."
Push-Location (Join-Path $Root "viewer")
try {
  npm run build
} finally {
  Pop-Location
}

Write-Host "Validating current-schema benchmark JSON artifacts..."
$JsonFiles = Get-ChildItem (Join-Path $Root "benchmarks\raw") -Filter "*.json" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "-v6-|-v7-webgpu-|-v10-resource-warmup-|-v11-stability-fields-|-v12-gltf-|-v13-file-gltf-.*allow-file-access|-v14-webgpu-timestamp-|-v15-webgpu-postprocessing-|-v16-webgpu-shader-heavy-|-v17-webgpu-current-|-v18-renderer-resource-counters-|^baseline-|^fork-" -and $_.Name -notmatch "runtime-smoke" }
foreach ($File in $JsonFiles) {
  node (Join-Path $Root "scripts\validate_metrics.mjs") $File.FullName
}

Write-Host "Validating current smoke JSON artifacts..."
$SmokeFile = Join-Path $Root "benchmarks\raw\smoke-installed-chrome-v11-stability-smoke.json"
if (Test-Path $SmokeFile) {
  node (Join-Path $Root "scripts\validate_smoke_result.mjs") --type runtime --require-webgpu $SmokeFile
}

Write-Host "Validating current installed-Chrome WebGPU suite artifact coverage..."
$WebGpuSuite = @(Get-ChildItem (Join-Path $Root "benchmarks\raw") -Filter "smoke-installed-chrome-v17-webgpu-current-*-webgpu.json" -ErrorAction SilentlyContinue)
if ($WebGpuSuite.Count -gt 0) {
  node (Join-Path $Root "scripts\validate_benchmark_suite.mjs") --renderer webgpu --variant smoke-installed-chrome-v17-webgpu-current @($WebGpuSuite.FullName)
}

Write-Host "Prebuild verification complete."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\dry-run-manifest-test"
$OfficialManifestPath = Join-Path $Root "benchmarks\reports\official-comparison-manifest.dry-run.json"
$TrustedManifestPath = Join-Path $Root "benchmarks\reports\trusted-experiment-matrix-manifest.dry-run.json"
$OfficialBackupPath = Join-Path $TempDir "official-comparison-manifest.dry-run.backup.json"
$TrustedBackupPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.dry-run.backup.json"
$RequiredScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

function Get-GitRevision {
  param([string]$RepoPath)
  if (-not (Test-Path $RepoPath)) {
    throw "Git repository path not found: $RepoPath"
  }
  $Revision = (& git -C $RepoPath rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $Revision) {
    throw "Unable to read git revision from $RepoPath"
  }
  return $Revision
}

function Get-ShortSha256 {
  param([string]$PathValue)
  if (-not (Test-Path $PathValue)) {
    throw "File not found for hash: $PathValue"
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.Substring(0, 12).ToLowerInvariant()
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Description
  )
  if (-not $Condition) {
    throw "Dry-run manifest assertion failed: $Description"
  }
}

function Assert-Equal {
  param(
    [object]$Actual,
    [object]$Expected,
    [string]$Description
  )
  if ($Actual -ne $Expected) {
    throw "Dry-run manifest assertion failed: $Description. Actual='$Actual' Expected='$Expected'"
  }
}

function Assert-Count {
  param(
    [object[]]$Items,
    [int]$Expected,
    [string]$Description
  )
  $Actual = @($Items).Count
  if ($Actual -ne $Expected) {
    throw "Dry-run manifest assertion failed: $Description. Actual count=$Actual Expected=$Expected"
  }
}

function Assert-Matches {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Dry-run command assertion failed: $Description. Pattern: $Pattern"
  }
}

function Assert-Scenes {
  param(
    [object[]]$Scenes,
    [string]$Description
  )
  Assert-Count @($Scenes) $RequiredScenes.Count $Description
  foreach ($Scene in $RequiredScenes) {
    Assert-True (@($Scenes) -contains $Scene) "$Description contains $Scene"
  }
}

function Assert-UnderDirectory {
  param(
    [string]$PathValue,
    [string]$Parent
  )

  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if (-not $FullPath.StartsWith($FullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside expected directory. path=$FullPath parent=$FullParent"
  }
}

function Invoke-OfficialComparisonExpectFailure {
  param(
    [object[]]$Arguments,
    [string]$Description
  )

  $Command = @((Join-Path $Root "scripts\run_official_comparison.ps1"))
  $Command += $Arguments
  $CommandArgs = @($Command | Select-Object -Skip 1)
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Command[0] @CommandArgs *>&1
    $ExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($ExitCode -eq 0) {
    throw "Expected official comparison failure for $Description."
  }
  return ($Output | ForEach-Object { [string]$_ }) -join "`n"
}

function Invoke-TrustedExperimentExpectFailure {
  param(
    [object[]]$Arguments,
    [string]$Description
  )

  $Command = @((Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1"))
  $Command += $Arguments
  $CommandArgs = @($Command | Select-Object -Skip 1)
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Command[0] @CommandArgs *>&1
    $ExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($ExitCode -eq 0) {
    throw "Expected trusted experiment matrix failure for $Description."
  }
  return ($Output | ForEach-Object { [string]$_ }) -join "`n"
}

function Restore-DryRunManifest {
  param(
    [string]$ManifestPath,
    [string]$BackupPath,
    [bool]$HadManifest
  )

  if ($HadManifest) {
    Copy-Item -LiteralPath $BackupPath -Destination $ManifestPath -Force
  } elseif (Test-Path -LiteralPath $ManifestPath) {
    Remove-Item -LiteralPath $ManifestPath -Force
  }
  if (Test-Path -LiteralPath $BackupPath) {
    Remove-Item -LiteralPath $BackupPath -Force
  }
}

function Get-Experiment {
  param(
    [object]$Manifest,
    [string]$Label
  )
  $Matches = @($Manifest.experiments | Where-Object { $_.label -eq $Label })
  Assert-Count $Matches 1 "trusted experiment entry for $Label"
  return $Matches[0]
}

function Assert-Flags {
  param(
    [object]$Experiment,
    [string[]]$Expected,
    [string]$Description
  )
  $Actual = @($Experiment.flags)
  Assert-Count $Actual $Expected.Count "$Description flag count"
  for ($Index = 0; $Index -lt $Expected.Count; $Index += 1) {
    Assert-Equal $Actual[$Index] $Expected[$Index] "$Description flag[$Index]"
  }
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$HadOfficialManifest = Test-Path -LiteralPath $OfficialManifestPath
$HadTrustedManifest = Test-Path -LiteralPath $TrustedManifestPath
$OriginalOfficialManifestText = if ($HadOfficialManifest) { Get-Content -LiteralPath $OfficialManifestPath -Raw } else { $null }
$OriginalTrustedManifestText = if ($HadTrustedManifest) { Get-Content -LiteralPath $TrustedManifestPath -Raw } else { $null }
if ($HadOfficialManifest) {
  Copy-Item -LiteralPath $OfficialManifestPath -Destination $OfficialBackupPath -Force
}
if ($HadTrustedManifest) {
  Copy-Item -LiteralPath $TrustedManifestPath -Destination $TrustedBackupPath -Force
}

$Completed = $false
try {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
  $PatchHash = Get-ShortSha256 $PatchPath
  $ExpectedForkRevision = "$ChromiumRevision+viewerpatch-$PatchHash"

  $OfficialOutput = & (Join-Path $Root "scripts\run_official_comparison.ps1") `
    -Duration 1 `
    -Warmup 1 `
    -IncludeWebGPU `
    -IncludeAggressiveGpu `
    -AggressiveAngleBackend d3d11 `
    -CaptureTrace `
    -TraceDuration 1 `
    -TraceWarmup 1 `
    -TraceStartDelayMs 1234 `
    -BaselinePackageDir ".\benchmarks\packages\baseline-content-shell" `
    -ForkPackageDir ".\benchmarks\packages\viewer-default" `
    -Precompile `
    -PrerenderFrames 2 `
    -DryRun *>&1
  $OfficialText = ($OfficialOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $OfficialText "-Label\s+fork-viewer-default\b.*-ViewerMode\b.*-ViewerTrustedContent\b" "official fork default suite uses viewer trusted mode"
  Assert-Matches $OfficialText "-Label\s+fork-viewer-aggressive-gpu-d3d11\b.*-ViewerAggressiveGpu\b.*-ViewerForceAngleBackend\s+d3d11\b" "official aggressive suite uses aggressive GPU and ANGLE flags"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-default-webgpu\b.*-ViewerMode\b.*-ViewerTrustedContent\b" "official WebGPU fork suite uses viewer trusted mode"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-aggressive-gpu-d3d11-webgpu\b.*-ViewerAggressiveGpu\b.*-ViewerForceAngleBackend\s+d3d11\b" "official aggressive WebGPU suite uses aggressive GPU and ANGLE flags"
  Assert-Matches $OfficialText "run_trace_capture\.mjs\b.*--viewerMode\b.*--viewerTrustedContent\b" "official fork trace capture uses viewer trusted mode"
  Assert-Matches $OfficialText "run_trace_capture\.mjs\b.*--startDelayMs\s+1234\b" "official trace capture passes explicit start delay"
  Assert-Matches $OfficialText "validate_trace_file\.mjs\b.*--minEvents\s+1\b.*baseline-content-shell-many-draw-calls-webgl2-trace\.json" "official baseline trace validates raw trace immediately after capture"
  Assert-Matches $OfficialText "validate_trace_file\.mjs\b.*--minEvents\s+1\b.*fork-viewer-default-many-draw-calls-webgl2-trace\.json" "official fork trace validates raw trace immediately after capture"
  Assert-Matches $OfficialText "validate_trace_result\.mjs\b.*--expectedBrowser\b.*ReleaseBaseline.*--expectedScene\s+many-draw-calls\b.*--expectedRenderer\s+webgl2\b.*--expectedDuration\s+1\b.*--expectedWarmup\s+1\b.*--expectedStartDelayMs\s+1234\b.*--expectedFlagMetadata\s+viewer_mode=false\b.*--expectedFlagMetadata\s+viewer_block_external_navigation=false\b.*--expectedFlagMetadata\s+viewer_trusted_content=false\b.*--expectedFlagMetadata\s+requested_angle_backend=null\b.*baseline-content-shell-many-draw-calls-webgl2-trace\.result\.json" "official baseline trace sidecar validation checks browser, benchmark, and launch metadata"
  Assert-Matches $OfficialText "validate_trace_result\.mjs\b.*--expectedBrowser\b.*ReleaseViewerDefault.*--expectedScene\s+many-draw-calls\b.*--expectedRenderer\s+webgl2\b.*--expectedDuration\s+1\b.*--expectedWarmup\s+1\b.*--expectedStartDelayMs\s+1234\b.*--expectedFlagMetadata\s+viewer_mode=true\b.*--expectedFlagMetadata\s+viewer_block_external_navigation=true\b.*--expectedFlagMetadata\s+viewer_trusted_content=true\b.*--expectedFlagMetadata\s+requested_angle_backend=null\b.*fork-viewer-default-many-draw-calls-webgl2-trace\.result\.json" "official fork trace sidecar validation checks browser, benchmark, and viewer launch metadata"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-aggressive-gpu-d3d11\b.*--expectedScenes\s+many-draw-calls,instancing,shader-heavy,texture-streaming,postprocessing,large-static,gltf-loader-stress\b.*--expectedChromiumRevision\s+$([regex]::Escape($ChromiumRevision))\b.*--requireForkRevision\b.*--expectedForkRevision\s+$([regex]::Escape($ExpectedForkRevision))" "official aggressive suite validation requires expected scenes, Chromium revision, and fork revision"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--renderer\s+webgpu\b.*--variant\s+fork-viewer-aggressive-gpu-d3d11-webgpu\b.*--expectedFlagMetadata\s+viewer_aggressive_gpu=true\b.*--expectedFlagMetadata\s+requested_angle_backend=d3d11\b" "official aggressive WebGPU suite validation checks aggressive launch metadata"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+baseline-content-shell\b.*--requirePackageSize\b" "official baseline suite validation requires package size when package dir is provided"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-default\b.*--requirePackageSize\b" "official fork default suite validation requires package size when package dir is provided"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-aggressive-gpu-d3d11\b.*--requirePackageSize\b" "official aggressive suite validation requires package size when package dir is provided"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-default\b.*--expectedFlagMetadata\s+viewer_mode=true\b.*--expectedFlagMetadata\s+viewer_block_external_navigation=true\b.*--expectedFlagMetadata\s+viewer_trusted_content=true\b" "official fork default suite validation checks viewer trusted navigation-lock flag metadata"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-aggressive-gpu-d3d11\b.*--expectedFlagMetadata\s+viewer_aggressive_gpu=true\b.*--expectedFlagMetadata\s+viewer_force_angle_backend=d3d11\b.*--expectedFlagMetadata\s+requested_angle_backend=d3d11\b" "official aggressive suite validation checks aggressive flag metadata"
  Assert-Matches $OfficialText "run_smoke_tests\.mjs\b.*--browser\b.*ReleaseViewerDefault.*--viewerMode\b.*--viewerTrustedContent\b.*fork-viewer-default-runtime-smoke\.json" "official fork runtime smoke launches through viewer mode"
  Assert-Matches $OfficialText "run_smoke_tests\.mjs\b.*--browser\b.*ReleaseBaseline.*baseline-content-shell-runtime-smoke\.json.*--require-webgpu\b" "official baseline runtime smoke requires WebGPU when WebGPU suites are requested"
  Assert-Matches $OfficialText "run_smoke_tests\.mjs\b.*--browser\b.*ReleaseViewerDefault.*--viewerMode\b.*--viewerTrustedContent\b.*fork-viewer-default-runtime-smoke\.json.*--require-webgpu\b" "official fork runtime smoke requires WebGPU when WebGPU suites are requested"
  Assert-Matches $OfficialText "validate_smoke_result\.mjs\b.*--type\s+runtime\b.*--expect-browser-mode\b.*--expected-browser\b.*ReleaseBaseline.*baseline-content-shell-runtime-smoke\.json.*--require-webgpu\b" "official baseline runtime smoke validation command requires browser-mode metadata, baseline browser path, and WebGPU smoke"
  Assert-Matches $OfficialText "validate_smoke_result\.mjs\b.*--type\s+runtime\b.*--expect-viewer-mode\b.*--expect-viewer-trusted-content\b.*--expected-browser\b.*ReleaseViewerDefault.*fork-viewer-default-runtime-smoke\.json.*--require-webgpu\b" "official fork runtime smoke validation command requires viewer-mode metadata, fork browser path, and WebGPU smoke"
  Assert-Matches $OfficialText "validate_smoke_result\.mjs\b.*--type\s+navigation\b.*--expected-browser\b.*ReleaseViewerDefault.*fork-viewer-default-navigation-lock\.json" "official HTTP navigation smoke validation command checks fork browser path"
  Assert-Matches $OfficialText "validate_smoke_result\.mjs\b.*--type\s+file-navigation\b.*--expected-browser\b.*ReleaseViewerDefault.*fork-viewer-default-file-navigation-lock\.json" "official file navigation smoke validation command checks fork browser path"
  Assert-Matches $OfficialText "-PackageDir\s+.*benchmarks\\packages\\baseline-content-shell" "official baseline benchmark commands receive package dir"
  Assert-Matches $OfficialText "-PackageDir\s+.*benchmarks\\packages\\viewer-default" "official fork benchmark commands receive package dir"

  $SyntheticInputDir = Join-Path $TempDir "official-package-preflight-inputs"
  New-Item -ItemType Directory -Path $SyntheticInputDir -Force | Out-Null
  foreach ($SyntheticFile in @("baseline-content_shell.exe", "fork-content_shell.exe", "baseline-args.gn", "fork-args.gn")) {
    Set-Content -LiteralPath (Join-Path $SyntheticInputDir $SyntheticFile) -Value "synthetic" -Encoding ASCII
  }
  $MismatchedBaselinePackage = Join-Path $TempDir "mismatched-baseline-package"
  New-Item -ItemType Directory -Path (Join-Path $MismatchedBaselinePackage "viewer") -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $MismatchedBaselinePackage "content_shell.exe") -Value "different-browser" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $MismatchedBaselinePackage "viewer\index.html") -Value "<!doctype html>" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $MismatchedBaselinePackage "run_viewer.ps1") -Value "Write-Host synthetic" -Encoding ASCII
  $EmptyBaselineBrowser = Join-Path $SyntheticInputDir "empty-baseline-content_shell.exe"
  New-Item -ItemType File -Path $EmptyBaselineBrowser -Force | Out-Null
  $EmptyOfficialBrowserText = Invoke-OfficialComparisonExpectFailure @(
    "-BaselineBrowser", $EmptyBaselineBrowser,
    "-ForkBrowser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
    "-BaselineBuildArgs", (Join-Path $SyntheticInputDir "baseline-args.gn"),
    "-ForkBuildArgs", (Join-Path $SyntheticInputDir "fork-args.gn"),
    "-SkipSmoke",
    "-SkipNavigationLock"
  ) "empty baseline browser executable"
  Assert-Matches $EmptyOfficialBrowserText "Baseline browser is empty" "official input preflight rejects empty baseline browser executable"
  if ($EmptyOfficialBrowserText -match "run_full_suite\.ps1|run_smoke_tests\.mjs|validate_benchmark_suite\.mjs") {
    throw "Official comparison input preflight ran benchmark work before rejecting the empty baseline browser executable."
  }

  $MismatchedOfficialPackageText = Invoke-OfficialComparisonExpectFailure @(
    "-BaselineBrowser", (Join-Path $SyntheticInputDir "baseline-content_shell.exe"),
    "-ForkBrowser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
    "-BaselineBuildArgs", (Join-Path $SyntheticInputDir "baseline-args.gn"),
    "-ForkBuildArgs", (Join-Path $SyntheticInputDir "fork-args.gn"),
    "-BaselinePackageDir", $MismatchedBaselinePackage,
    "-SkipSmoke",
    "-SkipNavigationLock"
  ) "mismatched baseline package executable"
  Assert-Matches $MismatchedOfficialPackageText "Baseline package directory executable does not match expected browser" "official package preflight rejects package executable hash mismatch"
  if ($MismatchedOfficialPackageText -match "run_full_suite\.ps1|run_smoke_tests\.mjs|validate_benchmark_suite\.mjs") {
    throw "Official comparison package preflight ran benchmark work before rejecting the mismatched package executable."
  }

  $MissingPackageText = Invoke-OfficialComparisonExpectFailure @(
    "-BaselineBrowser", (Join-Path $SyntheticInputDir "baseline-content_shell.exe"),
    "-ForkBrowser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
    "-BaselineBuildArgs", (Join-Path $SyntheticInputDir "baseline-args.gn"),
    "-ForkBuildArgs", (Join-Path $SyntheticInputDir "fork-args.gn"),
    "-BaselinePackageDir", (Join-Path $TempDir "missing-baseline-package"),
    "-ForkPackageDir", (Join-Path $TempDir "missing-fork-package"),
    "-SkipSmoke",
    "-SkipNavigationLock"
  ) "missing supplied package directories"
  Assert-Matches $MissingPackageText "Baseline package directory not found" "official package preflight rejects missing baseline package directory"
  if ($MissingPackageText -match "run_full_suite\.ps1|run_smoke_tests\.mjs|validate_benchmark_suite\.mjs") {
    throw "Official comparison package preflight ran benchmark work before rejecting the missing package directory."
  }

  Assert-True (Test-Path $OfficialManifestPath) "official dry-run manifest exists"
  $Official = Get-Content -LiteralPath $OfficialManifestPath -Raw | ConvertFrom-Json

  Assert-True ([bool]$Official.dry_run) "official dry_run is true"
Assert-Equal $Official.phase "planned" "official phase"
Assert-Equal $Official.chromium_revision $ChromiumRevision "official Chromium revision"
Assert-Equal $Official.fork_revision $ExpectedForkRevision "official fork revision"
Assert-Scenes @($Official.scenes) "official scene list"
Assert-Equal $Official.options.include_webgpu $true "official include_webgpu"
Assert-Equal $Official.options.include_aggressive_gpu $true "official include_aggressive_gpu"
Assert-Equal $Official.options.aggressive_angle_backend "d3d11" "official aggressive ANGLE backend"
Assert-Equal $Official.options.capture_trace $true "official capture_trace"
Assert-Equal $Official.options.trace_start_delay_ms 1234 "official trace start delay"
Assert-Equal $Official.options.precompile $true "official precompile"
Assert-Equal $Official.options.prerender_frames 2 "official prerender_frames"
Assert-True ([bool]$Official.package_dirs.baseline) "official baseline package dir path exists in manifest"
Assert-True ([bool]$Official.package_dirs.fork) "official fork package dir path exists in manifest"
Assert-True ([string]$Official.package_dirs.baseline -match "benchmarks\\packages\\baseline-content-shell") "official baseline package dir points to baseline package"
Assert-True ([string]$Official.package_dirs.fork -match "benchmarks\\packages\\viewer-default") "official fork package dir points to fork package"
Assert-Count @($Official.result_files.baseline_webgl2) $RequiredScenes.Count "official baseline WebGL2 result files"
Assert-Count @($Official.result_files.fork_default_webgl2) $RequiredScenes.Count "official fork WebGL2 result files"
Assert-Count @($Official.result_files.aggressive_webgl2) $RequiredScenes.Count "official aggressive WebGL2 result files"
Assert-Count @($Official.result_files.baseline_webgpu) $RequiredScenes.Count "official baseline WebGPU result files"
Assert-Count @($Official.result_files.fork_default_webgpu) $RequiredScenes.Count "official fork WebGPU result files"
Assert-Count @($Official.result_files.aggressive_webgpu) $RequiredScenes.Count "official aggressive WebGPU result files"
Assert-Count @($Official.result_files.runtime_smoke) 2 "official runtime smoke files"
Assert-Count @($Official.result_files.navigation_lock) 2 "official navigation lock files"
Assert-True ([bool]$Official.report_files.official_webgl2_comparison) "official WebGL2 report path exists in manifest"
Assert-True ([bool]$Official.report_files.official_webgpu_comparison) "official WebGPU report path exists in manifest"
Assert-True ([bool]$Official.trace_files.baseline) "official baseline trace path exists in manifest"
Assert-True ([bool]$Official.trace_files.fork) "official fork trace path exists in manifest"
Assert-True ([bool]$Official.trace_result_files.baseline) "official baseline trace result sidecar path exists in manifest"
Assert-True ([bool]$Official.trace_result_files.fork) "official fork trace result sidecar path exists in manifest"
Assert-Equal $Official.suite_validation.expected_fork_revision $ExpectedForkRevision "official suite expected fork revision"
Assert-Equal $Official.suite_validation.expected_chromium_revision $ChromiumRevision "official suite expected Chromium revision"
Assert-Equal $Official.suite_validation.exact_scene_output_files $true "official exact scene output validation"
Assert-Equal $Official.suite_validation.reject_software_rendering $true "official software-renderer rejection validation"
Assert-Equal $Official.suite_validation.require_gpu_metadata $true "official GPU metadata validation"
Assert-Equal $Official.suite_validation.require_webgpu_runtime_smoke $true "official WebGPU runtime smoke validation"
Assert-True (@($Official.suite_validation.required_browser_flags) -contains "--disable-software-rasterizer") "official required browser launch flag validation"
Assert-Equal $Official.suite_validation.expected_measured_seconds 1 "official expected measured seconds validation"
Assert-Equal $Official.suite_validation.expected_warmup_seconds 1 "official expected warmup seconds validation"
Assert-True (@($Official.suite_validation.expected_flag_metadata.fork_default) -contains "viewer_block_external_navigation=true") "official fork default navigation-lock expected flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.fork_default) -contains "viewer_trusted_content=true") "official fork default expected flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive) -contains "viewer_force_angle_backend=d3d11") "official aggressive expected flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive) -contains "requested_angle_backend=d3d11") "official aggressive requested ANGLE expected flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_force_angle_backend=d3d11") "official aggressive WebGPU expected ANGLE flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "requested_angle_backend=d3d11") "official aggressive WebGPU requested ANGLE expected flag metadata"
Assert-Equal $Official.artifact_metadata.inputs.viewer_patch.exists $true "official viewer patch metadata exists"
Assert-True ([bool]$Official.artifact_metadata.inputs.viewer_patch.sha256) "official viewer patch metadata hash exists"
Assert-True ([bool]$Official.artifact_metadata.inputs.baseline_package.path) "official baseline package metadata path exists"
Assert-True ([bool]$Official.artifact_metadata.inputs.fork_package.path) "official fork package metadata path exists"
Assert-Count @($Official.artifact_metadata.results.baseline_webgl2) $RequiredScenes.Count "official baseline WebGL2 metadata"
Assert-Count @($Official.artifact_metadata.results.fork_default_webgl2) $RequiredScenes.Count "official fork WebGL2 metadata"
Assert-Count @($Official.artifact_metadata.results.aggressive_webgpu) $RequiredScenes.Count "official aggressive WebGPU metadata"
Assert-True ($null -ne $Official.artifact_metadata.traces.baseline_result) "official baseline trace sidecar metadata exists"
Assert-True ($null -ne $Official.artifact_metadata.traces.fork_result) "official fork trace sidecar metadata exists"

$TrustedOutput = & (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1") `
  -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
  -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
  -PackageDir ".\benchmarks\packages\viewer-default" `
  -ForkRevision $ExpectedForkRevision `
  -Renderer webgl2 `
  -Duration 1 `
  -Warmup 1 `
  -IncludeDefault `
  -IncludeAggressiveGpu `
  -IncludeInProcessGpu `
  -IncludeSingleProcess `
  -AngleBackend d3d11 `
  -IncludeReservedNoopGates `
  -Precompile `
  -PrerenderFrames 2 `
  -DryRun *>&1
$TrustedText = ($TrustedOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerAggressiveGpu\b" "trusted aggressive experiment command uses trusted and aggressive flags"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerInProcessGpu\b" "trusted in-process GPU experiment command uses trusted and in-process flags"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerSingleProcess\b" "trusted single-process experiment command uses trusted and single-process flags"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerForceAngleBackend\s+d3d11\b" "trusted ANGLE experiment command uses trusted and ANGLE flags"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerRelaxedWebglValidation\b" "trusted relaxed WebGL validation command uses trusted gate"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerDisableUnneededBlinkFeatures\b" "trusted reserved Blink command uses trusted gate"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerDirectGpuPresentation\b" "trusted reserved direct presentation command uses trusted gate"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--requirePackageSize\b" "trusted suite validation requires package size when package dir is provided"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--expectedChromiumRevision\s+$([regex]::Escape($ChromiumRevision))\b" "trusted suite validation requires expected Chromium revision"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--expectedFlagMetadata\s+viewer_block_external_navigation=true\b" "trusted default suite validation checks navigation-lock flag metadata"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-in-process-gpu\b.*--expectedFlagMetadata\s+viewer_in_process_gpu=true\b" "trusted in-process suite validation checks in-process flag metadata"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-angle-d3d11\b.*--expectedFlagMetadata\s+viewer_force_angle_backend=d3d11\b.*--expectedFlagMetadata\s+requested_angle_backend=d3d11\b" "trusted ANGLE suite validation checks ANGLE flag metadata"

$MissingTrustedPackageText = Invoke-TrustedExperimentExpectFailure @(
  "-Browser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
  "-BuildArgs", (Join-Path $SyntheticInputDir "fork-args.gn"),
  "-PackageDir", (Join-Path $TempDir "missing-trusted-package"),
  "-ForkRevision", $ExpectedForkRevision,
  "-Renderer", "webgl2",
  "-Duration", "1",
  "-Warmup", "1",
  "-IncludeDefault"
) "missing supplied trusted package directory"
Assert-Matches $MissingTrustedPackageText "Trusted package directory not found" "trusted package preflight rejects missing package directory"
if ($MissingTrustedPackageText -match "run_benchmark\.mjs|validate_benchmark_suite\.mjs|summarize_results\.mjs") {
  throw "Trusted experiment package preflight ran benchmark work before rejecting the missing package directory."
}

$MismatchedTrustedPackage = Join-Path $TempDir "mismatched-trusted-package"
New-Item -ItemType Directory -Path (Join-Path $MismatchedTrustedPackage "viewer") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $MismatchedTrustedPackage "content_shell.exe") -Value "different-browser" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $MismatchedTrustedPackage "viewer\index.html") -Value "<!doctype html>" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $MismatchedTrustedPackage "run_viewer.ps1") -Value "Write-Host synthetic" -Encoding ASCII
$MismatchedTrustedPackageText = Invoke-TrustedExperimentExpectFailure @(
  "-Browser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
  "-BuildArgs", (Join-Path $SyntheticInputDir "fork-args.gn"),
  "-PackageDir", $MismatchedTrustedPackage,
  "-ForkRevision", $ExpectedForkRevision,
  "-Renderer", "webgl2",
  "-Duration", "1",
  "-Warmup", "1",
  "-IncludeDefault"
) "mismatched trusted package executable"
Assert-Matches $MismatchedTrustedPackageText "Trusted package directory executable does not match expected browser" "trusted package preflight rejects package executable hash mismatch"
if ($MismatchedTrustedPackageText -match "run_benchmark\.mjs|validate_benchmark_suite\.mjs|summarize_results\.mjs") {
  throw "Trusted experiment package preflight ran benchmark work before rejecting the mismatched package executable."
}

$EmptyTrustedBuildArgs = Join-Path $SyntheticInputDir "empty-trusted-args.gn"
New-Item -ItemType File -Path $EmptyTrustedBuildArgs -Force | Out-Null
$EmptyTrustedBuildArgsText = Invoke-TrustedExperimentExpectFailure @(
  "-Browser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
  "-BuildArgs", $EmptyTrustedBuildArgs,
  "-ForkRevision", $ExpectedForkRevision,
  "-Renderer", "webgl2",
  "-Duration", "1",
  "-Warmup", "1",
  "-IncludeDefault"
) "empty trusted build args"
Assert-Matches $EmptyTrustedBuildArgsText "Build args is empty" "trusted input preflight rejects empty build args"
if ($EmptyTrustedBuildArgsText -match "run_benchmark\.mjs|validate_benchmark_suite\.mjs|summarize_results\.mjs") {
  throw "Trusted experiment input preflight ran benchmark work before rejecting the empty build args file."
}

$TrustedManifestPath = Join-Path $Root "benchmarks\reports\trusted-experiment-matrix-manifest.dry-run.json"
Assert-True (Test-Path $TrustedManifestPath) "trusted dry-run manifest exists"
$Trusted = Get-Content -LiteralPath $TrustedManifestPath -Raw | ConvertFrom-Json

Assert-True ([bool]$Trusted.dry_run) "trusted dry_run is true"
Assert-Equal $Trusted.phase "planned" "trusted phase"
Assert-Equal $Trusted.chromium_revision $ChromiumRevision "trusted Chromium revision"
Assert-Equal $Trusted.fork_revision $ExpectedForkRevision "trusted fork revision"
Assert-Equal $Trusted.renderer "webgl2" "trusted renderer"
Assert-Scenes @($Trusted.scenes) "trusted scene list"
Assert-Equal $Trusted.options.precompile $true "trusted precompile"
Assert-Equal $Trusted.options.prerender_frames 2 "trusted prerender_frames"
Assert-Equal $Trusted.suite_validation.expected_fork_revision $ExpectedForkRevision "trusted suite expected fork revision"
Assert-Equal $Trusted.suite_validation.expected_chromium_revision $ChromiumRevision "trusted suite expected Chromium revision"
Assert-Equal $Trusted.suite_validation.exact_scene_output_files $true "trusted exact scene output validation"
Assert-Equal $Trusted.suite_validation.reject_software_rendering $true "trusted software-renderer rejection validation"
Assert-Equal $Trusted.suite_validation.require_gpu_metadata $true "trusted GPU metadata validation"
Assert-True (@($Trusted.suite_validation.required_browser_flags) -contains "--disable-software-rasterizer") "trusted required browser launch flag validation"
Assert-Equal $Trusted.suite_validation.expected_measured_seconds 1 "trusted expected measured seconds validation"
Assert-Equal $Trusted.suite_validation.expected_warmup_seconds 1 "trusted expected warmup seconds validation"
Assert-Equal $Trusted.suite_validation.expected_flag_metadata $true "trusted expected flag metadata validation"

$ExpectedExperiments = @(
  "fork-viewer-exp-default",
  "fork-viewer-exp-aggressive-gpu",
  "fork-viewer-exp-in-process-gpu",
  "fork-viewer-exp-single-process",
  "fork-viewer-exp-angle-d3d11",
  "fork-viewer-exp-relaxed-webgl-validation-gate",
  "fork-viewer-exp-disable-unneeded-blink-features-gate",
  "fork-viewer-exp-direct-gpu-presentation-gate"
)
Assert-Count @($Trusted.experiments) $ExpectedExperiments.Count "trusted experiment count"
foreach ($Label in $ExpectedExperiments) {
  Assert-True (@($Trusted.experiments | ForEach-Object { $_.label }) -contains $Label) "trusted experiment list contains $Label"
}
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-default") @() "default experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-aggressive-gpu") @("--viewerAggressiveGpu") "aggressive GPU experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-in-process-gpu") @("--viewerInProcessGpu") "in-process GPU experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-single-process") @("--viewerSingleProcess") "single-process experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11") @("--viewerForceAngleBackend", "d3d11") "ANGLE d3d11 experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-relaxed-webgl-validation-gate") @("--viewerRelaxedWebglValidation") "relaxed WebGL validation pass-through command decoder experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-disable-unneeded-blink-features-gate") @("--viewerDisableUnneededBlinkFeatures") "reserved Blink feature gate experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-direct-gpu-presentation-gate") @("--viewerDirectGpuPresentation") "reserved direct GPU presentation gate experiment"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-default").expected_flag_metadata) -contains "viewer_block_external_navigation=true") "default experiment navigation-lock expected flag metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-in-process-gpu").expected_flag_metadata) -contains "viewer_in_process_gpu=true") "in-process experiment expected flag metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11").expected_flag_metadata) -contains "viewer_force_angle_backend=d3d11") "ANGLE experiment expected flag metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11").expected_flag_metadata) -contains "requested_angle_backend=d3d11") "ANGLE experiment requested backend expected flag metadata"

$ExpectedTrustedResults = $ExpectedExperiments.Count * $RequiredScenes.Count
Assert-Count @($Trusted.result_files.all) $ExpectedTrustedResults "trusted result files"
Assert-Count @($Trusted.artifact_metadata.results.all) $ExpectedTrustedResults "trusted result metadata"
Assert-Equal $Trusted.artifact_metadata.inputs.viewer_patch.exists $true "trusted viewer patch metadata exists"
Assert-True ([bool]$Trusted.artifact_metadata.inputs.viewer_patch.sha256) "trusted viewer patch metadata hash exists"
Assert-True ([bool]$Trusted.report_files.summary) "trusted summary report path exists in manifest"
Assert-True ([bool]$Trusted.report_files.comparison) "trusted comparison report path exists in manifest"

if ($OfficialText -match "exited with code" -or
    $TrustedText -match "exited with code") {
  throw "Dry-run command output unexpectedly contained a command failure."
}

$Completed = $true
} finally {
  Restore-DryRunManifest $OfficialManifestPath $OfficialBackupPath $HadOfficialManifest
  Restore-DryRunManifest $TrustedManifestPath $TrustedBackupPath $HadTrustedManifest
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

if ($Completed) {
  Assert-Equal (Test-Path -LiteralPath $OfficialManifestPath) $HadOfficialManifest "official dry-run manifest restored existence"
  Assert-Equal (Test-Path -LiteralPath $TrustedManifestPath) $HadTrustedManifest "trusted dry-run manifest restored existence"
  if ($HadOfficialManifest) {
    Assert-Equal (Get-Content -LiteralPath $OfficialManifestPath -Raw) $OriginalOfficialManifestText "official dry-run manifest restored contents"
  }
  if ($HadTrustedManifest) {
    Assert-Equal (Get-Content -LiteralPath $TrustedManifestPath -Raw) $OriginalTrustedManifestText "trusted dry-run manifest restored contents"
  }
  Assert-True (-not (Test-Path -LiteralPath $TempDir)) "temporary dry-run manifest test directory was removed"
}

Write-Host "Official and trusted dry-run manifests are structurally valid, official/trusted input and package preflights reject bad supplied artifacts, and report artifacts are restored after the test."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\dry-run-manifest-test"
$OfficialManifestPath = Join-Path $Root "benchmarks\reports\official-comparison-manifest.dry-run.json"
$TrustedManifestPath = Join-Path $Root "benchmarks\reports\trusted-experiment-matrix-manifest.dry-run.json"
$TrustedWebGlManifestPath = Join-Path $Root "benchmarks\reports\trusted-experiment-matrix-webgl2-manifest.dry-run.json"
$TrustedWebGpuManifestPath = Join-Path $Root "benchmarks\reports\trusted-experiment-matrix-webgpu-manifest.dry-run.json"
$OfficialBackupPath = Join-Path $TempDir "official-comparison-manifest.dry-run.backup.json"
$TrustedBackupPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.dry-run.backup.json"
$TrustedWebGlBackupPath = Join-Path $TempDir "trusted-experiment-matrix-webgl2-manifest.dry-run.backup.json"
$TrustedWebGpuBackupPath = Join-Path $TempDir "trusted-experiment-matrix-webgpu-manifest.dry-run.backup.json"
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

function Get-Sha256IfExists {
  param([string]$PathValue)
  if (-not (Test-Path $PathValue)) {
    return ""
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
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

function Assert-BrowserFlags {
  param(
    [object]$Experiment,
    [string[]]$Expected,
    [string]$Description
  )
  $Actual = @($Experiment.browser_flags)
  Assert-Count $Actual $Expected.Count "$Description browser flag count"
  for ($Index = 0; $Index -lt $Expected.Count; $Index += 1) {
    Assert-Equal $Actual[$Index] $Expected[$Index] "$Description browser flag[$Index]"
    Assert-True (@($Experiment.required_browser_flags) -contains $Expected[$Index]) "$Description required browser flags include $($Expected[$Index])"
  }
  Assert-True (@($Experiment.required_browser_flags) -contains "--disable-software-rasterizer") "$Description required browser flags include hardware-GPU fail-closed flag"
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$HadOfficialManifest = Test-Path -LiteralPath $OfficialManifestPath
$HadTrustedManifest = Test-Path -LiteralPath $TrustedManifestPath
$HadTrustedWebGlManifest = Test-Path -LiteralPath $TrustedWebGlManifestPath
$HadTrustedWebGpuManifest = Test-Path -LiteralPath $TrustedWebGpuManifestPath
$OriginalOfficialManifestText = if ($HadOfficialManifest) { Get-Content -LiteralPath $OfficialManifestPath -Raw } else { $null }
$OriginalTrustedManifestText = if ($HadTrustedManifest) { Get-Content -LiteralPath $TrustedManifestPath -Raw } else { $null }
$OriginalTrustedWebGlManifestText = if ($HadTrustedWebGlManifest) { Get-Content -LiteralPath $TrustedWebGlManifestPath -Raw } else { $null }
$OriginalTrustedWebGpuManifestText = if ($HadTrustedWebGpuManifest) { Get-Content -LiteralPath $TrustedWebGpuManifestPath -Raw } else { $null }
if ($HadOfficialManifest) {
  Copy-Item -LiteralPath $OfficialManifestPath -Destination $OfficialBackupPath -Force
}
if ($HadTrustedManifest) {
  Copy-Item -LiteralPath $TrustedManifestPath -Destination $TrustedBackupPath -Force
}
if ($HadTrustedWebGlManifest) {
  Copy-Item -LiteralPath $TrustedWebGlManifestPath -Destination $TrustedWebGlBackupPath -Force
}
if ($HadTrustedWebGpuManifest) {
  Copy-Item -LiteralPath $TrustedWebGpuManifestPath -Destination $TrustedWebGpuBackupPath -Force
}

$Completed = $false
try {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $ExpectedForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ChromiumRevision -Root $Root
  $ExpectedBaselineBuildArgsHash = Get-Sha256IfExists (Join-Path $Root "src\out\ReleaseBaseline\args.gn")
  $ExpectedForkBuildArgsHash = Get-Sha256IfExists (Join-Path $Root "src\out\ReleaseViewerDefault\args.gn")

  $OfficialOutput = & (Join-Path $Root "scripts\run_official_comparison.ps1") `
    -Duration 1 `
    -Warmup 1 `
    -IncludeWebGPU `
    -IncludeAggressiveGpu `
    -AggressiveAngleBackend d3d11 `
    -AggressiveWebGpuSourceFastPath `
    -AggressiveWebGpuUploadFastPath `
    -CaptureTrace `
    -TraceDuration 1 `
    -TraceWarmup 1 `
    -TraceStartDelayMs 1234 `
    -BaselinePackageDir ".\benchmarks\packages\baseline-content-shell" `
    -ForkPackageDir ".\benchmarks\packages\viewer-default" `
    -Precompile `
    -PrerenderFrames 2 `
    -WebGpuProfileCacheKey "dryrun-webgpu-cache" `
    -ProfileCacheRoot ".\benchmarks\tmp\official-profile-cache-dry-run" `
    -PrimeWebGpuProfileCache `
    -DryRun *>&1
  $OfficialText = ($OfficialOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $OfficialText "-Label\s+fork-viewer-default\b.*-ViewerMode\b.*-ViewerTrustedContent\b" "official fork default suite uses viewer trusted mode"
  Assert-Matches $OfficialText "-Label\s+fork-viewer-aggressive-gpu-d3d11\b.*-ViewerAggressiveGpu\b.*-ViewerForceAngleBackend\s+d3d11\b" "official aggressive suite uses aggressive GPU and ANGLE flags"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-default-webgpu\b.*-ViewerMode\b.*-ViewerTrustedContent\b" "official WebGPU fork suite uses viewer trusted mode"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-aggressive-gpu-webgpu\b.*-ViewerAggressiveGpu\b" "official aggressive WebGPU suite uses aggressive GPU"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-aggressive-gpu-webgpu\b.*-ViewerDeferWebgpuPipelineFlush\b.*-ViewerCacheWebgpuBindGroupLayouts\b.*-ViewerSkipWebgpuCommandLabels\b.*-ViewerSkipWebgpuResourceLabels\b.*-ViewerSkipWebgpuShaderSourceNullCheck\b.*-ViewerSkipWebgpuShaderMemoryAccounting\b.*-ViewerSkipWebgpuRedundantPipelineSets\b.*-ViewerSkipWebgpuRedundantBindGroupSets\b.*-ViewerSkipWebgpuRedundantBufferSets\b.*-ViewerSkipWebgpuRedundantRenderStateSets\b" "official aggressive WebGPU source fast-path suite forwards all source-backed WebGPU flags"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-aggressive-gpu-webgpu\b.*-ViewerSkipWebgpuCopyExternalImageColorConversion\b.*-ViewerRejectWebgpuCpuTextureFallback\b" "official aggressive WebGPU upload fast-path suite forwards CPU-fallback-rejected upload flags"
  Assert-True ($OfficialText -notmatch "-Renderer\s+webgpu\b[^\r\n]*-ViewerForceAngleBackend\s+d3d11\b") "official aggressive WebGPU suite does not inherit the WebGL2 ANGLE backend flag"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+baseline-content-shell-webgpu\b.*-ProfileCacheKey\s+dryrun-webgpu-cache\b.*-UserDataDirRoot\b.*official-profile-cache-dry-run" "official WebGPU baseline suite receives matched profile-cache args"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-default-webgpu\b.*-ProfileCacheKey\s+dryrun-webgpu-cache\b.*-UserDataDirRoot\b.*official-profile-cache-dry-run" "official WebGPU fork suite receives matched profile-cache args"
  Assert-Matches $OfficialText "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-aggressive-gpu-webgpu\b.*-ProfileCacheKey\s+dryrun-webgpu-cache\b.*-UserDataDirRoot\b.*official-profile-cache-dry-run" "official aggressive WebGPU suite receives matched profile-cache args"
  Assert-Matches $OfficialText "Priming WebGPU profile cache for baseline-content-shell-webgpu" "official WebGPU baseline profile-cache priming pass is explicit"
  Assert-Matches $OfficialText "Priming WebGPU profile cache for fork-viewer-default-webgpu" "official WebGPU fork profile-cache priming pass is explicit"
  Assert-Matches $OfficialText "Priming WebGPU profile cache for fork-viewer-aggressive-gpu-webgpu" "official aggressive WebGPU profile-cache priming pass is explicit"
  Assert-True ([regex]::Matches($OfficialText, "-Renderer\s+webgpu\b.*-Label\s+baseline-content-shell-webgpu\b.*-ProfileCacheKey\s+dryrun-webgpu-cache").Count -ge 2) "official WebGPU baseline suite runs once to prime and once to measure"
  Assert-True ([regex]::Matches($OfficialText, "-Renderer\s+webgpu\b.*-Label\s+fork-viewer-default-webgpu\b.*-ProfileCacheKey\s+dryrun-webgpu-cache").Count -ge 2) "official WebGPU fork suite runs once to prime and once to measure"
  Assert-Matches $OfficialText "run_trace_capture\.mjs\b.*--viewerMode\b.*--viewerTrustedContent\b" "official fork trace capture uses viewer trusted mode"
  Assert-Matches $OfficialText "run_trace_capture\.mjs\b.*--startDelayMs\s+1234\b" "official trace capture passes explicit start delay"
  Assert-Matches $OfficialText "run_trace_capture\.mjs\b.*--complexity\s+2\b" "official trace capture uses the same stress complexity"
  Assert-Matches $OfficialText "validate_trace_file\.mjs\b.*--minEvents\s+1\b.*baseline-content-shell-many-draw-calls-webgl2-trace\.json" "official baseline trace validates raw trace immediately after capture"
  Assert-Matches $OfficialText "validate_trace_file\.mjs\b.*--minEvents\s+1\b.*fork-viewer-default-many-draw-calls-webgl2-trace\.json" "official fork trace validates raw trace immediately after capture"
  Assert-Matches $OfficialText "validate_trace_result\.mjs\b.*--expectedBrowser\b.*ReleaseBaseline.*--expectedScene\s+many-draw-calls\b.*--expectedRenderer\s+webgl2\b.*--expectedDuration\s+1\b.*--expectedWarmup\s+1\b.*--expectedStartDelayMs\s+1234\b.*--expectedFlagMetadata\s+viewer_mode=false\b.*--expectedFlagMetadata\s+viewer_block_external_navigation=false\b.*--expectedFlagMetadata\s+viewer_trusted_content=false\b.*--expectedFlagMetadata\s+requested_angle_backend=null\b.*baseline-content-shell-many-draw-calls-webgl2-trace\.result\.json" "official baseline trace sidecar validation checks browser, benchmark, and launch metadata"
  Assert-Matches $OfficialText "validate_trace_result\.mjs\b.*--expectedBrowser\b.*ReleaseViewerDefault.*--expectedScene\s+many-draw-calls\b.*--expectedRenderer\s+webgl2\b.*--expectedDuration\s+1\b.*--expectedWarmup\s+1\b.*--expectedStartDelayMs\s+1234\b.*--expectedFlagMetadata\s+viewer_mode=true\b.*--expectedFlagMetadata\s+viewer_block_external_navigation=true\b.*--expectedFlagMetadata\s+viewer_trusted_content=true\b.*--expectedFlagMetadata\s+requested_angle_backend=null\b.*fork-viewer-default-many-draw-calls-webgl2-trace\.result\.json" "official fork trace sidecar validation checks browser, benchmark, and viewer launch metadata"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-aggressive-gpu-d3d11\b.*--expectedScenes\s+many-draw-calls,instancing,shader-heavy,texture-streaming,postprocessing,large-static,gltf-loader-stress\b.*--expectedChromiumRevision\s+$([regex]::Escape($ChromiumRevision))\b.*--requireForkRevision\b.*--expectedForkRevision\s+$([regex]::Escape($ExpectedForkRevision))" "official aggressive suite validation requires expected scenes, Chromium revision, and fork revision"
  Assert-Matches $OfficialText "run_full_suite\.ps1\b.*-Renderer\s+webgl2\b.*-Complexity\s+2\b.*-Label\s+baseline-content-shell\b" "official baseline WebGL2 suite runs at stress complexity"
  Assert-Matches $OfficialText "run_full_suite\.ps1\b.*-Renderer\s+webgpu\b.*-Complexity\s+2\b.*-Label\s+baseline-content-shell-webgpu\b" "official baseline WebGPU suite runs at stress complexity"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-default\b.*--expectedComplexity\s+2\b" "official fork suite validation checks stress complexity"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--renderer\s+webgpu\b.*--variant\s+fork-viewer-aggressive-gpu-webgpu\b.*--expectedFlagMetadata\s+viewer_aggressive_gpu=true\b.*--expectedFlagMetadata\s+requested_angle_backend=null\b" "official aggressive WebGPU suite validation checks aggressive backend-neutral launch metadata"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--renderer\s+webgpu\b.*--variant\s+fork-viewer-aggressive-gpu-webgpu\b.*--expectedFlagMetadata\s+viewer_defer_webgpu_pipeline_flush=true\b.*--expectedFlagMetadata\s+viewer_cache_webgpu_bind_group_layouts=true\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_command_labels=true\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_resource_labels=true\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_shader_source_null_check=true\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_shader_memory_accounting=true\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_redundant_pipeline_sets=true\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_redundant_bind_group_sets=true\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_redundant_buffer_sets=true\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_redundant_render_state_sets=true\b" "official aggressive WebGPU suite validation checks all source fast-path metadata"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--renderer\s+webgpu\b.*--variant\s+fork-viewer-aggressive-gpu-webgpu\b.*--expectedFlagMetadata\s+viewer_skip_webgpu_copy_external_image_color_conversion=true\b.*--expectedFlagMetadata\s+viewer_reject_webgpu_cpu_texture_fallback=true\b" "official aggressive WebGPU suite validation checks upload fast-path metadata"
  Assert-True ($OfficialText -notmatch "validate_benchmark_suite\.mjs\b[^\r\n]*--renderer\s+webgpu\b[^\r\n]*--variant\s+fork-viewer-aggressive-gpu-webgpu\b[^\r\n]*--expectedFlagMetadata\s+requested_angle_backend=d3d11\b") "official aggressive WebGPU suite validation does not expect ANGLE metadata"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+baseline-content-shell\b.*--requirePackageSize\b" "official baseline suite validation requires package size when package dir is provided"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-default\b.*--requirePackageSize\b" "official fork default suite validation requires package size when package dir is provided"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-aggressive-gpu-d3d11\b.*--requirePackageSize\b" "official aggressive suite validation requires package size when package dir is provided"
  Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+baseline-content-shell\b.*--requireFrameTimes\b" "official suite validation requires raw frame-time samples"
  if ($ExpectedBaselineBuildArgsHash) {
    Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+baseline-content-shell\b.*--expectedBuildArgsHash\s+$ExpectedBaselineBuildArgsHash\b" "official baseline suite validation binds result metadata to baseline GN args hash"
  }
  if ($ExpectedForkBuildArgsHash) {
    Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-default\b.*--expectedBuildArgsHash\s+$ExpectedForkBuildArgsHash\b" "official fork suite validation binds result metadata to fork GN args hash"
    Assert-Matches $OfficialText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-aggressive-gpu-d3d11\b.*--expectedBuildArgsHash\s+$ExpectedForkBuildArgsHash\b" "official aggressive suite validation binds result metadata to fork GN args hash"
  }
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

  $PrimeWithoutCacheKeyText = Invoke-OfficialComparisonExpectFailure @(
    "-BaselineBrowser", (Join-Path $SyntheticInputDir "baseline-content_shell.exe"),
    "-ForkBrowser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
    "-BaselineBuildArgs", (Join-Path $SyntheticInputDir "baseline-args.gn"),
    "-ForkBuildArgs", (Join-Path $SyntheticInputDir "fork-args.gn"),
    "-IncludeWebGPU",
    "-PrimeWebGpuProfileCache",
    "-SkipSmoke",
    "-SkipNavigationLock"
  ) "WebGPU profile-cache priming without cache key"
  Assert-Matches $PrimeWithoutCacheKeyText "PrimeWebGpuProfileCache requires -WebGpuProfileCacheKey" "official preflight rejects profile-cache priming without cache key"
  if ($PrimeWithoutCacheKeyText -match "run_full_suite\.ps1|run_smoke_tests\.mjs|validate_benchmark_suite\.mjs") {
    throw "Official comparison preflight ran benchmark work before rejecting profile-cache priming without a key."
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
Assert-Equal $Official.options.complexity 2 "official stress complexity"
Assert-Equal $Official.options.webgpu_profile_cache_key "dryrun-webgpu-cache" "official WebGPU profile-cache key"
Assert-Equal $Official.options.webgpu_profile_cache_mode "explicit-reuse" "official WebGPU profile-cache mode"
Assert-True ([string]$Official.options.profile_cache_root -match "official-profile-cache-dry-run") "official profile-cache root"
Assert-Equal $Official.options.prime_webgpu_profile_cache $true "official WebGPU profile-cache priming option"
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
Assert-Equal $Official.suite_validation.expected_baseline_build_args_hash $ExpectedBaselineBuildArgsHash "official suite expected baseline GN args hash"
Assert-Equal $Official.suite_validation.expected_fork_build_args_hash $ExpectedForkBuildArgsHash "official suite expected fork GN args hash"
Assert-Equal $Official.suite_validation.exact_scene_output_files $true "official exact scene output validation"
Assert-Equal $Official.suite_validation.reject_software_rendering $true "official software-renderer rejection validation"
Assert-Equal $Official.suite_validation.reject_gpu_instability $true "official GPU-instability rejection validation"
Assert-Equal $Official.suite_validation.require_gpu_metadata $true "official GPU metadata validation"
Assert-Equal $Official.suite_validation.require_frame_times $true "official raw frame-time sample validation"
Assert-Equal $Official.suite_validation.require_webgpu_runtime_smoke $true "official WebGPU runtime smoke validation"
Assert-True (@($Official.suite_validation.required_browser_flags) -contains "--disable-software-rasterizer") "official required browser launch flag validation"
Assert-Equal $Official.suite_validation.expected_measured_seconds 1 "official expected measured seconds validation"
Assert-Equal $Official.suite_validation.expected_warmup_seconds 1 "official expected warmup seconds validation"
Assert-Equal $Official.suite_validation.expected_complexity 2 "official expected complexity validation"
Assert-Equal $Official.suite_validation.profile_cache_policy "same-profile-cache-mode-and-key" "official profile-cache compatibility policy"
Assert-Equal $Official.suite_validation.profile_cache_prime_policy "prime-before-measured-run" "official profile-cache priming policy"
Assert-True (@($Official.suite_validation.expected_flag_metadata.fork_default) -contains "viewer_block_external_navigation=true") "official fork default navigation-lock expected flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.fork_default) -contains "viewer_trusted_content=true") "official fork default expected flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.baseline) -contains "resource_warmup_enabled=true") "official baseline expected resource warmup enabled metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.fork_default) -contains "resource_warmup_precompile=true") "official fork default expected resource precompile metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive) -contains "resource_warmup_prerender_frames=2") "official aggressive expected resource prerender metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive) -contains "viewer_force_angle_backend=d3d11") "official aggressive expected flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive) -contains "requested_angle_backend=d3d11") "official aggressive requested ANGLE expected flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_force_angle_backend=null") "official aggressive WebGPU expected backend-neutral ANGLE flag metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "requested_angle_backend=null") "official aggressive WebGPU requested ANGLE expected flag metadata stays neutral"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_skip_webgpu_resource_labels=true") "official aggressive WebGPU source fast-path expected resource-label metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_skip_webgpu_shader_source_null_check=true") "official aggressive WebGPU source fast-path expected shader-source NUL-check metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_skip_webgpu_shader_memory_accounting=true") "official aggressive WebGPU source fast-path expected shader memory-accounting metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_skip_webgpu_redundant_pipeline_sets=true") "official aggressive WebGPU source fast-path expected redundant pipeline metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_skip_webgpu_redundant_bind_group_sets=true") "official aggressive WebGPU source fast-path expected redundant bind-group metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_skip_webgpu_redundant_buffer_sets=true") "official aggressive WebGPU source fast-path expected redundant buffer metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -contains "viewer_skip_webgpu_redundant_render_state_sets=true") "official aggressive WebGPU source fast-path expected redundant render-state metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -notcontains "viewer_force_angle_backend=d3d11") "official aggressive WebGPU expected flag metadata does not inherit ANGLE backend"
Assert-True (@($Official.suite_validation.expected_flag_metadata.aggressive_webgpu) -notcontains "requested_angle_backend=d3d11") "official aggressive WebGPU requested ANGLE expected flag metadata does not inherit ANGLE backend"
Assert-True (@($Official.suite_validation.expected_flag_metadata.baseline_webgpu) -contains "profile_cache_mode=explicit-reuse") "official baseline WebGPU expected profile-cache mode"
Assert-True (@($Official.suite_validation.expected_flag_metadata.baseline_webgpu) -contains "profile_cache_key=dryrun-webgpu-cache") "official baseline WebGPU expected profile-cache key"
Assert-True (@($Official.suite_validation.expected_flag_metadata.fork_default_webgpu) -contains "profile_reuse_enabled=true") "official fork WebGPU expected profile-cache reuse metadata"
Assert-True (@($Official.suite_validation.expected_flag_metadata.baseline) -contains "profile_cache_mode=fresh-temp") "official WebGL2 baseline expected fresh profile-cache mode"
Assert-Equal $Official.artifact_metadata.inputs.viewer_patch.exists $true "official viewer patch metadata exists"
Assert-True ([bool]$Official.artifact_metadata.inputs.viewer_patch.sha256) "official viewer patch metadata hash exists"
Assert-Count @($Official.artifact_metadata.inputs.viewer_patch_series) 2 "official viewer patch series metadata count"
foreach ($PatchMetadata in @($Official.artifact_metadata.inputs.viewer_patch_series)) {
  Assert-Equal $PatchMetadata.exists $true "official viewer patch series metadata exists"
  Assert-True ([bool]$PatchMetadata.sha256) "official viewer patch series metadata hash exists"
}
Assert-True ([bool]$Official.artifact_metadata.inputs.baseline_package.path) "official baseline package metadata path exists"
Assert-True ([bool]$Official.artifact_metadata.inputs.fork_package.path) "official fork package metadata path exists"
Assert-Count @($Official.artifact_metadata.results.baseline_webgl2) $RequiredScenes.Count "official baseline WebGL2 metadata"
Assert-Count @($Official.artifact_metadata.results.fork_default_webgl2) $RequiredScenes.Count "official fork WebGL2 metadata"
Assert-Count @($Official.artifact_metadata.results.aggressive_webgpu) $RequiredScenes.Count "official aggressive WebGPU metadata"
Assert-True ($null -ne $Official.artifact_metadata.traces.baseline_result) "official baseline trace sidecar metadata exists"
Assert-True ($null -ne $Official.artifact_metadata.traces.fork_result) "official fork trace sidecar metadata exists"

  $OfficialBundleOutput = & (Join-Path $Root "scripts\run_official_comparison.ps1") `
    -Duration 1 `
    -Warmup 1 `
    -IncludeWebGPU `
    -IncludeAggressiveGpu `
    -WebGpuBundleMode static `
    -CaptureTrace `
    -TraceScene many-draw-calls `
    -TraceRenderer webgpu `
    -TraceDuration 1 `
    -TraceWarmup 1 `
    -TraceStartDelayMs 2222 `
    -DisableWebGpuTiming `
    -DisableForkWebGpuTiming `
    -SkipSmoke `
    -SkipNavigationLock `
    -DryRun *>&1
  $OfficialBundleText = ($OfficialBundleOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $OfficialBundleText "run_full_suite\.ps1\b.*-Renderer\s+webgpu\b.*-Label\s+baseline-content-shell-webgpu-bundlegroup-static\b.*-WebGpuBundleMode\s+static\b" "official BundleGroup baseline suite handoff"
  Assert-Matches $OfficialBundleText "run_full_suite\.ps1\b.*-Renderer\s+webgpu\b.*-Label\s+fork-viewer-default-webgpu-bundlegroup-static\b.*-WebGpuBundleMode\s+static\b" "official BundleGroup fork suite handoff"
  Assert-Matches $OfficialBundleText "run_full_suite\.ps1\b.*-Renderer\s+webgpu\b.*-Label\s+fork-viewer-aggressive-gpu-webgpu-bundlegroup-static\b.*-WebGpuBundleMode\s+static\b" "official BundleGroup aggressive suite handoff"
  Assert-Matches $OfficialBundleText "run_trace_capture\.mjs\b.*--renderer\s+webgpu\b.*baseline-content-shell-bundlegroup-static-many-draw-calls-webgpu-trace\.json\b.*--webgpuBundleMode\s+static\b" "official BundleGroup baseline trace handoff"
  Assert-Matches $OfficialBundleText "validate_benchmark_suite\.mjs\b.*--renderer\s+webgpu\b.*--variant\s+baseline-content-shell-webgpu-bundlegroup-static\b.*--expectedFlagMetadata\s+webgpu_bundle_mode=static\b" "official BundleGroup baseline validation metadata"
  Assert-Matches $OfficialBundleText "validate_trace_result\.mjs\b.*--expectedRenderer\s+webgpu\b.*--expectedFlagMetadata\s+webgpu_bundle_mode=static\b.*baseline-content-shell-bundlegroup-static-many-draw-calls-webgpu-trace\.result\.json" "official BundleGroup trace sidecar metadata"
  $OfficialBundleManifest = Get-Content -LiteralPath $OfficialManifestPath -Raw | ConvertFrom-Json
  Assert-Equal $OfficialBundleManifest.options.webgpu_bundle_mode "static" "official BundleGroup manifest option"
  Assert-Equal $OfficialBundleManifest.suite_validation.webgpu_bundle_mode_policy "same-webgpu-bundle-mode" "official BundleGroup compatibility policy"
  Assert-True (@($OfficialBundleManifest.result_files.baseline_webgpu | Where-Object { [string]$_ -match "baseline-content-shell-webgpu-bundlegroup-static-many-draw-calls-webgpu\.json$" }).Count -eq 1) "official BundleGroup manifest baseline result file labels"
  Assert-True (@($OfficialBundleManifest.suite_validation.expected_flag_metadata.fork_default_webgpu) -contains "webgpu_bundle_mode=static") "official BundleGroup manifest expected fork metadata"

  $OfficialWebGpuTraceOutput = & (Join-Path $Root "scripts\run_official_comparison.ps1") `
    -Duration 1 `
    -Warmup 1 `
    -CaptureTrace `
    -TraceScene texture-streaming `
    -TraceRenderer webgpu `
    -TraceDuration 1 `
    -TraceWarmup 1 `
    -TraceStartDelayMs 4321 `
    -RejectWebGpuCpuFallbackTrace `
    -DisableWebGpuTiming `
    -DisableForkWebGpuTiming `
    -SkipSmoke `
    -SkipNavigationLock `
    -DryRun *>&1
  $OfficialWebGpuTraceText = ($OfficialWebGpuTraceOutput | ForEach-Object { [string]$_ }) -join "`n"
  Assert-Matches $OfficialWebGpuTraceText "run_trace_capture\.mjs\b.*--renderer\s+webgpu\b.*--output\b.*baseline-content-shell-texture-streaming-webgpu-trace\.json\b.*--disableGpuTiming\b" "official WebGPU baseline trace capture disables GPU timing"
  Assert-Matches $OfficialWebGpuTraceText "run_trace_capture\.mjs\b.*--renderer\s+webgpu\b.*--viewerMode\b.*--viewerTrustedContent\b.*--output\b.*fork-viewer-default-texture-streaming-webgpu-trace\.json\b.*--disableGpuTiming\b.*--viewerTraceWebgpuQueue\b.*--viewerRejectWebgpuCpuTextureFallback\b" "official WebGPU fork trace capture disables GPU timing and enables trusted queue/reject diagnostics in viewer mode"
  Assert-Matches $OfficialWebGpuTraceText "validate_trace_file\.mjs\b.*--minEvents\s+1\b.*--rejectWebGpuCpuFallback\b.*baseline-content-shell-texture-streaming-webgpu-trace\.json" "official WebGPU baseline trace file validation rejects CPU fallback"
  Assert-Matches $OfficialWebGpuTraceText "validate_trace_file\.mjs\b.*--minEvents\s+1\b.*--rejectWebGpuCpuFallback\b.*fork-viewer-default-texture-streaming-webgpu-trace\.json" "official WebGPU fork trace file validation rejects CPU fallback"
  Assert-Matches $OfficialWebGpuTraceText "validate_trace_result\.mjs\b.*--expectedRenderer\s+webgpu\b.*--expectedStartDelayMs\s+4321\b.*--expectedFlagMetadata\s+gpu_timing_enabled=false\b.*baseline-content-shell-texture-streaming-webgpu-trace\.result\.json" "official WebGPU baseline trace sidecar validation records disabled GPU timing"
  Assert-Matches $OfficialWebGpuTraceText "validate_trace_result\.mjs\b.*--expectedRenderer\s+webgpu\b.*--expectedFlagMetadata\s+viewer_mode=true\b.*--expectedFlagMetadata\s+viewer_trusted_content=true\b.*--expectedFlagMetadata\s+viewer_reject_webgpu_cpu_texture_fallback=true\b.*--expectedFlagMetadata\s+viewer_trace_webgpu_queue=true\b.*--expectedFlagMetadata\s+gpu_timing_enabled=false\b.*fork-viewer-default-texture-streaming-webgpu-trace\.result\.json" "official WebGPU fork trace sidecar validation records viewer mode, queue/reject diagnostics, and disabled GPU timing"
  Assert-Matches $OfficialWebGpuTraceText "summarize_trace\.mjs\b.*baseline-content-shell-texture-streaming-webgpu-trace\.json\b.*--rejectWebGpuCpuFallback\b" "official WebGPU baseline trace summary rejects CPU fallback"
  Assert-Matches $OfficialWebGpuTraceText "summarize_trace\.mjs\b.*fork-viewer-default-texture-streaming-webgpu-trace\.json\b.*--rejectWebGpuCpuFallback\b" "official WebGPU fork trace summary rejects CPU fallback"
  $OfficialWebGpuTraceManifest = Get-Content -LiteralPath $OfficialManifestPath -Raw | ConvertFrom-Json
  Assert-Equal $OfficialWebGpuTraceManifest.options.trace_scene "texture-streaming" "official WebGPU trace manifest scene"
  Assert-Equal $OfficialWebGpuTraceManifest.options.trace_renderer "webgpu" "official WebGPU trace manifest renderer"
  Assert-Equal $OfficialWebGpuTraceManifest.options.trace_start_delay_ms 4321 "official WebGPU trace manifest start delay"
  Assert-Equal $OfficialWebGpuTraceManifest.options.reject_webgpu_cpu_fallback_trace $true "official WebGPU trace manifest CPU fallback rejection option"
  Assert-Equal $OfficialWebGpuTraceManifest.options.disable_webgpu_timing $true "official WebGPU trace manifest disables baseline GPU timing"
  Assert-Equal $OfficialWebGpuTraceManifest.options.disable_fork_webgpu_timing $true "official WebGPU trace manifest disables fork GPU timing"

  $InvalidTraceRejectRendererText = Invoke-OfficialComparisonExpectFailure @(
    "-CaptureTrace",
    "-TraceRenderer", "webgl2",
    "-RejectWebGpuCpuFallbackTrace",
    "-SkipSmoke",
    "-SkipNavigationLock",
    "-DryRun"
  ) "CPU-fallback trace rejection with a non-WebGPU trace renderer"
  Assert-Matches $InvalidTraceRejectRendererText "-RejectWebGpuCpuFallbackTrace is only valid with -TraceRenderer webgpu" "official trace preflight rejects WebGPU CPU fallback rejection outside WebGPU traces"
  if ($InvalidTraceRejectRendererText -match "run_trace_capture\.mjs|run_full_suite\.ps1|run_smoke_tests\.mjs") {
    throw "Official trace CPU-fallback rejection preflight ran work before rejecting a non-WebGPU trace renderer."
  }

  $MissingTraceCaptureText = Invoke-OfficialComparisonExpectFailure @(
    "-TraceRenderer", "webgpu",
    "-RejectWebGpuCpuFallbackTrace",
    "-SkipSmoke",
    "-SkipNavigationLock",
    "-DryRun"
  ) "CPU-fallback trace rejection without trace capture"
  Assert-Matches $MissingTraceCaptureText "-RejectWebGpuCpuFallbackTrace requires -CaptureTrace" "official trace preflight rejects CPU fallback rejection without trace capture"
  if ($MissingTraceCaptureText -match "run_trace_capture\.mjs|run_full_suite\.ps1|run_smoke_tests\.mjs") {
    throw "Official trace CPU-fallback rejection preflight ran work before rejecting missing trace capture."
  }

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
  -IncludeZeroCopy `
  -IncludeWebGlCompositorExperiments `
  -IncludeFramePacingExperiments `
  -IncludeInProcessGpu `
  -IncludeSingleProcess `
  -AngleBackend d3d11 `
  -IncludeReservedNoopGates `
  -Precompile `
  -PrerenderFrames 2 `
  -DryRun *>&1
$TrustedText = ($TrustedOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerAggressiveGpu\b" "trusted aggressive experiment command uses trusted and aggressive flags"
Assert-Matches $TrustedText "run_benchmark\.mjs\b.*--complexity\s+2\b" "trusted experiment command defaults to stress complexity"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerZeroCopy\b" "trusted zero-copy experiment command uses trusted zero-copy gate"
Assert-Matches $TrustedText "--browser-flag\s+--enable-gpu-memory-buffer-compositor-resources\b" "trusted WebGL2 compositor-resource experiment passes GPU-memory-buffer browser flag"
Assert-Matches $TrustedText "--browser-flag\s+--ui-enable-zero-copy\b" "trusted WebGL2 compositor-resource experiment passes UI zero-copy browser flag"
Assert-Matches $TrustedText "--browser-flag\s+--enable-gpu-rasterization\b" "trusted WebGL2 compositor-resource experiment passes GPU rasterization browser flag"
Assert-Matches $TrustedText "--browser-flag\s+--disable-frame-rate-limit\b" "trusted frame-pacing experiment passes frame-rate-limit browser flag"
Assert-Matches $TrustedText "--browser-flag\s+--disable-gpu-vsync\b" "trusted frame-pacing experiment passes GPU-vsync browser flag"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerInProcessGpu\b" "trusted in-process GPU experiment command uses trusted and in-process flags"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerSingleProcess\b" "trusted single-process experiment command uses trusted and single-process flags"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerForceAngleBackend\s+d3d11\b" "trusted ANGLE experiment command uses trusted and ANGLE flags"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerRelaxedWebglValidation\b" "trusted relaxed WebGL validation command uses trusted gate"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerDisableUnneededBlinkFeatures\b" "trusted reserved Blink command uses trusted gate"
Assert-Matches $TrustedText "--viewerTrustedContent\b.*--viewerDirectGpuPresentation\b" "trusted reserved direct presentation command uses trusted gate"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--requirePackageSize\b" "trusted suite validation requires package size when package dir is provided"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--requireFrameTimes\b" "trusted suite validation requires raw frame-time samples"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--expectedChromiumRevision\s+$([regex]::Escape($ChromiumRevision))\b" "trusted suite validation requires expected Chromium revision"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--expectedComplexity\s+2\b" "trusted suite validation checks stress complexity"
if ($ExpectedForkBuildArgsHash) {
  Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--expectedBuildArgsHash\s+$ExpectedForkBuildArgsHash\b" "trusted suite validation binds result metadata to GN args hash"
}
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--expectedFlagMetadata\s+viewer_block_external_navigation=true\b" "trusted default suite validation checks navigation-lock flag metadata"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--expectedFlagMetadata\s+resource_warmup_enabled=true\b.*--expectedFlagMetadata\s+resource_warmup_prerender_frames=2\b" "trusted default suite validation checks resource warmup metadata"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-zero-copy\b.*--expectedFlagMetadata\s+viewer_zero_copy=true\b" "trusted zero-copy suite validation checks zero-copy flag metadata"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgl2-gpu-compositor-resources\b.*--requiredBrowserFlag\s+--enable-gpu-memory-buffer-compositor-resources\b" "trusted WebGL2 compositor-resource validation requires GMB browser flag"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources\b.*--expectedFlagMetadata\s+viewer_zero_copy=true\b.*--requiredBrowserFlag\s+--ui-enable-zero-copy\b" "trusted WebGL2 zero-copy compositor-resource validation checks zero-copy metadata and UI zero-copy browser flag"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-disable-frame-rate-limit\b.*--requiredBrowserFlag\s+--disable-frame-rate-limit\b" "trusted frame-rate-limit validation requires browser flag"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-disable-frame-rate-limit-gpu-vsync\b.*--requiredBrowserFlag\s+--disable-gpu-vsync\b" "trusted combined frame pacing validation requires GPU-vsync browser flag"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-in-process-gpu\b.*--expectedFlagMetadata\s+viewer_in_process_gpu=true\b" "trusted in-process suite validation checks in-process flag metadata"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-angle-d3d11\b.*--expectedFlagMetadata\s+viewer_force_angle_backend=d3d11\b.*--expectedFlagMetadata\s+requested_angle_backend=d3d11\b" "trusted ANGLE suite validation checks ANGLE flag metadata"
Assert-Matches $TrustedText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy\b.*--expectedFlagMetadata\s+viewer_relaxed_webgl_validation=true\b.*--expectedFlagMetadata\s+viewer_zero_copy=true\b.*--expectedFlagMetadata\s+viewer_force_angle_backend=d3d11\b" "trusted WebGL2 D3D11 relaxed zero-copy suite validation checks combined flag metadata"

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
Assert-True (Test-Path $TrustedWebGlManifestPath) "trusted WebGL2 dry-run manifest exists"
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
Assert-Equal $Trusted.suite_validation.expected_build_args_hash $ExpectedForkBuildArgsHash "trusted suite expected GN args hash"
Assert-Equal $Trusted.suite_validation.exact_scene_output_files $true "trusted exact scene output validation"
Assert-Equal $Trusted.suite_validation.reject_software_rendering $true "trusted software-renderer rejection validation"
Assert-Equal $Trusted.suite_validation.reject_gpu_instability $true "trusted GPU-instability rejection validation"
Assert-Equal $Trusted.suite_validation.require_gpu_metadata $true "trusted GPU metadata validation"
Assert-Equal $Trusted.suite_validation.require_frame_times $true "trusted raw frame-time sample validation"
Assert-True (@($Trusted.suite_validation.required_browser_flags) -contains "--disable-software-rasterizer") "trusted required browser launch flag validation"
Assert-Equal $Trusted.suite_validation.expected_measured_seconds 1 "trusted expected measured seconds validation"
Assert-Equal $Trusted.suite_validation.expected_warmup_seconds 1 "trusted expected warmup seconds validation"
Assert-Equal $Trusted.suite_validation.expected_complexity 2 "trusted expected complexity validation"
Assert-Equal $Trusted.suite_validation.expected_flag_metadata $true "trusted expected flag metadata validation"

$ExpectedExperiments = @(
  "fork-viewer-exp-default",
  "fork-viewer-exp-aggressive-gpu",
  "fork-viewer-exp-zero-copy",
  "fork-viewer-exp-webgl2-gpu-compositor-resources",
  "fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources",
  "fork-viewer-exp-disable-frame-rate-limit",
  "fork-viewer-exp-disable-gpu-vsync",
  "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync",
  "fork-viewer-exp-in-process-gpu",
  "fork-viewer-exp-single-process",
  "fork-viewer-exp-angle-d3d11",
  "fork-viewer-exp-relaxed-webgl-validation-gate",
  "fork-viewer-exp-disable-unneeded-blink-features-gate",
  "fork-viewer-exp-direct-gpu-presentation-gate",
  "fork-viewer-exp-relaxed-webgl-validation-zero-copy",
  "fork-viewer-exp-angle-d3d11-zero-copy",
  "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation",
  "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy"
)
Assert-Count @($Trusted.experiments) $ExpectedExperiments.Count "trusted experiment count"
foreach ($Label in $ExpectedExperiments) {
  Assert-True (@($Trusted.experiments | ForEach-Object { $_.label }) -contains $Label) "trusted experiment list contains $Label"
}
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-default") @() "default experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-aggressive-gpu") @("--viewerAggressiveGpu") "aggressive GPU experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-zero-copy") @("--viewerZeroCopy") "zero-copy experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-webgl2-gpu-compositor-resources") @() "WebGL2 compositor GPU-resource experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources") @("--viewerZeroCopy") "WebGL2 zero-copy compositor GPU-resource experiment"
Assert-BrowserFlags (Get-Experiment $Trusted "fork-viewer-exp-webgl2-gpu-compositor-resources") @("--enable-gpu-memory-buffer-compositor-resources", "--ui-enable-zero-copy", "--enable-gpu-rasterization") "WebGL2 compositor GPU-resource experiment"
Assert-BrowserFlags (Get-Experiment $Trusted "fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources") @("--enable-gpu-memory-buffer-compositor-resources", "--ui-enable-zero-copy", "--enable-gpu-rasterization") "WebGL2 zero-copy compositor GPU-resource experiment"
Assert-BrowserFlags (Get-Experiment $Trusted "fork-viewer-exp-disable-frame-rate-limit") @("--disable-frame-rate-limit") "frame-rate-limit experiment"
Assert-BrowserFlags (Get-Experiment $Trusted "fork-viewer-exp-disable-gpu-vsync") @("--disable-gpu-vsync") "GPU-vsync experiment"
Assert-BrowserFlags (Get-Experiment $Trusted "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync") @("--disable-frame-rate-limit", "--disable-gpu-vsync") "combined frame-pacing experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-in-process-gpu") @("--viewerInProcessGpu") "in-process GPU experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-single-process") @("--viewerSingleProcess") "single-process experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11") @("--viewerForceAngleBackend", "d3d11") "ANGLE d3d11 experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-relaxed-webgl-validation-gate") @("--viewerRelaxedWebglValidation") "relaxed WebGL validation pass-through command decoder experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-disable-unneeded-blink-features-gate") @("--viewerDisableUnneededBlinkFeatures") "reserved Blink feature gate experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-direct-gpu-presentation-gate") @("--viewerDirectGpuPresentation") "reserved direct GPU presentation gate experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-relaxed-webgl-validation-zero-copy") @("--viewerRelaxedWebglValidation", "--viewerZeroCopy") "combined relaxed WebGL validation plus zero-copy needs-suite experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11-zero-copy") @("--viewerForceAngleBackend", "d3d11", "--viewerZeroCopy") "combined ANGLE d3d11 plus zero-copy experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation") @("--viewerForceAngleBackend", "d3d11", "--viewerRelaxedWebglValidation") "combined ANGLE d3d11 plus relaxed WebGL validation experiment"
Assert-Flags (Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy") @("--viewerForceAngleBackend", "d3d11", "--viewerRelaxedWebglValidation", "--viewerZeroCopy") "combined ANGLE d3d11 plus relaxed WebGL validation plus zero-copy experiment"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-default").expected_flag_metadata) -contains "viewer_block_external_navigation=true") "default experiment navigation-lock expected flag metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-default").expected_flag_metadata) -contains "resource_warmup_enabled=true") "default experiment expected resource warmup enabled metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-default").expected_flag_metadata) -contains "resource_warmup_precompile=true") "default experiment expected resource precompile metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-default").expected_flag_metadata) -contains "resource_warmup_prerender_frames=2") "default experiment expected resource prerender metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-zero-copy").expected_flag_metadata) -contains "viewer_zero_copy=true") "zero-copy experiment expected flag metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-relaxed-webgl-validation-zero-copy").expected_flag_metadata) -contains "viewer_zero_copy=true") "combined relaxed validation zero-copy expected zero-copy metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-relaxed-webgl-validation-zero-copy").expected_flag_metadata) -contains "viewer_relaxed_webgl_validation=true") "combined relaxed validation zero-copy expected relaxed-validation metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources").expected_flag_metadata) -contains "viewer_zero_copy=true") "WebGL2 zero-copy compositor GPU-resource experiment expected zero-copy metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-in-process-gpu").expected_flag_metadata) -contains "viewer_in_process_gpu=true") "in-process experiment expected flag metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11-zero-copy").expected_flag_metadata) -contains "viewer_zero_copy=true") "ANGLE zero-copy experiment expected zero-copy metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11-zero-copy").expected_flag_metadata) -contains "viewer_force_angle_backend=d3d11") "ANGLE zero-copy experiment expected backend metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11").expected_flag_metadata) -contains "viewer_force_angle_backend=d3d11") "ANGLE experiment expected flag metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11").expected_flag_metadata) -contains "requested_angle_backend=d3d11") "ANGLE experiment requested backend expected flag metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy").expected_flag_metadata) -contains "viewer_relaxed_webgl_validation=true") "ANGLE relaxed zero-copy experiment expected relaxed-validation metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy").expected_flag_metadata) -contains "viewer_zero_copy=true") "ANGLE relaxed zero-copy experiment expected zero-copy metadata"
Assert-True (@((Get-Experiment $Trusted "fork-viewer-exp-angle-d3d11-relaxed-webgl-validation-zero-copy").expected_flag_metadata) -contains "viewer_force_angle_backend=d3d11") "ANGLE relaxed zero-copy experiment expected backend metadata"

$ExpectedTrustedResults = $ExpectedExperiments.Count * $RequiredScenes.Count
Assert-Count @($Trusted.result_files.all) $ExpectedTrustedResults "trusted result files"
Assert-Count @($Trusted.artifact_metadata.results.all) $ExpectedTrustedResults "trusted result metadata"
Assert-Equal $Trusted.artifact_metadata.inputs.viewer_patch.exists $true "trusted viewer patch metadata exists"
Assert-True ([bool]$Trusted.artifact_metadata.inputs.viewer_patch.sha256) "trusted viewer patch metadata hash exists"
Assert-Count @($Trusted.artifact_metadata.inputs.viewer_patch_series) 2 "trusted viewer patch series metadata count"
foreach ($PatchMetadata in @($Trusted.artifact_metadata.inputs.viewer_patch_series)) {
  Assert-Equal $PatchMetadata.exists $true "trusted viewer patch series metadata exists"
  Assert-True ([bool]$PatchMetadata.sha256) "trusted viewer patch series metadata hash exists"
}
Assert-True ([bool]$Trusted.report_files.summary) "trusted summary report path exists in manifest"
Assert-True ([bool]$Trusted.report_files.comparison) "trusted comparison report path exists in manifest"

$InvalidWebGpuDawnRendererText = Invoke-TrustedExperimentExpectFailure @(
  "-Browser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
  "-BuildArgs", (Join-Path $SyntheticInputDir "fork-args.gn"),
  "-ForkRevision", $ExpectedForkRevision,
  "-Renderer", "webgl2",
  "-Duration", "1",
  "-Warmup", "1",
  "-IncludeWebGpuDawnExperiments"
) "WebGPU Dawn browser-flag experiments with WebGL2 renderer"
Assert-Matches $InvalidWebGpuDawnRendererText "-IncludeWebGpuDawnExperiments is only valid with -Renderer webgpu" "trusted matrix rejects WebGPU Dawn browser-flag experiments outside WebGPU renderer"
if ($InvalidWebGpuDawnRendererText -match "run_benchmark\.mjs|validate_benchmark_suite\.mjs|summarize_results\.mjs") {
  throw "Trusted experiment renderer guard ran benchmark work before rejecting WebGPU Dawn experiments on WebGL2."
}

$InvalidWebGpuChromiumFeatureRendererText = Invoke-TrustedExperimentExpectFailure @(
  "-Browser", (Join-Path $SyntheticInputDir "fork-content_shell.exe"),
  "-BuildArgs", (Join-Path $SyntheticInputDir "fork-args.gn"),
  "-ForkRevision", $ExpectedForkRevision,
  "-Renderer", "webgl2",
  "-Duration", "1",
  "-Warmup", "1",
  "-IncludeWebGpuChromiumFeatureExperiments"
) "WebGPU Chromium feature experiments with WebGL2 renderer"
Assert-Matches $InvalidWebGpuChromiumFeatureRendererText "-IncludeWebGpuChromiumFeatureExperiments is only valid with -Renderer webgpu" "trusted matrix rejects WebGPU Chromium feature experiments outside WebGPU renderer"
if ($InvalidWebGpuChromiumFeatureRendererText -match "run_benchmark\.mjs|validate_benchmark_suite\.mjs|summarize_results\.mjs") {
  throw "Trusted experiment renderer guard ran benchmark work before rejecting WebGPU Chromium feature experiments on WebGL2."
}

$TrustedWebGpuOutput = & (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1") `
  -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
  -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
  -PackageDir ".\benchmarks\packages\viewer-default" `
  -ForkRevision $ExpectedForkRevision `
  -Renderer webgpu `
  -Duration 1 `
  -Warmup 1 `
  -IncludeDefault `
  -IncludeWebGpuDawnExperiments `
  -IncludeWebGpuChromiumFeatureExperiments `
  -IncludeWebGpuUploadExperiments `
  -DisableGpuTiming `
  -ProfileCacheKey "dryrun-trusted-webgpu-cache" `
  -UserDataDirRoot ".\benchmarks\tmp\trusted-profile-cache-dry-run" `
  -PrimeProfileCache `
  -DryRun *>&1
$TrustedWebGpuText = ($TrustedWebGpuOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $TrustedWebGpuText "Trusted WebGPU experiment Dawn toggles, Chromium feature flags, adapter values, source-backed viewer flags, and trace-only diagnostics map to source registries and patch wiring\." "trusted WebGPU matrix validates experiment flags against source registries before dry-run benchmark commands"
Assert-Matches $TrustedWebGpuText "--disableGpuTiming\b" "trusted WebGPU Dawn matrix disables viewer GPU timestamp timing"
Assert-Matches $TrustedWebGpuText "--userDataDir\s+.*trusted-profile-cache-dry-run.*fork-viewer-exp-default.*webgpu.*many-draw-calls\b.*--profileCacheKey\s+dryrun-trusted-webgpu-cache\b" "trusted WebGPU matrix forwards per-experiment profile-cache args"
Assert-Matches $TrustedWebGpuText "Priming profile cache for fork-viewer-exp-default many-draw-calls" "trusted WebGPU matrix prints explicit profile-cache priming pass"
Assert-True ([regex]::Matches($TrustedWebGpuText, "--variant\s+fork-viewer-exp-default\b.*--scene\s+many-draw-calls\b.*--profileCacheKey\s+dryrun-trusted-webgpu-cache").Count -ge 2) "trusted WebGPU default run occurs once for priming and once for measurement"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--use-webgpu-adapter=d3d11\b" "trusted WebGPU Dawn matrix passes D3D11 adapter browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=d3d11_delay_flush_to_gpu\b" "trusted WebGPU Dawn matrix passes D3D11 delayed-flush browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=d3d11_use_unmonitored_fence\b" "trusted WebGPU Dawn matrix passes D3D11 unmonitored-fence browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=d3d11_disable_fence\b" "trusted WebGPU Dawn matrix passes D3D11 disable-fence browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence\b" "trusted WebGPU Dawn matrix passes D3D11 delayed-flush plus unmonitored-fence browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=d3d11_use_discard_view\b" "trusted WebGPU Dawn matrix passes D3D11 DiscardView browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=d3d11_disable_cpu_buffers\b" "trusted WebGPU Dawn matrix passes D3D11 CPU upload-buffer browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=d3d11_disable_map_on_default_buffers\b" "trusted WebGPU Dawn matrix passes D3D11 MapOnDefaultBuffers browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=disable_lazy_clear_for_mapped_at_creation_buffer\b" "trusted WebGPU Dawn matrix passes mapped-at-creation clear-skip browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=use_dxc\b" "trusted WebGPU Dawn matrix passes DXC shader compiler browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--disable-dawn-features=blob_cache_hash_validation\b" "trusted WebGPU Dawn matrix passes blob-cache hash-validation disable browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=skip_validation\b" "trusted WebGPU Dawn matrix passes skip-validation browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=disable_robustness\b" "trusted WebGPU Dawn matrix passes disable-robustness browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=skip_validation,disable_robustness\b" "trusted WebGPU Dawn matrix passes combined skip-validation plus disable-robustness browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=d3d12_create_not_zeroed_heap,use_d3d12_resource_heap_tier2,use_d3d12_render_pass,d3d12_use_root_signature_version_1_1\b" "trusted WebGPU Dawn matrix passes D3D12 toggle browser flags"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-features=RemoveGPULegacyIPC\b" "trusted WebGPU Chromium feature matrix passes RemoveGPULegacyIPC browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-features=WebGPUUseHLSL2021\b" "trusted WebGPU Chromium feature matrix passes HLSL 2021 browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--disable-features=WebGPUEnableRangeAnalysisForRobustness\b" "trusted WebGPU Chromium feature matrix passes range-analysis disable browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021\b" "trusted WebGPU Chromium feature matrix passes combined feature browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-features=IncreasedCmdBufferParseSlice\b" "trusted WebGPU upload matrix passes command-buffer slice browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--disable-features=D3DBackingUploadWithUpdateSubresource\b" "trusted WebGPU upload matrix passes D3D staging upload browser flag"
Assert-Matches $TrustedWebGpuText "--viewerDeferWebgpuQueueFlush\b" "trusted WebGPU upload matrix passes Blink queue-flush deferral runner flag"
Assert-Matches $TrustedWebGpuText "--viewerDeferWebgpuSubmitFlush\b" "trusted WebGPU upload matrix passes Blink submit-flush deferral runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuCanvasTextureValidation\b" "trusted WebGPU upload matrix passes Blink canvas texture validation skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuCanvasMemoryAccounting\b" "trusted WebGPU upload matrix passes Blink canvas memory-accounting skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuCopyExternalImageColorConversion\b" "trusted WebGPU upload matrix passes Blink copyExternalImage color-conversion setup skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation\b" "trusted WebGPU upload matrix passes Blink copyExternalImage color-space validation skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuCopyExternalImageDestValidation\b" "trusted WebGPU upload matrix passes Blink copyExternalImage destination validation skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuCopyExternalImageSourceValidation\b" "trusted WebGPU upload matrix passes Blink copyExternalImage source validation skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuCopyExternalImageCopySizeValidation\b" "trusted WebGPU upload matrix passes Blink copyExternalImage copy-size validation skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerRejectWebgpuCpuTextureFallback\b" "trusted WebGPU copyExternalImage upload matrix passes CPU texture fallback rejection runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuWriteTextureLayoutValidation\b" "trusted WebGPU upload matrix passes Blink writeTexture layout validation skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuUseCounters\b" "trusted WebGPU upload matrix passes Blink use-counter skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuRedundantPipelineSets\b" "trusted WebGPU upload matrix passes Blink redundant setPipeline skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuRedundantBindGroupSets\b" "trusted WebGPU upload matrix passes Blink redundant setBindGroup skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuRedundantBufferSets\b" "trusted WebGPU upload matrix passes Blink redundant setVertexBuffer/setIndexBuffer skip runner flag"
Assert-Matches $TrustedWebGpuText "--viewerSkipWebgpuRedundantRenderStateSets\b" "trusted WebGPU upload matrix passes Blink redundant render-state skip runner flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice\b" "trusted WebGPU interaction matrix passes combined Chromium feature/upload browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer\b" "trusted WebGPU interaction matrix passes D3D11 DXC/flush/fence/clear-skip browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer,skip_validation,disable_robustness\b" "trusted WebGPU interaction matrix passes aggressive D3D11 Dawn pipeline fast-path browser flag"
Assert-Matches $TrustedWebGpuText "--browser-flag\s+--disable-features=WebGPUEnableRangeAnalysisForRobustness,D3DBackingUploadWithUpdateSubresource\b" "trusted WebGPU interaction matrix passes aggressive upload disable-features browser flag"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-adapter-d3d11\b.*--requiredBrowserFlag\s+--use-webgpu-adapter=d3d11\b" "trusted WebGPU Dawn adapter validation requires adapter browser flag"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation\b.*--requiredBrowserFlag\s+--disable-dawn-features=blob_cache_hash_validation\b" "trusted WebGPU Dawn blob-cache hash-validation disable suite validation requires Dawn browser flag"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-dawn-skip-validation\b.*--requiredBrowserFlag\s+--enable-dawn-features=skip_validation\b" "trusted WebGPU Dawn skip-validation suite validation requires Dawn browser flag"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d11-skip-validation\b.*--requiredBrowserFlag\s+--use-webgpu-adapter=d3d11\b.*--requiredBrowserFlag\s+--enable-dawn-features=skip_validation\b" "trusted WebGPU D3D11 skip-validation suite validation requires adapter and Dawn browser flags"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d11-skip-validation-disable-robustness\b.*--requiredBrowserFlag\s+--use-webgpu-adapter=d3d11\b.*--requiredBrowserFlag\s+--enable-dawn-features=skip_validation,disable_robustness\b" "trusted WebGPU D3D11 skip-validation plus disable-robustness suite validation requires adapter and Dawn browser flags"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-remove-gpu-legacy-ipc\b.*--requiredBrowserFlag\s+--enable-features=RemoveGPULegacyIPC\b" "trusted WebGPU Chromium feature validation requires RemoveGPULegacyIPC browser flag"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-disable-range-analysis\b.*--requiredBrowserFlag\s+--disable-features=WebGPUEnableRangeAnalysisForRobustness\b" "trusted WebGPU range-analysis feature validation requires disable-features browser flag"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment\b.*--requiredBrowserFlag\s+--enable-dawn-features=d3d12_relax_buffer_texture_copy_pitch_and_offset_alignment\b" "trusted WebGPU D3D12 relaxed copy-alignment validation requires Dawn browser flag"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment-staging-upload\b.*--requiredBrowserFlag\s+--enable-dawn-features=d3d12_relax_buffer_texture_copy_pitch_and_offset_alignment\b.*--requiredBrowserFlag\s+--disable-features=D3DBackingUploadWithUpdateSubresource\b" "trusted WebGPU D3D12 relaxed copy-alignment plus staging-upload validation requires all browser flags"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d11-ipc-hlsl2021-cmd-slice-staging-upload\b.*--requiredBrowserFlag\s+--use-webgpu-adapter=d3d11\b.*--requiredBrowserFlag\s+--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice\b.*--requiredBrowserFlag\s+--disable-features=D3DBackingUploadWithUpdateSubresource\b" "trusted WebGPU D3D11 feature/upload interaction validation requires all browser flags"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range\b.*--requiredBrowserFlag\s+--use-webgpu-adapter=d3d11\b.*--requiredBrowserFlag\s+--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer\b.*--requiredBrowserFlag\s+--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice\b.*--requiredBrowserFlag\s+--disable-features=WebGPUEnableRangeAnalysisForRobustness\b" "trusted WebGPU D3D11 DXC/IPC/HLSL/range-analysis interaction validation requires all browser flags"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path\b.*--requiredBrowserFlag\s+--use-webgpu-adapter=d3d11\b.*--requiredBrowserFlag\s+--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer,skip_validation,disable_robustness\b.*--requiredBrowserFlag\s+--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice\b.*--requiredBrowserFlag\s+--disable-features=WebGPUEnableRangeAnalysisForRobustness\b" "trusted WebGPU aggressive D3D11 pipeline fast-path validation requires all browser flags"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path\b.*--requiredBrowserFlag\s+--use-webgpu-adapter=d3d11\b.*--requiredBrowserFlag\s+--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer,skip_validation,disable_robustness\b.*--requiredBrowserFlag\s+--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice\b.*--requiredBrowserFlag\s+--disable-features=WebGPUEnableRangeAnalysisForRobustness,D3DBackingUploadWithUpdateSubresource\b" "trusted WebGPU aggressive D3D11 upload fast-path validation requires all browser flags"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip\b.*--requiredBrowserFlag\s+--use-webgpu-adapter=d3d11\b.*--requiredBrowserFlag\s+--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer\b" "trusted WebGPU D3D11 DXC/flush/fence/clear-skip validation requires all browser flags"
Assert-Matches $TrustedWebGpuText "validate_benchmark_suite\.mjs\b.*--variant\s+fork-viewer-exp-default\b.*--expectedFlagMetadata\s+profile_cache_mode=explicit-reuse\b.*--expectedFlagMetadata\s+profile_cache_key=dryrun-trusted-webgpu-cache\b.*--expectedFlagMetadata\s+profile_reuse_enabled=true\b" "trusted WebGPU suite validation checks profile-cache metadata"

Assert-True (Test-Path $TrustedManifestPath) "trusted WebGPU dry-run manifest exists"
Assert-True (Test-Path $TrustedWebGpuManifestPath) "trusted WebGPU renderer-specific dry-run manifest exists"
$TrustedWebGpu = Get-Content -LiteralPath $TrustedManifestPath -Raw | ConvertFrom-Json
Assert-Equal $TrustedWebGpu.renderer "webgpu" "trusted WebGPU renderer"
Assert-Equal $TrustedWebGpu.options.disable_gpu_timing $true "trusted WebGPU disable_gpu_timing option"
Assert-Equal $TrustedWebGpu.options.profile_cache_key "dryrun-trusted-webgpu-cache" "trusted WebGPU profile-cache key option"
Assert-Equal $TrustedWebGpu.options.profile_cache_mode "explicit-reuse" "trusted WebGPU profile-cache mode option"
Assert-True ([string]$TrustedWebGpu.options.profile_cache_root -match "trusted-profile-cache-dry-run") "trusted WebGPU profile-cache root option"
Assert-Equal $TrustedWebGpu.options.prime_profile_cache $true "trusted WebGPU profile-cache priming option"
Assert-Equal $TrustedWebGpu.suite_validation.profile_cache_policy "same-profile-cache-mode-and-key" "trusted WebGPU profile-cache compatibility policy"
Assert-Equal $TrustedWebGpu.suite_validation.profile_cache_prime_policy "prime-before-measured-run" "trusted WebGPU profile-cache priming policy"
Assert-True (@($TrustedWebGpu.suite_validation.required_browser_flags) -contains "--disable-software-rasterizer") "trusted WebGPU suite required browser launch flag validation"

$ExpectedWebGpuExperiments = @(
  "fork-viewer-exp-default",
  "fork-viewer-exp-webgpu-adapter-d3d11",
  "fork-viewer-exp-webgpu-d3d11-delay-flush",
  "fork-viewer-exp-webgpu-d3d11-unmonitored-fence",
  "fork-viewer-exp-webgpu-d3d11-disable-fence",
  "fork-viewer-exp-webgpu-d3d11-delay-flush-unmonitored-fence",
  "fork-viewer-exp-webgpu-d3d11-wait-thread-safe",
  "fork-viewer-exp-webgpu-d3d11-delay-flush-wait-thread-safe",
  "fork-viewer-exp-webgpu-d3d11-discard-view",
  "fork-viewer-exp-webgpu-d3d11-disable-cpu-upload-buffers",
  "fork-viewer-exp-webgpu-d3d11-disable-map-default-buffers",
  "fork-viewer-exp-webgpu-d3d11-auto-map-backend-buffer",
  "fork-viewer-exp-webgpu-dawn-mapped-buffer-clear-skip",
  "fork-viewer-exp-webgpu-dawn-use-dxc",
  "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation",
  "fork-viewer-exp-webgpu-dawn-skip-validation",
  "fork-viewer-exp-webgpu-dawn-disable-robustness",
  "fork-viewer-exp-webgpu-d3d11-skip-validation",
  "fork-viewer-exp-webgpu-d3d11-disable-robustness",
  "fork-viewer-exp-webgpu-d3d11-skip-validation-disable-robustness",
  "fork-viewer-exp-webgpu-d3d12-toggles",
  "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc",
  "fork-viewer-exp-webgpu-hlsl2021",
  "fork-viewer-exp-webgpu-disable-range-analysis",
  "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc-hlsl2021",
  "fork-viewer-exp-webgpu-defer-pipeline-flush",
  "fork-viewer-exp-webgpu-cache-bind-group-layouts",
  "fork-viewer-exp-webgpu-skip-command-labels",
  "fork-viewer-exp-webgpu-skip-resource-labels",
  "fork-viewer-exp-webgpu-skip-shader-source-null-check",
  "fork-viewer-exp-webgpu-skip-shader-memory-accounting",
  "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets",
  "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets",
  "fork-viewer-exp-webgpu-skip-redundant-buffer-sets",
  "fork-viewer-exp-webgpu-skip-redundant-render-state-sets",
  "fork-viewer-exp-webgpu-defer-queue-flush",
  "fork-viewer-exp-webgpu-defer-submit-flush",
  "fork-viewer-exp-webgpu-skip-canvas-texture-validation",
  "fork-viewer-exp-webgpu-skip-canvas-memory-accounting",
  "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion",
  "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation",
  "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation",
  "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation",
  "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation",
  "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path",
  "fork-viewer-exp-webgpu-skip-write-texture-layout-validation",
  "fork-viewer-exp-webgpu-skip-use-counters",
  "fork-viewer-exp-webgpu-increased-cmd-buffer-slice",
  "fork-viewer-exp-webgpu-d3d-staging-upload",
  "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment",
  "fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload",
  "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment-staging-upload",
  "fork-viewer-exp-webgpu-d3d11-remove-gpu-legacy-ipc-hlsl2021",
  "fork-viewer-exp-webgpu-d3d11-cmd-slice-d3d-staging-upload",
  "fork-viewer-exp-webgpu-d3d11-ipc-hlsl2021-cmd-slice-staging-upload",
  "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range",
  "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path",
  "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-shader-source-null-check",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-shader-memory-accounting",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-buffer-sets",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-render-state-sets",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-color-conv",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-colorspace",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-validation",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-source",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-copy-size",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-copy-ext-image-fast-path",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-write-texture-layout-validation",
  "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters"
)
Assert-Count @($TrustedWebGpu.experiments) $ExpectedWebGpuExperiments.Count "trusted WebGPU experiment count"
foreach ($Label in $ExpectedWebGpuExperiments) {
  Assert-True (@($TrustedWebGpu.experiments | ForEach-Object { $_.label }) -contains $Label) "trusted WebGPU experiment list contains $Label"
}
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-default") @() "trusted WebGPU default experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-adapter-d3d11") @("--use-webgpu-adapter=d3d11") "trusted WebGPU D3D11 adapter experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-delay-flush") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_delay_flush_to_gpu") "trusted WebGPU D3D11 delayed-flush experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-unmonitored-fence") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_use_unmonitored_fence") "trusted WebGPU D3D11 unmonitored-fence experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-disable-fence") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_disable_fence") "trusted WebGPU D3D11 disable-fence experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-delay-flush-unmonitored-fence") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence") "trusted WebGPU D3D11 delayed-flush plus unmonitored-fence experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-wait-thread-safe") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=wait_is_thread_safe") "trusted WebGPU D3D11 thread-safe wait experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-delay-flush-wait-thread-safe") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_delay_flush_to_gpu,wait_is_thread_safe") "trusted WebGPU D3D11 delayed-flush plus thread-safe wait experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-discard-view") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_use_discard_view") "trusted WebGPU D3D11 DiscardView experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-disable-cpu-upload-buffers") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_disable_cpu_buffers") "trusted WebGPU D3D11 CPU upload-buffer experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-disable-map-default-buffers") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_disable_map_on_default_buffers") "trusted WebGPU D3D11 MapOnDefaultBuffers experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-auto-map-backend-buffer") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=auto_map_backend_buffer") "trusted WebGPU D3D11 backend-buffer auto-map experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-dawn-mapped-buffer-clear-skip") @("--enable-dawn-features=disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU mapped-at-creation buffer clear-skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-dawn-use-dxc") @("--enable-dawn-features=use_dxc") "trusted WebGPU Dawn DXC shader compiler experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation") @("--disable-dawn-features=blob_cache_hash_validation") "trusted WebGPU Dawn blob-cache hash-validation disable experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-dawn-skip-validation") @("--enable-dawn-features=skip_validation") "trusted WebGPU Dawn skip-validation experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-dawn-disable-robustness") @("--enable-dawn-features=disable_robustness") "trusted WebGPU Dawn disable-robustness experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-skip-validation") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=skip_validation") "trusted WebGPU D3D11 skip-validation interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-disable-robustness") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=disable_robustness") "trusted WebGPU D3D11 disable-robustness interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-skip-validation-disable-robustness") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=skip_validation,disable_robustness") "trusted WebGPU D3D11 skip-validation plus disable-robustness interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d12-toggles") @("--enable-dawn-features=d3d12_create_not_zeroed_heap,use_d3d12_resource_heap_tier2,use_d3d12_render_pass,d3d12_use_root_signature_version_1_1") "trusted WebGPU Dawn D3D12 toggles experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc") @("--enable-features=RemoveGPULegacyIPC") "trusted WebGPU RemoveGPULegacyIPC experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-hlsl2021") @("--enable-features=WebGPUUseHLSL2021") "trusted WebGPU HLSL 2021 experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-disable-range-analysis") @("--disable-features=WebGPUEnableRangeAnalysisForRobustness") "trusted WebGPU range-analysis disable experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc-hlsl2021") @("--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021") "trusted WebGPU combined Chromium feature experiment"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-pipeline-flush") @("--viewerDeferWebgpuPipelineFlush") "trusted WebGPU Blink async pipeline flush deferral experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-pipeline-flush") @() "trusted WebGPU Blink async pipeline flush deferral experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-cache-bind-group-layouts") @("--viewerCacheWebgpuBindGroupLayouts") "trusted WebGPU Blink bind-group-layout cache experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-cache-bind-group-layouts") @() "trusted WebGPU Blink bind-group-layout cache experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-command-labels") @("--viewerSkipWebgpuCommandLabels") "trusted WebGPU Blink command-label skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-command-labels") @() "trusted WebGPU Blink command-label skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-resource-labels") @("--viewerSkipWebgpuResourceLabels") "trusted WebGPU Blink resource-label skip experiment"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-shader-source-null-check") @("--viewerSkipWebgpuShaderSourceNullCheck") "trusted WebGPU Blink shader-source NUL-check skip experiment"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-shader-memory-accounting") @("--viewerSkipWebgpuShaderMemoryAccounting") "trusted WebGPU Blink shader memory-accounting skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-resource-labels") @() "trusted WebGPU Blink resource-label skip experiment browser flags"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-shader-source-null-check") @() "trusted WebGPU Blink shader-source NUL-check skip experiment browser flags"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-shader-memory-accounting") @() "trusted WebGPU Blink shader memory-accounting skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets") @("--viewerSkipWebgpuRedundantPipelineSets") "trusted WebGPU Blink redundant setPipeline skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets") @() "trusted WebGPU Blink redundant setPipeline skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets") @("--viewerSkipWebgpuRedundantBindGroupSets") "trusted WebGPU Blink redundant setBindGroup skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets") @() "trusted WebGPU Blink redundant setBindGroup skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-buffer-sets") @("--viewerSkipWebgpuRedundantBufferSets") "trusted WebGPU Blink redundant setVertexBuffer/setIndexBuffer skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-buffer-sets") @() "trusted WebGPU Blink redundant setVertexBuffer/setIndexBuffer skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-render-state-sets") @("--viewerSkipWebgpuRedundantRenderStateSets") "trusted WebGPU Blink redundant render-state skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-render-state-sets") @() "trusted WebGPU Blink redundant render-state skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-queue-flush") @("--viewerDeferWebgpuQueueFlush") "trusted WebGPU Blink queue-flush deferral experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-queue-flush") @() "trusted WebGPU Blink queue-flush deferral experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-submit-flush") @("--viewerDeferWebgpuSubmitFlush") "trusted WebGPU Blink submit-flush deferral experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-submit-flush") @() "trusted WebGPU Blink submit-flush deferral experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-canvas-texture-validation") @("--viewerSkipWebgpuCanvasTextureValidation") "trusted WebGPU Blink canvas texture validation skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-canvas-texture-validation") @() "trusted WebGPU Blink canvas texture validation skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-canvas-memory-accounting") @("--viewerSkipWebgpuCanvasMemoryAccounting") "trusted WebGPU Blink canvas memory-accounting skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-canvas-memory-accounting") @() "trusted WebGPU Blink canvas memory-accounting skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion") @("--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU Blink copyExternalImage color-conversion setup skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion") @() "trusted WebGPU Blink copyExternalImage color-conversion setup skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation") @("--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU Blink copyExternalImage color-space validation skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation") @() "trusted WebGPU Blink copyExternalImage color-space validation skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") @("--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU Blink copyExternalImage destination validation skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation") @() "trusted WebGPU Blink copyExternalImage destination validation skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation") @("--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU Blink copyExternalImage source validation skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation") @() "trusted WebGPU Blink copyExternalImage source validation skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation") @("--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU Blink copyExternalImage copy-size validation skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation") @() "trusted WebGPU Blink copyExternalImage copy-size validation skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path") @("--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU Blink copyExternalImage combined fast-path experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path") @() "trusted WebGPU Blink copyExternalImage combined fast-path experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-write-texture-layout-validation") @("--viewerSkipWebgpuWriteTextureLayoutValidation") "trusted WebGPU Blink writeTexture layout validation skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-write-texture-layout-validation") @() "trusted WebGPU Blink writeTexture layout validation skip experiment browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-use-counters") @("--viewerSkipWebgpuUseCounters") "trusted WebGPU Blink use-counter skip experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-use-counters") @() "trusted WebGPU Blink use-counter skip experiment browser flags"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-increased-cmd-buffer-slice") @("--enable-features=IncreasedCmdBufferParseSlice") "trusted WebGPU increased command-buffer slice experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d-staging-upload") @("--disable-features=D3DBackingUploadWithUpdateSubresource") "trusted WebGPU D3D staging upload experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment") @("--enable-dawn-features=d3d12_relax_buffer_texture_copy_pitch_and_offset_alignment") "trusted WebGPU D3D12 relaxed copy-alignment experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload") @("--enable-features=IncreasedCmdBufferParseSlice", "--disable-features=D3DBackingUploadWithUpdateSubresource") "trusted WebGPU combined upload/command-buffer experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment-staging-upload") @("--enable-dawn-features=d3d12_relax_buffer_texture_copy_pitch_and_offset_alignment", "--disable-features=D3DBackingUploadWithUpdateSubresource") "trusted WebGPU D3D12 relaxed copy-alignment plus staging-upload experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-remove-gpu-legacy-ipc-hlsl2021") @("--use-webgpu-adapter=d3d11", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021") "trusted WebGPU D3D11 plus Chromium feature interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-cmd-slice-d3d-staging-upload") @("--use-webgpu-adapter=d3d11", "--enable-features=IncreasedCmdBufferParseSlice", "--disable-features=D3DBackingUploadWithUpdateSubresource") "trusted WebGPU D3D11 plus upload/command-buffer interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-ipc-hlsl2021-cmd-slice-staging-upload") @("--use-webgpu-adapter=d3d11", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice", "--disable-features=D3DBackingUploadWithUpdateSubresource") "trusted WebGPU D3D11 plus feature/upload interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice", "--disable-features=WebGPUEnableRangeAnalysisForRobustness") "trusted WebGPU D3D11 DXC/IPC/HLSL/range-analysis interaction experiment"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path") @("--viewerDeferWebgpuPipelineFlush", "--viewerCacheWebgpuBindGroupLayouts", "--viewerSkipWebgpuCommandLabels", "--viewerSkipWebgpuResourceLabels", "--viewerSkipWebgpuShaderSourceNullCheck", "--viewerSkipWebgpuShaderMemoryAccounting", "--viewerSkipWebgpuRedundantPipelineSets", "--viewerSkipWebgpuRedundantBindGroupSets", "--viewerSkipWebgpuRedundantBufferSets", "--viewerSkipWebgpuRedundantRenderStateSets", "--viewerDeferWebgpuQueueFlush", "--viewerDeferWebgpuSubmitFlush", "--viewerSkipWebgpuCanvasTextureValidation", "--viewerSkipWebgpuCanvasMemoryAccounting", "--viewerSkipWebgpuWriteTextureLayoutValidation", "--viewerSkipWebgpuUseCounters") "trusted WebGPU aggressive D3D11 pipeline fast-path viewer flags"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer,skip_validation,disable_robustness", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice", "--disable-features=WebGPUEnableRangeAnalysisForRobustness") "trusted WebGPU aggressive D3D11 pipeline fast-path browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") @("--viewerDeferWebgpuQueueFlush", "--viewerDeferWebgpuSubmitFlush", "--viewerSkipWebgpuCanvasTextureValidation", "--viewerSkipWebgpuCanvasMemoryAccounting", "--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerSkipWebgpuWriteTextureLayoutValidation", "--viewerRejectWebgpuCpuTextureFallback", "--viewerSkipWebgpuUseCounters") "trusted WebGPU aggressive D3D11 upload fast-path viewer flags"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer,skip_validation,disable_robustness", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice", "--disable-features=WebGPUEnableRangeAnalysisForRobustness,D3DBackingUploadWithUpdateSubresource") "trusted WebGPU aggressive D3D11 upload fast-path browser flags"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip interaction experiment"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush") @("--viewerDeferWebgpuPipelineFlush") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus async pipeline flush deferral interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus async pipeline flush deferral interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts") @("--viewerCacheWebgpuBindGroupLayouts") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus bind-group-layout cache interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus bind-group-layout cache interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels") @("--viewerSkipWebgpuCommandLabels") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus command-label skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus command-label skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels") @("--viewerSkipWebgpuResourceLabels") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus resource-label skip interaction experiment"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-shader-source-null-check") @("--viewerSkipWebgpuShaderSourceNullCheck") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus shader-source NUL-check skip interaction experiment"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-shader-memory-accounting") @("--viewerSkipWebgpuShaderMemoryAccounting") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus shader memory-accounting skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus resource-label skip interaction browser flags"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-shader-source-null-check") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus shader-source NUL-check skip interaction browser flags"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-shader-memory-accounting") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus shader memory-accounting skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets") @("--viewerSkipWebgpuRedundantPipelineSets") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus redundant setPipeline skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus redundant setPipeline skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets") @("--viewerSkipWebgpuRedundantBindGroupSets") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus redundant setBindGroup skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus redundant setBindGroup skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-buffer-sets") @("--viewerSkipWebgpuRedundantBufferSets") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus redundant setVertexBuffer/setIndexBuffer skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-buffer-sets") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus redundant setVertexBuffer/setIndexBuffer skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-render-state-sets") @("--viewerSkipWebgpuRedundantRenderStateSets") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus redundant render-state skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-render-state-sets") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus redundant render-state skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush") @("--viewerDeferWebgpuQueueFlush") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus queue-flush deferral interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus queue-flush deferral interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush") @("--viewerDeferWebgpuSubmitFlush") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus submit-flush deferral interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus submit-flush deferral interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation") @("--viewerSkipWebgpuCanvasTextureValidation") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus canvas validation skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus canvas validation skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory") @("--viewerSkipWebgpuCanvasMemoryAccounting") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus canvas memory-accounting skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus canvas memory-accounting skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-color-conv") @("--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage color-conversion setup skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-color-conv") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage color-conversion setup skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-colorspace") @("--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage color-space validation skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-colorspace") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage color-space validation skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-validation") @("--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage destination validation skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-validation") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage destination validation skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-source") @("--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage source validation skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-source") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage source validation skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-copy-size") @("--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage copy-size validation skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-copy-size") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage copy-size validation skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-copy-ext-image-fast-path") @("--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerRejectWebgpuCpuTextureFallback") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage combined fast-path interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-copy-ext-image-fast-path") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus copyExternalImage combined fast-path interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-write-texture-layout-validation") @("--viewerSkipWebgpuWriteTextureLayoutValidation") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus writeTexture layout validation skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-write-texture-layout-validation") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus writeTexture layout validation skip interaction browser flags"
Assert-Flags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters") @("--viewerSkipWebgpuUseCounters") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus use-counter skip interaction experiment"
Assert-BrowserFlags (Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer") "trusted WebGPU D3D11 DXC/flush/fence/clear-skip plus use-counter skip interaction browser flags"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-default").expected_flag_metadata) -contains "gpu_timing_enabled=false") "trusted WebGPU default expected GPU timing disabled metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-dawn-skip-validation").expected_flag_metadata) -contains "gpu_timing_enabled=false") "trusted WebGPU Dawn expected GPU timing disabled metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-pipeline-flush").expected_flag_metadata) -contains "viewer_defer_webgpu_pipeline_flush=true") "trusted WebGPU async pipeline flush deferral expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-cache-bind-group-layouts").expected_flag_metadata) -contains "viewer_cache_webgpu_bind_group_layouts=true") "trusted WebGPU bind-group-layout cache expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-command-labels").expected_flag_metadata) -contains "viewer_skip_webgpu_command_labels=true") "trusted WebGPU command-label skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-resource-labels").expected_flag_metadata) -contains "viewer_skip_webgpu_resource_labels=true") "trusted WebGPU resource-label skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-shader-source-null-check").expected_flag_metadata) -contains "viewer_skip_webgpu_shader_source_null_check=true") "trusted WebGPU shader-source NUL-check skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-shader-memory-accounting").expected_flag_metadata) -contains "viewer_skip_webgpu_shader_memory_accounting=true") "trusted WebGPU shader memory-accounting skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets").expected_flag_metadata) -contains "viewer_skip_webgpu_redundant_pipeline_sets=true") "trusted WebGPU redundant setPipeline skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets").expected_flag_metadata) -contains "viewer_skip_webgpu_redundant_bind_group_sets=true") "trusted WebGPU redundant setBindGroup skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-buffer-sets").expected_flag_metadata) -contains "viewer_skip_webgpu_redundant_buffer_sets=true") "trusted WebGPU redundant setVertexBuffer/setIndexBuffer skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-redundant-render-state-sets").expected_flag_metadata) -contains "viewer_skip_webgpu_redundant_render_state_sets=true") "trusted WebGPU redundant render-state skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-queue-flush").expected_flag_metadata) -contains "viewer_defer_webgpu_queue_flush=true") "trusted WebGPU queue-flush deferral expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-defer-submit-flush").expected_flag_metadata) -contains "viewer_defer_webgpu_submit_flush=true") "trusted WebGPU submit-flush deferral expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-canvas-texture-validation").expected_flag_metadata) -contains "viewer_skip_webgpu_canvas_texture_validation=true") "trusted WebGPU canvas texture validation skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-canvas-memory-accounting").expected_flag_metadata) -contains "viewer_skip_webgpu_canvas_memory_accounting=true") "trusted WebGPU canvas memory-accounting skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_color_conversion=true") "trusted WebGPU copyExternalImage color-conversion setup skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_color_space_validation=true") "trusted WebGPU copyExternalImage color-space validation skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_dest_validation=true") "trusted WebGPU copyExternalImage destination validation skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_source_validation=true") "trusted WebGPU copyExternalImage source validation skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_copy_size_validation=true") "trusted WebGPU copyExternalImage copy-size validation skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_source_validation=true") "trusted WebGPU copyExternalImage combined fast-path expected source metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_dest_validation=true") "trusted WebGPU copyExternalImage combined fast-path expected destination metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_copy_size_validation=true") "trusted WebGPU copyExternalImage combined fast-path expected copy-size metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path").expected_flag_metadata) -contains "viewer_reject_webgpu_cpu_texture_fallback=true") "trusted WebGPU copyExternalImage combined fast-path expected CPU-fallback rejection metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-write-texture-layout-validation").expected_flag_metadata) -contains "viewer_skip_webgpu_write_texture_layout_validation=true") "trusted WebGPU writeTexture layout validation skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-skip-use-counters").expected_flag_metadata) -contains "viewer_skip_webgpu_use_counters=true") "trusted WebGPU use-counter skip expected metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_defer_webgpu_pipeline_flush=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected async pipeline flush metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_cache_webgpu_bind_group_layouts=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected bind-group-layout cache metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_command_labels=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected command-label skip metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_resource_labels=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected resource-label skip metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_shader_source_null_check=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected shader-source NUL-check metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_shader_memory_accounting=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected shader memory-accounting metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_redundant_pipeline_sets=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected redundant setPipeline skip metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_redundant_bind_group_sets=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected redundant setBindGroup skip metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_redundant_buffer_sets=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected redundant setVertexBuffer/setIndexBuffer skip metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_redundant_render_state_sets=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected redundant render-state skip metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_defer_webgpu_queue_flush=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected queue-flush metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_defer_webgpu_submit_flush=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected submit-flush metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_write_texture_layout_validation=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected writeTexture layout validation metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_use_counters=true") "trusted WebGPU aggressive D3D11 pipeline fast-path expected use-counter metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path").expected_flag_metadata) -contains "viewer_defer_webgpu_queue_flush=true") "trusted WebGPU aggressive D3D11 upload fast-path expected queue-flush metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path").expected_flag_metadata) -contains "viewer_defer_webgpu_submit_flush=true") "trusted WebGPU aggressive D3D11 upload fast-path expected submit-flush metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_source_validation=true") "trusted WebGPU aggressive D3D11 upload fast-path expected copyExternalImage source metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_dest_validation=true") "trusted WebGPU aggressive D3D11 upload fast-path expected copyExternalImage destination metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_copy_external_image_copy_size_validation=true") "trusted WebGPU aggressive D3D11 upload fast-path expected copyExternalImage copy-size metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path").expected_flag_metadata) -contains "viewer_skip_webgpu_write_texture_layout_validation=true") "trusted WebGPU aggressive D3D11 upload fast-path expected writeTexture layout validation metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path").expected_flag_metadata) -contains "viewer_reject_webgpu_cpu_texture_fallback=true") "trusted WebGPU aggressive D3D11 upload fast-path expected CPU-fallback rejection metadata"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-default").expected_flag_metadata) -contains "viewer_trace_webgpu_queue=false") "trusted WebGPU default expected queue trace metadata is off for performance runs"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-default").expected_flag_metadata) -contains "profile_cache_mode=explicit-reuse") "trusted WebGPU default expected profile-cache mode"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-default").expected_flag_metadata) -contains "profile_cache_key=dryrun-trusted-webgpu-cache") "trusted WebGPU default expected profile-cache key"
Assert-True (@((Get-Experiment $TrustedWebGpu "fork-viewer-exp-default").expected_flag_metadata) -contains "profile_reuse_enabled=true") "trusted WebGPU default expected profile-cache reuse"

$ExpectedTrustedWebGpuResults = $ExpectedWebGpuExperiments.Count * $RequiredScenes.Count
Assert-Count @($TrustedWebGpu.result_files.all) $ExpectedTrustedWebGpuResults "trusted WebGPU result files"
Assert-Count @($TrustedWebGpu.artifact_metadata.results.all) $ExpectedTrustedWebGpuResults "trusted WebGPU result metadata"

if ($OfficialText -match "exited with code" -or
    $TrustedText -match "exited with code" -or
    $TrustedWebGpuText -match "exited with code") {
  throw "Dry-run command output unexpectedly contained a command failure."
}

$Completed = $true
} finally {
  Restore-DryRunManifest $OfficialManifestPath $OfficialBackupPath $HadOfficialManifest
  Restore-DryRunManifest $TrustedManifestPath $TrustedBackupPath $HadTrustedManifest
  Restore-DryRunManifest $TrustedWebGlManifestPath $TrustedWebGlBackupPath $HadTrustedWebGlManifest
  Restore-DryRunManifest $TrustedWebGpuManifestPath $TrustedWebGpuBackupPath $HadTrustedWebGpuManifest
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

if ($Completed) {
  Assert-Equal (Test-Path -LiteralPath $OfficialManifestPath) $HadOfficialManifest "official dry-run manifest restored existence"
  Assert-Equal (Test-Path -LiteralPath $TrustedManifestPath) $HadTrustedManifest "trusted dry-run manifest restored existence"
  Assert-Equal (Test-Path -LiteralPath $TrustedWebGlManifestPath) $HadTrustedWebGlManifest "trusted WebGL2 dry-run manifest restored existence"
  Assert-Equal (Test-Path -LiteralPath $TrustedWebGpuManifestPath) $HadTrustedWebGpuManifest "trusted WebGPU dry-run manifest restored existence"
  if ($HadOfficialManifest) {
    Assert-Equal (Get-Content -LiteralPath $OfficialManifestPath -Raw) $OriginalOfficialManifestText "official dry-run manifest restored contents"
  }
  if ($HadTrustedManifest) {
    Assert-Equal (Get-Content -LiteralPath $TrustedManifestPath -Raw) $OriginalTrustedManifestText "trusted dry-run manifest restored contents"
  }
  if ($HadTrustedWebGlManifest) {
    Assert-Equal (Get-Content -LiteralPath $TrustedWebGlManifestPath -Raw) $OriginalTrustedWebGlManifestText "trusted WebGL2 dry-run manifest restored contents"
  }
  if ($HadTrustedWebGpuManifest) {
    Assert-Equal (Get-Content -LiteralPath $TrustedWebGpuManifestPath -Raw) $OriginalTrustedWebGpuManifestText "trusted WebGPU dry-run manifest restored contents"
  }
  Assert-True (-not (Test-Path -LiteralPath $TempDir)) "temporary dry-run manifest test directory was removed"
}

Write-Host "Official and trusted dry-run manifests are structurally valid, official/trusted input and package preflights reject bad supplied artifacts, and report artifacts are restored after the test."

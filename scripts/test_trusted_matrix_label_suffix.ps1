[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\trusted-matrix-label-suffix-test"
$TrustedManifestPath = Join-Path $Root "benchmarks\reports\trusted-experiment-matrix-manifest.dry-run.json"
$TrustedWebGlManifestPath = Join-Path $Root "benchmarks\reports\trusted-experiment-matrix-webgl2-manifest.dry-run.json"
$TrustedWebGpuManifestPath = Join-Path $Root "benchmarks\reports\trusted-experiment-matrix-webgpu-manifest.dry-run.json"
$TrustedBackupPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.dry-run.backup.json"
$TrustedWebGlBackupPath = Join-Path $TempDir "trusted-experiment-matrix-webgl2-manifest.dry-run.backup.json"
$TrustedWebGpuBackupPath = Join-Path $TempDir "trusted-experiment-matrix-webgpu-manifest.dry-run.backup.json"

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) {
    throw $Message
  }
}

function Assert-Equal {
  param(
    [AllowNull()][object]$Actual,
    [AllowNull()][object]$Expected,
    [string]$Message
  )
  if ($Actual -ne $Expected) {
    throw "$Message. Expected '$Expected' but got '$Actual'."
  }
}

function Assert-Matches {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Message
  )
  if ($Text -notmatch $Pattern) {
    throw "$Message. Pattern: $Pattern"
  }
}

function Backup-Manifest {
  param(
    [string]$PathValue,
    [string]$BackupPath
  )

  if (Test-Path -LiteralPath $PathValue -PathType Leaf) {
    Copy-Item -LiteralPath $PathValue -Destination $BackupPath -Force
    return $true
  }
  return $false
}

function Restore-Manifest {
  param(
    [string]$PathValue,
    [string]$BackupPath,
    [bool]$HadOriginal
  )

  if ($HadOriginal) {
    Copy-Item -LiteralPath $BackupPath -Destination $PathValue -Force
  } elseif (Test-Path -LiteralPath $PathValue -PathType Leaf) {
    Remove-Item -LiteralPath $PathValue -Force
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

$HadTrustedManifest = $false
$HadTrustedWebGlManifest = $false
$HadTrustedWebGpuManifest = $false
try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
  $HadTrustedManifest = Backup-Manifest $TrustedManifestPath $TrustedBackupPath
  $HadTrustedWebGlManifest = Backup-Manifest $TrustedWebGlManifestPath $TrustedWebGlBackupPath
  $HadTrustedWebGpuManifest = Backup-Manifest $TrustedWebGpuManifestPath $TrustedWebGpuBackupPath

  $Output = & (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1") `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -Renderer webgl2 `
    -Scenes many-draw-calls `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -IncludeDefault `
    -Precompile `
    -PrerenderFrames 2 `
    -LabelSuffix "-warmup-precompile-prerender2" `
    -DryRun *>&1
  $Text = ($Output | ForEach-Object { [string]$_ }) -join "`n"

  Assert-Matches $Text "--variant\s+fork-viewer-exp-default-warmup-precompile-prerender2\b" "trusted matrix did not suffix benchmark variant labels"
  Assert-Matches $Text "--output\s+.*fork-viewer-exp-default-warmup-precompile-prerender2-many-draw-calls-webgl2\.json\b" "trusted matrix did not suffix result filenames"
  Assert-Matches $Text "--expectedFlagMetadata\s+resource_warmup_enabled=true\b" "trusted matrix did not validate resource warmup metadata"
  Assert-Matches $Text "--expectedFlagMetadata\s+resource_warmup_prerender_frames=2\b" "trusted matrix did not validate prerender-frame metadata"

  Assert-True (Test-Path -LiteralPath $TrustedManifestPath -PathType Leaf) "trusted dry-run manifest was not written"
  $Manifest = Get-Content -LiteralPath $TrustedManifestPath -Raw | ConvertFrom-Json
  Assert-Equal $Manifest.options.label_suffix "-warmup-precompile-prerender2" "trusted manifest did not record label suffix"
  $Experiment = @($Manifest.experiments | Where-Object { [string]$_.base_label -eq "fork-viewer-exp-default" }) | Select-Object -First 1
  Assert-True ($null -ne $Experiment) "trusted manifest did not retain the base experiment label"
  Assert-Equal $Experiment.label "fork-viewer-exp-default-warmup-precompile-prerender2" "trusted manifest did not suffix experiment label"
  Assert-Equal $Experiment.label_suffix "-warmup-precompile-prerender2" "trusted manifest did not record experiment label suffix"
  Assert-True (@($Experiment.expected_flag_metadata) -contains "resource_warmup_enabled=true") "trusted manifest did not record warmup expected metadata"
  Assert-True (@($Experiment.result_files | Where-Object { [string]$_ -match "fork-viewer-exp-default-warmup-precompile-prerender2-many-draw-calls-webgl2\.json$" }).Count -eq 1) "trusted manifest did not suffix result file paths"

  $FilterOutput = & (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1") `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -Renderer webgpu `
    -Scenes many-draw-calls `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -IncludeDefault `
    -IncludeWebGpuDawnExperiments `
    -ExperimentLabelFilter "fork-viewer-exp-default,fork-viewer-exp-webgpu-dawn-use-dxc" `
    -DisableGpuTiming `
    -DryRun *>&1
  $FilterText = ($FilterOutput | ForEach-Object { [string]$_ }) -join "`n"

  Assert-Matches $FilterText "Filtered trusted experiment matrix to 2 experiment\(s\)" "trusted matrix did not report focused experiment filtering"
  Assert-Matches $FilterText "--variant\s+fork-viewer-exp-default\b" "trusted matrix filter dropped the default experiment"
  Assert-Matches $FilterText "--variant\s+fork-viewer-exp-webgpu-dawn-use-dxc\b" "trusted matrix filter dropped the requested Dawn DXC experiment"
  if ($FilterText -match "--variant\s+fork-viewer-exp-webgpu-dawn-skip-validation") {
    throw "trusted matrix emitted an experiment excluded by ExperimentLabelFilter."
  }

  $FilterManifest = Get-Content -LiteralPath $TrustedManifestPath -Raw | ConvertFrom-Json
  Assert-Equal (@($FilterManifest.experiments).Count) 2 "trusted manifest did not record only filtered experiments"
  Assert-True (@($FilterManifest.options.experiment_label_filter) -contains "fork-viewer-exp-default") "trusted manifest did not record default experiment filter"
  Assert-True (@($FilterManifest.options.experiment_label_filter) -contains "fork-viewer-exp-webgpu-dawn-use-dxc") "trusted manifest did not record Dawn DXC experiment filter"
  Assert-True (@($FilterManifest.experiments | ForEach-Object { [string]$_.base_label }) -contains "fork-viewer-exp-webgpu-dawn-use-dxc") "trusted manifest did not include requested Dawn DXC experiment"
  Assert-True (-not (@($FilterManifest.experiments | ForEach-Object { [string]$_.base_label }) -contains "fork-viewer-exp-webgpu-dawn-skip-validation")) "trusted manifest included an experiment excluded by ExperimentLabelFilter"

  $BundleOutput = & (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1") `
    -Browser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
    -BuildArgs ".\src\out\ReleaseViewerDefault\args.gn" `
    -PackageDir ".\benchmarks\packages\viewer-default" `
    -Renderer webgpu `
    -Scenes many-draw-calls `
    -Duration 1 `
    -Warmup 1 `
    -Complexity 2 `
    -IncludeDefault `
    -WebGpuBundleMode static `
    -DisableGpuTiming `
    -DryRun *>&1
  $BundleText = ($BundleOutput | ForEach-Object { [string]$_ }) -join "`n"

  Assert-Matches $BundleText "--variant\s+fork-viewer-exp-default-bundlegroup-static\b" "trusted matrix did not isolate WebGPU BundleGroup variants with a label suffix"
  Assert-Matches $BundleText "--webgpuBundleMode\s+static\b" "trusted matrix did not forward WebGPU BundleGroup scene mode"
  Assert-Matches $BundleText "--expectedFlagMetadata\s+webgpu_bundle_mode=static\b" "trusted matrix did not validate WebGPU BundleGroup metadata"

  $BundleManifest = Get-Content -LiteralPath $TrustedManifestPath -Raw | ConvertFrom-Json
  Assert-Equal $BundleManifest.options.label_suffix "-bundlegroup-static" "trusted manifest did not auto-label WebGPU BundleGroup mode"
  Assert-Equal $BundleManifest.options.webgpu_bundle_mode "static" "trusted manifest did not record WebGPU BundleGroup mode"
  $BundleExperiment = @($BundleManifest.experiments | Where-Object { [string]$_.base_label -eq "fork-viewer-exp-default" }) | Select-Object -First 1
  Assert-True ($null -ne $BundleExperiment) "trusted BundleGroup manifest did not retain the base experiment label"
  Assert-Equal $BundleExperiment.label "fork-viewer-exp-default-bundlegroup-static" "trusted BundleGroup manifest did not suffix experiment label"
  Assert-True (@($BundleExperiment.expected_flag_metadata) -contains "webgpu_bundle_mode=static") "trusted BundleGroup manifest did not record expected metadata"
  Assert-True (@($BundleExperiment.result_files | Where-Object { [string]$_ -match "fork-viewer-exp-default-bundlegroup-static-many-draw-calls-webgpu\.json$" }).Count -eq 1) "trusted BundleGroup manifest did not suffix result file paths"
} finally {
  Restore-Manifest $TrustedManifestPath $TrustedBackupPath $HadTrustedManifest
  Restore-Manifest $TrustedWebGlManifestPath $TrustedWebGlBackupPath $HadTrustedWebGlManifest
  Restore-Manifest $TrustedWebGpuManifestPath $TrustedWebGpuBackupPath $HadTrustedWebGpuManifest
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Trusted experiment matrix labels resource-warmup dry-run variants without mixing warmed and unwarmed artifacts, and filters focused experiment labels."

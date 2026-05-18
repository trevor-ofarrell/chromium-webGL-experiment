[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Browser,
  [string]$BuildArgs = "",
  [string]$PackageDir = "",
  [string]$ForkRevision = "",
  [string]$Renderer = "webgl2",
  [string[]]$Scenes = @(
    "many-draw-calls",
    "instancing",
    "shader-heavy",
    "texture-streaming",
    "postprocessing",
    "large-static",
    "gltf-loader-stress"
  ),
  [int]$Duration = 60,
  [int]$Warmup = 10,
  [string[]]$AngleBackend = @(),
  [switch]$IncludeDefault,
  [switch]$IncludeAggressiveGpu,
  [switch]$IncludeInProcessGpu,
  [switch]$IncludeSingleProcess,
  [switch]$IncludeReservedNoopGates,
  [switch]$Precompile,
  [int]$PrerenderFrames = 0,
  [double]$Complexity = 1.0,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$RawDir = Join-Path $Root "benchmarks\raw"
$ReportDir = Join-Path $Root "benchmarks\reports"
New-Item -ItemType Directory -Path $RawDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

function Resolve-RepoPath {
  param([string]$PathValue)
  if (-not $PathValue) {
    return ""
  }
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return (Join-Path $Root $PathValue)
}

function Require-PackageDirectory {
  param(
    [string]$PathValue,
    [string]$Label,
    [string]$ExpectedBrowser = ""
  )

  $Resolved = Resolve-RepoPath $PathValue
  if ($DryRun -or -not $Resolved) {
    return $Resolved
  }

  if (-not (Test-Path -LiteralPath $Resolved -PathType Container)) {
    throw "$Label not found: $Resolved"
  }

  foreach ($RequiredRelativePath in @("content_shell.exe", "viewer\index.html", "run_viewer.ps1")) {
    $RequiredPath = Join-Path $Resolved $RequiredRelativePath
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
      throw "$Label is incomplete; missing $RequiredRelativePath under $Resolved"
    }
  }

  $Files = @(Get-ChildItem -LiteralPath $Resolved -Recurse -File -ErrorAction SilentlyContinue)
  $SizeBytes = ($Files | Measure-Object -Property Length -Sum).Sum
  if ($Files.Count -eq 0 -or $SizeBytes -le 0) {
    throw "$Label is empty: $Resolved"
  }

  if ($ExpectedBrowser) {
    $PackagedBrowser = Join-Path $Resolved "content_shell.exe"
    $ExpectedBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ExpectedBrowser).Hash
    $PackagedBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PackagedBrowser).Hash
    if ($PackagedBrowserHash -ne $ExpectedBrowserHash) {
      throw "$Label executable does not match expected browser: $PackagedBrowser"
    }
  }

  return $Resolved
}

function Require-InputFile {
  param(
    [string]$PathValue,
    [string]$Label
  )

  $Resolved = Resolve-RepoPath $PathValue
  if ($DryRun) {
    return $Resolved
  }

  if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
    throw "$Label not found: $Resolved"
  }
  $Item = Get-Item -LiteralPath $Resolved
  if ($Item.Length -le 0) {
    throw "$Label is empty: $Resolved"
  }

  return $Resolved
}

function Format-Command {
  param([object[]]$Command)
  return ($Command | ForEach-Object {
    $Text = [string]$_
    if ($Text -match "\s") {
      return '"' + ($Text -replace '"', '\"') + '"'
    }
    return $Text
  }) -join " "
}

function Invoke-CommandChecked {
  param([object[]]$Command)
  if ($DryRun) {
    Write-Host "[dry-run] $(Format-Command $Command)"
    return
  }
  $CommandArgs = @($Command | Select-Object -Skip 1)
  $Executable = [string]$Command[0]
  if ([System.IO.Path]::GetExtension($Executable) -ieq ".ps1") {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Executable @CommandArgs
  } else {
    & $Executable @CommandArgs
  }
  if ($LASTEXITCODE -ne 0) {
    throw "$($Command[0]) exited with code $LASTEXITCODE"
  }
}

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

function Get-FileMetadata {
  param([string]$PathValue)
  if (-not $PathValue) {
    return [pscustomobject]@{
      path = $null
      exists = $false
      size_bytes = $null
      sha256 = $null
    }
  }

  $Resolved = Resolve-RepoPath $PathValue
  $Exists = Test-Path -LiteralPath $Resolved -PathType Leaf
  return [pscustomobject]@{
    path = $Resolved
    exists = $Exists
    size_bytes = if ($Exists) { (Get-Item -LiteralPath $Resolved).Length } else { $null }
    sha256 = if ($Exists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Resolved).Hash.ToLowerInvariant() } else { $null }
  }
}

function Get-FileMetadataList {
  param([string[]]$Paths)
  return @($Paths | ForEach-Object { Get-FileMetadata $_ })
}

function Get-DirectoryMetadata {
  param([string]$PathValue)
  if (-not $PathValue) {
    return [pscustomobject]@{
      path = $null
      exists = $false
      file_count = $null
      size_bytes = $null
    }
  }

  $Resolved = Resolve-RepoPath $PathValue
  $Exists = Test-Path -LiteralPath $Resolved -PathType Container
  $Files = if ($Exists) { @(Get-ChildItem -LiteralPath $Resolved -Recurse -File -ErrorAction SilentlyContinue) } else { @() }
  $Size = if ($Exists) {
    ($Files | Measure-Object -Property Length -Sum).Sum
  } else {
    $null
  }
  return [pscustomobject]@{
    path = $Resolved
    exists = $Exists
    file_count = if ($Exists) { $Files.Count } else { $null }
    size_bytes = $Size
  }
}

function Get-ViewerForkRevision {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
  $PatchHash = Get-ShortSha256 $PatchPath
  return "$ChromiumRevision+viewerpatch-$PatchHash"
}

function Invoke-BenchmarkSuiteValidation {
  param(
    [string]$Variant,
    [string[]]$Files,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @()
  )

  $Command = @(
    "node",
    (Join-Path $Root "scripts\validate_benchmark_suite.mjs"),
    "--renderer", $Renderer,
    "--variant", $Variant,
    "--expectedScenes", ($Scenes -join ","),
    "--requireCheckout",
    "--requireBuildArgs",
    "--forbidSmoke",
    "--rejectSoftwareRendering",
    "--requireGpuMetadata",
    "--expectedMeasuredSeconds", [string]$Duration,
    "--expectedWarmupSeconds", [string]$Warmup,
    "--requireForkRevision",
    "--expectedForkRevision", $ForkRevision
  )
  if ($ExpectedChromiumRevision) {
    $Command += @("--expectedChromiumRevision", $ExpectedChromiumRevision)
  }
  if ($ExpectedBrowser) {
    $Command += @("--expectedBrowser", $ExpectedBrowser)
  }
  if ($PackageDir) {
    $Command += "--requirePackageSize"
  }
  foreach ($Metadata in $ExpectedFlagMetadata) {
    $Command += @("--expectedFlagMetadata", $Metadata)
  }
  foreach ($Flag in $RequiredBrowserFlags) {
    $Command += @("--requiredBrowserFlag", $Flag)
  }
  $Command += $Files
  Invoke-CommandChecked $Command
}

function Convert-MetadataValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) {
    return "null"
  }
  if ($Value -is [bool]) {
    return $Value.ToString().ToLowerInvariant()
  }
  return [string]$Value
}

function Get-ExperimentExpectedFlagMetadata {
  param([object]$Experiment)

  $Metadata = [ordered]@{
    viewer_mode = $true
    viewer_block_external_navigation = $true
    viewer_trusted_content = $true
    viewer_aggressive_gpu = $false
    viewer_relaxed_webgl_validation = $false
    viewer_in_process_gpu = $false
    viewer_single_process = $false
    viewer_force_angle_backend = $null
    requested_angle_backend = $null
    viewer_disable_unneeded_blink_features = $false
    viewer_direct_gpu_presentation = $false
  }

  for ($Index = 0; $Index -lt $Experiment.Flags.Count; $Index += 1) {
    switch ($Experiment.Flags[$Index]) {
      "--viewerAggressiveGpu" { $Metadata.viewer_aggressive_gpu = $true }
      "--viewerRelaxedWebglValidation" { $Metadata.viewer_relaxed_webgl_validation = $true }
      "--viewerInProcessGpu" { $Metadata.viewer_in_process_gpu = $true }
      "--viewerSingleProcess" { $Metadata.viewer_single_process = $true }
      "--viewerDisableUnneededBlinkFeatures" { $Metadata.viewer_disable_unneeded_blink_features = $true }
      "--viewerDirectGpuPresentation" { $Metadata.viewer_direct_gpu_presentation = $true }
      "--viewerForceAngleBackend" {
        $Index += 1
        if ($Index -ge $Experiment.Flags.Count) {
          throw "Experiment $($Experiment.Label) is missing the value for --viewerForceAngleBackend."
        }
        $Metadata.viewer_force_angle_backend = $Experiment.Flags[$Index]
        $Metadata.requested_angle_backend = $Experiment.Flags[$Index]
      }
    }
  }

  return @($Metadata.GetEnumerator() | ForEach-Object {
    "$($_.Key)=$(Convert-MetadataValue $_.Value)"
  })
}

function New-Experiment {
  param(
    [string]$Label,
    [string]$Description,
    [string[]]$Flags = @()
  )
  return [pscustomobject]@{
    Label = $Label
    Description = $Description
    Flags = $Flags
  }
}

function Get-ExperimentResultFiles {
  param([object]$Experiment)
  return @($Scenes | ForEach-Object {
    Join-Path $RawDir "$($Experiment.Label)-$_-$Renderer.json"
  })
}

function Get-ExperimentManifestEntry {
  param([object]$Experiment)
  return [pscustomobject]@{
    label = $Experiment.Label
    description = $Experiment.Description
    flags = @($Experiment.Flags)
    expected_flag_metadata = @(Get-ExperimentExpectedFlagMetadata $Experiment)
    result_files = @(Get-ExperimentResultFiles $Experiment)
  }
}

function Get-ExperimentResultMetadata {
  param([object]$Experiment)
  return [pscustomobject]@{
    label = $Experiment.Label
    files = Get-FileMetadataList @(Get-ExperimentResultFiles $Experiment)
  }
}

function Write-TrustedExperimentManifest {
  param([string]$Phase = "planned")

  $ManifestName = if ($DryRun) {
    "trusted-experiment-matrix-manifest.dry-run.json"
  } else {
    "trusted-experiment-matrix-manifest.json"
  }
  $ManifestPath = Join-Path $ReportDir $ManifestName
  $SummaryPath = Join-Path $ReportDir "trusted-experiment-matrix-$Renderer-summary.md"
  $ComparePath = Join-Path $ReportDir "trusted-experiment-matrix-$Renderer-comparison.md"
  $ExperimentEntries = @($Experiments | ForEach-Object { Get-ExperimentManifestEntry $_ })
  $AllResultFiles = @($ExperimentEntries | ForEach-Object { $_.result_files })
  $ExperimentResultMetadata = @($Experiments | ForEach-Object { Get-ExperimentResultMetadata $_ })

  $Manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = [bool]$DryRun
    phase = $Phase
    chromium_revision = Get-GitRevision (Join-Path $Root "src")
    fork_revision = $ForkRevision
    browser = $Browser
    build_args = $BuildArgs
    package_dir = $PackageDir
    renderer = $Renderer
    scenes = $Scenes
    suite_validation = [pscustomobject]@{
      expected_scenes = $Scenes
      require_checkout = $true
      require_build_args = $true
      require_fork_revision = $true
      expected_fork_revision = $ForkRevision
      forbid_smoke = $true
      reject_software_rendering = $true
      require_gpu_metadata = $true
      expected_chromium_revision = $ChromiumRevision
      expected_browser = $Browser
      expected_measured_seconds = $Duration
      expected_warmup_seconds = $Warmup
      exact_scene_output_files = $true
      expected_flag_metadata = $true
      required_browser_flags = @($RequiredBrowserFlags)
    }
    options = [pscustomobject]@{
      duration = $Duration
      warmup = $Warmup
      precompile = [bool]$Precompile
      prerender_frames = $PrerenderFrames
      complexity = $Complexity
    }
    experiments = $ExperimentEntries
    result_files = [pscustomobject]@{
      all = $AllResultFiles
      by_experiment = $ExperimentEntries
    }
    report_files = [pscustomobject]@{
      summary = $SummaryPath
      comparison = $ComparePath
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        browser = Get-FileMetadata $Browser
        build_args = Get-FileMetadata $BuildArgs
        viewer_patch = Get-FileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
        package = Get-DirectoryMetadata $PackageDir
      }
      results = [pscustomobject]@{
        all = Get-FileMetadataList $AllResultFiles
        by_experiment = $ExperimentResultMetadata
      }
      reports = [pscustomobject]@{
        summary = Get-FileMetadata $SummaryPath
        comparison = Get-FileMetadata $ComparePath
      }
    }
  }

  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  Write-Host "Wrote $ManifestPath"
}

if (-not $BuildArgs) {
  throw "BuildArgs is required so trusted experiment results include reproducible build_args_hash metadata."
}
$Browser = Require-InputFile $Browser "Browser executable"
$BuildArgs = Require-InputFile $BuildArgs "Build args"
$PackageDir = Require-PackageDirectory $PackageDir "Trusted package directory" $Browser
$ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
if (-not $ForkRevision) {
  $ForkRevision = Get-ViewerForkRevision
}
Write-Host "Viewer fork revision: $ForkRevision"
$RequiredBrowserFlags = @("--disable-software-rasterizer")

$Experiments = [System.Collections.Generic.List[object]]::new()
if ($IncludeDefault) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-default" "Default trusted viewer profile for experiment comparisons")) | Out-Null
}
if ($IncludeAggressiveGpu) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-aggressive-gpu" "Trusted aggressive GPU alias bundle" @("--viewerAggressiveGpu"))) | Out-Null
}
if ($IncludeInProcessGpu) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-in-process-gpu" "Trusted in-process GPU experiment" @("--viewerInProcessGpu"))) | Out-Null
}
if ($IncludeSingleProcess) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-single-process" "Trusted single-process experiment" @("--viewerSingleProcess"))) | Out-Null
}
foreach ($Backend in $AngleBackend) {
  if ($Backend -and $Backend -ne "default") {
    $Experiments.Add((New-Experiment "fork-viewer-exp-angle-$Backend" "Trusted ANGLE backend experiment: $Backend" @("--viewerForceAngleBackend", $Backend))) | Out-Null
  }
}
if ($IncludeReservedNoopGates) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" "Trusted pass-through command decoder alias for WebGL validation-overhead measurement" @("--viewerRelaxedWebglValidation"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" "Reserved gate; should remain behaviorally no-op until source experiment exists" @("--viewerDisableUnneededBlinkFeatures"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" "Reserved gate; should remain behaviorally no-op until source experiment exists" @("--viewerDirectGpuPresentation"))) | Out-Null
}

if ($Experiments.Count -eq 0) {
  throw "No experiments selected. Add -IncludeDefault, -IncludeAggressiveGpu, -IncludeInProcessGpu, -IncludeSingleProcess, -AngleBackend <value>, or -IncludeReservedNoopGates."
}

$ResultFiles = [System.Collections.Generic.List[string]]::new()
foreach ($Experiment in $Experiments) {
  $ExperimentFiles = [System.Collections.Generic.List[string]]::new()
  foreach ($Scene in $Scenes) {
    $Output = Join-Path $RawDir "$($Experiment.Label)-$Scene-$Renderer.json"
    $ExperimentFiles.Add($Output) | Out-Null
    $Command = @(
      "node",
      (Join-Path $Root "scripts\run_benchmark.mjs"),
      "--browser", $Browser,
      "--variant", $Experiment.Label,
      "--scene", $Scene,
      "--renderer", $Renderer,
      "--complexity", [string]$Complexity,
      "--duration", [string]$Duration,
      "--warmup", [string]$Warmup,
      "--forkRevision", $ForkRevision,
      "--viewerMode",
      "--viewerTrustedContent",
      "--output", $Output
    )
    if ($BuildArgs) {
      $Command += @("--buildArgs", $BuildArgs)
    }
    if ($PackageDir) {
      $Command += @("--packageDir", $PackageDir)
    }
    if ($Precompile) {
      $Command += "--precompile"
    }
    if ($PrerenderFrames -gt 0) {
      $Command += @("--prerenderFrames", [string]$PrerenderFrames)
    }
    foreach ($Flag in $Experiment.Flags) {
      $Command += $Flag
    }

    Invoke-CommandChecked $Command
  }
  Invoke-BenchmarkSuiteValidation `
    -Variant $Experiment.Label `
    -Files @($ExperimentFiles) `
    -ExpectedChromiumRevision $ChromiumRevision `
    -ExpectedBrowser $Browser `
    -ExpectedFlagMetadata (Get-ExperimentExpectedFlagMetadata $Experiment) `
    -RequiredBrowserFlags $RequiredBrowserFlags
  foreach ($File in $ExperimentFiles) {
    $ResultFiles.Add($File) | Out-Null
  }
}

$SummaryPath = Join-Path $ReportDir "trusted-experiment-matrix-$Renderer-summary.md"
$SummaryCommand = @(
  "node",
  (Join-Path $Root "scripts\summarize_results.mjs")
)
foreach ($File in $ResultFiles) {
  $SummaryCommand += $File
}
$SummaryCommand += @("--output", $SummaryPath)
Invoke-CommandChecked $SummaryCommand

$ComparePath = Join-Path $ReportDir "trusted-experiment-matrix-$Renderer-comparison.md"
$CompareCommand = @(
  "node",
  (Join-Path $Root "scripts\compare_results.mjs")
)
foreach ($File in $ResultFiles) {
  $CompareCommand += $File
}
$CompareCommand += @("--output", $ComparePath)
Invoke-CommandChecked $CompareCommand

if ($DryRun) {
  Write-TrustedExperimentManifest -Phase "planned"
} else {
  Write-TrustedExperimentManifest -Phase "completed"
}

Write-Host "Trusted experiment matrix completed."

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BaselineBrowser,
  [Parameter(Mandatory = $true)]
  [string]$ForkBrowser,
  [string]$Renderer = "webgpu",
  [string[]]$Scenes = @(
    "many-draw-calls",
    "instancing",
    "shader-heavy",
    "texture-streaming",
    "postprocessing",
    "large-static",
    "gltf-loader-stress"
  ),
  [int]$Repeats = 1,
  [int]$Duration = 120,
  [int]$Warmup = 20,
  [double]$Complexity = 2.0,
  [string]$BaselineLabel = "baseline-content-shell-paired",
  [string]$ForkLabel = "fork-viewer-paired",
  [string]$BaselineBuildArgs = "",
  [string]$ForkBuildArgs = "",
  [string]$BaselinePackageDir = "",
  [string]$ForkPackageDir = "",
  [string]$ForkRevision = "",
  [ValidateSet("baseline-first", "fork-first", "alternate")]
  [string]$Order = "alternate",
  [string[]]$BaselineBenchmarkArg = @(),
  [string[]]$ForkBenchmarkArg = @(),
  [string[]]$BaselineBrowserFlag = @(),
  [string[]]$ForkBrowserFlag = @(),
  [switch]$DisableGpuTiming,
  [switch]$RequireCheckout,
  [switch]$RequireBuildArgs,
  [switch]$RequireGpuMetadata,
  [switch]$RequirePackageSize,
  [switch]$RequireFrameTimes,
  [switch]$RejectSoftwareRendering,
  [switch]$RejectGpuInstability,
  [string]$Manifest = "",
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
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $Root $PathValue))
}

function Require-File {
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
  if ((Get-Item -LiteralPath $Resolved).Length -le 0) {
    throw "$Label is empty: $Resolved"
  }
  return $Resolved
}

function Require-Directory {
  param(
    [string]$PathValue,
    [string]$Label
  )
  if (-not $PathValue) {
    return ""
  }
  $Resolved = Resolve-RepoPath $PathValue
  if ($DryRun) {
    return $Resolved
  }
  if (-not (Test-Path -LiteralPath $Resolved -PathType Container)) {
    throw "$Label not found: $Resolved"
  }
  return $Resolved
}

function Get-Sha256OrEmpty {
  param([string]$PathValue)
  if (-not $PathValue -or $DryRun) {
    return ""
  }
  return ((Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash).ToLowerInvariant()
}

function ConvertTo-SafeLabel {
  param([string]$Value)
  $Safe = ([string]$Value) -replace '[^A-Za-z0-9._-]', '-'
  $Safe = $Safe.Trim("-")
  if (-not $Safe) {
    throw "Labels must contain at least one ASCII letter, number, dot, underscore, or hyphen."
  }
  return $Safe
}

function Get-RepeatLabel {
  param(
    [string]$BaseLabel,
    [int]$Repeat
  )
  if ($Repeats -eq 1) {
    return $BaseLabel
  }
  return "$BaseLabel-r$Repeat"
}

function Get-PairOrder {
  param(
    [int]$Repeat,
    [int]$SceneIndex
  )
  if ($Order -eq "baseline-first") {
    return @("baseline", "fork")
  }
  if ($Order -eq "fork-first") {
    return @("fork", "baseline")
  }
  $PairIndex = (($Repeat - 1) * $Scenes.Count) + $SceneIndex
  if (($PairIndex % 2) -eq 0) {
    return @("baseline", "fork")
  }
  return @("fork", "baseline")
}

function New-BenchmarkCommand {
  param(
    [string]$Side,
    [string]$Scene,
    [string]$Variant,
    [string]$Output
  )

  $Browser = if ($Side -eq "baseline") { $BaselineBrowser } else { $ForkBrowser }
  $BuildArgs = if ($Side -eq "baseline") { $BaselineBuildArgs } else { $ForkBuildArgs }
  $PackageDir = if ($Side -eq "baseline") { $BaselinePackageDir } else { $ForkPackageDir }
  $ExtraArgs = if ($Side -eq "baseline") { $BaselineBenchmarkArg } else { $ForkBenchmarkArg }
  $ExtraBrowserFlags = if ($Side -eq "baseline") { $BaselineBrowserFlag } else { $ForkBrowserFlag }

  $Command = @(
    (Join-Path $Root "scripts\run_benchmark.mjs"),
    "--browser", $Browser,
    "--variant", $Variant,
    "--scene", $Scene,
    "--renderer", $Renderer,
    "--complexity", [string]$Complexity,
    "--duration", [string]$Duration,
    "--warmup", [string]$Warmup,
    "--output", $Output
  )
  if ($BuildArgs) {
    $Command += @("--buildArgs", $BuildArgs)
  }
  if ($PackageDir) {
    $Command += @("--packageDir", $PackageDir)
  }
  if ($Side -eq "fork" -and $ForkRevision) {
    $Command += @("--forkRevision", $ForkRevision)
  }
  if ($DisableGpuTiming) {
    $Command += "--disableGpuTiming"
  }
  foreach ($Arg in $ExtraArgs) {
    $Command += $Arg
  }
  foreach ($Flag in $ExtraBrowserFlags) {
    $Command += @("--browser-flag", $Flag)
  }
  return $Command
}

function Invoke-Node {
  param([object[]]$Command)
  Write-Host ("node " + ($Command -join " "))
  if ($DryRun) {
    return
  }
  node @Command
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE."
  }
}

function Test-ResultGpuMetadata {
  param([string]$PathValue)
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }
  foreach ($Key in @("gpu_name", "driver_version", "angle_backend")) {
    $Value = $Result.$Key
    if ($Value -is [string] -and $Value.Trim().Length -gt 0) {
      return $true
    }
  }
  return $false
}

if ($Renderer -notin @("webgl2", "webgpu")) {
  throw "-Renderer must be webgl2 or webgpu."
}
if ($Scenes.Count -eq 0) {
  throw "-Scenes must contain at least one scene."
}
if (($Scenes | Select-Object -Unique).Count -ne $Scenes.Count) {
  throw "-Scenes contains duplicate scene names."
}
if ($Repeats -le 0) {
  throw "-Repeats must be greater than zero."
}
if ($Duration -le 0 -or $Warmup -lt 0) {
  throw "-Duration must be greater than zero and -Warmup must be non-negative."
}
if ($Complexity -le 0) {
  throw "-Complexity must be greater than zero."
}

$BaselineLabel = ConvertTo-SafeLabel $BaselineLabel
$ForkLabel = ConvertTo-SafeLabel $ForkLabel
$BaselineBrowser = Require-File $BaselineBrowser "Baseline browser"
$ForkBrowser = Require-File $ForkBrowser "Fork browser"
$BaselineBuildArgs = if ($BaselineBuildArgs) { Require-File $BaselineBuildArgs "Baseline build args" } else { "" }
$ForkBuildArgs = if ($ForkBuildArgs) { Require-File $ForkBuildArgs "Fork build args" } else { "" }
$BaselinePackageDir = Require-Directory $BaselinePackageDir "Baseline package directory"
$ForkPackageDir = Require-Directory $ForkPackageDir "Fork package directory"
$BaselineBuildArgsHash = Get-Sha256OrEmpty $BaselineBuildArgs
$ForkBuildArgsHash = Get-Sha256OrEmpty $ForkBuildArgs

if (-not $Manifest) {
  $Manifest = Join-Path $ReportDir "$ForkLabel-alternating-pair-manifest.json"
}
$Manifest = Resolve-RepoPath $Manifest
$InputList = [System.IO.Path]::ChangeExtension($Manifest, ".inputs.txt")

$Steps = [System.Collections.Generic.List[object]]::new()
$ResultFiles = [System.Collections.Generic.List[string]]::new()
$ByVariant = @{}

for ($Repeat = 1; $Repeat -le $Repeats; $Repeat += 1) {
  $BaselineVariant = Get-RepeatLabel $BaselineLabel $Repeat
  $ForkVariant = Get-RepeatLabel $ForkLabel $Repeat
  foreach ($Variant in @($BaselineVariant, $ForkVariant)) {
    if (-not $ByVariant.ContainsKey($Variant)) {
      $ByVariant[$Variant] = [System.Collections.Generic.List[string]]::new()
    }
  }

  for ($SceneIndex = 0; $SceneIndex -lt $Scenes.Count; $SceneIndex += 1) {
    $Scene = $Scenes[$SceneIndex]
    foreach ($Side in (Get-PairOrder $Repeat $SceneIndex)) {
      $Variant = if ($Side -eq "baseline") { $BaselineVariant } else { $ForkVariant }
      $Output = Join-Path $RawDir "$Variant-$Scene-$Renderer.json"
      $Command = New-BenchmarkCommand -Side $Side -Scene $Scene -Variant $Variant -Output $Output
      $Steps.Add([ordered]@{
        repeat = $Repeat
        scene = $Scene
        side = $Side
        variant = $Variant
        output = $Output
        command = @("node") + $Command
      }) | Out-Null
      $ResultFiles.Add($Output) | Out-Null
      $ByVariant[$Variant].Add($Output) | Out-Null
    }
  }
}

$ManifestObject = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  phase = if ($DryRun) { "planned" } else { "running" }
  renderer = $Renderer
  scenes = @($Scenes)
  repeats = $Repeats
  order = $Order
  duration = $Duration
  warmup = $Warmup
  complexity = $Complexity
  disable_gpu_timing = [bool]$DisableGpuTiming
  baseline = [ordered]@{
    browser = $BaselineBrowser
    label = $BaselineLabel
    build_args = $BaselineBuildArgs
    build_args_hash = $BaselineBuildArgsHash
    package_dir = $BaselinePackageDir
    benchmark_args = @($BaselineBenchmarkArg)
    browser_flags = @($BaselineBrowserFlag)
  }
  fork = [ordered]@{
    browser = $ForkBrowser
    label = $ForkLabel
    build_args = $ForkBuildArgs
    build_args_hash = $ForkBuildArgsHash
    package_dir = $ForkPackageDir
    fork_revision = $ForkRevision
    benchmark_args = @($ForkBenchmarkArg)
    browser_flags = @($ForkBrowserFlag)
  }
  validation = [ordered]@{
    require_checkout = [bool]$RequireCheckout
    require_build_args = [bool]$RequireBuildArgs
    require_gpu_metadata = [bool]$RequireGpuMetadata
    require_package_size = [bool]$RequirePackageSize
    require_frame_times = [bool]$RequireFrameTimes
    reject_software_rendering = [bool]$RejectSoftwareRendering
    reject_gpu_instability = [bool]$RejectGpuInstability
  }
  result_files = @($ResultFiles)
  input_list = $InputList
  steps = @($Steps)
}

function Write-ManifestState {
  param(
    [string]$Phase,
    [string]$ErrorMessage = "",
    [object]$FailedStep = $null
  )

  $ManifestObject["phase"] = $Phase
  if ($Phase -eq "completed") {
    $ManifestObject["completed_at"] = (Get-Date).ToUniversalTime().ToString("o")
  } elseif ($Phase -eq "failed") {
    $ManifestObject["failed_at"] = (Get-Date).ToUniversalTime().ToString("o")
    $ManifestObject["error"] = $ErrorMessage
    if ($null -ne $FailedStep) {
      $ManifestObject["failed_step"] = $FailedStep
    }
  }
  $ManifestObject | ConvertTo-Json -Depth 12 | Set-Content -Path $Manifest -Encoding UTF8
}

Write-ManifestState -Phase $ManifestObject["phase"]
$ResultFiles | Set-Content -Path $InputList -Encoding UTF8

try {
  foreach ($Step in $Steps) {
    try {
      Invoke-Node ($Step.command | Select-Object -Skip 1)
      if ($DryRun) {
        continue
      }
      node (Join-Path $Root "scripts\validate_metrics.mjs") $Step.output
      if ($LASTEXITCODE -ne 0) {
        throw "Benchmark output failed metric validation: $($Step.output)"
      }
      if ($RequireGpuMetadata -and -not (Test-ResultGpuMetadata $Step.output)) {
        throw "Benchmark output is missing GPU metadata: $($Step.output)"
      }
    } catch {
      Write-ManifestState -Phase "failed" -ErrorMessage $_.Exception.Message -FailedStep $Step
      throw
    }
  }

  if (-not $DryRun) {
    foreach ($Variant in ($ByVariant.Keys | Sort-Object)) {
      $SuiteCommand = @(
        (Join-Path $Root "scripts\validate_benchmark_suite.mjs"),
        "--renderer", $Renderer,
        "--variant", $Variant,
        "--expectedScenes", ($Scenes -join ","),
        "--expectedMeasuredSeconds", [string]$Duration,
        "--expectedWarmupSeconds", [string]$Warmup,
        "--expectedComplexity", [string]$Complexity
      )
      if ($RequireCheckout) {
        $SuiteCommand += "--requireCheckout"
      }
      if ($RequireBuildArgs) {
        $SuiteCommand += "--requireBuildArgs"
      }
      if ($RequireGpuMetadata) {
        $SuiteCommand += "--requireGpuMetadata"
      }
      if ($RequirePackageSize) {
        $SuiteCommand += "--requirePackageSize"
      }
      if ($RequireFrameTimes) {
        $SuiteCommand += "--requireFrameTimes"
      }
      if ($RejectSoftwareRendering) {
        $SuiteCommand += "--rejectSoftwareRendering"
      }
      if ($RejectGpuInstability) {
        $SuiteCommand += "--rejectGpuInstability"
      }
      $SuiteCommand += @($ByVariant[$Variant])
      Invoke-Node $SuiteCommand
    }
    Write-ManifestState -Phase "completed"
  }
} catch {
  if ($ManifestObject["phase"] -ne "failed") {
    Write-ManifestState -Phase "failed" -ErrorMessage $_.Exception.Message
  }
  throw
}

Write-Host "Wrote alternating pair manifest: $Manifest"
Write-Host "Wrote alternating pair input list: $InputList"

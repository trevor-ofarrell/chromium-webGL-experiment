[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Browser,
  [string]$Renderer = "webgl2",
  [string]$Scene = "instancing",
  [int]$Duration = 3600,
  [int]$Warmup = 30,
  [string]$Label = "long-stability",
  [string]$Output = "",
  [string]$BuildArgs = "",
  [string]$PackageDir = "",
  [string]$ExpectedChromiumRevision = "",
  [string]$ForkRevision = "",
  [switch]$ViewerMode,
  [switch]$ViewerTrustedContent,
  [switch]$ViewerAggressiveGpu,
  [switch]$ViewerRelaxedWebglValidation,
  [switch]$ViewerInProcessGpu,
  [switch]$ViewerSingleProcess,
  [string]$ViewerForceAngleBackend = "",
  [switch]$ViewerDisableUnneededBlinkFeatures,
  [switch]$ViewerDirectGpuPresentation,
  [switch]$Precompile,
  [int]$PrerenderFrames = 0,
  [double]$Complexity = 1.0,
  [double]$MaxRssDeltaMb = 128,
  [double]$MaxRendererResourceDelta = 0,
  [string[]]$BrowserFlag = @()
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not $Output) {
  $Output = Join-Path $Root "benchmarks\raw\$Label-$Scene-$Renderer.json"
}

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
  if (-not $Resolved) {
    return ""
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
  if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
    throw "$Label not found: $Resolved"
  }
  $Item = Get-Item -LiteralPath $Resolved
  if ($Item.Length -le 0) {
    throw "$Label is empty: $Resolved"
  }

  return $Resolved
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

function Get-ExpectedFlagMetadata {
  $Metadata = [ordered]@{
    viewer_mode = [bool]$ViewerMode
    viewer_block_external_navigation = [bool]$ViewerMode
    viewer_trusted_content = [bool]$ViewerTrustedContent
    viewer_aggressive_gpu = [bool]$ViewerAggressiveGpu
    viewer_relaxed_webgl_validation = [bool]$ViewerRelaxedWebglValidation
    viewer_in_process_gpu = [bool]$ViewerInProcessGpu
    viewer_single_process = [bool]$ViewerSingleProcess
    viewer_force_angle_backend = if ($ViewerForceAngleBackend) { $ViewerForceAngleBackend } else { $null }
    requested_angle_backend = if ($ViewerForceAngleBackend) { $ViewerForceAngleBackend } else { $null }
    viewer_disable_unneeded_blink_features = [bool]$ViewerDisableUnneededBlinkFeatures
    viewer_direct_gpu_presentation = [bool]$ViewerDirectGpuPresentation
  }

  return @($Metadata.GetEnumerator() | ForEach-Object {
    "$($_.Key)=$(Convert-MetadataValue $_.Value)"
  })
}

$Browser = Require-InputFile $Browser "Browser executable"
if ($BuildArgs) {
  $BuildArgs = Require-InputFile $BuildArgs "Build args"
}
$PackageDir = Require-PackageDirectory $PackageDir "Long-stability package directory" $Browser

$Command = @(
  (Join-Path $Root "scripts\run_benchmark.mjs"),
  "--browser", $Browser,
  "--variant", $Label,
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
if ($ForkRevision) {
  $Command += @("--forkRevision", $ForkRevision)
}
if ($ViewerMode) {
  $Command += "--viewerMode"
}
if ($ViewerTrustedContent) {
  $Command += "--viewerTrustedContent"
}
if ($ViewerAggressiveGpu) {
  $Command += "--viewerAggressiveGpu"
}
if ($ViewerRelaxedWebglValidation) {
  $Command += "--viewerRelaxedWebglValidation"
}
if ($ViewerInProcessGpu) {
  $Command += "--viewerInProcessGpu"
}
if ($ViewerSingleProcess) {
  $Command += "--viewerSingleProcess"
}
if ($ViewerForceAngleBackend) {
  $Command += @("--viewerForceAngleBackend", $ViewerForceAngleBackend)
}
if ($ViewerDisableUnneededBlinkFeatures) {
  $Command += "--viewerDisableUnneededBlinkFeatures"
}
if ($ViewerDirectGpuPresentation) {
  $Command += "--viewerDirectGpuPresentation"
}
if ($Precompile) {
  $Command += "--precompile"
}
if ($PrerenderFrames -gt 0) {
  $Command += @("--prerenderFrames", [string]$PrerenderFrames)
}
foreach ($Flag in $BrowserFlag) {
  $Command += @("--browser-flag", $Flag)
}

node @Command
if ($LASTEXITCODE -ne 0) {
  throw "Long stability benchmark failed or browser crashed before result."
}

node (Join-Path $Root "scripts\validate_metrics.mjs") $Output
if ($LASTEXITCODE -ne 0) {
  throw "Long stability output did not match the metric schema."
}

$StabilityValidation = @(
  (Join-Path $Root "scripts\validate_stability_result.mjs"),
  $Output
)
if ($MaxRssDeltaMb -ge 0) {
  $StabilityValidation += @("--maxRssDeltaMb", [string]$MaxRssDeltaMb)
}
if ($MaxRendererResourceDelta -ge 0) {
  $StabilityValidation += @("--maxRendererResourceDelta", [string]$MaxRendererResourceDelta)
}
if ($ExpectedChromiumRevision) {
  $StabilityValidation += @("--expectedChromiumRevision", $ExpectedChromiumRevision)
  $StabilityValidation += @("--pinRefreshManifest", (Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json"))
}
$StabilityValidation += @("--expectedBrowser", $Browser)
$StabilityValidation += @("--requiredBrowserFlag", "--disable-software-rasterizer")
if ($PackageDir) {
  $StabilityValidation += "--requirePackageSize"
}
foreach ($Metadata in (Get-ExpectedFlagMetadata)) {
  $StabilityValidation += @("--expectedFlagMetadata", $Metadata)
}
node @StabilityValidation
if ($LASTEXITCODE -ne 0) {
  throw "Long stability output did not pass stability thresholds."
}

$Result = Get-Content $Output -Raw | ConvertFrom-Json
Write-Host "Long stability run passed: $Output"
Write-Host "avg_fps=$($Result.avg_fps) rss_delta_mb=$($Result.process_rss_delta_mb) rss_peak_mb=$($Result.process_rss_peak_mb) renderer_geometry_delta=$($Result.renderer_memory_geometries_delta) renderer_texture_delta=$($Result.renderer_memory_textures_delta) renderer_program_delta=$($Result.renderer_programs_delta)"

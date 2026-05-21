[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Browser,
  [string]$Renderer = "webgl2",
  [int]$Duration = 120,
  [int]$Warmup = 20,
  [string]$Label = "baseline",
  [string]$BuildArgs = "",
  [string]$PackageDir = "",
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
  [switch]$DisableGpuTiming,
  [switch]$ReuseValidResults,
  [switch]$RequireGpuMetadata,
  [int]$PrerenderFrames = 0,
  [double]$Complexity = 1.0
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Scenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

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

function Test-ResultGpuTimingMode {
  param(
    [string]$PathValue,
    [bool]$ExpectedEnabled
  )
  try {
    $Result = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
  } catch {
    return $false
  }
  return [bool]$Result.gpu_timing_enabled -eq $ExpectedEnabled
}

foreach ($Scene in $Scenes) {
  $Out = Join-Path $Root "benchmarks\raw\$Label-$Scene-$Renderer.json"
  $ExpectedGpuTimingEnabled = -not $DisableGpuTiming
  if ($ReuseValidResults -and (Test-Path -LiteralPath $Out)) {
    node (Join-Path $Root "scripts\validate_metrics.mjs") $Out
    if ($LASTEXITCODE -eq 0) {
      if ($RequireGpuMetadata -and -not (Test-ResultGpuMetadata $Out)) {
        Write-Host "Existing benchmark result is missing GPU metadata and will be regenerated: $Out"
      } elseif (-not (Test-ResultGpuTimingMode $Out $ExpectedGpuTimingEnabled)) {
        Write-Host "Existing benchmark result has the wrong GPU timing mode and will be regenerated: $Out"
      } else {
        Write-Host "Reusing valid benchmark result: $Out"
        continue
      }
    }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Existing benchmark result failed validation and will be regenerated: $Out"
    }
  }

  $Command = @(
    (Join-Path $Root "scripts\run_benchmark.mjs"),
    "--browser", $Browser,
    "--variant", $Label,
    "--scene", $Scene,
    "--renderer", $Renderer,
    "--complexity", [string]$Complexity,
    "--duration", [string]$Duration,
    "--warmup", [string]$Warmup,
    "--output", $Out
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
  if ($DisableGpuTiming) {
    $Command += "--disableGpuTiming"
  }
  if ($PrerenderFrames -gt 0) {
    $Command += @("--prerenderFrames", [string]$PrerenderFrames)
  }

  node @Command
  if ($LASTEXITCODE -ne 0) {
    throw "Benchmark failed for scene '$Scene' with renderer '$Renderer'."
  }

  node (Join-Path $Root "scripts\validate_metrics.mjs") $Out
  if ($LASTEXITCODE -ne 0) {
    throw "Benchmark output failed metric validation for scene '$Scene': $Out"
  }
  if ($RequireGpuMetadata -and -not (Test-ResultGpuMetadata $Out)) {
    throw "Benchmark output is missing GPU metadata for scene '$Scene': $Out"
  }
  if (-not (Test-ResultGpuTimingMode $Out $ExpectedGpuTimingEnabled)) {
    throw "Benchmark output has the wrong GPU timing mode for scene '$Scene': $Out"
  }
}

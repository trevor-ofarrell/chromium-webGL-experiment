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

foreach ($Scene in $Scenes) {
  $Out = Join-Path $Root "benchmarks\raw\$Label-$Scene-$Renderer.json"
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
}

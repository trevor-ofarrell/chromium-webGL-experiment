$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Manifest = Join-Path $Root "benchmarks\tmp\test-alternating-pair-manifest.json"
$InputList = [System.IO.Path]::ChangeExtension($Manifest, ".inputs.txt")

Remove-Item -LiteralPath $Manifest, $InputList -ErrorAction SilentlyContinue

& (Join-Path $Root "scripts\run_alternating_pair_suite.ps1") `
  -BaselineBrowser ".\src\out\ReleaseBaseline\content_shell.exe" `
  -ForkBrowser ".\src\out\ReleaseViewerDefault\content_shell.exe" `
  -Renderer webgpu `
  -Scenes many-draw-calls,texture-streaming `
  -Repeats 2 `
  -Duration 30 `
  -Warmup 5 `
  -Complexity 2 `
  -BaselineLabel "baseline-dry" `
  -ForkLabel "fork-dry" `
  -Order alternate `
  -ForkBenchmarkArg @(
    "--viewerMode",
    "--viewerTrustedContent",
    "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation",
    "--viewerRejectWebgpuCpuTextureFallback"
  ) `
  -DisableGpuTiming `
  -Manifest $Manifest `
  -DryRun

if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
  throw "Dry-run manifest was not written: $Manifest"
}
if (-not (Test-Path -LiteralPath $InputList -PathType Leaf)) {
  throw "Dry-run input list was not written: $InputList"
}

$Json = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
if ($Json.phase -ne "planned") {
  throw "Expected phase=planned, got '$($Json.phase)'"
}
if ($Json.steps.Count -ne 8) {
  throw "Expected 8 planned steps, got $($Json.steps.Count)"
}
if ($Json.result_files.Count -ne 8) {
  throw "Expected 8 result files, got $($Json.result_files.Count)"
}

$ExpectedSides = @(
  "baseline", "fork",
  "fork", "baseline",
  "baseline", "fork",
  "fork", "baseline"
)
for ($Index = 0; $Index -lt $ExpectedSides.Count; $Index += 1) {
  if ($Json.steps[$Index].side -ne $ExpectedSides[$Index]) {
    throw "Step $Index side mismatch: expected $($ExpectedSides[$Index]), got $($Json.steps[$Index].side)"
  }
}

$ForkSteps = @($Json.steps | Where-Object { $_.side -eq "fork" })
foreach ($Step in $ForkSteps) {
  $Command = @($Step.command | ForEach-Object { [string]$_ })
  foreach ($RequiredArg in @(
    "--viewerMode",
    "--viewerTrustedContent",
    "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation",
    "--viewerRejectWebgpuCpuTextureFallback",
    "--disableGpuTiming"
  )) {
    if ($Command -notcontains $RequiredArg) {
      throw "Fork command for $($Step.scene) is missing $RequiredArg"
    }
  }
}

$Inputs = @(Get-Content -LiteralPath $InputList)
if ($Inputs.Count -ne 8) {
  throw "Expected 8 input-list entries, got $($Inputs.Count)"
}
if (($Inputs | Select-Object -Unique).Count -ne 8) {
  throw "Input list contains duplicate output paths."
}

Write-Host "OK: alternating pair dry-run manifest records interleaved stock/fork order and forwarded WebGPU flags."

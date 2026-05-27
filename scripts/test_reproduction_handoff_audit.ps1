[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path -LiteralPath $Resolved)) {
    throw "Required file not found: $PathValue"
  }
  return Get-Content -LiteralPath $Resolved -Raw
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Needle,
    [string]$Description
  )

  if ($Text -notmatch [regex]::Escape($Needle)) {
    throw "Reproduction handoff audit is missing ${Description}: $Needle"
  }
}

$RequiredHandoffTerms = @(
  "verify_prebuild.ps1",
  "install_vs_atl.ps1",
  "run_post_atl_pipeline.ps1",
  "-RefreshChromiumPin",
  "-IncludeWebGPU",
  "-IncludeAggressiveGpu",
  "-AggressiveAngleBackend d3d11",
  "-AggressiveWebGl2RelaxedValidation",
  "-AggressiveWebGpuSourceFastPath",
  "-AggressiveWebGpuUploadFastPath",
  "-CaptureTrace",
  "-DisableWebGpuTiming",
  "-DisableForkWebGpuTiming",
  "-RunTrustedExperimentMatrix",
  "-RunTrustedWebGpuDawnMatrix",
  "-TrustedMatrixZeroCopy",
  "-TrustedMatrixWebGlCompositorExperiments",
  "-TrustedMatrixWebGpuChromiumFeatureExperiments",
  "-TrustedMatrixWebGpuUploadExperiments",
  "-TrustedMatrixInProcessGpu",
  "-TrustedMatrixSingleProcess",
  "-TrustedMatrixAngleBackend d3d11",
  "-TrustedMatrixReservedNoopGates",
  "-RunLongStability",
  "-MaxRssDeltaMb 128",
  "-MaxRendererResourceDelta 0",
  "-FinalGate"
)

$Readme = Read-RepoFile "README.md"
$BuildDoc = Read-RepoFile "docs\build.md"
$Audit = Read-RepoFile "scripts\audit_artifacts.ps1"
$DocumentationTest = Read-RepoFile "scripts\test_documentation_structure.ps1"

foreach ($Term in $RequiredHandoffTerms) {
  Assert-Contains $Readme $Term "README handoff term"
  Assert-Contains $BuildDoc $Term "build document handoff term"
  Assert-Contains $Audit $Term "artifact audit README required term"
  Assert-Contains $DocumentationTest $Term "documentation structure required term"
}

Assert-Contains $Audit "Top-level reproduction handoff" "artifact audit row label"
Assert-Contains $Audit "not the official same-revision Chromium baseline" "smoke-evidence warning term"
Assert-Contains $DocumentationTest "not the official same-revision Chromium baseline" "README smoke-evidence warning check"

Write-Host "Top-level reproduction handoff audit requires the full post-ATL command shape in README, build docs, audit, and documentation regression tests."

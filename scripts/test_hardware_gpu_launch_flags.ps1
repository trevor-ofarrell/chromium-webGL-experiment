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
    [string]$Label,
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )

  if ($Text -notmatch $Pattern) {
    throw "$Label is missing $Description. Pattern: $Pattern"
  }
}

function Assert-LaunchListContains {
  param(
    [string]$PathValue,
    [string]$Text
  )

  Assert-Contains $PathValue $Text "'--disable-software-rasterizer'|`"--disable-software-rasterizer`"" "hardware-GPU fail-closed launch flag"
  Assert-Contains $PathValue $Text "'--force-high-performance-gpu'|`"--force-high-performance-gpu`"" "discrete/high-performance GPU request flag"
  Assert-Contains $PathValue $Text "'--window-size=640,480'|`"--window-size=640,480`"" "safe small-window launch flag"
  Assert-Contains $PathValue $Text "'--force-device-scale-factor=1'|`"--force-device-scale-factor=1`"" "safe device-scale launch flag"
  Assert-Contains $PathValue $Text "'--enable-unsafe-webgpu'|`"--enable-unsafe-webgpu`"" "WebGPU launch flag"
}

$BenchmarkRunner = Read-RepoFile "scripts\run_benchmark.mjs"
$SmokeRunner = Read-RepoFile "scripts\run_smoke_tests.mjs"
$TraceRunner = Read-RepoFile "scripts\run_trace_capture.mjs"
$PackageStager = Read-RepoFile "scripts\stage_viewer_package.ps1"
$SuiteValidator = Read-RepoFile "scripts\validate_benchmark_suite.mjs"
$StabilityValidator = Read-RepoFile "scripts\validate_stability_result.mjs"
$SmokeValidator = Read-RepoFile "scripts\validate_smoke_result.mjs"
$TraceValidator = Read-RepoFile "scripts\validate_trace_result.mjs"
$OfficialRunner = Read-RepoFile "scripts\run_official_comparison.ps1"
$TrustedRunner = Read-RepoFile "scripts\run_trusted_experiment_matrix.ps1"
$LongStabilityRunner = Read-RepoFile "scripts\run_long_stability.ps1"

Assert-LaunchListContains "scripts\run_benchmark.mjs" $BenchmarkRunner
Assert-LaunchListContains "scripts\run_smoke_tests.mjs" $SmokeRunner
Assert-LaunchListContains "scripts\run_trace_capture.mjs" $TraceRunner
Assert-LaunchListContains "scripts\stage_viewer_package.ps1" $PackageStager

Assert-Contains "scripts\run_benchmark.mjs" $BenchmarkRunner "result\.browser_flags\s*=\s*browserArgs" "effective benchmark launch-argument metadata"
Assert-Contains "scripts\run_benchmark.mjs" $BenchmarkRunner "result\.browser_extra_flags\s*=\s*args\.browserFlag" "benchmark pass-through extra-flag metadata"
Assert-Contains "scripts\run_smoke_tests.mjs" $SmokeRunner "browser_flags:\s*browserArgs" "effective smoke launch-argument metadata"
Assert-Contains "scripts\run_smoke_tests.mjs" $SmokeRunner "browser_extra_flags:\s*args\.browserFlag" "smoke pass-through extra-flag metadata"
Assert-Contains "scripts\run_trace_capture.mjs" $TraceRunner "browser_flags:\s*browserArgs" "effective trace launch-argument metadata"
Assert-Contains "scripts\run_trace_capture.mjs" $TraceRunner "browser_extra_flags:\s*args\.browserFlag" "trace pass-through extra-flag metadata"
Assert-Contains "scripts\validate_benchmark_suite.mjs" $SuiteValidator "--requiredBrowserFlag" "required effective benchmark launch-flag validation"
Assert-Contains "scripts\validate_stability_result.mjs" $StabilityValidator "--requiredBrowserFlag" "required effective stability launch-flag validation"
Assert-Contains "scripts\validate_smoke_result.mjs" $SmokeValidator "--required-browser-flag" "required effective smoke launch-flag validation"
Assert-Contains "scripts\validate_trace_result.mjs" $TraceValidator "--requiredBrowserFlag" "required effective trace launch-flag validation"
Assert-Contains "scripts\run_official_comparison.ps1" $OfficialRunner "required_browser_flags" "official manifest required launch-flag metadata"
Assert-Contains "scripts\run_official_comparison.ps1" $OfficialRunner "--requiredBrowserFlag" "official suite/trace required launch-flag handoff"
Assert-Contains "scripts\run_official_comparison.ps1" $OfficialRunner "--required-browser-flag" "official runtime smoke required launch-flag handoff"
Assert-Contains "scripts\run_trusted_experiment_matrix.ps1" $TrustedRunner "--requiredBrowserFlag" "trusted suite required launch-flag handoff"
Assert-Contains "scripts\run_long_stability.ps1" $LongStabilityRunner "--requiredBrowserFlag" "long-stability required launch-flag handoff"
Assert-Contains "scripts\run_long_stability.ps1" $LongStabilityRunner "--requireGpuMetadata" "long-stability GPU metadata validation handoff"
Assert-Contains "scripts\run_long_stability.ps1" $LongStabilityRunner "--rejectSoftwareRendering" "long-stability software-renderer rejection handoff"
Assert-Contains "scripts\run_long_stability.ps1" $LongStabilityRunner "FriendlyWindow" "long-stability friendly launch profile"
Assert-Contains "scripts\run_long_stability.ps1" $LongStabilityRunner "--window-size=640,480" "long-stability friendly small-window flag"
Assert-Contains "scripts\run_long_stability.ps1" $LongStabilityRunner "--force-device-scale-factor=1" "long-stability friendly device-scale flag"

foreach ($LabelAndText in @(
    @("scripts\validate_benchmark_suite.mjs", $SuiteValidator),
    @("scripts\validate_stability_result.mjs", $StabilityValidator)
  )) {
  $Label = $LabelAndText[0]
  $Text = $LabelAndText[1]
  foreach ($SoftwareTerm in @("swiftshader", "warp", "llvmpipe", "software rasterizer", "software renderer")) {
    Assert-Contains $Label $Text ([regex]::Escape($SoftwareTerm)) "software-renderer rejection term $SoftwareTerm"
  }
}

Write-Host "Primary launchers disable software rasterizer fallback, record required launch flags, and validators reject software-rendered evidence."

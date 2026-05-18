[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path $Resolved)) {
    throw "Required file not found: $PathValue"
  }
  return Get-Content $Resolved -Raw
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Missing benchmark flag metadata evidence: $Description. Pattern: $Pattern"
  }
}

$Runner = Read-RepoFile "scripts\run_benchmark.mjs"
$TraceRunner = Read-RepoFile "scripts\run_trace_capture.mjs"
$Validator = Read-RepoFile "scripts\validate_metrics.mjs"
$TraceValidator = Read-RepoFile "scripts\validate_trace_result.mjs"
$SuiteValidator = Read-RepoFile "scripts\validate_benchmark_suite.mjs"

$FlagMappings = @(
  @{ Arg = "viewerMode"; Switch = "--viewer-block-external-navigation"; Field = "viewer_block_external_navigation"; Type = "boolean" },
  @{ Arg = "viewerTrustedContent"; Switch = "--viewer-trusted-content"; Field = "viewer_trusted_content"; Type = "boolean" },
  @{ Arg = "viewerAggressiveGpu"; Switch = "--viewer-aggressive-gpu"; Field = "viewer_aggressive_gpu"; Type = "boolean" },
  @{ Arg = "viewerRelaxedWebglValidation"; Switch = "--viewer-relaxed-webgl-validation"; Field = "viewer_relaxed_webgl_validation"; Type = "boolean" },
  @{ Arg = "viewerInProcessGpu"; Switch = "--viewer-in-process-gpu"; Field = "viewer_in_process_gpu"; Type = "boolean" },
  @{ Arg = "viewerSingleProcess"; Switch = "--viewer-single-process"; Field = "viewer_single_process"; Type = "boolean" },
  @{ Arg = "viewerForceAngleBackend"; Switch = "--viewer-force-angle-backend"; Field = "viewer_force_angle_backend"; Type = "string" },
  @{ Arg = "viewerDisableUnneededBlinkFeatures"; Switch = "--viewer-disable-unneeded-blink-features"; Field = "viewer_disable_unneeded_blink_features"; Type = "boolean" },
  @{ Arg = "viewerDirectGpuPresentation"; Switch = "--viewer-direct-gpu-presentation"; Field = "viewer_direct_gpu_presentation"; Type = "boolean" }
)

foreach ($Mapping in $FlagMappings) {
  Assert-Contains $Runner ([regex]::Escape($Mapping.Arg)) "parser support for $($Mapping.Arg)"
  Assert-Contains $Runner ([regex]::Escape($Mapping.Switch)) "browser switch emission for $($Mapping.Switch)"
  Assert-Contains $Runner "result\.$([regex]::Escape($Mapping.Field))\s*=" "result metadata field $($Mapping.Field)"
  Assert-Contains $TraceRunner ([regex]::Escape($Mapping.Arg)) "trace parser support for $($Mapping.Arg)"
  Assert-Contains $TraceRunner ([regex]::Escape($Mapping.Switch)) "trace browser switch emission for $($Mapping.Switch)"
  Assert-Contains $TraceRunner "$([regex]::Escape($Mapping.Field)):\s*args\.$([regex]::Escape($Mapping.Arg))" "trace sidecar metadata field $($Mapping.Field)"
  if ($Mapping.Type -eq "boolean") {
    Assert-Contains $Validator "'$([regex]::Escape($Mapping.Field))'" "optional boolean validation for $($Mapping.Field)"
  } else {
    Assert-Contains $Validator "'$([regex]::Escape($Mapping.Field))'" "optional string validation for $($Mapping.Field)"
  }
}

Assert-Contains $Runner "result\.requested_angle_backend\s*=" "requested ANGLE backend metadata"
Assert-Contains $Runner "requestedAngleBackend\s*=\s*args\.angleBackend\s*\|\|\s*args\.viewerForceAngleBackend\s*\|\|\s*null" "requested ANGLE backend includes viewer force alias"
Assert-Contains $Validator "'requested_angle_backend'" "requested ANGLE backend validation"
Assert-Contains $Runner "result\.browser_flags\s*=\s*browserArgs" "effective browser flag metadata"
Assert-Contains $Runner "result\.browser_extra_flags\s*=\s*args\.browserFlag" "pass-through browser extra flag metadata"
Assert-Contains $Validator "validateOptionalStringArray\(data,\s*'browser_flags',\s*errors\)" "browser_flags array validation"
Assert-Contains $Validator "validateOptionalStringArray\(data,\s*'browser_extra_flags',\s*errors\)" "browser_extra_flags array validation"
Assert-Contains $Validator "\$\{key\} must be an array" "optional flag array validation helper"
Assert-Contains $Validator "\$\{key\}\[\$\{index\}\] must be a string" "optional flag element validation helper"
Assert-Contains $TraceRunner "browser_flags:\s*browserArgs" "trace sidecar effective browser flag metadata"
Assert-Contains $TraceRunner "browser_extra_flags:\s*args\.browserFlag" "trace sidecar browser extra flag metadata"
Assert-Contains $TraceValidator "validateOptionalStringArray\(errors,\s*data,\s*'browser_flags',\s*label\)" "trace browser_flags array validation"
Assert-Contains $TraceValidator "validateOptionalStringArray\(errors,\s*data,\s*'browser_extra_flags',\s*label\)" "trace browser_extra_flags array validation"
Assert-Contains $SuiteValidator "--requiredBrowserFlag" "suite required effective browser flag option"
Assert-Contains $SuiteValidator "browser_flags must include" "suite required effective browser flag validation"
Assert-Contains $TraceValidator "--requiredBrowserFlag" "trace required effective browser flag option"
Assert-Contains $TraceValidator "browser_flags must include" "trace required effective browser flag validation"
Assert-Contains $Runner "assertTrustedViewerExperimentGates\(args\)" "benchmark runner trusted experiment gate invocation"
Assert-Contains $Runner "Unsafe viewer experiment flags require --viewerMode and --viewerTrustedContent" "benchmark runner trusted experiment gate failure"
Assert-Contains $TraceRunner "assertTrustedViewerExperimentGates\(args\)" "trace runner trusted experiment gate invocation"
Assert-Contains $TraceRunner "Unsafe viewer experiment flags require --viewerMode and --viewerTrustedContent" "trace runner trusted experiment gate failure"

function Assert-NodeFailsWith {
  param(
    [string]$ScriptPath,
    [string[]]$Arguments,
    [string]$Pattern,
    [string]$Description
  )

  $ProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $ProcessInfo.FileName = "node"
  $ProcessInfo.Arguments = (@($ScriptPath) + $Arguments | ForEach-Object {
    $Text = [string]$_
    '"' + ($Text -replace '"', '\"') + '"'
  }) -join " "
  $ProcessInfo.RedirectStandardOutput = $true
  $ProcessInfo.RedirectStandardError = $true
  $ProcessInfo.UseShellExecute = $false
  $ProcessInfo.CreateNoWindow = $true

  $Process = [System.Diagnostics.Process]::new()
  $Process.StartInfo = $ProcessInfo
  try {
    if (-not $Process.Start()) {
      throw "Unable to start node for $Description."
    }
    $Stdout = $Process.StandardOutput.ReadToEnd()
    $Stderr = $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()
    if ($Process.ExitCode -eq 0) {
      throw "Expected node command to fail for $Description."
    }
    $Text = "$Stdout`n$Stderr"
  } finally {
    $Process.Dispose()
  }
  Assert-Contains $Text $Pattern $Description
}

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_benchmark.mjs") `
  @("--browser", "missing-browser.exe", "--viewerAggressiveGpu") `
  "Unsafe viewer experiment flags require --viewerMode and --viewerTrustedContent" `
  "benchmark runner rejects unsafe viewer flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerAggressiveGpu") `
  "Unsafe viewer experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects unsafe viewer flags without trusted viewer mode"

Assert-NodeFailsWith `
  (Join-Path $Root "scripts\run_trace_capture.mjs") `
  @("--browser", "missing-browser.exe", "--viewerRelaxedWebglValidation") `
  "Unsafe viewer experiment flags require --viewerMode and --viewerTrustedContent" `
  "trace runner rejects relaxed WebGL validation without trusted viewer mode"

Write-Host "Benchmark runner records, validates, and gates trusted viewer flag metadata."

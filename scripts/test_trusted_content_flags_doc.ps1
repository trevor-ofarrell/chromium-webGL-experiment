[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$DocPath = Join-Path $Root "docs\trusted_content_flags.md"

if (-not (Test-Path -LiteralPath $DocPath)) {
  throw "Missing docs\trusted_content_flags.md."
}

$Text = Get-Content -LiteralPath $DocPath -Raw
foreach ($RequiredPhrase in @(
    'Unsafe behavior is gated by both `--viewer-app-url` and `--viewer-trusted-content`',
    'keeps unimplemented reserved experiment gates as no-ops',
    'maps the relaxed WebGL validation experiment to Chromium''s pass-through command decoder switch',
    'Each aggressive run must be compared against stock Chromium and the fork default profile from the same Chromium revision'
  )) {
  if ($Text -notmatch [regex]::Escape($RequiredPhrase)) {
    throw "Trusted-content flag doc is missing required guardrail text: $RequiredPhrase"
  }
}

function Split-MarkdownRow {
  param([string]$Line)

  $Trimmed = $Line.Trim()
  if (-not $Trimmed.StartsWith("|") -or -not $Trimmed.EndsWith("|")) {
    throw "Invalid markdown table row: $Line"
  }

  return @($Trimmed.Trim("|").Split("|") | ForEach-Object { $_.Trim() })
}

$TableLines = @((Get-Content -LiteralPath $DocPath) | Where-Object { $_.Trim().StartsWith("|") })
if ($TableLines.Count -lt 3) {
  throw "Trusted-content flag doc does not contain the flag table."
}

$Header = Split-MarkdownRow $TableLines[0]
foreach ($Column in @("Viewer switch", "Current behavior", "Risk", "Status")) {
  if ($Header -notcontains $Column) {
    throw "Trusted-content flag table is missing required column '$Column'."
  }
}

$Rows = @()
foreach ($Line in @($TableLines | Select-Object -Skip 2)) {
  $Cells = Split-MarkdownRow $Line
  if ($Cells.Count -ne $Header.Count) {
    throw "Trusted-content flag table has a row with $($Cells.Count) cells; expected $($Header.Count): $Line"
  }
  $Row = [ordered]@{}
  for ($Index = 0; $Index -lt $Header.Count; $Index++) {
    $Row[$Header[$Index]] = $Cells[$Index]
  }
  $Rows += [pscustomobject]$Row
}

$RequiredSwitches = @(
  "--viewer-app-url",
  "--viewer-block-external-navigation",
  "--viewer-trusted-content",
  "--viewer-aggressive-gpu",
  "--viewer-in-process-gpu",
  "--viewer-single-process",
  "--viewer-force-angle-backend",
  "--viewer-relaxed-webgl-validation",
  "--viewer-disable-unneeded-blink-features",
  "--viewer-direct-gpu-presentation"
)

foreach ($Switch in $RequiredSwitches) {
  $Matches = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape($Switch) })
  if ($Matches.Count -ne 1) {
    throw "Trusted-content flag table does not contain exactly one row for $Switch."
  }
  $Row = $Matches[0]
  foreach ($Column in @("Current behavior", "Risk", "Status")) {
    if ([string]::IsNullOrWhiteSpace([string]$Row.$Column)) {
      throw "Trusted-content flag row $Switch has an empty '$Column' cell."
    }
  }
  if ($Row.Risk -notmatch "Low|Medium|High|Very high") {
    throw "Trusted-content flag row $Switch has an unclassified risk: $($Row.Risk)"
  }
}

foreach ($UnsafeSwitch in @(
    "--viewer-trusted-content",
    "--viewer-aggressive-gpu",
    "--viewer-in-process-gpu",
    "--viewer-single-process",
    "--viewer-force-angle-backend",
    "--viewer-relaxed-webgl-validation",
    "--viewer-disable-unneeded-blink-features",
    "--viewer-direct-gpu-presentation"
  )) {
  $Row = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape($UnsafeSwitch) })[0]
  if ($Row.Risk -notmatch "Medium|High|Very high") {
    throw "Unsafe trusted-content flag $UnsafeSwitch must document at least medium risk."
  }
}

foreach ($ReservedSwitch in @(
    "--viewer-disable-unneeded-blink-features",
    "--viewer-direct-gpu-presentation"
  )) {
  $Row = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape($ReservedSwitch) })[0]
  if ($Row."Current behavior" -notmatch "Reserved gate only" -or
      $Row.Status -notmatch "Pending source experiment") {
    throw "Reserved trusted-content flag $ReservedSwitch must remain documented as a no-op pending source experiment."
  }
}

$RelaxedWebglRow = @($Rows | Where-Object { $_."Viewer switch" -match [regex]::Escape("--viewer-relaxed-webgl-validation") })[0]
if ($RelaxedWebglRow."Current behavior" -notmatch [regex]::Escape("--use-cmd-decoder=passthrough") -or
    $RelaxedWebglRow.Status -notmatch "benchmark pending") {
  throw "Trusted-content flag --viewer-relaxed-webgl-validation must document the pass-through command decoder alias and pending benchmark status."
}

foreach ($MetadataField in @(
    "viewer_trusted_content",
    "viewer_block_external_navigation",
    "viewer_aggressive_gpu",
    "viewer_relaxed_webgl_validation",
    "viewer_in_process_gpu",
    "viewer_single_process",
    "viewer_force_angle_backend",
    "viewer_disable_unneeded_blink_features",
    "viewer_direct_gpu_presentation",
    "requested_angle_backend",
    "browser_flags"
  )) {
  if ($Text -notmatch [regex]::Escape($MetadataField)) {
    throw "Trusted-content flag doc does not list benchmark metadata field $MetadataField."
  }
}

Write-Host "Trusted-content flag documentation covers gating, risk, pass-through decoder aliasing, reserved no-op gates, and benchmark metadata for $($RequiredSwitches.Count) viewer switches."

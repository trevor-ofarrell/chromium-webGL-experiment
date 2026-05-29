[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$Profiles = [ordered]@{
  baseline = "build\gn_args\baseline_content_shell.gn"
  fork_default = "build\gn_args\fork_safe_content_shell.gn"
  fork_trusted_aggressive = "build\gn_args\fork_trusted_aggressive.gn"
}

$ExpectedArgs = [ordered]@{
  is_debug = "false"
  is_component_build = "false"
  is_official_build = "false"
  symbol_level = "1"
  blink_symbol_level = "0"
  v8_symbol_level = "0"
  treat_warnings_as_errors = "false"
  dcheck_always_on = "false"
  enable_expensive_dchecks = "false"
  enable_ubsan_hardening = "false"
  disable_llvm_machine_scheduler = "true"
}

$DisallowedTerms = @(
  "--viewer-app-url",
  "--viewer-trusted-content",
  "--viewer-aggressive-gpu",
  "enable_unsafe_webgpu",
  "in_process_gpu",
  "single_process",
  "use_angle"
)

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path $Resolved)) {
    throw "Required GN args file not found: $PathValue"
  }
  return Get-Content $Resolved -Raw
}

function Parse-GnArgs {
  param(
    [string]$PathValue,
    [string]$Text
  )

  $Args = [ordered]@{}
  $Lines = $Text -split "`r?`n"
  foreach ($Line in $Lines) {
    $Trimmed = $Line.Trim()
    if (-not $Trimmed -or $Trimmed.StartsWith("#")) {
      continue
    }
    $Match = [regex]::Match($Trimmed, '^([A-Za-z0-9_]+)\s*=\s*(.+)$')
    if (-not $Match.Success) {
      throw "$PathValue contains an unsupported GN args line: $Trimmed"
    }
    $Key = $Match.Groups[1].Value
    $Value = $Match.Groups[2].Value.Trim()
    if ($Args.Contains($Key)) {
      throw "$PathValue defines $Key more than once."
    }
    $Args[$Key] = $Value
  }
  return $Args
}

function Assert-ExpectedArgs {
  param(
    [string]$Label,
    [hashtable]$Actual
  )

  $ActualKeys = @($Actual.Keys)
  $ExpectedKeys = @($ExpectedArgs.Keys)
  $Unexpected = @($ActualKeys | Where-Object { $ExpectedKeys -notcontains $_ })
  $Missing = @($ExpectedKeys | Where-Object { $ActualKeys -notcontains $_ })
  if ($Unexpected.Count -gt 0) {
    throw "$Label contains unexpected GN args: $($Unexpected -join ', ')"
  }
  if ($Missing.Count -gt 0) {
    throw "$Label is missing required GN args: $($Missing -join ', ')"
  }
  foreach ($Key in $ExpectedKeys) {
    if ($Actual[$Key] -ne $ExpectedArgs[$Key]) {
      throw "$Label $Key=$($Actual[$Key]), expected $($ExpectedArgs[$Key])."
    }
  }
}

function Assert-SameArgs {
  param(
    [string]$LeftLabel,
    [hashtable]$Left,
    [string]$RightLabel,
    [hashtable]$Right
  )

  foreach ($Key in $ExpectedArgs.Keys) {
    if ($Left[$Key] -ne $Right[$Key]) {
      throw "$LeftLabel and $RightLabel differ for ${Key}: $($Left[$Key]) vs $($Right[$Key])"
    }
  }
}

function Assert-NoDisallowedTerms {
  param(
    [string]$PathValue,
    [string]$Text
  )
  foreach ($Term in $DisallowedTerms) {
    if ($Text -match [regex]::Escape($Term)) {
      throw "$PathValue contains unsafe runtime/control term that must stay out of GN args: $Term"
    }
  }
}

$Parsed = @{}
$Texts = @{}
foreach ($Entry in $Profiles.GetEnumerator()) {
  $Text = Read-RepoFile $Entry.Value
  $Texts[$Entry.Key] = $Text
  $Parsed[$Entry.Key] = Parse-GnArgs $Entry.Value $Text
  Assert-ExpectedArgs $Entry.Key $Parsed[$Entry.Key]
  Assert-NoDisallowedTerms $Entry.Value $Text
}

Assert-SameArgs "baseline" $Parsed.baseline "fork default" $Parsed.fork_default
Assert-SameArgs "baseline" $Parsed.baseline "fork trusted/aggressive" $Parsed.fork_trusted_aggressive

if ($Texts.fork_trusted_aggressive -notmatch "Experimental profile only\. Runtime flags still control unsafe behavior\.") {
  throw "build\gn_args\fork_trusted_aggressive.gn must document that unsafe behavior remains controlled by runtime flags."
}

Write-Host "GN args profile checks passed for baseline, fork default, and trusted/aggressive templates."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$OutRoot = Join-Path $Src "out"
$TestOutDir = "out\BaselineSourceGuardTest-$PID"
$TestOutAbs = Join-Path $Src $TestOutDir
$BuildScript = Join-Path $Root "scripts\build_chromium.ps1"
$PatchSeries = @(
  "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch",
  "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"
)

function Assert-UnderDirectory {
  param(
    [string]$PathValue,
    [string]$Parent
  )

  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if (-not $FullPath.StartsWith($FullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside expected directory. path=$FullPath parent=$FullParent"
  }
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )

  if ($Text -notmatch $Pattern) {
    throw "build_chromium.ps1 is missing $Description. Pattern: $Pattern"
  }
}

function Test-GitApply {
  param(
    [string]$PatchPath,
    [switch]$Reverse
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Arguments = @("-C", $Src, "apply")
    if ($Reverse) {
      $Arguments += "--reverse"
    }
    $Arguments += @("--check", $PatchPath)
    $null = (& git @Arguments 2>$null)
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

Assert-UnderDirectory $TestOutAbs $OutRoot

$BuildText = Get-Content -LiteralPath $BuildScript -Raw
Assert-Contains $BuildText '\[switch\]\$AllowViewerPatchApplied' "explicit patched-source non-evidence opt-in"
Assert-Contains $BuildText "Assert-StockBaselineSourceUnpatched" "stock baseline source-state guard"
Assert-Contains $BuildText "Cannot build stock baseline while viewer patch series entries are already applied" "applied-patch baseline rejection"
Assert-Contains $BuildText "Cannot audit viewer patch series state before stock baseline build" "broken patch-state baseline rejection"
Assert-Contains $BuildText "baseline_source_guard_enabled" "provenance flag for baseline source guard"

$ArgsMismatchIndex = $BuildText.IndexOf("Existing GN args differ", [System.StringComparison]::Ordinal)
$GuardCallIndex = $BuildText.LastIndexOf("Assert-StockBaselineSourceUnpatched", [System.StringComparison]::Ordinal)
if ($ArgsMismatchIndex -lt 0 -or $GuardCallIndex -lt 0 -or $GuardCallIndex -lt $ArgsMismatchIndex) {
  throw "Baseline source guard must run after the stale args.gn guard so args mismatches keep their specific failure."
}

$PatchStates = @($PatchSeries | ForEach-Object {
    $PatchPath = Join-Path $Root $_
    [pscustomobject]@{
      Path = $_
      Exists = Test-Path -LiteralPath $PatchPath -PathType Leaf
      Applies = Test-GitApply -PatchPath $PatchPath
      AlreadyApplied = Test-GitApply -PatchPath $PatchPath -Reverse
    }
  })
$AppliedPatchStates = @($PatchStates | Where-Object { $_.AlreadyApplied })
$BlockedPatchStates = @($PatchStates | Where-Object { -not $_.Exists -or (-not $_.Applies -and -not $_.AlreadyApplied) })

try {
  if ($AppliedPatchStates.Count -eq 0 -and $BlockedPatchStates.Count -eq 0) {
    Write-Host "Baseline source guard static coverage passed; current src is unpatched, so dynamic rejection was not exercised."
    return
  }

  $ExpectedPattern = if ($AppliedPatchStates.Count -gt 0) {
    "Cannot build stock baseline while viewer patch series entries are already applied"
  } else {
    "Cannot audit viewer patch series state before stock baseline build"
  }

  $FailedAsExpected = $false
  $Message = ""
  try {
    & $BuildScript `
      -OutDir $TestOutDir `
      -Target content_shell `
      -ArgsFile "build\gn_args\baseline_content_shell.gn" `
      -SkipPrereqCheck `
      -GenOnly
  } catch {
    $FailedAsExpected = $true
    $Message = $_.Exception.Message
  }

  if (-not $FailedAsExpected) {
    throw "Stock baseline build did not reject the current patched or unauditable source state."
  }
  if ($Message -notmatch $ExpectedPattern) {
    throw "Stock baseline source guard failed for the wrong reason. Pattern: $ExpectedPattern Message: $Message"
  }
  if (Test-Path -LiteralPath (Join-Path $TestOutAbs "build.ninja")) {
    throw "Stock baseline source guard ran too late; GN output was generated before rejection."
  }

  Write-Host "Stock baseline source guard rejects patched or unauditable src before GN generation."
} finally {
  if (Test-Path $TestOutAbs) {
    Assert-UnderDirectory $TestOutAbs $OutRoot
    Remove-Item -LiteralPath $TestOutAbs -Recurse -Force
  }
}

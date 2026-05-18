[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$OutRoot = Join-Path $Src "out"
$TestOutDir = "out\GnGenOnlyTest-$PID"
$TestOutAbs = Join-Path $Src $TestOutDir
$Template = Join-Path $Root "build\gn_args\baseline_content_shell.gn"

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

function Get-HashString {
  param([string]$PathValue)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
}

Assert-UnderDirectory $TestOutAbs $OutRoot

try {
  & (Join-Path $Root "scripts\build_chromium.ps1") `
    -OutDir $TestOutDir `
    -Target content_shell `
    -ArgsFile "build\gn_args\baseline_content_shell.gn" `
    -SkipPrereqCheck `
    -GenOnly

  $GeneratedArgs = Join-Path $TestOutAbs "args.gn"
  if (-not (Test-Path $GeneratedArgs)) {
    throw "GN generation-only run did not create args.gn."
  }
  if ((Get-HashString $GeneratedArgs) -ne (Get-HashString $Template)) {
    throw "Generated args.gn does not match the checked-in baseline template."
  }
  if (-not (Test-Path (Join-Path $TestOutAbs "build.ninja"))) {
    throw "GN generation-only run did not create build.ninja."
  }
  if (Test-Path (Join-Path $TestOutAbs "content_shell.exe")) {
    throw "GN generation-only run unexpectedly produced a content_shell.exe binary."
  }

  Write-Host "GN generation-only mode creates reproducible args without invoking autoninja."
} finally {
  if (Test-Path $TestOutAbs) {
    Assert-UnderDirectory $TestOutAbs $OutRoot
    Remove-Item -LiteralPath $TestOutAbs -Recurse -Force
  }
}

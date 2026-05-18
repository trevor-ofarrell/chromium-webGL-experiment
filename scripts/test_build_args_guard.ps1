[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$OutRoot = Join-Path $Src "out"
$TestOutDir = "out\ArgsGuardTest-$PID"
$TestOutAbs = Join-Path $Src $TestOutDir
$ExpectedMessage = "Existing GN args differ"

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

Assert-UnderDirectory $TestOutAbs $OutRoot

try {
  New-Item -ItemType Directory -Path $TestOutAbs -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $TestOutAbs "args.gn") -Value "# intentionally stale args for guard regression test`n" -Encoding ASCII

  $FailedAsExpected = $false
  try {
    & (Join-Path $Root "scripts\build_chromium.ps1") `
      -OutDir $TestOutDir `
      -Target content_shell `
      -ArgsFile "build\gn_args\baseline_content_shell.gn" `
      -SkipPrereqCheck
  } catch {
    if ([string]$_.Exception.Message -like "*$ExpectedMessage*") {
      $FailedAsExpected = $true
      Write-Host "Build args guard rejected stale args.gn as expected."
    } else {
      throw
    }
  }

  if (-not $FailedAsExpected) {
    throw "Build args guard did not reject the stale args.gn fixture."
  }
} finally {
  if (Test-Path $TestOutAbs) {
    Assert-UnderDirectory $TestOutAbs $OutRoot
    Remove-Item -LiteralPath $TestOutAbs -Recurse -Force
  }
}

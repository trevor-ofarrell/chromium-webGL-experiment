[CmdletBinding()]
param(
  [string]$Revision = "",
  [switch]$SkipSync,
  [switch]$SkipHooks
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$DepotTools = Join-Path $Root "tools\depot_tools"
$RevisionFile = Join-Path $Root ".chromium_revision"

if (-not $Revision) {
  $Revision = (Get-Content $RevisionFile -Raw).Trim()
}

if (-not (Test-Path $DepotTools)) {
  New-Item -ItemType Directory -Path (Join-Path $Root "tools") -Force | Out-Null
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $DepotTools
}

$env:PATH = "$DepotTools;$env:PATH"
if ($IsWindows -or $env:OS -eq "Windows_NT") {
  if (-not $env:DEPOT_TOOLS_WIN_TOOLCHAIN) {
    $env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
  }
  $DefaultVs2022 = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
  if (-not $env:vs2022_install -and (Test-Path $DefaultVs2022)) {
    $env:vs2022_install = $DefaultVs2022
  }
}
& (Join-Path $DepotTools "update_depot_tools.bat")

if ($SkipSync) {
  Write-Host "Skipping Chromium sync. depot_tools is ready at $DepotTools"
  exit 0
}

$Gclient = Join-Path $Root ".gclient"
if (-not (Test-Path $Gclient)) {
  Push-Location $Root
  try {
    gclient config https://chromium.googlesource.com/chromium/src.git
  } finally {
    Pop-Location
  }
}

Push-Location $Root
try {
  $syncArgs = @("sync", "--no-history", "--revision", "src@$Revision")
  if ($SkipHooks) {
    $syncArgs += "--nohooks"
  }
  gclient @syncArgs

  if (-not $SkipHooks) {
    gclient runhooks
  }

  Push-Location (Join-Path $Root "src")
  try {
    git rev-parse HEAD
  } finally {
    Pop-Location
  }
} finally {
  Pop-Location
}

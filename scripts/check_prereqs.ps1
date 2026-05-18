[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$checks = @()
$AtlComponentId = "Microsoft.VisualStudio.Component.VC.ATLMFC"
$Installer = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
$VsWhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"

function Add-Check {
  param(
    [string]$Name,
    [bool]$Ok,
    [string]$Detail
  )
  $script:checks += [pscustomobject]@{
    Check = $Name
    OK = $Ok
    Detail = $Detail
  }
}

$DepotTools = Join-Path $Root "tools\depot_tools"
Add-Check "depot_tools" (Test-Path (Join-Path $DepotTools "gclient.py")) $DepotTools
Add-Check "visual_studio_installer" (Test-Path $Installer) $Installer

$VsAtlInstances = @()
if (Test-Path $VsWhere) {
  try {
    $VsWhereOutput = & $VsWhere -latest -products * -requires $AtlComponentId -format json 2>$null
    if ($LASTEXITCODE -eq 0 -and $VsWhereOutput) {
      $ParsedVsAtlInstances = ($VsWhereOutput -join "`n") | ConvertFrom-Json
      if ($null -ne $ParsedVsAtlInstances) {
        $VsAtlInstances = @($ParsedVsAtlInstances | Where-Object { $null -ne $_ })
      }
    }
  } catch {
    $VsAtlInstances = @()
  }
}

$ChromiumRevisionFile = Join-Path $Root ".chromium_revision"
$ExpectedRevision = if (Test-Path $ChromiumRevisionFile) { (Get-Content $ChromiumRevisionFile -Raw).Trim() } else { "" }
$Src = Join-Path $Root "src"
$ActualRevision = ""
if (Test-Path (Join-Path $Src ".git")) {
  $ActualRevision = (git -C $Src rev-parse HEAD 2>$null)
}
Add-Check "chromium_revision" ($ExpectedRevision -and $ActualRevision -eq $ExpectedRevision) "expected=$ExpectedRevision actual=$ActualRevision"

Add-Check "gclient_entries" (Test-Path (Join-Path $Root ".gclient_entries")) (Join-Path $Root ".gclient_entries")
Add-Check "gn" (Test-Path (Join-Path $Src "buildtools\win\gn.exe")) (Join-Path $Src "buildtools\win\gn.exe")
Add-Check "ninja" (Test-Path (Join-Path $Src "third_party\ninja\ninja.exe")) (Join-Path $Src "third_party\ninja\ninja.exe")

$VsPath = $env:vs2022_install
if (-not $VsPath) {
  $VsPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
}
Add-Check "vs2022_install" (Test-Path $VsPath) $VsPath

$MsvcRoot = Join-Path $VsPath "VC\Tools\MSVC"
$Atldef = $null
if (Test-Path $MsvcRoot) {
  $Atldef = Get-ChildItem $MsvcRoot -Recurse -Filter atldef.h -ErrorAction SilentlyContinue | Select-Object -First 1
}
Add-Check "visual_studio_atl" ($null -ne $Atldef) ($(if ($Atldef) { $Atldef.FullName } else { "missing atldef.h; install component $AtlComponentId with .\scripts\install_vs_atl.ps1 from elevated PowerShell" }))
Add-Check "visual_studio_atl_component" ($VsAtlInstances.Count -gt 0) ($(if ($VsAtlInstances.Count -gt 0) { "vswhere reports $AtlComponentId in $($VsAtlInstances[0].installationPath)" } else { "vswhere does not report component $AtlComponentId; install with .\scripts\install_vs_atl.ps1 from elevated PowerShell" }))

$DbgHelp = "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbghelp.dll"
Add-Check "windows_sdk_debuggers" (Test-Path $DbgHelp) $DbgHelp

$ViewerDist = Join-Path $Root "viewer\dist\index.html"
Add-Check "viewer_dist" (Test-Path $ViewerDist) $ViewerDist

$checks | Format-Table -AutoSize
if ($checks | Where-Object { -not $_.OK }) {
  Write-Host ""
  Write-Host "One or more prerequisites are missing."
  if (-not $Atldef) {
    Write-Host "ATL/MFC remediation:"
    Write-Host "  1. Open PowerShell as Administrator."
    Write-Host "  2. cd `"$Root`""
    Write-Host "  3. .\scripts\install_vs_atl.ps1"
    Write-Host "  4. .\scripts\verify_prebuild.ps1"
    Write-Host "  5. .\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -RunTrustedExperimentMatrix -TrustedMatrixInProcessGpu -TrustedMatrixSingleProcess -TrustedMatrixAngleBackend d3d11 -TrustedMatrixReservedNoopGates -RunLongStability -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FinalGate"
  }
  exit 1
}

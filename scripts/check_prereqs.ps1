[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$checks = @()
$AtlComponentId = "Microsoft.VisualStudio.Component.VC.ATLMFC"
$Installer = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
$VsWhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$CodeIntegrityActivePolicyDir = "C:\Windows\System32\CodeIntegrity\CiPolicies\Active"

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

function Get-CodeIntegrityChromiumRustBlock {
  if (-not ([System.Management.Automation.PSTypeName]"ThreeBrowserCodeIntegrityProbe").Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ThreeBrowserCodeIntegrityProbe {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hReservedNull, uint dwFlags);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool FreeLibrary(IntPtr hModule);
}
"@
  }

  $Result = [ordered]@{
    active_policy_ids = @()
    verified_and_reputable_policy_state = $null
    sample_dlls = @()
    blocked_sample_dll_count = 0
    recent_block_count = 0
    recent_active_policy_block_count = 0
    recent_policy_ids = @()
    recent_first_message = $null
    query_error = $null
  }

  try {
    $PolicyState = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -ErrorAction SilentlyContinue
    if ($PolicyState) {
      $Result.verified_and_reputable_policy_state = $PolicyState.VerifiedAndReputablePolicyState
    }
  } catch {
  }

  if (Test-Path $CodeIntegrityActivePolicyDir) {
    $Result.active_policy_ids = @(Get-ChildItem $CodeIntegrityActivePolicyDir -Filter "*.cip" -ErrorAction SilentlyContinue |
      ForEach-Object { $_.BaseName.Trim("{}").ToUpperInvariant() })
  }

  $OutRoot = Join-Path $Src "out"
  if (Test-Path $OutRoot) {
    $SampleDlls = @(Get-ChildItem $OutRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Join-Path $_.FullName "win_clang_x64_for_rust_host_build_tools\parsing_attribute_34eeb95b.dll"
      } | Where-Object { Test-Path $_ })
    $Result.sample_dlls = @($SampleDlls | ForEach-Object {
        $Handle = [ThreeBrowserCodeIntegrityProbe]::LoadLibraryEx($_, [IntPtr]::Zero, 0)
        if ($Handle -eq [IntPtr]::Zero) {
          $LastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
          [pscustomobject]@{
            path = $_
            loaded = $false
            last_error = $LastError
            blocked_by_code_integrity = ($LastError -eq 4551 -or $LastError -eq 577)
          }
        } else {
          [void][ThreeBrowserCodeIntegrityProbe]::FreeLibrary($Handle)
          [pscustomobject]@{
            path = $_
            loaded = $true
            last_error = 0
            blocked_by_code_integrity = $false
          }
        }
      })
    $Result.blocked_sample_dll_count = @($Result.sample_dlls | Where-Object { $_.blocked_by_code_integrity }).Count
  }

  try {
    $StartTime = (Get-Date).AddDays(-7)
    $RepoPathForEventMatch = ($Root.ProviderPath -replace "\\", "\\")
    $Events = @(Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-CodeIntegrity/Operational"; StartTime = $StartTime } -ErrorAction Stop |
      Where-Object {
        $_.Message -match "rustc\.exe" -and
        $_.Message -match "three-browser" -and
        $_.Message -match "Application Control policy|Enterprise signing level|did not meet"
      })
    $Result.recent_block_count = $Events.Count
    $PolicyIds = @()
    foreach ($Event in $Events) {
      if (-not $Result.recent_first_message) {
        $Result.recent_first_message = (($Event.Message -split "`r?`n") -join " ")
      }
      if ($Event.Message -match "Policy ID:\{([^}]+)\}") {
        $PolicyIds += $Matches[1].ToUpperInvariant()
      }
    }
    $Result.recent_policy_ids = @($PolicyIds | Sort-Object -Unique)
    $Result.recent_active_policy_block_count = @($Result.recent_policy_ids | Where-Object {
        $Result.active_policy_ids -contains $_
      }).Count
  } catch {
    $Result.query_error = $_.Exception.Message
  }

  [pscustomobject]$Result
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

$CodeIntegrityBlock = Get-CodeIntegrityChromiumRustBlock
$CodeIntegrityOk = $CodeIntegrityBlock.blocked_sample_dll_count -eq 0
$CodeIntegrityDetail = if ($CodeIntegrityOk) {
  "no current Code Integrity block when probing existing Chromium Rust proc-macro DLLs; active_policies=$(@($CodeIntegrityBlock.active_policy_ids).Count); recent_block_events=$($CodeIntegrityBlock.recent_block_count); verified_and_reputable_policy_state=$($CodeIntegrityBlock.verified_and_reputable_policy_state)"
} else {
  "current Code Integrity block for Chromium Rust proc-macro DLLs; blocked_samples=$($CodeIntegrityBlock.blocked_sample_dll_count); policy_ids=$(@($CodeIntegrityBlock.recent_policy_ids) -join ','); unblock WDAC/Smart App Control for generated Chromium build DLLs, then rerun the failed build"
}
Add-Check "windows_code_integrity_chromium_rust" $CodeIntegrityOk $CodeIntegrityDetail

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

[CmdletBinding()]
param(
  [string]$VsInstallPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
)

$ErrorActionPreference = "Stop"
$Installer = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
$VsWhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$AtlComponentId = "Microsoft.VisualStudio.Component.VC.ATLMFC"

function Get-AtlHeaderPath {
  param(
    [string]$InstallPath
  )

  $MsvcRoot = Join-Path $InstallPath "VC\Tools\MSVC"
  if (-not (Test-Path $MsvcRoot)) {
    return $null
  }

  $Header = Get-ChildItem $MsvcRoot -Recurse -Filter atldef.h -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($Header) {
    return $Header.FullName
  }
  return $null
}

function Test-AtlComponentRegistered {
  param(
    [string]$InstallPath
  )

  if (-not (Test-Path $VsWhere)) {
    return $false
  }

  try {
    $VsWhereOutput = & $VsWhere -latest -products * -requires $AtlComponentId -format json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $VsWhereOutput) {
      return $false
    }

    $Instances = @((($VsWhereOutput -join "`n") | ConvertFrom-Json) | Where-Object { $null -ne $_ })
    return ($Instances | Where-Object { $_.installationPath -eq $InstallPath }).Count -gt 0
  } catch {
    return $false
  }
}

if (-not (Test-Path $Installer)) {
  throw "Visual Studio Installer not found at $Installer"
}

if (-not (Test-Path $VsInstallPath)) {
  throw "Visual Studio install path not found: $VsInstallPath"
}

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
$IsAdmin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
  throw "This script must be run from an elevated PowerShell because Visual Studio Installer requires elevation for --quiet modify operations. Open PowerShell as Administrator, cd to this repository, then run .\scripts\install_vs_atl.ps1."
}

$InstallerArguments = @(
  "modify",
  "--installPath",
  "`"$VsInstallPath`"",
  "--add",
  $AtlComponentId,
  "--quiet",
  "--norestart",
  "--force"
)

$InstallerProcess = Start-Process -FilePath $Installer -ArgumentList $InstallerArguments -Wait -PassThru
$InstallerExitCode = $InstallerProcess.ExitCode
$AcceptedInstallerExitCodes = @(0, 3010)
$InstallerProblem = $null
if ($null -eq $InstallerExitCode) {
  Write-Warning "Visual Studio Installer did not report an exit code; using post-install ATL/MFC verification as the source of truth."
} elseif ($AcceptedInstallerExitCodes -notcontains $InstallerExitCode) {
  $InstallerProblem = "Visual Studio Installer exited with code $InstallerExitCode"
}

$Atldef = Get-AtlHeaderPath -InstallPath $VsInstallPath
$AtlComponentRegistered = Test-AtlComponentRegistered -InstallPath $VsInstallPath
$VerificationProblems = @()
if (-not $Atldef) {
  $VerificationProblems += "atldef.h was not found under $VsInstallPath\VC\Tools\MSVC"
}
if (-not $AtlComponentRegistered) {
  $VerificationProblems += "vswhere does not report $AtlComponentId for $VsInstallPath"
}
if ($VerificationProblems.Count -gt 0) {
  $VerificationFailure = "ATL/MFC post-install verification failed: $($VerificationProblems -join '; ')"
  if ($InstallerProblem) {
    throw "$InstallerProblem; $VerificationFailure"
  }
  throw $VerificationFailure
}

if ($InstallerProblem) {
  Write-Warning "$InstallerProblem, but ATL/MFC post-install verification succeeded; continuing because the Chromium prerequisite is present."
}

if ($InstallerExitCode -eq 3010) {
  Write-Warning "Visual Studio Installer requested a restart. ATL/MFC verification succeeded, so Chromium builds can continue unless later toolchain steps fail."
}

Write-Host "ATL/MFC component install completed: $AtlComponentId"
Write-Host "Verified ATL/MFC header: $Atldef"
Write-Host "Verified Visual Studio component registration: $AtlComponentId"
Write-Host "Next:"
Write-Host "  .\scripts\verify_prebuild.ps1"
Write-Host "  .\scripts\run_post_atl_pipeline.ps1 -RefreshChromiumPin -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -AggressiveWebGl2RelaxedValidation -AggressiveWebGpuSourceFastPath -AggressiveWebGpuUploadFastPath -CaptureTrace -DisableWebGpuTiming -DisableForkWebGpuTiming -RunTrustedExperimentMatrix -RunTrustedWebGpuDawnMatrix -RunTargetedBlockerExperiments -TrustedMatrixZeroCopy -TrustedMatrixWebGlCompositorExperiments -TrustedMatrixWebGpuChromiumFeatureExperiments -TrustedMatrixWebGpuUploadExperiments -TrustedMatrixInProcessGpu -TrustedMatrixSingleProcess -TrustedMatrixAngleBackend d3d11 -TrustedMatrixReservedNoopGates -RunLongStability -MaxRssDeltaMb 128 -MaxRendererResourceDelta 0 -FinalGate"

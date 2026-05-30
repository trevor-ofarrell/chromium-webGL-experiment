[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallScript = Join-Path $Root "scripts\install_vs_atl.ps1"
$PrereqScript = Join-Path $Root "scripts\check_prereqs.ps1"
$ReadmePath = Join-Path $Root "README.md"
$BuildDocPath = Join-Path $Root "docs\build.md"
$InstallText = Get-Content $InstallScript -Raw
$PrereqText = Get-Content $PrereqScript -Raw
$ReadmeText = Get-Content $ReadmePath -Raw
$BuildDocText = Get-Content $BuildDocPath -Raw

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )

  if ($Text -notmatch $Pattern) {
    throw "ATL remediation handoff is missing $Description. Pattern: $Pattern"
  }
}

Assert-Contains $InstallText "Microsoft\.VisualStudio\.Component\.VC\.ATLMFC" "the ATL/MFC component id"
Assert-Contains $InstallText "WindowsBuiltInRole\]::Administrator" "an administrator-role check"
Assert-Contains $InstallText "elevated PowerShell" "a clear elevation failure message"
Assert-Contains $InstallText '"--add",\s+\$AtlComponentId' "the installer component add switch"
Assert-Contains $InstallText "--quiet" "quiet installer mode"
Assert-Contains $InstallText "--norestart" "no-restart installer mode"
Assert-Contains $InstallText "--force" "forced installer modify mode"
Assert-Contains $InstallText "Start-Process" "a waited Visual Studio Installer launch"
Assert-Contains $InstallText "-Wait" "waiting for the Visual Studio Installer process"
Assert-Contains $InstallText "-PassThru" "capturing the Visual Studio Installer process exit code"
Assert-Contains $InstallText "did not report an exit code" "a clear installer exit-code handoff warning"
Assert-Contains $InstallText 'Get-ChildItem\s+\$MsvcRoot\s+-Recurse\s+-Filter\s+atldef\.h' "post-install ATL header verification"
Assert-Contains $InstallText "vswhere\.exe" "post-install component verification through vswhere"
Assert-Contains $InstallText '-requires\s+\$AtlComponentId' "vswhere component requirement check"
Assert-Contains $InstallText "ATL/MFC post-install verification failed" "clear post-install verification failure"
Assert-Contains $InstallText "Verified ATL/MFC header" "post-install header success message"
Assert-Contains $InstallText "Verified Visual Studio component registration" "post-install component success message"
Assert-Contains $InstallText "verify_prebuild\.ps1" "the post-install verifier command"

foreach ($Switch in @(
  "-RefreshChromiumPin",
  "-IncludeWebGPU",
  "-IncludeAggressiveGpu",
  "-AggressiveAngleBackend d3d11",
  "-AggressiveWebGl2RelaxedValidation",
  "-AggressiveWebGpuSourceFastPath",
  "-AggressiveWebGpuUploadFastPath",
  "-CaptureTrace",
  "-DisableWebGpuTiming",
  "-DisableForkWebGpuTiming",
  "-RunTrustedExperimentMatrix",
  "-RunTrustedWebGpuDawnMatrix",
  "-RunTargetedBlockerExperiments",
  "-TrustedMatrixZeroCopy",
  "-TrustedMatrixWebGlCompositorExperiments",
  "-TrustedMatrixWebGpuChromiumFeatureExperiments",
  "-TrustedMatrixWebGpuUploadExperiments",
  "-TrustedMatrixInProcessGpu",
  "-TrustedMatrixSingleProcess",
  "-TrustedMatrixAngleBackend d3d11",
  "-TrustedMatrixReservedNoopGates",
  "-RunLongStability",
  "-MaxRssDeltaMb 128",
  "-MaxRendererResourceDelta 0",
  "-FinalGate"
)) {
  Assert-Contains $InstallText ([regex]::Escape($Switch)) "post-ATL pipeline switch $Switch"
  Assert-Contains $PrereqText ([regex]::Escape($Switch)) "prerequisite remediation post-ATL pipeline switch $Switch"
  Assert-Contains $ReadmeText ([regex]::Escape($Switch)) "README post-ATL pipeline switch $Switch"
  Assert-Contains $BuildDocText ([regex]::Escape($Switch)) "build document post-ATL pipeline switch $Switch"
}

Assert-Contains $PrereqText "Microsoft\.VisualStudio\.Component\.VC\.ATLMFC" "the prerequisite component id"
Assert-Contains $PrereqText "atldef\.h" "the missing ATL header name"
Assert-Contains $PrereqText "install_vs_atl\.ps1" "the prerequisite remediation script"
Assert-Contains $ReadmeText "install_vs_atl\.ps1" "the README ATL install command"
Assert-Contains $BuildDocText "install_vs_atl\.ps1" "the build document ATL install command"

Write-Host "ATL remediation handoff includes elevation guard, component id, post-install header/component verification, and completion-oriented post-install pipeline in scripts and docs."

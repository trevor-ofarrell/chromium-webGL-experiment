[CmdletBinding()]
param(
  [string]$Output = "benchmarks\reports\prebuild-environment.json",
  [switch]$TestAssumeViewerPatchAlreadyApplied
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

if ($TestAssumeViewerPatchAlreadyApplied) {
  $ResolvedOutputForTest = if ([System.IO.Path]::IsPathRooted($Output)) {
    $Output
  } else {
    Join-Path $Root $Output
  }
  $OutputFullPath = [System.IO.Path]::GetFullPath($ResolvedOutputForTest)
  $BenchmarksTmpPath = [System.IO.Path]::GetFullPath((Join-Path $Root "benchmarks\tmp"))
  $BenchmarksTmpPrefix = $BenchmarksTmpPath.TrimEnd("\") + "\"
  if (-not $OutputFullPath.StartsWith($BenchmarksTmpPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "-TestAssumeViewerPatchAlreadyApplied is only valid for outputs under benchmarks\tmp."
  }
}

function Resolve-RepoPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return (Join-Path $Root $PathValue)
}

function Get-GitText {
  param(
    [string]$Repo,
    [string[]]$Arguments
  )
  $OutputText = (& git -C $Repo @Arguments 2>$null)
  if ($LASTEXITCODE -ne 0) {
    return ""
  }
  return ($OutputText -join "`n").Trim()
}

function Get-UpstreamHeadRevision {
  param([string]$Repo)

  $ProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $ProcessInfo.FileName = "git"
  $ProcessInfo.Arguments = "-C `"$Repo`" ls-remote origin HEAD"
  $ProcessInfo.RedirectStandardOutput = $true
  $ProcessInfo.RedirectStandardError = $true
  $ProcessInfo.UseShellExecute = $false
  $ProcessInfo.CreateNoWindow = $true

  $Process = [System.Diagnostics.Process]::new()
  $Process.StartInfo = $ProcessInfo
  try {
    if (-not $Process.Start()) {
      return ""
    }
    if (-not $Process.WaitForExit(60000)) {
      try {
        $Process.Kill()
      } catch {
      }
      return ""
    }
    if ($Process.ExitCode -ne 0) {
      return ""
    }
    $OutputText = $Process.StandardOutput.ReadToEnd()
  } finally {
    $Process.Dispose()
  }

  if (-not $OutputText) {
    return ""
  }

  $FirstLine = @($OutputText -split "`r?`n" | Where-Object { $_ })[0]
  $Parts = $FirstLine -split "\s+"
  if ($Parts.Count -lt 1) {
    return ""
  }

  return $Parts[0].Trim()
}

function Get-FileHashOrNull {
  param([string]$PathValue)
  if (-not (Test-Path $PathValue)) {
    return $null
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
}

function Get-FileLastWriteUtcOrNull {
  param([string]$PathValue)
  if (-not (Test-Path $PathValue)) {
    return $null
  }
  return (Get-Item -LiteralPath $PathValue).LastWriteTimeUtc
}

function Format-DateTimeUtcOrNull {
  param([object]$DateValue)
  if ($null -eq $DateValue) {
    return $null
  }
  return ([datetime]$DateValue).ToUniversalTime().ToString("o")
}

function Get-SisoBuildFailure {
  param([string]$RelativeOutDir)

  $OutDir = Resolve-RepoPath $RelativeOutDir
  $FailedTargetsPath = Join-Path $OutDir ".siso_failed_targets"
  $OutputPath = Join-Path $OutDir "siso_output"
  $BuildNinjaPath = Join-Path $OutDir "build.ninja"
  $BuildNinjaStampPath = Join-Path $OutDir "build.ninja.stamp"
  $FailedTargetsLastWriteUtc = Get-FileLastWriteUtcOrNull $FailedTargetsPath
  $OutputLastWriteUtc = Get-FileLastWriteUtcOrNull $OutputPath
  $BuildNinjaLastWriteUtc = Get-FileLastWriteUtcOrNull $BuildNinjaPath
  $BuildNinjaStampLastWriteUtc = Get-FileLastWriteUtcOrNull $BuildNinjaStampPath
  $FailureLogTimes = @($FailedTargetsLastWriteUtc, $OutputLastWriteUtc) | Where-Object { $null -ne $_ }
  $GnOutputTimes = @($BuildNinjaLastWriteUtc, $BuildNinjaStampLastWriteUtc) | Where-Object { $null -ne $_ }
  $NewestFailureLogUtc = if ($FailureLogTimes.Count -gt 0) {
    $FailureLogTimes | Sort-Object -Descending | Select-Object -First 1
  } else {
    $null
  }
  $NewestGnOutputUtc = if ($GnOutputTimes.Count -gt 0) {
    $GnOutputTimes | Sort-Object -Descending | Select-Object -First 1
  } else {
    $null
  }
  $FailureLogsStaleAfterGnGen = (
    $null -ne $NewestFailureLogUtc -and
    $null -ne $NewestGnOutputUtc -and
    $NewestFailureLogUtc -lt $NewestGnOutputUtc
  )
  $FailureLogsCurrentForGeneratedBuild = (
    $null -ne $NewestFailureLogUtc -and
    (
      $null -eq $NewestGnOutputUtc -or
      $NewestFailureLogUtc -ge $NewestGnOutputUtc
    )
  )
  $Result = [ordered]@{
    out_dir = $RelativeOutDir
    failed_targets_exists = Test-Path $FailedTargetsPath
    siso_output_exists = Test-Path $OutputPath
    requested_targets = @()
    failed_targets = @()
    first_fatal_error = $null
    failed_targets_sha256 = Get-FileHashOrNull $FailedTargetsPath
    siso_output_sha256 = Get-FileHashOrNull $OutputPath
    failed_targets_last_write_utc = Format-DateTimeUtcOrNull $FailedTargetsLastWriteUtc
    siso_output_last_write_utc = Format-DateTimeUtcOrNull $OutputLastWriteUtc
    build_ninja_last_write_utc = Format-DateTimeUtcOrNull $BuildNinjaLastWriteUtc
    build_ninja_stamp_last_write_utc = Format-DateTimeUtcOrNull $BuildNinjaStampLastWriteUtc
    failure_logs_current_for_generated_build = [bool]$FailureLogsCurrentForGeneratedBuild
    failure_logs_stale_after_gn_gen = [bool]$FailureLogsStaleAfterGnGen
  }

  if (Test-Path $FailedTargetsPath) {
    try {
      $FailureJson = Get-Content -LiteralPath $FailedTargetsPath -Raw | ConvertFrom-Json
      $Result.requested_targets = @($FailureJson.targets)
      $Result.failed_targets = @($FailureJson.failed)
    } catch {
      $Result.failed_targets = @("unparseable .siso_failed_targets")
    }
  }

  if (Test-Path $OutputPath) {
    $FatalLine = Get-Content -LiteralPath $OutputPath |
      Where-Object { $_ -match "fatal error:" } |
      Select-Object -First 1
    if ($FatalLine) {
      $Result.first_fatal_error = $FatalLine.Trim()
    }
  }

  [pscustomobject]$Result
}

function Test-GitApply {
  param(
    [string]$Repo,
    [string]$Patch,
    [switch]$Reverse
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Arguments = @("-C", $Repo, "apply")
    if ($Reverse) {
      $Arguments += "--reverse"
    }
    $Arguments += @("--check", $Patch)
    $null = (& git @Arguments 2>$null)
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Add-Check {
  param(
    [System.Collections.Generic.List[object]]$Checks,
    [string]$Name,
    [bool]$Ok,
    [string]$Detail
  )
  $Checks.Add([pscustomobject]@{
    name = $Name
    ok = $Ok
    detail = $Detail
  }) | Out-Null
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

  $ActivePolicyDir = "C:\Windows\System32\CodeIntegrity\CiPolicies\Active"
  $Result = [ordered]@{
    active_policy_ids = @()
    verified_and_reputable_policy_state = $null
    sac_previous_state = $null
    sac_enforcement_reason = $null
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
      $Result.sac_previous_state = $PolicyState.SAC_PreviousState
      $Result.sac_enforcement_reason = $PolicyState.SAC_EnforcementReason
    }
  } catch {
  }

  if (Test-Path $ActivePolicyDir) {
    $Result.active_policy_ids = @(Get-ChildItem $ActivePolicyDir -Filter "*.cip" -ErrorAction SilentlyContinue |
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

function Get-NonLoopbackIPv4Addresses {
  $Results = @()
  foreach ($Interface in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
    if ($Interface.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) {
      continue
    }

    foreach ($AddressInfo in $Interface.GetIPProperties().UnicastAddresses) {
      $Address = $AddressInfo.Address
      if ($Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        continue
      }
      if ([System.Net.IPAddress]::IsLoopback($Address)) {
        continue
      }

      $AddressText = $Address.ToString()
      if ($AddressText.StartsWith("169.254.", [System.StringComparison]::Ordinal)) {
        continue
      }

      $Results += [pscustomobject]@{
        address = $AddressText
        interface_name = $Interface.Name
        interface_type = $Interface.NetworkInterfaceType.ToString()
      }
    }
  }
  return @($Results)
}

function Get-PinRefreshProvenance {
  $RefreshPath = Resolve-RepoPath "benchmarks\reports\chromium-pin-refresh.json"
  $Result = [ordered]@{
    path = "benchmarks\reports\chromium-pin-refresh.json"
    exists = $false
    target_revision = $null
    previous_revision = $null
    selected_from_upstream_head = $false
    selected_at = $null
    source = $null
    generated_at = $null
    target_matches_expected = $false
  }

  if (-not (Test-Path -LiteralPath $RefreshPath)) {
    return [pscustomobject]$Result
  }

  $Result.exists = $true
  try {
    $Parsed = Get-Content -LiteralPath $RefreshPath -Raw | ConvertFrom-Json
    $Result.target_revision = $Parsed.target_revision
    $Result.previous_revision = $Parsed.previous_revision
    $Result.selected_from_upstream_head = [bool]$Parsed.selected_from_upstream_head
    $Result.selected_at = $Parsed.selected_at
    $Result.source = $Parsed.source
    $Result.generated_at = $Parsed.generated_at
    $Result.target_matches_expected = (
      $ExpectedRevision -and
      $Parsed.target_revision -and
      $ExpectedRevision -eq $Parsed.target_revision
    )
  } catch {
    $Result.source = "unparseable"
  }

  return [pscustomobject]$Result
}

$Src = Resolve-RepoPath "src"
$DepotTools = Resolve-RepoPath "tools\depot_tools"
$VisualStudioInstaller = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
$VsWhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$AtlComponentId = "Microsoft.VisualStudio.Component.VC.ATLMFC"
$ChromiumRevisionFile = Resolve-RepoPath ".chromium_revision"
$ExpectedRevision = if (Test-Path $ChromiumRevisionFile) { (Get-Content $ChromiumRevisionFile -Raw).Trim() } else { "" }
$ActualRevision = if (Test-Path (Join-Path $Src ".git")) { Get-GitText $Src @("rev-parse", "HEAD") } else { "" }
$PinRefreshProvenance = Get-PinRefreshProvenance
$TestUpstreamHeadRevision = $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION
if ($TestUpstreamHeadRevision) {
  $OutputFullPathForTest = [System.IO.Path]::GetFullPath((Resolve-RepoPath $Output))
  $BenchmarksTmpPathForTest = [System.IO.Path]::GetFullPath((Join-Path $Root "benchmarks\tmp"))
  $BenchmarksTmpPrefixForTest = $BenchmarksTmpPathForTest.TrimEnd("\") + "\"
  if (-not $OutputFullPathForTest.StartsWith($BenchmarksTmpPrefixForTest, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION is only valid for outputs under benchmarks\tmp."
  }
  $UpstreamHeadRevision = $TestUpstreamHeadRevision
} else {
  $UpstreamHeadRevision = if (Test-Path (Join-Path $Src ".git")) { Get-UpstreamHeadRevision $Src } else { "" }
}
$SrcStatus = if (Test-Path (Join-Path $Src ".git")) { Get-GitText $Src @("status", "--short", "--branch") } else { "" }

$VsPath = $env:vs2022_install
if (-not $VsPath) {
  $VsPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
}

function Get-VsWhereInstances {
  param([string]$RequiredComponent = "")

  if (-not (Test-Path $VsWhere)) {
    return @()
  }

  $Arguments = @("-latest", "-products", "*", "-format", "json")
  if ($RequiredComponent) {
    $Arguments += @("-requires", $RequiredComponent)
  }

  try {
    $OutputText = & $VsWhere @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $OutputText) {
      return @()
    }
    $ParsedInstances = ($OutputText -join "`n") | ConvertFrom-Json
    if ($null -eq $ParsedInstances) {
      return @()
    }
    return @($ParsedInstances | Where-Object { $null -ne $_ })
  } catch {
    return @()
  }
}

$VsInstances = @(Get-VsWhereInstances)
$VsAtlInstances = @(Get-VsWhereInstances $AtlComponentId)
$VsInstance = $VsInstances | Select-Object -First 1

$MsvcRoot = Join-Path $VsPath "VC\Tools\MSVC"
$Atldef = $null
if (Test-Path $MsvcRoot) {
  $Atldef = Get-ChildItem $MsvcRoot -Recurse -Filter atldef.h -ErrorAction SilentlyContinue | Select-Object -First 1
}

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
$IsAdmin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$NonLoopbackIPv4Addresses = @(Get-NonLoopbackIPv4Addresses)
$CodeIntegrityBlock = Get-CodeIntegrityChromiumRustBlock

$PatchPath = Resolve-RepoPath "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
$PatchApplies = $false
$PatchAlreadyApplied = $false
if (Test-Path $PatchPath) {
  $PatchApplies = Test-GitApply $Src $PatchPath
  $PatchAlreadyApplied = Test-GitApply $Src $PatchPath -Reverse
  if ($TestAssumeViewerPatchAlreadyApplied) {
    $PatchApplies = $false
    $PatchAlreadyApplied = $true
  }
}

$Checks = [System.Collections.Generic.List[object]]::new()
Add-Check $Checks "depot_tools" (Test-Path (Join-Path $DepotTools "gclient.py")) $DepotTools
Add-Check $Checks "visual_studio_installer" (Test-Path $VisualStudioInstaller) $VisualStudioInstaller
Add-Check $Checks "chromium_revision" ($ExpectedRevision -and $ActualRevision -eq $ExpectedRevision) "expected=$ExpectedRevision actual=$ActualRevision"
Add-Check $Checks "gclient_entries" (Test-Path (Resolve-RepoPath ".gclient_entries")) (Resolve-RepoPath ".gclient_entries")
Add-Check $Checks "gn" (Test-Path (Join-Path $Src "buildtools\win\gn.exe")) (Join-Path $Src "buildtools\win\gn.exe")
Add-Check $Checks "ninja" (Test-Path (Join-Path $Src "third_party\ninja\ninja.exe")) (Join-Path $Src "third_party\ninja\ninja.exe")
Add-Check $Checks "vs2022_install" (Test-Path $VsPath) $VsPath
Add-Check $Checks "visual_studio_atl" ($null -ne $Atldef) ($(if ($Atldef) { $Atldef.FullName } else { "missing atldef.h" }))
Add-Check $Checks "visual_studio_atl_component" ($VsAtlInstances.Count -gt 0) ($(if ($VsAtlInstances.Count -gt 0) { "vswhere reports $AtlComponentId in $($VsAtlInstances[0].installationPath)" } else { "vswhere does not report component $AtlComponentId" }))
Add-Check $Checks "windows_sdk_debuggers" (Test-Path "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbghelp.dll") "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbghelp.dll"
Add-Check $Checks "windows_code_integrity_chromium_rust" ($CodeIntegrityBlock.blocked_sample_dll_count -eq 0) ($(if ($CodeIntegrityBlock.blocked_sample_dll_count -eq 0) { "no current Code Integrity block when probing existing Chromium Rust proc-macro DLLs; active_policies=$(@($CodeIntegrityBlock.active_policy_ids).Count); recent_block_events=$($CodeIntegrityBlock.recent_block_count); verified_and_reputable_policy_state=$($CodeIntegrityBlock.verified_and_reputable_policy_state)" } else { "current Code Integrity block for Chromium Rust proc-macro DLLs; blocked_samples=$($CodeIntegrityBlock.blocked_sample_dll_count); policy_ids=$(@($CodeIntegrityBlock.recent_policy_ids) -join ','); unblock WDAC/Smart App Control for generated Chromium build DLLs, then rerun the failed build" }))
Add-Check $Checks "viewer_dist" (Test-Path (Resolve-RepoPath "viewer\dist\index.html")) (Resolve-RepoPath "viewer\dist\index.html")
Add-Check $Checks "viewer_patch_available" (Test-Path $PatchPath) $PatchPath
Add-Check $Checks "viewer_patch_state" ($PatchApplies -or $PatchAlreadyApplied) ($(if ($PatchApplies) { "applies cleanly" } elseif ($PatchAlreadyApplied) { "already applied" } else { "not applicable" }))
Add-Check $Checks "navigation_external_ipv4" ($NonLoopbackIPv4Addresses.Count -gt 0) ($(if ($NonLoopbackIPv4Addresses.Count -gt 0) { (@($NonLoopbackIPv4Addresses | ForEach-Object { "$($_.address) on $($_.interface_name)" }) -join "; ") } else { "no non-loopback IPv4 address available for external HTTP navigation-lock smoke" }))

$GnArgFiles = @(
  "build\gn_args\baseline_content_shell.gn",
  "build\gn_args\fork_safe_content_shell.gn",
  "build\gn_args\fork_trusted_aggressive.gn",
  "src\out\ReleaseBaseline\args.gn",
  "src\out\ReleaseViewerDefault\args.gn",
  "src\out\ReleaseViewerTrustedAggressive\args.gn"
) | ForEach-Object {
  $PathValue = Resolve-RepoPath $_
  [pscustomobject]@{
    path = $_
    exists = Test-Path $PathValue
    sha256 = Get-FileHashOrNull $PathValue
  }
}

$Binaries = @(
  "src\out\ReleaseBaseline\content_shell.exe",
  "src\out\ReleaseViewerDefault\content_shell.exe"
) | ForEach-Object {
  $PathValue = Resolve-RepoPath $_
  $Exists = Test-Path $PathValue
  [pscustomobject]@{
    path = $_
    exists = $Exists
    size_bytes = if ($Exists) { (Get-Item -LiteralPath $PathValue).Length } else { $null }
    sha256 = Get-FileHashOrNull $PathValue
  }
}

$BuildFailures = @(
  Get-SisoBuildFailure "src\out\ReleaseBaseline"
  Get-SisoBuildFailure "src\out\ReleaseViewerDefault"
)

$Manifest = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  root = $Root.ProviderPath
  user = $Identity.Name
  is_admin = $IsAdmin
  platform = [pscustomobject]@{
    os = [System.Environment]::OSVersion.VersionString
    architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    powershell_version = $PSVersionTable.PSVersion.ToString()
  }
  chromium = [pscustomobject]@{
    expected_revision = $ExpectedRevision
    actual_revision = $ActualRevision
    upstream_head_revision = $UpstreamHeadRevision
    upstream_head_checked_at = (Get-Date).ToUniversalTime().ToString("o")
    upstream_head_matches_expected = ($ExpectedRevision -and $UpstreamHeadRevision -and $ExpectedRevision -eq $UpstreamHeadRevision)
    pin_refresh = $PinRefreshProvenance
    status_short = $SrcStatus -split "`n"
  }
  environment = [pscustomobject]@{
    DEPOT_TOOLS_WIN_TOOLCHAIN = $env:DEPOT_TOOLS_WIN_TOOLCHAIN
    vs2022_install = $VsPath
    visual_studio_installer = $VisualStudioInstaller
    visual_studio_vswhere = $VsWhere
    atl_component_id = $AtlComponentId
    visual_studio_instance = if ($VsInstance) {
      [pscustomobject]@{
        instance_id = $VsInstance.instanceId
        installation_path = $VsInstance.installationPath
        installation_version = $VsInstance.installationVersion
        product_id = $VsInstance.productId
        is_complete = $VsInstance.isComplete
        is_launchable = $VsInstance.isLaunchable
        is_reboot_required = $VsInstance.isRebootRequired
      }
    } else {
      $null
    }
    atl_component_reported_by_vswhere = ($VsAtlInstances.Count -gt 0)
    navigation_external_ipv4_addresses = $NonLoopbackIPv4Addresses
    windows_code_integrity = $CodeIntegrityBlock
    test_assumed_viewer_patch_already_applied = [bool]$TestAssumeViewerPatchAlreadyApplied
  }
  patch = [pscustomobject]@{
    path = "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
    exists = Test-Path $PatchPath
    applies_cleanly = $PatchApplies
    already_applied = $PatchAlreadyApplied
    sha256 = Get-FileHashOrNull $PatchPath
  }
  gn_args = $GnArgFiles
  binaries = $Binaries
  build_failures = $BuildFailures
  checks = $Checks
  ok = -not ($Checks | Where-Object { -not $_.ok })
}

$OutputPath = Resolve-RepoPath $Output
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
Set-Content -LiteralPath $OutputPath -Value (($Manifest | ConvertTo-Json -Depth 8) + "`n") -Encoding UTF8
Write-Host "Wrote $OutputPath"
if (-not $Manifest.ok) {
  Write-Host "Environment manifest contains failing checks."
}

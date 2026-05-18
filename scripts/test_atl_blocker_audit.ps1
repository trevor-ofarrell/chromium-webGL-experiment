[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\atl-blocker-audit"

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

function Set-Check {
  param(
    [object]$Manifest,
    [string]$Name,
    [bool]$Ok,
    [string]$Detail
  )

  $Matches = @($Manifest.checks | Where-Object { $_.name -eq $Name })
  if ($Matches.Count -ne 1) {
    throw "Expected exactly one check named $Name in synthetic manifest."
  }
  $Matches[0].ok = $Ok
  $Matches[0].detail = $Detail
}

function New-SyntheticManifest {
  param(
    [string]$Name,
    [bool]$CurrentFailure,
    [bool]$StaleFailure,
    [bool]$IncludeFailure = $true
  )

  $ManifestRel = "benchmarks\tmp\atl-blocker-audit\$Name-manifest.json"
  $OldObservedHead = $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION
  $ExpectedRevision = (Get-Content -LiteralPath (Join-Path $Root ".chromium_revision") -Raw).Trim()
  $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION = $ExpectedRevision
  try {
    $null = & (Join-Path $Root "scripts\write_environment_manifest.ps1") -Output $ManifestRel *>&1
  } finally {
    if ($null -eq $OldObservedHead) {
      Remove-Item Env:\THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION = $OldObservedHead
    }
  }

  $ManifestPath = Join-Path $Root $ManifestRel
  $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  Set-Check $Manifest "visual_studio_atl" $false "missing atldef.h"
  Set-Check $Manifest "visual_studio_atl_component" $false "vswhere does not report component Microsoft.VisualStudio.Component.VC.ATLMFC"

  if ($IncludeFailure) {
    $Failure = [pscustomobject]@{
      out_dir = "src\out\ReleaseBaseline"
      failed_targets_exists = $true
      siso_output_exists = $true
      requested_targets = @("content_shell")
      failed_targets = @("obj/base/base/atl_throw.obj")
      first_fatal_error = "../..\base/win/atl_throw.h(35,10): fatal error: 'atldef.h' file not found"
      failed_targets_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      siso_output_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      failed_targets_last_write_utc = "2026-05-18T00:00:00Z"
      siso_output_last_write_utc = "2026-05-18T00:00:00Z"
      build_ninja_last_write_utc = "2026-05-17T00:00:00Z"
      build_ninja_stamp_last_write_utc = "2026-05-17T00:00:00Z"
      failure_logs_current_for_generated_build = $CurrentFailure
      failure_logs_stale_after_gn_gen = $StaleFailure
    }
    $Manifest.build_failures = @(
      $Failure,
      [pscustomobject]@{
        out_dir = "src\out\ReleaseViewerDefault"
        failed_targets_exists = $false
        siso_output_exists = $false
        requested_targets = @()
        failed_targets = @()
        first_fatal_error = $null
        failed_targets_sha256 = $null
        siso_output_sha256 = $null
        failed_targets_last_write_utc = $null
        siso_output_last_write_utc = $null
        build_ninja_last_write_utc = "2026-05-17T00:00:00Z"
        build_ninja_stamp_last_write_utc = "2026-05-17T00:00:00Z"
        failure_logs_current_for_generated_build = $false
        failure_logs_stale_after_gn_gen = $false
      }
    )
  } else {
    $Manifest.build_failures = @()
  }

  $Manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  return $ManifestRel
}

function Invoke-AtlAudit {
  param(
    [string]$Name,
    [string]$ManifestRel
  )

  $AuditRel = "benchmarks\tmp\atl-blocker-audit\$Name-audit.md"
  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") `
    -Output $AuditRel `
    -EnvironmentManifest $ManifestRel `
    -BuildStateOnly *>&1
  return Get-Content -LiteralPath (Join-Path $Root $AuditRel) -Raw
}

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  $CurrentManifest = New-SyntheticManifest "current" -CurrentFailure $true -StaleFailure $false
  $CurrentAudit = Invoke-AtlAudit "current" $CurrentManifest
  if ($CurrentAudit -notmatch "\| Build \| Host prerequisite: Visual Studio ATL/MFC \| blocked \|") {
    throw "Current ATL blocker manifest did not produce a blocked ATL row."
  }
  if ($CurrentAudit -notmatch "latest src\\out\\ReleaseBaseline failure: obj/base/base/atl_throw.obj") {
    throw "Current ATL blocker manifest did not report the latest baseline failure target."
  }
  if ($CurrentAudit -notmatch "fatal error: 'atldef.h' file not found") {
    throw "Current ATL blocker manifest did not report the missing atldef.h fatal error."
  }

  $StaleManifest = New-SyntheticManifest "stale" -CurrentFailure $false -StaleFailure $true
  $StaleAudit = Invoke-AtlAudit "stale" $StaleManifest
  if ($StaleAudit -notmatch "\| Build \| Host prerequisite: Visual Studio ATL/MFC \| blocked \|") {
    throw "Stale ATL blocker manifest did not produce a blocked ATL row."
  }
  if ($StaleAudit -notmatch "prior src\\out\\ReleaseBaseline failure logs are older than latest GN generation") {
    throw "Stale ATL blocker manifest did not report stale baseline failure logs."
  }
  if ($StaleAudit -match "latest src\\out\\ReleaseBaseline failure") {
    throw "Stale ATL blocker manifest was incorrectly reported as a latest failure."
  }

  $NoFailureManifest = New-SyntheticManifest "no-failure" -CurrentFailure $false -StaleFailure $false -IncludeFailure $false
  $NoFailureAudit = Invoke-AtlAudit "no-failure" $NoFailureManifest
  if ($NoFailureAudit -notmatch "\| Build \| Host prerequisite: Visual Studio ATL/MFC \| blocked \| missing atldef.h; vswhere does not report component Microsoft\.VisualStudio\.Component\.VC\.ATLMFC") {
    throw "ATL blocker manifest without build failure logs did not preserve the prerequisite probe evidence."
  }
  if ($NoFailureAudit -match "latest src\\out\\ReleaseBaseline failure|prior src\\out\\ReleaseBaseline failure logs") {
    throw "ATL blocker manifest without build failure logs reported build-failure evidence."
  }
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "ATL blocker audit distinguishes current build failure logs, stale logs, and prerequisite-only evidence."

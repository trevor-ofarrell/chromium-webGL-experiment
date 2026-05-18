[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\environment-manifest-test"
$OutputRel = "benchmarks\tmp\environment-manifest-test\prebuild-environment-test.json"
$OutputPath = Join-Path $Root $OutputRel
$ManifestScriptPath = Join-Path $Root "scripts\write_environment_manifest.ps1"

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

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) {
    throw $Message
  }
}

function Assert-PathEntry {
  param(
    [object[]]$Entries,
    [string]$PathValue,
    [string]$CollectionName
  )
  $Matches = @($Entries | Where-Object { $_.path -eq $PathValue })
  Assert-True ($Matches.Count -eq 1) "$CollectionName does not contain exactly one entry for $PathValue."
  return $Matches[0]
}

try {
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
  $ExpectedRevision = (Get-Content (Join-Path $Root ".chromium_revision") -Raw).Trim()
  $OldTestUpstreamHeadRevision = $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION
  $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION = $ExpectedRevision
  try {
    & (Join-Path $Root "scripts\write_environment_manifest.ps1") -Output $OutputRel | Out-Null
  } finally {
    $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION = $OldTestUpstreamHeadRevision
  }

  Assert-True (Test-Path $OutputPath) "Environment manifest test output was not written."
  $Manifest = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json

  Assert-True ($Manifest.root -eq $Root.ProviderPath) "Manifest root does not match repository root."
  Assert-True ($Manifest.chromium.expected_revision -eq $ExpectedRevision) "Manifest expected Chromium revision is incorrect."
  Assert-True ($Manifest.chromium.actual_revision -eq $ExpectedRevision) "Manifest actual Chromium revision is incorrect."
  Assert-True ([string]::IsNullOrWhiteSpace($Manifest.chromium.upstream_head_revision) -eq $false) "Manifest does not record upstream Chromium HEAD."
  Assert-True ([string]::IsNullOrWhiteSpace($Manifest.chromium.upstream_head_checked_at) -eq $false) "Manifest does not record when upstream Chromium HEAD was checked."
  Assert-True ($null -ne $Manifest.chromium.upstream_head_matches_expected) "Manifest does not record whether upstream Chromium HEAD matches the pinned revision."
  Assert-True ($null -ne $Manifest.chromium.pin_refresh) "Manifest does not record Chromium pin refresh provenance."
  foreach ($PropertyName in @(
    "path",
    "exists",
    "target_revision",
    "selected_from_upstream_head",
    "selected_at",
    "source",
    "target_matches_expected"
  )) {
    Assert-True ($null -ne $Manifest.chromium.pin_refresh.PSObject.Properties[$PropertyName]) "Manifest Chromium pin_refresh entry lacks $PropertyName."
  }
  Assert-True ($Manifest.environment.atl_component_id -eq "Microsoft.VisualStudio.Component.VC.ATLMFC") "Manifest does not record the ATL/MFC component id."
  Assert-True ([string]::IsNullOrWhiteSpace($Manifest.environment.visual_studio_vswhere) -eq $false) "Manifest does not record the Visual Studio vswhere path."
  Assert-True ($null -ne $Manifest.environment.atl_component_reported_by_vswhere) "Manifest does not record whether vswhere reports the ATL/MFC component."
  Assert-True ($null -ne $Manifest.environment.navigation_external_ipv4_addresses) "Manifest does not record non-loopback IPv4 addresses for external navigation smoke."
  if ($Manifest.environment.visual_studio_instance) {
    Assert-True ([string]::IsNullOrWhiteSpace($Manifest.environment.visual_studio_instance.installation_path) -eq $false) "Manifest Visual Studio instance lacks installation_path."
    Assert-True ([string]::IsNullOrWhiteSpace($Manifest.environment.visual_studio_instance.installation_version) -eq $false) "Manifest Visual Studio instance lacks installation_version."
  }
  Assert-True ($null -ne $Manifest.is_admin) "Manifest does not record administrator state."
  Assert-True ($Manifest.patch.exists -eq $true) "Manifest does not record the viewer patch as present."
  Assert-True (($Manifest.patch.applies_cleanly -eq $true) -or ($Manifest.patch.already_applied -eq $true)) "Manifest patch state is neither clean-applying nor already-applied."
  Assert-True ([string]::IsNullOrWhiteSpace($Manifest.patch.sha256) -eq $false) "Manifest does not record a viewer patch hash."

  foreach ($PathValue in @(
    "build\gn_args\baseline_content_shell.gn",
    "build\gn_args\fork_safe_content_shell.gn",
    "build\gn_args\fork_trusted_aggressive.gn",
    "src\out\ReleaseBaseline\args.gn",
    "src\out\ReleaseViewerDefault\args.gn",
    "src\out\ReleaseViewerTrustedAggressive\args.gn"
  )) {
    $Entry = Assert-PathEntry @($Manifest.gn_args) $PathValue "gn_args"
    if ($Entry.exists) {
      Assert-True ([string]::IsNullOrWhiteSpace($Entry.sha256) -eq $false) "GN args entry $PathValue exists but lacks a sha256 hash."
    }
  }

  foreach ($PathValue in @(
    "src\out\ReleaseBaseline\content_shell.exe",
    "src\out\ReleaseViewerDefault\content_shell.exe"
  )) {
    $Entry = Assert-PathEntry @($Manifest.binaries) $PathValue "binaries"
    if ($Entry.exists) {
      Assert-True ($Entry.size_bytes -gt 0) "Binary entry $PathValue exists but has no positive size."
      Assert-True ([string]::IsNullOrWhiteSpace($Entry.sha256) -eq $false) "Binary entry $PathValue exists but lacks a sha256 hash."
    }
  }

  foreach ($Name in @(
    "depot_tools",
    "visual_studio_installer",
    "chromium_revision",
    "gclient_entries",
    "gn",
    "ninja",
    "vs2022_install",
    "visual_studio_atl",
    "visual_studio_atl_component",
    "windows_sdk_debuggers",
    "viewer_dist",
    "viewer_patch_available",
    "viewer_patch_state",
    "navigation_external_ipv4"
  )) {
    $Matches = @($Manifest.checks | Where-Object { $_.name -eq $Name })
    Assert-True ($Matches.Count -eq 1) "Manifest checks do not contain exactly one $Name entry."
    Assert-True ($null -ne $Matches[0].ok) "Manifest check $Name lacks ok state."
  }

  foreach ($OutDir in @(
    "src\out\ReleaseBaseline",
    "src\out\ReleaseViewerDefault"
  )) {
    $Matches = @($Manifest.build_failures | Where-Object { $_.out_dir -eq $OutDir })
    Assert-True ($Matches.Count -eq 1) "Manifest build_failures does not contain exactly one $OutDir entry."
    foreach ($PropertyName in @(
      "failed_targets_last_write_utc",
      "siso_output_last_write_utc",
      "build_ninja_last_write_utc",
      "build_ninja_stamp_last_write_utc",
      "failure_logs_current_for_generated_build",
      "failure_logs_stale_after_gn_gen"
    )) {
      Assert-True ($null -ne $Matches[0].PSObject.Properties[$PropertyName]) "Manifest build failure entry $OutDir lacks $PropertyName."
    }
  }

  $ParserErrors = $null
  $Tokens = $null
  $Ast = [System.Management.Automation.Language.Parser]::ParseFile($ManifestScriptPath, [ref]$Tokens, [ref]$ParserErrors)
  Assert-True ($ParserErrors.Count -eq 0) "write_environment_manifest.ps1 has parser errors: $($ParserErrors[0].Message)"
  foreach ($FunctionName in @(
    "Resolve-RepoPath",
    "Get-FileHashOrNull",
    "Get-FileLastWriteUtcOrNull",
    "Format-DateTimeUtcOrNull",
    "Get-SisoBuildFailure"
  )) {
    $FunctionAst = $Ast.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
          $Node.Name -eq $FunctionName
      }, $true)
    Assert-True ($null -ne $FunctionAst) "write_environment_manifest.ps1 does not define $FunctionName."
    . ([scriptblock]::Create($FunctionAst.Extent.Text))
  }

  $SyntheticOutRel = "benchmarks\tmp\environment-manifest-test\synthetic-out"
  $SyntheticOutDir = Join-Path $Root $SyntheticOutRel
  New-Item -ItemType Directory -Path $SyntheticOutDir -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $SyntheticOutDir ".siso_failed_targets") -Value (@{
      targets = @("content_shell")
      failed = @("obj/base/base/atl_throw.obj")
    } | ConvertTo-Json -Depth 4) -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $SyntheticOutDir "siso_output") -Value "../..\base/win/atl_throw.h(35,10): fatal error: 'atldef.h' file not found" -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $SyntheticOutDir "build.ninja") -Value "ninja" -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $SyntheticOutDir "build.ninja.stamp") -Value "" -Encoding UTF8

  $OldFailureTime = [datetime]"2026-01-01T00:00:00Z"
  $NewGnTime = [datetime]"2026-01-02T00:00:00Z"
  (Get-Item -LiteralPath (Join-Path $SyntheticOutDir ".siso_failed_targets")).LastWriteTimeUtc = $OldFailureTime
  (Get-Item -LiteralPath (Join-Path $SyntheticOutDir "siso_output")).LastWriteTimeUtc = $OldFailureTime
  (Get-Item -LiteralPath (Join-Path $SyntheticOutDir "build.ninja")).LastWriteTimeUtc = $NewGnTime
  (Get-Item -LiteralPath (Join-Path $SyntheticOutDir "build.ninja.stamp")).LastWriteTimeUtc = $NewGnTime
  $StaleFailure = Get-SisoBuildFailure $SyntheticOutRel
  Assert-True ($StaleFailure.failure_logs_stale_after_gn_gen -eq $true) "Synthetic stale build failure was not marked stale after GN generation."
  Assert-True ($StaleFailure.failure_logs_current_for_generated_build -eq $false) "Synthetic stale build failure was marked current."

  $FreshFailureTime = [datetime]"2026-01-03T00:00:00Z"
  (Get-Item -LiteralPath (Join-Path $SyntheticOutDir ".siso_failed_targets")).LastWriteTimeUtc = $FreshFailureTime
  (Get-Item -LiteralPath (Join-Path $SyntheticOutDir "siso_output")).LastWriteTimeUtc = $FreshFailureTime
  $FreshFailure = Get-SisoBuildFailure $SyntheticOutRel
  Assert-True ($FreshFailure.failure_logs_stale_after_gn_gen -eq $false) "Synthetic fresh build failure was marked stale after GN generation."
  Assert-True ($FreshFailure.failure_logs_current_for_generated_build -eq $true) "Synthetic fresh build failure was not marked current."

  Write-Host "Environment manifest coverage includes revisions, upstream HEAD observation, patch state, GN args, binaries, prerequisites, navigation-test network state, and build-failure freshness slots."
} finally {
  if (Test-Path $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

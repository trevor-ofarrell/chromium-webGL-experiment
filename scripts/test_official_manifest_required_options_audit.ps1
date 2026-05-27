[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\official-manifest-required-options-audit"
$ManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$TempOutput = Join-Path $TempDir "official-manifest-required-options-audit.md"

function Write-Manifest {
  param(
    [switch]$IncludeWebGPU,
    [switch]$IncludeAggressiveGpu,
    [string]$AggressiveAngleBackend = "",
    [switch]$AggressiveWebGl2RelaxedValidation,
    [switch]$AggressiveWebGpuSourceFastPath,
    [switch]$AggressiveWebGpuUploadFastPath,
    [switch]$CaptureTrace,
    [switch]$IncludePackages
  )

  $Manifest = [pscustomobject]@{
    options = [pscustomobject]@{
      include_webgpu = [bool]$IncludeWebGPU
      include_aggressive_gpu = [bool]$IncludeAggressiveGpu
      aggressive_angle_backend = $AggressiveAngleBackend
      aggressive_webgl2_relaxed_validation = [bool]$AggressiveWebGl2RelaxedValidation
      aggressive_webgpu_source_fast_path = [bool]$AggressiveWebGpuSourceFastPath
      aggressive_webgpu_upload_fast_path = [bool]$AggressiveWebGpuUploadFastPath
      capture_trace = [bool]$CaptureTrace
    }
    package_dirs = [pscustomobject]@{
      baseline = if ($IncludePackages) { Join-Path $TempDir "baseline-package" } else { "" }
      fork = if ($IncludePackages) { Join-Path $TempDir "fork-package" } else { "" }
    }
  }

  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
}

function Invoke-ManifestAudit {
  $OldAllowManifestOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
  $OldOfficialManifestPath = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
  $OldSkipTrustedProvenance = $env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST
  $OldSkipOfficialProvenance = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST
  $OldSkipAggressive = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST
  $OldSkipWebGpu = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST
  $OldSkipReport = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST
  $OldSkipRuntime = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST
  $OldSkipTrace = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST
  $OldSkipRequiredOptions = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST
  $OldSkipPackage = $env:THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST
  $OldSkipArtifactPath = $env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST

  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $ManifestPath
  $env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST = "1"

  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -ManifestAuditOnly -Output $TempOutput *>&1
  } finally {
    $Restore = @{
      THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowManifestOverrides
      THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OldOfficialManifestPath
      THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST = $OldSkipTrustedProvenance
      THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST = $OldSkipOfficialProvenance
      THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST = $OldSkipAggressive
      THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST = $OldSkipWebGpu
      THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST = $OldSkipReport
      THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST = $OldSkipRuntime
      THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST = $OldSkipTrace
      THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST = $OldSkipRequiredOptions
      THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST = $OldSkipPackage
      THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST = $OldSkipArtifactPath
    }
    foreach ($Name in $Restore.Keys) {
      if ($null -eq $Restore[$Name]) {
        Remove-Item "Env:\$Name" -ErrorAction SilentlyContinue
      } else {
        Set-Item "Env:\$Name" $Restore[$Name]
      }
    }
  }

  return Get-Content -LiteralPath $TempOutput -Raw
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Official manifest required-options audit assertion failed: $Description. Pattern: $Pattern"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -match $Pattern) {
    throw "Official manifest required-options audit assertion failed: unexpected $Description. Pattern: $Pattern"
  }
}

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

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
try {
  Write-Manifest
  $MissingText = Invoke-ManifestAudit
  Assert-Contains $MissingText "Official comparison required options.*pending.*include_webgpu" "missing WebGPU option is reported"
  Assert-Contains $MissingText "Official comparison required options.*pending.*include_aggressive_gpu" "missing aggressive GPU option is reported"
  Assert-Contains $MissingText "Official comparison required options.*pending.*aggressive_angle_backend" "missing aggressive ANGLE backend option is reported"
  Assert-Contains $MissingText "Official comparison required options.*pending.*aggressive_webgl2_relaxed_validation" "missing WebGL2 relaxed-validation aggressive profile option is reported"
  Assert-Contains $MissingText "Official comparison required options.*pending.*aggressive_webgpu_source_fast_path" "missing WebGPU source fast-path aggressive profile option is reported"
  Assert-Contains $MissingText "Official comparison required options.*pending.*aggressive_webgpu_upload_fast_path" "missing WebGPU upload fast-path aggressive profile option is reported"
  Assert-Contains $MissingText "Official comparison required options.*pending.*capture_trace" "missing trace option is reported"
  Assert-Contains $MissingText "Official comparison required options.*pending.*baseline_package_dir" "missing baseline package dir is reported"
  Assert-Contains $MissingText "Official comparison required options.*pending.*fork_package_dir" "missing fork package dir is reported"

  Write-Manifest -IncludeWebGPU -IncludeAggressiveGpu -CaptureTrace -IncludePackages
  $MissingBackendText = Invoke-ManifestAudit
  Assert-Contains $MissingBackendText "Official comparison required options.*pending.*aggressive_angle_backend" "otherwise complete manifest without aggressive ANGLE backend remains pending"
  Assert-Contains $MissingBackendText "Official comparison required options.*pending.*aggressive_webgl2_relaxed_validation" "otherwise complete manifest without WebGL2 relaxed-validation profile remains pending"
  Assert-Contains $MissingBackendText "Official comparison required options.*pending.*aggressive_webgpu_source_fast_path" "otherwise complete manifest without WebGPU source fast-path profile remains pending"
  Assert-Contains $MissingBackendText "Official comparison required options.*pending.*aggressive_webgpu_upload_fast_path" "otherwise complete manifest without WebGPU upload fast-path profile remains pending"
  Assert-NotContains $MissingBackendText "Official comparison required options.*done" "missing aggressive backend is not accepted as complete evidence"

  Write-Manifest -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend "d3d11" -AggressiveWebGl2RelaxedValidation -AggressiveWebGpuSourceFastPath -AggressiveWebGpuUploadFastPath -CaptureTrace -IncludePackages
  $CompleteText = Invoke-ManifestAudit
  Assert-Contains $CompleteText "Official comparison required options.*done.*WebGPU, aggressive GPU, aggressive ANGLE backend, WebGL2 relaxed-validation aggressive profile, WebGPU source/upload aggressive profiles, trace capture, baseline package dir, and fork package dir" "complete official option evidence is accepted"
  Assert-NotContains $CompleteText "Official comparison required options.*pending" "pending required-options row after complete evidence"
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Official manifest required-options audit requires WebGPU, aggressive GPU, an aggressive ANGLE backend, WebGL2 relaxed-validation aggressive profile, WebGPU source/upload aggressive profiles, trace capture, and baseline/fork package dirs."

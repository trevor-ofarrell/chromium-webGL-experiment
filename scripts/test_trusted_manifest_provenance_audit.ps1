[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\trusted-manifest-provenance-audit"
$ManifestPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.json"
$BackupPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.provenance-audit.backup.json"
$PinRefreshPath = Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json"
$PinRefreshBackupPath = Join-Path $TempDir "chromium-pin-refresh.trusted-provenance-audit.backup.json"
$TempOutput = Join-Path $TempDir "trusted-manifest-provenance-audit.md"
$RequiredScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

function Get-GitRevision {
  param([string]$RepoPath)
  $Revision = (& git -C $RepoPath rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $Revision) {
    throw "Unable to read git revision from $RepoPath"
  }
  return $Revision
}

function Get-ShortSha256 {
  param([string]$PathValue)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.Substring(0, 12).ToLowerInvariant()
}

function New-FileMetadata {
  param([string]$PathValue)
  [pscustomobject]@{
    path = $PathValue
    exists = $true
    size_bytes = 123
    sha256 = "0123456789abcdef"
  }
}

function New-ResultFiles {
  param([string]$Label)
  @($RequiredScenes | ForEach-Object {
    Join-Path $Root "benchmarks\raw\$Label-$_-webgl2.json"
  })
}

function New-MetadataList {
  param([string[]]$Paths)
  @($Paths | ForEach-Object { New-FileMetadata $_ })
}

function New-Experiment {
  param(
    [string]$Label,
    [string[]]$Flags
  )
  $ExpectedFlagMetadata = @()
  for ($Index = 0; $Index -lt $Flags.Count; $Index += 1) {
    if ($Flags[$Index] -eq "--viewerForceAngleBackend" -and $Index + 1 -lt $Flags.Count) {
      $Backend = $Flags[$Index + 1]
      $ExpectedFlagMetadata += "viewer_force_angle_backend=$Backend"
      $ExpectedFlagMetadata += "requested_angle_backend=$Backend"
    }
  }
  [pscustomobject]@{
    label = $Label
    description = "synthetic trusted provenance audit experiment"
    flags = $Flags
    expected_flag_metadata = $ExpectedFlagMetadata
    result_files = New-ResultFiles $Label
  }
}

function New-ValidTrustedManifest {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PatchHash = Get-ShortSha256 (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
  $ForkRevision = "$ChromiumRevision+viewerpatch-$PatchHash"
  $Experiments = @(
    (New-Experiment "fork-viewer-exp-default" @())
    (New-Experiment "fork-viewer-exp-aggressive-gpu" @("--viewerAggressiveGpu"))
    (New-Experiment "fork-viewer-exp-in-process-gpu" @("--viewerInProcessGpu"))
    (New-Experiment "fork-viewer-exp-single-process" @("--viewerSingleProcess"))
    (New-Experiment "fork-viewer-exp-angle-d3d11" @("--viewerForceAngleBackend", "d3d11"))
    (New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" @("--viewerRelaxedWebglValidation"))
    (New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" @("--viewerDisableUnneededBlinkFeatures"))
    (New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" @("--viewerDirectGpuPresentation"))
  )
  $AllResultFiles = @($Experiments | ForEach-Object { $_.result_files })

  [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browser = "fork.exe"
    build_args = "fork-args.gn"
    package_dir = ""
    renderer = "webgl2"
    scenes = $RequiredScenes
    suite_validation = [pscustomobject]@{
      expected_scenes = $RequiredScenes
      require_checkout = $true
      require_build_args = $true
      expected_build_args_hash = "0123456789abcdef"
      require_fork_revision = $true
      expected_fork_revision = $ForkRevision
      forbid_smoke = $true
      reject_software_rendering = $true
      require_gpu_metadata = $true
      require_frame_times = $true
      expected_chromium_revision = $ChromiumRevision
      expected_browser = "fork.exe"
      expected_measured_seconds = 60
      expected_warmup_seconds = 10
      exact_scene_output_files = $true
      expected_flag_metadata = $true
    }
    options = [pscustomobject]@{
      duration = 60
      warmup = 10
    }
    experiments = $Experiments
    result_files = [pscustomobject]@{
      all = $AllResultFiles
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        browser = New-FileMetadata "fork.exe"
        build_args = New-FileMetadata "fork-args.gn"
        package = [pscustomobject]@{
          path = $null
          exists = $false
          file_count = 0
          size_bytes = 0
        }
      }
      results = [pscustomobject]@{
        all = New-MetadataList $AllResultFiles
      }
      reports = [pscustomobject]@{
        summary = New-FileMetadata "trusted-summary.md"
        comparison = New-FileMetadata "trusted-comparison.md"
      }
    }
  }
}

function Invoke-AuditAndReadChecklist {
  $OldValues = @{}
  foreach ($Name in @(
    "THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST",
    "THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST",
    "THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES",
    "THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST"
  )) {
    $OldValues[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($Name -eq "THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES") {
      Set-Item "Env:\$Name" "1"
    } elseif ($Name -eq "THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST") {
      Set-Item "Env:\$Name" $ManifestPath
    } else {
      Set-Item "Env:\$Name" "1"
    }
  }

  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $TempOutput -ManifestAuditOnly *>&1
  } finally {
    foreach ($Name in $OldValues.Keys) {
      if ($null -eq $OldValues[$Name]) {
        Remove-Item "Env:\$Name" -ErrorAction SilentlyContinue
      } else {
        Set-Item "Env:\$Name" $OldValues[$Name]
      }
    }
  }

  Get-Content -LiteralPath $TempOutput -Raw
}

function Assert-AuditRejects {
  param(
    [scriptblock]$Mutate,
    [string]$Pattern,
    [string]$Description
  )
  $Manifest = New-ValidTrustedManifest
  & $Mutate $Manifest
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch $Pattern) {
    throw "Artifact audit accepted or misreported a completed trusted matrix manifest with $Description."
  }
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$HadManifest = Test-Path -LiteralPath $ManifestPath
$HadPinRefresh = Test-Path -LiteralPath $PinRefreshPath
if ($HadManifest) {
  Copy-Item -LiteralPath $ManifestPath -Destination $BackupPath -Force
}
if ($HadPinRefresh) {
  Copy-Item -LiteralPath $PinRefreshPath -Destination $PinRefreshBackupPath -Force
}

try {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PinSelectedAt = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString("o")
  $SyntheticPinRefresh = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    target_revision = $ChromiumRevision
    previous_revision = $ChromiumRevision
    selected_from_upstream_head = $true
    selected_at = $PinSelectedAt
    source = "synthetic trusted provenance audit test"
    skip_sync = $true
    skip_hooks = $true
    skip_gn_gen = $true
  }
  New-Item -ItemType Directory -Path (Split-Path $PinRefreshPath -Parent) -Force | Out-Null
  $SyntheticPinRefresh | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PinRefreshPath -Encoding UTF8

  Assert-AuditRejects { param($Manifest) $Manifest.dry_run = $true } "Trusted experiment matrix manifest.*pending.*dry-run manifest" "dry_run=true"
  Assert-AuditRejects { param($Manifest) $Manifest.phase = "planned" } "Trusted experiment matrix manifest.*pending.*phase=planned" "phase other than completed"
  Assert-AuditRejects { param($Manifest) $Manifest.chromium_revision = "stale-chromium-revision" } "Trusted experiment matrix manifest.*pending.*chromium_revision=stale-chromium-revision" "stale Chromium revision"
  Assert-AuditRejects { param($Manifest) $Manifest.generated_at = "2000-01-01T00:00:00.000Z" } "Trusted experiment matrix manifest.*pending.*pin refresh" "manifest generated before the current pin refresh"
  Assert-AuditRejects { param($Manifest) $Manifest.fork_revision = "stale-fork-revision" } "Trusted experiment matrix manifest.*pending.*fork_revision=stale-fork-revision" "stale fork revision"
  Assert-AuditRejects { param($Manifest) $Manifest.suite_validation.expected_measured_seconds = 1 } "Trusted experiment matrix manifest.*pending.*duration/warmup validation" "mismatched duration validation"
  Assert-AuditRejects { param($Manifest) $Manifest.suite_validation.expected_scenes = @($RequiredScenes | Select-Object -Skip 1) } "Trusted experiment matrix manifest.*pending.*suite validation settings mismatch.*expected_scenes" "incomplete expected scenes suite validation setting"
  Assert-AuditRejects { param($Manifest) $Manifest.suite_validation.require_frame_times = $false } "Trusted experiment matrix manifest.*pending.*suite validation settings mismatch.*require_frame_times" "missing raw frame-time suite validation setting"
  Assert-AuditRejects { param($Manifest) $Manifest.suite_validation.expected_build_args_hash = "wrong-hash" } "Trusted experiment matrix manifest.*pending.*suite validation settings mismatch.*expected_build_args_hash" "mismatched expected build args hash setting"
  Assert-AuditRejects { param($Manifest) $Manifest.suite_validation.expected_browser = "" } "Trusted experiment matrix manifest.*pending.*suite validation settings mismatch.*expected_browser" "missing expected browser suite validation setting"
  Assert-AuditRejects { param($Manifest) $Manifest.suite_validation.expected_flag_metadata = $false } "Trusted experiment matrix manifest.*pending.*suite validation settings mismatch.*expected_flag_metadata" "disabled expected flag metadata suite validation setting"
  Assert-AuditRejects { param($Manifest) $Manifest.experiments = @(); $Manifest.result_files.all = @(); $Manifest.artifact_metadata.results.all = @() } "Trusted experiment matrix manifest.*pending.*records no experiments" "no experiments"
  Assert-AuditRejects { param($Manifest) $Manifest.result_files.all = @($Manifest.result_files.all | Select-Object -Skip 1) } "Trusted experiment matrix manifest.*pending.*result file count" "missing result file"
  Assert-AuditRejects { param($Manifest) $Manifest.artifact_metadata.inputs.browser.exists = $false } "Trusted experiment matrix manifest.*pending.*fork browser binary" "missing browser metadata"
  Assert-AuditRejects {
    param($Manifest)
    $Manifest.artifact_metadata.inputs.build_args.sha256 = $null
    $Manifest.suite_validation.expected_build_args_hash = ""
  } "Trusted experiment matrix manifest.*pending.*build-args hash" "missing build-args hash"
  Assert-AuditRejects { param($Manifest) $Manifest.artifact_metadata.results.all = @() } "Trusted experiment matrix manifest.*pending.*hashed result count" "missing result hashes"
  Assert-AuditRejects { param($Manifest) $Manifest.artifact_metadata.reports.summary.exists = $false } "Trusted experiment matrix manifest.*pending.*trusted matrix report hashes" "missing summary report metadata"
  Assert-AuditRejects { param($Manifest) $Manifest.artifact_metadata.reports.summary.sha256 = $null } "Trusted experiment matrix manifest.*pending.*trusted matrix report hashes" "missing summary report hash"
  Assert-AuditRejects { param($Manifest) $Manifest.artifact_metadata.reports.comparison.sha256 = $null } "Trusted experiment matrix manifest.*pending.*trusted matrix report hashes" "missing comparison report hash"
} finally {
  if ($HadManifest) {
    Copy-Item -LiteralPath $BackupPath -Destination $ManifestPath -Force
  } elseif (Test-Path -LiteralPath $ManifestPath) {
    Remove-Item -LiteralPath $ManifestPath -Force
  }
  if ($HadPinRefresh) {
    Copy-Item -LiteralPath $PinRefreshBackupPath -Destination $PinRefreshPath -Force
  } elseif (Test-Path -LiteralPath $PinRefreshPath) {
    Remove-Item -LiteralPath $PinRefreshPath -Force
  }
  foreach ($PathValue in @($BackupPath, $PinRefreshBackupPath, $TempOutput)) {
    if (Test-Path -LiteralPath $PathValue) {
      Remove-Item -LiteralPath $PathValue -Force
    }
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Trusted manifest audit rejects stale provenance, incomplete artifact metadata, and missing suite-validation settings."

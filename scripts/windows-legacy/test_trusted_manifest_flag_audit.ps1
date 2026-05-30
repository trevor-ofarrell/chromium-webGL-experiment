[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\trusted-manifest-flag-audit"
$ManifestPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.json"
$BackupPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.backup.json"
$TempOutput = Join-Path $TempDir "trusted-manifest-flag-audit.md"
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
  return [pscustomobject]@{
    path = $PathValue
    exists = $true
    size_bytes = 123
    sha256 = "0123456789abcdef"
  }
}

function New-Experiment {
  param(
    [string]$Label,
    [string[]]$Flags
  )
  return [pscustomobject]@{
    label = $Label
    description = "synthetic audit test experiment"
    flags = $Flags
    result_files = @($RequiredScenes | ForEach-Object {
      Join-Path $Root "benchmarks\raw\$Label-$_-webgl2.json"
    })
  }
}

function New-MetadataList {
  param([string[]]$Paths)
  return @($Paths | ForEach-Object { New-FileMetadata $_ })
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$HadManifest = Test-Path -LiteralPath $ManifestPath
if ($HadManifest) {
  Copy-Item -LiteralPath $ManifestPath -Destination $BackupPath -Force
}

try {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $ForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ChromiumRevision -Root $Root

  $Experiments = @(
    New-Experiment "fork-viewer-exp-default" @(),
    New-Experiment "fork-viewer-exp-aggressive-gpu" @(),
    New-Experiment "fork-viewer-exp-zero-copy" @("--viewerZeroCopy"),
    New-Experiment "fork-viewer-exp-in-process-gpu" @("--viewerInProcessGpu"),
    New-Experiment "fork-viewer-exp-single-process" @("--viewerSingleProcess"),
    New-Experiment "fork-viewer-exp-angle-d3d11" @("--viewerForceAngleBackend", "d3d11"),
    New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" @("--viewerRelaxedWebglValidation"),
    New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" @("--viewerDisableUnneededBlinkFeatures"),
    New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" @("--viewerDirectGpuPresentation")
  )
  $AllResultFiles = @($Experiments | ForEach-Object { $_.result_files })

  $Manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browser = "fork.exe"
    build_args = "fork-args.gn"
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
      reject_gpu_instability = $true
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

  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
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
  $Checklist = Get-Content -LiteralPath $TempOutput -Raw
  if ($Checklist -notmatch "Trusted experiment matrix manifest.*pending.*missing trusted experiment flag evidence.*fork-viewer-exp-aggressive-gpu") {
    throw "Artifact audit accepted or misreported a completed trusted matrix manifest with missing aggressive GPU flag evidence."
  }
} finally {
  if ($HadManifest) {
    Copy-Item -LiteralPath $BackupPath -Destination $ManifestPath -Force
  } elseif (Test-Path -LiteralPath $ManifestPath) {
    Remove-Item -LiteralPath $ManifestPath -Force
  }
  if (Test-Path -LiteralPath $BackupPath) {
    Remove-Item -LiteralPath $BackupPath -Force
  }
  if (Test-Path -LiteralPath $TempOutput) {
    Remove-Item -LiteralPath $TempOutput -Force
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Trusted manifest audit rejects missing trusted experiment flag evidence."

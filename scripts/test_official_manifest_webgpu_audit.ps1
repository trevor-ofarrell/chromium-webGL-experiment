[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\official-manifest-webgpu-audit"
$ManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$BackupPath = Join-Path $TempDir "official-comparison-manifest.backup.json"
$TempOutput = Join-Path $TempDir "official-manifest-webgpu-audit.md"
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

function New-ResultFiles {
  param(
    [string]$Label,
    [string]$Renderer
  )
  return @($RequiredScenes | ForEach-Object {
    Join-Path $Root "benchmarks\raw\$Label-$_-$Renderer.json"
  })
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
  $PatchHash = Get-ShortSha256 (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
  $ForkRevision = "$ChromiumRevision+viewerpatch-$PatchHash"
  $BaselineWebGl = New-ResultFiles "baseline-content-shell" "webgl2"
  $ForkWebGl = New-ResultFiles "fork-viewer-default" "webgl2"
  $BaselineWebGpu = New-ResultFiles "baseline-content-shell-webgpu" "webgpu"
  $ForkWebGpu = New-ResultFiles "fork-viewer-default-webgpu" "webgpu"

  $Manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browsers = [pscustomobject]@{
      baseline = "baseline.exe"
      fork = "fork.exe"
    }
    options = [pscustomobject]@{
      duration = 120
      warmup = 20
      include_webgpu = $true
      include_aggressive_gpu = $false
      capture_trace = $false
    }
    suite_validation = [pscustomobject]@{
      require_checkout = $true
      require_build_args = $true
      expected_baseline_build_args_hash = "0123456789abcdef"
      expected_fork_build_args_hash = "0123456789abcdef"
      forbid_smoke = $true
      reject_software_rendering = $true
      require_gpu_metadata = $true
      require_frame_times = $true
      require_webgpu_runtime_smoke = $true
      expected_measured_seconds = 120
      expected_warmup_seconds = 20
      expected_chromium_revision = $ChromiumRevision
      expected_baseline_browser = "baseline.exe"
      expected_fork_browser = "fork.exe"
      require_fork_revision_for_fork_suites = $true
      expected_fork_revision = $ForkRevision
      exact_scene_output_files = $true
      expected_flag_metadata = [pscustomobject]@{
        baseline = @("viewer_mode=false")
        fork_default = @("viewer_mode=true")
        aggressive = @()
        baseline_webgpu = @("viewer_mode=false")
        fork_default_webgpu = @("viewer_mode=true")
        aggressive_webgpu = @()
      }
    }
    result_files = [pscustomobject]@{
      baseline_webgl2 = $BaselineWebGl
      fork_default_webgl2 = $ForkWebGl
      aggressive_webgl2 = @()
      baseline_webgpu = $BaselineWebGpu
      fork_default_webgpu = $ForkWebGpu
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        baseline_browser = New-FileMetadata "baseline.exe"
        fork_browser = New-FileMetadata "fork.exe"
        baseline_build_args = New-FileMetadata "baseline-args.gn"
        fork_build_args = New-FileMetadata "fork-args.gn"
      }
      results = [pscustomobject]@{
        baseline_webgl2 = New-MetadataList $BaselineWebGl
        fork_default_webgl2 = New-MetadataList $ForkWebGl
        aggressive_webgl2 = @()
        baseline_webgpu = @()
        fork_default_webgpu = @()
      }
      reports = [pscustomobject]@{
        official_webgl2_comparison = New-FileMetadata "official-webgl2-comparison.md"
        official_webgpu_comparison = New-FileMetadata "official-webgpu-comparison.md"
      }
      traces = [pscustomobject]@{
        baseline = [pscustomobject]@{ exists = $false; sha256 = $null }
        fork = [pscustomobject]@{ exists = $false; sha256 = $null }
      }
    }
  }

  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $OldSkip = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST
  $OldSkipTrustedProvenance = $env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST
  $OldSkipAggressive = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST
  $OldSkipProvenance = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST
  $OldSkipRuntime = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST
  $OldSkipReport = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST
  $OldSkipArtifactPath = $env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST
  $OldAllowManifestOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
  $OldOfficialManifestPath = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST = "1"
  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $ManifestPath
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $TempOutput -ManifestAuditOnly *>&1
  } finally {
    if ($null -eq $OldSkip) {
      Remove-Item Env:\THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST = $OldSkip
    }
    if ($null -eq $OldSkipRuntime) {
      Remove-Item Env:\THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST = $OldSkipRuntime
    }
    if ($null -eq $OldSkipAggressive) {
      Remove-Item Env:\THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST = $OldSkipAggressive
    }
    if ($null -eq $OldSkipTrustedProvenance) {
      Remove-Item Env:\THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST = $OldSkipTrustedProvenance
    }
    if ($null -eq $OldSkipProvenance) {
      Remove-Item Env:\THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST = $OldSkipProvenance
    }
    if ($null -eq $OldSkipReport) {
      Remove-Item Env:\THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST = $OldSkipReport
    }
    if ($null -eq $OldSkipArtifactPath) {
      Remove-Item Env:\THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST = $OldSkipArtifactPath
    }
    if ($null -eq $OldAllowManifestOverrides) {
      Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowManifestOverrides
    }
    if ($null -eq $OldOfficialManifestPath) {
      Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OldOfficialManifestPath
    }
  }
  $Checklist = Get-Content -LiteralPath $TempOutput -Raw
  if ($Checklist -notmatch "Official comparison manifest.*pending.*hashed webgpu result counts") {
    throw "Artifact audit accepted or misreported a completed official manifest without WebGPU result hashes."
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

Write-Host "Official manifest audit rejects completed WebGPU manifests without WebGPU result hashes."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\official-manifest-aggressive-audit"
$ManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$BackupPath = Join-Path $TempDir "official-comparison-manifest.aggressive-audit.backup.json"
$TempOutput = Join-Path $TempDir "official-manifest-aggressive-audit.md"
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

function New-MissingFileMetadata {
  param([string]$PathValue)
  [pscustomobject]@{
    path = $PathValue
    exists = $false
    size_bytes = 0
    sha256 = $null
  }
}

function New-MissingDirectoryMetadata {
  param([string]$PathValue)
  [pscustomobject]@{
    path = $PathValue
    exists = $false
    file_count = 0
    size_bytes = 0
  }
}

function New-ResultFiles {
  param(
    [string]$Label,
    [string]$Renderer
  )
  @($RequiredScenes | ForEach-Object {
    Join-Path $Root "benchmarks\raw\$Label-$_-$Renderer.json"
  })
}

function New-MetadataList {
  param([string[]]$Paths)
  @($Paths | ForEach-Object { New-FileMetadata $_ })
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
    "THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST"
  )) {
    $OldValues[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($Name -eq "THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES") {
      Set-Item "Env:\$Name" "1"
    } elseif ($Name -eq "THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST") {
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
  $AggressiveWebGl = New-ResultFiles "fork-viewer-aggressive-gpu-d3d11" "webgl2"
  $BaselineWebGpu = New-ResultFiles "baseline-content-shell-webgpu" "webgpu"
  $ForkWebGpu = New-ResultFiles "fork-viewer-default-webgpu" "webgpu"
  $AggressiveWebGpu = New-ResultFiles "fork-viewer-aggressive-gpu-d3d11-webgpu" "webgpu"
  $RuntimeSmoke = @(
    (Join-Path $Root "benchmarks\raw\baseline-content-shell-runtime-smoke.json"),
    (Join-Path $Root "benchmarks\raw\fork-viewer-default-runtime-smoke.json")
  )
  $NavigationLock = @(
    (Join-Path $Root "benchmarks\raw\fork-viewer-default-navigation-lock.json"),
    (Join-Path $Root "benchmarks\raw\fork-viewer-default-file-navigation-lock.json")
  )

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
    package_dirs = [pscustomobject]@{
      baseline = ""
      fork = ""
    }
    options = [pscustomobject]@{
      duration = 120
      warmup = 20
      include_webgpu = $false
      include_aggressive_gpu = $true
      aggressive_angle_backend = "d3d11"
      capture_trace = $false
      skip_smoke = $false
      skip_navigation_lock = $false
    }
    labels = [pscustomobject]@{
      aggressive = "fork-viewer-aggressive-gpu-d3d11"
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
      require_webgpu_runtime_smoke = $false
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
        aggressive = @(
          "viewer_aggressive_gpu=true",
          "viewer_force_angle_backend=d3d11",
          "requested_angle_backend=d3d11"
        )
        baseline_webgpu = @("viewer_mode=false")
        fork_default_webgpu = @("viewer_mode=true")
        aggressive_webgpu = @(
          "viewer_aggressive_gpu=true",
          "viewer_force_angle_backend=d3d11",
          "requested_angle_backend=d3d11"
        )
      }
    }
    result_files = [pscustomobject]@{
      baseline_webgl2 = $BaselineWebGl
      fork_default_webgl2 = $ForkWebGl
      aggressive_webgl2 = $AggressiveWebGl
      baseline_webgpu = @()
      fork_default_webgpu = @()
      aggressive_webgpu = @()
      runtime_smoke = $RuntimeSmoke
      navigation_lock = $NavigationLock
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        baseline_browser = New-FileMetadata "baseline.exe"
        fork_browser = New-FileMetadata "fork.exe"
        baseline_build_args = New-FileMetadata "baseline-args.gn"
        fork_build_args = New-FileMetadata "fork-args.gn"
        baseline_package = New-MissingDirectoryMetadata ""
        fork_package = New-MissingDirectoryMetadata ""
      }
      results = [pscustomobject]@{
        baseline_webgl2 = New-MetadataList $BaselineWebGl
        fork_default_webgl2 = New-MetadataList $ForkWebGl
        aggressive_webgl2 = @()
        baseline_webgpu = @()
        fork_default_webgpu = @()
        aggressive_webgpu = @()
      }
      runtime_tests = [pscustomobject]@{
        smoke = New-MetadataList $RuntimeSmoke
        navigation_lock = New-MetadataList $NavigationLock
      }
      reports = [pscustomobject]@{
        official_webgl2_comparison = New-FileMetadata "official-webgl2-comparison.md"
        official_webgpu_comparison = New-MissingFileMetadata "official-webgpu-comparison.md"
        baseline_trace_summary = New-MissingFileMetadata "baseline-trace-summary.md"
        fork_trace_summary = New-MissingFileMetadata "fork-trace-summary.md"
      }
      traces = [pscustomobject]@{
        baseline = New-MissingFileMetadata "baseline-trace.json"
        fork = New-MissingFileMetadata "fork-trace.json"
        baseline_result = New-MissingFileMetadata "baseline-trace.result.json"
        fork_result = New-MissingFileMetadata "fork-trace.result.json"
      }
    }
  }

  $MismatchedManifest = $Manifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $MismatchedManifest.result_files.aggressive_webgl2 = New-ResultFiles "fork-viewer-aggressive-gpu" "webgl2"
  $MismatchedManifest.artifact_metadata.results.aggressive_webgl2 = New-MetadataList @($MismatchedManifest.result_files.aggressive_webgl2)
  $MismatchedManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $MismatchChecklist = Invoke-AuditAndReadChecklist
  if ($MismatchChecklist -notmatch "Official comparison manifest.*pending.*aggressive backend metadata mismatch") {
    throw "Artifact audit accepted or misreported a completed official manifest whose aggressive result labels do not match the requested backend."
  }

  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*pending.*aggressive WebGL2 counts") {
    throw "Artifact audit accepted or misreported a completed official manifest without aggressive WebGL2 result hashes."
  }

  $MissingAggressiveWebGpuManifest = $Manifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $MissingAggressiveWebGpuManifest.options.include_webgpu = $true
  $MissingAggressiveWebGpuManifest.suite_validation.require_webgpu_runtime_smoke = $true
  $MissingAggressiveWebGpuManifest.result_files.baseline_webgpu = $BaselineWebGpu
  $MissingAggressiveWebGpuManifest.result_files.fork_default_webgpu = $ForkWebGpu
  $MissingAggressiveWebGpuManifest.result_files.aggressive_webgpu = $AggressiveWebGpu
  $MissingAggressiveWebGpuManifest.artifact_metadata.results.aggressive_webgl2 = New-MetadataList $AggressiveWebGl
  $MissingAggressiveWebGpuManifest.artifact_metadata.results.baseline_webgpu = New-MetadataList $BaselineWebGpu
  $MissingAggressiveWebGpuManifest.artifact_metadata.results.fork_default_webgpu = New-MetadataList $ForkWebGpu
  $MissingAggressiveWebGpuManifest.artifact_metadata.results.aggressive_webgpu = @()
  $MissingAggressiveWebGpuManifest.artifact_metadata.reports.official_webgpu_comparison = New-FileMetadata "official-webgpu-comparison.md"
  $MissingAggressiveWebGpuManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $MissingAggressiveWebGpuChecklist = Invoke-AuditAndReadChecklist
  if ($MissingAggressiveWebGpuChecklist -notmatch "Official comparison manifest.*pending.*aggressive WebGPU counts") {
    throw "Artifact audit accepted or misreported a completed official manifest without aggressive WebGPU result hashes."
  }

  $MissingAggressiveWebGpuMetadataManifest = $MissingAggressiveWebGpuManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $MissingAggressiveWebGpuMetadataManifest.artifact_metadata.results.aggressive_webgpu = New-MetadataList $AggressiveWebGpu
  $MissingAggressiveWebGpuMetadataManifest.suite_validation.expected_flag_metadata.aggressive_webgpu = @()
  $MissingAggressiveWebGpuMetadataManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $MissingAggressiveWebGpuMetadataChecklist = Invoke-AuditAndReadChecklist
  if ($MissingAggressiveWebGpuMetadataChecklist -notmatch "Official comparison manifest.*pending.*suite validation settings mismatch.*expected_flag_metadata\.aggressive_webgpu") {
    throw "Artifact audit accepted or misreported a completed official manifest without aggressive WebGPU expected flag metadata."
  }
} finally {
  if ($HadManifest) {
    Copy-Item -LiteralPath $BackupPath -Destination $ManifestPath -Force
  } elseif (Test-Path -LiteralPath $ManifestPath) {
    Remove-Item -LiteralPath $ManifestPath -Force
  }
  foreach ($PathValue in @($BackupPath, $TempOutput)) {
    if (Test-Path -LiteralPath $PathValue) {
      Remove-Item -LiteralPath $PathValue -Force
    }
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Official manifest audit rejects completed aggressive manifests with mismatched backend labels, missing requested backend metadata, or missing aggressive WebGL2/WebGPU result hashes."

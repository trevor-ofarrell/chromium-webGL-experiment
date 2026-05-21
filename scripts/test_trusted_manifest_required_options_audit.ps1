[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\trusted-manifest-required-options-audit"
$ManifestPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.json"
$TempOutput = Join-Path $TempDir "trusted-manifest-required-options-audit.md"
$PackageDir = Join-Path $TempDir "package"
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

function Get-Sha256 {
  param([string]$PathValue)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
}

function Write-TestFile {
  param(
    [string]$PathValue,
    [string]$Text
  )

  $Parent = Split-Path -Parent $PathValue
  New-Item -ItemType Directory -Path $Parent -Force | Out-Null
  Set-Content -LiteralPath $PathValue -Value $Text -Encoding ASCII
  return $PathValue
}

function New-FileMetadata {
  param([string]$PathValue)
  $Item = Get-Item -LiteralPath $PathValue
  [pscustomobject]@{
    path = $PathValue
    exists = $true
    size_bytes = $Item.Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
  }
}

function New-DirectoryMetadata {
  param([string]$PathValue)
  $Files = @(Get-ChildItem -LiteralPath $PathValue -File -Recurse)
  $Size = 0L
  foreach ($File in $Files) {
    $Size += $File.Length
  }
  [pscustomobject]@{
    path = $PathValue
    exists = $true
    file_count = $Files.Count
    size_bytes = $Size
  }
}

function Convert-MetadataValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) {
    return "null"
  }
  if ($Value -is [bool]) {
    return $Value.ToString().ToLowerInvariant()
  }
  return [string]$Value
}

function Get-ExperimentFlagValues {
  param([string[]]$Flags)

  $Values = [ordered]@{
    viewer_mode = $true
    viewer_block_external_navigation = $true
    viewer_trusted_content = $true
    viewer_aggressive_gpu = $false
    viewer_relaxed_webgl_validation = $false
    viewer_in_process_gpu = $false
    viewer_single_process = $false
    viewer_force_angle_backend = $null
    requested_angle_backend = $null
    viewer_disable_unneeded_blink_features = $false
    viewer_direct_gpu_presentation = $false
  }

  for ($Index = 0; $Index -lt $Flags.Count; $Index += 1) {
    switch ($Flags[$Index]) {
      "--viewerAggressiveGpu" { $Values.viewer_aggressive_gpu = $true }
      "--viewerRelaxedWebglValidation" { $Values.viewer_relaxed_webgl_validation = $true }
      "--viewerInProcessGpu" { $Values.viewer_in_process_gpu = $true }
      "--viewerSingleProcess" { $Values.viewer_single_process = $true }
      "--viewerDisableUnneededBlinkFeatures" { $Values.viewer_disable_unneeded_blink_features = $true }
      "--viewerDirectGpuPresentation" { $Values.viewer_direct_gpu_presentation = $true }
      "--viewerForceAngleBackend" {
        $Index += 1
        if ($Index -ge $Flags.Count) {
          throw "Missing backend after --viewerForceAngleBackend"
        }
        $Values.viewer_force_angle_backend = $Flags[$Index]
        $Values.requested_angle_backend = $Flags[$Index]
      }
    }
  }

  return $Values
}

function Get-ExpectedFlagMetadata {
  param([string[]]$Flags)
  $Values = Get-ExperimentFlagValues -Flags $Flags
  return @($Values.GetEnumerator() | ForEach-Object {
    "$($_.Key)=$(Convert-MetadataValue $_.Value)"
  })
}

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Data
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  $Json = $Data | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($PathValue, $Json, [System.Text.UTF8Encoding]::new($false))
  return $PathValue
}

function New-TrustedSummaryReportContent {
  param(
    [object[]]$Experiments,
    [string[]]$Scenes = $RequiredScenes
  )

  $Rows = [System.Collections.Generic.List[string]]::new()
  foreach ($Experiment in $Experiments) {
    foreach ($Scene in $Scenes) {
      $Rows.Add("| $Scene | webgl2 | $($Experiment.label) | 60 |") | Out-Null
    }
  }

  @"
# Benchmark Summary

Generated from synthetic trusted required-options fixtures.

| Scene | Renderer | Variant | Avg FPS |
| --- | --- | --- | --- |
$($Rows -join "`n")
"@
}

function New-TrustedComparisonReportContent {
  param(
    [object[]]$Experiments,
    [string[]]$Scenes = $RequiredScenes
  )

  $Rows = [System.Collections.Generic.List[string]]::new()
  foreach ($Experiment in $Experiments) {
    foreach ($Scene in $Scenes) {
      $Rows.Add("| $Scene | webgl2 | $($Experiment.label) | 60 | 0 | 0 | 0 |") | Out-Null
    }
  }

  @"
# Benchmark Comparison

Generated from synthetic trusted required-options fixtures.

| Scene | Renderer | Variant | Avg FPS | Dropped Delta | JS heap Delta | GPU memory Delta |
| --- | --- | --- | ---: | ---: | ---: | ---: |
$($Rows -join "`n")
"@
}

function New-Result {
  param(
    [string]$Scene,
    [string]$Variant,
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$BrowserExecutable,
    [string]$BuildArgsHash,
    [string[]]$Flags
  )

  $FlagValues = Get-ExperimentFlagValues -Flags $Flags
  [ordered]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    build_args_hash = $BuildArgsHash
    platform = "test-platform"
    gpu_name = "NVIDIA GeForce RTX Test"
    driver_version = "test-driver"
    angle_backend = "ANGLE (NVIDIA, D3D11)"
    renderer_type = "webgl2"
    scene_name = $Scene
    warmup_seconds = 10
    measured_seconds = 60
    avg_fps = 60
    p50_frame_ms = 16
    p95_frame_ms = 17
    p99_frame_ms = 18
    frame_times_ms = @(16, 16.5, 17, 18)
    one_percent_low_fps = 55
    point_one_percent_low_fps = 50
    avg_cpu_frame_ms = 1
    avg_gpu_frame_ms = 1
    avg_js_frame_ms = 0.5
    avg_render_submission_ms = 0.5
    avg_compositor_latency_ms = $null
    avg_presentation_latency_ms = $null
    max_frame_ms = 18
    dropped_frames = 0
    draw_calls = 100
    triangles = 1000
    texture_upload_mb = 0
    buffer_upload_mb = 0
    shader_compile_events = 0
    js_heap_mb = 10
    gpu_memory_mb = 20
    process_rss_mb = 100
    startup_ms_to_first_frame = 500
    browser_binary_size_mb = 100
    viewer_bundle_size_mb = 1
    package_size_mb = 120
    browser_executable = $BrowserExecutable
    browser_is_from_checkout = $true
    benchmark_variant = $Variant
    viewer_mode = $FlagValues.viewer_mode
    viewer_block_external_navigation = $FlagValues.viewer_block_external_navigation
    viewer_trusted_content = $FlagValues.viewer_trusted_content
    viewer_aggressive_gpu = $FlagValues.viewer_aggressive_gpu
    viewer_relaxed_webgl_validation = $FlagValues.viewer_relaxed_webgl_validation
    viewer_in_process_gpu = $FlagValues.viewer_in_process_gpu
    viewer_single_process = $FlagValues.viewer_single_process
    viewer_force_angle_backend = $FlagValues.viewer_force_angle_backend
    requested_angle_backend = $FlagValues.requested_angle_backend
    viewer_disable_unneeded_blink_features = $FlagValues.viewer_disable_unneeded_blink_features
    viewer_direct_gpu_presentation = $FlagValues.viewer_direct_gpu_presentation
    browser_flags = @("--disable-software-rasterizer")
  }
}

function New-Experiment {
  param(
    [string]$Label,
    [string[]]$Flags,
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$Browser,
    [string]$BuildArgsHash
  )

  $ResultFiles = @($RequiredScenes | ForEach-Object {
    Join-Path $TempDir "results\$Label-$_-webgl2.json"
  })
  for ($Index = 0; $Index -lt $RequiredScenes.Count; $Index += 1) {
    $null = Write-Json $ResultFiles[$Index] (New-Result `
        -Scene $RequiredScenes[$Index] `
        -Variant $Label `
        -ChromiumRevision $ChromiumRevision `
        -ForkRevision $ForkRevision `
        -BrowserExecutable $Browser `
        -BuildArgsHash $BuildArgsHash `
        -Flags $Flags)
  }

  [pscustomobject]@{
    label = $Label
    description = "synthetic trusted required-options audit experiment"
    flags = $Flags
    expected_flag_metadata = @(Get-ExpectedFlagMetadata -Flags $Flags)
    result_files = $ResultFiles
  }
}

function New-ValidTrustedManifest {
  param([switch]$WithPackage)

  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PatchHash = Get-ShortSha256 (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
  $ForkRevision = "$ChromiumRevision+viewerpatch-$PatchHash"
  $Browser = Write-TestFile (Join-Path $TempDir "fork.exe") "fork browser"
  $BuildArgs = Write-TestFile (Join-Path $TempDir "args.gn") "is_debug=false"
  $BuildArgsHash = Get-Sha256 $BuildArgs
  $Summary = Join-Path $TempDir "trusted-summary.md"
  $Comparison = Join-Path $TempDir "trusted-comparison.md"
  New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null
  $null = Write-TestFile (Join-Path $PackageDir "content_shell.exe") "fork browser"

  $Experiments = @(
    (New-Experiment "fork-viewer-exp-default" @() $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-aggressive-gpu" @("--viewerAggressiveGpu") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-in-process-gpu" @("--viewerInProcessGpu") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-single-process" @("--viewerSingleProcess") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-angle-d3d11" @("--viewerForceAngleBackend", "d3d11") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" @("--viewerRelaxedWebglValidation") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" @("--viewerDisableUnneededBlinkFeatures") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
    (New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" @("--viewerDirectGpuPresentation") $ChromiumRevision $ForkRevision $Browser $BuildArgsHash)
  )
  $AllResultFiles = @($Experiments | ForEach-Object { $_.result_files })
  $null = Write-TestFile $Summary (New-TrustedSummaryReportContent -Experiments $Experiments)
  $null = Write-TestFile $Comparison (New-TrustedComparisonReportContent -Experiments $Experiments)

  [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browser = $Browser
    build_args = $BuildArgs
    package_dir = if ($WithPackage) { $PackageDir } else { "" }
    renderer = "webgl2"
    scenes = $RequiredScenes
    suite_validation = [pscustomobject]@{
      expected_scenes = $RequiredScenes
      require_checkout = $true
      require_build_args = $true
      require_fork_revision = $true
      expected_fork_revision = $ForkRevision
      forbid_smoke = $true
      reject_software_rendering = $true
      require_gpu_metadata = $true
      require_frame_times = $true
      expected_chromium_revision = $ChromiumRevision
      expected_browser = $Browser
      expected_build_args_hash = $BuildArgsHash
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
    report_files = [pscustomobject]@{
      summary = $Summary
      comparison = $Comparison
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        browser = New-FileMetadata $Browser
        build_args = New-FileMetadata $BuildArgs
        viewer_patch = New-FileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
        package = if ($WithPackage) {
          New-DirectoryMetadata $PackageDir
        } else {
          [pscustomobject]@{
            path = $null
            exists = $false
            file_count = 0
            size_bytes = 0
          }
        }
      }
      results = [pscustomobject]@{
        all = @($AllResultFiles | ForEach-Object { New-FileMetadata $_ })
      }
      reports = [pscustomobject]@{
        summary = New-FileMetadata $Summary
        comparison = New-FileMetadata $Comparison
      }
    }
  }
}

function Invoke-AuditAndReadChecklist {
  $OldValues = @{}
  foreach ($Name in @(
    "THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST",
    "THREE_BROWSER_SKIP_TRUSTED_MANIFEST_FLAG_AUDIT_TEST",
    "THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_TRUSTED_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST",
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

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  New-ValidTrustedManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $MissingPackageChecklist = Invoke-AuditAndReadChecklist
  if ($MissingPackageChecklist -notmatch "Trusted experiment matrix manifest.*pending.*missing required package_dir") {
    throw "Artifact audit accepted or misreported a completed trusted matrix manifest without package_dir."
  }

  New-ValidTrustedManifest -WithPackage | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $CompleteChecklist = Invoke-AuditAndReadChecklist
  if ($CompleteChecklist -notmatch "Trusted experiment matrix manifest.*done.*required package metadata") {
    throw "Artifact audit rejected a completed trusted matrix manifest with package_dir and matching package metadata."
  }
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Trusted manifest required-options audit requires a staged package directory for completed trusted matrices."

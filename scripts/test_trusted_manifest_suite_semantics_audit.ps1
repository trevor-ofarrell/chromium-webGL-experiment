[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\trusted-manifest-suite-semantics-audit"
$ManifestPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.json"
$TempOutput = Join-Path $TempDir "trusted-manifest-suite-semantics-audit.md"
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
}

function Write-ArtifactFile {
  param(
    [string]$PathValue,
    [string]$Content
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  [System.IO.File]::WriteAllText($PathValue, $Content, [System.Text.UTF8Encoding]::new($false))
  return $PathValue
}

function Write-PackageDir {
  param([string]$PathValue)

  New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
  $null = Write-ArtifactFile (Join-Path $PathValue "content_shell.exe") "fork browser"
  return $PathValue
}

function New-FileMetadata {
  param([string]$PathValue)

  [pscustomobject]@{
    path = $PathValue
    exists = $true
    size_bytes = (Get-Item -LiteralPath $PathValue).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
  }
}

function New-DirectoryMetadata {
  param([string]$PathValue)

  $Files = @(Get-ChildItem -LiteralPath $PathValue -File -Recurse -ErrorAction SilentlyContinue)
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

function New-MetadataList {
  param([string[]]$Paths)
  @($Paths | ForEach-Object { New-FileMetadata $_ })
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

Generated from synthetic trusted manifest test fixtures.

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

Generated from synthetic trusted manifest test fixtures.

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
    [string[]]$Flags
  )

  $FlagValues = Get-ExperimentFlagValues -Flags $Flags
  [ordered]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    build_args_hash = "synthetic-build-args-hash"
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
    [string]$Browser
  )

  $ResultFiles = @($RequiredScenes | ForEach-Object {
    Join-Path $TempDir "results\$Label-$_-webgl2.json"
  })
  for ($Index = 0; $Index -lt $RequiredScenes.Count; $Index += 1) {
    Write-Json $ResultFiles[$Index] (New-Result `
        -Scene $RequiredScenes[$Index] `
        -Variant $Label `
        -ChromiumRevision $ChromiumRevision `
        -ForkRevision $ForkRevision `
        -BrowserExecutable $Browser `
        -Flags $Flags)
  }

  [pscustomobject]@{
    label = $Label
    description = "synthetic trusted exact-suite audit experiment"
    flags = $Flags
    expected_flag_metadata = @(Get-ExpectedFlagMetadata -Flags $Flags)
    result_files = $ResultFiles
  }
}

function New-ValidTrustedManifest {
  param(
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$Browser,
    [string]$BuildArgs,
    [string]$PackageDir,
    [string]$Summary,
    [string]$Comparison
  )

  $Experiments = @(
    (New-Experiment "fork-viewer-exp-default" @() $ChromiumRevision $ForkRevision $Browser)
    (New-Experiment "fork-viewer-exp-aggressive-gpu" @("--viewerAggressiveGpu") $ChromiumRevision $ForkRevision $Browser)
    (New-Experiment "fork-viewer-exp-in-process-gpu" @("--viewerInProcessGpu") $ChromiumRevision $ForkRevision $Browser)
    (New-Experiment "fork-viewer-exp-single-process" @("--viewerSingleProcess") $ChromiumRevision $ForkRevision $Browser)
    (New-Experiment "fork-viewer-exp-angle-d3d11" @("--viewerForceAngleBackend", "d3d11") $ChromiumRevision $ForkRevision $Browser)
    (New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" @("--viewerRelaxedWebglValidation") $ChromiumRevision $ForkRevision $Browser)
    (New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" @("--viewerDisableUnneededBlinkFeatures") $ChromiumRevision $ForkRevision $Browser)
    (New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" @("--viewerDirectGpuPresentation") $ChromiumRevision $ForkRevision $Browser)
  )
  $AllResultFiles = @($Experiments | ForEach-Object { $_.result_files })
  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Experiments)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Experiments)

  [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browser = $Browser
    build_args = $BuildArgs
    package_dir = $PackageDir
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
      expected_chromium_revision = $ChromiumRevision
      expected_browser = $Browser
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
        package = New-DirectoryMetadata $PackageDir
      }
      results = [pscustomobject]@{
        all = New-MetadataList $AllResultFiles
      }
      reports = [pscustomobject]@{
        summary = New-FileMetadata $Summary
        comparison = New-FileMetadata $Comparison
      }
    }
  }
}

function Invoke-AuditAndReadChecklist {
  $OldAllowManifestOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
  $OldTrustedManifestPath = $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST
  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $ManifestPath
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $TempOutput -ManifestAuditOnly *>&1
  } finally {
    if ($null -eq $OldAllowManifestOverrides) {
      Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldAllowManifestOverrides
    }
    if ($null -eq $OldTrustedManifestPath) {
      Remove-Item Env:\THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $OldTrustedManifestPath
    }
  }

  Get-Content -LiteralPath $TempOutput -Raw
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
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PatchHash = Get-ShortSha256 (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
  $ForkRevision = "$ChromiumRevision+viewerpatch-$PatchHash"
  $Browser = Write-ArtifactFile (Join-Path $TempDir "fork.exe") "fork browser"
  $BuildArgs = Write-ArtifactFile (Join-Path $TempDir "args.gn") "is_debug=false"
  $PackageDir = Write-PackageDir (Join-Path $TempDir "package")
  $Summary = Write-ArtifactFile (Join-Path $TempDir "trusted-summary.md") ""
  $Comparison = Write-ArtifactFile (Join-Path $TempDir "trusted-comparison.md") ""

  $Manifest = New-ValidTrustedManifest `
    -ChromiumRevision $ChromiumRevision `
    -ForkRevision $ForkRevision `
    -Browser $Browser `
    -BuildArgs $BuildArgs `
    -PackageDir $PackageDir `
    -Summary $Summary `
    -Comparison $Comparison
  Write-Json $ManifestPath $Manifest
  $DoneChecklist = Invoke-AuditAndReadChecklist
  if ($DoneChecklist -notmatch "Trusted experiment matrix manifest.*done.*benchmark suites semantically validated") {
    throw "Artifact audit did not accept a completed trusted manifest whose exact experiment suites pass validation. Checklist: $DoneChecklist"
  }

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments -Scenes @($RequiredScenes | Select-Object -Skip 1))
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  Write-Json $ManifestPath $Manifest
  $SceneIncompleteReportChecklist = Invoke-AuditAndReadChecklist
  if ($SceneIncompleteReportChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $SceneIncompleteReportChecklist -notmatch "trusted summary missing scene many-draw-calls") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose summary report omits a required scene. Checklist: $SceneIncompleteReportChecklist"
  }

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments @($Manifest.experiments | Select-Object -Skip 1))
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  Write-Json $ManifestPath $Manifest
  $LabelIncompleteReportChecklist = Invoke-AuditAndReadChecklist
  if ($LabelIncompleteReportChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $LabelIncompleteReportChecklist -notmatch "trusted summary missing experiment label fork-viewer-exp-default") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose summary report omits an experiment label. Checklist: $LabelIncompleteReportChecklist"
  }

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary

  $null = Write-ArtifactFile $Summary "not a benchmark summary"
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  Write-Json $ManifestPath $Manifest
  $BadReportChecklist = Invoke-AuditAndReadChecklist
  if ($BadReportChecklist -notmatch "Trusted experiment matrix manifest.*pending.*report content validation failed" -or
      $BadReportChecklist -notmatch "trusted summary missing summary heading") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose hashed report content is not a benchmark summary. Checklist: $BadReportChecklist"
  }

  $null = Write-ArtifactFile $Summary (New-TrustedSummaryReportContent -Experiments $Manifest.experiments)
  $null = Write-ArtifactFile $Comparison (New-TrustedComparisonReportContent -Experiments $Manifest.experiments)
  $Manifest.artifact_metadata.reports.summary = New-FileMetadata $Summary
  $Manifest.artifact_metadata.reports.comparison = New-FileMetadata $Comparison

  $FirstResult = [string]$Manifest.experiments[0].result_files[0]
  $OriginalFirstResult = Get-Content -LiteralPath $FirstResult -Raw | ConvertFrom-Json
  $WrongBrowserResult = Get-Content -LiteralPath $FirstResult -Raw | ConvertFrom-Json
  $WrongBrowserResult.browser_executable = Join-Path $TempDir "wrong-fork-browser.exe"
  Write-Json $FirstResult $WrongBrowserResult
  $Manifest.artifact_metadata.results.all = New-MetadataList @($Manifest.result_files.all)
  Write-Json $ManifestPath $Manifest
  $WrongBrowserChecklist = Invoke-AuditAndReadChecklist
  if ($WrongBrowserChecklist -notmatch "Trusted experiment matrix manifest.*pending.*suite validation failed" -or
      $WrongBrowserChecklist -notmatch "browser_executable") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose exact result file records the wrong browser executable. Checklist: $WrongBrowserChecklist"
  }
  Write-Json $FirstResult $OriginalFirstResult
  $Manifest.artifact_metadata.results.all = New-MetadataList @($Manifest.result_files.all)
  Write-Json $ManifestPath $Manifest

  $BadResult = Get-Content -LiteralPath $FirstResult -Raw | ConvertFrom-Json
  $BadResult.measured_seconds = 59
  Write-Json $FirstResult $BadResult
  $Manifest.artifact_metadata.results.all = New-MetadataList @($Manifest.result_files.all)
  Write-Json $ManifestPath $Manifest
  $BadChecklist = Invoke-AuditAndReadChecklist
  if ($BadChecklist -notmatch "Trusted experiment matrix manifest.*pending.*suite validation failed" -or
      $BadChecklist -notmatch "measured_seconds") {
    throw "Artifact audit accepted or misreported a completed trusted manifest whose exact result file fails benchmark suite validation. Checklist: $BadChecklist"
  }
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Trusted manifest audit semantically validates exact experiment suite files and report content before marking matrix evidence complete."

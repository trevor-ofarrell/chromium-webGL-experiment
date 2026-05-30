[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\manifest-artifact-path-audit"
$OfficialManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$TrustedManifestPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.json"
$OfficialBackupPath = Join-Path $TempDir "official-comparison-manifest.artifact-path-audit.backup.json"
$TrustedBackupPath = Join-Path $TempDir "trusted-experiment-matrix-manifest.artifact-path-audit.backup.json"
$PinRefreshPath = Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json"
$PinRefreshBackupPath = Join-Path $TempDir "chromium-pin-refresh.artifact-path-audit.backup.json"
$OfficialOutput = Join-Path $TempDir "official-manifest-artifact-path-audit.md"
$TrustedOutput = Join-Path $TempDir "trusted-manifest-artifact-path-audit.md"
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

function New-FakeFileMetadata {
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

function New-RealFileMetadata {
  param([string]$PathValue)

  [pscustomobject]@{
    path = $PathValue
    exists = $true
    size_bytes = (Get-Item -LiteralPath $PathValue).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
  }
}

function New-RealDirectoryMetadata {
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
  param(
    [string]$PathValue,
    [string]$Content,
    [string]$ExecutableContent = $Content
  )

  New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $PathValue "viewer") -Force | Out-Null
  $null = Write-ArtifactFile (Join-Path $PathValue "content_shell.exe") $ExecutableContent
  $null = Write-ArtifactFile (Join-Path $PathValue "viewer\index.html") "<!doctype html>"
  $null = Write-ArtifactFile (Join-Path $PathValue "run_viewer.ps1") "Write-Host synthetic"
  $null = Write-ArtifactFile (Join-Path $PathValue "payload.txt") $Content
  return $PathValue
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
  @($Paths | ForEach-Object { New-FakeFileMetadata $_ })
}

function New-RealMetadataList {
  param([string[]]$Paths)
  @($Paths | ForEach-Object { New-RealFileMetadata $_ })
}

function New-OfficialSuiteValidation {
  param(
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$BaselineBrowser = "baseline.exe",
    [string]$ForkBrowser = "fork.exe",
    [string]$BaselineBuildArgsHash = "0123456789abcdef",
    [string]$ForkBuildArgsHash = "0123456789abcdef"
  )

  [pscustomobject]@{
    require_checkout = $true
    require_build_args = $true
    expected_baseline_build_args_hash = $BaselineBuildArgsHash
    expected_fork_build_args_hash = $ForkBuildArgsHash
    forbid_smoke = $true
    reject_software_rendering = $true
    reject_gpu_instability = $true
    require_gpu_metadata = $true
    require_frame_times = $true
    expected_measured_seconds = 120
    expected_warmup_seconds = 20
    expected_chromium_revision = $ChromiumRevision
    expected_baseline_browser = $BaselineBrowser
    expected_fork_browser = $ForkBrowser
    require_fork_revision_for_fork_suites = $true
    expected_fork_revision = $ForkRevision
    exact_scene_output_files = $true
    expected_flag_metadata = [pscustomobject]@{
      baseline = @("viewer_mode=false", "resource_warmup_enabled=false", "resource_warmup_precompile=false", "resource_warmup_prerender_frames=0")
      fork_default = @("viewer_mode=true", "resource_warmup_enabled=false", "resource_warmup_precompile=false", "resource_warmup_prerender_frames=0")
      aggressive = @()
      baseline_webgpu = @()
      fork_default_webgpu = @()
      aggressive_webgpu = @()
    }
  }
}

function New-TrustedSuiteValidation {
  param(
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$Browser = "fork.exe",
    [string]$BuildArgsHash = "0123456789abcdef"
  )

  [pscustomobject]@{
    expected_scenes = $RequiredScenes
    require_checkout = $true
    require_build_args = $true
    expected_build_args_hash = $BuildArgsHash
    require_fork_revision = $true
    expected_fork_revision = $ForkRevision
    forbid_smoke = $true
    reject_software_rendering = $true
    reject_gpu_instability = $true
    require_gpu_metadata = $true
    require_frame_times = $true
    expected_chromium_revision = $ChromiumRevision
    expected_browser = $Browser
    expected_measured_seconds = 60
    expected_warmup_seconds = 10
    exact_scene_output_files = $true
    expected_flag_metadata = $true
  }
}

function New-TempResultFiles {
  param(
    [string]$Label,
    [string]$Renderer
  )
  @($RequiredScenes | ForEach-Object {
    Join-Path $TempDir "$Label-$_-$Renderer.json"
  })
}

function Write-ArtifactFiles {
  param([string[]]$Paths)
  foreach ($PathValue in $Paths) {
    $null = Write-ArtifactFile $PathValue "{}"
  }
}

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Data
  )
  $Json = $Data | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($PathValue, $Json, [System.Text.UTF8Encoding]::new($false))
}

function Write-ValidSmokeFiles {
  param(
    [string[]]$RuntimeSmoke,
    [string[]]$NavigationLock,
    [string]$BaselineBrowser = "baseline.exe",
    [string]$ForkBrowser = "fork.exe"
  )

  foreach ($PathValue in @($RuntimeSmoke + $NavigationLock)) {
    New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  }

  $BaselineRuntime = [pscustomobject]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    platform = "synthetic"
    browser_executable = $BaselineBrowser
    browser_version = "synthetic"
    browser_flags = @("--disable-software-rasterizer")
    viewer_mode = $false
    viewer_trusted_content = $false
    viewer_app_url = $null
    ok = $true
    tests = @(
      [pscustomobject]@{ name = "viewer_launch"; status = "pass" },
      [pscustomobject]@{ name = "webgl2_context"; status = "pass" },
      [pscustomobject]@{ name = "web_platform_basics"; status = "pass"; details = [pscustomobject]@{ canvas_2d = $true; raf_timestamp_ms = 16; performance_delta_ms = 1; fetch_content_type = "image/svg+xml"; fetch_bytes = 100 } },
      [pscustomobject]@{ name = "basic_input_events"; status = "pass"; details = [pscustomobject]@{ events = @("pointerdown", "pointermove", "pointerup", "wheel", "keydown"); pointer_event_constructor = $true; wheel_delta_y = 42; key = "ArrowLeft" } },
      [pscustomobject]@{ name = "three_cube_render"; status = "pass" },
      [pscustomobject]@{ name = "texture_load"; status = "pass" },
      [pscustomobject]@{ name = "shader_material"; status = "pass" },
      [pscustomobject]@{ name = "benchmark_run"; status = "pass"; details = [pscustomobject]@{ scene_name = "many-draw-calls"; renderer_type = "webgl2"; avg_fps = 60; frame_count = 60; startup_ms_to_first_frame = 10 } }
    )
  }
  $ForkRuntime = $BaselineRuntime | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $ForkRuntime.browser_executable = $ForkBrowser
  $ForkRuntime.viewer_mode = $true
  $ForkRuntime.viewer_trusted_content = $true
  $ForkRuntime.viewer_app_url = "http://127.0.0.1:1111/__smoke.html"
  Write-Json $RuntimeSmoke[0] $BaselineRuntime
  Write-Json $RuntimeSmoke[1] $ForkRuntime

  $NavigationSmoke = [pscustomobject]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    platform = "synthetic"
    browser_executable = $ForkBrowser
    browser_version = "synthetic"
    viewer_app_url = "http://127.0.0.1:1111/index.html"
    blocked_origin = "http://127.0.0.1:2222"
    external_blocked_url = "http://203.0.113.10/blocked.html"
    ok = $true
    tests = @(
      [pscustomobject]@{ name = "launches_viewer_app_url"; status = "pass"; details = [pscustomobject]@{ url = "http://127.0.0.1:1111/index.html" } },
      [pscustomobject]@{ name = "allows_same_origin_navigation"; status = "pass"; details = [pscustomobject]@{ url = "http://127.0.0.1:1111/allowed.html" } },
      [pscustomobject]@{ name = "blocks_cross_origin_navigation"; status = "pass"; details = [pscustomobject]@{ url = "http://127.0.0.1:1111/allowed.html"; blocked_origin_hits = 0 } },
      [pscustomobject]@{ name = "blocks_external_http_navigation"; status = "pass"; details = [pscustomobject]@{ url = "http://127.0.0.1:1111/allowed.html"; blocked_url = "http://203.0.113.10/blocked.html"; external_blocked_hits = 0 } },
      [pscustomobject]@{ name = "blocks_window_open"; status = "pass"; details = [pscustomobject]@{ before_pages = 1; after_pages = 1 } }
    )
  }
  Write-Json $NavigationLock[0] $NavigationSmoke

  $FileNavigationSmoke = [pscustomobject]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    platform = "synthetic"
    browser_executable = $ForkBrowser
    browser_version = "synthetic"
    viewer_app_path = "C:\synthetic\viewer\index.html"
    viewer_app_url = "file:///C:/synthetic/viewer/index.html"
    allowed_file_url = "file:///C:/synthetic/viewer/assets/allowed.html"
    blocked_file_url = "file:///C:/synthetic/outside/blocked.html"
    ok = $true
    tests = @(
      [pscustomobject]@{ name = "launches_file_viewer_app_path"; status = "pass"; details = [pscustomobject]@{ url = "file:///C:/synthetic/viewer/index.html" } },
      [pscustomobject]@{ name = "allows_viewer_directory_file_navigation"; status = "pass"; details = [pscustomobject]@{ url = "file:///C:/synthetic/viewer/assets/allowed.html" } },
      [pscustomobject]@{ name = "blocks_file_navigation_outside_viewer_directory"; status = "pass"; details = [pscustomobject]@{ url = "file:///C:/synthetic/viewer/assets/allowed.html"; blocked_url = "file:///C:/synthetic/outside/blocked.html" } },
      [pscustomobject]@{ name = "blocks_file_window_open_outside_viewer_directory"; status = "pass"; details = [pscustomobject]@{ before_pages = 1; after_pages = 1 } }
    )
  }
  Write-Json $NavigationLock[1] $FileNavigationSmoke
}

function New-Experiment {
  param(
    [string]$Label,
    [string[]]$Flags
  )
  $ExpectedFlagMetadata = @(
    "viewer_mode=true",
    "viewer_block_external_navigation=true",
    "viewer_trusted_content=true",
    "resource_warmup_enabled=false",
    "resource_warmup_precompile=false",
    "resource_warmup_prerender_frames=0"
  )
  for ($Index = 0; $Index -lt $Flags.Count; $Index += 1) {
    switch ($Flags[$Index]) {
      "--viewerAggressiveGpu" { $ExpectedFlagMetadata += "viewer_aggressive_gpu=true" }
      "--viewerRelaxedWebglValidation" { $ExpectedFlagMetadata += "viewer_relaxed_webgl_validation=true" }
      "--viewerZeroCopy" { $ExpectedFlagMetadata += "viewer_zero_copy=true" }
      "--viewerInProcessGpu" { $ExpectedFlagMetadata += "viewer_in_process_gpu=true" }
      "--viewerSingleProcess" { $ExpectedFlagMetadata += "viewer_single_process=true" }
      "--viewerDisableUnneededBlinkFeatures" { $ExpectedFlagMetadata += "viewer_disable_unneeded_blink_features=true" }
      "--viewerDirectGpuPresentation" { $ExpectedFlagMetadata += "viewer_direct_gpu_presentation=true" }
      "--viewerDeferWebgpuPipelineFlush" { $ExpectedFlagMetadata += "viewer_defer_webgpu_pipeline_flush=true" }
      "--viewerDeferWebgpuQueueFlush" { $ExpectedFlagMetadata += "viewer_defer_webgpu_queue_flush=true" }
      "--viewerDeferWebgpuSubmitFlush" { $ExpectedFlagMetadata += "viewer_defer_webgpu_submit_flush=true" }
      "--viewerSkipWebgpuCanvasTextureValidation" { $ExpectedFlagMetadata += "viewer_skip_webgpu_canvas_texture_validation=true" }
      "--viewerSkipWebgpuCanvasMemoryAccounting" { $ExpectedFlagMetadata += "viewer_skip_webgpu_canvas_memory_accounting=true" }
      "--viewerSkipWebgpuCopyExternalImageColorConversion" { $ExpectedFlagMetadata += "viewer_skip_webgpu_copy_external_image_color_conversion=true" }
      "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation" { $ExpectedFlagMetadata += "viewer_skip_webgpu_copy_external_image_color_space_validation=true" }
      "--viewerSkipWebgpuCopyExternalImageDestValidation" { $ExpectedFlagMetadata += "viewer_skip_webgpu_copy_external_image_dest_validation=true" }
      "--viewerSkipWebgpuCopyExternalImageSourceValidation" { $ExpectedFlagMetadata += "viewer_skip_webgpu_copy_external_image_source_validation=true" }
      "--viewerSkipWebgpuCopyExternalImageCopySizeValidation" { $ExpectedFlagMetadata += "viewer_skip_webgpu_copy_external_image_copy_size_validation=true" }
      "--viewerSkipWebgpuWriteTextureLayoutValidation" { $ExpectedFlagMetadata += "viewer_skip_webgpu_write_texture_layout_validation=true" }
      "--viewerRejectWebgpuCpuTextureFallback" { $ExpectedFlagMetadata += "viewer_reject_webgpu_cpu_texture_fallback=true" }
      "--viewerSkipWebgpuUseCounters" { $ExpectedFlagMetadata += "viewer_skip_webgpu_use_counters=true" }
      "--viewerSkipWebgpuResourceLabels" { $ExpectedFlagMetadata += "viewer_skip_webgpu_resource_labels=true" }
      "--viewerSkipWebgpuShaderSourceNullCheck" { $ExpectedFlagMetadata += "viewer_skip_webgpu_shader_source_null_check=true" }
      "--viewerSkipWebgpuShaderMemoryAccounting" { $ExpectedFlagMetadata += "viewer_skip_webgpu_shader_memory_accounting=true" }
      "--viewerSkipWebgpuRedundantPipelineSets" { $ExpectedFlagMetadata += "viewer_skip_webgpu_redundant_pipeline_sets=true" }
      "--viewerSkipWebgpuRedundantBindGroupSets" { $ExpectedFlagMetadata += "viewer_skip_webgpu_redundant_bind_group_sets=true" }
      "--viewerSkipWebgpuRedundantBufferSets" { $ExpectedFlagMetadata += "viewer_skip_webgpu_redundant_buffer_sets=true" }
      "--viewerSkipWebgpuRedundantRenderStateSets" { $ExpectedFlagMetadata += "viewer_skip_webgpu_redundant_render_state_sets=true" }
      "--viewerTraceWebgpuQueue" { $ExpectedFlagMetadata += "viewer_trace_webgpu_queue=true" }
      "--viewerForceAngleBackend" {
        if ($Index + 1 -lt $Flags.Count) {
          $Backend = $Flags[$Index + 1]
          $ExpectedFlagMetadata += "viewer_force_angle_backend=$Backend"
          $ExpectedFlagMetadata += "requested_angle_backend=$Backend"
        }
      }
    }
  }
  [pscustomobject]@{
    label = $Label
    description = "synthetic artifact path audit experiment"
    flags = $Flags
    expected_flag_metadata = $ExpectedFlagMetadata
    result_files = New-ResultFiles $Label "webgl2"
  }
}

function Invoke-AuditForTest {
  param([string]$OutputPath)

  $SkipNames = @(
    "THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST",
    "THREE_BROWSER_SKIP_TRUSTED_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST",
    "THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST"
  )
  $OldValues = @{}
  foreach ($Name in $SkipNames) {
    $OldValues[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    Set-Item "Env:\$Name" "1"
  }
  foreach ($Item in @(
    @("THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES", "1"),
    @("THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST", $OfficialManifestPath),
    @("THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST", $TrustedManifestPath)
  )) {
    $OldValues[$Item[0]] = [Environment]::GetEnvironmentVariable($Item[0], "Process")
    Set-Item "Env:\$($Item[0])" $Item[1]
  }

  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $OutputPath -ManifestAuditOnly *>&1
  } finally {
    foreach ($Name in @($SkipNames + @("THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES", "THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST", "THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST"))) {
      if ($null -eq $OldValues[$Name]) {
        Remove-Item "Env:\$Name" -ErrorAction SilentlyContinue
      } else {
        Set-Item "Env:\$Name" $OldValues[$Name]
      }
    }
  }
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$HadOfficialManifest = Test-Path -LiteralPath $OfficialManifestPath
$HadTrustedManifest = Test-Path -LiteralPath $TrustedManifestPath
$HadPinRefresh = Test-Path -LiteralPath $PinRefreshPath
if ($HadOfficialManifest) {
  Copy-Item -LiteralPath $OfficialManifestPath -Destination $OfficialBackupPath -Force
}
if ($HadTrustedManifest) {
  Copy-Item -LiteralPath $TrustedManifestPath -Destination $TrustedBackupPath -Force
}
if ($HadPinRefresh) {
  Copy-Item -LiteralPath $PinRefreshPath -Destination $PinRefreshBackupPath -Force
}

try {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $ForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ChromiumRevision -Root $Root
  $PinSelectedAt = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString("o")
  $SyntheticPinRefresh = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    target_revision = $ChromiumRevision
    previous_revision = $ChromiumRevision
    selected_from_upstream_head = $true
    selected_at = $PinSelectedAt
    source = "synthetic artifact path audit test"
    skip_sync = $true
    skip_hooks = $true
    skip_gn_gen = $true
  }
  New-Item -ItemType Directory -Path (Split-Path $PinRefreshPath -Parent) -Force | Out-Null
  Write-Json $PinRefreshPath $SyntheticPinRefresh

  $BaselineWebGl = New-ResultFiles "baseline-content-shell" "webgl2"
  $ForkWebGl = New-ResultFiles "fork-viewer-default" "webgl2"
  $RuntimeSmoke = @(
    (Join-Path $TempDir "baseline-content-shell-runtime-smoke.json"),
    (Join-Path $TempDir "fork-viewer-default-runtime-smoke.json")
  )
  $NavigationLock = @(
    (Join-Path $TempDir "fork-viewer-default-navigation-lock.json"),
    (Join-Path $TempDir "fork-viewer-default-file-navigation-lock.json")
  )
  Write-ValidSmokeFiles -RuntimeSmoke $RuntimeSmoke -NavigationLock $NavigationLock

  $OfficialManifest = [pscustomobject]@{
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
      include_aggressive_gpu = $false
      capture_trace = $false
      skip_smoke = $false
      skip_navigation_lock = $false
    }
    suite_validation = New-OfficialSuiteValidation -ChromiumRevision $ChromiumRevision -ForkRevision $ForkRevision
    result_files = [pscustomobject]@{
      baseline_webgl2 = $BaselineWebGl
      fork_default_webgl2 = $ForkWebGl
      aggressive_webgl2 = @()
      baseline_webgpu = @()
      fork_default_webgpu = @()
      runtime_smoke = $RuntimeSmoke
      navigation_lock = $NavigationLock
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        baseline_browser = New-FakeFileMetadata "baseline.exe"
        fork_browser = New-FakeFileMetadata "fork.exe"
        baseline_build_args = New-FakeFileMetadata "baseline-args.gn"
        fork_build_args = New-FakeFileMetadata "fork-args.gn"
        viewer_patch = New-FakeFileMetadata "not-the-viewer-patch.patch"
        baseline_package = New-MissingDirectoryMetadata ""
        fork_package = New-MissingDirectoryMetadata ""
      }
      results = [pscustomobject]@{
        baseline_webgl2 = New-MetadataList $BaselineWebGl
        fork_default_webgl2 = New-MetadataList $ForkWebGl
        aggressive_webgl2 = @()
        baseline_webgpu = @()
        fork_default_webgpu = @()
      }
      runtime_tests = [pscustomobject]@{
        smoke = New-MetadataList $RuntimeSmoke
        navigation_lock = New-MetadataList $NavigationLock
      }
      reports = [pscustomobject]@{
        baseline_webgl2_summary = New-FakeFileMetadata "baseline-webgl2-summary.md"
        fork_default_webgl2_summary = New-FakeFileMetadata "fork-default-webgl2-summary.md"
        official_webgl2_comparison = New-FakeFileMetadata "official-webgl2-comparison.md"
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

  $OfficialManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OfficialManifestPath -Encoding UTF8
  Invoke-AuditForTest $OfficialOutput
  $OfficialChecklist = Get-Content -LiteralPath $OfficialOutput -Raw
  $OfficialRejectedFakeInputs =
    ($OfficialChecklist -match "Official comparison manifest.*pending.*path/hash does not match files on disk" -and
      $OfficialChecklist -match "viewer_patch") -or
    ($OfficialChecklist -match "Official comparison manifest.*pending.*does not record both official WebGL2 summary report hashes")
  if (-not $OfficialRejectedFakeInputs) {
    throw "Artifact audit accepted or misreported a completed official manifest with fake artifact paths/hashes."
  }

  $ValidBaselineBrowser = Write-ArtifactFile (Join-Path $TempDir "valid-baseline.exe") "baseline-browser"
  $ValidForkBrowser = Write-ArtifactFile (Join-Path $TempDir "valid-fork.exe") "fork-browser"
  $ValidBaselineArgs = Write-ArtifactFile (Join-Path $TempDir "valid-baseline-args.gn") "is_debug=false"
  $ValidForkArgs = Write-ArtifactFile (Join-Path $TempDir "valid-fork-args.gn") "is_debug=false"
  $ValidBaselineArgsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ValidBaselineArgs).Hash.ToLowerInvariant()
  $ValidForkArgsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ValidForkArgs).Hash.ToLowerInvariant()
  $ValidBaselineSummary = Write-ArtifactFile (Join-Path $TempDir "valid-baseline-webgl2-summary.md") "# summary"
  $ValidForkSummary = Write-ArtifactFile (Join-Path $TempDir "valid-fork-webgl2-summary.md") "# summary"
  $ValidOfficialReport = Write-ArtifactFile (Join-Path $TempDir "valid-official-webgl2-comparison.md") "# comparison"
  $ValidBaselineWebGl = New-TempResultFiles "valid-baseline-content-shell" "webgl2"
  $ValidForkWebGl = New-TempResultFiles "valid-fork-viewer-default" "webgl2"
  Write-ArtifactFiles @($ValidBaselineWebGl + $ValidForkWebGl)
  Write-ValidSmokeFiles -RuntimeSmoke $RuntimeSmoke -NavigationLock $NavigationLock -BaselineBrowser $ValidBaselineBrowser -ForkBrowser $ValidForkBrowser
  $OtherOfficialResult = Write-ArtifactFile (Join-Path $TempDir "other-official-result.json") "{}"
  $ValidBaselineWebGlMetadata = New-RealMetadataList $ValidBaselineWebGl
  $ValidBaselineWebGlMetadata[0] = New-RealFileMetadata $OtherOfficialResult

  $OfficialManifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browsers = [pscustomobject]@{
      baseline = $ValidBaselineBrowser
      fork = $ValidForkBrowser
    }
    build_args = [pscustomobject]@{
      baseline = $ValidBaselineArgs
      fork = $ValidForkArgs
    }
    package_dirs = [pscustomobject]@{
      baseline = ""
      fork = ""
    }
    options = [pscustomobject]@{
      duration = 120
      warmup = 20
      include_webgpu = $false
      include_aggressive_gpu = $false
      capture_trace = $false
      skip_smoke = $false
      skip_navigation_lock = $false
    }
    suite_validation = New-OfficialSuiteValidation -ChromiumRevision $ChromiumRevision -ForkRevision $ForkRevision -BaselineBrowser $ValidBaselineBrowser -ForkBrowser $ValidForkBrowser -BaselineBuildArgsHash $ValidBaselineArgsHash -ForkBuildArgsHash $ValidForkArgsHash
    result_files = [pscustomobject]@{
      baseline_webgl2 = $ValidBaselineWebGl
      fork_default_webgl2 = $ValidForkWebGl
      aggressive_webgl2 = @()
      baseline_webgpu = @()
      fork_default_webgpu = @()
      runtime_smoke = $RuntimeSmoke
      navigation_lock = $NavigationLock
    }
    report_files = [pscustomobject]@{
      baseline_webgl2_summary = $ValidBaselineSummary
      fork_default_webgl2_summary = $ValidForkSummary
      official_webgl2_comparison = $ValidOfficialReport
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        baseline_browser = New-RealFileMetadata $ValidBaselineBrowser
        fork_browser = New-RealFileMetadata $ValidForkBrowser
        baseline_build_args = New-RealFileMetadata $ValidBaselineArgs
        fork_build_args = New-RealFileMetadata $ValidForkArgs
        viewer_patch = New-RealFileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
        baseline_package = New-MissingDirectoryMetadata ""
        fork_package = New-MissingDirectoryMetadata ""
      }
      results = [pscustomobject]@{
        baseline_webgl2 = $ValidBaselineWebGlMetadata
        fork_default_webgl2 = New-RealMetadataList $ValidForkWebGl
        aggressive_webgl2 = @()
        baseline_webgpu = @()
        fork_default_webgpu = @()
      }
      runtime_tests = [pscustomobject]@{
        smoke = New-RealMetadataList $RuntimeSmoke
        navigation_lock = New-RealMetadataList $NavigationLock
      }
      reports = [pscustomobject]@{
        baseline_webgl2_summary = New-RealFileMetadata $ValidBaselineSummary
        fork_default_webgl2_summary = New-RealFileMetadata $ValidForkSummary
        official_webgl2_comparison = New-RealFileMetadata $ValidOfficialReport
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

  $OfficialManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OfficialManifestPath -Encoding UTF8
  Invoke-AuditForTest $OfficialOutput
  $OfficialChecklist = Get-Content -LiteralPath $OfficialOutput -Raw
  if ($OfficialChecklist -notmatch "Official comparison manifest.*pending.*path/hash does not match files on disk" -or $OfficialChecklist -notmatch "result:baseline_webgl2:0") {
    throw "Artifact audit accepted or misreported official result metadata for a different valid file."
  }

  $ValidOfficialPackage = Write-PackageDir (Join-Path $TempDir "valid-official-package") "official-package"
  $OtherOfficialPackage = Write-PackageDir (Join-Path $TempDir "other-official-package") "other-official-package"
  $OfficialManifest.package_dirs.fork = $ValidOfficialPackage
  $OfficialManifest.artifact_metadata.results.baseline_webgl2 = New-RealMetadataList $ValidBaselineWebGl
  $OfficialManifest.artifact_metadata.inputs.fork_package = New-RealDirectoryMetadata $OtherOfficialPackage
  $OfficialManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OfficialManifestPath -Encoding UTF8
  Invoke-AuditForTest $OfficialOutput
  $OfficialChecklist = Get-Content -LiteralPath $OfficialOutput -Raw
  if ($OfficialChecklist -notmatch "Official comparison manifest.*pending.*package metadata whose path/count/size does not match disk" -or $OfficialChecklist -notmatch "fork_package") {
    throw "Artifact audit accepted or misreported official package metadata for a different valid directory."
  }

  $MismatchedOfficialPackage = Write-PackageDir (Join-Path $TempDir "mismatched-official-package") "official-package" "stale-fork-browser"
  $OfficialManifest.package_dirs.fork = $MismatchedOfficialPackage
  $OfficialManifest.artifact_metadata.inputs.fork_package = New-RealDirectoryMetadata $MismatchedOfficialPackage
  $OfficialManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OfficialManifestPath -Encoding UTF8
  Invoke-AuditForTest $OfficialOutput
  $OfficialChecklist = Get-Content -LiteralPath $OfficialOutput -Raw
  if ($OfficialChecklist -notmatch "Official comparison manifest.*pending.*package executable hash that does not match the manifest browser" -or $OfficialChecklist -notmatch "fork_package") {
    throw "Artifact audit accepted or misreported an official package whose executable does not match the fork browser metadata."
  }

  $Experiments = @(
    (New-Experiment "fork-viewer-exp-default" @())
    (New-Experiment "fork-viewer-exp-aggressive-gpu" @("--viewerAggressiveGpu"))
    (New-Experiment "fork-viewer-exp-zero-copy" @("--viewerZeroCopy"))
    (New-Experiment "fork-viewer-exp-in-process-gpu" @("--viewerInProcessGpu"))
    (New-Experiment "fork-viewer-exp-single-process" @("--viewerSingleProcess"))
    (New-Experiment "fork-viewer-exp-angle-d3d11" @("--viewerForceAngleBackend", "d3d11"))
    (New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" @("--viewerRelaxedWebglValidation"))
    (New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" @("--viewerDisableUnneededBlinkFeatures"))
    (New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" @("--viewerDirectGpuPresentation"))
  )
  $AllResultFiles = @($Experiments | ForEach-Object { $_.result_files })
  $TrustedFakePackage = Write-PackageDir (Join-Path $TempDir "trusted-fake-path-package") "trusted-package"
  $TrustedManifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browser = "fork.exe"
    build_args = "fork-args.gn"
    package_dir = $TrustedFakePackage
    renderer = "webgl2"
    scenes = $RequiredScenes
    suite_validation = New-TrustedSuiteValidation -ChromiumRevision $ChromiumRevision -ForkRevision $ForkRevision
    options = [pscustomobject]@{
      duration = 60
      warmup = 10
      precompile = $false
      prerender_frames = 0
    }
    experiments = $Experiments
    result_files = [pscustomobject]@{
      all = $AllResultFiles
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        browser = New-FakeFileMetadata "fork.exe"
        build_args = New-FakeFileMetadata "fork-args.gn"
        viewer_patch = New-FakeFileMetadata "not-the-viewer-patch.patch"
        package = New-RealDirectoryMetadata $TrustedFakePackage
      }
      results = [pscustomobject]@{
        all = New-MetadataList $AllResultFiles
      }
      reports = [pscustomobject]@{
        summary = New-FakeFileMetadata "trusted-summary.md"
        comparison = New-FakeFileMetadata "trusted-comparison.md"
      }
    }
  }

  $TrustedManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $TrustedManifestPath -Encoding UTF8
  Invoke-AuditForTest $TrustedOutput
  $TrustedChecklist = Get-Content -LiteralPath $TrustedOutput -Raw
  if ($TrustedChecklist -notmatch "Trusted experiment matrix manifest.*pending.*path/hash does not match files on disk" -or
      $TrustedChecklist -notmatch "viewer_patch") {
    throw "Artifact audit accepted or misreported a completed trusted manifest with fake artifact paths/hashes."
  }

  $ValidTrustedBrowser = Write-ArtifactFile (Join-Path $TempDir "valid-trusted-fork.exe") "trusted-browser"
  $ValidTrustedArgs = Write-ArtifactFile (Join-Path $TempDir "valid-trusted-args.gn") "is_debug=false"
  $ValidTrustedSummary = Write-ArtifactFile (Join-Path $TempDir "valid-trusted-summary.md") "# trusted summary"
  $ValidTrustedComparison = Write-ArtifactFile (Join-Path $TempDir "valid-trusted-comparison.md") "# trusted comparison"
  $ValidTrustedPackageForPathTest = Write-PackageDir (Join-Path $TempDir "valid-trusted-package-for-path-test") "trusted-package"
  $ValidTrustedExperiments = @(
    (New-Experiment "fork-viewer-exp-default" @())
    (New-Experiment "fork-viewer-exp-aggressive-gpu" @("--viewerAggressiveGpu"))
    (New-Experiment "fork-viewer-exp-zero-copy" @("--viewerZeroCopy"))
    (New-Experiment "fork-viewer-exp-in-process-gpu" @("--viewerInProcessGpu"))
    (New-Experiment "fork-viewer-exp-single-process" @("--viewerSingleProcess"))
    (New-Experiment "fork-viewer-exp-angle-d3d11" @("--viewerForceAngleBackend", "d3d11"))
    (New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" @("--viewerRelaxedWebglValidation"))
    (New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" @("--viewerDisableUnneededBlinkFeatures"))
    (New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" @("--viewerDirectGpuPresentation"))
  )
  foreach ($Experiment in $ValidTrustedExperiments) {
    $Experiment.result_files = New-TempResultFiles $Experiment.label "webgl2"
    Write-ArtifactFiles @($Experiment.result_files)
  }
  $ValidTrustedResultFiles = @($ValidTrustedExperiments | ForEach-Object { $_.result_files })
  $OtherTrustedResult = Write-ArtifactFile (Join-Path $TempDir "other-trusted-result.json") "{}"
  $ValidTrustedMetadata = New-RealMetadataList $ValidTrustedResultFiles
  $ValidTrustedMetadata[0] = New-RealFileMetadata $OtherTrustedResult

  $TrustedManifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browser = $ValidTrustedBrowser
    build_args = $ValidTrustedArgs
    package_dir = $ValidTrustedPackageForPathTest
    renderer = "webgl2"
    scenes = $RequiredScenes
    suite_validation = New-TrustedSuiteValidation -ChromiumRevision $ChromiumRevision -ForkRevision $ForkRevision -Browser $ValidTrustedBrowser -BuildArgsHash ((Get-FileHash -Algorithm SHA256 -LiteralPath $ValidTrustedArgs).Hash.ToLowerInvariant())
    options = [pscustomobject]@{
      duration = 60
      warmup = 10
      precompile = $false
      prerender_frames = 0
    }
    experiments = $ValidTrustedExperiments
    result_files = [pscustomobject]@{
      all = $ValidTrustedResultFiles
    }
    report_files = [pscustomobject]@{
      summary = $ValidTrustedSummary
      comparison = $ValidTrustedComparison
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        browser = New-RealFileMetadata $ValidTrustedBrowser
        build_args = New-RealFileMetadata $ValidTrustedArgs
        viewer_patch = New-RealFileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
        package = New-RealDirectoryMetadata $ValidTrustedPackageForPathTest
      }
      results = [pscustomobject]@{
        all = $ValidTrustedMetadata
      }
      reports = [pscustomobject]@{
        summary = New-RealFileMetadata $ValidTrustedSummary
        comparison = New-RealFileMetadata $ValidTrustedComparison
      }
    }
  }

  $TrustedManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $TrustedManifestPath -Encoding UTF8
  Invoke-AuditForTest $TrustedOutput
  $TrustedChecklist = Get-Content -LiteralPath $TrustedOutput -Raw
  if ($TrustedChecklist -notmatch "Trusted experiment matrix manifest.*pending.*path/hash does not match files on disk" -or $TrustedChecklist -notmatch "result:0") {
    throw "Artifact audit accepted or misreported trusted result metadata for a different valid file."
  }

  $ValidTrustedPackage = Write-PackageDir (Join-Path $TempDir "valid-trusted-package") "trusted-package"
  $OtherTrustedPackage = Write-PackageDir (Join-Path $TempDir "other-trusted-package") "other-trusted-package"
  $TrustedManifest.package_dir = $ValidTrustedPackage
  $TrustedManifest.artifact_metadata.results.all = New-RealMetadataList $ValidTrustedResultFiles
  $TrustedManifest.artifact_metadata.inputs.package = New-RealDirectoryMetadata $OtherTrustedPackage
  $TrustedManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $TrustedManifestPath -Encoding UTF8
  Invoke-AuditForTest $TrustedOutput
  $TrustedChecklist = Get-Content -LiteralPath $TrustedOutput -Raw
  if ($TrustedChecklist -notmatch "Trusted experiment matrix manifest.*pending.*package metadata whose path/count/size does not match disk" -or $TrustedChecklist -notmatch "package") {
    throw "Artifact audit accepted or misreported trusted package metadata for a different valid directory."
  }

  $MismatchedTrustedPackage = Write-PackageDir (Join-Path $TempDir "mismatched-trusted-package") "trusted-package" "stale-trusted-browser"
  $TrustedManifest.package_dir = $MismatchedTrustedPackage
  $TrustedManifest.artifact_metadata.inputs.package = New-RealDirectoryMetadata $MismatchedTrustedPackage
  $TrustedManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $TrustedManifestPath -Encoding UTF8
  Invoke-AuditForTest $TrustedOutput
  $TrustedChecklist = Get-Content -LiteralPath $TrustedOutput -Raw
  if ($TrustedChecklist -notmatch "Trusted experiment matrix manifest.*pending.*package executable hash that does not match the manifest browser" -or $TrustedChecklist -notmatch "package") {
    throw "Artifact audit accepted or misreported a trusted package whose executable does not match the fork browser metadata."
  }
} finally {
  if ($HadOfficialManifest) {
    Copy-Item -LiteralPath $OfficialBackupPath -Destination $OfficialManifestPath -Force
  } elseif (Test-Path -LiteralPath $OfficialManifestPath) {
    Remove-Item -LiteralPath $OfficialManifestPath -Force
  }
  if ($HadTrustedManifest) {
    Copy-Item -LiteralPath $TrustedBackupPath -Destination $TrustedManifestPath -Force
  } elseif (Test-Path -LiteralPath $TrustedManifestPath) {
    Remove-Item -LiteralPath $TrustedManifestPath -Force
  }
  if ($HadPinRefresh) {
    Copy-Item -LiteralPath $PinRefreshBackupPath -Destination $PinRefreshPath -Force
  } elseif (Test-Path -LiteralPath $PinRefreshPath) {
    Remove-Item -LiteralPath $PinRefreshPath -Force
  }
  foreach ($PathValue in @($OfficialBackupPath, $TrustedBackupPath, $PinRefreshBackupPath, $OfficialOutput, $TrustedOutput)) {
    if (Test-Path -LiteralPath $PathValue) {
      Remove-Item -LiteralPath $PathValue -Force
    }
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Manifest audit rejects completed manifests whose artifact paths or hashes do not match disk."

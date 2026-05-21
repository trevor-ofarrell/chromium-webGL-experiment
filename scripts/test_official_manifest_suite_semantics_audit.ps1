[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\official-manifest-suite-semantics-audit"
$ManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$PinRefreshPath = Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json"
$PinRefreshBackupPath = Join-Path $TempDir "chromium-pin-refresh.official-suite-semantics-audit.backup.json"
$TempOutput = Join-Path $TempDir "official-manifest-suite-semantics-audit.md"
$RequiredScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)
$BrowserModeFlags = @(
  "viewer_mode=false",
  "viewer_block_external_navigation=false",
  "viewer_trusted_content=false",
  "viewer_aggressive_gpu=false",
  "viewer_relaxed_webgl_validation=false",
  "viewer_in_process_gpu=false",
  "viewer_single_process=false",
  "viewer_force_angle_backend=null",
  "requested_angle_backend=null",
  "viewer_disable_unneeded_blink_features=false",
  "viewer_direct_gpu_presentation=false"
)
$ForkDefaultFlags = @(
  "viewer_mode=true",
  "viewer_block_external_navigation=true",
  "viewer_trusted_content=true",
  "viewer_aggressive_gpu=false",
  "viewer_relaxed_webgl_validation=false",
  "viewer_in_process_gpu=false",
  "viewer_single_process=false",
  "viewer_force_angle_backend=null",
  "requested_angle_backend=null",
  "viewer_disable_unneeded_blink_features=false",
  "viewer_direct_gpu_presentation=false"
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

function New-FileMetadata {
  param([string]$PathValue)

  [pscustomobject]@{
    path = $PathValue
    exists = $true
    size_bytes = (Get-Item -LiteralPath $PathValue).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
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

function New-MetadataList {
  param([string[]]$Paths)
  @($Paths | ForEach-Object { New-FileMetadata $_ })
}

function New-OfficialComparisonReportContent {
  param([string[]]$Scenes = $RequiredScenes)

  $Rows = [System.Collections.Generic.List[string]]::new()
  foreach ($Scene in $Scenes) {
    $Rows.Add("| $Scene | webgl2 | baseline-content-shell | 60 | 0 | 0 | 0 |") | Out-Null
    $Rows.Add("| $Scene | webgl2 | fork-viewer-default | 60 | 0 | 0 | 0 |") | Out-Null
  }

  @"
# Benchmark Comparison

Generated from synthetic official manifest test fixtures.

Strict official input validation was enabled: synthetic.

| Scene | Renderer | Variant | Avg FPS | Dropped Delta | JS heap Delta | GPU memory Delta |
| --- | --- | --- | ---: | ---: | ---: | ---: |
$($Rows -join "`n")
"@
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

function New-Result {
  param(
    [string]$Scene,
    [string]$Variant,
    [string]$ChromiumRevision,
    [AllowNull()][string]$ForkRevision,
    [string]$BuildArgsHash,
    [string]$BrowserExecutable,
    [bool]$ViewerMode,
    [bool]$ViewerBlockExternalNavigation,
    [bool]$ViewerTrustedContent
  )

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
    warmup_seconds = 20
    measured_seconds = 120
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
    package_size_mb = $null
    browser_executable = $BrowserExecutable
    browser_is_from_checkout = $true
    benchmark_variant = $Variant
    viewer_mode = $ViewerMode
    viewer_block_external_navigation = $ViewerBlockExternalNavigation
    viewer_trusted_content = $ViewerTrustedContent
    viewer_aggressive_gpu = $false
    viewer_relaxed_webgl_validation = $false
    viewer_in_process_gpu = $false
    viewer_single_process = $false
    viewer_force_angle_backend = $null
    requested_angle_backend = $null
    viewer_disable_unneeded_blink_features = $false
    viewer_direct_gpu_presentation = $false
    browser_flags = @("--disable-software-rasterizer")
  }
}

function Write-ResultSuite {
  param(
    [string[]]$Paths,
    [string]$Variant,
    [string]$ChromiumRevision,
    [AllowNull()][string]$ForkRevision,
    [string]$BuildArgsHash,
    [string]$BrowserExecutable,
    [bool]$ViewerMode,
    [bool]$ViewerBlockExternalNavigation,
    [bool]$ViewerTrustedContent
  )

  for ($Index = 0; $Index -lt $RequiredScenes.Count; $Index += 1) {
    Write-Json $Paths[$Index] (New-Result `
        -Scene $RequiredScenes[$Index] `
        -Variant $Variant `
        -ChromiumRevision $ChromiumRevision `
        -ForkRevision $ForkRevision `
        -BuildArgsHash $BuildArgsHash `
        -BrowserExecutable $BrowserExecutable `
        -ViewerMode $ViewerMode `
        -ViewerBlockExternalNavigation $ViewerBlockExternalNavigation `
        -ViewerTrustedContent $ViewerTrustedContent)
  }
}

function Write-ValidSmokeFiles {
  param(
    [string[]]$RuntimeSmoke,
    [string[]]$NavigationLock,
    [string]$BaselineBrowser,
    [string]$ForkBrowser
  )

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

function New-TraceFile {
  param([string]$PathValue)

  Write-Json $PathValue ([pscustomobject]@{
      traceEvents = @(
        [pscustomobject]@{ name = "RunTask"; ph = "X"; ts = 1; dur = 1000; pid = 1; tid = 1 },
        [pscustomobject]@{ name = "SubmitCompositorFrame"; ph = "X"; ts = 2; dur = 500; pid = 1; tid = 2 }
      )
    })
}

function New-TraceSidecar {
  param(
    [string]$PathValue,
    [string]$Browser,
    [bool]$ViewerMode,
    [bool]$ViewerTrustedContent,
    [bool]$ViewerBlockExternalNavigation
  )

  Write-Json $PathValue ([pscustomobject]@{
      generated_at = "2026-05-16T00:00:00.000Z"
      platform = "test-platform"
      browser = $Browser
      scene = "many-draw-calls"
      renderer = "webgl2"
      duration_seconds = 10
      warmup_seconds = 2
      start_delay_ms = 2000
      viewer_mode = $ViewerMode
      viewer_block_external_navigation = $ViewerBlockExternalNavigation
      viewer_trusted_content = $ViewerTrustedContent
      viewer_aggressive_gpu = $false
      viewer_relaxed_webgl_validation = $false
      viewer_in_process_gpu = $false
      viewer_single_process = $false
      viewer_force_angle_backend = $null
      requested_angle_backend = $null
      viewer_disable_unneeded_blink_features = $false
      viewer_direct_gpu_presentation = $false
      browser_flags = @("--disable-software-rasterizer")
      categories = "gpu,viz,v8"
      benchmark_result = [pscustomobject]@{
        scene_name = "many-draw-calls"
        renderer_type = "webgl2"
        measured_seconds = 10
        warmup_seconds = 2
        avg_fps = 60
        startup_ms_to_first_frame = 123
      }
    })
}

function New-TraceSummaryReportContent {
  param([string]$TracePath)

  $Tick = [char]0x60
  $TraceLine = "Trace: $Tick$TracePath$Tick"
  @"
# Trace Summary

$TraceLine

Total events: 2

## Classified Events

| Class | Count | Total Duration ms |
| --- | ---: | ---: |
| presentation | 1 | 0.50 |
| other | 1 | 1.00 |

## Top Duration Events

| Event | Count | Total ms | Max ms |
| --- | ---: | ---: | ---: |
| RunTask | 1 | 1.00 | 1.00 |

Classification is name-based and intended for triage. Confirm important findings against the raw trace.
"@
}

function New-OfficialManifest {
  param(
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string]$BaselineBrowser,
    [string]$ForkBrowser,
    [string]$BaselineBuildArgs,
    [string]$ForkBuildArgs,
    [string]$OfficialReport,
    [string[]]$BaselineWebGl,
    [string[]]$ForkWebGl,
    [string[]]$RuntimeSmoke,
    [string[]]$NavigationLock
  )

  $BaselineBuildArgsHash = Get-Sha256 $BaselineBuildArgs
  $ForkBuildArgsHash = Get-Sha256 $ForkBuildArgs
  [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $false
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    browsers = [pscustomobject]@{
      baseline = $BaselineBrowser
      fork = $ForkBrowser
    }
    build_args = [pscustomobject]@{
      baseline = $BaselineBuildArgs
      fork = $ForkBuildArgs
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
      aggressive_angle_backend = ""
      capture_trace = $false
      trace_scene = "many-draw-calls"
      trace_renderer = "webgl2"
      trace_duration = 10
      trace_warmup = 2
      trace_start_delay_ms = 2000
      skip_smoke = $false
      skip_navigation_lock = $false
    }
    labels = [pscustomobject]@{
      baseline = "baseline-content-shell"
      fork_default = "fork-viewer-default"
      aggressive = ""
    }
    scenes = $RequiredScenes
    suite_validation = [pscustomobject]@{
      require_checkout = $true
      require_build_args = $true
      expected_baseline_build_args_hash = $BaselineBuildArgsHash
      expected_fork_build_args_hash = $ForkBuildArgsHash
      forbid_smoke = $true
      reject_software_rendering = $true
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
        baseline = $BrowserModeFlags
        fork_default = $ForkDefaultFlags
        aggressive = @()
        baseline_webgpu = @()
        fork_default_webgpu = @()
        aggressive_webgpu = @()
      }
    }
    result_files = [pscustomobject]@{
      baseline_webgl2 = $BaselineWebGl
      fork_default_webgl2 = $ForkWebGl
      aggressive_webgl2 = @()
      baseline_webgpu = @()
      fork_default_webgpu = @()
      aggressive_webgpu = @()
      runtime_smoke = $RuntimeSmoke
      navigation_lock = $NavigationLock
    }
    report_files = [pscustomobject]@{
      official_webgl2_comparison = $OfficialReport
      official_webgpu_comparison = $null
      baseline_trace_summary = $null
      fork_trace_summary = $null
    }
    trace_files = [pscustomobject]@{
      baseline = $null
      fork = $null
    }
    trace_result_files = [pscustomobject]@{
      baseline = $null
      fork = $null
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        baseline_browser = New-FileMetadata $BaselineBrowser
        fork_browser = New-FileMetadata $ForkBrowser
        baseline_build_args = New-FileMetadata $BaselineBuildArgs
        fork_build_args = New-FileMetadata $ForkBuildArgs
        viewer_patch = New-FileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
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
        official_webgl2_comparison = New-FileMetadata $OfficialReport
        official_webgpu_comparison = New-MissingFileMetadata ""
        baseline_trace_summary = New-MissingFileMetadata ""
        fork_trace_summary = New-MissingFileMetadata ""
      }
      traces = [pscustomobject]@{
        baseline = New-MissingFileMetadata ""
        fork = New-MissingFileMetadata ""
        baseline_result = New-MissingFileMetadata ""
        fork_result = New-MissingFileMetadata ""
      }
    }
  }
}

function Invoke-AuditAndReadChecklist {
  $OldAllowManifestOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
  $OldOfficialManifestPath = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
  $OldTrustedManifestPath = $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST
  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $ManifestPath
  Remove-Item Env:\THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST -ErrorAction SilentlyContinue
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $TempOutput -ManifestAuditOnly *>&1
  } finally {
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
$HadPinRefresh = Test-Path -LiteralPath $PinRefreshPath
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
    source = "synthetic official suite semantics audit test"
    skip_sync = $true
    skip_hooks = $true
    skip_gn_gen = $true
  }
  New-Item -ItemType Directory -Path (Split-Path $PinRefreshPath -Parent) -Force | Out-Null
  Write-Json $PinRefreshPath $SyntheticPinRefresh

  $PatchHash = Get-ShortSha256 (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
  $ForkRevision = "$ChromiumRevision+viewerpatch-$PatchHash"
  $BaselineBrowser = Write-ArtifactFile (Join-Path $TempDir "baseline.exe") "baseline-browser"
  $ForkBrowser = Write-ArtifactFile (Join-Path $TempDir "fork.exe") "fork-browser"
  $BaselineBuildArgs = Write-ArtifactFile (Join-Path $TempDir "baseline-args.gn") "is_debug=false"
  $ForkBuildArgs = Write-ArtifactFile (Join-Path $TempDir "fork-args.gn") "is_debug=false"
  $BaselineBuildArgsHash = Get-Sha256 $BaselineBuildArgs
  $ForkBuildArgsHash = Get-Sha256 $ForkBuildArgs
  $OfficialReport = Write-ArtifactFile (Join-Path $TempDir "official-webgl2-comparison.md") (New-OfficialComparisonReportContent)
  $BaselineWebGl = New-TempResultFiles "baseline-content-shell" "webgl2"
  $ForkWebGl = New-TempResultFiles "fork-viewer-default" "webgl2"
  $RuntimeSmoke = @(
    (Join-Path $TempDir "baseline-content-shell-runtime-smoke.json"),
    (Join-Path $TempDir "fork-viewer-default-runtime-smoke.json")
  )
  $NavigationLock = @(
    (Join-Path $TempDir "fork-viewer-default-navigation-lock.json"),
    (Join-Path $TempDir "fork-viewer-default-file-navigation-lock.json")
  )

  Write-ResultSuite -Paths $BaselineWebGl -Variant "baseline-content-shell" -ChromiumRevision $ChromiumRevision -ForkRevision $null -BuildArgsHash $BaselineBuildArgsHash -BrowserExecutable $BaselineBrowser -ViewerMode $false -ViewerBlockExternalNavigation $false -ViewerTrustedContent $false
  Write-ResultSuite -Paths $ForkWebGl -Variant "fork-viewer-default" -ChromiumRevision $ChromiumRevision -ForkRevision $ForkRevision -BuildArgsHash $ForkBuildArgsHash -BrowserExecutable $ForkBrowser -ViewerMode $true -ViewerBlockExternalNavigation $true -ViewerTrustedContent $true
  Write-ValidSmokeFiles -RuntimeSmoke $RuntimeSmoke -NavigationLock $NavigationLock -BaselineBrowser $BaselineBrowser -ForkBrowser $ForkBrowser

  $Manifest = New-OfficialManifest `
    -ChromiumRevision $ChromiumRevision `
    -ForkRevision $ForkRevision `
    -BaselineBrowser $BaselineBrowser `
    -ForkBrowser $ForkBrowser `
    -BaselineBuildArgs $BaselineBuildArgs `
    -ForkBuildArgs $ForkBuildArgs `
    -OfficialReport $OfficialReport `
    -BaselineWebGl $BaselineWebGl `
    -ForkWebGl $ForkWebGl `
    -RuntimeSmoke $RuntimeSmoke `
    -NavigationLock $NavigationLock
  Write-Json $ManifestPath $Manifest
  $DoneChecklist = Invoke-AuditAndReadChecklist
  if ($DoneChecklist -notmatch "Official comparison manifest.*done.*benchmark suites semantically validated") {
    throw "Artifact audit did not accept a completed official manifest whose exact suites pass validation. Checklist: $DoneChecklist"
  }

  $WrongBrowserResultPath = [string]$BaselineWebGl[0]
  $OriginalWrongBrowserResult = Get-Content -LiteralPath $WrongBrowserResultPath -Raw | ConvertFrom-Json
  $WrongBrowserResult = Get-Content -LiteralPath $WrongBrowserResultPath -Raw | ConvertFrom-Json
  $WrongBrowserResult.browser_executable = Join-Path $TempDir "wrong-baseline-browser.exe"
  Write-Json $WrongBrowserResultPath $WrongBrowserResult
  $Manifest.artifact_metadata.results.baseline_webgl2 = New-MetadataList $BaselineWebGl
  Write-Json $ManifestPath $Manifest
  $WrongBrowserChecklist = Invoke-AuditAndReadChecklist
  if ($WrongBrowserChecklist -notmatch "Official comparison manifest.*pending.*suite validation failed" -or
      $WrongBrowserChecklist -notmatch "browser_executable") {
    throw "Artifact audit accepted or misreported a completed official manifest whose exact result file records the wrong browser executable. Checklist: $WrongBrowserChecklist"
  }
  Write-Json $WrongBrowserResultPath $OriginalWrongBrowserResult
  $Manifest.artifact_metadata.results.baseline_webgl2 = New-MetadataList $BaselineWebGl
  Write-Json $ManifestPath $Manifest

  $BaselineTrace = Join-Path $TempDir "baseline-trace.json"
  $ForkTrace = Join-Path $TempDir "fork-trace.json"
  $BaselineTraceSidecar = Join-Path $TempDir "baseline-trace.result.json"
  $ForkTraceSidecar = Join-Path $TempDir "fork-trace.result.json"
  $BaselineTraceSummary = Write-ArtifactFile (Join-Path $TempDir "baseline-trace-summary.md") (New-TraceSummaryReportContent -TracePath $BaselineTrace)
  $ForkTraceSummary = Write-ArtifactFile (Join-Path $TempDir "fork-trace-summary.md") (New-TraceSummaryReportContent -TracePath $ForkTrace)
  New-TraceFile $BaselineTrace
  New-TraceFile $ForkTrace
  New-TraceSidecar $BaselineTraceSidecar -Browser $BaselineBrowser -ViewerMode $false -ViewerTrustedContent $false -ViewerBlockExternalNavigation $false
  New-TraceSidecar $ForkTraceSidecar -Browser $ForkBrowser -ViewerMode $true -ViewerTrustedContent $true -ViewerBlockExternalNavigation $true

  $Manifest.options.capture_trace = $true
  $Manifest.report_files.baseline_trace_summary = $BaselineTraceSummary
  $Manifest.report_files.fork_trace_summary = $ForkTraceSummary
  $Manifest.trace_files.baseline = $BaselineTrace
  $Manifest.trace_files.fork = $ForkTrace
  $Manifest.trace_result_files.baseline = $BaselineTraceSidecar
  $Manifest.trace_result_files.fork = $ForkTraceSidecar
  $Manifest.artifact_metadata.traces.baseline = New-FileMetadata $BaselineTrace
  $Manifest.artifact_metadata.traces.fork = New-FileMetadata $ForkTrace
  $Manifest.artifact_metadata.traces.baseline_result = New-FileMetadata $BaselineTraceSidecar
  $Manifest.artifact_metadata.traces.fork_result = New-FileMetadata $ForkTraceSidecar
  $Manifest.artifact_metadata.reports.baseline_trace_summary = New-FileMetadata $BaselineTraceSummary
  $Manifest.artifact_metadata.reports.fork_trace_summary = New-FileMetadata $ForkTraceSummary
  Write-Json $ManifestPath $Manifest
  $TraceDoneChecklist = Invoke-AuditAndReadChecklist
  if ($TraceDoneChecklist -notmatch "Official comparison manifest.*done.*trace-summary content validation") {
    throw "Artifact audit did not accept a completed official manifest whose trace summaries pass validation. Checklist: $TraceDoneChecklist"
  }

  $null = Write-ArtifactFile $BaselineTraceSummary "not a trace summary"
  $Manifest.artifact_metadata.reports.baseline_trace_summary = New-FileMetadata $BaselineTraceSummary
  Write-Json $ManifestPath $Manifest
  $BadTraceSummaryChecklist = Invoke-AuditAndReadChecklist
  if ($BadTraceSummaryChecklist -notmatch "Official comparison manifest.*pending.*report content validation failed" -or
      $BadTraceSummaryChecklist -notmatch "baseline_trace_summary missing trace summary heading") {
    throw "Artifact audit accepted or misreported a completed official manifest whose hashed trace summary content is invalid. Checklist: $BadTraceSummaryChecklist"
  }

  $null = Write-ArtifactFile $BaselineTraceSummary (New-TraceSummaryReportContent -TracePath $BaselineTrace)
  $Manifest.artifact_metadata.reports.baseline_trace_summary = New-FileMetadata $BaselineTraceSummary
  $Manifest.options.capture_trace = $false
  $Manifest.report_files.baseline_trace_summary = $null
  $Manifest.report_files.fork_trace_summary = $null
  $Manifest.trace_files.baseline = $null
  $Manifest.trace_files.fork = $null
  $Manifest.trace_result_files.baseline = $null
  $Manifest.trace_result_files.fork = $null
  $Manifest.artifact_metadata.traces.baseline = New-MissingFileMetadata ""
  $Manifest.artifact_metadata.traces.fork = New-MissingFileMetadata ""
  $Manifest.artifact_metadata.traces.baseline_result = New-MissingFileMetadata ""
  $Manifest.artifact_metadata.traces.fork_result = New-MissingFileMetadata ""
  $Manifest.artifact_metadata.reports.baseline_trace_summary = New-MissingFileMetadata ""
  $Manifest.artifact_metadata.reports.fork_trace_summary = New-MissingFileMetadata ""

  $null = Write-ArtifactFile $OfficialReport (New-OfficialComparisonReportContent -Scenes @($RequiredScenes | Select-Object -Skip 1))
  $Manifest.artifact_metadata.reports.official_webgl2_comparison = New-FileMetadata $OfficialReport
  Write-Json $ManifestPath $Manifest
  $SceneIncompleteReportChecklist = Invoke-AuditAndReadChecklist
  if ($SceneIncompleteReportChecklist -notmatch "Official comparison manifest.*pending.*report content validation failed" -or
      $SceneIncompleteReportChecklist -notmatch "official_webgl2_comparison missing scene many-draw-calls") {
    throw "Artifact audit accepted or misreported a completed official manifest whose report omits a required scene. Checklist: $SceneIncompleteReportChecklist"
  }

  $null = Write-ArtifactFile $OfficialReport "not a benchmark comparison report"
  $Manifest.artifact_metadata.reports.official_webgl2_comparison = New-FileMetadata $OfficialReport
  Write-Json $ManifestPath $Manifest
  $BadReportChecklist = Invoke-AuditAndReadChecklist
  if ($BadReportChecklist -notmatch "Official comparison manifest.*pending.*report content validation failed" -or
      $BadReportChecklist -notmatch "official_webgl2_comparison missing comparison heading") {
    throw "Artifact audit accepted or misreported a completed official manifest whose hashed report content is not a comparison report. Checklist: $BadReportChecklist"
  }

  $null = Write-ArtifactFile $OfficialReport (New-OfficialComparisonReportContent)
  $Manifest.artifact_metadata.reports.official_webgl2_comparison = New-FileMetadata $OfficialReport

  $BadForkResult = Get-Content -LiteralPath $ForkWebGl[0] -Raw | ConvertFrom-Json
  $BadForkResult.measured_seconds = 119
  Write-Json $ForkWebGl[0] $BadForkResult
  $Manifest.artifact_metadata.results.fork_default_webgl2 = New-MetadataList $ForkWebGl
  Write-Json $ManifestPath $Manifest
  $BadChecklist = Invoke-AuditAndReadChecklist
  if ($BadChecklist -notmatch "Official comparison manifest.*pending.*suite validation failed" -or
      $BadChecklist -notmatch "measured_seconds") {
    throw "Artifact audit accepted or misreported a completed official manifest whose exact result file fails benchmark suite validation. Checklist: $BadChecklist"
  }
} finally {
  if ($HadPinRefresh) {
    Copy-Item -LiteralPath $PinRefreshBackupPath -Destination $PinRefreshPath -Force
  } elseif (Test-Path -LiteralPath $PinRefreshPath) {
    Remove-Item -LiteralPath $PinRefreshPath -Force
  }
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Official manifest audit semantically validates exact benchmark suite files, comparison reports, and trace summaries before marking comparison evidence complete."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\official-manifest-trace-audit"
$ManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$BackupPath = Join-Path $TempDir "official-comparison-manifest.trace-audit.backup.json"
$TempOutput = Join-Path $TempDir "official-manifest-trace-audit.md"
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

function New-FileMetadata {
  param([string]$PathValue)
  if (Test-Path -LiteralPath $PathValue -PathType Leaf) {
    return [pscustomobject]@{
      path = $PathValue
      exists = $true
      size_bytes = (Get-Item -LiteralPath $PathValue).Length
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
    }
  }

  return [pscustomobject]@{
    path = $PathValue
    exists = $true
    size_bytes = 123
    sha256 = "0123456789abcdef"
  }
}

function New-MissingMetadata {
  param([string]$PathValue)
  return [pscustomobject]@{
    path = $PathValue
    exists = $false
    size_bytes = $null
    sha256 = $null
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

function Write-ArtifactFile {
  param(
    [string]$PathValue,
    [string]$Content
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  [System.IO.File]::WriteAllText($PathValue, $Content, [System.Text.UTF8Encoding]::new($false))
  return $PathValue
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

function New-OfficialComparisonReportContent {
  param([string[]]$Scenes = $RequiredScenes)

  $Rows = [System.Collections.Generic.List[string]]::new()
  foreach ($Scene in $Scenes) {
    $Rows.Add("| $Scene | webgl2 | baseline-content-shell | 60 | 0 | 0 | 0 |") | Out-Null
    $Rows.Add("| $Scene | webgl2 | fork-viewer-default | 60 | 0 | 0 | 0 |") | Out-Null
  }

  @"
# Benchmark Comparison

Generated from synthetic official trace audit fixtures.

Strict official input validation was enabled: synthetic.

| Scene | Renderer | Variant | Avg FPS | Dropped Delta | JS heap Delta | GPU memory Delta |
| --- | --- | --- | ---: | ---: | ---: | ---: |
$($Rows -join "`n")
"@
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

function New-TraceSidecar {
  param(
    [string]$PathValue,
    [string]$Scene = "many-draw-calls",
    [string]$Renderer = "webgl2",
    [int]$Duration = 10,
    [int]$Warmup = 2,
    [int]$StartDelayMs = 2000,
    [string]$Browser = "baseline.exe",
    [bool]$ViewerMode = $false,
    [bool]$ViewerTrustedContent = $false,
    [bool]$ViewerBlockExternalNavigation = $false
  )
  [pscustomobject]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    platform = "test-platform"
    browser = $Browser
    scene = $Scene
    renderer = $Renderer
    duration_seconds = $Duration
    warmup_seconds = $Warmup
    start_delay_ms = $StartDelayMs
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
      scene_name = $Scene
      renderer_type = $Renderer
      measured_seconds = $Duration
      warmup_seconds = $Warmup
      avg_fps = 60
      startup_ms_to_first_frame = 123
    }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PathValue -Encoding UTF8
}

function New-TraceFile {
  param([string]$PathValue)
  [pscustomobject]@{
    traceEvents = @(
      [pscustomobject]@{ name = "RunTask"; ph = "X"; ts = 1; dur = 1000; pid = 1; tid = 1 },
      [pscustomobject]@{ name = "SubmitCompositorFrame"; ph = "X"; ts = 2; dur = 500; pid = 1; tid = 2 }
    )
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PathValue -Encoding UTF8
}

function New-BenchmarkResult {
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

function Write-BenchmarkResultSuite {
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
    Write-Json $Paths[$Index] (New-BenchmarkResult `
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

function Invoke-AuditAndReadChecklist {
  $OldSkipPackage = $env:THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST
  $OldSkipArtifactPath = $env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST
  $OldSkipWebGpu = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST
  $OldSkipTrustedProvenance = $env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST
  $OldSkipAggressive = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST
  $OldSkipProvenance = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST
  $OldSkipRuntime = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST
  $OldSkipTrace = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST
  $OldSkipReport = $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST
  $OldAllowManifestOverrides = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES
  $OldOfficialManifestPath = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
  $env:THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST = "1"
  $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST = "1"
  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $ManifestPath
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $TempOutput -ManifestAuditOnly *>&1
  } finally {
    if ($null -eq $OldSkipPackage) {
      Remove-Item Env:\THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST = $OldSkipPackage
    }
    if ($null -eq $OldSkipArtifactPath) {
      Remove-Item Env:\THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST = $OldSkipArtifactPath
    }
    if ($null -eq $OldSkipWebGpu) {
      Remove-Item Env:\THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST = $OldSkipWebGpu
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
    if ($null -eq $OldSkipTrace) {
      Remove-Item Env:\THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST = $OldSkipTrace
    }
    if ($null -eq $OldSkipReport) {
      Remove-Item Env:\THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST -ErrorAction SilentlyContinue
    } else {
      $env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST = $OldSkipReport
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
  return Get-Content -LiteralPath $TempOutput -Raw
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
  $RuntimeSmoke = @(
    (Join-Path $TempDir "baseline-content-shell-runtime-smoke.json"),
    (Join-Path $TempDir "fork-viewer-default-runtime-smoke.json")
  )
  $NavigationLock = @(
    (Join-Path $TempDir "fork-viewer-default-navigation-lock.json"),
    (Join-Path $TempDir "fork-viewer-default-file-navigation-lock.json")
  )
  Write-ValidSmokeFiles -RuntimeSmoke $RuntimeSmoke -NavigationLock $NavigationLock
  $BaselineTraceSidecar = Join-Path $TempDir "baseline-trace.result.json"
  $ForkTraceSidecar = Join-Path $TempDir "fork-trace.result.json"
  $BaselineTrace = Join-Path $TempDir "baseline-trace.json"
  $ForkTrace = Join-Path $TempDir "fork-trace.json"
  New-TraceFile $BaselineTrace
  New-TraceFile $ForkTrace

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
    build_args = [pscustomobject]@{
      baseline = "baseline-args.gn"
      fork = "fork-args.gn"
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
      capture_trace = $true
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
      expected_baseline_build_args_hash = "0123456789abcdef"
      expected_fork_build_args_hash = "0123456789abcdef"
      forbid_smoke = $true
      reject_software_rendering = $true
      require_gpu_metadata = $true
      require_frame_times = $true
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
        baseline_webgpu = @()
        fork_default_webgpu = @()
        aggressive_webgpu = @()
      }
    }
    report_files = [pscustomobject]@{
      official_webgl2_comparison = "official-webgl2-comparison.md"
      official_webgpu_comparison = $null
      baseline_trace_summary = "baseline-trace-summary.md"
      fork_trace_summary = "fork-trace-summary.md"
    }
    result_files = [pscustomobject]@{
      baseline_webgl2 = $BaselineWebGl
      fork_default_webgl2 = $ForkWebGl
      aggressive_webgl2 = @()
      baseline_webgpu = @()
      fork_default_webgpu = @()
      runtime_smoke = $RuntimeSmoke
      navigation_lock = $NavigationLock
    }
    trace_result_files = [pscustomobject]@{
      baseline = $BaselineTraceSidecar
      fork = $ForkTraceSidecar
    }
    trace_files = [pscustomobject]@{
      baseline = $BaselineTrace
      fork = $ForkTrace
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        baseline_browser = New-FileMetadata "baseline.exe"
        fork_browser = New-FileMetadata "fork.exe"
        baseline_build_args = New-FileMetadata "baseline-args.gn"
        fork_build_args = New-FileMetadata "fork-args.gn"
        viewer_patch = New-FileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
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
        official_webgl2_comparison = New-FileMetadata "official-webgl2-comparison.md"
        official_webgpu_comparison = New-MissingMetadata "official-webgpu-comparison.md"
        baseline_trace_summary = New-FileMetadata "baseline-trace-summary.md"
        fork_trace_summary = New-FileMetadata "fork-trace-summary.md"
      }
      traces = [pscustomobject]@{
        baseline = New-FileMetadata $BaselineTrace
        fork = New-FileMetadata $ForkTrace
        baseline_result = New-MissingMetadata "baseline-trace.result.json"
        fork_result = New-MissingMetadata "fork-trace.result.json"
      }
    }
  }

  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*pending.*trace benchmark sidecar hashes") {
    throw "Artifact audit accepted or misreported a completed official manifest without trace benchmark sidecar hashes."
  }

  Set-Content -LiteralPath $BaselineTrace -Value "{ not json" -Encoding UTF8
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*pending.*raw trace validation failed") {
    throw "Artifact audit accepted or misreported a completed official manifest with an invalid raw trace file."
  }
  New-TraceFile $BaselineTrace

  New-TraceSidecar $BaselineTraceSidecar -StartDelayMs 0
  New-TraceSidecar $ForkTraceSidecar -Browser "fork.exe" -ViewerMode $true -ViewerTrustedContent $true -ViewerBlockExternalNavigation $true
  $Manifest.artifact_metadata.traces.baseline_result = New-FileMetadata $BaselineTraceSidecar
  $Manifest.artifact_metadata.traces.fork_result = New-FileMetadata $ForkTraceSidecar
  $Manifest.artifact_metadata.reports.baseline_trace_summary = New-FileMetadata "baseline-trace-summary.md"
  $Manifest.artifact_metadata.reports.fork_trace_summary = New-FileMetadata "fork-trace-summary.md"
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*pending.*trace benchmark sidecar validation failed") {
    throw "Artifact audit accepted or misreported a completed official manifest with mismatched trace benchmark sidecar metadata."
  }

  New-TraceSidecar $BaselineTraceSidecar
  New-TraceSidecar $ForkTraceSidecar -Browser "fork.exe" -ViewerMode $true -ViewerTrustedContent $true -ViewerBlockExternalNavigation $true
  $Manifest.artifact_metadata.traces.baseline_result = New-FileMetadata $BaselineTraceSidecar
  $Manifest.artifact_metadata.traces.fork_result = New-FileMetadata $ForkTraceSidecar
  $Manifest.artifact_metadata.reports.baseline_trace_summary = New-MissingMetadata "baseline-trace-summary.md"
  $Manifest.artifact_metadata.reports.fork_trace_summary = New-MissingMetadata "fork-trace-summary.md"
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*pending.*trace summary report hashes") {
    throw "Artifact audit accepted or misreported a completed official manifest without trace summary hashes."
  }

  $ActualBaselineBrowser = Write-ArtifactFile (Join-Path $TempDir "actual-baseline.exe") "baseline browser"
  $ActualForkBrowser = Write-ArtifactFile (Join-Path $TempDir "actual-fork.exe") "fork browser"
  $ActualBaselineArgs = Write-ArtifactFile (Join-Path $TempDir "actual-baseline-args.gn") "is_debug=false"
  $ActualForkArgs = Write-ArtifactFile (Join-Path $TempDir "actual-fork-args.gn") "is_debug=false"
  $ActualBaselineArgsHash = Get-Sha256 $ActualBaselineArgs
  $ActualForkArgsHash = Get-Sha256 $ActualForkArgs
  $ActualOfficialReport = Write-ArtifactFile (Join-Path $TempDir "official-webgl2-comparison.md") (New-OfficialComparisonReportContent)
  $ActualBaselineTraceSummary = Write-ArtifactFile (Join-Path $TempDir "baseline-trace-summary.md") (New-TraceSummaryReportContent -TracePath $BaselineTrace)
  $ActualForkTraceSummary = Write-ArtifactFile (Join-Path $TempDir "fork-trace-summary.md") (New-TraceSummaryReportContent -TracePath $ForkTrace)
  $ActualBaselineWebGl = @($RequiredScenes | ForEach-Object { Join-Path $TempDir "baseline-content-shell-$_-webgl2.json" })
  $ActualForkWebGl = @($RequiredScenes | ForEach-Object { Join-Path $TempDir "fork-viewer-default-$_-webgl2.json" })
  $ActualRuntimeSmoke = @(
    (Join-Path $TempDir "baseline-content-shell-runtime-smoke.json"),
    (Join-Path $TempDir "fork-viewer-default-runtime-smoke.json")
  )
  $ActualNavigationLock = @(
    (Join-Path $TempDir "actual-fork-viewer-default-navigation-lock.json"),
    (Join-Path $TempDir "actual-fork-viewer-default-file-navigation-lock.json")
  )

  Write-BenchmarkResultSuite `
    -Paths $ActualBaselineWebGl `
    -Variant "baseline-content-shell" `
    -ChromiumRevision $ChromiumRevision `
    -ForkRevision $null `
    -BuildArgsHash $ActualBaselineArgsHash `
    -BrowserExecutable $ActualBaselineBrowser `
    -ViewerMode $false `
    -ViewerBlockExternalNavigation $false `
    -ViewerTrustedContent $false
  Write-BenchmarkResultSuite `
    -Paths $ActualForkWebGl `
    -Variant "fork-viewer-default" `
    -ChromiumRevision $ChromiumRevision `
    -ForkRevision $ForkRevision `
    -BuildArgsHash $ActualForkArgsHash `
    -BrowserExecutable $ActualForkBrowser `
    -ViewerMode $true `
    -ViewerBlockExternalNavigation $true `
    -ViewerTrustedContent $true
  Write-ValidSmokeFiles `
    -RuntimeSmoke $ActualRuntimeSmoke `
    -NavigationLock $ActualNavigationLock `
    -BaselineBrowser $ActualBaselineBrowser `
    -ForkBrowser $ActualForkBrowser
  New-TraceSidecar $BaselineTraceSidecar -Browser $ActualBaselineBrowser
  New-TraceSidecar $ForkTraceSidecar -Browser $ActualForkBrowser -ViewerMode $true -ViewerTrustedContent $true -ViewerBlockExternalNavigation $true

  $Manifest.browsers.baseline = $ActualBaselineBrowser
  $Manifest.browsers.fork = $ActualForkBrowser
  $Manifest.suite_validation.expected_baseline_browser = $ActualBaselineBrowser
  $Manifest.suite_validation.expected_fork_browser = $ActualForkBrowser
  $Manifest.build_args.baseline = $ActualBaselineArgs
  $Manifest.build_args.fork = $ActualForkArgs
  $Manifest.suite_validation.expected_baseline_build_args_hash = $ActualBaselineArgsHash
  $Manifest.suite_validation.expected_fork_build_args_hash = $ActualForkArgsHash
  $Manifest.result_files.baseline_webgl2 = $ActualBaselineWebGl
  $Manifest.result_files.fork_default_webgl2 = $ActualForkWebGl
  $Manifest.result_files.runtime_smoke = $ActualRuntimeSmoke
  $Manifest.result_files.navigation_lock = $ActualNavigationLock
  $Manifest.report_files.official_webgl2_comparison = $ActualOfficialReport
  $Manifest.report_files.baseline_trace_summary = $ActualBaselineTraceSummary
  $Manifest.report_files.fork_trace_summary = $ActualForkTraceSummary
  $Manifest.artifact_metadata.inputs.baseline_browser = New-FileMetadata $ActualBaselineBrowser
  $Manifest.artifact_metadata.inputs.fork_browser = New-FileMetadata $ActualForkBrowser
  $Manifest.artifact_metadata.inputs.baseline_build_args = New-FileMetadata $ActualBaselineArgs
  $Manifest.artifact_metadata.inputs.fork_build_args = New-FileMetadata $ActualForkArgs
  $Manifest.artifact_metadata.inputs.viewer_patch = New-FileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
  $Manifest.artifact_metadata.results.baseline_webgl2 = New-MetadataList $ActualBaselineWebGl
  $Manifest.artifact_metadata.results.fork_default_webgl2 = New-MetadataList $ActualForkWebGl
  $Manifest.artifact_metadata.runtime_tests.smoke = New-MetadataList $ActualRuntimeSmoke
  $Manifest.artifact_metadata.runtime_tests.navigation_lock = New-MetadataList $ActualNavigationLock
  $Manifest.artifact_metadata.reports.official_webgl2_comparison = New-FileMetadata $ActualOfficialReport
  $Manifest.artifact_metadata.reports.baseline_trace_summary = New-FileMetadata $ActualBaselineTraceSummary
  $Manifest.artifact_metadata.reports.fork_trace_summary = New-FileMetadata $ActualForkTraceSummary
  $Manifest.artifact_metadata.traces.baseline = New-FileMetadata $BaselineTrace
  $Manifest.artifact_metadata.traces.fork = New-FileMetadata $ForkTrace
  $Manifest.artifact_metadata.traces.baseline_result = New-FileMetadata $BaselineTraceSidecar
  $Manifest.artifact_metadata.traces.fork_result = New-FileMetadata $ForkTraceSidecar
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*done.*trace-summary content validation") {
    throw "Artifact audit did not accept a completed official trace manifest with valid trace summary content. Checklist: $Checklist"
  }

  $null = Write-ArtifactFile $ActualBaselineTraceSummary "not a trace summary"
  $Manifest.artifact_metadata.reports.baseline_trace_summary = New-FileMetadata $ActualBaselineTraceSummary
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*pending.*report content validation failed" -or
      $Checklist -notmatch "baseline_trace_summary missing trace summary heading") {
    throw "Artifact audit accepted or misreported a completed official manifest whose hashed trace summary content is invalid. Checklist: $Checklist"
  }
} finally {
  if ($HadManifest) {
    Copy-Item -LiteralPath $BackupPath -Destination $ManifestPath -Force
  } elseif (Test-Path -LiteralPath $ManifestPath) {
    Remove-Item -LiteralPath $ManifestPath -Force
  }
  foreach ($PathValue in @($BackupPath, $TempOutput, $BaselineTrace, $ForkTrace, $BaselineTraceSidecar, $ForkTraceSidecar)) {
    if (Test-Path -LiteralPath $PathValue) {
      Remove-Item -LiteralPath $PathValue -Force
    }
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Official manifest audit rejects completed trace manifests with invalid raw traces, missing/mismatched/unhashed trace benchmark sidecars including browser and launch flag metadata, missing summary hashes, or invalid trace summary content."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$TempDir = Join-Path $Root "benchmarks\tmp\official-manifest-report-audit"
$ManifestPath = Join-Path $TempDir "official-comparison-manifest.json"
$BackupPath = Join-Path $TempDir "official-comparison-manifest.report-audit.backup.json"
$TempOutput = Join-Path $TempDir "official-manifest-report-audit.md"
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
    [string[]]$NavigationLock
  )

  foreach ($PathValue in @($RuntimeSmoke + $NavigationLock)) {
    New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  }

  $BaselineRuntime = [pscustomobject]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    platform = "synthetic"
    browser_executable = "baseline.exe"
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
      [pscustomobject]@{ name = "webgpu_adapter_device"; status = "pass"; details = [pscustomobject]@{ features = @("timestamp-query"); max_texture_dimension_2d = 8192 } },
      [pscustomobject]@{ name = "webgpu_device_loss_signal"; status = "pass"; details = [pscustomobject]@{ reason = "destroyed"; message = "synthetic" } },
      [pscustomobject]@{ name = "three_webgpu_render"; status = "pass"; details = [pscustomobject]@{ is_webgpu_renderer = $true; backend = "WebGPUBackend"; render_ms = 1; canvas_width = 64; canvas_height = 64 } },
      [pscustomobject]@{ name = "three_cube_render"; status = "pass" },
      [pscustomobject]@{ name = "texture_load"; status = "pass" },
      [pscustomobject]@{ name = "shader_material"; status = "pass" },
      [pscustomobject]@{ name = "benchmark_run"; status = "pass"; details = [pscustomobject]@{ scene_name = "many-draw-calls"; renderer_type = "webgl2"; avg_fps = 60; frame_count = 60; startup_ms_to_first_frame = 10 } }
    )
  }
  $ForkRuntime = $BaselineRuntime | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $ForkRuntime.browser_executable = "fork.exe"
  $ForkRuntime.viewer_mode = $true
  $ForkRuntime.viewer_trusted_content = $true
  $ForkRuntime.viewer_app_url = "http://127.0.0.1:1111/__smoke.html"
  Write-Json $RuntimeSmoke[0] $BaselineRuntime
  Write-Json $RuntimeSmoke[1] $ForkRuntime

  $NavigationSmoke = [pscustomobject]@{
    generated_at = "2026-05-16T00:00:00.000Z"
    platform = "synthetic"
    browser_executable = "fork.exe"
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
    browser_executable = "fork.exe"
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

function New-OfficialManifest {
  param(
    [bool]$IncludeWebGPU,
    [string]$MissingReport
  )

  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $ForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ChromiumRevision -Root $Root
  $BaselineWebGl = New-ResultFiles "baseline-content-shell" "webgl2"
  $ForkWebGl = New-ResultFiles "fork-viewer-default" "webgl2"
  $BaselineWebGpu = if ($IncludeWebGPU) { New-ResultFiles "baseline-content-shell-webgpu" "webgpu" } else { @() }
  $ForkWebGpu = if ($IncludeWebGPU) { New-ResultFiles "fork-viewer-default-webgpu" "webgpu" } else { @() }
  $RuntimeSmoke = @(
    (Join-Path $TempDir "baseline-content-shell-runtime-smoke.json"),
    (Join-Path $TempDir "fork-viewer-default-runtime-smoke.json")
  )
  $NavigationLock = @(
    (Join-Path $TempDir "fork-viewer-default-navigation-lock.json"),
    (Join-Path $TempDir "fork-viewer-default-file-navigation-lock.json")
  )
  Write-ValidSmokeFiles -RuntimeSmoke $RuntimeSmoke -NavigationLock $NavigationLock

  [pscustomobject]@{
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
      include_webgpu = $IncludeWebGPU
      include_aggressive_gpu = $false
      capture_trace = $false
      skip_smoke = $false
      skip_navigation_lock = $false
    }
    suite_validation = [pscustomobject]@{
      require_checkout = $true
      require_build_args = $true
      expected_baseline_build_args_hash = "0123456789abcdef"
      expected_fork_build_args_hash = "0123456789abcdef"
      forbid_smoke = $true
      reject_software_rendering = $true
      reject_gpu_instability = $true
      require_gpu_metadata = $true
      require_frame_times = $true
      require_webgpu_runtime_smoke = [bool]$IncludeWebGPU
      expected_measured_seconds = 120
      expected_warmup_seconds = 20
      expected_chromium_revision = $ChromiumRevision
      expected_baseline_browser = "baseline.exe"
      expected_fork_browser = "fork.exe"
      require_fork_revision_for_fork_suites = $true
      expected_fork_revision = $ForkRevision
      exact_scene_output_files = $true
      expected_flag_metadata = [pscustomobject]@{
        baseline = @("viewer_mode=false", "resource_warmup_enabled=false", "resource_warmup_precompile=false", "resource_warmup_prerender_frames=0")
        fork_default = @("viewer_mode=true", "resource_warmup_enabled=false", "resource_warmup_precompile=false", "resource_warmup_prerender_frames=0")
        aggressive = @()
        baseline_webgpu = if ($IncludeWebGPU) { @("viewer_mode=false", "resource_warmup_enabled=false", "resource_warmup_precompile=false", "resource_warmup_prerender_frames=0") } else { @() }
        fork_default_webgpu = if ($IncludeWebGPU) { @("viewer_mode=true", "resource_warmup_enabled=false", "resource_warmup_precompile=false", "resource_warmup_prerender_frames=0") } else { @() }
        aggressive_webgpu = @()
      }
    }
    result_files = [pscustomobject]@{
      baseline_webgl2 = $BaselineWebGl
      fork_default_webgl2 = $ForkWebGl
      aggressive_webgl2 = @()
      baseline_webgpu = $BaselineWebGpu
      fork_default_webgpu = $ForkWebGpu
      runtime_smoke = $RuntimeSmoke
      navigation_lock = $NavigationLock
    }
    report_files = [pscustomobject]@{
      baseline_webgl2_summary = "baseline-content-shell-webgl2-summary.md"
      fork_default_webgl2_summary = "fork-viewer-default-webgl2-summary.md"
      official_webgl2_comparison = "official-webgl2-comparison.md"
      official_webgpu_comparison = if ($IncludeWebGPU) { "official-webgpu-comparison.md" } else { $null }
      baseline_trace_summary = $null
      fork_trace_summary = $null
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
        baseline_webgpu = New-MetadataList $BaselineWebGpu
        fork_default_webgpu = New-MetadataList $ForkWebGpu
      }
      runtime_tests = [pscustomobject]@{
        smoke = New-MetadataList $RuntimeSmoke
        navigation_lock = New-MetadataList $NavigationLock
      }
      reports = [pscustomobject]@{
        baseline_webgl2_summary = New-FileMetadata "baseline-content-shell-webgl2-summary.md"
        fork_default_webgl2_summary = New-FileMetadata "fork-viewer-default-webgl2-summary.md"
        official_webgl2_comparison = if ($MissingReport -eq "webgl2") { New-MissingFileMetadata "official-webgl2-comparison.md" } else { New-FileMetadata "official-webgl2-comparison.md" }
        official_webgpu_comparison = if ($MissingReport -eq "webgpu") { New-MissingFileMetadata "official-webgpu-comparison.md" } else { New-FileMetadata "official-webgpu-comparison.md" }
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
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST",
    "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST",
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
  $Manifest = New-OfficialManifest -IncludeWebGPU $false -MissingReport "webgl2"
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*pending.*official WebGL2 comparison report hash") {
    throw "Artifact audit accepted or misreported a completed official manifest without the WebGL2 comparison report hash."
  }

  $Manifest = New-OfficialManifest -IncludeWebGPU $true -MissingReport "webgpu"
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  $Checklist = Invoke-AuditAndReadChecklist
  if ($Checklist -notmatch "Official comparison manifest.*pending.*official WebGPU comparison report hash") {
    throw "Artifact audit accepted or misreported a completed official manifest without the WebGPU comparison report hash."
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

Write-Host "Official manifest audit rejects completed manifests without official comparison report hashes."

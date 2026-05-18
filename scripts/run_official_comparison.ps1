[CmdletBinding()]
param(
  [string]$BaselineBrowser = ".\src\out\ReleaseBaseline\content_shell.exe",
  [string]$ForkBrowser = ".\src\out\ReleaseViewerDefault\content_shell.exe",
  [string]$BaselineBuildArgs = ".\src\out\ReleaseBaseline\args.gn",
  [string]$ForkBuildArgs = ".\src\out\ReleaseViewerDefault\args.gn",
  [string]$BaselinePackageDir = "",
  [string]$ForkPackageDir = "",
  [int]$Duration = 120,
  [int]$Warmup = 20,
  [switch]$IncludeWebGPU,
  [switch]$IncludeAggressiveGpu,
  [string]$AggressiveAngleBackend = "",
  [switch]$CaptureTrace,
  [string]$TraceScene = "many-draw-calls",
  [string]$TraceRenderer = "webgl2",
  [int]$TraceDuration = 10,
  [int]$TraceWarmup = 2,
  [int]$TraceStartDelayMs = 2000,
  [switch]$Precompile,
  [int]$PrerenderFrames = 0,
  [switch]$SkipSmoke,
  [switch]$SkipNavigationLock,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Resolve-RepoPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return (Join-Path $Root $PathValue)
}

function Require-File {
  param(
    [string]$PathValue,
    [string]$Label
  )
  $Resolved = Resolve-RepoPath $PathValue
  if ($DryRun) {
    return $Resolved
  }

  if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
    throw "$Label not found: $Resolved"
  }
  $Item = Get-Item -LiteralPath $Resolved
  if ($Item.Length -le 0) {
    throw "$Label is empty: $Resolved"
  }
  return $Resolved
}

function Require-PackageDirectory {
  param(
    [string]$PathValue,
    [string]$Label,
    [string]$ExpectedBrowser = ""
  )

  $Resolved = Resolve-RepoPath $PathValue
  if ($DryRun) {
    return $Resolved
  }

  if (-not (Test-Path -LiteralPath $Resolved -PathType Container)) {
    throw "$Label not found: $Resolved"
  }

  foreach ($RequiredRelativePath in @("content_shell.exe", "viewer\index.html", "run_viewer.ps1")) {
    $RequiredPath = Join-Path $Resolved $RequiredRelativePath
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
      throw "$Label is incomplete; missing $RequiredRelativePath under $Resolved"
    }
  }

  $Files = @(Get-ChildItem -LiteralPath $Resolved -Recurse -File -ErrorAction SilentlyContinue)
  $SizeBytes = ($Files | Measure-Object -Property Length -Sum).Sum
  if ($Files.Count -eq 0 -or $SizeBytes -le 0) {
    throw "$Label is empty: $Resolved"
  }

  if ($ExpectedBrowser) {
    $PackagedBrowser = Join-Path $Resolved "content_shell.exe"
    $ExpectedBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ExpectedBrowser).Hash
    $PackagedBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PackagedBrowser).Hash
    if ($PackagedBrowserHash -ne $ExpectedBrowserHash) {
      throw "$Label executable does not match expected browser: $PackagedBrowser"
    }
  }

  return $Resolved
}

function Run-Command {
  param([object[]]$Command)
  if ($DryRun) {
    Write-Host "[dry-run] $($Command -join ' ')"
    return
  }
  $CommandArgs = @($Command | Select-Object -Skip 1)
  $Executable = [string]$Command[0]
  if ([System.IO.Path]::GetExtension($Executable) -ieq ".ps1") {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Executable @CommandArgs
  } else {
    & $Executable @CommandArgs
  }
  if ($LASTEXITCODE -ne 0) {
    throw "$($Command[0]) exited with code $LASTEXITCODE"
  }
}

function Add-ResourceWarmupArgs {
  param([object[]]$Command)
  $Result = @($Command)
  if ($Precompile) {
    $Result += "-Precompile"
  }
  if ($PrerenderFrames -gt 0) {
    $Result += @("-PrerenderFrames", [string]$PrerenderFrames)
  }
  return $Result
}

function Add-TraceResourceWarmupArgs {
  param([object[]]$Command)
  $Result = @($Command)
  if ($Precompile) {
    $Result += "--precompile"
  }
  if ($PrerenderFrames -gt 0) {
    $Result += @("--prerenderFrames", [string]$PrerenderFrames)
  }
  return $Result
}

function Get-GitRevision {
  param([string]$RepoPath)
  if (-not (Test-Path $RepoPath)) {
    throw "Git repository path not found: $RepoPath"
  }
  $Revision = (& git -C $RepoPath rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $Revision) {
    throw "Unable to read git revision from $RepoPath"
  }
  return $Revision
}

function Get-ShortSha256 {
  param([string]$PathValue)
  if (-not (Test-Path $PathValue)) {
    throw "File not found for hash: $PathValue"
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.Substring(0, 12).ToLowerInvariant()
}

function Get-ViewerForkRevision {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
  $PatchHash = Get-ShortSha256 $PatchPath
  return "$ChromiumRevision+viewerpatch-$PatchHash"
}

function Invoke-BenchmarkSuiteValidation {
  param(
    [string]$Renderer,
    [string]$Variant,
    [string[]]$Files,
    [switch]$RequireForkRevision,
    [switch]$RequirePackageSize,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [string]$ExpectedForkRevision = "",
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @()
  )

  $Command = @(
    "node",
    (Join-Path $Root "scripts\validate_benchmark_suite.mjs"),
    "--renderer", $Renderer,
    "--variant", $Variant,
    "--expectedScenes", ($SceneNames -join ","),
    "--requireCheckout",
    "--requireBuildArgs",
    "--forbidSmoke",
    "--rejectSoftwareRendering",
    "--requireGpuMetadata",
    "--expectedMeasuredSeconds", [string]$Duration,
    "--expectedWarmupSeconds", [string]$Warmup
  )
  if ($ExpectedChromiumRevision) {
    $Command += @("--expectedChromiumRevision", $ExpectedChromiumRevision)
  }
  if ($ExpectedBrowser) {
    $Command += @("--expectedBrowser", $ExpectedBrowser)
  }
  if ($RequireForkRevision) {
    $Command += "--requireForkRevision"
  }
  if ($RequirePackageSize) {
    $Command += "--requirePackageSize"
  }
  if ($ExpectedForkRevision) {
    $Command += @("--expectedForkRevision", $ExpectedForkRevision)
  }
  foreach ($Metadata in $ExpectedFlagMetadata) {
    $Command += @("--expectedFlagMetadata", $Metadata)
  }
  foreach ($Flag in $RequiredBrowserFlags) {
    $Command += @("--requiredBrowserFlag", $Flag)
  }
  $Command += $Files
  Run-Command $Command
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

function Get-ViewerFlagMetadata {
  param(
    [bool]$ViewerMode = $false,
    [bool]$ViewerTrustedContent = $false,
    [bool]$ViewerAggressiveGpu = $false,
    [string]$ViewerForceAngleBackend = ""
  )

  $Metadata = [ordered]@{
    viewer_mode = $ViewerMode
    viewer_block_external_navigation = $ViewerMode
    viewer_trusted_content = $ViewerTrustedContent
    viewer_aggressive_gpu = $ViewerAggressiveGpu
    viewer_relaxed_webgl_validation = $false
    viewer_in_process_gpu = $false
    viewer_single_process = $false
    viewer_force_angle_backend = if ($ViewerForceAngleBackend) { $ViewerForceAngleBackend } else { $null }
    requested_angle_backend = if ($ViewerForceAngleBackend) { $ViewerForceAngleBackend } else { $null }
    viewer_disable_unneeded_blink_features = $false
    viewer_direct_gpu_presentation = $false
  }

  return @($Metadata.GetEnumerator() | ForEach-Object {
    "$($_.Key)=$(Convert-MetadataValue $_.Value)"
  })
}

function Get-TraceFlagMetadata {
  param(
    [bool]$ViewerMode = $false,
    [bool]$ViewerTrustedContent = $false,
    [bool]$ViewerAggressiveGpu = $false,
    [string]$ViewerForceAngleBackend = ""
  )

  return @(Get-ViewerFlagMetadata `
    -ViewerMode $ViewerMode `
    -ViewerTrustedContent $ViewerTrustedContent `
    -ViewerAggressiveGpu $ViewerAggressiveGpu `
    -ViewerForceAngleBackend $ViewerForceAngleBackend)
}

function Get-TraceResultPath {
  param([string]$TracePath)
  return [System.IO.Path]::ChangeExtension($TracePath, ".result.json")
}

function Invoke-TraceArtifactValidation {
  param(
    [string]$TracePath,
    [string]$ExpectedBrowser,
    [string[]]$ExpectedFlagMetadata,
    [string[]]$RequiredBrowserFlags = @()
  )

  Run-Command @(
    "node",
    (Join-Path $Root "scripts\validate_trace_file.mjs"),
    "--minEvents", "1",
    $TracePath
  )

  $TraceResultPath = Get-TraceResultPath $TracePath
  $Command = @(
    "node",
    (Join-Path $Root "scripts\validate_trace_result.mjs"),
    "--expectedBrowser", $ExpectedBrowser,
    "--expectedScene", $TraceScene,
    "--expectedRenderer", $TraceRenderer,
    "--expectedDuration", [string]$TraceDuration,
    "--expectedWarmup", [string]$TraceWarmup,
    "--expectedStartDelayMs", [string]$TraceStartDelayMs
  )
  foreach ($Metadata in $ExpectedFlagMetadata) {
    $Command += @("--expectedFlagMetadata", $Metadata)
  }
  foreach ($Flag in $RequiredBrowserFlags) {
    $Command += @("--requiredBrowserFlag", $Flag)
  }
  $Command += $TraceResultPath
  Run-Command $Command
}

function Get-SuiteResultFiles {
  param(
    [string]$Label,
    [string]$Renderer
  )

  return @($SceneNames | ForEach-Object {
    Join-Path $RawDir "$Label-$_-$Renderer.json"
  })
}

function Get-FileMetadata {
  param([string]$PathValue)
  if (-not $PathValue) {
    return [pscustomobject]@{
      path = $null
      exists = $false
      size_bytes = $null
      sha256 = $null
    }
  }

  $Resolved = Resolve-RepoPath $PathValue
  $Exists = Test-Path -LiteralPath $Resolved -PathType Leaf
  return [pscustomobject]@{
    path = $Resolved
    exists = $Exists
    size_bytes = if ($Exists) { (Get-Item -LiteralPath $Resolved).Length } else { $null }
    sha256 = if ($Exists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Resolved).Hash.ToLowerInvariant() } else { $null }
  }
}

function Get-FileMetadataList {
  param([string[]]$Paths)
  return @($Paths | ForEach-Object { Get-FileMetadata $_ })
}

function Get-DirectoryMetadata {
  param([string]$PathValue)
  if (-not $PathValue) {
    return [pscustomobject]@{
      path = $null
      exists = $false
      file_count = $null
      size_bytes = $null
    }
  }

  $Resolved = Resolve-RepoPath $PathValue
  $Exists = Test-Path -LiteralPath $Resolved -PathType Container
  $Files = if ($Exists) { @(Get-ChildItem -LiteralPath $Resolved -Recurse -File -ErrorAction SilentlyContinue) } else { @() }
  $Size = if ($Exists) {
    ($Files | Measure-Object -Property Length -Sum).Sum
  } else {
    $null
  }
  return [pscustomobject]@{
    path = $Resolved
    exists = $Exists
    file_count = if ($Exists) { $Files.Count } else { $null }
    size_bytes = $Size
  }
}

function Write-OfficialComparisonManifest {
  param([string]$Phase = "planned")

  $ManifestName = if ($DryRun) {
    "official-comparison-manifest.dry-run.json"
  } else {
    "official-comparison-manifest.json"
  }
  $ManifestPath = Join-Path $ReportDir $ManifestName

  $Manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = [bool]$DryRun
    phase = $Phase
    chromium_revision = Get-GitRevision (Join-Path $Root "src")
    fork_revision = $ViewerForkRevision
    browsers = [pscustomobject]@{
      baseline = $BaselineBrowser
      fork = $ForkBrowser
    }
    build_args = [pscustomobject]@{
      baseline = $BaselineBuildArgs
      fork = $ForkBuildArgs
    }
    package_dirs = [pscustomobject]@{
      baseline = $BaselinePackageDir
      fork = $ForkPackageDir
    }
    options = [pscustomobject]@{
      duration = $Duration
      warmup = $Warmup
      include_webgpu = [bool]$IncludeWebGPU
      include_aggressive_gpu = [bool]$IncludeAggressiveGpu
      aggressive_angle_backend = $AggressiveAngleBackend
      capture_trace = [bool]$CaptureTrace
      trace_scene = $TraceScene
      trace_renderer = $TraceRenderer
      trace_duration = $TraceDuration
      trace_warmup = $TraceWarmup
      trace_start_delay_ms = $TraceStartDelayMs
      precompile = [bool]$Precompile
      prerender_frames = $PrerenderFrames
      skip_smoke = [bool]$SkipSmoke
      skip_navigation_lock = [bool]$SkipNavigationLock
    }
    labels = [pscustomobject]@{
      baseline = $BaselineLabel
      fork_default = $ForkDefaultLabel
      aggressive = $AggressiveLabel
    }
    scenes = $SceneNames
    result_files = [pscustomobject]@{
      baseline_webgl2 = $BaselineWebGlFiles
      fork_default_webgl2 = $ForkWebGlFiles
      aggressive_webgl2 = if ($IncludeAggressiveGpu) { $AggressiveWebGlFiles } else { @() }
      baseline_webgpu = if ($IncludeWebGPU) { $BaselineWebGpuFiles } else { @() }
      fork_default_webgpu = if ($IncludeWebGPU) { $ForkWebGpuFiles } else { @() }
      aggressive_webgpu = if ($IncludeWebGPU -and $IncludeAggressiveGpu) { $AggressiveWebGpuFiles } else { @() }
      runtime_smoke = if (-not $SkipSmoke) {
        @(
          (Join-Path $RawDir "$BaselineLabel-runtime-smoke.json"),
          (Join-Path $RawDir "$ForkDefaultLabel-runtime-smoke.json")
        )
      } else {
        @()
      }
      navigation_lock = if (-not $SkipNavigationLock) {
        @(
          (Join-Path $RawDir "$ForkDefaultLabel-navigation-lock.json"),
          (Join-Path $RawDir "$ForkDefaultLabel-file-navigation-lock.json")
        )
      } else {
        @()
      }
    }
    report_files = [pscustomobject]@{
      baseline_webgl2_summary = Join-Path $ReportDir "$BaselineLabel-webgl2-summary.md"
      fork_default_webgl2_summary = Join-Path $ReportDir "$ForkDefaultLabel-webgl2-summary.md"
      official_webgl2_comparison = Join-Path $ReportDir "official-webgl2-comparison.md"
      official_webgpu_comparison = if ($IncludeWebGPU) { Join-Path $ReportDir "official-webgpu-comparison.md" } else { $null }
      baseline_trace_summary = if ($CaptureTrace) { Join-Path $ReportDir "$BaselineLabel-$TraceScene-$TraceRenderer-trace-summary.md" } else { $null }
      fork_trace_summary = if ($CaptureTrace) { Join-Path $ReportDir "$ForkDefaultLabel-$TraceScene-$TraceRenderer-trace-summary.md" } else { $null }
    }
    trace_files = [pscustomobject]@{
      baseline = if ($CaptureTrace) { Join-Path $Root "benchmarks\traces\$BaselineLabel-$TraceScene-$TraceRenderer-trace.json" } else { $null }
      fork = if ($CaptureTrace) { Join-Path $Root "benchmarks\traces\$ForkDefaultLabel-$TraceScene-$TraceRenderer-trace.json" } else { $null }
    }
    trace_result_files = [pscustomobject]@{
      baseline = if ($CaptureTrace) { Join-Path $Root "benchmarks\traces\$BaselineLabel-$TraceScene-$TraceRenderer-trace.result.json" } else { $null }
      fork = if ($CaptureTrace) { Join-Path $Root "benchmarks\traces\$ForkDefaultLabel-$TraceScene-$TraceRenderer-trace.result.json" } else { $null }
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        baseline_browser = Get-FileMetadata $BaselineBrowser
        fork_browser = Get-FileMetadata $ForkBrowser
        baseline_build_args = Get-FileMetadata $BaselineBuildArgs
        fork_build_args = Get-FileMetadata $ForkBuildArgs
        viewer_patch = Get-FileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
        baseline_package = Get-DirectoryMetadata $BaselinePackageDir
        fork_package = Get-DirectoryMetadata $ForkPackageDir
      }
      results = [pscustomobject]@{
        baseline_webgl2 = Get-FileMetadataList $BaselineWebGlFiles
        fork_default_webgl2 = Get-FileMetadataList $ForkWebGlFiles
        aggressive_webgl2 = if ($IncludeAggressiveGpu) { Get-FileMetadataList $AggressiveWebGlFiles } else { @() }
        baseline_webgpu = if ($IncludeWebGPU) { Get-FileMetadataList $BaselineWebGpuFiles } else { @() }
        fork_default_webgpu = if ($IncludeWebGPU) { Get-FileMetadataList $ForkWebGpuFiles } else { @() }
        aggressive_webgpu = if ($IncludeWebGPU -and $IncludeAggressiveGpu) { Get-FileMetadataList $AggressiveWebGpuFiles } else { @() }
      }
      runtime_tests = [pscustomobject]@{
        smoke = if (-not $SkipSmoke) {
          Get-FileMetadataList @(
            (Join-Path $RawDir "$BaselineLabel-runtime-smoke.json"),
            (Join-Path $RawDir "$ForkDefaultLabel-runtime-smoke.json")
          )
        } else {
          @()
        }
        navigation_lock = if (-not $SkipNavigationLock) {
          Get-FileMetadataList @(
            (Join-Path $RawDir "$ForkDefaultLabel-navigation-lock.json"),
            (Join-Path $RawDir "$ForkDefaultLabel-file-navigation-lock.json")
          )
        } else {
          @()
        }
      }
      reports = [pscustomobject]@{
        baseline_webgl2_summary = Get-FileMetadata (Join-Path $ReportDir "$BaselineLabel-webgl2-summary.md")
        fork_default_webgl2_summary = Get-FileMetadata (Join-Path $ReportDir "$ForkDefaultLabel-webgl2-summary.md")
        official_webgl2_comparison = Get-FileMetadata (Join-Path $ReportDir "official-webgl2-comparison.md")
        official_webgpu_comparison = if ($IncludeWebGPU) { Get-FileMetadata (Join-Path $ReportDir "official-webgpu-comparison.md") } else { Get-FileMetadata "" }
        baseline_trace_summary = if ($CaptureTrace) { Get-FileMetadata (Join-Path $ReportDir "$BaselineLabel-$TraceScene-$TraceRenderer-trace-summary.md") } else { Get-FileMetadata "" }
        fork_trace_summary = if ($CaptureTrace) { Get-FileMetadata (Join-Path $ReportDir "$ForkDefaultLabel-$TraceScene-$TraceRenderer-trace-summary.md") } else { Get-FileMetadata "" }
      }
      traces = [pscustomobject]@{
        baseline = if ($CaptureTrace) { Get-FileMetadata (Join-Path $Root "benchmarks\traces\$BaselineLabel-$TraceScene-$TraceRenderer-trace.json") } else { Get-FileMetadata "" }
        fork = if ($CaptureTrace) { Get-FileMetadata (Join-Path $Root "benchmarks\traces\$ForkDefaultLabel-$TraceScene-$TraceRenderer-trace.json") } else { Get-FileMetadata "" }
        baseline_result = if ($CaptureTrace) { Get-FileMetadata (Join-Path $Root "benchmarks\traces\$BaselineLabel-$TraceScene-$TraceRenderer-trace.result.json") } else { Get-FileMetadata "" }
        fork_result = if ($CaptureTrace) { Get-FileMetadata (Join-Path $Root "benchmarks\traces\$ForkDefaultLabel-$TraceScene-$TraceRenderer-trace.result.json") } else { Get-FileMetadata "" }
      }
    }
    suite_validation = [pscustomobject]@{
      require_checkout = $true
      require_build_args = $true
      forbid_smoke = $true
      reject_software_rendering = $true
      require_gpu_metadata = $true
      require_webgpu_runtime_smoke = [bool]$IncludeWebGPU
      expected_measured_seconds = $Duration
      expected_warmup_seconds = $Warmup
      expected_chromium_revision = $ChromiumRevision
      expected_baseline_browser = $BaselineBrowser
      expected_fork_browser = $ForkBrowser
      require_fork_revision_for_fork_suites = $true
      expected_fork_revision = $ViewerForkRevision
      exact_scene_output_files = $true
      required_browser_flags = @($RequiredBrowserFlags)
      expected_flag_metadata = [pscustomobject]@{
        baseline = @(Get-ViewerFlagMetadata)
        fork_default = @(Get-ViewerFlagMetadata -ViewerMode $true -ViewerTrustedContent $true)
        aggressive = if ($IncludeAggressiveGpu) { @(Get-ViewerFlagMetadata -ViewerMode $true -ViewerTrustedContent $true -ViewerAggressiveGpu $true -ViewerForceAngleBackend $AggressiveAngleBackend) } else { @() }
        baseline_webgpu = if ($IncludeWebGPU) { @(Get-ViewerFlagMetadata) } else { @() }
        fork_default_webgpu = if ($IncludeWebGPU) { @(Get-ViewerFlagMetadata -ViewerMode $true -ViewerTrustedContent $true) } else { @() }
        aggressive_webgpu = if ($IncludeWebGPU -and $IncludeAggressiveGpu) { @(Get-ViewerFlagMetadata -ViewerMode $true -ViewerTrustedContent $true -ViewerAggressiveGpu $true -ViewerForceAngleBackend $AggressiveAngleBackend) } else { @() }
      }
    }
  }

  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  Write-Host "Wrote $ManifestPath"
}

$BaselineBrowser = Require-File $BaselineBrowser "Baseline browser"
$ForkBrowser = Require-File $ForkBrowser "Fork browser"
$BaselineBuildArgs = Require-File $BaselineBuildArgs "Baseline GN args"
$ForkBuildArgs = Require-File $ForkBuildArgs "Fork GN args"
if ($BaselinePackageDir) {
  $BaselinePackageDir = Require-PackageDirectory $BaselinePackageDir "Baseline package directory" $BaselineBrowser
}
if ($ForkPackageDir) {
  $ForkPackageDir = Require-PackageDirectory $ForkPackageDir "Fork package directory" $ForkBrowser
}

$RawDir = Join-Path $Root "benchmarks\raw"
$ReportDir = Join-Path $Root "benchmarks\reports"
New-Item -ItemType Directory -Path $RawDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$SceneNames = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

$BaselineLabel = "baseline-content-shell"
$ForkDefaultLabel = "fork-viewer-default"
$AggressiveLabel = if ($AggressiveAngleBackend) {
  "fork-viewer-aggressive-gpu-$AggressiveAngleBackend"
} else {
  "fork-viewer-aggressive-gpu"
}
$ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
$ViewerForkRevision = Get-ViewerForkRevision
Write-Host "Viewer fork revision: $ViewerForkRevision"
$RequiredBrowserFlags = @("--disable-software-rasterizer")
$BaselineWebGlFiles = Get-SuiteResultFiles -Label $BaselineLabel -Renderer "webgl2"
$ForkWebGlFiles = Get-SuiteResultFiles -Label $ForkDefaultLabel -Renderer "webgl2"
$AggressiveWebGlFiles = Get-SuiteResultFiles -Label $AggressiveLabel -Renderer "webgl2"
$BaselineWebGpuFiles = Get-SuiteResultFiles -Label "$BaselineLabel-webgpu" -Renderer "webgpu"
$ForkWebGpuFiles = Get-SuiteResultFiles -Label "$ForkDefaultLabel-webgpu" -Renderer "webgpu"
$AggressiveWebGpuFiles = Get-SuiteResultFiles -Label "$AggressiveLabel-webgpu" -Renderer "webgpu"

if (-not $SkipSmoke) {
  $BaselineSmokeFile = Join-Path $RawDir "$BaselineLabel-runtime-smoke.json"
  $ForkSmokeFile = Join-Path $RawDir "$ForkDefaultLabel-runtime-smoke.json"

  $BaselineSmokeCommand = @(
    "node",
    (Join-Path $Root "scripts\run_smoke_tests.mjs"),
    "--browser", $BaselineBrowser,
    "--output", $BaselineSmokeFile
  )
  if ($IncludeWebGPU) {
    $BaselineSmokeCommand += "--require-webgpu"
  }
  Run-Command $BaselineSmokeCommand

  $ForkSmokeCommand = @(
    "node",
    (Join-Path $Root "scripts\run_smoke_tests.mjs"),
    "--browser", $ForkBrowser,
    "--viewerMode",
    "--viewerTrustedContent",
    "--output", $ForkSmokeFile
  )
  if ($IncludeWebGPU) {
    $ForkSmokeCommand += "--require-webgpu"
  }
  Run-Command $ForkSmokeCommand

  $BaselineSmokeValidationCommand = @(
    "node",
    (Join-Path $Root "scripts\validate_smoke_result.mjs"),
    "--type", "runtime",
    "--expect-browser-mode",
    "--expected-browser", $BaselineBrowser,
    "--required-browser-flag", "--disable-software-rasterizer",
    $BaselineSmokeFile
  )
  if ($IncludeWebGPU) {
    $BaselineSmokeValidationCommand += "--require-webgpu"
  }
  Run-Command $BaselineSmokeValidationCommand

  $ForkSmokeValidationCommand = @(
    "node",
    (Join-Path $Root "scripts\validate_smoke_result.mjs"),
    "--type", "runtime",
    "--expect-viewer-mode",
    "--expect-viewer-trusted-content",
    "--expected-browser", $ForkBrowser,
    "--required-browser-flag", "--disable-software-rasterizer",
    $ForkSmokeFile
  )
  if ($IncludeWebGPU) {
    $ForkSmokeValidationCommand += "--require-webgpu"
  }
  Run-Command $ForkSmokeValidationCommand
}

if (-not $SkipNavigationLock) {
  $NavigationLockFile = Join-Path $RawDir "$ForkDefaultLabel-navigation-lock.json"
  $FileNavigationLockFile = Join-Path $RawDir "$ForkDefaultLabel-file-navigation-lock.json"

  Run-Command @(
    "node",
    (Join-Path $Root "scripts\run_navigation_lock_tests.mjs"),
    "--browser", $ForkBrowser,
    "--output", $NavigationLockFile
  )

  Run-Command @(
    "node",
    (Join-Path $Root "scripts\run_file_navigation_lock_tests.mjs"),
    "--browser", $ForkBrowser,
    "--output", $FileNavigationLockFile
  )

  Run-Command @(
    "node",
    (Join-Path $Root "scripts\validate_smoke_result.mjs"),
    "--type", "navigation",
    "--expected-browser", $ForkBrowser,
    $NavigationLockFile
  )

  Run-Command @(
    "node",
    (Join-Path $Root "scripts\validate_smoke_result.mjs"),
    "--type", "file-navigation",
    "--expected-browser", $ForkBrowser,
    $FileNavigationLockFile
  )
}

$BaselineWebGlCommand = @(
  (Join-Path $Root "scripts\run_full_suite.ps1"),
  "-Browser", $BaselineBrowser,
  "-Renderer", "webgl2",
  "-Duration", [string]$Duration,
  "-Warmup", [string]$Warmup,
  "-Label", $BaselineLabel,
  "-BuildArgs", $BaselineBuildArgs
)
if ($BaselinePackageDir) {
  $BaselineWebGlCommand += @("-PackageDir", $BaselinePackageDir)
}
Run-Command (Add-ResourceWarmupArgs $BaselineWebGlCommand)

$ForkWebGlCommand = @(
  (Join-Path $Root "scripts\run_full_suite.ps1"),
  "-Browser", $ForkBrowser,
  "-Renderer", "webgl2",
  "-Duration", [string]$Duration,
  "-Warmup", [string]$Warmup,
  "-Label", $ForkDefaultLabel,
  "-BuildArgs", $ForkBuildArgs,
  "-ForkRevision", $ViewerForkRevision,
  "-ViewerMode",
  "-ViewerTrustedContent"
)
if ($ForkPackageDir) {
  $ForkWebGlCommand += @("-PackageDir", $ForkPackageDir)
}
Run-Command (Add-ResourceWarmupArgs $ForkWebGlCommand)

if ($IncludeAggressiveGpu) {
  $AggressiveCommand = @(
    (Join-Path $Root "scripts\run_full_suite.ps1"),
    "-Browser", $ForkBrowser,
    "-Renderer", "webgl2",
    "-Duration", [string]$Duration,
    "-Warmup", [string]$Warmup,
    "-Label", $AggressiveLabel,
    "-BuildArgs", $ForkBuildArgs,
    "-ForkRevision", $ViewerForkRevision,
    "-ViewerMode",
    "-ViewerTrustedContent",
    "-ViewerAggressiveGpu"
  )
  if ($AggressiveAngleBackend) {
    $AggressiveCommand += @("-ViewerForceAngleBackend", $AggressiveAngleBackend)
  }
  if ($ForkPackageDir) {
    $AggressiveCommand += @("-PackageDir", $ForkPackageDir)
  }
  Run-Command (Add-ResourceWarmupArgs $AggressiveCommand)
}

if ($IncludeWebGPU) {
  $BaselineWebGpuCommand = @(
    (Join-Path $Root "scripts\run_full_suite.ps1"),
    "-Browser", $BaselineBrowser,
    "-Renderer", "webgpu",
    "-Duration", [string]$Duration,
    "-Warmup", [string]$Warmup,
    "-Label", "$BaselineLabel-webgpu",
    "-BuildArgs", $BaselineBuildArgs
  )
  if ($BaselinePackageDir) {
    $BaselineWebGpuCommand += @("-PackageDir", $BaselinePackageDir)
  }
  Run-Command (Add-ResourceWarmupArgs $BaselineWebGpuCommand)

  $ForkWebGpuCommand = @(
    (Join-Path $Root "scripts\run_full_suite.ps1"),
    "-Browser", $ForkBrowser,
    "-Renderer", "webgpu",
    "-Duration", [string]$Duration,
    "-Warmup", [string]$Warmup,
    "-Label", "$ForkDefaultLabel-webgpu",
    "-BuildArgs", $ForkBuildArgs,
    "-ForkRevision", $ViewerForkRevision,
    "-ViewerMode",
    "-ViewerTrustedContent"
  )
  if ($ForkPackageDir) {
    $ForkWebGpuCommand += @("-PackageDir", $ForkPackageDir)
  }
  Run-Command (Add-ResourceWarmupArgs $ForkWebGpuCommand)

  if ($IncludeAggressiveGpu) {
    $AggressiveWebGpuCommand = @(
      (Join-Path $Root "scripts\run_full_suite.ps1"),
      "-Browser", $ForkBrowser,
      "-Renderer", "webgpu",
      "-Duration", [string]$Duration,
      "-Warmup", [string]$Warmup,
      "-Label", "$AggressiveLabel-webgpu",
      "-BuildArgs", $ForkBuildArgs,
      "-ForkRevision", $ViewerForkRevision,
      "-ViewerMode",
      "-ViewerTrustedContent",
      "-ViewerAggressiveGpu"
    )
    if ($AggressiveAngleBackend) {
      $AggressiveWebGpuCommand += @("-ViewerForceAngleBackend", $AggressiveAngleBackend)
    }
    if ($ForkPackageDir) {
      $AggressiveWebGpuCommand += @("-PackageDir", $ForkPackageDir)
    }
    Run-Command (Add-ResourceWarmupArgs $AggressiveWebGpuCommand)
  }
}

if ($CaptureTrace) {
  $BaselineTrace = Join-Path $Root "benchmarks\traces\$BaselineLabel-$TraceScene-$TraceRenderer-trace.json"
  $ForkTrace = Join-Path $Root "benchmarks\traces\$ForkDefaultLabel-$TraceScene-$TraceRenderer-trace.json"

  $BaselineTraceCommand = @(
    "node",
    (Join-Path $Root "scripts\run_trace_capture.mjs"),
    "--browser", $BaselineBrowser,
    "--scene", $TraceScene,
    "--renderer", $TraceRenderer,
    "--duration", [string]$TraceDuration,
    "--warmup", [string]$TraceWarmup,
    "--startDelayMs", [string]$TraceStartDelayMs,
    "--output", $BaselineTrace
  )
  Run-Command (Add-TraceResourceWarmupArgs $BaselineTraceCommand)
  Invoke-TraceArtifactValidation `
    -TracePath $BaselineTrace `
    -ExpectedBrowser $BaselineBrowser `
    -ExpectedFlagMetadata (Get-TraceFlagMetadata) `
    -RequiredBrowserFlags $RequiredBrowserFlags
  Run-Command @(
    "node",
    (Join-Path $Root "scripts\summarize_trace.mjs"),
    $BaselineTrace,
    "--output", (Join-Path $ReportDir "$BaselineLabel-$TraceScene-$TraceRenderer-trace-summary.md")
  )

  $ForkTraceCommand = @(
    "node",
    (Join-Path $Root "scripts\run_trace_capture.mjs"),
    "--browser", $ForkBrowser,
    "--scene", $TraceScene,
    "--renderer", $TraceRenderer,
    "--duration", [string]$TraceDuration,
    "--warmup", [string]$TraceWarmup,
    "--startDelayMs", [string]$TraceStartDelayMs,
    "--viewerMode",
    "--viewerTrustedContent",
    "--output", $ForkTrace
  )
  Run-Command (Add-TraceResourceWarmupArgs $ForkTraceCommand)
  Invoke-TraceArtifactValidation `
    -TracePath $ForkTrace `
    -ExpectedBrowser $ForkBrowser `
    -ExpectedFlagMetadata (Get-TraceFlagMetadata -ViewerMode $true -ViewerTrustedContent $true) `
    -RequiredBrowserFlags $RequiredBrowserFlags
  Run-Command @(
    "node",
    (Join-Path $Root "scripts\summarize_trace.mjs"),
    $ForkTrace,
    "--output", (Join-Path $ReportDir "$ForkDefaultLabel-$TraceScene-$TraceRenderer-trace-summary.md")
  )
}

Invoke-BenchmarkSuiteValidation `
  -Renderer "webgl2" `
  -Variant $BaselineLabel `
  -Files $BaselineWebGlFiles `
  -RequirePackageSize:([bool]$BaselinePackageDir) `
  -ExpectedChromiumRevision $ChromiumRevision `
  -ExpectedBrowser $BaselineBrowser `
  -ExpectedFlagMetadata (Get-ViewerFlagMetadata) `
  -RequiredBrowserFlags $RequiredBrowserFlags

Invoke-BenchmarkSuiteValidation `
  -Renderer "webgl2" `
  -Variant $ForkDefaultLabel `
  -Files $ForkWebGlFiles `
  -RequireForkRevision `
  -RequirePackageSize:([bool]$ForkPackageDir) `
  -ExpectedChromiumRevision $ChromiumRevision `
  -ExpectedBrowser $ForkBrowser `
  -ExpectedForkRevision $ViewerForkRevision `
  -ExpectedFlagMetadata (Get-ViewerFlagMetadata -ViewerMode $true -ViewerTrustedContent $true) `
  -RequiredBrowserFlags $RequiredBrowserFlags

if ($IncludeAggressiveGpu) {
  Invoke-BenchmarkSuiteValidation `
    -Renderer "webgl2" `
    -Variant $AggressiveLabel `
    -Files $AggressiveWebGlFiles `
    -RequireForkRevision `
    -RequirePackageSize:([bool]$ForkPackageDir) `
    -ExpectedChromiumRevision $ChromiumRevision `
    -ExpectedBrowser $ForkBrowser `
    -ExpectedForkRevision $ViewerForkRevision `
    -ExpectedFlagMetadata (Get-ViewerFlagMetadata -ViewerMode $true -ViewerTrustedContent $true -ViewerAggressiveGpu $true -ViewerForceAngleBackend $AggressiveAngleBackend) `
    -RequiredBrowserFlags $RequiredBrowserFlags
}

if ($IncludeWebGPU) {
  Invoke-BenchmarkSuiteValidation `
    -Renderer "webgpu" `
    -Variant "$BaselineLabel-webgpu" `
    -Files $BaselineWebGpuFiles `
    -RequirePackageSize:([bool]$BaselinePackageDir) `
    -ExpectedChromiumRevision $ChromiumRevision `
    -ExpectedBrowser $BaselineBrowser `
    -ExpectedFlagMetadata (Get-ViewerFlagMetadata) `
    -RequiredBrowserFlags $RequiredBrowserFlags

  Invoke-BenchmarkSuiteValidation `
    -Renderer "webgpu" `
    -Variant "$ForkDefaultLabel-webgpu" `
    -Files $ForkWebGpuFiles `
    -RequireForkRevision `
    -RequirePackageSize:([bool]$ForkPackageDir) `
    -ExpectedChromiumRevision $ChromiumRevision `
    -ExpectedBrowser $ForkBrowser `
    -ExpectedForkRevision $ViewerForkRevision `
    -ExpectedFlagMetadata (Get-ViewerFlagMetadata -ViewerMode $true -ViewerTrustedContent $true) `
    -RequiredBrowserFlags $RequiredBrowserFlags

  if ($IncludeAggressiveGpu) {
    Invoke-BenchmarkSuiteValidation `
      -Renderer "webgpu" `
      -Variant "$AggressiveLabel-webgpu" `
      -Files $AggressiveWebGpuFiles `
      -RequireForkRevision `
      -RequirePackageSize:([bool]$ForkPackageDir) `
      -ExpectedChromiumRevision $ChromiumRevision `
      -ExpectedBrowser $ForkBrowser `
      -ExpectedForkRevision $ViewerForkRevision `
      -ExpectedFlagMetadata (Get-ViewerFlagMetadata -ViewerMode $true -ViewerTrustedContent $true -ViewerAggressiveGpu $true -ViewerForceAngleBackend $AggressiveAngleBackend) `
      -RequiredBrowserFlags $RequiredBrowserFlags
  }
}

$ReportInputs = @()
$ReportInputs += $BaselineWebGlFiles
$ReportInputs += $ForkWebGlFiles
if ($IncludeAggressiveGpu) {
  $ReportInputs += $AggressiveWebGlFiles
}

$BaselineSummaryCommand = @(
  "node",
  (Join-Path $Root "scripts\summarize_results.mjs")
)
$BaselineSummaryCommand += $BaselineWebGlFiles
$BaselineSummaryCommand += @("--output", (Join-Path $ReportDir "$BaselineLabel-webgl2-summary.md"))
Run-Command $BaselineSummaryCommand

$ForkSummaryCommand = @(
  "node",
  (Join-Path $Root "scripts\summarize_results.mjs")
)
$ForkSummaryCommand += $ForkWebGlFiles
$ForkSummaryCommand += @("--output", (Join-Path $ReportDir "$ForkDefaultLabel-webgl2-summary.md"))
Run-Command $ForkSummaryCommand

$CompareCommand = @(
  "node",
  (Join-Path $Root "scripts\compare_results.mjs")
)
$CompareCommand += $ReportInputs
$CompareCommand += @(
  "--strictOfficial",
  "--output", (Join-Path $ReportDir "official-webgl2-comparison.md")
)
Run-Command $CompareCommand

if ($IncludeWebGPU) {
  $WebGpuInputs = @()
  $WebGpuInputs += $BaselineWebGpuFiles
  $WebGpuInputs += $ForkWebGpuFiles
  if ($IncludeAggressiveGpu) {
    $WebGpuInputs += $AggressiveWebGpuFiles
  }
  $WebGpuCompareCommand = @(
    "node",
    (Join-Path $Root "scripts\compare_results.mjs")
  )
  $WebGpuCompareCommand += $WebGpuInputs
  $WebGpuCompareCommand += @(
    "--strictOfficial",
    "--output", (Join-Path $ReportDir "official-webgpu-comparison.md")
  )
  Run-Command $WebGpuCompareCommand
}

if ($DryRun) {
  Write-OfficialComparisonManifest -Phase "planned"
} else {
  Write-OfficialComparisonManifest -Phase "completed"
}

Write-Host "Official comparison workflow completed."
Write-Host "Reports written under $ReportDir"

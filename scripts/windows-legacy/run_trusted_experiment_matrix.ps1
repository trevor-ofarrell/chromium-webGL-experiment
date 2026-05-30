[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Browser,
  [string]$BuildArgs = "",
  [string]$PackageDir = "",
  [string]$ForkRevision = "",
  [string]$Renderer = "webgl2",
  [string]$LabelSuffix = "",
  [string[]]$Scenes = @(
    "many-draw-calls",
    "instancing",
    "shader-heavy",
    "texture-streaming",
    "postprocessing",
    "large-static",
    "gltf-loader-stress"
  ),
  [int]$Duration = 60,
  [int]$Warmup = 10,
  [string[]]$AngleBackend = @(),
  [switch]$IncludeDefault,
  [switch]$IncludeAggressiveGpu,
  [switch]$IncludeZeroCopy,
  [switch]$IncludeWebGlCompositorExperiments,
  [switch]$IncludeFramePacingExperiments,
  [switch]$IncludeInProcessGpu,
  [switch]$IncludeSingleProcess,
  [switch]$IncludeReservedNoopGates,
  [switch]$IncludeWebGpuDawnExperiments,
  [switch]$IncludeWebGpuChromiumFeatureExperiments,
  [switch]$IncludeWebGpuUploadExperiments,
  [string[]]$ExperimentLabelFilter = @(),
  [switch]$Precompile,
  [int]$PrerenderFrames = 0,
  [switch]$SettleGpuAfterWarmup,
  [int]$WebGpuPipelineQuietFrames = 0,
  [int]$WebGpuPipelineQuietMaxFrames = 30,
  [ValidateSet("off", "static")]
  [string]$WebGpuBundleMode = "off",
  [switch]$DisableGpuTiming,
  [double]$Complexity = 2.0,
  [string]$ProfileCacheKey = "",
  [string]$UserDataDirRoot = "",
  [switch]$PrimeProfileCache,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BenchmarkTmpRoot = Join-Path $Root "benchmarks\tmp"
$ViewerPatchSeries = @(
  "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch",
  "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"
)
$RawDir = Join-Path $Root "benchmarks\raw"
$ReportDir = Join-Path $Root "benchmarks\reports"
New-Item -ItemType Directory -Path $RawDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

function Normalize-StringList {
  param(
    [AllowNull()][string[]]$Values,
    [string]$Label,
    [switch]$AllowEmpty
  )

  $Items = @(
    @($Values) |
      ForEach-Object {
        foreach ($Part in ([string]$_ -split ",")) {
          $Trimmed = $Part.Trim()
          if ($Trimmed) {
            $Trimmed
          }
        }
      }
  )

  if (-not $AllowEmpty -and $Items.Count -eq 0) {
    throw "$Label cannot be empty."
  }

  return @($Items)
}

$Scenes = @(Normalize-StringList -Values $Scenes -Label "Scenes")
$AngleBackend = @(Normalize-StringList -Values $AngleBackend -Label "AngleBackend" -AllowEmpty)
$ExperimentLabelFilter = @(Normalize-StringList -Values $ExperimentLabelFilter -Label "ExperimentLabelFilter" -AllowEmpty)
if ($LabelSuffix -and $LabelSuffix -notmatch "^[A-Za-z0-9._-]+$") {
  throw "LabelSuffix may contain only ASCII letters, numbers, dot, underscore, or hyphen."
}
if ($WebGpuBundleMode -ne "off" -and $Renderer -ne "webgpu") {
  throw "-WebGpuBundleMode is only supported with -Renderer webgpu."
}
if ($Renderer -eq "webgpu" -and $WebGpuBundleMode -eq "static" -and $LabelSuffix -notmatch "(^|-)bundlegroup-static($|-)") {
  $LabelSuffix = "$LabelSuffix-bundlegroup-static"
}

function Resolve-RepoPath {
  param([string]$PathValue)
  if (-not $PathValue) {
    return ""
  }
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return (Join-Path $Root $PathValue)
}

function Resolve-RepoFullPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $Root $PathValue))
}

function Test-PathUnderDirectory {
  param(
    [string]$PathValue,
    [string]$Parent
  )

  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  return $FullPath.StartsWith($FullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-SafePathSegment {
  param([string]$Value)
  return ([string]$Value) -replace '[^A-Za-z0-9._-]', '_'
}

if ($ProfileCacheKey -and -not $UserDataDirRoot) {
  $UserDataDirRoot = Join-Path $BenchmarkTmpRoot "trusted-profile-cache"
}
if ($Complexity -le 0) {
  throw "-Complexity must be greater than zero."
}
if ($WebGpuPipelineQuietFrames -lt 0 -or $WebGpuPipelineQuietMaxFrames -lt 0) {
  throw "-WebGpuPipelineQuietFrames and -WebGpuPipelineQuietMaxFrames must be non-negative."
}
if ($WebGpuPipelineQuietFrames -gt 0 -and $Renderer -ne "webgpu") {
  throw "-WebGpuPipelineQuietFrames is only supported with -Renderer webgpu."
}
if ($UserDataDirRoot -and -not $ProfileCacheKey) {
  throw "-UserDataDirRoot requires -ProfileCacheKey so reused-profile artifacts are labeled for compatibility checks."
}
if ($PrimeProfileCache -and -not $ProfileCacheKey) {
  throw "-PrimeProfileCache requires -ProfileCacheKey."
}
$ResolvedUserDataDirRoot = ""
if ($ProfileCacheKey) {
  $ResolvedUserDataDirRoot = Resolve-RepoFullPath $UserDataDirRoot
  if (-not (Test-PathUnderDirectory $ResolvedUserDataDirRoot $BenchmarkTmpRoot)) {
    throw "-UserDataDirRoot must resolve under $BenchmarkTmpRoot."
  }
}

function Require-PackageDirectory {
  param(
    [string]$PathValue,
    [string]$Label,
    [string]$ExpectedBrowser = ""
  )

  $Resolved = Resolve-RepoPath $PathValue
  if ($DryRun -or -not $Resolved) {
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

function Require-InputFile {
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

function Format-Command {
  param([object[]]$Command)
  return ($Command | ForEach-Object {
    $Text = [string]$_
    if ($Text -match "\s") {
      return '"' + ($Text -replace '"', '\"') + '"'
    }
    return $Text
  }) -join " "
}

function Invoke-CommandChecked {
  param([object[]]$Command)
  if ($DryRun) {
    Write-Host "[dry-run] $(Format-Command $Command)"
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

function Invoke-WebGpuExperimentSourceValidation {
  if ($Renderer -ne "webgpu") {
    return
  }
  if (-not ($IncludeWebGpuDawnExperiments -or $IncludeWebGpuChromiumFeatureExperiments -or $IncludeWebGpuUploadExperiments)) {
    return
  }

  $ValidationScript = Join-Path $PSScriptRoot "test_webgpu_experiment_flag_sources.ps1"
  if (-not (Test-Path -LiteralPath $ValidationScript -PathType Leaf)) {
    throw "WebGPU experiment source-registry validation script not found: $ValidationScript"
  }

  Write-Host "Checking trusted WebGPU experiment flag source registrations..."
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ValidationScript
  if ($LASTEXITCODE -ne 0) {
    throw "WebGPU experiment source-registry validation failed with exit code $LASTEXITCODE"
  }
}

function Test-ExperimentMatchesLabelFilter {
  param(
    [object]$Experiment,
    [string]$Pattern
  )

  return $Experiment.Label -like $Pattern -or $Experiment.BaseLabel -like $Pattern
}

function Apply-ExperimentLabelFilter {
  if ($ExperimentLabelFilter.Count -eq 0) {
    return
  }

  $UnmatchedFilters = @(
    foreach ($Pattern in $ExperimentLabelFilter) {
      $Matched = @($Experiments | Where-Object { Test-ExperimentMatchesLabelFilter $_ $Pattern })
      if ($Matched.Count -eq 0) {
        $Pattern
      }
    }
  )
  if ($UnmatchedFilters.Count -gt 0) {
    throw "ExperimentLabelFilter did not match any selected experiment labels: $($UnmatchedFilters -join ', ')"
  }

  $FilteredExperiments = [System.Collections.Generic.List[object]]::new()
  foreach ($Experiment in $Experiments) {
    foreach ($Pattern in $ExperimentLabelFilter) {
      if (Test-ExperimentMatchesLabelFilter $Experiment $Pattern) {
        $FilteredExperiments.Add($Experiment) | Out-Null
        break
      }
    }
  }

  $script:Experiments = $FilteredExperiments
  Write-Host "Filtered trusted experiment matrix to $($Experiments.Count) experiment(s): $($ExperimentLabelFilter -join ', ')"
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

function Get-Sha256 {
  param([string]$PathValue)
  if (-not (Test-Path $PathValue)) {
    if ($DryRun) {
      return ""
    }
    throw "File not found for hash: $PathValue"
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
}

function Get-ShortSha256Text {
  param([string]$Text)
  $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return (([System.BitConverter]::ToString($Sha.ComputeHash($Bytes)) -replace "-", "").Substring(0, 12)).ToLowerInvariant()
  } finally {
    $Sha.Dispose()
  }
}

function Get-ViewerPatchSeriesHash {
  $Entries = @($ViewerPatchSeries | ForEach-Object {
      $PatchPath = Join-Path $Root $_
      if (-not (Test-Path $PatchPath)) {
        throw "Viewer patch not found for fork revision hash: $PatchPath"
      }
      $CanonicalPath = $_ -replace "\\", "/"
      "$CanonicalPath=$((Get-FileHash -Algorithm SHA256 -LiteralPath $PatchPath).Hash.ToLowerInvariant())"
    })
  return Get-ShortSha256Text ($Entries -join "`n")
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

function Get-ViewerForkRevision {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $PatchHash = Get-ViewerPatchSeriesHash
  return "$ChromiumRevision+viewerpatch-$PatchHash"
}

function Invoke-BenchmarkSuiteValidation {
  param(
    [string]$Variant,
    [string[]]$Files,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [string]$ExpectedBuildArgsHash = "",
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @()
  )

  $Command = @(
    "node",
    (Join-Path $Root "scripts\validate_benchmark_suite.mjs"),
    "--renderer", $Renderer,
    "--variant", $Variant,
    "--expectedScenes", ($Scenes -join ","),
    "--requireCheckout",
    "--requireBuildArgs",
    "--forbidSmoke",
    "--rejectSoftwareRendering",
    "--rejectGpuInstability",
    "--requireGpuMetadata",
    "--requireFrameTimes",
    "--expectedMeasuredSeconds", [string]$Duration,
    "--expectedWarmupSeconds", [string]$Warmup,
    "--expectedComplexity", [string]$Complexity,
    "--requireForkRevision",
    "--expectedForkRevision", $ForkRevision
  )
  if ($ExpectedChromiumRevision) {
    $Command += @("--expectedChromiumRevision", $ExpectedChromiumRevision)
  }
  if ($ExpectedBrowser) {
    $Command += @("--expectedBrowser", $ExpectedBrowser)
  }
  if ($ExpectedBuildArgsHash) {
    $Command += @("--expectedBuildArgsHash", $ExpectedBuildArgsHash)
  }
  if ($PackageDir) {
    $Command += "--requirePackageSize"
  }
  foreach ($Metadata in $ExpectedFlagMetadata) {
    $Command += @("--expectedFlagMetadata", $Metadata)
  }
  foreach ($Flag in $RequiredBrowserFlags) {
    $Command += @("--requiredBrowserFlag", $Flag)
  }
  $Command += $Files
  Invoke-CommandChecked $Command
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

function Get-ExperimentExpectedFlagMetadata {
  param([object]$Experiment)

  $Metadata = [ordered]@{
    viewer_mode = $true
    viewer_block_external_navigation = $true
    viewer_trusted_content = $true
    viewer_aggressive_gpu = $false
    viewer_relaxed_webgl_validation = $false
    viewer_zero_copy = $false
    viewer_in_process_gpu = $false
    viewer_single_process = $false
    viewer_force_angle_backend = $null
    requested_angle_backend = $null
    viewer_disable_unneeded_blink_features = $false
    viewer_direct_gpu_presentation = $false
    viewer_defer_webgpu_pipeline_flush = $false
    viewer_defer_webgpu_queue_flush = $false
    viewer_defer_webgpu_submit_flush = $false
    viewer_skip_webgpu_canvas_texture_validation = $false
    viewer_skip_webgpu_canvas_memory_accounting = $false
    viewer_skip_webgpu_copy_external_image_color_conversion = $false
    viewer_skip_webgpu_copy_external_image_color_space_validation = $false
    viewer_skip_webgpu_copy_external_image_dest_validation = $false
    viewer_skip_webgpu_copy_external_image_source_validation = $false
    viewer_skip_webgpu_copy_external_image_copy_size_validation = $false
    viewer_skip_webgpu_write_texture_layout_validation = $false
    viewer_reject_webgpu_cpu_texture_fallback = $false
    viewer_skip_webgpu_use_counters = $false
    viewer_cache_webgpu_bind_group_layouts = $false
    viewer_skip_webgpu_command_labels = $false
    viewer_skip_webgpu_resource_labels = $false
    viewer_skip_webgpu_shader_source_null_check = $false
    viewer_skip_webgpu_shader_memory_accounting = $false
    viewer_skip_webgpu_redundant_pipeline_sets = $false
    viewer_skip_webgpu_redundant_bind_group_sets = $false
    viewer_skip_webgpu_redundant_buffer_sets = $false
    viewer_skip_webgpu_redundant_render_state_sets = $false
    viewer_trace_webgpu_queue = $false
    gpu_timing_enabled = -not [bool]$DisableGpuTiming
    benchmark_hud_enabled = $false
    resource_warmup_enabled = [bool]($Precompile -or $PrerenderFrames -gt 0 -or $SettleGpuAfterWarmup -or ($Renderer -eq "webgpu" -and $WebGpuPipelineQuietFrames -gt 0))
    resource_warmup_precompile = [bool]$Precompile
    resource_warmup_prerender_frames = $PrerenderFrames
    resource_warmup_settle_gpu = [bool]$SettleGpuAfterWarmup
    resource_warmup_pipeline_quiet_frames = if ($Renderer -eq "webgpu") { $WebGpuPipelineQuietFrames } else { 0 }
    resource_warmup_pipeline_quiet_max_frames = if ($Renderer -eq "webgpu" -and $WebGpuPipelineQuietFrames -gt 0) { [Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames) } else { 0 }
    webgpu_bundle_mode = if ($Renderer -eq "webgpu") { $WebGpuBundleMode } else { "off" }
    profile_cache_mode = if ($ProfileCacheKey) { "explicit-reuse" } else { "fresh-temp" }
    profile_cache_key = if ($ProfileCacheKey) { $ProfileCacheKey } else { $null }
    profile_reuse_enabled = [bool]$ProfileCacheKey
  }

  for ($Index = 0; $Index -lt $Experiment.Flags.Count; $Index += 1) {
    switch ($Experiment.Flags[$Index]) {
      "--viewerAggressiveGpu" { $Metadata.viewer_aggressive_gpu = $true }
      "--viewerRelaxedWebglValidation" { $Metadata.viewer_relaxed_webgl_validation = $true }
      "--viewerZeroCopy" { $Metadata.viewer_zero_copy = $true }
      "--viewerInProcessGpu" { $Metadata.viewer_in_process_gpu = $true }
      "--viewerSingleProcess" { $Metadata.viewer_single_process = $true }
      "--viewerDisableUnneededBlinkFeatures" { $Metadata.viewer_disable_unneeded_blink_features = $true }
      "--viewerDirectGpuPresentation" { $Metadata.viewer_direct_gpu_presentation = $true }
      "--viewerDeferWebgpuPipelineFlush" { $Metadata.viewer_defer_webgpu_pipeline_flush = $true }
      "--viewerDeferWebgpuQueueFlush" { $Metadata.viewer_defer_webgpu_queue_flush = $true }
      "--viewerDeferWebgpuSubmitFlush" { $Metadata.viewer_defer_webgpu_submit_flush = $true }
      "--viewerSkipWebgpuCanvasTextureValidation" { $Metadata.viewer_skip_webgpu_canvas_texture_validation = $true }
      "--viewerSkipWebgpuCanvasMemoryAccounting" { $Metadata.viewer_skip_webgpu_canvas_memory_accounting = $true }
      "--viewerSkipWebgpuCopyExternalImageColorConversion" { $Metadata.viewer_skip_webgpu_copy_external_image_color_conversion = $true }
      "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation" { $Metadata.viewer_skip_webgpu_copy_external_image_color_space_validation = $true }
      "--viewerSkipWebgpuCopyExternalImageDestValidation" { $Metadata.viewer_skip_webgpu_copy_external_image_dest_validation = $true }
      "--viewerSkipWebgpuCopyExternalImageSourceValidation" { $Metadata.viewer_skip_webgpu_copy_external_image_source_validation = $true }
      "--viewerSkipWebgpuCopyExternalImageCopySizeValidation" { $Metadata.viewer_skip_webgpu_copy_external_image_copy_size_validation = $true }
      "--viewerSkipWebgpuWriteTextureLayoutValidation" { $Metadata.viewer_skip_webgpu_write_texture_layout_validation = $true }
      "--viewerRejectWebgpuCpuTextureFallback" { $Metadata.viewer_reject_webgpu_cpu_texture_fallback = $true }
      "--viewerSkipWebgpuUseCounters" { $Metadata.viewer_skip_webgpu_use_counters = $true }
      "--viewerCacheWebgpuBindGroupLayouts" { $Metadata.viewer_cache_webgpu_bind_group_layouts = $true }
      "--viewerSkipWebgpuCommandLabels" { $Metadata.viewer_skip_webgpu_command_labels = $true }
      "--viewerSkipWebgpuResourceLabels" { $Metadata.viewer_skip_webgpu_resource_labels = $true }
      "--viewerSkipWebgpuShaderSourceNullCheck" { $Metadata.viewer_skip_webgpu_shader_source_null_check = $true }
      "--viewerSkipWebgpuShaderMemoryAccounting" { $Metadata.viewer_skip_webgpu_shader_memory_accounting = $true }
      "--viewerSkipWebgpuRedundantPipelineSets" { $Metadata.viewer_skip_webgpu_redundant_pipeline_sets = $true }
      "--viewerSkipWebgpuRedundantBindGroupSets" { $Metadata.viewer_skip_webgpu_redundant_bind_group_sets = $true }
      "--viewerSkipWebgpuRedundantBufferSets" { $Metadata.viewer_skip_webgpu_redundant_buffer_sets = $true }
      "--viewerSkipWebgpuRedundantRenderStateSets" { $Metadata.viewer_skip_webgpu_redundant_render_state_sets = $true }
      "--viewerTraceWebgpuQueue" { $Metadata.viewer_trace_webgpu_queue = $true }
      "--viewerForceAngleBackend" {
        $Index += 1
        if ($Index -ge $Experiment.Flags.Count) {
          throw "Experiment $($Experiment.Label) is missing the value for --viewerForceAngleBackend."
        }
        $Metadata.viewer_force_angle_backend = $Experiment.Flags[$Index]
        $Metadata.requested_angle_backend = $Experiment.Flags[$Index]
      }
    }
  }

  return @($Metadata.GetEnumerator() | ForEach-Object {
    "$($_.Key)=$(Convert-MetadataValue $_.Value)"
  })
}

function New-Experiment {
  param(
    [string]$Label,
    [string]$Description,
    [string[]]$Flags = @(),
    [string[]]$BrowserFlags = @()
  )
  return [pscustomobject]@{
    Label = "$Label$LabelSuffix"
    BaseLabel = $Label
    LabelSuffix = $LabelSuffix
    Description = $Description
    Flags = $Flags
    BrowserFlags = $BrowserFlags
  }
}

function Get-ExperimentResultFiles {
  param([object]$Experiment)
  return @($Scenes | ForEach-Object {
    Join-Path $RawDir "$($Experiment.Label)-$_-$Renderer.json"
  })
}

function Get-ExperimentUserDataDir {
  param(
    [object]$Experiment,
    [string]$Scene
  )

  if (-not $ProfileCacheKey) {
    return ""
  }

  return Join-Path $ResolvedUserDataDirRoot (Join-Path (ConvertTo-SafePathSegment $Experiment.Label) (Join-Path (ConvertTo-SafePathSegment $Renderer) (ConvertTo-SafePathSegment $Scene)))
}

function Get-ExperimentManifestEntry {
  param([object]$Experiment)
  return [pscustomobject]@{
    label = $Experiment.Label
    base_label = $Experiment.BaseLabel
    label_suffix = $Experiment.LabelSuffix
    description = $Experiment.Description
    flags = @($Experiment.Flags)
    browser_flags = @($Experiment.BrowserFlags)
    required_browser_flags = @($RequiredBrowserFlags + @($Experiment.BrowserFlags))
    expected_flag_metadata = @(Get-ExperimentExpectedFlagMetadata $Experiment)
    result_files = @(Get-ExperimentResultFiles $Experiment)
  }
}

function Get-ExperimentResultMetadata {
  param([object]$Experiment)
  return [pscustomobject]@{
    label = $Experiment.Label
    files = Get-FileMetadataList @(Get-ExperimentResultFiles $Experiment)
  }
}

function Write-TrustedExperimentManifest {
  param([string]$Phase = "planned")

  $ManifestName = if ($DryRun) {
    "trusted-experiment-matrix-manifest.dry-run.json"
  } else {
    "trusted-experiment-matrix-manifest.json"
  }
  $RendererManifestName = if ($DryRun) {
    "trusted-experiment-matrix-$Renderer-manifest.dry-run.json"
  } else {
    "trusted-experiment-matrix-$Renderer-manifest.json"
  }
  $ManifestPath = Join-Path $ReportDir $ManifestName
  $RendererManifestPath = Join-Path $ReportDir $RendererManifestName
  $SummaryPath = Join-Path $ReportDir "trusted-experiment-matrix-$Renderer-summary.md"
  $ComparePath = Join-Path $ReportDir "trusted-experiment-matrix-$Renderer-comparison.md"
  $ExperimentEntries = @($Experiments | ForEach-Object { Get-ExperimentManifestEntry $_ })
  $AllResultFiles = @($ExperimentEntries | ForEach-Object { $_.result_files })
  $ExperimentResultMetadata = @($Experiments | ForEach-Object { Get-ExperimentResultMetadata $_ })

  $Manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = [bool]$DryRun
    phase = $Phase
    chromium_revision = Get-GitRevision (Join-Path $Root "src")
    fork_revision = $ForkRevision
    browser = $Browser
    build_args = $BuildArgs
    package_dir = $PackageDir
    renderer = $Renderer
    scenes = $Scenes
    suite_validation = [pscustomobject]@{
      expected_scenes = $Scenes
      require_checkout = $true
      require_build_args = $true
      require_fork_revision = $true
      expected_fork_revision = $ForkRevision
      forbid_smoke = $true
      reject_software_rendering = $true
      reject_gpu_instability = $true
      require_gpu_metadata = $true
      require_frame_times = $true
      expected_chromium_revision = $ChromiumRevision
      expected_browser = $Browser
      expected_build_args_hash = $BuildArgsHash
      expected_measured_seconds = $Duration
      expected_warmup_seconds = $Warmup
      expected_complexity = $Complexity
      exact_scene_output_files = $true
      expected_flag_metadata = $true
      required_browser_flags = @($RequiredBrowserFlags)
      profile_cache_policy = "same-profile-cache-mode-and-key"
      profile_cache_prime_policy = if ($PrimeProfileCache) { "prime-before-measured-run" } else { "none" }
    }
    options = [pscustomobject]@{
      duration = $Duration
      warmup = $Warmup
      precompile = [bool]$Precompile
      prerender_frames = $PrerenderFrames
      settle_gpu_after_warmup = [bool]$SettleGpuAfterWarmup
      webgpu_pipeline_quiet_frames = if ($Renderer -eq "webgpu") { $WebGpuPipelineQuietFrames } else { 0 }
      webgpu_pipeline_quiet_max_frames = if ($Renderer -eq "webgpu" -and $WebGpuPipelineQuietFrames -gt 0) { [Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames) } else { 0 }
      webgpu_bundle_mode = if ($Renderer -eq "webgpu") { $WebGpuBundleMode } else { "off" }
      label_suffix = $LabelSuffix
      experiment_label_filter = @($ExperimentLabelFilter)
      disable_gpu_timing = [bool]$DisableGpuTiming
      complexity = $Complexity
      profile_cache_key = if ($ProfileCacheKey) { $ProfileCacheKey } else { $null }
      profile_cache_mode = if ($ProfileCacheKey) { "explicit-reuse" } else { "fresh-temp" }
      profile_cache_root = if ($ProfileCacheKey) { $ResolvedUserDataDirRoot } else { $null }
      prime_profile_cache = [bool]$PrimeProfileCache
      profile_cache_policy = "same-profile-cache-mode-and-key"
      profile_cache_prime_policy = if ($PrimeProfileCache) { "prime-before-measured-run" } else { "none" }
    }
    experiments = $ExperimentEntries
    result_files = [pscustomobject]@{
      all = $AllResultFiles
      by_experiment = $ExperimentEntries
    }
    report_files = [pscustomobject]@{
      summary = $SummaryPath
      comparison = $ComparePath
    }
    manifest_files = [pscustomobject]@{
      generic = $ManifestPath
      renderer = $RendererManifestPath
    }
    artifact_metadata = [pscustomobject]@{
      inputs = [pscustomobject]@{
        browser = Get-FileMetadata $Browser
        build_args = Get-FileMetadata $BuildArgs
        viewer_patch = Get-FileMetadata (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
        viewer_patch_series = Get-FileMetadataList $ViewerPatchSeries
        package = Get-DirectoryMetadata $PackageDir
      }
      results = [pscustomobject]@{
        all = Get-FileMetadataList $AllResultFiles
        by_experiment = $ExperimentResultMetadata
      }
      reports = [pscustomobject]@{
        summary = Get-FileMetadata $SummaryPath
        comparison = Get-FileMetadata $ComparePath
      }
    }
  }

  $ManifestJson = $Manifest | ConvertTo-Json -Depth 8
  $ManifestJson | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  Write-Host "Wrote $ManifestPath"
  if ($RendererManifestPath -ne $ManifestPath) {
    $ManifestJson | Set-Content -LiteralPath $RendererManifestPath -Encoding UTF8
    Write-Host "Wrote $RendererManifestPath"
  }
}

if (-not $BuildArgs) {
  throw "BuildArgs is required so trusted experiment results include reproducible build_args_hash metadata."
}
if ($IncludeZeroCopy -and $Renderer -ne "webgl2") {
  throw "-IncludeZeroCopy is currently restricted to -Renderer webgl2 because WebGPU zero-copy evidence regressed."
}
if ($IncludeWebGlCompositorExperiments -and $Renderer -ne "webgl2") {
  throw "-IncludeWebGlCompositorExperiments is only valid with -Renderer webgl2."
}
if ($IncludeWebGpuDawnExperiments -and $Renderer -ne "webgpu") {
  throw "-IncludeWebGpuDawnExperiments is only valid with -Renderer webgpu."
}
if ($IncludeWebGpuChromiumFeatureExperiments -and $Renderer -ne "webgpu") {
  throw "-IncludeWebGpuChromiumFeatureExperiments is only valid with -Renderer webgpu."
}
if ($IncludeWebGpuUploadExperiments -and $Renderer -ne "webgpu") {
  throw "-IncludeWebGpuUploadExperiments is only valid with -Renderer webgpu."
}
$Browser = Require-InputFile $Browser "Browser executable"
$BuildArgs = Require-InputFile $BuildArgs "Build args"
$BuildArgsHash = Get-Sha256 $BuildArgs
$PackageDir = Require-PackageDirectory $PackageDir "Trusted package directory" $Browser
$ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
if (-not $ForkRevision) {
  $ForkRevision = Get-ViewerForkRevision
}
Write-Host "Viewer fork revision: $ForkRevision"
$RequiredBrowserFlags = @("--disable-software-rasterizer")

$Experiments = [System.Collections.Generic.List[object]]::new()
if ($IncludeDefault) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-default" "Default trusted viewer profile for experiment comparisons")) | Out-Null
}
if ($IncludeAggressiveGpu) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-aggressive-gpu" "Trusted aggressive GPU alias bundle" @("--viewerAggressiveGpu"))) | Out-Null
}
if ($IncludeZeroCopy) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-zero-copy" "Trusted zero-copy raster/upload path experiment; currently valid only for WebGL2 speed-candidate runs" @("--viewerZeroCopy"))) | Out-Null
}
if ($IncludeWebGlCompositorExperiments) {
  $WebGlCompositorBrowserFlags = @(
    "--enable-gpu-memory-buffer-compositor-resources",
    "--ui-enable-zero-copy",
    "--enable-gpu-rasterization"
  )
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgl2-gpu-compositor-resources" "Trusted WebGL2 compositor GPU-memory-buffer resource experiment for zero-copy tail attribution" @() $WebGlCompositorBrowserFlags)) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources" "Trusted WebGL2 zero-copy plus compositor GPU-memory-buffer resource experiment for tail-latency repair" @("--viewerZeroCopy") $WebGlCompositorBrowserFlags)) | Out-Null
}
if ($IncludeFramePacingExperiments) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-disable-frame-rate-limit" "Trusted frame-pacing experiment disabling Chromium's frame-rate limiter for FPS and latency attribution" @() @("--disable-frame-rate-limit"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-disable-gpu-vsync" "Trusted frame-pacing experiment disabling GPU vsync for presentation-latency attribution" @() @("--disable-gpu-vsync"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync" "Trusted frame-pacing experiment disabling both frame-rate limiting and GPU vsync" @() @("--disable-frame-rate-limit", "--disable-gpu-vsync"))) | Out-Null
}
if ($IncludeInProcessGpu) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-in-process-gpu" "Trusted in-process GPU experiment" @("--viewerInProcessGpu"))) | Out-Null
}
if ($IncludeSingleProcess) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-single-process" "Trusted single-process experiment" @("--viewerSingleProcess"))) | Out-Null
}
foreach ($Backend in $AngleBackend) {
  if ($Backend -and $Backend -ne "default") {
    $Experiments.Add((New-Experiment "fork-viewer-exp-angle-$Backend" "Trusted ANGLE backend experiment: $Backend" @("--viewerForceAngleBackend", $Backend))) | Out-Null
    if ($Renderer -eq "webgl2" -and $IncludeZeroCopy) {
      $Experiments.Add((New-Experiment "fork-viewer-exp-angle-$Backend-zero-copy" "Trusted WebGL2 ANGLE $Backend plus zero-copy interaction experiment for tail/throughput attribution" @("--viewerForceAngleBackend", $Backend, "--viewerZeroCopy"))) | Out-Null
    }
  }
}
if ($IncludeReservedNoopGates) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-relaxed-webgl-validation-gate" "Trusted pass-through command decoder alias for WebGL validation-overhead measurement" @("--viewerRelaxedWebglValidation"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-disable-unneeded-blink-features-gate" "Reserved gate; should remain behaviorally no-op until source experiment exists" @("--viewerDisableUnneededBlinkFeatures"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-direct-gpu-presentation-gate" "Reserved gate; should remain behaviorally no-op until source experiment exists" @("--viewerDirectGpuPresentation"))) | Out-Null
}
if ($Renderer -eq "webgl2" -and $IncludeZeroCopy -and $IncludeReservedNoopGates) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-relaxed-webgl-validation-zero-copy" "Trusted WebGL2 combined relaxed-validation plus zero-copy experiment for needs-suite expansion" @("--viewerRelaxedWebglValidation", "--viewerZeroCopy"))) | Out-Null
}
if ($Renderer -eq "webgl2" -and $IncludeReservedNoopGates) {
  foreach ($Backend in $AngleBackend) {
    if ($Backend -and $Backend -ne "default") {
      $Experiments.Add((New-Experiment "fork-viewer-exp-angle-$Backend-relaxed-webgl-validation" "Trusted WebGL2 ANGLE $Backend plus relaxed-validation interaction experiment" @("--viewerForceAngleBackend", $Backend, "--viewerRelaxedWebglValidation"))) | Out-Null
      if ($IncludeZeroCopy) {
        $Experiments.Add((New-Experiment "fork-viewer-exp-angle-$Backend-relaxed-webgl-validation-zero-copy" "Trusted WebGL2 ANGLE $Backend plus relaxed-validation plus zero-copy interaction experiment" @("--viewerForceAngleBackend", $Backend, "--viewerRelaxedWebglValidation", "--viewerZeroCopy"))) | Out-Null
      }
    }
  }
}
if ($IncludeWebGpuDawnExperiments) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-adapter-d3d11" "Trusted WebGPU adapter override: D3D11" @() @("--use-webgpu-adapter=d3d11"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-delay-flush" "Trusted Dawn D3D11 delayed flush experiment" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_delay_flush_to_gpu"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-unmonitored-fence" "Trusted Dawn D3D11 unmonitored-fence experiment for CPU/GPU wait overhead" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_use_unmonitored_fence"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-disable-fence" "Trusted Dawn D3D11 fence-disable experiment for CPU/GPU wait overhead attribution" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_disable_fence"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-delay-flush-unmonitored-fence" "Trusted Dawn D3D11 delayed-flush plus unmonitored-fence interaction experiment" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-wait-thread-safe" "Trusted Dawn D3D11 thread-safe queue wait experiment for wait/lock overhead attribution" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=wait_is_thread_safe"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-delay-flush-wait-thread-safe" "Trusted Dawn D3D11 delayed-flush plus thread-safe wait interaction experiment" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_delay_flush_to_gpu,wait_is_thread_safe"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-discard-view" "Trusted Dawn D3D11 DiscardView experiment for discarded render-pass attachments" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_use_discard_view"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-disable-cpu-upload-buffers" "Trusted Dawn D3D11 upload-path experiment disabling CPU upload buffers" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_disable_cpu_buffers"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-disable-map-default-buffers" "Trusted Dawn D3D11 upload-path experiment disabling MapOnDefaultBuffers" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=d3d11_disable_map_on_default_buffers"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-auto-map-backend-buffer" "Trusted Dawn D3D11 mappable backend-buffer auto-map experiment for upload-path attribution" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=auto_map_backend_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-dawn-mapped-buffer-clear-skip" "Trusted Dawn mapped-at-creation buffer clear-skip experiment for glTF/resource-upload attribution" @() @("--enable-dawn-features=disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-dawn-use-dxc" "Trusted Dawn DXC shader-compiler experiment for WebGPU pipeline-stall attribution" @() @("--enable-dawn-features=use_dxc"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation" "Trusted Dawn blob-cache hash-validation disable experiment for WebGPU shader/pipeline cache overhead attribution" @() @("--disable-dawn-features=blob_cache_hash_validation"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-dawn-skip-validation" "Unsafe Dawn skip-validation experiment for trusted local WebGPU content" @() @("--enable-dawn-features=skip_validation"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-dawn-disable-robustness" "Unsafe Dawn disable-robustness experiment for trusted local WebGPU content" @() @("--enable-dawn-features=disable_robustness"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-skip-validation" "Unsafe WebGPU D3D11 adapter plus Dawn skip-validation interaction experiment for trusted local draw-call/glTF content" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=skip_validation"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-disable-robustness" "Unsafe WebGPU D3D11 adapter plus Dawn disable-robustness interaction experiment for trusted local draw-call/glTF content" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=disable_robustness"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-skip-validation-disable-robustness" "Unsafe WebGPU D3D11 adapter plus Dawn skip-validation and disable-robustness interaction experiment for trusted local draw-call/glTF content" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=skip_validation,disable_robustness"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d12-toggles" "Trusted Dawn D3D12 heap/render-pass/root-signature toggles" @() @("--enable-dawn-features=d3d12_create_not_zeroed_heap,use_d3d12_resource_heap_tier2,use_d3d12_render_pass,d3d12_use_root_signature_version_1_1"))) | Out-Null
}
if ($IncludeWebGpuChromiumFeatureExperiments) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc" "Trusted WebGPU GPU-channel Mojo feature experiment: RemoveGPULegacyIPC" @() @("--enable-features=RemoveGPULegacyIPC"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-hlsl2021" "Trusted WebGPU shader compiler feature experiment: WebGPUUseHLSL2021" @() @("--enable-features=WebGPUUseHLSL2021"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-disable-range-analysis" "Trusted WebGPU robustness range-analysis disable experiment for shader/pipeline compile overhead attribution" @() @("--disable-features=WebGPUEnableRangeAnalysisForRobustness"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc-hlsl2021" "Trusted combined WebGPU IPC plus HLSL 2021 feature experiment" @() @("--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021"))) | Out-Null
}
if ($IncludeWebGpuUploadExperiments) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-defer-pipeline-flush" "Trusted Blink WebGPU async pipeline creation flush deferral experiment for pipeline-stall attribution" @("--viewerDeferWebgpuPipelineFlush"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-cache-bind-group-layouts" "Trusted Blink WebGPU getBindGroupLayout wrapper-cache experiment for pass and bind-group setup overhead attribution" @("--viewerCacheWebgpuBindGroupLayouts"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-command-labels" "Trusted Blink WebGPU command encoder/pass/buffer Dawn-label skip experiment for per-frame command setup overhead attribution" @("--viewerSkipWebgpuCommandLabels"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-resource-labels" "Trusted Blink WebGPU resource/pipeline Dawn-label skip experiment for Three.js resource setup overhead attribution" @("--viewerSkipWebgpuResourceLabels"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-shader-source-null-check" "Trusted Blink WebGPU shader-source NUL scan skip experiment for shader-heavy startup attribution" @("--viewerSkipWebgpuShaderSourceNullCheck"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-shader-memory-accounting" "Trusted Blink WebGPU shader-module Tint memory-accounting skip experiment for shader-heavy startup and memory attribution" @("--viewerSkipWebgpuShaderMemoryAccounting"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets" "Trusted Blink WebGPU redundant setPipeline skip experiment for pass-encoding overhead attribution" @("--viewerSkipWebgpuRedundantPipelineSets"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets" "Trusted Blink WebGPU redundant zero-dynamic-offset setBindGroup skip experiment for pass-encoding overhead attribution" @("--viewerSkipWebgpuRedundantBindGroupSets"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-redundant-buffer-sets" "Trusted Blink WebGPU redundant setVertexBuffer/setIndexBuffer skip experiment for pass-encoding overhead attribution" @("--viewerSkipWebgpuRedundantBufferSets"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-redundant-render-state-sets" "Trusted Blink WebGPU redundant setViewport/setScissorRect/setStencilReference skip experiment for pass-encoding overhead attribution" @("--viewerSkipWebgpuRedundantRenderStateSets"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-defer-queue-flush" "Trusted Blink WebGPU writeBuffer/writeTexture queue-flush deferral experiment for upload overhead attribution" @("--viewerDeferWebgpuQueueFlush"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-defer-submit-flush" "Trusted Blink WebGPU queue.submit immediate-flush deferral experiment for submit and frame-pacing overhead attribution" @("--viewerDeferWebgpuSubmitFlush"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-canvas-texture-validation" "Trusted Blink WebGPU getCurrentTexture texture-descriptor validation skip experiment for canvas presentation overhead attribution" @("--viewerSkipWebgpuCanvasTextureValidation"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-canvas-memory-accounting" "Trusted Blink WebGPU getCurrentTexture canvas memory-accounting skip experiment for presentation overhead attribution" @("--viewerSkipWebgpuCanvasMemoryAccounting"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion" "Trusted Blink WebGPU copyExternalImageToTexture sRGB color-conversion setup skip experiment for CanvasTexture upload overhead attribution" @("--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerRejectWebgpuCpuTextureFallback"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation" "Trusted Blink WebGPU copyExternalImageToTexture sRGB color-space validation skip experiment for CanvasTexture upload overhead attribution" @("--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerRejectWebgpuCpuTextureFallback"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation" "Trusted Blink WebGPU copyExternalImageToTexture destination-validation skip experiment for CanvasTexture upload overhead attribution" @("--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerRejectWebgpuCpuTextureFallback"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation" "Trusted Blink WebGPU copyExternalImageToTexture source validation skip experiment for CanvasTexture upload overhead attribution" @("--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerRejectWebgpuCpuTextureFallback"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation" "Trusted Blink WebGPU copyExternalImageToTexture copy-size/depth/no-op validation skip experiment for CanvasTexture upload overhead attribution" @("--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerRejectWebgpuCpuTextureFallback"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path" "Trusted Blink WebGPU copyExternalImageToTexture combined CanvasTexture validation/conversion fast-path experiment" @("--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerRejectWebgpuCpuTextureFallback"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-write-texture-layout-validation" "Trusted Blink WebGPU writeTexture buffer-layout validation skip experiment for DataTexture and glTF upload overhead attribution" @("--viewerSkipWebgpuWriteTextureLayoutValidation"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-skip-use-counters" "Trusted Blink WebGPU hot-path UseCounter skip experiment for submit and canvas presentation overhead attribution" @("--viewerSkipWebgpuUseCounters"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-increased-cmd-buffer-slice" "Trusted WebGPU command-buffer parse-slice experiment for submit-heavy scenes" @() @("--enable-features=IncreasedCmdBufferParseSlice"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d-staging-upload" "Trusted WebGPU D3D texture-upload path experiment: disable UpdateSubresource backing upload" @() @("--disable-features=D3DBackingUploadWithUpdateSubresource"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment" "Trusted Dawn D3D12 buffer-texture copy pitch/offset alignment experiment for WebGPU texture-upload blockers" @() @("--enable-dawn-features=d3d12_relax_buffer_texture_copy_pitch_and_offset_alignment"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload" "Trusted combined WebGPU command-buffer parse-slice plus D3D staging-upload experiment" @() @("--enable-features=IncreasedCmdBufferParseSlice", "--disable-features=D3DBackingUploadWithUpdateSubresource"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment-staging-upload" "Trusted combined Dawn D3D12 relaxed copy alignment plus Chromium D3D staging-upload experiment for texture uploads" @() @("--enable-dawn-features=d3d12_relax_buffer_texture_copy_pitch_and_offset_alignment", "--disable-features=D3DBackingUploadWithUpdateSubresource"))) | Out-Null
}
if ($Renderer -eq "webgpu" -and $IncludeWebGpuDawnExperiments -and $IncludeWebGpuChromiumFeatureExperiments) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-remove-gpu-legacy-ipc-hlsl2021" "Trusted WebGPU D3D11 adapter plus combined RemoveGPULegacyIPC and HLSL 2021 feature experiment" @() @("--use-webgpu-adapter=d3d11", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021"))) | Out-Null
}
if ($Renderer -eq "webgpu" -and $IncludeWebGpuDawnExperiments -and $IncludeWebGpuUploadExperiments) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-cmd-slice-d3d-staging-upload" "Trusted WebGPU D3D11 adapter plus command-buffer parse-slice and D3D staging-upload experiment" @() @("--use-webgpu-adapter=d3d11", "--enable-features=IncreasedCmdBufferParseSlice", "--disable-features=D3DBackingUploadWithUpdateSubresource"))) | Out-Null
}
if ($Renderer -eq "webgpu" -and $IncludeWebGpuDawnExperiments -and $IncludeWebGpuChromiumFeatureExperiments -and $IncludeWebGpuUploadExperiments) {
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-ipc-hlsl2021-cmd-slice-staging-upload" "Trusted WebGPU D3D11 adapter plus IPC, HLSL 2021, command-slice, and staging-upload interaction experiment" @() @("--use-webgpu-adapter=d3d11", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice", "--disable-features=D3DBackingUploadWithUpdateSubresource"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, IPC, HLSL 2021, command-slice, and robustness range-analysis interaction experiment" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice", "--disable-features=WebGPUEnableRangeAnalysisForRobustness"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path" "Aggressive trusted WebGPU D3D11 pipeline/submit fast-path experiment for glTF and draw-call blockers" @("--viewerDeferWebgpuPipelineFlush", "--viewerCacheWebgpuBindGroupLayouts", "--viewerSkipWebgpuCommandLabels", "--viewerSkipWebgpuResourceLabels", "--viewerSkipWebgpuShaderSourceNullCheck", "--viewerSkipWebgpuShaderMemoryAccounting", "--viewerSkipWebgpuRedundantPipelineSets", "--viewerSkipWebgpuRedundantBindGroupSets", "--viewerSkipWebgpuRedundantBufferSets", "--viewerSkipWebgpuRedundantRenderStateSets", "--viewerDeferWebgpuQueueFlush", "--viewerDeferWebgpuSubmitFlush", "--viewerSkipWebgpuCanvasTextureValidation", "--viewerSkipWebgpuCanvasMemoryAccounting", "--viewerSkipWebgpuWriteTextureLayoutValidation", "--viewerSkipWebgpuUseCounters") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer,skip_validation,disable_robustness", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice", "--disable-features=WebGPUEnableRangeAnalysisForRobustness"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path" "Aggressive trusted WebGPU D3D11 CanvasTexture upload fast-path experiment for texture-streaming blockers" @("--viewerDeferWebgpuQueueFlush", "--viewerDeferWebgpuSubmitFlush", "--viewerSkipWebgpuCanvasTextureValidation", "--viewerSkipWebgpuCanvasMemoryAccounting", "--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerSkipWebgpuWriteTextureLayoutValidation", "--viewerRejectWebgpuCpuTextureFallback", "--viewerSkipWebgpuUseCounters") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer,skip_validation,disable_robustness", "--enable-features=RemoveGPULegacyIPC,WebGPUUseHLSL2021,IncreasedCmdBufferParseSlice", "--disable-features=WebGPUEnableRangeAnalysisForRobustness,D3DBackingUploadWithUpdateSubresource"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, and mapped-buffer clear-skip interaction experiment" @() @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink async pipeline flush deferral interaction experiment" @("--viewerDeferWebgpuPipelineFlush") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink getBindGroupLayout wrapper-cache interaction experiment" @("--viewerCacheWebgpuBindGroupLayouts") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink command-label skip interaction experiment" @("--viewerSkipWebgpuCommandLabels") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink resource-label skip interaction experiment" @("--viewerSkipWebgpuResourceLabels") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-shader-source-null-check" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink shader-source NUL scan skip interaction experiment" @("--viewerSkipWebgpuShaderSourceNullCheck") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-shader-memory-accounting" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink shader-module memory-accounting skip interaction experiment" @("--viewerSkipWebgpuShaderMemoryAccounting") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink redundant setPipeline skip interaction experiment" @("--viewerSkipWebgpuRedundantPipelineSets") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink redundant zero-dynamic-offset setBindGroup skip interaction experiment" @("--viewerSkipWebgpuRedundantBindGroupSets") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-buffer-sets" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink redundant setVertexBuffer/setIndexBuffer skip interaction experiment" @("--viewerSkipWebgpuRedundantBufferSets") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-render-state-sets" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink redundant render-state set skip interaction experiment" @("--viewerSkipWebgpuRedundantRenderStateSets") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink queue-flush deferral interaction experiment" @("--viewerDeferWebgpuQueueFlush") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink submit-flush deferral interaction experiment" @("--viewerDeferWebgpuSubmitFlush") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink canvas texture validation skip interaction experiment" @("--viewerSkipWebgpuCanvasTextureValidation") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink canvas memory-accounting skip interaction experiment" @("--viewerSkipWebgpuCanvasMemoryAccounting") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-color-conv" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink copyExternalImage sRGB color-conversion setup skip interaction experiment" @("--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerRejectWebgpuCpuTextureFallback") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-colorspace" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink copyExternalImage sRGB color-space validation skip interaction experiment" @("--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerRejectWebgpuCpuTextureFallback") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-validation" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink copyExternalImage destination-validation skip interaction experiment" @("--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerRejectWebgpuCpuTextureFallback") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-source" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink copyExternalImage source-validation skip interaction experiment" @("--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerRejectWebgpuCpuTextureFallback") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-copy-size" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink copyExternalImage copy-size validation skip interaction experiment" @("--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerRejectWebgpuCpuTextureFallback") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-copy-ext-image-fast-path" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and combined copyExternalImage CanvasTexture fast-path interaction experiment" @("--viewerSkipWebgpuCopyExternalImageSourceValidation", "--viewerSkipWebgpuCopyExternalImageColorConversion", "--viewerSkipWebgpuCopyExternalImageColorSpaceValidation", "--viewerSkipWebgpuCopyExternalImageDestValidation", "--viewerSkipWebgpuCopyExternalImageCopySizeValidation", "--viewerRejectWebgpuCpuTextureFallback") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-write-texture-layout-validation" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink writeTexture layout-validation skip interaction experiment" @("--viewerSkipWebgpuWriteTextureLayoutValidation") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
  $Experiments.Add((New-Experiment "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters" "Trusted WebGPU D3D11 DXC, delayed-flush, unmonitored-fence, mapped-buffer clear-skip, and Blink UseCounter skip interaction experiment" @("--viewerSkipWebgpuUseCounters") @("--use-webgpu-adapter=d3d11", "--enable-dawn-features=use_dxc,d3d11_delay_flush_to_gpu,d3d11_use_unmonitored_fence,disable_lazy_clear_for_mapped_at_creation_buffer"))) | Out-Null
}

Apply-ExperimentLabelFilter

if ($Experiments.Count -eq 0) {
  throw "No experiments selected. Add -IncludeDefault, -IncludeAggressiveGpu, -IncludeZeroCopy, -IncludeWebGlCompositorExperiments, -IncludeFramePacingExperiments, -IncludeInProcessGpu, -IncludeSingleProcess, -AngleBackend <value>, -IncludeReservedNoopGates, -IncludeWebGpuDawnExperiments, -IncludeWebGpuChromiumFeatureExperiments, or -IncludeWebGpuUploadExperiments."
}

Invoke-WebGpuExperimentSourceValidation

$ResultFiles = [System.Collections.Generic.List[string]]::new()
foreach ($Experiment in $Experiments) {
  $ExperimentFiles = [System.Collections.Generic.List[string]]::new()
  foreach ($Scene in $Scenes) {
    $Output = Join-Path $RawDir "$($Experiment.Label)-$Scene-$Renderer.json"
    $ExperimentFiles.Add($Output) | Out-Null
    $Command = @(
      "node",
      (Join-Path $Root "scripts\run_benchmark.mjs"),
      "--browser", $Browser,
      "--variant", $Experiment.Label,
      "--scene", $Scene,
      "--renderer", $Renderer,
      "--complexity", [string]$Complexity,
      "--duration", [string]$Duration,
      "--warmup", [string]$Warmup,
      "--forkRevision", $ForkRevision,
      "--viewerMode",
      "--viewerTrustedContent",
      "--output", $Output
    )
    if ($BuildArgs) {
      $Command += @("--buildArgs", $BuildArgs)
    }
    if ($PackageDir) {
      $Command += @("--packageDir", $PackageDir)
    }
    if ($Precompile) {
      $Command += "--precompile"
    }
    if ($PrerenderFrames -gt 0) {
      $Command += @("--prerenderFrames", [string]$PrerenderFrames)
    }
    if ($SettleGpuAfterWarmup) {
      $Command += "--settleGpuAfterWarmup"
    }
    if ($Renderer -eq "webgpu" -and $WebGpuPipelineQuietFrames -gt 0) {
      $Command += @("--pipelineQuietFrames", [string]$WebGpuPipelineQuietFrames)
      $Command += @("--pipelineQuietMaxFrames", [string]([Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames)))
    }
    if ($Renderer -eq "webgpu" -and $WebGpuBundleMode -ne "off") {
      $Command += @("--webgpuBundleMode", $WebGpuBundleMode)
    }
    if ($DisableGpuTiming) {
      $Command += "--disableGpuTiming"
    }
    foreach ($Flag in $Experiment.Flags) {
      $Command += $Flag
    }
    foreach ($BrowserFlag in $Experiment.BrowserFlags) {
      $Command += @("--browser-flag", $BrowserFlag)
    }
    if ($ProfileCacheKey) {
      $Command += @("--userDataDir", (Get-ExperimentUserDataDir $Experiment $Scene), "--profileCacheKey", $ProfileCacheKey)
    }

    if ($PrimeProfileCache) {
      Write-Host "Priming profile cache for $($Experiment.Label) $Scene"
      Invoke-CommandChecked $Command
    }
    Invoke-CommandChecked $Command
  }
  Invoke-BenchmarkSuiteValidation `
    -Variant $Experiment.Label `
    -Files @($ExperimentFiles) `
    -ExpectedChromiumRevision $ChromiumRevision `
    -ExpectedBrowser $Browser `
    -ExpectedBuildArgsHash $BuildArgsHash `
    -ExpectedFlagMetadata (Get-ExperimentExpectedFlagMetadata $Experiment) `
    -RequiredBrowserFlags @($RequiredBrowserFlags + @($Experiment.BrowserFlags))
  foreach ($File in $ExperimentFiles) {
    $ResultFiles.Add($File) | Out-Null
  }
}

$SummaryPath = Join-Path $ReportDir "trusted-experiment-matrix-$Renderer-summary.md"
$SummaryCommand = @(
  "node",
  (Join-Path $Root "scripts\summarize_results.mjs")
)
foreach ($File in $ResultFiles) {
  $SummaryCommand += $File
}
$SummaryCommand += @("--strictEvidence", "--output", $SummaryPath)
Invoke-CommandChecked $SummaryCommand

$ComparePath = Join-Path $ReportDir "trusted-experiment-matrix-$Renderer-comparison.md"
$CompareCommand = @(
  "node",
  (Join-Path $Root "scripts\compare_results.mjs")
)
foreach ($File in $ResultFiles) {
  $CompareCommand += $File
}
$CompareCommand += @("--strictEvidence", "--output", $ComparePath)
Invoke-CommandChecked $CompareCommand

if ($DryRun) {
  Write-TrustedExperimentManifest -Phase "planned"
} else {
  Write-TrustedExperimentManifest -Phase "completed"
}

Write-Host "Trusted experiment matrix completed."

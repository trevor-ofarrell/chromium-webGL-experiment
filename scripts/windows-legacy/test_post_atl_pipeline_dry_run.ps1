[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$Src = Join-Path $Root "src"
$Patch = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
$PatchSeries = @(
  "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch",
  "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"
)
$BuildViewerText = Get-Content (Join-Path $Root "scripts\build_viewer_fork.ps1") -Raw
$PostAtlText = Get-Content (Join-Path $Root "scripts\run_post_atl_pipeline.ps1") -Raw
$AuditText = Get-Content (Join-Path $Root "scripts\audit_artifacts.ps1") -Raw
$OfficialText = Get-Content (Join-Path $Root "scripts\run_official_comparison.ps1") -Raw
$TrustedText = Get-Content (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1") -Raw
$DryRunRefreshRevision = "1111111111111111111111111111111111111111"

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
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
}

function Write-SyntheticBuildProvenance {
  param(
    [string]$OutDir,
    [string]$SourceArgsPath,
    [switch]$ViewerPatchApplied
  )

  $OutFull = Join-Path $Src $OutDir
  $Browser = Join-Path $OutFull "content_shell.exe"
  $Args = Join-Path $OutFull "args.gn"
  $ProvenancePath = Join-Path $OutFull "three_browser_build_provenance.json"
  $Provenance = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    build_started_at = (Get-Date).ToUniversalTime().ToString("o")
    chromium_revision = Get-GitRevision $Src
    out_dir = $OutDir
    target = "content_shell"
    target_artifact = $Browser
    target_artifact_sha256 = Get-Sha256 $Browser
    args_gn = $Args
    args_gn_sha256 = Get-Sha256 $Args
    source_args = $SourceArgsPath
    source_args_sha256 = Get-Sha256 $SourceArgsPath
    build_jobs = 0
    allow_viewer_patch_applied = [bool]$ViewerPatchApplied
    baseline_source_guard_enabled = [bool](-not $ViewerPatchApplied)
    viewer_patch_applies_cleanly = [bool](-not $ViewerPatchApplied)
    viewer_patch_already_applied = [bool]$ViewerPatchApplied
    viewer_patch_series = @($PatchSeries | ForEach-Object {
        [pscustomobject]@{
          path = $_
          exists = $true
          sha256 = Get-Sha256 (Join-Path $Root $_)
          applies_cleanly = [bool](-not $ViewerPatchApplied)
          already_applied = [bool]$ViewerPatchApplied
        }
      })
  }
  $Provenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ProvenancePath -Encoding UTF8
}

function Assert-Matches {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    $Excerpt = if ($Text.Length -gt 1600) { $Text.Substring(0, 1600) + "..." } else { $Text }
    throw "Post-ATL dry-run output did not include $Description. Pattern: $Pattern. Output excerpt: $Excerpt"
  }
}

function Test-GitApply {
  param(
    [string]$PatchPath = $Patch,
    [switch]$Reverse
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Arguments = @("-C", $Src, "apply")
    if ($Reverse) {
      $Arguments += "--reverse"
    }
    $Arguments += @("--check", $PatchPath)
    $null = (& git @Arguments 2>$null)
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Get-PatchState {
  $States = @($PatchSeries | ForEach-Object {
      $PatchPath = Join-Path $Root $_
      [pscustomobject]@{
        Path = $_
        Applies = Test-GitApply -PatchPath $PatchPath
        AlreadyApplied = Test-GitApply -PatchPath $PatchPath -Reverse
      }
    })
  return [pscustomobject]@{
    Applies = @($States | Where-Object { -not $_.Applies }).Count -eq 0
    AlreadyApplied = @($States | Where-Object { $_.AlreadyApplied }).Count -gt 0
    Blocked = @($States | Where-Object { -not $_.Applies -and -not $_.AlreadyApplied }).Count -gt 0
    States = $States
  }
}

function Invoke-PostAtlPipelineDryRun {
  param(
    [switch]$SkipBaselineBuild,
    [switch]$AssumeViewerPatchAlreadyApplied,
    [switch]$OmitAggressiveAngleBackend,
    [switch]$OmitAggressiveWebGl2RelaxedValidation,
    [switch]$OmitAggressiveWebGpuSourceFastPath,
    [switch]$OmitAggressiveWebGpuUploadFastPath,
    [switch]$OmitFinalGate,
    [switch]$OmitTrustedMatrixZeroCopy,
    [switch]$OmitTrustedMatrixWebGlCompositorExperiments,
    [switch]$OmitTrustedMatrixWebGpuChromiumFeatureExperiments,
    [switch]$OmitTrustedMatrixWebGpuUploadExperiments,
    [switch]$OmitTrustedWebGpuDawnMatrix,
    [int]$BuildJobs = 0,
    [string]$AggressiveAngleBackend = "d3d11",
    [string]$TraceRenderer = "",
    [switch]$RejectWebGpuCpuFallbackTrace,
    [string[]]$TrustedMatrixAngleBackend = @(),
    [string]$TrustedMatrixRenderer = "",
    [switch]$TrustedMatrixWebGpuDawnExperiments,
    [switch]$OmitReuseValidResults,
    [string]$WebGpuProfileCacheKey = "",
    [string]$ProfileCacheRoot = "",
    [switch]$PrimeWebGpuProfileCache,
    [int]$WebGpuPipelineQuietFrames = 0,
    [int]$WebGpuPipelineQuietMaxFrames = 30,
    [string]$WebGpuBundleMode = "off",
    [switch]$TraceQueueInstrumentation,
    [switch]$TraceBindGroupInstrumentation,
    [switch]$TracePipelineStateInstrumentation,
    [switch]$TraceBufferStateInstrumentation,
    [switch]$TraceRenderStateInstrumentation,
    [switch]$TraceImmediateInstrumentation
  )

  $Command = @(
    (Join-Path $Root "scripts\run_post_atl_pipeline.ps1"),
    "-RefreshChromiumPin",
    "-RefreshRevision", $DryRunRefreshRevision,
    "-Duration", "120",
    "-Warmup", "20",
    "-IncludeWebGPU",
    "-IncludeAggressiveGpu",
    "-CaptureTrace",
    "-TraceDuration", "1",
    "-TraceWarmup", "1",
    "-TraceStartDelayMs", "1234",
    "-Precompile",
    "-DisableWebGpuTiming",
    "-DisableForkWebGpuTiming",
    "-PrerenderFrames", "2",
    "-SettleGpuAfterWarmup",
    "-RunTrustedExperimentMatrix",
    "-RunTrustedWebGpuDawnMatrix",
    "-RunTargetedBlockerExperiments",
    "-TrustedMatrixInProcessGpu",
    "-TrustedMatrixSingleProcess",
    "-TrustedMatrixReservedNoopGates",
    "-RunLongStability",
    "-LongStabilityDuration", "1",
    "-LongStabilityWarmup", "1",
    "-MaxRssDeltaMb", "128",
    "-MaxRendererResourceDelta", "0",
    "-DryRun"
  )
  if (-not $OmitReuseValidResults) {
    $Command += "-ReuseValidResults"
  }
  if (-not $OmitFinalGate) {
    $Command += "-FinalGate"
  }
  if ($BuildJobs -gt 0) {
    $Command += @("-BuildJobs", "$BuildJobs")
  }
  if (-not $OmitAggressiveAngleBackend) {
    $Command += @("-AggressiveAngleBackend", $AggressiveAngleBackend)
  }
  if (-not $OmitAggressiveWebGl2RelaxedValidation) {
    $Command += "-AggressiveWebGl2RelaxedValidation"
  }
  if (-not $OmitAggressiveWebGpuSourceFastPath) {
    $Command += "-AggressiveWebGpuSourceFastPath"
  }
  if (-not $OmitAggressiveWebGpuUploadFastPath) {
    $Command += "-AggressiveWebGpuUploadFastPath"
  }
  if ($TraceRenderer) {
    $Command += @("-TraceRenderer", $TraceRenderer)
  }
  if ($RejectWebGpuCpuFallbackTrace) {
    $Command += "-RejectWebGpuCpuFallbackTrace"
  }
  if ($TraceQueueInstrumentation) {
    $Command += "-TraceQueueInstrumentation"
  }
  if ($TraceBindGroupInstrumentation) {
    $Command += "-TraceBindGroupInstrumentation"
  }
  if ($TracePipelineStateInstrumentation) {
    $Command += "-TracePipelineStateInstrumentation"
  }
  if ($TraceBufferStateInstrumentation) {
    $Command += "-TraceBufferStateInstrumentation"
  }
  if ($TraceRenderStateInstrumentation) {
    $Command += "-TraceRenderStateInstrumentation"
  }
  if ($TraceImmediateInstrumentation) {
    $Command += "-TraceImmediateInstrumentation"
  }
  if ($TrustedMatrixAngleBackend.Count -gt 0) {
    $Command += "-TrustedMatrixAngleBackend"
    $Command += $TrustedMatrixAngleBackend
  }
  if ($TrustedMatrixRenderer) {
    $Command += @("-TrustedMatrixRenderer", $TrustedMatrixRenderer)
  }
  if (-not $OmitTrustedMatrixZeroCopy) {
    $Command += "-TrustedMatrixZeroCopy"
  }
  if (-not $OmitTrustedMatrixWebGlCompositorExperiments) {
    $Command += "-TrustedMatrixWebGlCompositorExperiments"
  }
  if ($TrustedMatrixWebGpuDawnExperiments) {
    $Command += "-TrustedMatrixWebGpuDawnExperiments"
  }
  if ($WebGpuProfileCacheKey) {
    $Command += @("-WebGpuProfileCacheKey", $WebGpuProfileCacheKey)
  }
  if ($ProfileCacheRoot) {
    $Command += @("-ProfileCacheRoot", $ProfileCacheRoot)
  }
  if ($PrimeWebGpuProfileCache) {
    $Command += "-PrimeWebGpuProfileCache"
  }
  if ($WebGpuPipelineQuietFrames -gt 0) {
    $Command += @("-WebGpuPipelineQuietFrames", [string]$WebGpuPipelineQuietFrames)
    $Command += @("-WebGpuPipelineQuietMaxFrames", [string]$WebGpuPipelineQuietMaxFrames)
  }
  if ($WebGpuBundleMode -ne "off") {
    $Command += @("-WebGpuBundleMode", $WebGpuBundleMode)
  }
  if (-not $OmitTrustedMatrixWebGpuChromiumFeatureExperiments) {
    $Command += "-TrustedMatrixWebGpuChromiumFeatureExperiments"
  }
  if (-not $OmitTrustedMatrixWebGpuUploadExperiments) {
    $Command += "-TrustedMatrixWebGpuUploadExperiments"
  }
  if ($OmitTrustedWebGpuDawnMatrix) {
    $Command = @($Command | Where-Object { $_ -ne "-RunTrustedWebGpuDawnMatrix" })
  }
  if ($SkipBaselineBuild) {
    $Command += "-SkipBaselineBuild"
  }
  if ($AssumeViewerPatchAlreadyApplied) {
    $Command += "-DryRunAssumeViewerPatchAlreadyApplied"
  }
  $CommandArgs = @($Command | Select-Object -Skip 1)
  return & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Command[0] @CommandArgs *>&1
}

function Invoke-PostAtlPipelineExpectFailure {
  param(
    [object[]]$Arguments,
    [string]$Description
  )

  $Command = @((Join-Path $Root "scripts\run_post_atl_pipeline.ps1"))
  $Command += $Arguments
  $CommandArgs = @($Command | Select-Object -Skip 1)
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Command[0] @CommandArgs *>&1
    $ExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($ExitCode -eq 0) {
    throw "Expected post-ATL pipeline failure for $Description."
  }
  return ($Output | ForEach-Object { [string]$_ }) -join "`n"
}

$ChromiumRevision = $DryRunRefreshRevision
$ExpectedForkRevision = Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ChromiumRevision -Root $Root
$InitialPatchState = Get-PatchState
if ($InitialPatchState.Blocked) {
  $BlockedPatches = @($InitialPatchState.States | Where-Object { -not $_.Applies -and -not $_.AlreadyApplied } | ForEach-Object { $_.Path }) -join ", "
  throw "Post-ATL dry-run test requires each viewer patch series entry to either apply cleanly or already be applied. Blocked: $BlockedPatches"
}

$Output = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild:$InitialPatchState.AlreadyApplied

$Text = ($Output | ForEach-Object { [string]$_ }) -join "`n"

Assert-Matches $Text "refresh Chromium pin" "the Chromium pin refresh step"
Assert-Matches $Text "refresh_chromium_pin\.ps1" "the Chromium pin refresh script"
Assert-Matches $Text "-Revision\s+$DryRunRefreshRevision" "the dry-run target Chromium revision handoff"
Assert-Matches $Text "-DryRun" "nested refresh dry-run handoff"
Assert-Matches $Text "Viewer fork revision:\s+$([regex]::Escape($ExpectedForkRevision))" "planned refreshed fork revision"

Assert-Matches $Text "official stock-vs-fork comparison" "the official comparison step"
Assert-Matches $Text "run_official_comparison\.ps1" "the official comparison script"
Assert-Matches $Text "stage stock baseline package" "the baseline package staging step"
Assert-Matches $Text "stage fork viewer package" "the fork package staging step"
Assert-Matches $Text "stage_viewer_package\.ps1" "the package staging script"
Assert-Matches $Text "-PackageDir\s+.*benchmarks\\packages\\baseline-content-shell" "baseline package staging destination"
Assert-Matches $Text "-PackageDir\s+.*benchmarks\\packages\\viewer-default" "fork package staging destination"
Assert-Matches $Text "-BaselinePackageDir\s+.*benchmarks\\packages\\baseline-content-shell" "baseline package handoff to official comparison"
Assert-Matches $Text "-ForkPackageDir\s+.*benchmarks\\packages\\viewer-default" "fork package handoff to official comparison"
Assert-Matches $Text "-IncludeWebGPU" "official WebGPU coverage"
Assert-Matches $Text "-IncludeAggressiveGpu" "official aggressive GPU coverage"
Assert-Matches $Text "-AggressiveAngleBackend\s+d3d11" "official ANGLE backend handoff"
Assert-Matches $Text "-AggressiveWebGl2RelaxedValidation" "official WebGL2 relaxed-validation aggressive profile handoff"
Assert-Matches $Text "-CaptureTrace" "official trace capture handoff"
Assert-Matches $Text "-TraceStartDelayMs\s+1234" "official trace start delay handoff"
Assert-Matches $Text "-DisableWebGpuTiming" "global WebGPU timing disable handoff"
Assert-Matches $Text "-DisableForkWebGpuTiming" "fork WebGPU timing disable handoff"
Assert-Matches $Text "-ReuseValidResults" "official benchmark resume handoff"
Assert-Matches $Text "(?s)official stock-vs-fork comparison.*-Complexity\s+2\b" "official comparison stress complexity handoff"
Assert-Matches $Text "(?s)official stock-vs-fork comparison.*-Precompile\b.*-PrerenderFrames\s+2\b.*-SettleGpuAfterWarmup\b" "official resource warmup GPU-settle handoff"
Assert-Matches $Text "-DryRun" "nested official dry-run handoff"
Assert-Matches $Text "run_blocker_experiments\.ps1\b.*-CaptureTargetedTrace\b.*-RejectWebGpuCpuFallbackTrace\b" "final-gate targeted WebGPU CPU-fallback trace rejection handoff"

$TraceGateOutput = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild:$InitialPatchState.AlreadyApplied -OmitFinalGate -OmitTrustedWebGpuDawnMatrix -TraceRenderer "webgpu" -RejectWebGpuCpuFallbackTrace
$TraceGateText = ($TraceGateOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $TraceGateText "run_official_comparison\.ps1\b.*-CaptureTrace\b.*-TraceRenderer\s+webgpu\b.*-RejectWebGpuCpuFallbackTrace\b" "official WebGPU CPU-fallback trace rejection handoff"
Assert-Matches $TraceGateText "run_blocker_experiments\.ps1\b.*-CaptureTargetedTrace\b.*-RejectWebGpuCpuFallbackTrace\b" "targeted blocker WebGPU CPU-fallback trace rejection handoff"

$TraceAttributionOutput = Invoke-PostAtlPipelineDryRun `
  -SkipBaselineBuild:$InitialPatchState.AlreadyApplied `
  -OmitFinalGate `
  -OmitTrustedWebGpuDawnMatrix `
  -TraceRenderer "webgpu" `
  -TraceQueueInstrumentation `
  -TraceBindGroupInstrumentation `
  -TracePipelineStateInstrumentation `
  -TraceBufferStateInstrumentation `
  -TraceRenderStateInstrumentation `
  -TraceImmediateInstrumentation
$TraceAttributionText = ($TraceAttributionOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $TraceAttributionText "run_blocker_experiments\.ps1\b.*-CaptureTargetedTrace\b.*-TraceQueueInstrumentation\b.*-TraceBindGroupInstrumentation\b.*-TracePipelineStateInstrumentation\b.*-TraceBufferStateInstrumentation\b.*-TraceRenderStateInstrumentation\b.*-TraceImmediateInstrumentation\b" "targeted blocker WebGPU attribution trace handoff"

$ProfileCacheOutput = Invoke-PostAtlPipelineDryRun `
  -SkipBaselineBuild:$InitialPatchState.AlreadyApplied `
  -OmitFinalGate `
  -OmitReuseValidResults `
  -OmitTrustedMatrixZeroCopy `
  -TrustedMatrixRenderer "webgpu" `
  -TrustedMatrixWebGpuDawnExperiments `
  -WebGpuProfileCacheKey "dryrun-postatl-webgpu-cache" `
  -ProfileCacheRoot ".\benchmarks\tmp\postatl-profile-cache" `
  -PrimeWebGpuProfileCache
$ProfileCacheText = ($ProfileCacheOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $ProfileCacheText "run_official_comparison\.ps1\b.*-IncludeWebGPU\b.*-WebGpuProfileCacheKey\s+dryrun-postatl-webgpu-cache\b.*-ProfileCacheRoot\s+\.\\benchmarks\\tmp\\postatl-profile-cache\b.*-PrimeWebGpuProfileCache\b" "official WebGPU profile-cache handoff"
Assert-Matches $ProfileCacheText "(?s)trusted-content experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-Renderer\s+webgpu\b.*-ProfileCacheKey\s+dryrun-postatl-webgpu-cache\b.*-UserDataDirRoot\s+\.\\benchmarks\\tmp\\postatl-profile-cache\b.*-PrimeProfileCache\b" "trusted WebGPU matrix profile-cache handoff"
Assert-Matches $ProfileCacheText "(?s)trusted-content WebGPU Dawn experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-Renderer\s+webgpu\b.*-ProfileCacheKey\s+dryrun-postatl-webgpu-cache\b.*-UserDataDirRoot\s+\.\\benchmarks\\tmp\\postatl-profile-cache\b.*-PrimeProfileCache\b" "trusted WebGPU Dawn matrix profile-cache handoff"
Assert-Matches $ProfileCacheText "run_blocker_experiments\.ps1\b.*-WebGpuProfileCacheKey\s+dryrun-postatl-webgpu-cache\b.*-ProfileCacheRoot\s+\.\\benchmarks\\tmp\\postatl-profile-cache\b.*-PrimeWebGpuProfileCache\b" "targeted blocker WebGPU profile-cache handoff"
if ($ProfileCacheText -match "-ReuseValidResults") {
  throw "Profile-cache priming dry-run unexpectedly kept -ReuseValidResults."
}

$PipelineQuietOutput = Invoke-PostAtlPipelineDryRun `
  -SkipBaselineBuild:$InitialPatchState.AlreadyApplied `
  -OmitFinalGate `
  -OmitReuseValidResults `
  -OmitTrustedMatrixZeroCopy `
  -TraceRenderer "webgpu" `
  -WebGpuPipelineQuietFrames 2 `
  -WebGpuPipelineQuietMaxFrames 12
$PipelineQuietText = ($PipelineQuietOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $PipelineQuietText "run_official_comparison\.ps1\b.*-IncludeWebGPU\b.*-WebGpuPipelineQuietFrames\s+2\b.*-WebGpuPipelineQuietMaxFrames\s+12\b" "official WebGPU pipeline-quiet warmup handoff"
Assert-Matches $PipelineQuietText "(?s)trusted-content WebGPU Dawn experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-Renderer\s+webgpu\b.*-WebGpuPipelineQuietFrames\s+2\b.*-WebGpuPipelineQuietMaxFrames\s+12\b" "trusted WebGPU Dawn matrix pipeline-quiet warmup handoff"
Assert-Matches $PipelineQuietText "run_blocker_experiments\.ps1\b.*-WebGpuPipelineQuietFrames\s+2\b.*-WebGpuPipelineQuietMaxFrames\s+12\b" "targeted blocker WebGPU pipeline-quiet warmup handoff"
if ($PipelineQuietText -match "trusted-content experiment matrix[^\r\n]*run_trusted_experiment_matrix\.ps1\b[^\r\n]*-Renderer\s+webgl2\b[^\r\n]*-WebGpuPipelineQuietFrames") {
  throw "WebGL2 trusted matrix unexpectedly received WebGPU pipeline-quiet warmup flags."
}

$BundleModeOutput = Invoke-PostAtlPipelineDryRun `
  -SkipBaselineBuild:$InitialPatchState.AlreadyApplied `
  -OmitFinalGate `
  -OmitReuseValidResults `
  -OmitTrustedMatrixZeroCopy `
  -TrustedMatrixRenderer "webgpu" `
  -TrustedMatrixWebGpuDawnExperiments `
  -TraceRenderer "webgpu" `
  -WebGpuBundleMode "static"
$BundleModeText = ($BundleModeOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $BundleModeText "run_official_comparison\.ps1\b.*-IncludeWebGPU\b.*-WebGpuBundleMode\s+static\b" "official WebGPU BundleGroup mode handoff"
Assert-Matches $BundleModeText "(?s)trusted-content experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-Renderer\s+webgpu\b.*-WebGpuBundleMode\s+static\b" "trusted WebGPU matrix BundleGroup mode handoff"
Assert-Matches $BundleModeText "(?s)trusted-content WebGPU Dawn experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-Renderer\s+webgpu\b.*-WebGpuBundleMode\s+static\b" "trusted WebGPU Dawn matrix BundleGroup mode handoff"
Assert-Matches $BundleModeText "run_blocker_experiments\.ps1\b.*-WebGpuBundleMode\s+static\b" "targeted blocker WebGPU BundleGroup mode handoff"

Assert-Matches $Text "trusted-content experiment matrix" "the trusted experiment matrix step"
Assert-Matches $Text "run_trusted_experiment_matrix\.ps1" "the trusted experiment matrix script"
Assert-Matches $Text "-BuildArgs\s+.*ReleaseViewerDefault\\args\.gn" "trusted matrix build args handoff"
Assert-Matches $Text "-PackageDir\s+.*benchmarks\\packages\\viewer-default" "trusted matrix package handoff"
Assert-Matches $Text "-ForkRevision\s+$([regex]::Escape($ExpectedForkRevision))" "trusted matrix fork revision handoff"
Assert-Matches $Text "-IncludeDefault" "trusted matrix default experiment"
Assert-Matches $Text "-IncludeAggressiveGpu" "trusted matrix aggressive GPU experiment"
Assert-Matches $Text "-IncludeZeroCopy" "trusted matrix zero-copy experiment"
Assert-Matches $Text "-IncludeWebGlCompositorExperiments" "trusted matrix WebGL2 compositor GPU-resource experiments"
Assert-Matches $Text "-IncludeInProcessGpu" "trusted matrix in-process GPU experiment"
Assert-Matches $Text "-IncludeSingleProcess" "trusted matrix single-process experiment"
Assert-Matches $Text "-IncludeReservedNoopGates" "trusted matrix reserved/no-op and relaxed WebGL gate experiments"
Assert-Matches $Text "-Scenes\s+many-draw-calls,instancing,shader-heavy,texture-streaming,postprocessing,large-static,gltf-loader-stress" "trusted matrix complete scene-list handoff"
Assert-Matches $Text "-AngleBackend\s+d3d11" "trusted matrix ANGLE backend experiment"
Assert-Matches $Text "run_trusted_experiment_matrix\.ps1\b.*-Duration\s+120\b.*-Warmup\s+20\b" "trusted matrix inherits official duration and warmup by default"
Assert-Matches $Text "run_trusted_experiment_matrix\.ps1\b.*-Complexity\s+2\b" "trusted matrix inherits stress complexity by default"
Assert-Matches $Text "-Precompile" "trusted matrix resource warmup flag"
Assert-Matches $Text "-PrerenderFrames\s+2" "trusted matrix prerender frame handoff"
Assert-Matches $Text "-SettleGpuAfterWarmup" "trusted matrix GPU-settle warmup handoff"
Assert-Matches $Text "trusted-content WebGPU Dawn experiment matrix" "the trusted WebGPU Dawn experiment matrix step"
Assert-Matches $Text "(?s)trusted-content WebGPU Dawn experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-Renderer\s+webgpu\b.*-IncludeWebGpuDawnExperiments" "trusted WebGPU Dawn matrix handoff"
Assert-Matches $Text "(?s)trusted-content WebGPU Dawn experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-IncludeWebGpuChromiumFeatureExperiments" "trusted WebGPU Chromium feature matrix handoff"
Assert-Matches $Text "(?s)trusted-content WebGPU Dawn experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-IncludeWebGpuUploadExperiments" "trusted WebGPU upload/command-buffer matrix handoff"
Assert-Matches $Text "(?s)trusted-content WebGPU Dawn experiment matrix.*run_trusted_experiment_matrix\.ps1\b.*-DisableGpuTiming\b" "trusted WebGPU Dawn matrix disables timestamp GPU timing"
if ($Text -match "(?s)trusted-content WebGPU Dawn experiment matrix.*-IncludeZeroCopy") {
  throw "Separate WebGPU Dawn trusted-matrix dry-run unexpectedly included the WebGL2-only zero-copy experiment."
}

Assert-Matches $Text "current candidate speed analysis for targeted blockers" "current candidate-analysis step before targeted blockers"
Assert-Matches $Text "run_current_candidate_analysis\.ps1" "current candidate-analysis script"
Assert-Matches $Text "run_current_candidate_analysis\.ps1\b.*-OfficialManifest\s+\.\\benchmarks\\reports\\official-comparison-manifest\.json" "current candidate-analysis official manifest handoff"
Assert-Matches $Text "run_current_candidate_analysis\.ps1\b.*-InputList\s+\.\\benchmarks\\reports\\post-atl-current-candidate-analysis-inputs\.txt" "current candidate-analysis input-list handoff"
Assert-Matches $Text "run_current_candidate_analysis\.ps1\b.*-Json\s+\.\\benchmarks\\reports\\post-atl-current-candidate-analysis\.json" "current candidate-analysis JSON handoff"
Assert-Matches $Text "run_current_candidate_analysis\.ps1\b.*-ExpectedChromiumRevision\s+$DryRunRefreshRevision" "current candidate-analysis Chromium revision handoff"
Assert-Matches $Text "run_current_candidate_analysis\.ps1\b.*-ExpectedForkRevision\s+$([regex]::Escape($ExpectedForkRevision))" "current candidate-analysis fork revision handoff"
Assert-Matches $Text "run_current_candidate_analysis\.ps1\b.*-RequireCandidateRenderer\s+webgl2,webgpu" "current candidate-analysis renderer gate handoff"
Assert-Matches $Text "run_current_candidate_analysis\.ps1\b.*-CpuFrameRegressionMs\s+0\.5\b.*-RenderSubmissionRegressionMs\s+0\.5\b.*-PipelineCreateRegressionMs\s+1\.0\b" "current candidate-analysis CPU/render-submission/WebGPU pipeline-create regression gates"

Assert-Matches $Text "targeted blocker speed iteration" "the targeted blocker speed-iteration step"
Assert-Matches $Text "run_blocker_experiments\.ps1" "the targeted blocker experiment script"
Assert-Matches $Text "-CandidateAnalysisJson\s+\.\\benchmarks\\reports\\post-atl-current-candidate-analysis\.json" "targeted blocker current candidate-analysis input handoff"
if ($Text -match "iter9-existing-candidate-analysis\.json") {
  throw "Post-ATL targeted blocker dry-run unexpectedly used stale iter9 candidate analysis."
}
Assert-Matches $Text "-BaselineBrowser\s+.*ReleaseBaseline\\content_shell\.exe" "targeted blocker baseline browser handoff"
Assert-Matches $Text "-Browser\s+.*ReleaseViewerDefault\\content_shell\.exe" "targeted blocker fork browser handoff"
Assert-Matches $Text "-ForkRevision\s+$([regex]::Escape($ExpectedForkRevision))" "targeted blocker fork revision handoff"
Assert-Matches $Text "-RunComparableBaselines" "targeted blocker comparable stock baseline handoff"
Assert-Matches $Text "-AnalyzeAfterRun" "targeted blocker post-run analyzer handoff"
Assert-Matches $Text "-PlanSuitePromotionAfterTriage" "targeted blocker suite promotion handoff"
Assert-Matches $Text "-RequireCandidateRenderer\s+webgl2,webgpu" "targeted blocker required renderer gate handoff"
Assert-Matches $Text "-PostRunAnalysisCpuFrameRegressionMs\s+0\.5\b.*-PostRunAnalysisRenderSubmissionRegressionMs\s+0\.5\b.*-PostRunAnalysisPipelineCreateRegressionMs\s+1\.0\b" "targeted blocker CPU/render-submission/WebGPU pipeline-create regression gates"
Assert-Matches $Text "-Complexity\s+2" "targeted blocker complexity handoff"
Assert-Matches $Text "-DisableWebGpuTiming" "targeted blocker WebGPU timestamp timing handoff"
Assert-Matches $Text "-Precompile" "targeted blocker precompile handoff"
Assert-Matches $Text "-PrerenderFrames\s+2" "targeted blocker prerender frame handoff"
Assert-Matches $Text "-SettleGpuAfterWarmup" "targeted blocker GPU-settle warmup handoff"
Assert-Matches $Text "run_blocker_experiments\.ps1\b.*-CaptureTargetedTrace\b.*-TraceDuration\s+1\b.*-TraceWarmup\s+1\b.*-TraceStartDelayMs\s+1234\b" "targeted blocker WebGPU trace capture handoff"

$WebGpuDawnOutput = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild:$InitialPatchState.AlreadyApplied -OmitFinalGate -OmitTrustedMatrixZeroCopy -OmitTrustedWebGpuDawnMatrix -TrustedMatrixRenderer "webgpu" -TrustedMatrixWebGpuDawnExperiments
$WebGpuDawnText = ($WebGpuDawnOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $WebGpuDawnText "-Renderer\s+webgpu" "trusted matrix WebGPU renderer handoff"
Assert-Matches $WebGpuDawnText "-IncludeWebGpuDawnExperiments" "trusted matrix WebGPU Dawn browser-flag experiment handoff"
Assert-Matches $WebGpuDawnText "-IncludeWebGpuChromiumFeatureExperiments" "trusted matrix WebGPU Chromium feature experiment handoff"
Assert-Matches $WebGpuDawnText "-IncludeWebGpuUploadExperiments" "trusted matrix WebGPU upload/command-buffer experiment handoff"
Assert-Matches $WebGpuDawnText "-DisableGpuTiming" "standalone trusted WebGPU matrix disables timestamp GPU timing"
if ($WebGpuDawnText -match "-IncludeZeroCopy") {
  throw "WebGPU Dawn trusted-matrix dry-run unexpectedly included the WebGL2-only zero-copy experiment."
}
if ($WebGpuDawnText -match "-IncludeWebGlCompositorExperiments") {
  throw "WebGPU Dawn trusted-matrix dry-run unexpectedly included the WebGL2-only compositor GPU-resource experiments."
}

$ExplicitAngleOutput = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild:$InitialPatchState.AlreadyApplied -OmitAggressiveAngleBackend -OmitFinalGate -TrustedMatrixAngleBackend "d3d11"
$ExplicitAngleText = ($ExplicitAngleOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $ExplicitAngleText "-AngleBackend\s+d3d11" "explicit trusted matrix D3D11 ANGLE experiment"

$DefaultAngleOutput = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild:$InitialPatchState.AlreadyApplied -OmitAggressiveAngleBackend -OmitFinalGate
$DefaultAngleText = ($DefaultAngleOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $DefaultAngleText "trusted-content experiment matrix" "the trusted experiment matrix step when no official aggressive ANGLE backend is supplied"
Assert-Matches $DefaultAngleText "-AngleBackend\s+d3d11" "default trusted matrix D3D11 ANGLE experiment"
if ($DefaultAngleText -match "-AggressiveAngleBackend\s+d3d11") {
  throw "Default trusted matrix ANGLE dry-run unexpectedly depended on the official aggressive ANGLE backend parameter."
}

$FallbackAngleOutput = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild:$InitialPatchState.AlreadyApplied -AggressiveAngleBackend "vulkan"
$FallbackAngleText = ($FallbackAngleOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $FallbackAngleText "-AggressiveAngleBackend\s+vulkan" "official aggressive ANGLE backend override"
Assert-Matches $FallbackAngleText "-AngleBackend\s+vulkan" "trusted matrix fallback to official aggressive ANGLE backend"
if ($FallbackAngleText -match "-AngleBackend\s+d3d11") {
  throw "Trusted matrix unexpectedly kept the D3D11 default when an official aggressive ANGLE backend override was supplied."
}

$ThrottledBuildOutput = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild:$InitialPatchState.AlreadyApplied -BuildJobs 8
$ThrottledBuildText = ($ThrottledBuildOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $ThrottledBuildText "-Jobs\s+8" "post-ATL build job throttle handoff"

Assert-Matches $Text "stock one-hour stability" "the stock long-stability step"
Assert-Matches $Text "fork one-hour stability" "the fork long-stability step"
Assert-Matches $Text "run_long_stability\.ps1" "the long-stability script"
Assert-Matches $Text "-BuildArgs\s+.*ReleaseBaseline\\args\.gn" "baseline stability build args handoff"
Assert-Matches $Text "-BuildArgs\s+.*ReleaseViewerDefault\\args\.gn" "fork stability build args handoff"
Assert-Matches $Text "-ExpectedChromiumRevision\s+$([regex]::Escape($ChromiumRevision))" "long-stability expected Chromium revision handoff"
Assert-Matches $Text "-Label\s+baseline-content-shell-long-stability" "baseline stability label"
Assert-Matches $Text "-Label\s+fork-viewer-default-long-stability" "fork stability label"
Assert-Matches $Text "-Duration\s+1" "long-stability duration handoff"
Assert-Matches $Text "-Warmup\s+1" "long-stability warmup handoff"
Assert-Matches $Text "-MaxRssDeltaMb\s+128" "long-stability RSS threshold handoff"
Assert-Matches $Text "-MaxRendererResourceDelta\s+0" "long-stability renderer resource threshold handoff"
Assert-Matches $Text "-PackageDir\s+.*benchmarks\\packages\\baseline-content-shell" "baseline stability package handoff"
Assert-Matches $Text "-PackageDir\s+.*benchmarks\\packages\\viewer-default" "fork stability package handoff"
Assert-Matches $Text "-ForkRevision\s+$([regex]::Escape($ExpectedForkRevision))" "fork stability revision handoff"
Assert-Matches $Text "-ViewerMode" "fork stability viewer mode handoff"
Assert-Matches $Text "-ViewerTrustedContent" "fork stability trusted-content handoff"
Assert-Matches $Text "artifact audit" "the final artifact audit step"
Assert-Matches $Text "audit_artifacts\.ps1" "the artifact audit script"
Assert-Matches $Text "-FailOnIncomplete" "final audit completion gate handoff"

if ($Text -match "Checking host and checkout prerequisites") {
  throw "Post-ATL dry-run unexpectedly executed prebuild verification instead of only printing it."
}

Assert-Matches $PostAtlText "powershell\.exe\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File" "PowerShell child script dispatch in the post-ATL pipeline"
Assert-Matches $OfficialText "powershell\.exe\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File" "PowerShell child script dispatch in the official comparison workflow"
Assert-Matches $TrustedText "powershell\.exe\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File" "PowerShell child script dispatch in the trusted experiment workflow"
Assert-Matches $OfficialText "--expectedChromiumRevision" "official suite validation expected Chromium revision gate"
Assert-Matches $TrustedText "--expectedChromiumRevision" "trusted suite validation expected Chromium revision gate"
Assert-Matches $PostAtlText "-ExpectedChromiumRevision" "post-ATL long-stability expected Chromium revision handoff"
Assert-Matches $PostAtlText "DryRunAssumeViewerPatchAlreadyApplied" "non-mutating dry-run patch-state override"
Assert-Matches $PostAtlText "-DryRunAssumeViewerPatchAlreadyApplied is only valid with -DryRun" "dry-run-only guard for patch-state override"
Assert-Matches $PostAtlText "0002-draft-webgpu-queue-trace-attribution\.patch" "post-ATL patch-series state includes WebGPU queue trace patch"
Assert-Matches $PostAtlText "viewer patch series entries are already applied" "baseline source-state guard covers full patch series"
Assert-Matches $BuildViewerText "0002-draft-webgpu-queue-trace-attribution\.patch" "fork build applies the WebGPU queue trace patch"
Assert-Matches $BuildViewerText '\[string\]\$Target\s*=\s*[''"]content_shell[''"]' "fork build accepts the documented target parameter"
Assert-Matches $BuildViewerText '-Target\s+\$Target' "fork build forwards the target parameter to build_chromium"
Assert-Matches $AuditText "viewer_patch_series" "artifact audit checks patch-series build provenance"
Assert-Matches $AuditText "0002-draft-webgpu-queue-trace-attribution\.patch" "artifact audit requires the WebGPU queue trace patch in fork provenance"
Assert-Matches $PostAtlText "-RefreshRevision requires -RefreshChromiumPin" "refresh revision guard"
Assert-Matches $PostAtlText "Assert-SkippedArtifactState" "resume artifact preflight guard"
Assert-Matches $PostAtlText "Assert-FinalGateOptions" "final-gate option preflight"
Assert-Matches $PostAtlText "-FinalGate requires completion-oriented options" "final-gate missing-options failure"
Assert-Matches $PostAtlText "-FinalGate cannot be combined with -SkipOfficialComparison" "final-gate skip-official guard"
Assert-Matches $PostAtlText '\[string\]\$WebGpuProfileCacheKey' "post-ATL WebGPU profile-cache key parameter"
Assert-Matches $PostAtlText "-PrimeWebGpuProfileCache requires -WebGpuProfileCacheKey" "post-ATL profile-cache priming guard"
Assert-Matches $PostAtlText "-PrimeWebGpuProfileCache cannot be combined with -ReuseValidResults" "post-ATL profile-cache priming and reuse guard"
Assert-Matches $PostAtlText "-Jobs" "build-job throttle handoff"
Assert-Matches $PostAtlText "SkipBaselineBuild requires an existing stock baseline binary" "skip-baseline existing binary guard"
Assert-Matches $PostAtlText "SkipForkBuild requires an existing fork binary" "skip-fork existing binary guard"
Assert-Matches $PostAtlText "SkipPackage requires -SkipBaselineBuild" "skip-package requires baseline build reuse guard"
Assert-Matches $PostAtlText "SkipPackage requires -SkipForkBuild" "skip-package requires fork build reuse guard"
Assert-Matches $PostAtlText "SkipPackage requires an existing stock baseline package" "skip-package existing baseline package guard"
Assert-Matches $PostAtlText "SkipPackage requires an existing fork package" "skip-package existing fork package guard"
Assert-Matches $PostAtlText "executable does not match expected browser" "skip-package package executable hash guard"
Assert-Matches $PostAtlText "Assert-ExistingBuildProvenance" "skip-build provenance guard"
Assert-Matches $PostAtlText "build provenance revision mismatch" "skip-build provenance revision guard"
Assert-Matches $PostAtlText "stock baseline evidence must come from an unmodified checkout" "skip-baseline patch-state provenance guard"
Assert-Matches $PostAtlText "does not show patch-series entry applied" "skip-fork full patch-series provenance guard"
Assert-Matches $PostAtlText "does not show patch-series entry applying cleanly to the stock baseline checkout" "skip-baseline full patch-series provenance guard"

$MissingFinalGateOptionsText = Invoke-PostAtlPipelineExpectFailure @(
  "-FinalGate",
  "-DryRun"
) "final gate without completion options"
Assert-Matches $MissingFinalGateOptionsText "-FinalGate requires completion-oriented options" "final-gate missing completion options runtime guard"
foreach ($RequiredFinalGateOption in @(
  "-RefreshChromiumPin",
  "-IncludeWebGPU",
  "-IncludeAggressiveGpu",
  "-AggressiveAngleBackend <backend>",
  "-AggressiveWebGl2RelaxedValidation",
  "-AggressiveWebGpuSourceFastPath",
  "-AggressiveWebGpuUploadFastPath",
  "-CaptureTrace",
  "-DisableWebGpuTiming",
  "-DisableForkWebGpuTiming",
  "-RunTrustedExperimentMatrix",
  "-RunTrustedWebGpuDawnMatrix",
  "-RunTargetedBlockerExperiments",
  "-TrustedMatrixZeroCopy",
  "-TrustedMatrixWebGlCompositorExperiments",
  "-TrustedMatrixWebGpuChromiumFeatureExperiments",
  "-TrustedMatrixWebGpuUploadExperiments",
  "-RunLongStability"
)) {
  Assert-Matches $MissingFinalGateOptionsText ([regex]::Escape($RequiredFinalGateOption)) "final-gate missing option $RequiredFinalGateOption"
}
if ($MissingFinalGateOptionsText -match "refresh Chromium pin|Checking host and checkout prerequisites") {
  throw "Final-gate option preflight ran work before rejecting missing completion options."
}

$PrimeWithoutCacheKeyText = Invoke-PostAtlPipelineExpectFailure @(
  "-PrimeWebGpuProfileCache",
  "-DryRun"
) "profile-cache priming without cache key"
Assert-Matches $PrimeWithoutCacheKeyText "-PrimeWebGpuProfileCache requires -WebGpuProfileCacheKey" "profile-cache priming missing-key runtime guard"
if ($PrimeWithoutCacheKeyText -match "refresh Chromium pin|Checking host and checkout prerequisites") {
  throw "Profile-cache priming preflight ran work before rejecting a missing cache key."
}

$PrimeWithReuseText = Invoke-PostAtlPipelineExpectFailure @(
  "-IncludeWebGPU",
  "-ReuseValidResults",
  "-WebGpuProfileCacheKey", "dryrun-postatl-webgpu-cache",
  "-PrimeWebGpuProfileCache",
  "-DryRun"
) "profile-cache priming with official reuse"
Assert-Matches $PrimeWithReuseText "-PrimeWebGpuProfileCache cannot be combined with -ReuseValidResults" "profile-cache priming rejects official result reuse"
if ($PrimeWithReuseText -match "refresh Chromium pin|Checking host and checkout prerequisites") {
  throw "Profile-cache priming reuse preflight ran work before rejecting incompatible reuse."
}

$SkipOfficialFinalGateText = Invoke-PostAtlPipelineExpectFailure @(
  "-FinalGate",
  "-RefreshChromiumPin",
  "-RefreshRevision", $DryRunRefreshRevision,
  "-IncludeWebGPU",
  "-IncludeAggressiveGpu",
  "-AggressiveAngleBackend", "d3d11",
  "-AggressiveWebGl2RelaxedValidation",
  "-AggressiveWebGpuSourceFastPath",
  "-AggressiveWebGpuUploadFastPath",
  "-CaptureTrace",
  "-RunTrustedExperimentMatrix",
  "-RunTrustedWebGpuDawnMatrix",
  "-TrustedMatrixZeroCopy",
  "-TrustedMatrixWebGlCompositorExperiments",
  "-TrustedMatrixWebGpuChromiumFeatureExperiments",
  "-TrustedMatrixWebGpuUploadExperiments",
  "-TrustedMatrixInProcessGpu",
  "-TrustedMatrixSingleProcess",
  "-TrustedMatrixReservedNoopGates",
  "-RunLongStability",
  "-SkipOfficialComparison",
  "-DryRun"
) "final gate with skipped official comparison"
Assert-Matches $SkipOfficialFinalGateText "-FinalGate cannot be combined with -SkipOfficialComparison" "final-gate skip-official runtime guard"
if ($SkipOfficialFinalGateText -match "refresh Chromium pin|Checking host and checkout prerequisites") {
  throw "Final-gate skip-official preflight ran work before rejecting the incomplete evidence path."
}

$ShortFinalGateDurationText = Invoke-PostAtlPipelineExpectFailure @(
  "-FinalGate",
  "-RefreshChromiumPin",
  "-RefreshRevision", $DryRunRefreshRevision,
  "-Duration", "30",
  "-Warmup", "20",
  "-IncludeWebGPU",
  "-IncludeAggressiveGpu",
  "-AggressiveAngleBackend", "d3d11",
  "-AggressiveWebGl2RelaxedValidation",
  "-AggressiveWebGpuSourceFastPath",
  "-AggressiveWebGpuUploadFastPath",
  "-CaptureTrace",
  "-DisableWebGpuTiming",
  "-DisableForkWebGpuTiming",
  "-RunTrustedExperimentMatrix",
  "-RunTrustedWebGpuDawnMatrix",
  "-RunTargetedBlockerExperiments",
  "-TrustedMatrixZeroCopy",
  "-TrustedMatrixWebGlCompositorExperiments",
  "-TrustedMatrixWebGpuChromiumFeatureExperiments",
  "-TrustedMatrixWebGpuUploadExperiments",
  "-TrustedMatrixInProcessGpu",
  "-TrustedMatrixSingleProcess",
  "-TrustedMatrixReservedNoopGates",
  "-RunLongStability",
  "-DryRun"
) "final gate with short official duration"
Assert-Matches $ShortFinalGateDurationText "-FinalGate requires -Duration >= 120" "final-gate duration floor"
if ($ShortFinalGateDurationText -match "refresh Chromium pin|Checking host and checkout prerequisites") {
  throw "Final-gate duration preflight ran work before rejecting short completion evidence."
}

$ShortFinalGateWarmupText = Invoke-PostAtlPipelineExpectFailure @(
  "-FinalGate",
  "-RefreshChromiumPin",
  "-RefreshRevision", $DryRunRefreshRevision,
  "-Duration", "120",
  "-Warmup", "5",
  "-IncludeWebGPU",
  "-IncludeAggressiveGpu",
  "-AggressiveAngleBackend", "d3d11",
  "-AggressiveWebGl2RelaxedValidation",
  "-AggressiveWebGpuSourceFastPath",
  "-AggressiveWebGpuUploadFastPath",
  "-CaptureTrace",
  "-DisableWebGpuTiming",
  "-DisableForkWebGpuTiming",
  "-RunTrustedExperimentMatrix",
  "-RunTrustedWebGpuDawnMatrix",
  "-RunTargetedBlockerExperiments",
  "-TrustedMatrixZeroCopy",
  "-TrustedMatrixWebGlCompositorExperiments",
  "-TrustedMatrixWebGpuChromiumFeatureExperiments",
  "-TrustedMatrixWebGpuUploadExperiments",
  "-TrustedMatrixInProcessGpu",
  "-TrustedMatrixSingleProcess",
  "-TrustedMatrixReservedNoopGates",
  "-RunLongStability",
  "-DryRun"
) "final gate with short official warmup"
Assert-Matches $ShortFinalGateWarmupText "-FinalGate requires -Warmup >= 20" "final-gate warmup floor"
if ($ShortFinalGateWarmupText -match "refresh Chromium pin|Checking host and checkout prerequisites") {
  throw "Final-gate warmup preflight ran work before rejecting incomplete completion evidence."
}

$MismatchedTargetedComplexityText = Invoke-PostAtlPipelineExpectFailure @(
  "-FinalGate",
  "-RefreshChromiumPin",
  "-RefreshRevision", $DryRunRefreshRevision,
  "-Duration", "120",
  "-Warmup", "20",
  "-Complexity", "2",
  "-TargetedBlockerComplexity", "1",
  "-IncludeWebGPU",
  "-IncludeAggressiveGpu",
  "-AggressiveAngleBackend", "d3d11",
  "-AggressiveWebGl2RelaxedValidation",
  "-AggressiveWebGpuSourceFastPath",
  "-AggressiveWebGpuUploadFastPath",
  "-CaptureTrace",
  "-DisableWebGpuTiming",
  "-DisableForkWebGpuTiming",
  "-RunTrustedExperimentMatrix",
  "-RunTrustedWebGpuDawnMatrix",
  "-RunTargetedBlockerExperiments",
  "-TrustedMatrixZeroCopy",
  "-TrustedMatrixWebGlCompositorExperiments",
  "-TrustedMatrixWebGpuChromiumFeatureExperiments",
  "-TrustedMatrixWebGpuUploadExperiments",
  "-TrustedMatrixInProcessGpu",
  "-TrustedMatrixSingleProcess",
  "-TrustedMatrixReservedNoopGates",
  "-RunLongStability",
  "-DryRun"
) "final gate with easier targeted blocker complexity"
Assert-Matches $MismatchedTargetedComplexityText "-FinalGate requires -TargetedBlockerComplexity to match -Complexity" "final-gate targeted complexity match"
if ($MismatchedTargetedComplexityText -match "refresh Chromium pin|Checking host and checkout prerequisites") {
  throw "Final-gate targeted-complexity preflight ran work before rejecting mismatched blocker evidence."
}

$NonDryRunFailureText = ""
$NonDryRunFailedAsExpected = $false
try {
  $Command = @(
    (Join-Path $Root "scripts\run_post_atl_pipeline.ps1"),
    "-SkipBaselineBuild",
    "-DryRunAssumeViewerPatchAlreadyApplied"
  )
  $CommandArgs = @($Command | Select-Object -Skip 1)
  $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Command[0] @CommandArgs *>&1
} catch {
  $NonDryRunFailedAsExpected = $true
  $NonDryRunFailureText = $_.Exception.Message
}
if (-not $NonDryRunFailedAsExpected) {
  throw "Expected post-ATL dry-run patch-state override to be rejected outside -DryRun."
}
Assert-Matches $NonDryRunFailureText "-DryRunAssumeViewerPatchAlreadyApplied is only valid with -DryRun" "dry-run-only patch-state override runtime guard"

$MissingBaselineOutDir = "out\MissingBaselineResumeGuard-$PID"
$MissingBaselineFailureText = Invoke-PostAtlPipelineExpectFailure @(
  "-BaselineOutDir", $MissingBaselineOutDir,
  "-SkipBaselineBuild",
  "-SkipOfficialComparison"
) "missing skipped baseline binary"
Assert-Matches $MissingBaselineFailureText "SkipBaselineBuild requires an existing stock baseline binary" "skip-baseline missing binary runtime guard"
if ($MissingBaselineFailureText -match "Checking host and checkout prerequisites") {
  throw "Skip-baseline resume guard ran prebuild verification before rejecting the missing baseline binary."
}

$SyntheticBaselineOutDir = "out\PostAtlBaselineResumeGuard-$PID"
$SyntheticForkOutDir = "out\PostAtlForkResumeGuard-$PID"
$MissingForkOutDir = "out\MissingForkResumeGuard-$PID"
$SyntheticBaselineFull = Join-Path $Src $SyntheticBaselineOutDir
$SyntheticForkFull = Join-Path $Src $SyntheticForkOutDir
$MissingForkFull = Join-Path $Src $MissingForkOutDir
$SyntheticBaselineArgsFile = Join-Path $Root "benchmarks\tmp\post-atl-baseline-args-$PID.gn"
$SyntheticForkArgsFile = Join-Path $Root "benchmarks\tmp\post-atl-fork-args-$PID.gn"
$MismatchedBaselinePackage = Join-Path $Root "benchmarks\tmp\post-atl-mismatched-baseline-package-$PID"
$MismatchedForkPackage = Join-Path $Root "benchmarks\tmp\post-atl-mismatched-fork-package-$PID"
try {
  New-Item -ItemType Directory -Path $SyntheticBaselineFull -Force | Out-Null
  New-Item -ItemType Directory -Path $SyntheticForkFull -Force | Out-Null
  New-Item -ItemType Directory -Path (Split-Path $SyntheticBaselineArgsFile -Parent) -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $SyntheticBaselineFull "content_shell.exe") -Value "synthetic-baseline-browser" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $SyntheticBaselineFull "args.gn") -Value "is_debug=false" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $SyntheticForkFull "content_shell.exe") -Value "synthetic-fork-browser" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $SyntheticForkFull "args.gn") -Value "is_debug=false" -Encoding ASCII
  Set-Content -LiteralPath $SyntheticBaselineArgsFile -Value "is_debug=false" -Encoding ASCII
  Set-Content -LiteralPath $SyntheticForkArgsFile -Value "is_debug=false" -Encoding ASCII
  Write-SyntheticBuildProvenance -OutDir $SyntheticBaselineOutDir -SourceArgsPath $SyntheticBaselineArgsFile
  Write-SyntheticBuildProvenance -OutDir $SyntheticForkOutDir -SourceArgsPath $SyntheticForkArgsFile -ViewerPatchApplied

  $MissingForkFailureText = Invoke-PostAtlPipelineExpectFailure @(
    "-BaselineOutDir", $SyntheticBaselineOutDir,
    "-BaselineArgsFile", $SyntheticBaselineArgsFile,
    "-ForkOutDir", $MissingForkOutDir,
    "-SkipBaselineBuild",
    "-SkipForkBuild",
    "-SkipOfficialComparison"
  ) "missing skipped fork binary"
  Assert-Matches $MissingForkFailureText "SkipForkBuild requires an existing fork binary" "skip-fork missing binary runtime guard"
  if ($MissingForkFailureText -match "Checking host and checkout prerequisites") {
    throw "Skip-fork resume guard ran prebuild verification before rejecting the missing fork binary."
  }

  $StaleProvenancePath = Join-Path $SyntheticBaselineFull "three_browser_build_provenance.json"
  $OriginalProvenance = Get-Content -LiteralPath $StaleProvenancePath -Raw
  $StaleProvenance = $OriginalProvenance | ConvertFrom-Json
  $StaleProvenance.chromium_revision = "0000000000000000000000000000000000000000"
  $StaleProvenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StaleProvenancePath -Encoding UTF8
  $StaleProvenanceFailureText = Invoke-PostAtlPipelineExpectFailure @(
    "-BaselineOutDir", $SyntheticBaselineOutDir,
    "-BaselineArgsFile", $SyntheticBaselineArgsFile,
    "-SkipBaselineBuild",
    "-SkipOfficialComparison"
  ) "stale skipped baseline provenance"
  Assert-Matches $StaleProvenanceFailureText "SkipBaselineBuild requires current stock baseline build provenance revision mismatch" "skip-baseline stale provenance runtime guard"
  Set-Content -LiteralPath $StaleProvenancePath -Value $OriginalProvenance -Encoding UTF8

  $ContaminatedProvenance = $OriginalProvenance | ConvertFrom-Json
  $ContaminatedProvenance.allow_viewer_patch_applied = $true
  $ContaminatedProvenance.baseline_source_guard_enabled = $false
  $ContaminatedProvenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StaleProvenancePath -Encoding UTF8
  $ContaminatedProvenanceFailureText = Invoke-PostAtlPipelineExpectFailure @(
    "-BaselineOutDir", $SyntheticBaselineOutDir,
    "-BaselineArgsFile", $SyntheticBaselineArgsFile,
    "-SkipBaselineBuild",
    "-SkipOfficialComparison"
  ) "contaminated skipped baseline provenance"
  Assert-Matches $ContaminatedProvenanceFailureText "stock baseline evidence must not allow patched source" "skip-baseline contaminated provenance runtime guard"
  Set-Content -LiteralPath $StaleProvenancePath -Value $OriginalProvenance -Encoding UTF8

  $ForkProvenancePath = Join-Path $SyntheticForkFull "three_browser_build_provenance.json"
  $OriginalForkProvenance = Get-Content -LiteralPath $ForkProvenancePath -Raw
  $IncompleteForkProvenance = $OriginalForkProvenance | ConvertFrom-Json
  foreach ($PatchEntry in @($IncompleteForkProvenance.viewer_patch_series)) {
    if ($PatchEntry.path -eq "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch") {
      $PatchEntry.already_applied = $false
      $PatchEntry.applies_cleanly = $true
    }
  }
  $IncompleteForkProvenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ForkProvenancePath -Encoding UTF8
  $IncompleteForkProvenanceFailureText = Invoke-PostAtlPipelineExpectFailure @(
    "-BaselineOutDir", $SyntheticBaselineOutDir,
    "-ForkOutDir", $SyntheticForkOutDir,
    "-BaselineArgsFile", $SyntheticBaselineArgsFile,
    "-ForkArgsFile", $SyntheticForkArgsFile,
    "-SkipBaselineBuild",
    "-SkipForkBuild",
    "-SkipOfficialComparison"
  ) "incomplete skipped fork patch-series provenance"
  Assert-Matches $IncompleteForkProvenanceFailureText "does not show patch-series entry\s+applied:\s+chromium_patches\\0002-draft-webgpu-queue-trace-attribution\.patch" "skip-fork incomplete patch-series runtime guard"
  if ($IncompleteForkProvenanceFailureText -match "Checking host and checkout prerequisites") {
    throw "Skip-fork patch-series provenance guard ran prebuild verification before rejecting the incomplete fork build."
  }
  Set-Content -LiteralPath $ForkProvenancePath -Value $OriginalForkProvenance -Encoding UTF8

  $MissingPackageFailureText = Invoke-PostAtlPipelineExpectFailure @(
    "-BaselineOutDir", $SyntheticBaselineOutDir,
    "-ForkOutDir", $SyntheticForkOutDir,
    "-BaselineArgsFile", $SyntheticBaselineArgsFile,
    "-ForkArgsFile", $SyntheticForkArgsFile,
    "-BaselinePackageDir", ".\benchmarks\packages\missing-baseline-resume-guard-$PID",
    "-ForkPackageDir", ".\benchmarks\packages\missing-fork-resume-guard-$PID",
    "-SkipBaselineBuild",
    "-SkipForkBuild",
    "-SkipPackage"
  ) "missing skipped package directories"
  Assert-Matches $MissingPackageFailureText "SkipPackage requires an existing stock baseline package" "skip-package missing package runtime guard"
  if ($MissingPackageFailureText -match "Checking host and checkout prerequisites") {
    throw "Skip-package resume guard ran prebuild verification before rejecting the missing package directory."
  }

  New-Item -ItemType Directory -Path (Join-Path $MismatchedBaselinePackage "viewer") -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $MismatchedForkPackage "viewer") -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $MismatchedBaselinePackage "content_shell.exe") -Value "different-baseline-browser" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $MismatchedBaselinePackage "viewer\index.html") -Value "<!doctype html>" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $MismatchedBaselinePackage "run_viewer.ps1") -Value "Write-Host synthetic" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $MismatchedForkPackage "content_shell.exe") -Value "synthetic-fork-browser" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $MismatchedForkPackage "viewer\index.html") -Value "<!doctype html>" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $MismatchedForkPackage "run_viewer.ps1") -Value "Write-Host synthetic" -Encoding ASCII

  $MismatchedPackageFailureText = Invoke-PostAtlPipelineExpectFailure @(
    "-BaselineOutDir", $SyntheticBaselineOutDir,
    "-ForkOutDir", $SyntheticForkOutDir,
    "-BaselineArgsFile", $SyntheticBaselineArgsFile,
    "-ForkArgsFile", $SyntheticForkArgsFile,
    "-BaselinePackageDir", $MismatchedBaselinePackage,
    "-ForkPackageDir", $MismatchedForkPackage,
    "-SkipBaselineBuild",
    "-SkipForkBuild",
    "-SkipPackage"
  ) "mismatched skipped package executable"
  Assert-Matches $MismatchedPackageFailureText "SkipPackage requires an existing stock baseline package executable does not match\s+expected browser" "skip-package package executable hash runtime guard"
  if ($MismatchedPackageFailureText -match "Checking host and checkout prerequisites") {
    throw "Skip-package resume guard ran prebuild verification before rejecting the mismatched package executable."
  }
} finally {
  foreach ($PathToRemove in @($SyntheticBaselineFull, $SyntheticForkFull, $MissingForkFull, $MismatchedBaselinePackage, $MismatchedForkPackage, $SyntheticBaselineArgsFile, $SyntheticForkArgsFile)) {
    if (Test-Path -LiteralPath $PathToRemove) {
      Remove-Item -LiteralPath $PathToRemove -Recurse -Force
    }
  }
}

$FailureText = ""
$FailedAsExpected = $false
try {
  $null = Invoke-PostAtlPipelineDryRun -AssumeViewerPatchAlreadyApplied
} catch {
  $FailedAsExpected = $true
  $FailureText = $_.Exception.Message
}
if (-not $FailedAsExpected) {
  throw "Expected post-ATL dry-run to reject a baseline build while the viewer patch series is already applied."
}
Assert-Matches $FailureText "Cannot build stock baseline while viewer patch series entries are already applied" "the patched-source baseline-build guard"

$SkipOutput = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild -AssumeViewerPatchAlreadyApplied
$SkipText = ($SkipOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $SkipText "baseline build is skipped" "the patched-source skip-baseline acknowledgement"

$FinalPatchState = Get-PatchState
if ($InitialPatchState.Applies -ne $FinalPatchState.Applies -or $InitialPatchState.AlreadyApplied -ne $FinalPatchState.AlreadyApplied) {
  throw "Post-ATL dry-run patch-state guard test changed the src patch state."
}

Write-Host "Post-ATL pipeline dry-run includes Chromium pin refresh, official comparison, trusted matrix including default D3D11 ANGLE coverage, long-stability, final audit commands, PowerShell child-script dispatch, non-mutating patch-series baseline-build guard, and existing-artifact/hash checks for resume skips."

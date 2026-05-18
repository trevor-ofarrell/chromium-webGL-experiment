[CmdletBinding()]
param(
  [string]$BaselineOutDir = "out\ReleaseBaseline",
  [string]$ForkOutDir = "out\ReleaseViewerDefault",
  [string]$BaselineArgsFile = "build\gn_args\baseline_content_shell.gn",
  [string]$ForkArgsFile = "build\gn_args\fork_safe_content_shell.gn",
  [string]$BaselinePackageDir = ".\benchmarks\packages\baseline-content-shell",
  [string]$ForkPackageDir = ".\benchmarks\packages\viewer-default",
  [switch]$RefreshChromiumPin,
  [string]$RefreshRevision = "",
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
  [switch]$RunTrustedExperimentMatrix,
  [string]$TrustedMatrixRenderer = "webgl2",
  [string[]]$TrustedMatrixScenes = @(
    "many-draw-calls",
    "instancing",
    "shader-heavy",
    "texture-streaming",
    "postprocessing",
    "large-static",
    "gltf-loader-stress"
  ),
  [int]$TrustedMatrixDuration = 60,
  [int]$TrustedMatrixWarmup = 10,
  [string[]]$TrustedMatrixAngleBackend = @(),
  [switch]$TrustedMatrixInProcessGpu,
  [switch]$TrustedMatrixSingleProcess,
  [switch]$TrustedMatrixReservedNoopGates,
  [switch]$RunLongStability,
  [string]$LongStabilityScene = "instancing",
  [string]$LongStabilityRenderer = "webgl2",
  [int]$LongStabilityDuration = 3600,
  [int]$LongStabilityWarmup = 30,
  [double]$MaxRssDeltaMb = 128,
  [double]$MaxRendererResourceDelta = 0,
  [switch]$SkipBaselineBuild,
  [switch]$SkipForkBuild,
  [switch]$SkipPackage,
  [switch]$SkipOfficialComparison,
  [switch]$FinalGate,
  [switch]$DryRunAssumeViewerPatchAlreadyApplied,
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

function Join-SrcOutPath {
  param(
    [string]$OutDir,
    [string]$Leaf
  )
  return Join-Path (Join-Path (Join-Path $Root "src") $OutDir) $Leaf
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

function Invoke-Step {
  param(
    [string]$Name,
    [object[]]$Command
  )

  Write-Host ""
  Write-Host "== $Name =="
  Write-Host (Format-Command $Command)
  if ($DryRun) {
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
    throw "$Name failed with exit code $LASTEXITCODE"
  }
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
  param([string]$ChromiumRevision = "")

  if (-not $ChromiumRevision) {
    $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  }
  $PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
  $PatchHash = Get-ShortSha256 $PatchPath
  return "$ChromiumRevision+viewerpatch-$PatchHash"
}

function Test-ViewerPatchApplyState {
  param([switch]$Reverse)

  $Src = Join-Path $Root "src"
  $PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
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

function Assert-BaselineBuildSourceState {
  if ($DryRunAssumeViewerPatchAlreadyApplied -and -not $DryRun) {
    throw "-DryRunAssumeViewerPatchAlreadyApplied is only valid with -DryRun."
  }

  if ($DryRunAssumeViewerPatchAlreadyApplied) {
    $PatchApplies = $false
    $PatchAlreadyApplied = $true
  } else {
    $PatchApplies = Test-ViewerPatchApplyState
    $PatchAlreadyApplied = Test-ViewerPatchApplyState -Reverse
  }

  if ($PatchApplies) {
    return
  }

  if ($PatchAlreadyApplied) {
    if (-not $SkipBaselineBuild) {
      throw "Cannot build stock baseline while the viewer patch is already applied to src. Revert the viewer patch before running the baseline build, or pass -SkipBaselineBuild only when an existing ReleaseBaseline binary was built from an unmodified checkout."
    }
    Write-Host "Viewer patch is already applied; baseline build is skipped, so the existing baseline binary must be from an unmodified checkout."
    return
  }

  throw "Viewer patch neither applies cleanly nor reverse-applies. Resolve the src checkout state before running the post-ATL pipeline."
}

function Assert-ExistingPipelineFile {
  param(
    [string]$PathValue,
    [string]$Reason
  )

  if ($DryRun) {
    return
  }

  if (-not (Test-Path -LiteralPath $PathValue -PathType Leaf)) {
    throw "$Reason not found: $PathValue"
  }
  $Item = Get-Item -LiteralPath $PathValue
  if ($Item.Length -le 0) {
    throw "$Reason is empty: $PathValue"
  }
}

function Assert-ExistingPipelinePackage {
  param(
    [string]$PathValue,
    [string]$Reason,
    [string]$ExpectedBrowser = ""
  )

  if ($DryRun) {
    return
  }

  if (-not (Test-Path -LiteralPath $PathValue -PathType Container)) {
    throw "$Reason not found: $PathValue"
  }

  foreach ($RequiredRelativePath in @("content_shell.exe", "viewer\index.html", "run_viewer.ps1")) {
    $RequiredPath = Join-Path $PathValue $RequiredRelativePath
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
      throw "$Reason is incomplete; missing $RequiredRelativePath under $PathValue"
    }
  }

  $Files = @(Get-ChildItem -LiteralPath $PathValue -Recurse -File -ErrorAction SilentlyContinue)
  $SizeBytes = ($Files | Measure-Object -Property Length -Sum).Sum
  if ($Files.Count -eq 0 -or $SizeBytes -le 0) {
    throw "$Reason is empty: $PathValue"
  }

  if ($ExpectedBrowser) {
    $PackagedBrowser = Join-Path $PathValue "content_shell.exe"
    $ExpectedBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ExpectedBrowser).Hash
    $PackagedBrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PackagedBrowser).Hash
    if ($PackagedBrowserHash -ne $ExpectedBrowserHash) {
      throw "$Reason executable does not match expected browser: $PackagedBrowser"
    }
  }
}

function Assert-SkippedArtifactState {
  if ($SkipBaselineBuild) {
    Assert-ExistingPipelineFile $BaselineBrowser "SkipBaselineBuild requires an existing stock baseline binary"
    Assert-ExistingPipelineFile $BaselineBuildArgs "SkipBaselineBuild requires existing stock baseline GN args"
  }
  if ($SkipForkBuild) {
    Assert-ExistingPipelineFile $ForkBrowser "SkipForkBuild requires an existing fork binary"
    Assert-ExistingPipelineFile $ForkBuildArgs "SkipForkBuild requires existing fork GN args"
  }
  if ($SkipPackage -and (-not $SkipOfficialComparison -or $RunTrustedExperimentMatrix -or $RunLongStability)) {
    if (-not $SkipBaselineBuild) {
      throw "SkipPackage requires -SkipBaselineBuild when reusing an existing stock baseline package for evidence."
    }
    if (-not $SkipForkBuild) {
      throw "SkipPackage requires -SkipForkBuild when reusing an existing fork package for evidence."
    }
    Assert-ExistingPipelinePackage $BaselinePackageDir "SkipPackage requires an existing stock baseline package" $BaselineBrowser
    Assert-ExistingPipelinePackage $ForkPackageDir "SkipPackage requires an existing fork package" $ForkBrowser
  }
}

$BaselineBrowser = Join-SrcOutPath $BaselineOutDir "content_shell.exe"
$ForkBrowser = Join-SrcOutPath $ForkOutDir "content_shell.exe"
$BaselineBuildArgs = Join-SrcOutPath $BaselineOutDir "args.gn"
$ForkBuildArgs = Join-SrcOutPath $ForkOutDir "args.gn"
$BaselinePackageDir = Resolve-RepoPath $BaselinePackageDir
$ForkPackageDir = Resolve-RepoPath $ForkPackageDir

if ($RefreshRevision -and -not $RefreshChromiumPin) {
  throw "-RefreshRevision requires -RefreshChromiumPin."
}
if ($RefreshRevision -and $RefreshRevision -notmatch "^[0-9a-f]{40}$") {
  throw "Refresh revision must be a 40-character Chromium commit SHA: $RefreshRevision"
}

$PlannedChromiumRevision = ""
if ($RefreshChromiumPin) {
  $RefreshCommand = @(
    (Join-Path $Root "scripts\refresh_chromium_pin.ps1")
  )
  if ($RefreshRevision) {
    $RefreshCommand += @("-Revision", $RefreshRevision)
  }
  if ($DryRun) {
    $RefreshCommand += "-DryRun"
    if ($RefreshRevision) {
      $PlannedChromiumRevision = $RefreshRevision
    }
  }
  Invoke-Step "refresh Chromium pin" $RefreshCommand
}

$ChromiumRevision = if ($PlannedChromiumRevision) { $PlannedChromiumRevision } else { Get-GitRevision (Join-Path $Root "src") }
$ViewerForkRevision = Get-ViewerForkRevision -ChromiumRevision $ChromiumRevision
Write-Host "Viewer fork revision: $ViewerForkRevision"
Assert-BaselineBuildSourceState
Assert-SkippedArtifactState

Invoke-Step "prebuild verification" @(
  (Join-Path $Root "scripts\verify_prebuild.ps1")
)

if (-not $SkipBaselineBuild) {
  Invoke-Step "build stock baseline content_shell" @(
    (Join-Path $Root "scripts\build_chromium.ps1"),
    "-OutDir", $BaselineOutDir,
    "-Target", "content_shell",
    "-ArgsFile", $BaselineArgsFile
  )
}

if (-not $SkipForkBuild) {
  Invoke-Step "build patched viewer fork content_shell" @(
    (Join-Path $Root "scripts\build_viewer_fork.ps1"),
    "-OutDir", $ForkOutDir,
    "-ArgsFile", $ForkArgsFile,
    "-ApplyPatch"
  )
}

if (-not $SkipPackage) {
  Invoke-Step "stage stock baseline package" @(
    (Join-Path $Root "scripts\stage_viewer_package.ps1"),
    "-ChromiumOutDir", (Join-Path (Join-Path $Root "src") $BaselineOutDir),
    "-ViewerDist", (Join-Path $Root "viewer\dist"),
    "-PackageDir", $BaselinePackageDir,
    "-Clean"
  )

  Invoke-Step "stage fork viewer package" @(
    (Join-Path $Root "scripts\stage_viewer_package.ps1"),
    "-ChromiumOutDir", (Join-Path (Join-Path $Root "src") $ForkOutDir),
    "-ViewerDist", (Join-Path $Root "viewer\dist"),
    "-PackageDir", $ForkPackageDir,
    "-Clean"
  )
}

if (-not $SkipOfficialComparison) {
  $OfficialCommand = @(
    (Join-Path $Root "scripts\run_official_comparison.ps1"),
    "-BaselineBrowser", $BaselineBrowser,
    "-ForkBrowser", $ForkBrowser,
    "-BaselineBuildArgs", $BaselineBuildArgs,
    "-ForkBuildArgs", $ForkBuildArgs,
    "-BaselinePackageDir", $BaselinePackageDir,
    "-ForkPackageDir", $ForkPackageDir,
    "-Duration", [string]$Duration,
    "-Warmup", [string]$Warmup
  )
  if ($IncludeWebGPU) {
    $OfficialCommand += "-IncludeWebGPU"
  }
  if ($IncludeAggressiveGpu) {
    $OfficialCommand += "-IncludeAggressiveGpu"
  }
  if ($AggressiveAngleBackend) {
    $OfficialCommand += @("-AggressiveAngleBackend", $AggressiveAngleBackend)
  }
  if ($CaptureTrace) {
    $OfficialCommand += @(
      "-CaptureTrace",
      "-TraceScene", $TraceScene,
      "-TraceRenderer", $TraceRenderer,
      "-TraceDuration", [string]$TraceDuration,
      "-TraceWarmup", [string]$TraceWarmup,
      "-TraceStartDelayMs", [string]$TraceStartDelayMs
    )
  }
  if ($Precompile) {
    $OfficialCommand += "-Precompile"
  }
  if ($PrerenderFrames -gt 0) {
    $OfficialCommand += @("-PrerenderFrames", [string]$PrerenderFrames)
  }
  if ($DryRun) {
    $OfficialCommand += "-DryRun"
  }
  Invoke-Step "official stock-vs-fork comparison" $OfficialCommand
}

if ($RunTrustedExperimentMatrix) {
  $EffectiveTrustedMatrixAngleBackend = @($TrustedMatrixAngleBackend)
  if ($EffectiveTrustedMatrixAngleBackend.Count -eq 0) {
    if ($AggressiveAngleBackend) {
      $EffectiveTrustedMatrixAngleBackend = @($AggressiveAngleBackend)
    } else {
      $EffectiveTrustedMatrixAngleBackend = @("d3d11")
    }
  }

  $TrustedMatrixCommand = @(
    (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1"),
    "-Browser", $ForkBrowser,
    "-BuildArgs", $ForkBuildArgs,
    "-PackageDir", $ForkPackageDir,
    "-ForkRevision", $ViewerForkRevision,
    "-Renderer", $TrustedMatrixRenderer,
    "-Duration", [string]$TrustedMatrixDuration,
    "-Warmup", [string]$TrustedMatrixWarmup,
    "-IncludeDefault",
    "-IncludeAggressiveGpu"
  )
  if ($TrustedMatrixScenes.Count -gt 0) {
    $TrustedMatrixCommand += "-Scenes"
    $TrustedMatrixCommand += $TrustedMatrixScenes
  }
  if ($EffectiveTrustedMatrixAngleBackend.Count -gt 0) {
    $TrustedMatrixCommand += "-AngleBackend"
    $TrustedMatrixCommand += $EffectiveTrustedMatrixAngleBackend
  }
  if ($TrustedMatrixInProcessGpu) {
    $TrustedMatrixCommand += "-IncludeInProcessGpu"
  }
  if ($TrustedMatrixSingleProcess) {
    $TrustedMatrixCommand += "-IncludeSingleProcess"
  }
  if ($TrustedMatrixReservedNoopGates) {
    $TrustedMatrixCommand += "-IncludeReservedNoopGates"
  }
  if ($Precompile) {
    $TrustedMatrixCommand += "-Precompile"
  }
  if ($PrerenderFrames -gt 0) {
    $TrustedMatrixCommand += @("-PrerenderFrames", [string]$PrerenderFrames)
  }
  if ($DryRun) {
    $TrustedMatrixCommand += "-DryRun"
  }
  Invoke-Step "trusted-content experiment matrix" $TrustedMatrixCommand
}

if ($RunLongStability) {
  $BaselineStability = @(
    (Join-Path $Root "scripts\run_long_stability.ps1"),
    "-Browser", $BaselineBrowser,
    "-Renderer", $LongStabilityRenderer,
    "-Scene", $LongStabilityScene,
    "-Duration", [string]$LongStabilityDuration,
    "-Warmup", [string]$LongStabilityWarmup,
    "-Label", "baseline-content-shell-long-stability",
    "-BuildArgs", $BaselineBuildArgs,
    "-PackageDir", $BaselinePackageDir,
    "-ExpectedChromiumRevision", $ChromiumRevision
  )
  if ($MaxRssDeltaMb -ge 0) {
    $BaselineStability += @("-MaxRssDeltaMb", [string]$MaxRssDeltaMb)
  }
  if ($MaxRendererResourceDelta -ge 0) {
    $BaselineStability += @("-MaxRendererResourceDelta", [string]$MaxRendererResourceDelta)
  }
  Invoke-Step "stock one-hour stability" $BaselineStability

  $ForkStability = @(
    (Join-Path $Root "scripts\run_long_stability.ps1"),
    "-Browser", $ForkBrowser,
    "-Renderer", $LongStabilityRenderer,
    "-Scene", $LongStabilityScene,
    "-Duration", [string]$LongStabilityDuration,
    "-Warmup", [string]$LongStabilityWarmup,
    "-Label", "fork-viewer-default-long-stability",
    "-BuildArgs", $ForkBuildArgs,
    "-PackageDir", $ForkPackageDir,
    "-ExpectedChromiumRevision", $ChromiumRevision,
    "-ForkRevision", $ViewerForkRevision,
    "-ViewerMode",
    "-ViewerTrustedContent"
  )
  if ($MaxRssDeltaMb -ge 0) {
    $ForkStability += @("-MaxRssDeltaMb", [string]$MaxRssDeltaMb)
  }
  if ($MaxRendererResourceDelta -ge 0) {
    $ForkStability += @("-MaxRendererResourceDelta", [string]$MaxRendererResourceDelta)
  }
  Invoke-Step "fork one-hour stability" $ForkStability
}

$AuditCommand = @(
  (Join-Path $Root "scripts\audit_artifacts.ps1")
)
if ($FinalGate) {
  $AuditCommand += "-FailOnIncomplete"
}
Invoke-Step "artifact audit" $AuditCommand

Write-Host ""
Write-Host "Post-ATL pipeline finished."

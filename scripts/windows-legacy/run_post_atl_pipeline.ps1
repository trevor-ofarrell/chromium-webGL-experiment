[CmdletBinding()]
param(
  [string]$BaselineOutDir = "out\ReleaseBaseline",
  [string]$ForkOutDir = "out\ReleaseViewerDefault",
  [string]$BaselineArgsFile = "build\gn_args\baseline_content_shell.gn",
  [string]$ForkArgsFile = "build\gn_args\fork_safe_content_shell.gn",
  [int]$BuildJobs = 0,
  [string]$BaselinePackageDir = ".\benchmarks\packages\baseline-content-shell",
  [string]$ForkPackageDir = ".\benchmarks\packages\viewer-default",
  [switch]$RefreshChromiumPin,
  [string]$RefreshRevision = "",
  [int]$Duration = 120,
  [int]$Warmup = 20,
  [double]$Complexity = 2.0,
  [switch]$IncludeWebGPU,
  [switch]$IncludeAggressiveGpu,
  [string]$AggressiveAngleBackend = "",
  [switch]$AggressiveWebGl2RelaxedValidation,
  [switch]$AggressiveWebGl2ZeroCopy,
  [switch]$AggressiveWebGpuSourceFastPath,
  [switch]$AggressiveWebGpuUploadFastPath,
  [switch]$CaptureTrace,
  [string]$TraceScene = "many-draw-calls",
  [string]$TraceRenderer = "webgl2",
  [int]$TraceDuration = 10,
  [int]$TraceWarmup = 2,
  [int]$TraceStartDelayMs = 2000,
  [switch]$RejectWebGpuCpuFallbackTrace,
  [switch]$TraceQueueInstrumentation,
  [switch]$TraceBindGroupInstrumentation,
  [switch]$TracePipelineStateInstrumentation,
  [switch]$TraceBufferStateInstrumentation,
  [switch]$TraceRenderStateInstrumentation,
  [switch]$TraceImmediateInstrumentation,
  [switch]$Precompile,
  [switch]$DisableWebGpuTiming,
  [switch]$DisableForkWebGpuTiming,
  [switch]$ReuseValidResults,
  [int]$PrerenderFrames = 0,
  [switch]$SettleGpuAfterWarmup,
  [int]$WebGpuPipelineQuietFrames = 0,
  [int]$WebGpuPipelineQuietMaxFrames = 30,
  [ValidateSet("off", "static")]
  [string]$WebGpuBundleMode = "off",
  [string]$WebGpuProfileCacheKey = "",
  [string]$ProfileCacheRoot = "",
  [switch]$PrimeWebGpuProfileCache,
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
  [int]$TrustedMatrixDuration = 0,
  [int]$TrustedMatrixWarmup = 0,
  [string[]]$TrustedMatrixAngleBackend = @(),
  [switch]$TrustedMatrixZeroCopy,
  [switch]$TrustedMatrixWebGlCompositorExperiments,
  [switch]$TrustedMatrixInProcessGpu,
  [switch]$TrustedMatrixSingleProcess,
  [switch]$TrustedMatrixReservedNoopGates,
  [switch]$TrustedMatrixWebGpuDawnExperiments,
  [switch]$TrustedMatrixWebGpuChromiumFeatureExperiments,
  [switch]$TrustedMatrixWebGpuUploadExperiments,
  [switch]$RunTrustedWebGpuDawnMatrix,
  [switch]$RunTargetedBlockerExperiments,
  [string]$TargetedBlockerCandidateAnalysisJson = ".\benchmarks\reports\post-atl-current-candidate-analysis.json",
  [string]$TargetedBlockerCandidateAnalysisOutput = ".\benchmarks\reports\post-atl-current-candidate-analysis.md",
  [string]$TargetedBlockerCandidateAnalysisInputList = ".\benchmarks\reports\post-atl-current-candidate-analysis-inputs.txt",
  [double]$TargetedBlockerComplexity = 0.0,
  [switch]$TargetedBlockerIncludeAllDiagnostics,
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
$ViewerPatchSeries = @(
  "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch",
  "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"
)

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

function Get-ViewerForkRevision {
  param([string]$ChromiumRevision = "")

  if (-not $ChromiumRevision) {
    $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  }
  $PatchHash = Get-ViewerPatchSeriesHash
  return "$ChromiumRevision+viewerpatch-$PatchHash"
}

function Test-ViewerPatchApplyState {
  param(
    [string]$PatchRelativePath = "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch",
    [switch]$Reverse
  )

  $Src = Join-Path $Root "src"
  $PatchPath = Join-Path $Root $PatchRelativePath
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

function Get-ViewerPatchSeriesState {
  if ($DryRunAssumeViewerPatchAlreadyApplied) {
    return @($ViewerPatchSeries | ForEach-Object {
      [pscustomobject]@{
        Path = $_
        Applies = $false
        AlreadyApplied = $true
      }
    })
  }

  return @($ViewerPatchSeries | ForEach-Object {
    $PatchRelativePath = $_
    [pscustomobject]@{
      Path = $PatchRelativePath
      Applies = Test-ViewerPatchApplyState -PatchRelativePath $PatchRelativePath
      AlreadyApplied = Test-ViewerPatchApplyState -PatchRelativePath $PatchRelativePath -Reverse
    }
  })
}

function Assert-BaselineBuildSourceState {
  if ($DryRunAssumeViewerPatchAlreadyApplied -and -not $DryRun) {
    throw "-DryRunAssumeViewerPatchAlreadyApplied is only valid with -DryRun."
  }

  $PatchStates = @(Get-ViewerPatchSeriesState)
  $BadPatchStates = @($PatchStates | Where-Object { -not $_.Applies -and -not $_.AlreadyApplied })
  if ($BadPatchStates.Count -gt 0) {
    $BadPatchList = @($BadPatchStates | ForEach-Object { $_.Path }) -join ", "
    throw "Viewer patch series neither applies cleanly nor reverse-applies for: $BadPatchList. Resolve the src checkout state before running the post-ATL pipeline."
  }

  $AppliedPatchStates = @($PatchStates | Where-Object { $_.AlreadyApplied })
  if ($AppliedPatchStates.Count -eq 0) {
    return
  }

  if (-not $SkipBaselineBuild) {
    $AppliedPatchList = @($AppliedPatchStates | ForEach-Object { $_.Path }) -join ", "
    throw "Cannot build stock baseline while viewer patch series entries are already applied to src: $AppliedPatchList. Revert the viewer patch series before running the baseline build, or pass -SkipBaselineBuild only when an existing ReleaseBaseline binary was built from an unmodified checkout."
  }
  Write-Host "Viewer patch series is already applied; baseline build is skipped, so the existing baseline binary must be from an unmodified checkout."
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

function Assert-ExistingBuildProvenance {
  param(
    [string]$OutDir,
    [string]$BrowserPath,
    [string]$BuildArgsPath,
    [string]$SourceArgsPath,
    [string]$Reason,
    [switch]$ExpectViewerPatchApplied
  )

  if ($DryRun) {
    return
  }

  $ProvenancePath = Join-SrcOutPath $OutDir "three_browser_build_provenance.json"
  Assert-ExistingPipelineFile $ProvenancePath "$Reason build provenance"

  try {
    $Provenance = Get-Content -LiteralPath $ProvenancePath -Raw | ConvertFrom-Json
  } catch {
    throw "$Reason build provenance is not valid JSON: $ProvenancePath"
  }

  if ($Provenance.chromium_revision -ne $ChromiumRevision) {
    throw "$Reason build provenance revision mismatch: expected $ChromiumRevision, got $($Provenance.chromium_revision)"
  }
  if ($Provenance.target -ne "content_shell") {
    throw "$Reason build provenance target mismatch: expected content_shell, got $($Provenance.target)"
  }

  $BrowserHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $BrowserPath).Hash.ToLowerInvariant()
  if ([string]$Provenance.target_artifact_sha256 -ne $BrowserHash) {
    throw "$Reason build provenance executable hash does not match $BrowserPath"
  }

  $BuildArgsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $BuildArgsPath).Hash.ToLowerInvariant()
  if ([string]$Provenance.args_gn_sha256 -ne $BuildArgsHash) {
    throw "$Reason build provenance args.gn hash does not match $BuildArgsPath"
  }

  $ResolvedSourceArgsPath = Resolve-RepoPath $SourceArgsPath
  Assert-ExistingPipelineFile $ResolvedSourceArgsPath "$Reason source GN args"
  $SourceArgsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ResolvedSourceArgsPath).Hash.ToLowerInvariant()
  if ([string]$Provenance.source_args_sha256 -ne $SourceArgsHash) {
    throw "$Reason build provenance source args hash does not match $ResolvedSourceArgsPath"
  }

  if ($ExpectViewerPatchApplied) {
    if (-not $Provenance.PSObject.Properties["allow_viewer_patch_applied"] -or $Provenance.allow_viewer_patch_applied -ne $true) {
      throw "$Reason build provenance does not record the viewer-patch-applied build opt-in required for fork evidence."
    }
    if ($Provenance.viewer_patch_already_applied -ne $true) {
      throw "$Reason build provenance does not show the viewer patch applied."
    }
    $RecordedPatchSeries = @($Provenance.viewer_patch_series)
    foreach ($ExpectedPatchPath in $ViewerPatchSeries) {
      $PatchEntry = @($RecordedPatchSeries | Where-Object { $_.path -eq $ExpectedPatchPath } | Select-Object -First 1)
      if ($PatchEntry.Count -ne 1 -or $PatchEntry[0].already_applied -ne $true) {
        throw "$Reason build provenance does not show patch-series entry applied: $ExpectedPatchPath"
      }
    }
  } else {
    if (-not $Provenance.PSObject.Properties["allow_viewer_patch_applied"]) {
      throw "$Reason build provenance predates explicit viewer-patch-applied provenance."
    }
    if ($Provenance.allow_viewer_patch_applied -eq $true) {
      throw "$Reason build provenance was built with -AllowViewerPatchApplied; stock baseline evidence must not allow patched source."
    }
    if (-not $Provenance.PSObject.Properties["baseline_source_guard_enabled"] -or $Provenance.baseline_source_guard_enabled -ne $true) {
      throw "$Reason build provenance does not show the stock baseline source guard enabled."
    }
    if ($Provenance.viewer_patch_already_applied -eq $true) {
      throw "$Reason build provenance shows the viewer patch applied; stock baseline evidence must come from an unmodified checkout."
    }
    $RecordedPatchSeries = @($Provenance.viewer_patch_series)
    foreach ($ExpectedPatchPath in $ViewerPatchSeries) {
      $PatchEntry = @($RecordedPatchSeries | Where-Object { $_.path -eq $ExpectedPatchPath } | Select-Object -First 1)
      if ($PatchEntry.Count -ne 1) {
        throw "$Reason build provenance does not record patch-series entry: $ExpectedPatchPath"
      }
      if ($PatchEntry[0].already_applied -eq $true) {
        throw "$Reason build provenance shows viewer patch-series entry applied: $ExpectedPatchPath"
      }
      if ($PatchEntry[0].applies_cleanly -ne $true) {
        throw "$Reason build provenance does not show patch-series entry applying cleanly to the stock baseline checkout: $ExpectedPatchPath"
      }
    }
    if ($Provenance.viewer_patch_applies_cleanly -ne $true) {
      throw "$Reason build provenance does not show the viewer patch applying cleanly to the stock baseline checkout."
    }
  }
}

function Assert-SkippedArtifactState {
  if ($SkipBaselineBuild) {
    Assert-ExistingPipelineFile $BaselineBrowser "SkipBaselineBuild requires an existing stock baseline binary"
    Assert-ExistingPipelineFile $BaselineBuildArgs "SkipBaselineBuild requires existing stock baseline GN args"
    Assert-ExistingBuildProvenance $BaselineOutDir $BaselineBrowser $BaselineBuildArgs $BaselineArgsFile "SkipBaselineBuild requires current stock baseline"
  }
  if ($SkipForkBuild) {
    Assert-ExistingPipelineFile $ForkBrowser "SkipForkBuild requires an existing fork binary"
    Assert-ExistingPipelineFile $ForkBuildArgs "SkipForkBuild requires existing fork GN args"
    Assert-ExistingBuildProvenance $ForkOutDir $ForkBrowser $ForkBuildArgs $ForkArgsFile "SkipForkBuild requires current fork" -ExpectViewerPatchApplied
  }
  if ($SkipPackage -and (-not $SkipOfficialComparison -or $RunTrustedExperimentMatrix -or $RunTrustedWebGpuDawnMatrix -or $RunLongStability)) {
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

function Assert-FinalGateOptions {
  if (-not $FinalGate) {
    return
  }

  $Missing = [System.Collections.Generic.List[string]]::new()
  if (-not $RefreshChromiumPin) {
    $Missing.Add("-RefreshChromiumPin") | Out-Null
  }
  if (-not $IncludeWebGPU) {
    $Missing.Add("-IncludeWebGPU") | Out-Null
  }
  if (-not $IncludeAggressiveGpu) {
    $Missing.Add("-IncludeAggressiveGpu") | Out-Null
  }
  if (-not $AggressiveAngleBackend) {
    $Missing.Add("-AggressiveAngleBackend <backend>") | Out-Null
  }
  if (-not $AggressiveWebGl2RelaxedValidation) {
    $Missing.Add("-AggressiveWebGl2RelaxedValidation") | Out-Null
  }
  if (-not $AggressiveWebGpuSourceFastPath) {
    $Missing.Add("-AggressiveWebGpuSourceFastPath") | Out-Null
  }
  if (-not $AggressiveWebGpuUploadFastPath) {
    $Missing.Add("-AggressiveWebGpuUploadFastPath") | Out-Null
  }
  if (-not $CaptureTrace) {
    $Missing.Add("-CaptureTrace") | Out-Null
  }
  if (-not $DisableWebGpuTiming) {
    $Missing.Add("-DisableWebGpuTiming") | Out-Null
  }
  if (-not $DisableForkWebGpuTiming) {
    $Missing.Add("-DisableForkWebGpuTiming") | Out-Null
  }
  if (-not $RunTrustedExperimentMatrix) {
    $Missing.Add("-RunTrustedExperimentMatrix") | Out-Null
  }
  if ($TrustedMatrixRenderer -ne "webgl2") {
    $Missing.Add("-TrustedMatrixRenderer webgl2") | Out-Null
  }
  if (-not $TrustedMatrixInProcessGpu) {
    $Missing.Add("-TrustedMatrixInProcessGpu") | Out-Null
  }
  if (-not $TrustedMatrixZeroCopy) {
    $Missing.Add("-TrustedMatrixZeroCopy") | Out-Null
  }
  if (-not $TrustedMatrixWebGlCompositorExperiments) {
    $Missing.Add("-TrustedMatrixWebGlCompositorExperiments") | Out-Null
  }
  if (-not $TrustedMatrixSingleProcess) {
    $Missing.Add("-TrustedMatrixSingleProcess") | Out-Null
  }
  if (-not $TrustedMatrixReservedNoopGates) {
    $Missing.Add("-TrustedMatrixReservedNoopGates") | Out-Null
  }
  if (-not $RunTrustedWebGpuDawnMatrix) {
    $Missing.Add("-RunTrustedWebGpuDawnMatrix") | Out-Null
  }
  if (-not $RunTargetedBlockerExperiments) {
    $Missing.Add("-RunTargetedBlockerExperiments") | Out-Null
  }
  if (-not $TrustedMatrixWebGpuChromiumFeatureExperiments) {
    $Missing.Add("-TrustedMatrixWebGpuChromiumFeatureExperiments") | Out-Null
  }
  if (-not $TrustedMatrixWebGpuUploadExperiments) {
    $Missing.Add("-TrustedMatrixWebGpuUploadExperiments") | Out-Null
  }
  if (-not $RunLongStability) {
    $Missing.Add("-RunLongStability") | Out-Null
  }
  if (-not $BaselinePackageDir) {
    $Missing.Add("-BaselinePackageDir <dir>") | Out-Null
  }
  if (-not $ForkPackageDir) {
    $Missing.Add("-ForkPackageDir <dir>") | Out-Null
  }
  if ($SkipOfficialComparison) {
    throw "-FinalGate cannot be combined with -SkipOfficialComparison because official stock/fork evidence is required."
  }
  if ($Missing.Count -gt 0) {
    throw "-FinalGate requires completion-oriented options: $($Missing -join ', ')"
  }
  if ($Duration -lt 120) {
    throw "-FinalGate requires -Duration >= 120 so completion evidence cannot be produced from a short diagnostic run."
  }
  if ($Warmup -lt 20) {
    throw "-FinalGate requires -Warmup >= 20 so completion evidence cannot be produced without the documented warmup window."
  }
  if ($TargetedBlockerComplexity -gt 0 -and
      [Math]::Abs([double]$TargetedBlockerComplexity - [double]$Complexity) -gt 0.000001) {
    throw "-FinalGate requires -TargetedBlockerComplexity to match -Complexity so blocker triage cannot use an easier scene than the official suite."
  }
}

function New-TrustedMatrixCommand {
  param(
    [string]$Renderer,
    [string[]]$Scenes,
    [int]$DurationSeconds,
    [int]$WarmupSeconds,
    [string[]]$AngleBackend = @(),
    [switch]$IncludeZeroCopy,
    [switch]$IncludeWebGlCompositorExperiments,
    [switch]$IncludeInProcessGpu,
    [switch]$IncludeSingleProcess,
    [switch]$IncludeReservedNoopGates,
    [switch]$IncludeWebGpuDawnExperiments,
    [switch]$IncludeWebGpuChromiumFeatureExperiments,
    [switch]$IncludeWebGpuUploadExperiments,
    [switch]$DisableGpuTiming
  )

  $Command = @(
    (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1"),
    "-Browser", $ForkBrowser,
    "-BuildArgs", $ForkBuildArgs,
    "-PackageDir", $ForkPackageDir,
    "-ForkRevision", $ViewerForkRevision,
    "-Renderer", $Renderer,
    "-Duration", [string]$DurationSeconds,
    "-Warmup", [string]$WarmupSeconds,
    "-Complexity", [string]$Complexity,
    "-IncludeDefault",
    "-IncludeAggressiveGpu"
  )
  if ($Scenes.Count -gt 0) {
    $Command += @("-Scenes", ($Scenes -join ","))
  }
  if ($AngleBackend.Count -gt 0) {
    $Command += @("-AngleBackend", ($AngleBackend -join ","))
  }
  if ($IncludeZeroCopy) {
    $Command += "-IncludeZeroCopy"
  }
  if ($IncludeWebGlCompositorExperiments) {
    $Command += "-IncludeWebGlCompositorExperiments"
  }
  if ($IncludeInProcessGpu) {
    $Command += "-IncludeInProcessGpu"
  }
  if ($IncludeSingleProcess) {
    $Command += "-IncludeSingleProcess"
  }
  if ($IncludeReservedNoopGates) {
    $Command += "-IncludeReservedNoopGates"
  }
  if ($IncludeWebGpuDawnExperiments) {
    $Command += "-IncludeWebGpuDawnExperiments"
  }
  if ($IncludeWebGpuChromiumFeatureExperiments) {
    $Command += "-IncludeWebGpuChromiumFeatureExperiments"
  }
  if ($IncludeWebGpuUploadExperiments) {
    $Command += "-IncludeWebGpuUploadExperiments"
  }
  if ($Precompile) {
    $Command += "-Precompile"
  }
  if ($PrerenderFrames -gt 0) {
    $Command += @("-PrerenderFrames", [string]$PrerenderFrames)
  }
  if ($SettleGpuAfterWarmup) {
    $Command += "-SettleGpuAfterWarmup"
  }
  if ($Renderer -eq "webgpu" -and $WebGpuPipelineQuietFrames -gt 0) {
    $Command += @("-WebGpuPipelineQuietFrames", [string]$WebGpuPipelineQuietFrames)
    $Command += @("-WebGpuPipelineQuietMaxFrames", [string]([Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames)))
  }
  if ($Renderer -eq "webgpu" -and $WebGpuBundleMode -ne "off") {
    $Command += @("-WebGpuBundleMode", $WebGpuBundleMode)
  }
  if ($DisableGpuTiming) {
    $Command += "-DisableGpuTiming"
  }
  if ($Renderer -eq "webgpu" -and $WebGpuProfileCacheKey) {
    $Command += @("-ProfileCacheKey", $WebGpuProfileCacheKey)
    if ($ProfileCacheRoot) {
      $Command += @("-UserDataDirRoot", $ProfileCacheRoot)
    }
    if ($PrimeWebGpuProfileCache) {
      $Command += "-PrimeProfileCache"
    }
  }
  if ($DryRun) {
    $Command += "-DryRun"
  }
  return $Command
}

function New-TargetedBlockerExperimentsCommand {
  $Command = @(
    (Join-Path $Root "scripts\run_blocker_experiments.ps1"),
    "-CandidateAnalysisJson", $TargetedBlockerCandidateAnalysisJson,
    "-BaselineBrowser", $BaselineBrowser,
    "-BaselineBuildArgs", $BaselineBuildArgs,
    "-BaselinePackageDir", $BaselinePackageDir,
    "-Browser", $ForkBrowser,
    "-BuildArgs", $ForkBuildArgs,
    "-PackageDir", $ForkPackageDir,
    "-Duration", [string]$Duration,
    "-Warmup", [string]$Warmup,
    "-Complexity", [string]$EffectiveTargetedBlockerComplexity,
    "-ForkRevision", $ViewerForkRevision,
    "-RunComparableBaselines",
    "-AnalyzeAfterRun",
    "-PlanSuitePromotionAfterTriage",
    "-RequireCandidateRenderer", "webgl2,webgpu",
    "-PostRunAnalysisDroppedFramesRegression", "0.0",
    "-PostRunAnalysisCpuFrameRegressionMs", "0.5",
    "-PostRunAnalysisRenderSubmissionRegressionMs", "0.5",
    "-PostRunAnalysisPipelineCreateRegressionMs", "1.0"
  )
  if ($DisableWebGpuTiming -or $DisableForkWebGpuTiming) {
    $Command += "-DisableWebGpuTiming"
  }
  if ($Precompile) {
    $Command += "-Precompile"
  }
  if ($PrerenderFrames -gt 0) {
    $Command += @("-PrerenderFrames", [string]$PrerenderFrames)
  }
  if ($SettleGpuAfterWarmup) {
    $Command += "-SettleGpuAfterWarmup"
  }
  if ($WebGpuPipelineQuietFrames -gt 0) {
    $Command += @("-WebGpuPipelineQuietFrames", [string]$WebGpuPipelineQuietFrames)
    $Command += @("-WebGpuPipelineQuietMaxFrames", [string]([Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames)))
  }
  if ($WebGpuBundleMode -ne "off") {
    $Command += @("-WebGpuBundleMode", $WebGpuBundleMode)
  }
  if ($TargetedBlockerIncludeAllDiagnostics) {
    $Command += "-IncludeAllBlockerDiagnostics"
  }
  if ($WebGpuProfileCacheKey) {
    $Command += @("-WebGpuProfileCacheKey", $WebGpuProfileCacheKey)
    if ($ProfileCacheRoot) {
      $Command += @("-ProfileCacheRoot", $ProfileCacheRoot)
    }
    if ($PrimeWebGpuProfileCache) {
      $Command += "-PrimeWebGpuProfileCache"
    }
  }
  if ($CaptureTrace -and $IncludeWebGPU) {
    $Command += @(
      "-CaptureTargetedTrace",
      "-TraceDuration", [string]$TraceDuration,
      "-TraceWarmup", [string]$TraceWarmup,
      "-TraceStartDelayMs", [string]$TraceStartDelayMs
    )
    if ($RejectWebGpuCpuFallbackTrace -or $FinalGate) {
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
  }
  if ($DryRun) {
    $Command += "-DryRun"
  }
  return $Command
}

function New-CurrentCandidateAnalysisCommand {
  $Command = @(
    (Join-Path $Root "scripts\run_current_candidate_analysis.ps1"),
    "-OfficialManifest", ".\benchmarks\reports\official-comparison-manifest.json",
    "-InputList", $TargetedBlockerCandidateAnalysisInputList,
    "-Output", $TargetedBlockerCandidateAnalysisOutput,
    "-Json", $TargetedBlockerCandidateAnalysisJson,
    "-MinMeasuredSeconds", [string]([Math]::Min(30, $Duration)),
    "-MinAvgFpsDeltaPct", "0.5",
    "-SceneRegressionPct", "1.0",
    "-DroppedFramesRegression", "0.0",
    "-CpuFrameRegressionMs", "0.5",
    "-RenderSubmissionRegressionMs", "0.5",
    "-PipelineCreateRegressionMs", "1.0",
    "-ExpectedChromiumRevision", $ChromiumRevision,
    "-ExpectedForkRevision", $ViewerForkRevision,
    "-RequireCandidateRenderer", "webgl2,webgpu"
  )
  return $Command
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
if ($ProfileCacheRoot -and -not $WebGpuProfileCacheKey) {
  throw "-ProfileCacheRoot requires -WebGpuProfileCacheKey."
}
if ($PrimeWebGpuProfileCache -and -not $WebGpuProfileCacheKey) {
  throw "-PrimeWebGpuProfileCache requires -WebGpuProfileCacheKey."
}
if ($PrimeWebGpuProfileCache -and $ReuseValidResults -and -not $SkipOfficialComparison -and $IncludeWebGPU) {
  throw "-PrimeWebGpuProfileCache cannot be combined with -ReuseValidResults when the official WebGPU comparison runs because the measured pass must rerun after priming."
}
if ($WebGpuPipelineQuietFrames -lt 0 -or $WebGpuPipelineQuietMaxFrames -lt 0) {
  throw "-WebGpuPipelineQuietFrames and -WebGpuPipelineQuietMaxFrames must be non-negative."
}
if ($WebGpuBundleMode -ne "off" -and -not (
    $IncludeWebGPU -or
    ($CaptureTrace -and $TraceRenderer -eq "webgpu") -or
    ($RunTrustedExperimentMatrix -and $TrustedMatrixRenderer -eq "webgpu") -or
    $RunTrustedWebGpuDawnMatrix -or
    $RunTargetedBlockerExperiments
  )) {
  throw "-WebGpuBundleMode requires WebGPU official, trace, trusted-matrix, or targeted-blocker work."
}
if ($Complexity -le 0) {
  throw "-Complexity must be greater than zero."
}
if ($TargetedBlockerComplexity -lt 0) {
  throw "-TargetedBlockerComplexity must be greater than zero when supplied."
}
$EffectiveTargetedBlockerComplexity = if ($TargetedBlockerComplexity -gt 0) { $TargetedBlockerComplexity } else { $Complexity }
Assert-FinalGateOptions

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
  $BaselineBuildCommand = @(
    (Join-Path $Root "scripts\build_chromium.ps1"),
    "-OutDir", $BaselineOutDir,
    "-Target", "content_shell",
    "-ArgsFile", $BaselineArgsFile,
    "-OverwriteArgs"
  )
  if ($BuildJobs -gt 0) {
    $BaselineBuildCommand += @("-Jobs", "$BuildJobs")
  }
  Invoke-Step "build stock baseline content_shell" $BaselineBuildCommand
}

if (-not $SkipForkBuild) {
  $ForkBuildCommand = @(
    (Join-Path $Root "scripts\build_viewer_fork.ps1"),
    "-OutDir", $ForkOutDir,
    "-ArgsFile", $ForkArgsFile,
    "-ApplyPatch",
    "-OverwriteArgs"
  )
  if ($BuildJobs -gt 0) {
    $ForkBuildCommand += @("-Jobs", "$BuildJobs")
  }
  Invoke-Step "build patched viewer fork content_shell" $ForkBuildCommand
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
    "-Warmup", [string]$Warmup,
    "-Complexity", [string]$Complexity
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
  if ($AggressiveWebGl2RelaxedValidation) {
    $OfficialCommand += "-AggressiveWebGl2RelaxedValidation"
  }
  if ($AggressiveWebGl2ZeroCopy) {
    $OfficialCommand += "-AggressiveWebGl2ZeroCopy"
  }
  if ($AggressiveWebGpuSourceFastPath) {
    $OfficialCommand += "-AggressiveWebGpuSourceFastPath"
  }
  if ($AggressiveWebGpuUploadFastPath) {
    $OfficialCommand += "-AggressiveWebGpuUploadFastPath"
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
  if ($RejectWebGpuCpuFallbackTrace) {
    $OfficialCommand += "-RejectWebGpuCpuFallbackTrace"
  }
  if ($Precompile) {
    $OfficialCommand += "-Precompile"
  }
  if ($DisableWebGpuTiming) {
    $OfficialCommand += "-DisableWebGpuTiming"
  }
  if ($DisableForkWebGpuTiming) {
    $OfficialCommand += "-DisableForkWebGpuTiming"
  }
  if ($ReuseValidResults) {
    $OfficialCommand += "-ReuseValidResults"
  }
  if ($PrerenderFrames -gt 0) {
    $OfficialCommand += @("-PrerenderFrames", [string]$PrerenderFrames)
  }
  if ($SettleGpuAfterWarmup) {
    $OfficialCommand += "-SettleGpuAfterWarmup"
  }
  if (($IncludeWebGPU -or ($CaptureTrace -and $TraceRenderer -eq "webgpu")) -and $WebGpuPipelineQuietFrames -gt 0) {
    $OfficialCommand += @("-WebGpuPipelineQuietFrames", [string]$WebGpuPipelineQuietFrames)
    $OfficialCommand += @("-WebGpuPipelineQuietMaxFrames", [string]([Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames)))
  }
  if (($IncludeWebGPU -or ($CaptureTrace -and $TraceRenderer -eq "webgpu")) -and $WebGpuBundleMode -ne "off") {
    $OfficialCommand += @("-WebGpuBundleMode", $WebGpuBundleMode)
  }
  if ($WebGpuProfileCacheKey) {
    $OfficialCommand += @("-WebGpuProfileCacheKey", $WebGpuProfileCacheKey)
    if ($ProfileCacheRoot) {
      $OfficialCommand += @("-ProfileCacheRoot", $ProfileCacheRoot)
    }
    if ($PrimeWebGpuProfileCache) {
      $OfficialCommand += "-PrimeWebGpuProfileCache"
    }
  }
  if ($DryRun) {
    $OfficialCommand += "-DryRun"
  }
  Invoke-Step "official stock-vs-fork comparison" $OfficialCommand
}

if ($RunTrustedExperimentMatrix -or $RunTrustedWebGpuDawnMatrix) {
  $EffectiveTrustedMatrixDuration = if ($TrustedMatrixDuration -gt 0) { $TrustedMatrixDuration } else { $Duration }
  $EffectiveTrustedMatrixWarmup = if ($TrustedMatrixWarmup -gt 0) { $TrustedMatrixWarmup } else { $Warmup }
  $EffectiveTrustedMatrixAngleBackend = @($TrustedMatrixAngleBackend)
  if ($EffectiveTrustedMatrixAngleBackend.Count -eq 0) {
    if ($AggressiveAngleBackend) {
      $EffectiveTrustedMatrixAngleBackend = @($AggressiveAngleBackend)
    } else {
      $EffectiveTrustedMatrixAngleBackend = @("d3d11")
    }
  }
}

if ($RunTrustedExperimentMatrix) {
  $TrustedMatrixCommand = New-TrustedMatrixCommand `
    -Renderer $TrustedMatrixRenderer `
    -Scenes @($TrustedMatrixScenes) `
    -DurationSeconds $EffectiveTrustedMatrixDuration `
    -WarmupSeconds $EffectiveTrustedMatrixWarmup `
    -AngleBackend @($EffectiveTrustedMatrixAngleBackend) `
    -IncludeZeroCopy:$TrustedMatrixZeroCopy `
    -IncludeWebGlCompositorExperiments:($TrustedMatrixRenderer -eq "webgl2" -and $TrustedMatrixWebGlCompositorExperiments) `
    -IncludeInProcessGpu:$TrustedMatrixInProcessGpu `
    -IncludeSingleProcess:$TrustedMatrixSingleProcess `
    -IncludeReservedNoopGates:$TrustedMatrixReservedNoopGates `
    -IncludeWebGpuDawnExperiments:$TrustedMatrixWebGpuDawnExperiments `
    -IncludeWebGpuChromiumFeatureExperiments:($TrustedMatrixRenderer -eq "webgpu" -and $TrustedMatrixWebGpuChromiumFeatureExperiments) `
    -IncludeWebGpuUploadExperiments:($TrustedMatrixRenderer -eq "webgpu" -and $TrustedMatrixWebGpuUploadExperiments) `
    -DisableGpuTiming:($TrustedMatrixRenderer -eq "webgpu" -and ($DisableWebGpuTiming -or $DisableForkWebGpuTiming))
  Invoke-Step "trusted-content experiment matrix" $TrustedMatrixCommand
}

if ($RunTrustedWebGpuDawnMatrix) {
  $WebGpuDawnCommand = New-TrustedMatrixCommand `
    -Renderer "webgpu" `
    -Scenes @($TrustedMatrixScenes) `
    -DurationSeconds $EffectiveTrustedMatrixDuration `
    -WarmupSeconds $EffectiveTrustedMatrixWarmup `
    -AngleBackend @() `
    -IncludeZeroCopy:$false `
    -IncludeWebGlCompositorExperiments:$false `
    -IncludeInProcessGpu:$TrustedMatrixInProcessGpu `
    -IncludeSingleProcess:$TrustedMatrixSingleProcess `
    -IncludeReservedNoopGates:$false `
    -IncludeWebGpuDawnExperiments `
    -IncludeWebGpuChromiumFeatureExperiments:$TrustedMatrixWebGpuChromiumFeatureExperiments `
    -IncludeWebGpuUploadExperiments:$TrustedMatrixWebGpuUploadExperiments `
    -DisableGpuTiming:($DisableWebGpuTiming -or $DisableForkWebGpuTiming)
  Invoke-Step "trusted-content WebGPU Dawn experiment matrix" $WebGpuDawnCommand
}

if ($RunTargetedBlockerExperiments) {
  Invoke-Step "current candidate speed analysis for targeted blockers" (New-CurrentCandidateAnalysisCommand)
  Invoke-Step "targeted blocker speed iteration" (New-TargetedBlockerExperimentsCommand)
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

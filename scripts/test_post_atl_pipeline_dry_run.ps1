[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$Patch = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
$PostAtlText = Get-Content (Join-Path $Root "scripts\run_post_atl_pipeline.ps1") -Raw
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
    viewer_patch_applies_cleanly = [bool](-not $ViewerPatchApplied)
    viewer_patch_already_applied = [bool]$ViewerPatchApplied
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
    throw "Post-ATL dry-run output did not include $Description. Pattern: $Pattern"
  }
}

function Test-GitApply {
  param([switch]$Reverse)

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Arguments = @("-C", $Src, "apply")
    if ($Reverse) {
      $Arguments += "--reverse"
    }
    $Arguments += @("--check", $Patch)
    $null = (& git @Arguments 2>$null)
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Get-PatchState {
  return [pscustomobject]@{
    Applies = Test-GitApply
    AlreadyApplied = Test-GitApply -Reverse
  }
}

function Invoke-PostAtlPipelineDryRun {
  param(
    [switch]$SkipBaselineBuild,
    [switch]$AssumeViewerPatchAlreadyApplied,
    [switch]$OmitAggressiveAngleBackend,
    [switch]$OmitFinalGate,
    [int]$BuildJobs = 0,
    [string]$AggressiveAngleBackend = "d3d11",
    [string[]]$TrustedMatrixAngleBackend = @()
  )

  $Command = @(
    (Join-Path $Root "scripts\run_post_atl_pipeline.ps1"),
    "-RefreshChromiumPin",
    "-RefreshRevision", $DryRunRefreshRevision,
    "-Duration", "1",
    "-Warmup", "1",
    "-IncludeWebGPU",
    "-IncludeAggressiveGpu",
    "-CaptureTrace",
    "-TraceDuration", "1",
    "-TraceWarmup", "1",
    "-TraceStartDelayMs", "1234",
    "-Precompile",
    "-DisableWebGpuTiming",
    "-DisableForkWebGpuTiming",
    "-ReuseValidResults",
    "-PrerenderFrames", "2",
    "-RunTrustedExperimentMatrix",
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
  if (-not $OmitFinalGate) {
    $Command += "-FinalGate"
  }
  if ($BuildJobs -gt 0) {
    $Command += @("-BuildJobs", "$BuildJobs")
  }
  if (-not $OmitAggressiveAngleBackend) {
    $Command += @("-AggressiveAngleBackend", $AggressiveAngleBackend)
  }
  if ($TrustedMatrixAngleBackend.Count -gt 0) {
    $Command += "-TrustedMatrixAngleBackend"
    $Command += $TrustedMatrixAngleBackend
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

$PatchHash = Get-ShortSha256 (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch")
$ChromiumRevision = $DryRunRefreshRevision
$ExpectedForkRevision = "$ChromiumRevision+viewerpatch-$PatchHash"
$InitialPatchState = Get-PatchState
if (-not $InitialPatchState.Applies -and -not $InitialPatchState.AlreadyApplied) {
  throw "Post-ATL dry-run test requires the viewer patch to either apply cleanly or already be applied."
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
Assert-Matches $Text "-CaptureTrace" "official trace capture handoff"
Assert-Matches $Text "-TraceStartDelayMs\s+1234" "official trace start delay handoff"
Assert-Matches $Text "-DisableWebGpuTiming" "global WebGPU timing disable handoff"
Assert-Matches $Text "-DisableForkWebGpuTiming" "fork WebGPU timing disable handoff"
Assert-Matches $Text "-ReuseValidResults" "official benchmark resume handoff"
Assert-Matches $Text "-DryRun" "nested official dry-run handoff"

Assert-Matches $Text "trusted-content experiment matrix" "the trusted experiment matrix step"
Assert-Matches $Text "run_trusted_experiment_matrix\.ps1" "the trusted experiment matrix script"
Assert-Matches $Text "-BuildArgs\s+.*ReleaseViewerDefault\\args\.gn" "trusted matrix build args handoff"
Assert-Matches $Text "-PackageDir\s+.*benchmarks\\packages\\viewer-default" "trusted matrix package handoff"
Assert-Matches $Text "-ForkRevision\s+$([regex]::Escape($ExpectedForkRevision))" "trusted matrix fork revision handoff"
Assert-Matches $Text "-IncludeDefault" "trusted matrix default experiment"
Assert-Matches $Text "-IncludeAggressiveGpu" "trusted matrix aggressive GPU experiment"
Assert-Matches $Text "-IncludeInProcessGpu" "trusted matrix in-process GPU experiment"
Assert-Matches $Text "-IncludeSingleProcess" "trusted matrix single-process experiment"
Assert-Matches $Text "-IncludeReservedNoopGates" "trusted matrix reserved/no-op and relaxed WebGL gate experiments"
Assert-Matches $Text "-AngleBackend\s+d3d11" "trusted matrix ANGLE backend experiment"
Assert-Matches $Text "-Precompile" "trusted matrix resource warmup flag"
Assert-Matches $Text "-PrerenderFrames\s+2" "trusted matrix prerender frame handoff"

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
Assert-Matches $PostAtlText "-RefreshRevision requires -RefreshChromiumPin" "refresh revision guard"
Assert-Matches $PostAtlText "Assert-SkippedArtifactState" "resume artifact preflight guard"
Assert-Matches $PostAtlText "Assert-FinalGateOptions" "final-gate option preflight"
Assert-Matches $PostAtlText "-FinalGate requires completion-oriented options" "final-gate missing-options failure"
Assert-Matches $PostAtlText "-FinalGate cannot be combined with -SkipOfficialComparison" "final-gate skip-official guard"
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
  "-CaptureTrace",
  "-RunTrustedExperimentMatrix",
  "-RunLongStability"
)) {
  Assert-Matches $MissingFinalGateOptionsText ([regex]::Escape($RequiredFinalGateOption)) "final-gate missing option $RequiredFinalGateOption"
}
if ($MissingFinalGateOptionsText -match "refresh Chromium pin|Checking host and checkout prerequisites") {
  throw "Final-gate option preflight ran work before rejecting missing completion options."
}

$SkipOfficialFinalGateText = Invoke-PostAtlPipelineExpectFailure @(
  "-FinalGate",
  "-RefreshChromiumPin",
  "-RefreshRevision", $DryRunRefreshRevision,
  "-IncludeWebGPU",
  "-IncludeAggressiveGpu",
  "-AggressiveAngleBackend", "d3d11",
  "-CaptureTrace",
  "-RunTrustedExperimentMatrix",
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

$MissingForkOutDir = "out\MissingForkResumeGuard-$PID"
$MissingForkArgs = @(
  "-ForkOutDir", $MissingForkOutDir,
  "-SkipForkBuild",
  "-SkipOfficialComparison"
)
if ($InitialPatchState.AlreadyApplied) {
  $MissingForkArgs += "-SkipBaselineBuild"
}
$MissingForkFailureText = Invoke-PostAtlPipelineExpectFailure $MissingForkArgs "missing skipped fork binary"
Assert-Matches $MissingForkFailureText "SkipForkBuild requires an existing fork binary" "skip-fork missing binary runtime guard"
if ($MissingForkFailureText -match "Checking host and checkout prerequisites") {
  throw "Skip-fork resume guard ran prebuild verification before rejecting the missing fork binary."
}

$SyntheticBaselineOutDir = "out\PostAtlBaselineResumeGuard-$PID"
$SyntheticForkOutDir = "out\PostAtlForkResumeGuard-$PID"
$SyntheticBaselineFull = Join-Path $Src $SyntheticBaselineOutDir
$SyntheticForkFull = Join-Path $Src $SyntheticForkOutDir
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
  Assert-Matches $MismatchedPackageFailureText "SkipPackage requires an existing stock baseline package executable does not match expected browser" "skip-package package executable hash runtime guard"
  if ($MismatchedPackageFailureText -match "Checking host and checkout prerequisites") {
    throw "Skip-package resume guard ran prebuild verification before rejecting the mismatched package executable."
  }
} finally {
  foreach ($PathToRemove in @($SyntheticBaselineFull, $SyntheticForkFull, $MismatchedBaselinePackage, $MismatchedForkPackage, $SyntheticBaselineArgsFile, $SyntheticForkArgsFile)) {
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
  throw "Expected post-ATL dry-run to reject a baseline build while the viewer patch is already applied."
}
Assert-Matches $FailureText "Cannot build stock baseline while the viewer patch is already applied" "the patched-source baseline-build guard"

$SkipOutput = Invoke-PostAtlPipelineDryRun -SkipBaselineBuild -AssumeViewerPatchAlreadyApplied
$SkipText = ($SkipOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-Matches $SkipText "baseline build is skipped" "the patched-source skip-baseline acknowledgement"

$FinalPatchState = Get-PatchState
if ($InitialPatchState.Applies -ne $FinalPatchState.Applies -or $InitialPatchState.AlreadyApplied -ne $FinalPatchState.AlreadyApplied) {
  throw "Post-ATL dry-run patch-state guard test changed the src patch state."
}

Write-Host "Post-ATL pipeline dry-run includes Chromium pin refresh, official comparison, trusted matrix including default D3D11 ANGLE coverage, long-stability, final audit commands, PowerShell child-script dispatch, non-mutating patched-source baseline-build guard, and existing-artifact/hash checks for resume skips."

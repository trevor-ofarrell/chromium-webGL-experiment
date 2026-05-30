[CmdletBinding()]
param(
  [string]$CandidateAnalysisJson = ".\benchmarks\reports\post-atl-current-candidate-analysis.json",
  [string]$BaselineBrowser = ".\src\out\ReleaseBaseline\content_shell.exe",
  [string]$BaselineBuildArgs = ".\src\out\ReleaseBaseline\args.gn",
  [string]$BaselinePackageDir = ".\benchmarks\packages\baseline-content-shell",
  [string]$Browser = ".\src\out\ReleaseViewerDefault\content_shell.exe",
  [string]$BuildArgs = ".\src\out\ReleaseViewerDefault\args.gn",
  [string]$PackageDir = ".\benchmarks\packages\viewer-default",
  [string]$ForkRevision = "",
  [int]$Duration = 60,
  [int]$Warmup = 10,
  [double]$Complexity = 2.0,
  [switch]$Precompile,
  [int]$PrerenderFrames = 0,
  [switch]$SettleGpuAfterWarmup,
  [int]$WebGpuPipelineQuietFrames = 0,
  [int]$WebGpuPipelineQuietMaxFrames = 30,
  [ValidateSet("off", "static")]
  [string]$WebGpuBundleMode = "off",
  [string[]]$WebGlAngleBackend = @("d3d11"),
  [switch]$DisableWebGpuTiming,
  [switch]$AnalyzeAfterRun,
  [string[]]$PostRunAnalysisInputs = @(),
  [string]$PostRunAnalysisInputList = ".\benchmarks\reports\targeted-blocker-candidate-analysis-inputs.txt",
  [string]$PostRunTriageAnalysisOutput = ".\benchmarks\reports\targeted-blocker-triage-analysis.md",
  [string]$PostRunTriageAnalysisJson = ".\benchmarks\reports\targeted-blocker-triage-analysis.json",
  [string]$PostRunAnalysisOutput = ".\benchmarks\reports\targeted-blocker-candidate-analysis.md",
  [string]$PostRunAnalysisJson = ".\benchmarks\reports\targeted-blocker-candidate-analysis.json",
  [string]$TargetedPlanManifest = ".\benchmarks\reports\targeted-blocker-experiment-plan.json",
  [switch]$PlanSuitePromotionAfterTriage,
  [string]$SuitePromotionPlanManifest = ".\benchmarks\reports\targeted-suite-promotion-plan.json",
  [string]$SuitePromotionInputList = ".\benchmarks\reports\targeted-suite-promotion-analysis-inputs.txt",
  [string]$SuitePromotionAnalysisOutput = ".\benchmarks\reports\targeted-suite-promotion-analysis.md",
  [string]$SuitePromotionAnalysisJson = ".\benchmarks\reports\targeted-suite-promotion-analysis.json",
  [int]$SuitePromotionMaxProfilesPerRenderer = 3,
  [int]$PostRunAnalysisMinMeasuredSeconds = 30,
  [double]$PostRunAnalysisMinAvgFpsDeltaPct = 0.5,
  [double]$PostRunAnalysisSceneRegressionPct = 1.0,
  [double]$PostRunAnalysisDroppedFramesRegression = 0.0,
  [double]$PostRunAnalysisCpuFrameRegressionMs = 0.5,
  [double]$PostRunAnalysisRenderSubmissionRegressionMs = 0.5,
  [double]$PostRunAnalysisPipelineCreateRegressionMs = 1.0,
  [double]$SevereBlockerFpsRegressionPct = 20.0,
  [switch]$DisableSevereBlockerExpansion,
  [string[]]$RequireCandidateRenderer = @(),
  [switch]$RunComparableBaselines,
  [switch]$IncludeAllBlockerDiagnostics,
  [switch]$CaptureTargetedTrace,
  [int]$TraceDuration = 10,
  [int]$TraceWarmup = 2,
  [int]$TraceStartDelayMs = 2000,
  [switch]$TraceQueueInstrumentation,
  [switch]$TraceBindGroupInstrumentation,
  [switch]$TracePipelineStateInstrumentation,
  [switch]$TraceBufferStateInstrumentation,
  [switch]$TraceRenderStateInstrumentation,
  [switch]$TraceImmediateInstrumentation,
  [switch]$RejectWebGpuCpuFallbackTrace,
  [string]$WebGpuProfileCacheKey = "",
  [string]$ProfileCacheRoot = "",
  [switch]$PrimeWebGpuProfileCache,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BenchmarkTmpRoot = Join-Path $Root "benchmarks\tmp"
. (Join-Path $PSScriptRoot "viewer_patch_series.ps1")
$FullSuiteScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)
$PostRunAnalysisGeneratedInputs = [System.Collections.Generic.List[string]]::new()
$PlannedSteps = [System.Collections.Generic.List[object]]::new()
$ActiveBlockerDiagnostics = @()

function Resolve-RepoPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return Join-Path $Root $PathValue
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

function Get-StringSha256 {
  param([string]$Text)
  $Sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $HashBytes = $Sha256.ComputeHash($Bytes)
    return ([System.BitConverter]::ToString($HashBytes) -replace "-", "").ToLowerInvariant()
  } finally {
    $Sha256.Dispose()
  }
}

function ConvertTo-AnalyzerInputPath {
  param([string]$PathValue)

  $FullPath = [System.IO.Path]::GetFullPath((Resolve-RepoPath $PathValue))
  $FullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $Prefix = "$FullRoot$([System.IO.Path]::DirectorySeparatorChar)"
  $Comparison = if ($env:OS -eq "Windows_NT") {
    [System.StringComparison]::OrdinalIgnoreCase
  } else {
    [System.StringComparison]::Ordinal
  }
  $DisplayPath = if ($FullPath.StartsWith($Prefix, $Comparison)) {
    $FullPath.Substring($Prefix.Length)
  } else {
    $FullPath
  }
  return ($DisplayPath -replace "\\", "/")
}

function Get-AnalyzerInputDigest {
  param([string[]]$PathValues)

  $Inputs = @($PathValues | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($Inputs.Count -eq 0) {
    return $null
  }

  $Entries = [System.Collections.Generic.List[string]]::new()
  foreach ($PathValue in $Inputs) {
    $Resolved = Resolve-RepoPath $PathValue
    if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
      return $null
    }
    $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Resolved).Hash.ToLowerInvariant()
    $Size = (Get-Item -LiteralPath $Resolved).Length
    $Entries.Add("$(ConvertTo-AnalyzerInputPath $PathValue)`t$Hash`t$Size") | Out-Null
  }

  return Get-StringSha256 ((@($Entries | Sort-Object) -join "`n"))
}

function Normalize-CommaSeparatedStringList {
  param([AllowNull()][string[]]$Values)

  return @(
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
}

function Get-ResourceWarmupLabelSuffix {
  param([string]$Renderer = "")

  $WarmupParts = @()
  if ($Precompile) {
    $WarmupParts += "precompile"
  }
  if ($PrerenderFrames -gt 0) {
    $WarmupParts += "prerender$PrerenderFrames"
  }
  if ($SettleGpuAfterWarmup) {
    $WarmupParts += "settlegpu"
  }
  if ($Renderer -eq "webgpu" -and $WebGpuPipelineQuietFrames -gt 0) {
    $WarmupParts += "pipelinequiet$WebGpuPipelineQuietFrames"
  }
  $Suffix = ""
  if ($WarmupParts.Count -gt 0) {
    $Suffix += "-warmup-" + ($WarmupParts -join "-")
  }
  if ($Renderer -eq "webgpu" -and $WebGpuBundleMode -eq "static") {
    $Suffix += "-bundlegroup-static"
  }
  return $Suffix
}

$ResourceWarmupLabelSuffix = Get-ResourceWarmupLabelSuffix
$WebGlResourceWarmupLabelSuffix = Get-ResourceWarmupLabelSuffix -Renderer "webgl2"
$WebGpuResourceWarmupLabelSuffix = Get-ResourceWarmupLabelSuffix -Renderer "webgpu"

if ($RejectWebGpuCpuFallbackTrace -and -not $CaptureTargetedTrace) {
  throw "-RejectWebGpuCpuFallbackTrace requires -CaptureTargetedTrace."
}

if ($Complexity -le 0) {
  throw "-Complexity must be greater than zero."
}
if ($WebGpuPipelineQuietFrames -lt 0 -or $WebGpuPipelineQuietMaxFrames -lt 0) {
  throw "-WebGpuPipelineQuietFrames and -WebGpuPipelineQuietMaxFrames must be non-negative."
}
if ($TraceDuration -le 0) {
  throw "-TraceDuration must be greater than zero."
}
if ($TraceWarmup -lt 0) {
  throw "-TraceWarmup must be zero or greater."
}
if ($TraceStartDelayMs -lt 0) {
  throw "-TraceStartDelayMs must be zero or greater."
}
$RequireCandidateRenderer = @(
  Normalize-CommaSeparatedStringList $RequireCandidateRenderer |
    ForEach-Object { ([string]$_).ToLowerInvariant() } |
    Select-Object -Unique
)
if ($AnalyzeAfterRun -and $RequireCandidateRenderer.Count -eq 0) {
  $RequireCandidateRenderer = @("webgl2", "webgpu")
}
$WebGlAngleBackend = @(Normalize-CommaSeparatedStringList $WebGlAngleBackend)

if ($PlanSuitePromotionAfterTriage -and -not $AnalyzeAfterRun) {
  throw "-PlanSuitePromotionAfterTriage requires -AnalyzeAfterRun so targeted-blocker-triage-analysis.json is generated before promotion planning."
}
if ($WebGpuProfileCacheKey -and -not $ProfileCacheRoot) {
  $ProfileCacheRoot = Join-Path $BenchmarkTmpRoot "targeted-webgpu-profile-cache"
}
if ($ProfileCacheRoot -and -not $WebGpuProfileCacheKey) {
  throw "-ProfileCacheRoot requires -WebGpuProfileCacheKey so reused-profile artifacts are labeled for compatibility checks."
}
if ($PrimeWebGpuProfileCache -and -not $WebGpuProfileCacheKey) {
  throw "-PrimeWebGpuProfileCache requires -WebGpuProfileCacheKey."
}
$ResolvedProfileCacheRoot = $null
if ($WebGpuProfileCacheKey) {
  $ResolvedProfileCacheRoot = Resolve-RepoFullPath $ProfileCacheRoot
  if (-not (Test-PathUnderDirectory $ResolvedProfileCacheRoot $BenchmarkTmpRoot)) {
    throw "-ProfileCacheRoot must resolve under $BenchmarkTmpRoot."
  }
}

function Add-ResourceWarmupLabelSuffix {
  param(
    [string]$Label,
    [string]$Renderer = ""
  )

  $Suffix = switch ($Renderer) {
    "webgl2" { $WebGlResourceWarmupLabelSuffix }
    "webgpu" { $WebGpuResourceWarmupLabelSuffix }
    default { $ResourceWarmupLabelSuffix }
  }
  return "$Label$Suffix"
}

function Invoke-Step {
  param(
    [string]$Name,
    [object[]]$Command
  )

  Write-Host ""
  Write-Host "== $Name =="
  Write-Host (Format-Command $Command)
  $PlannedSteps.Add([pscustomobject]@{
      name = $Name
      command = @($Command)
      command_line = Format-Command $Command
    }) | Out-Null
  if ($DryRun) {
    return
  }

  Invoke-ExternalStepCommand -Name $Name -Command $Command
}

function Invoke-ExternalStepCommand {
  param(
    [string]$Name,
    [object[]]$Command
  )

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

function Get-TargetedTraceFlagMetadata {
  param(
    [bool]$ViewerMode,
    [bool]$ViewerTrustedContent,
    [bool]$ViewerTraceWebgpuQueue,
    [bool]$ViewerRejectWebgpuCpuTextureFallback,
    [bool]$GpuTimingEnabled
  )

  $Metadata = [ordered]@{
    viewer_mode = $ViewerMode
    viewer_block_external_navigation = $ViewerMode
    viewer_trusted_content = $ViewerTrustedContent
    viewer_trace_webgpu_queue = $ViewerTraceWebgpuQueue
    viewer_reject_webgpu_cpu_texture_fallback = $ViewerRejectWebgpuCpuTextureFallback
    gpu_timing_enabled = $GpuTimingEnabled
    webgpu_queue_instrumentation_enabled = [bool]$TraceQueueInstrumentation
    webgpu_bind_group_instrumentation_enabled = [bool]$TraceBindGroupInstrumentation
    webgpu_pipeline_state_instrumentation_enabled = [bool]$TracePipelineStateInstrumentation
    webgpu_buffer_state_instrumentation_enabled = [bool]$TraceBufferStateInstrumentation
    webgpu_render_state_instrumentation_enabled = [bool]$TraceRenderStateInstrumentation
    webgpu_immediate_instrumentation_enabled = [bool]$TraceImmediateInstrumentation
    benchmark_hud_enabled = $false
    resource_warmup_enabled = [bool]($Precompile -or $PrerenderFrames -gt 0 -or $SettleGpuAfterWarmup -or $WebGpuPipelineQuietFrames -gt 0)
    resource_warmup_precompile = [bool]$Precompile
    resource_warmup_prerender_frames = $PrerenderFrames
    resource_warmup_settle_gpu = [bool]$SettleGpuAfterWarmup
    resource_warmup_pipeline_quiet_frames = $WebGpuPipelineQuietFrames
    resource_warmup_pipeline_quiet_max_frames = if ($WebGpuPipelineQuietFrames -gt 0) { [Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames) } else { 0 }
    webgpu_bundle_mode = $WebGpuBundleMode
  }

  return @($Metadata.GetEnumerator() | ForEach-Object {
      "$($_.Key)=$(Convert-MetadataValue $_.Value)"
    })
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
  if ($SettleGpuAfterWarmup) {
    $Result += "--settleGpuAfterWarmup"
  }
  if ($WebGpuPipelineQuietFrames -gt 0) {
    $Result += @("--pipelineQuietFrames", [string]$WebGpuPipelineQuietFrames)
    $Result += @("--pipelineQuietMaxFrames", [string]([Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames)))
  }
  if ($WebGpuBundleMode -ne "off") {
    $Result += @("--webgpuBundleMode", $WebGpuBundleMode)
  }
  return $Result
}

function Get-TargetedTracePath {
  param(
    [string]$Label,
    [string]$Scene
  )

  return Join-Path $Root "benchmarks\traces\$Label-$Scene-webgpu-targeted-trace.json"
}

function Get-TargetedTraceResultPath {
  param([string]$TracePath)
  return [System.IO.Path]::ChangeExtension($TracePath, ".result.json")
}

function New-TargetedTraceCaptureCommand {
  param(
    [string]$BrowserPath,
    [string]$Scene,
    [string]$Output,
    [bool]$ViewerMode,
    [bool]$ViewerTrustedContent,
    [bool]$ViewerTraceWebgpuQueue
  )

  $Command = @(
    "node",
    (Join-Path $Root "scripts\run_trace_capture.mjs"),
    "--browser", $BrowserPath,
    "--scene", $Scene,
    "--renderer", "webgpu",
    "--complexity", [string]$Complexity,
    "--duration", [string]$TraceDuration,
    "--warmup", [string]$TraceWarmup,
    "--startDelayMs", [string]$TraceStartDelayMs,
    "--output", $Output
  )
  if ($DisableWebGpuTiming) {
    $Command += "--disableGpuTiming"
  }
  if ($TraceQueueInstrumentation) {
    $Command += "--queueInstrumentation"
  }
  if ($TraceBindGroupInstrumentation) {
    $Command += "--bindGroupInstrumentation"
  }
  if ($TracePipelineStateInstrumentation) {
    $Command += "--pipelineStateInstrumentation"
  }
  if ($TraceBufferStateInstrumentation) {
    $Command += "--bufferStateInstrumentation"
  }
  if ($TraceRenderStateInstrumentation) {
    $Command += "--renderStateInstrumentation"
  }
  if ($TraceImmediateInstrumentation) {
    $Command += "--immediateInstrumentation"
  }
  if ($ViewerMode) {
    $Command += "--viewerMode"
  }
  if ($ViewerTrustedContent) {
    $Command += "--viewerTrustedContent"
  }
  if ($ViewerTraceWebgpuQueue) {
    $Command += "--viewerTraceWebgpuQueue"
  }
  if ($RejectWebGpuCpuFallbackTrace -and $ViewerMode -and $ViewerTrustedContent) {
    $Command += "--viewerRejectWebgpuCpuTextureFallback"
  }
  return Add-TraceResourceWarmupArgs $Command
}

function New-TargetedTraceValidationCommand {
  param(
    [string]$TracePath,
    [string]$BrowserPath,
    [string]$Scene,
    [bool]$ViewerMode,
    [bool]$ViewerTrustedContent,
    [bool]$ViewerTraceWebgpuQueue
  )

  $Command = @(
    "node",
    (Join-Path $Root "scripts\validate_trace_result.mjs"),
    "--expectedBrowser", $BrowserPath,
    "--expectedScene", $Scene,
    "--expectedRenderer", "webgpu",
    "--expectedDuration", [string]$TraceDuration,
    "--expectedWarmup", [string]$TraceWarmup,
    "--expectedStartDelayMs", [string]$TraceStartDelayMs,
    "--rejectSoftwareRendering"
  )
  foreach ($Metadata in (Get-TargetedTraceFlagMetadata `
        -ViewerMode $ViewerMode `
        -ViewerTrustedContent $ViewerTrustedContent `
        -ViewerTraceWebgpuQueue $ViewerTraceWebgpuQueue `
        -ViewerRejectWebgpuCpuTextureFallback ([bool]($RejectWebGpuCpuFallbackTrace -and $ViewerMode -and $ViewerTrustedContent)) `
        -GpuTimingEnabled (-not [bool]$DisableWebGpuTiming))) {
    $Command += @("--expectedFlagMetadata", $Metadata)
  }
  foreach ($Flag in @("--disable-software-rasterizer")) {
    $Command += @("--requiredBrowserFlag", $Flag)
  }
  if ($ViewerMode) {
    foreach ($Flag in @("--viewer-block-external-navigation")) {
      $Command += @("--requiredBrowserFlag", $Flag)
    }
  }
  if ($ViewerTrustedContent) {
    $Command += @("--requiredBrowserFlag", "--viewer-trusted-content")
  }
  if ($ViewerTraceWebgpuQueue) {
    $Command += @("--requiredBrowserFlag", "--viewer-trace-webgpu-queue")
  }
  if ($RejectWebGpuCpuFallbackTrace -and $ViewerMode -and $ViewerTrustedContent) {
    $Command += @("--requiredBrowserFlag", "--viewer-reject-webgpu-cpu-texture-fallback")
  }
  $Command += Get-TargetedTraceResultPath $TracePath
  return $Command
}

function New-TargetedTraceFileValidationCommand {
  param([string]$TracePath)
  $Command = @(
    "node",
    (Join-Path $Root "scripts\validate_trace_file.mjs"),
    "--minEvents", "1"
  )
  if ($RejectWebGpuCpuFallbackTrace) {
    $Command += "--rejectWebGpuCpuFallback"
  }
  $Command += $TracePath
  return $Command
}

function New-TargetedTraceSummaryCommand {
  param(
    [string]$TracePath,
    [string]$Label,
    [string]$Scene
  )

  $Command = @(
    "node",
    (Join-Path $Root "scripts\summarize_trace.mjs"),
    $TracePath,
    "--output", (Join-Path $Root "benchmarks\reports\$Label-$Scene-webgpu-targeted-trace-summary.md")
  )
  if ($RejectWebGpuCpuFallbackTrace) {
    $Command += "--rejectWebGpuCpuFallback"
  }
  return $Command
}

function Add-TargetedTracePlanFiles {
  param(
    [System.Collections.Generic.List[object]]$Files,
    [string]$Label,
    [string]$Scene
  )

  $TracePath = Get-TargetedTracePath -Label $Label -Scene $Scene
  $Files.Add([pscustomobject]@{
      label = $Label
      scene = $Scene
      renderer = "webgpu"
      trace = $TracePath
      trace_result = Get-TargetedTraceResultPath $TracePath
      trace_summary = Join-Path $Root "benchmarks\reports\$Label-$Scene-webgpu-targeted-trace-summary.md"
    }) | Out-Null
}

function Invoke-TargetedWebGpuTraceCapture {
  param([string[]]$Scenes)

  if (-not $CaptureTargetedTrace -or $Scenes.Count -eq 0) {
    return
  }

  $BaselineLabel = Add-ResourceWarmupLabelSuffix "baseline-content-shell-targeted-blocker-webgpu-trace" -Renderer "webgpu"
  $ForkLabel = Add-ResourceWarmupLabelSuffix "fork-viewer-default-targeted-blocker-webgpu-trace" -Renderer "webgpu"
  foreach ($Scene in $Scenes) {
    $BaselineTrace = Get-TargetedTracePath -Label $BaselineLabel -Scene $Scene
    Invoke-Step "targeted WebGPU baseline trace ($Scene)" (New-TargetedTraceCaptureCommand `
        -BrowserPath $BaselineBrowser `
        -Scene $Scene `
        -Output $BaselineTrace `
        -ViewerMode:$false `
        -ViewerTrustedContent:$false `
        -ViewerTraceWebgpuQueue:$false)
    Invoke-Step "validate targeted WebGPU baseline trace file ($Scene)" (New-TargetedTraceFileValidationCommand -TracePath $BaselineTrace)
    Invoke-Step "validate targeted WebGPU baseline trace sidecar ($Scene)" (New-TargetedTraceValidationCommand `
        -TracePath $BaselineTrace `
        -BrowserPath $BaselineBrowser `
        -Scene $Scene `
        -ViewerMode:$false `
        -ViewerTrustedContent:$false `
        -ViewerTraceWebgpuQueue:$false)
    Invoke-Step "summarize targeted WebGPU baseline trace ($Scene)" (New-TargetedTraceSummaryCommand `
        -TracePath $BaselineTrace `
        -Label $BaselineLabel `
        -Scene $Scene)

    $ForkTrace = Get-TargetedTracePath -Label $ForkLabel -Scene $Scene
    Invoke-Step "targeted WebGPU fork trace ($Scene)" (New-TargetedTraceCaptureCommand `
        -BrowserPath $Browser `
        -Scene $Scene `
        -Output $ForkTrace `
        -ViewerMode:$true `
        -ViewerTrustedContent:$true `
        -ViewerTraceWebgpuQueue:$true)
    Invoke-Step "validate targeted WebGPU fork trace file ($Scene)" (New-TargetedTraceFileValidationCommand -TracePath $ForkTrace)
    Invoke-Step "validate targeted WebGPU fork trace sidecar ($Scene)" (New-TargetedTraceValidationCommand `
        -TracePath $ForkTrace `
        -BrowserPath $Browser `
        -Scene $Scene `
        -ViewerMode:$true `
        -ViewerTrustedContent:$true `
        -ViewerTraceWebgpuQueue:$true)
    Invoke-Step "summarize targeted WebGPU fork trace ($Scene)" (New-TargetedTraceSummaryCommand `
        -TracePath $ForkTrace `
        -Label $ForkLabel `
        -Scene $Scene)
  }
}

function Get-BlockerScenes {
  param(
    [string]$Renderer
  )

  $Scenes = @(
    $ActiveBlockerDiagnostics |
      Where-Object {
        [string]$_.renderer -eq $Renderer -and
          [string]$_.status -ne "candidate" -and
          [string]$_.scene -and
          [string]$_.scene -ne "suite average" -and
          [string]$_.scene -notmatch "^coverage\s"
      } |
      ForEach-Object { [string]$_.scene } |
      Sort-Object -Unique
  )
  return @($Scenes)
}

function Test-NeedsSuiteExpansion {
  param(
    [string]$Renderer
  )

  $NeedsSuiteRows = @(
    $ActiveBlockerDiagnostics |
      Where-Object {
        [string]$_.renderer -eq $Renderer -and
          [string]$_.status -in @("needs-suite", "weak-throughput")
      }
  )
  return $NeedsSuiteRows.Count -gt 0
}

function Get-PlannedScenes {
  param(
    [object]$Analysis,
    [string]$Renderer
  )

  if (Test-NeedsSuiteExpansion -Renderer $Renderer) {
    return @($FullSuiteScenes)
  }

  return @(Get-BlockerScenes -Renderer $Renderer)
}

function Add-PostRunAnalysisResultFiles {
  param(
    [string]$Label,
    [string]$Renderer,
    [string[]]$Scenes
  )

  foreach ($Scene in $Scenes) {
    $PostRunAnalysisGeneratedInputs.Add((Join-Path $Root "benchmarks\raw\$Label-$Scene-$Renderer.json")) | Out-Null
  }
}

function Add-UniqueLabels {
  param(
    [System.Collections.Generic.List[string]]$Labels,
    [string[]]$Values
  )

  foreach ($Value in $Values) {
    if ($Value -and -not $Labels.Contains($Value)) {
      $Labels.Add($Value) | Out-Null
    }
  }
}

function Test-AnySceneIn {
  param(
    [string[]]$Scenes,
    [string[]]$Values
  )

  foreach ($Scene in $Scenes) {
    if ($Values -contains $Scene) {
      return $true
    }
  }
  return $false
}

function Get-WebGpuBlockerRows {
  param([string[]]$Scenes)

  return @(
    $ActiveBlockerDiagnostics |
      Where-Object {
        [string]$_.renderer -eq "webgpu" -and
          [string]$_.scene -and
          [string]$_.scene -notmatch "^coverage\s" -and
          ($Scenes -contains [string]$_.scene)
      }
  )
}

function Get-RequiredGateRows {
  param([object]$Analysis)

  if ($null -eq $Analysis.required_candidate_gate -or
      $null -eq $Analysis.required_candidate_gate.renderers) {
    return @()
  }

  return @($Analysis.required_candidate_gate.renderers)
}

function Test-JsonProperty {
  param(
    [AllowNull()]$Object,
    [string]$Name
  )
  return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-NullableDouble {
  param([object]$Value)

  $Parsed = 0.0
  if ([double]::TryParse([string]$Value, [ref]$Parsed)) {
    return $Parsed
  }
  return $null
}

function Get-DiagnosticIdentity {
  param([object]$Row)

  return @(
    [string]$Row.renderer,
    [string]$Row.baseline_family,
    [string]$Row.candidate_family,
    [string]$Row.status,
    [string]$Row.scene
  ) -join "|"
}

function Add-UniqueDiagnostic {
  param(
    [System.Collections.Generic.List[object]]$Rows,
    [System.Collections.Generic.HashSet[string]]$Seen,
    [object]$Row
  )

  $Identity = Get-DiagnosticIdentity -Row $Row
  if ($Seen.Add($Identity)) {
    $Rows.Add($Row) | Out-Null
  }
}

function Select-ActiveBlockerDiagnostics {
  param([object]$Analysis)

  $AllRows = @($Analysis.blocker_diagnostics)
  if ($IncludeAllBlockerDiagnostics) {
    return $AllRows
  }

  $GateRows = @(Get-RequiredGateRows -Analysis $Analysis)
  if ($GateRows.Count -eq 0) {
    return $AllRows
  }

  $Selected = [System.Collections.Generic.List[object]]::new()
  $SeenDiagnostics = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $FailedGateRenderers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($GateRow in $GateRows) {
    if ([bool]$GateRow.ok) {
      continue
    }

    $Renderer = [string]$GateRow.renderer
    $CandidateFamily = [string]$GateRow.best_candidate_family
    $BaselineFamily = [string]$GateRow.best_baseline_family
    $Status = [string]$GateRow.best_status
    if (-not $Renderer -or -not $CandidateFamily) {
      continue
    }
    $FailedGateRenderers.Add($Renderer) | Out-Null

    $Matches = @($AllRows | Where-Object {
        [string]$_.renderer -eq $Renderer -and
          [string]$_.candidate_family -eq $CandidateFamily -and
          (-not $BaselineFamily -or [string]$_.baseline_family -eq $BaselineFamily) -and
          (-not $Status -or [string]$_.status -eq $Status)
      })
    if ($Matches.Count -eq 0) {
      $Matches = @($AllRows | Where-Object {
          [string]$_.renderer -eq $Renderer -and
            [string]$_.candidate_family -eq $CandidateFamily
        })
    }
    foreach ($Match in $Matches) {
      Add-UniqueDiagnostic -Rows $Selected -Seen $SeenDiagnostics -Row $Match
    }
  }

  if (-not $DisableSevereBlockerExpansion -and $FailedGateRenderers.Count -gt 0) {
    $SevereThreshold = -1.0 * [Math]::Abs($SevereBlockerFpsRegressionPct)
    $SevereRows = @($AllRows | Where-Object {
        $Renderer = [string]$_.renderer
        $Scene = [string]$_.scene
        $AvgFpsDeltaPct = Get-NullableDouble -Value $_.avg_fps_delta_pct
        $FailedGateRenderers.Contains($Renderer) -and
          [string]$_.status -ne "candidate" -and
          $Scene -and
          $Scene -ne "suite average" -and
          $Scene -notmatch "^coverage\s" -and
          $null -ne $AvgFpsDeltaPct -and
          $AvgFpsDeltaPct -le $SevereThreshold
      })
    foreach ($SevereRow in $SevereRows) {
      Add-UniqueDiagnostic -Rows $Selected -Seen $SeenDiagnostics -Row $SevereRow
    }

    $TailRows = @($AllRows | Where-Object {
        $Renderer = [string]$_.renderer
        $Scene = [string]$_.scene
        $FailedGateRenderers.Contains($Renderer) -and
          [string]$_.status -eq "blocked-tail" -and
          $Scene -and
          $Scene -ne "suite average" -and
          $Scene -notmatch "^coverage\s" -and
          $Scene -notmatch "^missing\s"
      })
    foreach ($TailRow in $TailRows) {
      Add-UniqueDiagnostic -Rows $Selected -Seen $SeenDiagnostics -Row $TailRow
    }

    $CpuOverheadRows = @($AllRows | Where-Object {
        $Renderer = [string]$_.renderer
        $Scene = [string]$_.scene
        $FailedGateRenderers.Contains($Renderer) -and
          [string]$_.status -eq "blocked-cpu-overhead" -and
          $Scene -and
          $Scene -ne "suite average" -and
          $Scene -notmatch "^coverage\s" -and
          $Scene -notmatch "^missing\s"
      })
    foreach ($CpuOverheadRow in $CpuOverheadRows) {
      Add-UniqueDiagnostic -Rows $Selected -Seen $SeenDiagnostics -Row $CpuOverheadRow
    }

    $TextureUploadRows = @($AllRows | Where-Object {
        $Renderer = [string]$_.renderer
        $Scene = [string]$_.scene
        $AvgFpsDeltaPct = Get-NullableDouble -Value $_.avg_fps_delta_pct
        $FailedGateRenderers.Contains($Renderer) -and
          $Renderer -eq "webgpu" -and
          [string]$_.status -ne "candidate" -and
          $Scene -eq "texture-streaming" -and
          $null -ne $AvgFpsDeltaPct -and
          $AvgFpsDeltaPct -lt 0
      })
    foreach ($TextureUploadRow in $TextureUploadRows) {
      Add-UniqueDiagnostic -Rows $Selected -Seen $SeenDiagnostics -Row $TextureUploadRow
    }
  }

  if ($Selected.Count -eq 0) {
    if ($AllRows.Count -gt 0) {
      return $AllRows
    }

    $FallbackRows = [System.Collections.Generic.List[object]]::new()
    foreach ($GateRow in $GateRows) {
      if ([bool]$GateRow.ok) {
        continue
      }
      $Renderer = [string]$GateRow.renderer
      if (-not $Renderer) {
        continue
      }
      $FallbackRows.Add([pscustomobject]@{
          renderer = $Renderer
          baseline_family = [string]$GateRow.best_baseline_family
          candidate_family = if ([string]$GateRow.best_candidate_family) { [string]$GateRow.best_candidate_family } else { "current-analysis-missing-$Renderer" }
          status = "needs-suite"
          scene = "coverage 0/$($FullSuiteScenes.Count)"
          avg_fps_delta_pct = $null
          primary_blocker = "no comparable fork-over-baseline family in current candidate analysis"
        }) | Out-Null
    }
    return @($FallbackRows.ToArray())
  }

  return @($Selected.ToArray())
}

function Get-WebGpuTargetedExperimentLabels {
  param([string[]]$Scenes)

  $Labels = [System.Collections.Generic.List[string]]::new()
  Add-UniqueLabels $Labels @(
    "fork-viewer-exp-default",
    "fork-viewer-exp-in-process-gpu",
    "fork-viewer-exp-single-process",
    "fork-viewer-exp-webgpu-adapter-d3d11"
  )

  $Rows = @(Get-WebGpuBlockerRows -Scenes $Scenes)
  $PrimaryBlockers = @($Rows | ForEach-Object { [string]$_.primary_blocker })
  $HasThroughputBlocker = @($PrimaryBlockers | Where-Object { $_ -match "avg FPS" }).Count -gt 0
  $HasTailBlocker = @($PrimaryBlockers | Where-Object { $_ -match "1% low|0\.1% low|p95|p99" }).Count -gt 0
  $HasDrawCallLikeScene = Test-AnySceneIn $Scenes @("many-draw-calls", "gltf-loader-stress")
  $HasTextureScene = Test-AnySceneIn $Scenes @("texture-streaming")
  $HasShaderScene = Test-AnySceneIn $Scenes @("shader-heavy", "gltf-loader-stress")
  $HasLargePassScene = Test-AnySceneIn $Scenes @("instancing", "postprocessing", "large-static")

  if ($HasDrawCallLikeScene) {
    Add-UniqueLabels $Labels @(
      "fork-viewer-exp-disable-frame-rate-limit",
      "fork-viewer-exp-disable-gpu-vsync",
      "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync",
      "fork-viewer-exp-webgpu-d3d11-delay-flush",
      "fork-viewer-exp-webgpu-d3d11-unmonitored-fence",
      "fork-viewer-exp-webgpu-d3d11-disable-fence",
      "fork-viewer-exp-webgpu-d3d11-delay-flush-unmonitored-fence",
      "fork-viewer-exp-webgpu-d3d11-wait-thread-safe",
      "fork-viewer-exp-webgpu-d3d11-delay-flush-wait-thread-safe",
      "fork-viewer-exp-webgpu-defer-pipeline-flush",
      "fork-viewer-exp-webgpu-cache-bind-group-layouts",
      "fork-viewer-exp-webgpu-skip-command-labels",
      "fork-viewer-exp-webgpu-skip-resource-labels",
      "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets",
      "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets",
      "fork-viewer-exp-webgpu-skip-redundant-buffer-sets",
      "fork-viewer-exp-webgpu-skip-redundant-render-state-sets",
      "fork-viewer-exp-webgpu-defer-queue-flush",
      "fork-viewer-exp-webgpu-defer-submit-flush",
      "fork-viewer-exp-webgpu-skip-canvas-texture-validation",
      "fork-viewer-exp-webgpu-skip-canvas-memory-accounting",
      "fork-viewer-exp-webgpu-skip-write-texture-layout-validation",
      "fork-viewer-exp-webgpu-skip-use-counters",
      "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc",
      "fork-viewer-exp-webgpu-increased-cmd-buffer-slice",
      "fork-viewer-exp-webgpu-disable-range-analysis",
      "fork-viewer-exp-webgpu-d3d11-remove-gpu-legacy-ipc-hlsl2021",
      "fork-viewer-exp-webgpu-d3d11-ipc-hlsl2021-cmd-slice-staging-upload",
      "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range",
      "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-buffer-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-render-state-sets"
    )
  }

  if ($HasThroughputBlocker -and -not $HasDrawCallLikeScene) {
    Add-UniqueLabels $Labels @(
      "fork-viewer-exp-disable-frame-rate-limit",
      "fork-viewer-exp-disable-gpu-vsync",
      "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync",
      "fork-viewer-exp-webgpu-d3d11-delay-flush",
      "fork-viewer-exp-webgpu-d3d11-unmonitored-fence",
      "fork-viewer-exp-webgpu-d3d11-disable-fence",
      "fork-viewer-exp-webgpu-d3d11-delay-flush-unmonitored-fence",
      "fork-viewer-exp-webgpu-d3d11-wait-thread-safe",
      "fork-viewer-exp-webgpu-d3d11-delay-flush-wait-thread-safe",
      "fork-viewer-exp-webgpu-defer-pipeline-flush",
      "fork-viewer-exp-webgpu-cache-bind-group-layouts",
      "fork-viewer-exp-webgpu-skip-command-labels",
      "fork-viewer-exp-webgpu-skip-resource-labels",
      "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets",
      "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets",
      "fork-viewer-exp-webgpu-skip-redundant-buffer-sets",
      "fork-viewer-exp-webgpu-skip-redundant-render-state-sets",
      "fork-viewer-exp-webgpu-defer-queue-flush",
      "fork-viewer-exp-webgpu-defer-submit-flush",
      "fork-viewer-exp-webgpu-skip-canvas-texture-validation",
      "fork-viewer-exp-webgpu-skip-canvas-memory-accounting",
      "fork-viewer-exp-webgpu-skip-write-texture-layout-validation",
      "fork-viewer-exp-webgpu-skip-use-counters",
      "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc",
      "fork-viewer-exp-webgpu-increased-cmd-buffer-slice",
      "fork-viewer-exp-webgpu-disable-range-analysis",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-buffer-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-render-state-sets"
    )
  }

  if ($HasTextureScene) {
    Add-UniqueLabels $Labels @(
      "fork-viewer-exp-webgpu-d3d11-disable-cpu-upload-buffers",
      "fork-viewer-exp-webgpu-d3d11-disable-map-default-buffers",
      "fork-viewer-exp-webgpu-d3d11-auto-map-backend-buffer",
      "fork-viewer-exp-webgpu-dawn-mapped-buffer-clear-skip",
      "fork-viewer-exp-webgpu-d3d-staging-upload",
      "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment",
      "fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload",
      "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment-staging-upload",
      "fork-viewer-exp-webgpu-d3d11-cmd-slice-d3d-staging-upload",
      "fork-viewer-exp-webgpu-defer-queue-flush",
      "fork-viewer-exp-webgpu-defer-submit-flush",
      "fork-viewer-exp-webgpu-skip-canvas-texture-validation",
      "fork-viewer-exp-webgpu-skip-canvas-memory-accounting",
      "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion",
      "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation",
      "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation",
      "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation",
      "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation",
      "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path",
      "fork-viewer-exp-webgpu-skip-write-texture-layout-validation",
      "fork-viewer-exp-webgpu-skip-use-counters",
      "fork-viewer-exp-webgpu-d3d11-ipc-hlsl2021-cmd-slice-staging-upload",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-color-conv",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-colorspace",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-validation",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-source",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-copy-size",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-copy-ext-image-fast-path",
      "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-write-texture-layout-validation",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters"
    )
  }

  if ($HasShaderScene -or $HasLargePassScene) {
    Add-UniqueLabels $Labels @(
      "fork-viewer-exp-webgpu-dawn-use-dxc",
      "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation",
      "fork-viewer-exp-webgpu-hlsl2021",
      "fork-viewer-exp-webgpu-disable-range-analysis",
      "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc-hlsl2021",
      "fork-viewer-exp-webgpu-d3d12-toggles",
      "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-buffer-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-render-state-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters"
    )
  }

  if ($HasTailBlocker -or $HasLargePassScene) {
    Add-UniqueLabels $Labels @(
      "fork-viewer-exp-disable-frame-rate-limit",
      "fork-viewer-exp-disable-gpu-vsync",
      "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync",
      "fork-viewer-exp-webgpu-d3d11-delay-flush",
      "fork-viewer-exp-webgpu-d3d11-unmonitored-fence",
      "fork-viewer-exp-webgpu-d3d11-disable-fence",
      "fork-viewer-exp-webgpu-d3d11-delay-flush-unmonitored-fence",
      "fork-viewer-exp-webgpu-d3d11-wait-thread-safe",
      "fork-viewer-exp-webgpu-d3d11-delay-flush-wait-thread-safe",
      "fork-viewer-exp-webgpu-d3d11-discard-view"
    )
  }

  if ($HasDrawCallLikeScene) {
    Add-UniqueLabels $Labels @(
      "fork-viewer-exp-webgpu-dawn-skip-validation",
      "fork-viewer-exp-webgpu-dawn-disable-robustness",
      "fork-viewer-exp-webgpu-d3d11-skip-validation",
      "fork-viewer-exp-webgpu-d3d11-disable-robustness",
      "fork-viewer-exp-webgpu-d3d11-skip-validation-disable-robustness"
    )
  }

  return @($Labels.ToArray())
}

function Get-TargetedExperimentLabels {
  param(
    [string]$Renderer,
    [string[]]$Scenes = @()
  )

  if ($Renderer -eq "webgl2") {
    $Labels = @(
      "fork-viewer-exp-default",
      "fork-viewer-exp-zero-copy",
      "fork-viewer-exp-webgl2-gpu-compositor-resources",
      "fork-viewer-exp-webgl2-zero-copy-gpu-compositor-resources",
      "fork-viewer-exp-disable-frame-rate-limit",
      "fork-viewer-exp-disable-gpu-vsync",
      "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync",
      "fork-viewer-exp-relaxed-webgl-validation-gate",
      "fork-viewer-exp-disable-unneeded-blink-features-gate",
      "fork-viewer-exp-direct-gpu-presentation-gate",
      "fork-viewer-exp-relaxed-webgl-validation-zero-copy"
    )
    foreach ($Backend in $WebGlAngleBackend) {
      if ($Backend -and $Backend -ne "default") {
        $Labels += @(
          "fork-viewer-exp-angle-$Backend",
          "fork-viewer-exp-angle-$Backend-zero-copy",
          "fork-viewer-exp-angle-$Backend-relaxed-webgl-validation",
          "fork-viewer-exp-angle-$Backend-relaxed-webgl-validation-zero-copy"
        )
      }
    }
    return @($Labels)
  }

  if ($Renderer -eq "webgpu") {
    if ($Scenes.Count -gt 0) {
      return @(Get-WebGpuTargetedExperimentLabels -Scenes $Scenes)
    }

    return @(
      "fork-viewer-exp-default",
      "fork-viewer-exp-in-process-gpu",
      "fork-viewer-exp-single-process",
      "fork-viewer-exp-disable-frame-rate-limit",
      "fork-viewer-exp-disable-gpu-vsync",
      "fork-viewer-exp-disable-frame-rate-limit-gpu-vsync",
      "fork-viewer-exp-webgpu-adapter-d3d11",
      "fork-viewer-exp-webgpu-d3d11-delay-flush",
      "fork-viewer-exp-webgpu-d3d11-unmonitored-fence",
      "fork-viewer-exp-webgpu-d3d11-disable-fence",
      "fork-viewer-exp-webgpu-d3d11-delay-flush-unmonitored-fence",
      "fork-viewer-exp-webgpu-d3d11-discard-view",
      "fork-viewer-exp-webgpu-d3d11-disable-cpu-upload-buffers",
      "fork-viewer-exp-webgpu-d3d11-disable-map-default-buffers",
      "fork-viewer-exp-webgpu-d3d11-wait-thread-safe",
      "fork-viewer-exp-webgpu-d3d11-delay-flush-wait-thread-safe",
      "fork-viewer-exp-webgpu-d3d11-auto-map-backend-buffer",
      "fork-viewer-exp-webgpu-defer-pipeline-flush",
      "fork-viewer-exp-webgpu-cache-bind-group-layouts",
      "fork-viewer-exp-webgpu-skip-command-labels",
      "fork-viewer-exp-webgpu-skip-resource-labels",
      "fork-viewer-exp-webgpu-skip-redundant-pipeline-sets",
      "fork-viewer-exp-webgpu-skip-redundant-bind-group-sets",
      "fork-viewer-exp-webgpu-skip-redundant-buffer-sets",
      "fork-viewer-exp-webgpu-skip-redundant-render-state-sets",
      "fork-viewer-exp-webgpu-defer-queue-flush",
      "fork-viewer-exp-webgpu-defer-submit-flush",
      "fork-viewer-exp-webgpu-skip-canvas-texture-validation",
      "fork-viewer-exp-webgpu-skip-canvas-memory-accounting",
      "fork-viewer-exp-webgpu-skip-copy-external-image-color-conversion",
      "fork-viewer-exp-webgpu-skip-copy-external-image-color-space-validation",
      "fork-viewer-exp-webgpu-skip-copy-external-image-dest-validation",
      "fork-viewer-exp-webgpu-skip-copy-external-image-source-validation",
      "fork-viewer-exp-webgpu-skip-copy-external-image-copy-size-validation",
      "fork-viewer-exp-webgpu-copy-external-image-trusted-fast-path",
      "fork-viewer-exp-webgpu-skip-write-texture-layout-validation",
      "fork-viewer-exp-webgpu-skip-use-counters",
      "fork-viewer-exp-webgpu-dawn-mapped-buffer-clear-skip",
      "fork-viewer-exp-webgpu-dawn-use-dxc",
      "fork-viewer-exp-webgpu-dawn-disable-blob-cache-hash-validation",
      "fork-viewer-exp-webgpu-dawn-skip-validation",
      "fork-viewer-exp-webgpu-dawn-disable-robustness",
      "fork-viewer-exp-webgpu-d3d12-toggles",
      "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc",
      "fork-viewer-exp-webgpu-hlsl2021",
      "fork-viewer-exp-webgpu-disable-range-analysis",
      "fork-viewer-exp-webgpu-remove-gpu-legacy-ipc-hlsl2021",
      "fork-viewer-exp-webgpu-increased-cmd-buffer-slice",
      "fork-viewer-exp-webgpu-d3d-staging-upload",
      "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment",
      "fork-viewer-exp-webgpu-cmd-slice-d3d-staging-upload",
      "fork-viewer-exp-webgpu-d3d12-relaxed-copy-alignment-staging-upload",
      "fork-viewer-exp-webgpu-d3d11-remove-gpu-legacy-ipc-hlsl2021",
      "fork-viewer-exp-webgpu-d3d11-cmd-slice-d3d-staging-upload",
      "fork-viewer-exp-webgpu-d3d11-ipc-hlsl2021-cmd-slice-staging-upload",
      "fork-viewer-exp-webgpu-d3d11-dxc-ipc-hlsl2021-cmd-slice-range",
      "fork-viewer-exp-webgpu-d3d11-aggressive-pipeline-fast-path",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-pipeline-flush",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-cache-bind-group-layouts",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-command-labels",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-resource-labels",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-pipeline-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-bind-group-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-buffer-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-redundant-render-state-sets",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-queue-flush",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-defer-submit-flush",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-validation",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-canvas-memory",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-color-conv",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-colorspace",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-validation",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-source",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-copy-ext-image-copy-size",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-copy-ext-image-fast-path",
      "fork-viewer-exp-webgpu-d3d11-aggressive-upload-fast-path",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-write-texture-layout-validation",
      "fork-viewer-exp-webgpu-d3d11-dxc-flush-fence-clear-skip-skip-use-counters"
    )
  }

  throw "Unsupported renderer for targeted experiment labels: $Renderer"
}

function Add-PostRunAnalysisExperimentFiles {
  param(
    [string]$Renderer,
    [string[]]$Scenes
  )

  foreach ($Label in (Get-TargetedExperimentLabels -Renderer $Renderer -Scenes $Scenes)) {
    Add-PostRunAnalysisResultFiles -Label (Add-ResourceWarmupLabelSuffix $Label -Renderer $Renderer) -Renderer $Renderer -Scenes $Scenes
  }
}

function Add-PostRunAnalysisExperimentFilesForLabels {
  param(
    [string[]]$Labels,
    [string]$Renderer,
    [string[]]$Scenes
  )

  foreach ($Label in $Labels) {
    Add-PostRunAnalysisResultFiles -Label (Add-ResourceWarmupLabelSuffix $Label -Renderer $Renderer) -Renderer $Renderer -Scenes $Scenes
  }
}

function Write-PostRunAnalysisInputList {
  param([string[]]$Inputs)

  $InputListPath = Resolve-RepoPath $PostRunAnalysisInputList
  $InputListDir = Split-Path -Parent $InputListPath
  if ($InputListDir) {
    New-Item -ItemType Directory -Path $InputListDir -Force | Out-Null
  }
  @($Inputs) | Set-Content -LiteralPath $InputListPath -Encoding UTF8
  return $InputListPath
}

function New-PostRunAnalysisCommand {
  param(
    [string]$Output = $PostRunAnalysisOutput,
    [string]$Json = $PostRunAnalysisJson,
    [int]$MinScenes = $FullSuiteScenes.Count,
    [switch]$RequireCandidateGate
  )

  $ExpectedChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $ExpectedForkRevision = if ($ForkRevision) {
    $ForkRevision
  } else {
    Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ExpectedChromiumRevision -Root $Root
  }

  $Command = @(
    "node",
    (Join-Path $Root "scripts\analyze_candidates.mjs")
  )

  $ExplicitInputPatterns = @($PostRunAnalysisInputs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($ExplicitInputPatterns.Count -eq 0) {
    if (-not $RunComparableBaselines) {
      throw "-AnalyzeAfterRun requires -RunComparableBaselines or explicit -PostRunAnalysisInputs so fork experiments are not analyzed against stale baseline artifacts."
    }
    $GeneratedInputPatterns = @($PostRunAnalysisGeneratedInputs.ToArray())
    if ($GeneratedInputPatterns.Count -eq 0) {
      throw "No post-run analysis inputs were planned."
    }
    $InputListPath = Write-PostRunAnalysisInputList -Inputs $GeneratedInputPatterns
    $Command += @("--fileList", $InputListPath)
  } else {
    foreach ($InputPattern in $ExplicitInputPatterns) {
      $Command += $InputPattern
    }
  }
  $Command += @(
    "--output", $Output,
    "--json", $Json,
    "--minMeasuredSeconds", [string]$PostRunAnalysisMinMeasuredSeconds,
    "--minScenes", [string]$MinScenes,
    "--minAvgFpsDeltaPct", [string]$PostRunAnalysisMinAvgFpsDeltaPct,
    "--sceneRegressionPct", [string]$PostRunAnalysisSceneRegressionPct,
    "--droppedFramesRegression", [string]$PostRunAnalysisDroppedFramesRegression,
    "--cpuFrameRegressionMs", [string]$PostRunAnalysisCpuFrameRegressionMs,
    "--renderSubmissionRegressionMs", [string]$PostRunAnalysisRenderSubmissionRegressionMs,
    "--pipelineCreateRegressionMs", [string]$PostRunAnalysisPipelineCreateRegressionMs,
    "--requireFrameTimes",
    "--requireCheckout",
    "--requirePackageSize",
    "--expectedChromiumRevision", $ExpectedChromiumRevision,
    "--expectedForkRevision", $ExpectedForkRevision
  )
  if ($RequireCandidateGate) {
    foreach ($Scene in $FullSuiteScenes) {
      $Command += @("--requiredScene", $Scene)
    }
    foreach ($Renderer in $RequireCandidateRenderer) {
      if ($Renderer) {
        $Command += @("--requireCandidateRenderer", $Renderer)
      }
    }
  }
  return $Command
}

function New-SuitePromotionCommand {
  $Command = @(
    (Join-Path $Root "scripts\plan_suite_promotion.ps1"),
    "-TriageAnalysisJson", $PostRunTriageAnalysisJson,
    "-TargetedPlanManifest", $TargetedPlanManifest,
    "-PromotionPlanManifest", $SuitePromotionPlanManifest,
    "-PromotionInputList", $SuitePromotionInputList,
    "-PromotionAnalysisOutput", $SuitePromotionAnalysisOutput,
    "-PromotionAnalysisJson", $SuitePromotionAnalysisJson,
    "-MinAvgFpsDeltaPct", [string]$PostRunAnalysisMinAvgFpsDeltaPct,
    "-SceneRegressionPct", [string]$PostRunAnalysisSceneRegressionPct,
    "-DroppedFramesRegression", [string]$PostRunAnalysisDroppedFramesRegression,
    "-CpuFrameRegressionMs", [string]$PostRunAnalysisCpuFrameRegressionMs,
    "-RenderSubmissionRegressionMs", [string]$PostRunAnalysisRenderSubmissionRegressionMs,
    "-PipelineCreateRegressionMs", [string]$PostRunAnalysisPipelineCreateRegressionMs,
    "-MaxProfilesPerRenderer", [string]$SuitePromotionMaxProfilesPerRenderer
  )
  $RendererGate = @($RequireCandidateRenderer | Where-Object { $_ })
  if ($RendererGate.Count -gt 0) {
    $Command += @("-RequireCandidateRenderer", ($RendererGate -join ","))
  }
  if ($DryRun) {
    $Command += "-DryRun"
  }
  return $Command
}

function Write-DryRunTriageAnalysisPlaceholder {
  $TriageJsonPath = Resolve-RepoPath $PostRunTriageAnalysisJson
  $TriageJsonDir = Split-Path -Parent $TriageJsonPath
  if ($TriageJsonDir) {
    New-Item -ItemType Directory -Path $TriageJsonDir -Force | Out-Null
  }

  $Placeholder = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = $true
    phase = "planned"
    note = "Dry-run placeholder written so suite-promotion handoff stays revision-synchronized; real triage analysis is generated after targeted runs."
    families = @()
    required_candidate_gate = [pscustomobject]@{
      required_renderers = @($RequireCandidateRenderer)
      ok = $false
      renderers = @()
      failures = @("dry-run placeholder; targeted runs not executed")
    }
    input_file_digest = $null
    input_files = @()
  }
  $Placeholder | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $TriageJsonPath -Encoding UTF8
  Write-Host "Wrote dry-run triage placeholder: $TriageJsonPath"

  $TriageOutputPath = Resolve-RepoPath $PostRunTriageAnalysisOutput
  $TriageOutputDir = Split-Path -Parent $TriageOutputPath
  if ($TriageOutputDir) {
    New-Item -ItemType Directory -Path $TriageOutputDir -Force | Out-Null
  }
  @(
    "# Targeted Blocker Triage Analysis (Dry Run)"
    ""
    "This placeholder keeps the suite-promotion handoff revision-synchronized during dry-run planning."
    "Run the targeted blocker experiments without -DryRun to replace it with measured triage evidence."
  ) | Set-Content -LiteralPath $TriageOutputPath -Encoding UTF8
  Write-Host "Wrote dry-run triage placeholder: $TriageOutputPath"
}

function Get-ExpectedRevisionInfo {
  $ChromiumRevision = Get-GitRevision (Join-Path $Root "src")
  $ViewerForkRevision = if ($ForkRevision) {
    $ForkRevision
  } else {
    Get-ViewerForkRevisionForChromiumRevision -ChromiumRevision $ChromiumRevision -Root $Root
  }

  return [pscustomobject]@{
    chromium_revision = $ChromiumRevision
    fork_revision = $ViewerForkRevision
  }
}

function Get-GitRevision {
  param([string]$RepoPath)
  if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    throw "Git repository path not found: $RepoPath"
  }
  $Revision = (& git -C $RepoPath rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $Revision) {
    throw "Unable to read git revision from $RepoPath"
  }
  return $Revision
}

function Get-ResultFilesForLabels {
  param(
    [string[]]$Labels,
    [string]$Renderer,
    [string[]]$Scenes
  )

  return @($Labels | ForEach-Object {
      $Label = [string]$_
      foreach ($Scene in $Scenes) {
        Join-Path $Root "benchmarks\raw\$Label-$Scene-$Renderer.json"
      }
    })
}

function Get-ResultFilesForSceneLabelGroups {
  param(
    [object[]]$Groups,
    [string]$Renderer
  )

  return @($Groups | ForEach-Object {
      Get-ResultFilesForLabels @($_.experiment_labels) $Renderer @($_.scenes)
    })
}

function Get-UniqueStrings {
  param([string[]]$Values)

  $Unique = [System.Collections.Generic.List[string]]::new()
  Add-UniqueLabels -Labels $Unique -Values $Values
  return @($Unique.ToArray())
}

function Get-WebGpuTargetedSceneLabelGroups {
  param(
    [string[]]$Scenes,
    [switch]$ForceSingleGroup
  )

  if ($Scenes.Count -eq 0) {
    return @()
  }

  if ($ForceSingleGroup -or $Scenes.Count -eq 1) {
    $BaseLabels = @(Get-TargetedExperimentLabels -Renderer "webgpu" -Scenes $Scenes)
    return @([pscustomobject]@{
        scenes = @($Scenes)
        base_experiment_labels = @($BaseLabels)
        experiment_labels = @($BaseLabels | ForEach-Object { Add-ResourceWarmupLabelSuffix $_ -Renderer "webgpu" })
      })
  }

  $GroupsBySignature = @{}
  $GroupOrder = [System.Collections.Generic.List[string]]::new()
  foreach ($Scene in $Scenes) {
    $BaseLabels = @(Get-TargetedExperimentLabels -Renderer "webgpu" -Scenes @($Scene))
    $Signature = $BaseLabels -join ([string][char]31)
    if (-not $GroupsBySignature.ContainsKey($Signature)) {
      $GroupsBySignature[$Signature] = [pscustomobject]@{
        scenes = [System.Collections.Generic.List[string]]::new()
        base_experiment_labels = @($BaseLabels)
      }
      $GroupOrder.Add($Signature) | Out-Null
    }
    $GroupsBySignature[$Signature].scenes.Add($Scene) | Out-Null
  }

  return @($GroupOrder.ToArray() | ForEach-Object {
      $Group = $GroupsBySignature[$_]
      $BaseLabels = @($Group.base_experiment_labels)
      [pscustomobject]@{
        scenes = @($Group.scenes.ToArray())
        base_experiment_labels = @($BaseLabels)
        experiment_labels = @($BaseLabels | ForEach-Object { Add-ResourceWarmupLabelSuffix $_ -Renderer "webgpu" })
      }
    })
}

function Write-TargetedPlanManifest {
  param(
    [string[]]$WebGlScenes,
    [string[]]$WebGpuScenes
  )

  $ManifestPath = Resolve-RepoPath $TargetedPlanManifest
  $ManifestDir = Split-Path -Parent $ManifestPath
  if ($ManifestDir) {
    New-Item -ItemType Directory -Path $ManifestDir -Force | Out-Null
  }

  $RevisionInfo = Get-ExpectedRevisionInfo
  $WebGlBaseExperimentLabels = if ($WebGlScenes.Count -gt 0) { @(Get-TargetedExperimentLabels -Renderer "webgl2" -Scenes $WebGlScenes) } else { @() }
  $WebGpuSceneLabelGroups = @(Get-WebGpuTargetedSceneLabelGroups -Scenes $WebGpuScenes -ForceSingleGroup:(Test-NeedsSuiteExpansion -Renderer "webgpu"))
  $WebGpuBaseExperimentLabels = @(Get-UniqueStrings @($WebGpuSceneLabelGroups | ForEach-Object { $_.base_experiment_labels }))
  $WebGlExperimentLabels = @($WebGlBaseExperimentLabels | ForEach-Object { Add-ResourceWarmupLabelSuffix $_ -Renderer "webgl2" })
  $WebGpuExperimentLabels = @($WebGpuBaseExperimentLabels | ForEach-Object { Add-ResourceWarmupLabelSuffix $_ -Renderer "webgpu" })
  $PostRunInputs = @($PostRunAnalysisGeneratedInputs.ToArray())
  $PostRunInputDigest = Get-AnalyzerInputDigest $PostRunInputs
  $TargetedTraceFiles = [System.Collections.Generic.List[object]]::new()
  if ($CaptureTargetedTrace -and $WebGpuScenes.Count -gt 0) {
    $BaselineTraceLabel = Add-ResourceWarmupLabelSuffix "baseline-content-shell-targeted-blocker-webgpu-trace" -Renderer "webgpu"
    $ForkTraceLabel = Add-ResourceWarmupLabelSuffix "fork-viewer-default-targeted-blocker-webgpu-trace" -Renderer "webgpu"
    foreach ($Scene in $WebGpuScenes) {
      Add-TargetedTracePlanFiles -Files $TargetedTraceFiles -Label $BaselineTraceLabel -Scene $Scene
      Add-TargetedTracePlanFiles -Files $TargetedTraceFiles -Label $ForkTraceLabel -Scene $Scene
    }
  }

  $Manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = [bool]$DryRun
    phase = if ($DryRun) { "planned" } else { "completed" }
    candidate_analysis_json = Resolve-RepoPath $CandidateAnalysisJson
    chromium_revision = $RevisionInfo.chromium_revision
    fork_revision = $RevisionInfo.fork_revision
    browsers = [pscustomobject]@{
      baseline = $BaselineBrowser
      fork = $Browser
    }
    build_args = [pscustomobject]@{
      baseline = $BaselineBuildArgs
      fork = $BuildArgs
    }
    package_dirs = [pscustomobject]@{
      baseline = $BaselinePackageDir
      fork = $PackageDir
    }
    options = [pscustomobject]@{
      duration = $Duration
      warmup = $Warmup
      complexity = $Complexity
      precompile = [bool]$Precompile
      prerender_frames = $PrerenderFrames
      settle_gpu_after_warmup = [bool]$SettleGpuAfterWarmup
      webgpu_pipeline_quiet_frames = $WebGpuPipelineQuietFrames
      webgpu_pipeline_quiet_max_frames = if ($WebGpuPipelineQuietFrames -gt 0) { [Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames) } else { 0 }
      webgpu_bundle_mode = $WebGpuBundleMode
      webgl_angle_backend = @($WebGlAngleBackend)
      resource_warmup_label_suffix = $ResourceWarmupLabelSuffix
      webgl2_resource_warmup_label_suffix = $WebGlResourceWarmupLabelSuffix
      webgpu_resource_warmup_label_suffix = $WebGpuResourceWarmupLabelSuffix
      disable_webgpu_timing = [bool]$DisableWebGpuTiming
      run_comparable_baselines = [bool]$RunComparableBaselines
      webgpu_profile_cache_key = if ($WebGpuProfileCacheKey) { $WebGpuProfileCacheKey } else { $null }
      webgpu_profile_cache_mode = if ($WebGpuProfileCacheKey) { "explicit-reuse" } else { "fresh-temp" }
      profile_cache_root = $ResolvedProfileCacheRoot
      prime_webgpu_profile_cache = [bool]$PrimeWebGpuProfileCache
      profile_cache_policy = "same-profile-cache-mode-and-key"
      profile_cache_prime_policy = if ($PrimeWebGpuProfileCache) { "prime-before-measured-run" } else { "none" }
      analyze_after_run = [bool]$AnalyzeAfterRun
      plan_suite_promotion_after_triage = [bool]$PlanSuitePromotionAfterTriage
      include_all_blocker_diagnostics = [bool]$IncludeAllBlockerDiagnostics
      include_severe_blocker_diagnostics = -not [bool]$DisableSevereBlockerExpansion
      include_tail_blocker_diagnostics = -not [bool]$DisableSevereBlockerExpansion
      include_cpu_overhead_blocker_diagnostics = -not [bool]$DisableSevereBlockerExpansion
      severe_blocker_fps_regression_pct = $SevereBlockerFpsRegressionPct
    }
    targeted_trace = [pscustomobject]@{
      enabled = [bool]($CaptureTargetedTrace -and $WebGpuScenes.Count -gt 0)
      renderer = "webgpu"
      duration = $TraceDuration
      warmup = $TraceWarmup
      start_delay_ms = $TraceStartDelayMs
      queue_instrumentation = [bool]$TraceQueueInstrumentation
      bind_group_instrumentation = [bool]$TraceBindGroupInstrumentation
      pipeline_state_instrumentation = [bool]$TracePipelineStateInstrumentation
      buffer_state_instrumentation = [bool]$TraceBufferStateInstrumentation
      render_state_instrumentation = [bool]$TraceRenderStateInstrumentation
      immediate_instrumentation = [bool]$TraceImmediateInstrumentation
      reject_webgpu_cpu_fallback = [bool]$RejectWebGpuCpuFallbackTrace
      viewer_trace_webgpu_queue = [bool]($CaptureTargetedTrace -and $WebGpuScenes.Count -gt 0)
      disable_webgpu_timing = [bool]$DisableWebGpuTiming
      webgpu_bundle_mode = $WebGpuBundleMode
      trace_files = @($TargetedTraceFiles.ToArray())
    }
    planned_scenes = [pscustomobject]@{
      webgl2 = @($WebGlScenes)
      webgpu = @($WebGpuScenes)
    }
    needs_suite_expansion = [pscustomobject]@{
      webgl2 = [bool](Test-NeedsSuiteExpansion -Renderer "webgl2")
      webgpu = [bool](Test-NeedsSuiteExpansion -Renderer "webgpu")
    }
    experiment_labels = [pscustomobject]@{
      webgl2 = @($WebGlExperimentLabels)
      webgpu = @($WebGpuExperimentLabels)
    }
    base_experiment_labels = [pscustomobject]@{
      webgl2 = @($WebGlBaseExperimentLabels)
      webgpu = @($WebGpuBaseExperimentLabels)
    }
    scene_label_groups = [pscustomobject]@{
      webgpu = @($WebGpuSceneLabelGroups)
    }
    active_blocker_diagnostics = @($ActiveBlockerDiagnostics)
    blocker_diagnostics = @($Analysis.blocker_diagnostics)
    result_files = [pscustomobject]@{
      baseline_webgl2 = if ($RunComparableBaselines -and $WebGlScenes.Count -gt 0) { @(Get-ResultFilesForLabels @((Add-ResourceWarmupLabelSuffix "baseline-content-shell-targeted-blocker" -Renderer "webgl2")) "webgl2" $FullSuiteScenes) } else { @() }
      fork_webgl2 = @(Get-ResultFilesForLabels $WebGlExperimentLabels "webgl2" $WebGlScenes)
      baseline_webgpu = if ($RunComparableBaselines -and $WebGpuScenes.Count -gt 0) { @(Get-ResultFilesForLabels @((Add-ResourceWarmupLabelSuffix "baseline-content-shell-targeted-blocker-webgpu" -Renderer "webgpu")) "webgpu" $FullSuiteScenes) } else { @() }
      fork_webgpu = @(Get-ResultFilesForSceneLabelGroups $WebGpuSceneLabelGroups "webgpu")
    }
    post_run_analysis = [pscustomobject]@{
      enabled = [bool]$AnalyzeAfterRun
      input_list = Resolve-RepoPath $PostRunAnalysisInputList
      generated_input_count = $PostRunInputs.Count
      triage_output = $PostRunTriageAnalysisOutput
      triage_json = $PostRunTriageAnalysisJson
      triage_min_scenes = 1
      output = $PostRunAnalysisOutput
      json = $PostRunAnalysisJson
      expected_input_file_digest = $PostRunInputDigest
      min_measured_seconds = $PostRunAnalysisMinMeasuredSeconds
      min_avg_fps_delta_pct = $PostRunAnalysisMinAvgFpsDeltaPct
      min_scenes = $FullSuiteScenes.Count
      required_scenes = @($FullSuiteScenes)
      scene_regression_pct = $PostRunAnalysisSceneRegressionPct
      dropped_frames_regression = $PostRunAnalysisDroppedFramesRegression
      cpu_frame_regression_ms = $PostRunAnalysisCpuFrameRegressionMs
      render_submission_regression_ms = $PostRunAnalysisRenderSubmissionRegressionMs
      pipeline_create_regression_ms = $PostRunAnalysisPipelineCreateRegressionMs
      require_frame_times = $true
      require_checkout = $true
      require_package_size = $true
      required_candidate_renderers = @($RequireCandidateRenderer)
      build_args_compatibility_policy = "same-build-args-hash"
      environment_compatibility_policy = "same-platform-driver-gpu-device"
      complexity_compatibility_policy = "same-explicit-benchmark-complexity"
      webgpu_bundle_mode_compatibility_policy = "same-webgpu-bundle-mode"
      webgpu_pipeline_instrumentation_compatibility_policy = "same-webgpu-pipeline-instrumentation-mode"
      resource_warmup_compatibility_policy = "same-precompile-prerender-compile-texture-render-target-count-gpu-settle-and-webgpu-pipeline-quiet-mode"
      profile_cache_compatibility_policy = "same-profile-cache-mode-and-key"
      baseline_selection_policy = "fastest-compatible-baseline"
      expected_chromium_revision = $RevisionInfo.chromium_revision
      expected_fork_revision = $RevisionInfo.fork_revision
    }
    suite_promotion = [pscustomobject]@{
      enabled = [bool]$PlanSuitePromotionAfterTriage
      plan_manifest = $SuitePromotionPlanManifest
      input_list = $SuitePromotionInputList
      output = $SuitePromotionAnalysisOutput
      json = $SuitePromotionAnalysisJson
      max_profiles_per_renderer = $SuitePromotionMaxProfilesPerRenderer
      source_triage_json = $PostRunTriageAnalysisJson
      source_targeted_plan_manifest = $TargetedPlanManifest
    }
    steps = @($PlannedSteps.ToArray())
  }

  $Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  Write-Host "Wrote $ManifestPath"
}

function New-ComparableBaselineCommand {
  param(
    [string]$Renderer,
    [string]$Label
  )

  $Command = @(
    (Join-Path $Root "scripts\run_full_suite.ps1"),
    "-Browser", $BaselineBrowser,
    "-Renderer", $Renderer,
    "-Duration", [string]$Duration,
    "-Warmup", [string]$Warmup,
    "-Label", $Label,
    "-BuildArgs", $BaselineBuildArgs,
    "-Complexity", [string]$Complexity,
    "-RequireGpuMetadata"
  )
  if ($BaselinePackageDir) {
    $Command += @("-PackageDir", $BaselinePackageDir)
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
  if ($Renderer -eq "webgpu" -and $DisableWebGpuTiming) {
    $Command += "-DisableGpuTiming"
  }
  if ($Renderer -eq "webgpu" -and $WebGpuProfileCacheKey) {
    $Command += @("-ProfileCacheKey", $WebGpuProfileCacheKey, "-UserDataDirRoot", $ResolvedProfileCacheRoot)
  }
  return $Command
}

$AnalysisPath = Resolve-RepoPath $CandidateAnalysisJson
if (-not (Test-Path -LiteralPath $AnalysisPath -PathType Leaf)) {
  throw "Candidate analysis JSON not found: $AnalysisPath"
}

$Analysis = Get-Content -LiteralPath $AnalysisPath -Raw | ConvertFrom-Json
if (-not (Test-JsonProperty -Object $Analysis -Name "blocker_diagnostics")) {
  throw "Candidate analysis JSON does not contain blocker_diagnostics: $AnalysisPath"
}
$ActiveBlockerDiagnostics = @(Select-ActiveBlockerDiagnostics -Analysis $Analysis)
if (-not $ActiveBlockerDiagnostics) {
  throw "Candidate analysis JSON did not provide any active blocker diagnostics: $AnalysisPath"
}

$TrustedMatrix = Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1"
$CommonArgs = @(
  "-Browser", $Browser,
  "-BuildArgs", $BuildArgs,
  "-PackageDir", $PackageDir,
  "-Duration", [string]$Duration,
  "-Warmup", [string]$Warmup,
  "-Complexity", [string]$Complexity,
  "-IncludeDefault"
)
if ($Precompile) {
  $CommonArgs += "-Precompile"
}
if ($PrerenderFrames -gt 0) {
  $CommonArgs += @("-PrerenderFrames", [string]$PrerenderFrames)
}
if ($SettleGpuAfterWarmup) {
  $CommonArgs += "-SettleGpuAfterWarmup"
}
if ($ForkRevision) {
  $CommonArgs += @("-ForkRevision", $ForkRevision)
}
if ($DryRun) {
  $CommonArgs += "-DryRun"
}

$WebGlScenes = @(Get-PlannedScenes -Analysis $Analysis -Renderer "webgl2")
if ($WebGlScenes.Count -gt 0) {
  if ($RunComparableBaselines) {
    $WebGlBaselineLabel = Add-ResourceWarmupLabelSuffix "baseline-content-shell-targeted-blocker" -Renderer "webgl2"
    Invoke-Step "targeted WebGL2 comparable baseline suite" (New-ComparableBaselineCommand "webgl2" $WebGlBaselineLabel)
    Add-PostRunAnalysisResultFiles -Label $WebGlBaselineLabel -Renderer "webgl2" -Scenes $FullSuiteScenes
  }

  $Command = @($TrustedMatrix)
  $Command += $CommonArgs
  $Command += @(
    "-Renderer", "webgl2",
    "-Scenes", ($WebGlScenes -join ",")
  )
  if ($WebGlResourceWarmupLabelSuffix) {
    $Command += @("-LabelSuffix", $WebGlResourceWarmupLabelSuffix)
  }
  if ($WebGlAngleBackend.Count -gt 0) {
    $Command += @("-AngleBackend", ($WebGlAngleBackend -join ","))
  }
  $Command += @(
    "-IncludeZeroCopy",
    "-IncludeWebGlCompositorExperiments",
    "-IncludeFramePacingExperiments",
    "-IncludeReservedNoopGates"
  )
  $StepName = if (Test-NeedsSuiteExpansion -Renderer "webgl2") {
    "targeted WebGL2 needs-suite expansion matrix"
  } else {
    "targeted WebGL2 blocker matrix"
  }
  Invoke-Step $StepName $Command
  Add-PostRunAnalysisExperimentFiles -Renderer "webgl2" -Scenes $WebGlScenes
} else {
  Write-Host "No WebGL2 blocker scenes found in $AnalysisPath."
}

$WebGpuScenes = @(Get-PlannedScenes -Analysis $Analysis -Renderer "webgpu")
if ($WebGpuScenes.Count -gt 0) {
  $WebGpuNeedsSuiteExpansion = Test-NeedsSuiteExpansion -Renderer "webgpu"
  $WebGpuSceneLabelGroups = @(Get-WebGpuTargetedSceneLabelGroups -Scenes $WebGpuScenes -ForceSingleGroup:$WebGpuNeedsSuiteExpansion)
  if ($RunComparableBaselines) {
    $WebGpuBaselineLabel = Add-ResourceWarmupLabelSuffix "baseline-content-shell-targeted-blocker-webgpu" -Renderer "webgpu"
    $WebGpuBaselineCommand = New-ComparableBaselineCommand "webgpu" $WebGpuBaselineLabel
    if ($PrimeWebGpuProfileCache) {
      Invoke-Step "prime targeted WebGPU comparable baseline suite" $WebGpuBaselineCommand
    }
    Invoke-Step "targeted WebGPU comparable baseline suite" $WebGpuBaselineCommand
    Add-PostRunAnalysisResultFiles -Label $WebGpuBaselineLabel -Renderer "webgpu" -Scenes $FullSuiteScenes
  }

  foreach ($Group in $WebGpuSceneLabelGroups) {
    $GroupScenes = @($Group.scenes)
    $WebGpuBaseExperimentLabels = @($Group.base_experiment_labels)
    $Command = @($TrustedMatrix)
    $Command += $CommonArgs
    $Command += @(
      "-Renderer", "webgpu",
      "-Scenes", ($GroupScenes -join ",")
    )
    if ($WebGpuResourceWarmupLabelSuffix) {
      $Command += @("-LabelSuffix", $WebGpuResourceWarmupLabelSuffix)
    }
    $Command += @(
      "-IncludeSingleProcess",
      "-IncludeInProcessGpu",
      "-IncludeFramePacingExperiments",
      "-IncludeWebGpuDawnExperiments",
      "-IncludeWebGpuChromiumFeatureExperiments",
      "-IncludeWebGpuUploadExperiments",
      "-ExperimentLabelFilter", ($WebGpuBaseExperimentLabels -join ",")
    )
    if ($DisableWebGpuTiming) {
      $Command += "-DisableGpuTiming"
    }
    if ($WebGpuPipelineQuietFrames -gt 0) {
      $Command += @("-WebGpuPipelineQuietFrames", [string]$WebGpuPipelineQuietFrames)
      $Command += @("-WebGpuPipelineQuietMaxFrames", [string]([Math]::Max($WebGpuPipelineQuietFrames, $WebGpuPipelineQuietMaxFrames)))
    }
    if ($WebGpuBundleMode -ne "off") {
      $Command += @("-WebGpuBundleMode", $WebGpuBundleMode)
    }
    if ($WebGpuProfileCacheKey) {
      $Command += @("-ProfileCacheKey", $WebGpuProfileCacheKey, "-UserDataDirRoot", $ResolvedProfileCacheRoot)
    }
    if ($PrimeWebGpuProfileCache) {
      $Command += "-PrimeProfileCache"
    }
    $StepName = if ($WebGpuNeedsSuiteExpansion) {
      "targeted WebGPU needs-suite expansion matrix"
    } else {
      "targeted WebGPU blocker matrix ($($GroupScenes -join ','))"
    }
    Invoke-Step $StepName $Command
    Add-PostRunAnalysisExperimentFilesForLabels -Labels $WebGpuBaseExperimentLabels -Renderer "webgpu" -Scenes $GroupScenes
  }
  Invoke-TargetedWebGpuTraceCapture -Scenes $WebGpuScenes
} else {
  Write-Host "No WebGPU blocker scenes found in $AnalysisPath."
}

if ($AnalyzeAfterRun) {
  Invoke-Step "post-run blocker triage analysis" (New-PostRunAnalysisCommand `
      -Output $PostRunTriageAnalysisOutput `
      -Json $PostRunTriageAnalysisJson `
      -MinScenes 1)
  Invoke-Step "post-run candidate speed analysis" (New-PostRunAnalysisCommand -RequireCandidateGate)
}

Write-TargetedPlanManifest -WebGlScenes $WebGlScenes -WebGpuScenes $WebGpuScenes

if ($AnalyzeAfterRun -and $PlanSuitePromotionAfterTriage) {
  $SuitePromotionCommand = New-SuitePromotionCommand
  if ($DryRun) {
    Write-DryRunTriageAnalysisPlaceholder
    Invoke-Step "post-run suite promotion planning" $SuitePromotionCommand
    Invoke-ExternalStepCommand -Name "post-run suite promotion planning" -Command $SuitePromotionCommand
  } else {
    Invoke-Step "post-run suite promotion planning" $SuitePromotionCommand
  }
  Write-TargetedPlanManifest -WebGlScenes $WebGlScenes -WebGpuScenes $WebGpuScenes
}

Write-Host "Targeted blocker experiment plan completed. These runs are triage evidence; final retention still requires the complete seven-scene candidate gate."

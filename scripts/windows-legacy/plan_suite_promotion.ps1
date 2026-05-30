[CmdletBinding()]
param(
  [string]$TriageAnalysisJson = ".\benchmarks\reports\targeted-blocker-triage-analysis.json",
  [string]$TargetedPlanManifest = ".\benchmarks\reports\targeted-blocker-experiment-plan.json",
  [string]$PromotionPlanManifest = ".\benchmarks\reports\targeted-suite-promotion-plan.json",
  [string]$PromotionInputList = ".\benchmarks\reports\targeted-suite-promotion-analysis-inputs.txt",
  [string]$PromotionAnalysisOutput = ".\benchmarks\reports\targeted-suite-promotion-analysis.md",
  [string]$PromotionAnalysisJson = ".\benchmarks\reports\targeted-suite-promotion-analysis.json",
  [string[]]$RequireCandidateRenderer = @(),
  [double]$MinAvgFpsDeltaPct = -1,
  [double]$SceneRegressionPct = -1,
  [double]$DroppedFramesRegression = -1,
  [double]$CpuFrameRegressionMs = -1,
  [double]$RenderSubmissionRegressionMs = -1,
  [double]$PipelineCreateRegressionMs = -1,
  [int]$MaxProfilesPerRenderer = 3,
  [switch]$RunComparableBaselines,
  [switch]$NoComparableBaselines,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$DefaultScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)
$FreshProfileConfirmationSuffix = "-fresh-profile-confirmation"

function Resolve-RepoPath {
  param([string]$PathValue)
  if (-not $PathValue) {
    return ""
  }
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return Join-Path $Root $PathValue
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

function ConvertTo-Array {
  param([AllowNull()]$Value)
  if ($null -eq $Value) {
    return @()
  }
  if ($Value -is [array]) {
    return @($Value)
  }
  return @($Value)
}

function Get-ObjectPropertyValue {
  param(
    [AllowNull()]$Object,
    [string]$Name
  )
  if ($null -eq $Object) {
    return $null
  }
  $Property = $Object.PSObject.Properties[$Name]
  if ($null -eq $Property) {
    return $null
  }
  return $Property.Value
}

function Get-PlanLabelSuffix {
  param(
    [object]$Plan,
    [string]$Renderer = ""
  )

  $PropertyName = switch ($Renderer) {
    "webgl2" { "webgl2_resource_warmup_label_suffix" }
    "webgpu" { "webgpu_resource_warmup_label_suffix" }
    default { "resource_warmup_label_suffix" }
  }
  $RendererSpecific = Get-ObjectPropertyValue $Plan.options $PropertyName
  if ($null -ne $RendererSpecific) {
    return [string]$RendererSpecific
  }
  return [string](Get-ObjectPropertyValue $Plan.options "resource_warmup_label_suffix")
}

function Get-StringListProperty {
  param(
    [AllowNull()]$Object,
    [string]$Name
  )
  return @(ConvertTo-Array (Get-ObjectPropertyValue $Object $Name) | ForEach-Object { [string]$_ } | Where-Object { $_ })
}

function Normalize-CommaSeparatedStringList {
  param([AllowNull()][string[]]$Values)
  return @(
    foreach ($Value in (ConvertTo-Array $Values)) {
      foreach ($Part in ([string]$Value -split ",")) {
        $Trimmed = $Part.Trim()
        if ($Trimmed) {
          $Trimmed.ToLowerInvariant()
        }
      }
    }
  )
}

function Read-JsonFile {
  param([string]$PathValue)
  $Resolved = Resolve-RepoPath $PathValue
  if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
    throw "Required JSON file not found: $Resolved"
  }
  return Get-Content -LiteralPath $Resolved -Raw | ConvertFrom-Json
}

function Get-ExperimentLabels {
  param(
    [object]$Plan,
    [string]$Renderer,
    [string]$PropertyName
  )
  $Container = Get-ObjectPropertyValue $Plan $PropertyName
  return @(Get-StringListProperty $Container $Renderer)
}

function Get-BaseExperimentLabel {
  param(
    [object]$Plan,
    [string]$Renderer,
    [string]$CandidateFamily
  )

  $ExperimentLabels = @(Get-ExperimentLabels $Plan $Renderer "experiment_labels")
  $BaseLabels = @(Get-ExperimentLabels $Plan $Renderer "base_experiment_labels")
  for ($Index = 0; $Index -lt $ExperimentLabels.Count; $Index++) {
    if ($ExperimentLabels[$Index] -eq $CandidateFamily) {
      if ($Index -lt $BaseLabels.Count -and $BaseLabels[$Index]) {
        return $BaseLabels[$Index]
      }
      return $CandidateFamily
    }
  }

  if ($BaseLabels -contains $CandidateFamily) {
    return $CandidateFamily
  }

  $Suffix = Get-PlanLabelSuffix -Plan $Plan -Renderer $Renderer
  if ($Suffix -and $CandidateFamily.EndsWith($Suffix, [System.StringComparison]::Ordinal)) {
    $WithoutSuffix = $CandidateFamily.Substring(0, $CandidateFamily.Length - $Suffix.Length)
    if ($BaseLabels -contains $WithoutSuffix) {
      return $WithoutSuffix
    }
  }

  throw "Candidate family '$CandidateFamily' for $Renderer is not present in the targeted plan experiment labels. Regenerate targeted-blocker-experiment-plan.json with this candidate's matrix row."
}

function Get-ResultFilesForLabel {
  param(
    [string]$Label,
    [string]$Renderer,
    [string[]]$Scenes
  )
  return @($Scenes | ForEach-Object {
      Join-Path $Root "benchmarks\raw\$Label-$_-$Renderer.json"
    })
}

function Get-ExistingBaselineFiles {
  param(
    [object]$Plan,
    [string]$Renderer
  )
  $PropertyName = if ($Renderer -eq "webgpu") { "baseline_webgpu" } else { "baseline_webgl2" }
  $ResultFiles = Get-ObjectPropertyValue $Plan "result_files"
  return @(ConvertTo-Array (Get-ObjectPropertyValue $ResultFiles $PropertyName) | ForEach-Object {
      if ($_ -and $_.path) {
        [string]$_.path
      } else {
        [string]$_
      }
    } | Where-Object { $_ })
}

function Get-BaselinePromotionLabel {
  param(
    [object]$Plan,
    [string]$Renderer,
    [AllowNull()]
    [string]$LabelSuffixOverride = $null,
    [switch]$FreshProfileConfirmation
  )
  $BaseLabel = if ($Renderer -eq "webgpu") {
    if ($FreshProfileConfirmation) { "baseline-content-shell-suite-promotion-fresh-profile-webgpu" } else { "baseline-content-shell-suite-promotion-webgpu" }
  } else {
    if ($FreshProfileConfirmation) { "baseline-content-shell-suite-promotion-fresh-profile" } else { "baseline-content-shell-suite-promotion" }
  }
  $Suffix = if ([string]::IsNullOrEmpty($LabelSuffixOverride)) {
    Get-PlanLabelSuffix -Plan $Plan -Renderer $Renderer
  } else {
    $LabelSuffixOverride
  }
  return "$BaseLabel$Suffix"
}

function Get-FreshProfileConfirmationLabelSuffix {
  param(
    [object]$Plan,
    [string]$Renderer = ""
  )
  $Suffix = Get-PlanLabelSuffix -Plan $Plan -Renderer $Renderer
  return "$Suffix$FreshProfileConfirmationSuffix"
}

function Get-WebGpuPipelineQuietFrames {
  param([object]$Plan)
  $Value = Get-ObjectPropertyValue $Plan.options "webgpu_pipeline_quiet_frames"
  if ($null -eq $Value) {
    return 0
  }
  return [int]$Value
}

function Get-WebGpuPipelineQuietMaxFrames {
  param([object]$Plan)
  $QuietFrames = Get-WebGpuPipelineQuietFrames -Plan $Plan
  if ($QuietFrames -le 0) {
    return 0
  }
  $Value = Get-ObjectPropertyValue $Plan.options "webgpu_pipeline_quiet_max_frames"
  $MaxFrames = if ($null -eq $Value) { 30 } else { [int]$Value }
  return [Math]::Max($QuietFrames, $MaxFrames)
}

function New-FullSuiteBaselineCommand {
  param(
    [object]$Plan,
    [string]$Renderer,
    [string]$Label,
    [string[]]$Scenes,
    [switch]$FreshProfile
  )

  $Command = @(
    (Join-Path $Root "scripts\run_full_suite.ps1"),
    "-Browser", [string]$Plan.browsers.baseline,
    "-Renderer", $Renderer,
    "-Duration", [string]$Plan.options.duration,
    "-Warmup", [string]$Plan.options.warmup,
    "-Label", $Label,
    "-BuildArgs", [string]$Plan.build_args.baseline,
    "-Complexity", [string]$Plan.options.complexity,
    "-RequireGpuMetadata",
    "-PackageDir", [string]$Plan.package_dirs.baseline
  )
  if ($Plan.options.precompile -eq $true) {
    $Command += "-Precompile"
  }
  if ([int]$Plan.options.prerender_frames -gt 0) {
    $Command += @("-PrerenderFrames", [string]$Plan.options.prerender_frames)
  }
  if ($Plan.options.settle_gpu_after_warmup -eq $true) {
    $Command += "-SettleGpuAfterWarmup"
  }
  if ($Renderer -eq "webgpu" -and $Plan.options.disable_webgpu_timing -eq $true) {
    $Command += "-DisableGpuTiming"
  }
  $PipelineQuietFrames = Get-WebGpuPipelineQuietFrames -Plan $Plan
  if ($Renderer -eq "webgpu" -and $PipelineQuietFrames -gt 0) {
    $Command += @("-WebGpuPipelineQuietFrames", [string]$PipelineQuietFrames)
    $Command += @("-WebGpuPipelineQuietMaxFrames", [string](Get-WebGpuPipelineQuietMaxFrames -Plan $Plan))
  }
  $ProfileCacheKey = [string](Get-ObjectPropertyValue $Plan.options "webgpu_profile_cache_key")
  if ($Renderer -eq "webgpu" -and $ProfileCacheKey -and -not $FreshProfile) {
    $ProfileCacheRoot = [string](Get-ObjectPropertyValue $Plan.options "profile_cache_root")
    $Command += @("-ProfileCacheKey", $ProfileCacheKey)
    if ($ProfileCacheRoot) {
      $Command += @("-UserDataDirRoot", $ProfileCacheRoot)
    }
  }
  if ($DryRun) {
    $Command += "-DryRun"
  }
  return @($Command)
}

function New-FullSuiteExperimentCommand {
  param(
    [object]$Plan,
    [string]$Renderer,
    [string[]]$BaseLabels,
    [string[]]$Scenes,
    [AllowNull()]
    [string]$LabelSuffixOverride = $null,
    [switch]$FreshProfile
  )

  $Command = @(
    (Join-Path $Root "scripts\run_trusted_experiment_matrix.ps1"),
    "-Browser", [string]$Plan.browsers.fork,
    "-BuildArgs", [string]$Plan.build_args.fork,
    "-PackageDir", [string]$Plan.package_dirs.fork,
    "-Duration", [string]$Plan.options.duration,
    "-Warmup", [string]$Plan.options.warmup,
    "-Complexity", [string]$Plan.options.complexity,
    "-IncludeDefault",
    "-Renderer", $Renderer,
    "-Scenes", ($Scenes -join ",")
  )
  if ($Plan.options.precompile -eq $true) {
    $Command += "-Precompile"
  }
  if ([int]$Plan.options.prerender_frames -gt 0) {
    $Command += @("-PrerenderFrames", [string]$Plan.options.prerender_frames)
  }
  if ($Plan.options.settle_gpu_after_warmup -eq $true) {
    $Command += "-SettleGpuAfterWarmup"
  }
  $LabelSuffix = if ([string]::IsNullOrEmpty($LabelSuffixOverride)) {
    Get-PlanLabelSuffix -Plan $Plan -Renderer $Renderer
  } else {
    $LabelSuffixOverride
  }
  if ($LabelSuffix) {
    $Command += @("-LabelSuffix", $LabelSuffix)
  }
  if ($Plan.fork_revision) {
    $Command += @("-ForkRevision", [string]$Plan.fork_revision)
  }

  if ($Renderer -eq "webgl2") {
    $AngleBackends = @(Get-StringListProperty $Plan.options "webgl_angle_backend")
    if ($AngleBackends.Count -gt 0) {
      $Command += @("-AngleBackend", ($AngleBackends -join ","))
    }
    $Command += @("-IncludeZeroCopy", "-IncludeWebGlCompositorExperiments", "-IncludeReservedNoopGates")
  } elseif ($Renderer -eq "webgpu") {
    $Command += @("-IncludeSingleProcess", "-IncludeInProcessGpu", "-IncludeWebGpuDawnExperiments", "-IncludeWebGpuChromiumFeatureExperiments", "-IncludeWebGpuUploadExperiments")
    if ($Plan.options.disable_webgpu_timing -eq $true) {
      $Command += "-DisableGpuTiming"
    }
    $PipelineQuietFrames = Get-WebGpuPipelineQuietFrames -Plan $Plan
    if ($PipelineQuietFrames -gt 0) {
      $Command += @("-WebGpuPipelineQuietFrames", [string]$PipelineQuietFrames)
      $Command += @("-WebGpuPipelineQuietMaxFrames", [string](Get-WebGpuPipelineQuietMaxFrames -Plan $Plan))
    }
    $ProfileCacheKey = [string](Get-ObjectPropertyValue $Plan.options "webgpu_profile_cache_key")
    if ($ProfileCacheKey -and -not $FreshProfile) {
      $ProfileCacheRoot = [string](Get-ObjectPropertyValue $Plan.options "profile_cache_root")
      $Command += @("-ProfileCacheKey", $ProfileCacheKey)
      if ($ProfileCacheRoot) {
        $Command += @("-UserDataDirRoot", $ProfileCacheRoot)
      }
      if ($Plan.options.prime_webgpu_profile_cache -eq $true) {
        $Command += "-PrimeProfileCache"
      }
    }
  } else {
    throw "Unsupported renderer for promotion planning: $Renderer"
  }

  $Command += @("-ExperimentLabelFilter", ($BaseLabels -join ","))
  if ($DryRun) {
    $Command += "-DryRun"
  }
  return @($Command)
}

function New-PromotionAnalysisCommand {
  param(
    [object]$Plan,
    [string[]]$Renderers,
    [string[]]$Scenes,
    [double]$MinimumAverageFpsDeltaPct,
    [double]$PerSceneRegressionPct,
    [double]$DroppedFramesRegressionThreshold,
    [double]$CpuFrameRegressionThresholdMs,
    [double]$RenderSubmissionRegressionThresholdMs,
    [double]$PipelineCreateRegressionThresholdMs
  )

  $Command = @(
    "node",
    (Join-Path $Root "scripts\analyze_candidates.mjs"),
    "--fileList", (Resolve-RepoPath $PromotionInputList),
    "--output", $PromotionAnalysisOutput,
    "--json", $PromotionAnalysisJson,
    "--minMeasuredSeconds", [string]$Plan.post_run_analysis.min_measured_seconds,
    "--minScenes", [string]$Scenes.Count,
    "--minAvgFpsDeltaPct", [string]$MinimumAverageFpsDeltaPct,
    "--sceneRegressionPct", [string]$PerSceneRegressionPct,
    "--droppedFramesRegression", [string]$DroppedFramesRegressionThreshold,
    "--cpuFrameRegressionMs", [string]$CpuFrameRegressionThresholdMs,
    "--renderSubmissionRegressionMs", [string]$RenderSubmissionRegressionThresholdMs,
    "--pipelineCreateRegressionMs", [string]$PipelineCreateRegressionThresholdMs,
    "--requireFrameTimes",
    "--requireCheckout",
    "--requirePackageSize"
  )
  if ($Plan.post_run_analysis.expected_chromium_revision) {
    $Command += @("--expectedChromiumRevision", [string]$Plan.post_run_analysis.expected_chromium_revision)
  }
  if ($Plan.post_run_analysis.expected_fork_revision) {
    $Command += @("--expectedForkRevision", [string]$Plan.post_run_analysis.expected_fork_revision)
  }
  foreach ($Scene in $Scenes) {
    $Command += @("--requiredScene", $Scene)
  }
  foreach ($Renderer in $Renderers) {
    $Command += @("--requireCandidateRenderer", $Renderer)
  }
  return @($Command)
}

function Invoke-Step {
  param(
    [string]$Name,
    [object[]]$Command
  )

  Write-Host "== $Name =="
  Write-Host ($Command -join " ")
  if (-not $DryRun) {
    $Executable = [string]$Command[0]
    $Arguments = @($Command | Select-Object -Skip 1)
    & $Executable @Arguments
  }
}

if ($MaxProfilesPerRenderer -lt 1) {
  throw "MaxProfilesPerRenderer must be at least 1."
}
if ($RunComparableBaselines -and $NoComparableBaselines) {
  throw "Use only one of -RunComparableBaselines or -NoComparableBaselines."
}

$Triage = Read-JsonFile $TriageAnalysisJson
$TargetedPlan = Read-JsonFile $TargetedPlanManifest
$RequiredScenes = @(Get-StringListProperty $TargetedPlan.post_run_analysis "required_scenes")
if ($RequiredScenes.Count -eq 0) {
  $RequiredScenes = @($DefaultScenes)
}

if ($MinAvgFpsDeltaPct -lt 0) {
  $MinAvgFpsDeltaPct = [double]$TargetedPlan.post_run_analysis.min_avg_fps_delta_pct
}
if ($SceneRegressionPct -lt 0) {
  $SceneRegressionPct = [double]$TargetedPlan.post_run_analysis.scene_regression_pct
}
if ($DroppedFramesRegression -lt 0) {
  $DroppedFramesValue = Get-ObjectPropertyValue $TargetedPlan.post_run_analysis "dropped_frames_regression"
  $DroppedFramesRegression = if ($null -eq $DroppedFramesValue) { 0.0 } else { [double]$DroppedFramesValue }
}
if ($CpuFrameRegressionMs -lt 0) {
  $CpuFrameValue = Get-ObjectPropertyValue $TargetedPlan.post_run_analysis "cpu_frame_regression_ms"
  $CpuFrameRegressionMs = if ($null -eq $CpuFrameValue) { 0.5 } else { [double]$CpuFrameValue }
}
if ($RenderSubmissionRegressionMs -lt 0) {
  $RenderSubmissionValue = Get-ObjectPropertyValue $TargetedPlan.post_run_analysis "render_submission_regression_ms"
  $RenderSubmissionRegressionMs = if ($null -eq $RenderSubmissionValue) { 0.5 } else { [double]$RenderSubmissionValue }
}
if ($PipelineCreateRegressionMs -lt 0) {
  $PipelineCreateValue = Get-ObjectPropertyValue $TargetedPlan.post_run_analysis "pipeline_create_regression_ms"
  $PipelineCreateRegressionMs = if ($null -eq $PipelineCreateValue) { 1.0 } else { [double]$PipelineCreateValue }
}

$RequestedRenderers = @(Normalize-CommaSeparatedStringList $RequireCandidateRenderer)
$CandidateFamilies = @(ConvertTo-Array $Triage.families | Where-Object {
    $Renderer = ([string]$_.renderer).ToLowerInvariant()
    $Status = [string]$_.status
    $AverageFpsDelta = [double]$_.avg_fps_delta_pct
    ($Status -eq "candidate" -or $Status -eq "needs-suite") -and
    $AverageFpsDelta -ge $MinAvgFpsDeltaPct -and
    ($RequestedRenderers.Count -eq 0 -or $RequestedRenderers -contains $Renderer)
  })
$CacheAttributionFamilies = @(ConvertTo-Array $Triage.families | Where-Object {
    $Renderer = ([string]$_.renderer).ToLowerInvariant()
    $Status = [string]$_.status
    $AverageFpsDelta = [double]$_.avg_fps_delta_pct
    $Status -eq "cache-attribution" -and
    $AverageFpsDelta -ge $MinAvgFpsDeltaPct -and
    ($RequestedRenderers.Count -eq 0 -or $RequestedRenderers -contains $Renderer)
  })

$Promotions = [System.Collections.Generic.List[object]]::new()
foreach ($Group in ($CandidateFamilies | Group-Object { ([string]$_.renderer).ToLowerInvariant() })) {
  $Selected = @($Group.Group |
    Sort-Object @{ Expression = "avg_fps_delta_pct"; Descending = $true }, @{ Expression = "p99_frame_ms_delta"; Descending = $false } |
    Select-Object -First $MaxProfilesPerRenderer)
  foreach ($Family in $Selected) {
    $Renderer = ([string]$Family.renderer).ToLowerInvariant()
    $CandidateFamily = [string]$Family.candidate_family
    $BaseLabel = Get-BaseExperimentLabel -Plan $TargetedPlan -Renderer $Renderer -CandidateFamily $CandidateFamily
    $Promotions.Add([pscustomobject]@{
        renderer = $Renderer
        status = [string]$Family.status
        candidate_family = $CandidateFamily
        base_experiment_label = $BaseLabel
        baseline_family = [string]$Family.baseline_family
        triage_scenes = @(Get-StringListProperty $Family "scene_names")
        avg_fps_delta_pct = [double]$Family.avg_fps_delta_pct
        min_fps_delta_pct = [double]$Family.min_fps_delta_pct
        p99_frame_ms_delta = [double]$Family.p99_frame_ms_delta
      }) | Out-Null
  }
}

$CacheAttributionConfirmations = [System.Collections.Generic.List[object]]::new()
foreach ($Group in ($CacheAttributionFamilies | Group-Object { ([string]$_.renderer).ToLowerInvariant() })) {
  $Selected = @($Group.Group |
    Sort-Object @{ Expression = "avg_fps_delta_pct"; Descending = $true }, @{ Expression = "p99_frame_ms_delta"; Descending = $false } |
    Select-Object -First $MaxProfilesPerRenderer)
  foreach ($Family in $Selected) {
    $Renderer = ([string]$Family.renderer).ToLowerInvariant()
    $SourceCandidateFamily = [string]$Family.candidate_family
    $BaseLabel = Get-BaseExperimentLabel -Plan $TargetedPlan -Renderer $Renderer -CandidateFamily $SourceCandidateFamily
    $RendererFreshProfileConfirmationLabelSuffix = Get-FreshProfileConfirmationLabelSuffix -Plan $TargetedPlan -Renderer $Renderer
    $CacheAttributionConfirmations.Add([pscustomobject]@{
        renderer = $Renderer
        status = "fresh-profile-confirmation"
        source_status = [string]$Family.status
        source_candidate_family = $SourceCandidateFamily
        candidate_family = "$BaseLabel$RendererFreshProfileConfirmationLabelSuffix"
        base_experiment_label = $BaseLabel
        baseline_family = [string]$Family.baseline_family
        triage_scenes = @(Get-StringListProperty $Family "scene_names")
        avg_fps_delta_pct = [double]$Family.avg_fps_delta_pct
        min_fps_delta_pct = [double]$Family.min_fps_delta_pct
        p99_frame_ms_delta = [double]$Family.p99_frame_ms_delta
        source_profile_cache_mode = [string](Get-ObjectPropertyValue $Family "profile_cache_mode")
        source_profile_cache_key = [string](Get-ObjectPropertyValue $Family "profile_cache_key")
      }) | Out-Null
  }
}

$PromotionRenderers = @($Promotions | ForEach-Object { [string]$_.renderer } | Select-Object -Unique)
$ConfirmationRenderers = @($CacheAttributionConfirmations | ForEach-Object { [string]$_.renderer } | Select-Object -Unique)
$PlannedRenderers = @($PromotionRenderers + $ConfirmationRenderers | Select-Object -Unique)
$AnalysisRenderers = if ($RequestedRenderers.Count -gt 0) { @($RequestedRenderers) } else { @($PlannedRenderers) }
$ShouldRunComparableBaselines = if ($NoComparableBaselines) {
  $false
} elseif ($RunComparableBaselines) {
  $true
} else {
  $false
}

$Steps = [System.Collections.Generic.List[object]]::new()
$PromotionInputs = [System.Collections.Generic.List[string]]::new()

foreach ($Renderer in $PromotionRenderers) {
  $ExistingBaselineFiles = @(Get-ExistingBaselineFiles -Plan $TargetedPlan -Renderer $Renderer)
  if ($ShouldRunComparableBaselines -or $ExistingBaselineFiles.Count -eq 0) {
    $BaselineLabel = Get-BaselinePromotionLabel -Plan $TargetedPlan -Renderer $Renderer
    $BaselineCommand = @(New-FullSuiteBaselineCommand -Plan $TargetedPlan -Renderer $Renderer -Label $BaselineLabel -Scenes $RequiredScenes)
    if ($Renderer -eq "webgpu" -and $TargetedPlan.options.prime_webgpu_profile_cache -eq $true) {
      $Steps.Add([pscustomobject]@{
          name = "prime promotion $Renderer comparable baseline suite"
          command = @($BaselineCommand)
          command_line = $BaselineCommand -join " "
        }) | Out-Null
    }
    $Steps.Add([pscustomobject]@{
        name = "promotion $Renderer comparable baseline suite"
        command = @($BaselineCommand)
        command_line = $BaselineCommand -join " "
      }) | Out-Null
    foreach ($PathValue in (Get-ResultFilesForLabel -Label $BaselineLabel -Renderer $Renderer -Scenes $RequiredScenes)) {
      $PromotionInputs.Add($PathValue) | Out-Null
    }
  } else {
    foreach ($PathValue in $ExistingBaselineFiles) {
      $PromotionInputs.Add($PathValue) | Out-Null
    }
  }

  $RendererPromotions = @($Promotions | Where-Object { $_.renderer -eq $Renderer })
  $BaseLabels = @($RendererPromotions | ForEach-Object { [string]$_.base_experiment_label } | Select-Object -Unique)
  $ExperimentCommand = @(New-FullSuiteExperimentCommand -Plan $TargetedPlan -Renderer $Renderer -BaseLabels $BaseLabels -Scenes $RequiredScenes)
  $Steps.Add([pscustomobject]@{
      name = "promotion $Renderer full-suite candidate matrix"
      command = @($ExperimentCommand)
      command_line = $ExperimentCommand -join " "
    }) | Out-Null

  foreach ($Promotion in $RendererPromotions) {
    foreach ($PathValue in (Get-ResultFilesForLabel -Label $Promotion.candidate_family -Renderer $Renderer -Scenes $RequiredScenes)) {
      $PromotionInputs.Add($PathValue) | Out-Null
    }
  }
}

foreach ($Renderer in $ConfirmationRenderers) {
  $RendererFreshProfileConfirmationLabelSuffix = Get-FreshProfileConfirmationLabelSuffix -Plan $TargetedPlan -Renderer $Renderer
  $BaselineLabel = Get-BaselinePromotionLabel `
    -Plan $TargetedPlan `
    -Renderer $Renderer `
    -LabelSuffixOverride $RendererFreshProfileConfirmationLabelSuffix `
    -FreshProfileConfirmation
  $BaselineCommand = @(New-FullSuiteBaselineCommand `
      -Plan $TargetedPlan `
      -Renderer $Renderer `
      -Label $BaselineLabel `
      -Scenes $RequiredScenes `
      -FreshProfile)
  $Steps.Add([pscustomobject]@{
      name = "fresh-profile confirmation $Renderer comparable baseline suite"
      command = @($BaselineCommand)
      command_line = $BaselineCommand -join " "
    }) | Out-Null
  foreach ($PathValue in (Get-ResultFilesForLabel -Label $BaselineLabel -Renderer $Renderer -Scenes $RequiredScenes)) {
    $PromotionInputs.Add($PathValue) | Out-Null
  }

  $RendererConfirmations = @($CacheAttributionConfirmations | Where-Object { $_.renderer -eq $Renderer })
  $BaseLabels = @($RendererConfirmations | ForEach-Object { [string]$_.base_experiment_label } | Select-Object -Unique)
  $ExperimentCommand = @(New-FullSuiteExperimentCommand `
      -Plan $TargetedPlan `
      -Renderer $Renderer `
      -BaseLabels $BaseLabels `
      -Scenes $RequiredScenes `
      -LabelSuffixOverride $RendererFreshProfileConfirmationLabelSuffix `
      -FreshProfile)
  $Steps.Add([pscustomobject]@{
      name = "fresh-profile confirmation $Renderer full-suite candidate matrix"
      command = @($ExperimentCommand)
      command_line = $ExperimentCommand -join " "
    }) | Out-Null

  foreach ($Confirmation in $RendererConfirmations) {
    foreach ($PathValue in (Get-ResultFilesForLabel -Label $Confirmation.candidate_family -Renderer $Renderer -Scenes $RequiredScenes)) {
      $PromotionInputs.Add($PathValue) | Out-Null
    }
  }
}

if ($Promotions.Count -gt 0 -or $CacheAttributionConfirmations.Count -gt 0) {
  $AnalysisCommand = @(New-PromotionAnalysisCommand `
      -Plan $TargetedPlan `
      -Renderers $AnalysisRenderers `
      -Scenes $RequiredScenes `
      -MinimumAverageFpsDeltaPct $MinAvgFpsDeltaPct `
      -PerSceneRegressionPct $SceneRegressionPct `
      -DroppedFramesRegressionThreshold $DroppedFramesRegression `
      -CpuFrameRegressionThresholdMs $CpuFrameRegressionMs `
      -RenderSubmissionRegressionThresholdMs $RenderSubmissionRegressionMs `
      -PipelineCreateRegressionThresholdMs $PipelineCreateRegressionMs)
  $Steps.Add([pscustomobject]@{
      name = "promotion full-suite candidate speed analysis"
      command = @($AnalysisCommand)
      command_line = $AnalysisCommand -join " "
    }) | Out-Null
}

$UniquePromotionInputs = @($PromotionInputs | Select-Object -Unique)
$PromotionInputDigest = Get-AnalyzerInputDigest $UniquePromotionInputs

$InputListPath = Resolve-RepoPath $PromotionInputList
$InputListDir = Split-Path -Parent $InputListPath
if ($InputListDir) {
  New-Item -ItemType Directory -Path $InputListDir -Force | Out-Null
}
Set-Content -LiteralPath $InputListPath -Encoding UTF8 -Value $UniquePromotionInputs

$ManifestPath = Resolve-RepoPath $PromotionPlanManifest
$ManifestDir = Split-Path -Parent $ManifestPath
if ($ManifestDir) {
  New-Item -ItemType Directory -Path $ManifestDir -Force | Out-Null
}

$Manifest = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  dry_run = [bool]$DryRun
  phase = if ($DryRun) { "planned" } else { "completed" }
  triage_analysis_json = Resolve-RepoPath $TriageAnalysisJson
  targeted_plan_manifest = Resolve-RepoPath $TargetedPlanManifest
  promotion_plan_manifest = $ManifestPath
  chromium_revision = [string]$TargetedPlan.chromium_revision
  fork_revision = [string]$TargetedPlan.fork_revision
  options = [pscustomobject]@{
    duration = $TargetedPlan.options.duration
    warmup = $TargetedPlan.options.warmup
    complexity = $TargetedPlan.options.complexity
    precompile = [bool]$TargetedPlan.options.precompile
    prerender_frames = [int]$TargetedPlan.options.prerender_frames
    settle_gpu_after_warmup = [bool]$TargetedPlan.options.settle_gpu_after_warmup
    webgpu_pipeline_quiet_frames = Get-WebGpuPipelineQuietFrames -Plan $TargetedPlan
    webgpu_pipeline_quiet_max_frames = Get-WebGpuPipelineQuietMaxFrames -Plan $TargetedPlan
    label_suffix = Get-PlanLabelSuffix -Plan $TargetedPlan
    webgl2_label_suffix = Get-PlanLabelSuffix -Plan $TargetedPlan -Renderer "webgl2"
    webgpu_label_suffix = Get-PlanLabelSuffix -Plan $TargetedPlan -Renderer "webgpu"
    disable_webgpu_timing = [bool]$TargetedPlan.options.disable_webgpu_timing
    webgpu_profile_cache_key = Get-ObjectPropertyValue $TargetedPlan.options "webgpu_profile_cache_key"
    webgpu_profile_cache_mode = Get-ObjectPropertyValue $TargetedPlan.options "webgpu_profile_cache_mode"
    profile_cache_root = Get-ObjectPropertyValue $TargetedPlan.options "profile_cache_root"
    prime_webgpu_profile_cache = [bool](Get-ObjectPropertyValue $TargetedPlan.options "prime_webgpu_profile_cache")
    profile_cache_policy = Get-ObjectPropertyValue $TargetedPlan.options "profile_cache_policy"
    profile_cache_prime_policy = Get-ObjectPropertyValue $TargetedPlan.options "profile_cache_prime_policy"
    run_comparable_baselines = [bool]$ShouldRunComparableBaselines
    max_profiles_per_renderer = $MaxProfilesPerRenderer
    fresh_profile_confirmation_label_suffix = Get-FreshProfileConfirmationLabelSuffix -Plan $TargetedPlan
    webgl2_fresh_profile_confirmation_label_suffix = Get-FreshProfileConfirmationLabelSuffix -Plan $TargetedPlan -Renderer "webgl2"
    webgpu_fresh_profile_confirmation_label_suffix = Get-FreshProfileConfirmationLabelSuffix -Plan $TargetedPlan -Renderer "webgpu"
  }
  required_scenes = @($RequiredScenes)
  required_candidate_renderers = @($AnalysisRenderers)
  promotion_profiles = @($Promotions)
  cache_attribution_confirmations = @($CacheAttributionConfirmations)
  generated_input_list = $InputListPath
  generated_input_count = $UniquePromotionInputs.Count
  analysis = [pscustomobject]@{
    output = $PromotionAnalysisOutput
    json = $PromotionAnalysisJson
    min_measured_seconds = $TargetedPlan.post_run_analysis.min_measured_seconds
    min_avg_fps_delta_pct = $MinAvgFpsDeltaPct
    min_scenes = $RequiredScenes.Count
    scene_regression_pct = $SceneRegressionPct
    dropped_frames_regression = $DroppedFramesRegression
    cpu_frame_regression_ms = $CpuFrameRegressionMs
    render_submission_regression_ms = $RenderSubmissionRegressionMs
    pipeline_create_regression_ms = $PipelineCreateRegressionMs
    require_frame_times = $true
    require_checkout = $true
    require_package_size = $true
    expected_input_file_digest = $PromotionInputDigest
    expected_chromium_revision = [string]$TargetedPlan.post_run_analysis.expected_chromium_revision
    expected_fork_revision = [string]$TargetedPlan.post_run_analysis.expected_fork_revision
  }
  steps = @($Steps)
}

$Manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

if ($Promotions.Count -eq 0 -and $CacheAttributionConfirmations.Count -eq 0) {
  Write-Host "No suite-promotion candidates found in $TriageAnalysisJson at minAvgFpsDeltaPct=$MinAvgFpsDeltaPct."
} else {
  foreach ($Step in $Steps) {
    Invoke-Step -Name $Step.name -Command @($Step.command)
  }
}
Write-Host "Wrote suite-promotion plan: $ManifestPath"
Write-Host "Wrote suite-promotion analyzer inputs: $InputListPath"

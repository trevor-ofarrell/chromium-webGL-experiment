[CmdletBinding()]
param(
  [string]$Output = "docs\prompt_to_artifact_checklist.md",
  [switch]$FailOnIncomplete,
  [string]$EnvironmentManifest = "benchmarks\reports\prebuild-environment.json",
  [switch]$ManifestAuditOnly,
  [switch]$PatchStateOnly,
  [switch]$BuildStateOnly,
  [switch]$ReportStateOnly,
  [switch]$StabilityOnly,
  [switch]$OptimizationOnly,
  [switch]$DocumentationOnly,
  [switch]$TestAssumeViewerPatchAlreadyApplied
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ExclusiveModes = @($ManifestAuditOnly, $PatchStateOnly, $BuildStateOnly, $ReportStateOnly, $StabilityOnly, $OptimizationOnly, $DocumentationOnly) | Where-Object { $_ }
if ($ExclusiveModes.Count -gt 1) {
  throw "-ManifestAuditOnly, -PatchStateOnly, -BuildStateOnly, -ReportStateOnly, -StabilityOnly, -OptimizationOnly, and -DocumentationOnly cannot be combined."
}
if ($TestAssumeViewerPatchAlreadyApplied -and -not $PatchStateOnly) {
  throw "-TestAssumeViewerPatchAlreadyApplied is only valid with -PatchStateOnly."
}
if ($env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -and
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ne "1") {
  throw "THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
}
if ($env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST -and
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ne "1") {
  throw "THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
}
if ($env:THREE_BROWSER_TEST_OPTIMIZATION_LOG -and
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ne "1") {
  throw "THREE_BROWSER_TEST_OPTIMIZATION_LOG requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
}
if ($env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC -and
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ne "1") {
  throw "THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
}
if ($env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS -and
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ne "1") {
  throw "THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
}
if (($env:THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT -or $env:THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT) -and
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ne "1") {
  throw "THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT and THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT require THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
}
$RevisionFile = Join-Path $Root ".chromium_revision"
if (-not (Test-Path $RevisionFile)) {
  throw "Pinned Chromium revision file missing: $RevisionFile"
}
$ExpectedChromiumRevision = (Get-Content $RevisionFile -Raw).Trim()
if (-not $ExpectedChromiumRevision) {
  throw "Pinned Chromium revision file is empty: $RevisionFile"
}
$RequiredScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)
$DefaultStabilityMaxRssDeltaMb = 128
$DefaultStabilityMaxRendererResourceDelta = 0
$RequiredBrowserFlags = @("--disable-software-rasterizer")
$RequiredMetricFields = @(
  "chromium_revision",
  "fork_revision",
  "build_args_hash",
  "platform",
  "gpu_name",
  "driver_version",
  "angle_backend",
  "renderer_type",
  "scene_name",
  "warmup_seconds",
  "measured_seconds",
  "avg_fps",
  "p50_frame_ms",
  "p95_frame_ms",
  "p99_frame_ms",
  "one_percent_low_fps",
  "point_one_percent_low_fps",
  "avg_cpu_frame_ms",
  "avg_gpu_frame_ms",
  "avg_js_frame_ms",
  "avg_render_submission_ms",
  "avg_compositor_latency_ms",
  "avg_presentation_latency_ms",
  "max_frame_ms",
  "dropped_frames",
  "draw_calls",
  "triangles",
  "texture_upload_mb",
  "buffer_upload_mb",
  "shader_compile_events",
  "js_heap_mb",
  "gpu_memory_mb",
  "process_rss_mb",
  "startup_ms_to_first_frame",
  "browser_binary_size_mb",
  "viewer_bundle_size_mb",
  "package_size_mb"
)
$PromptOptimizationClasses = @(
  "remove Chrome browser UI layer",
  "minimal content shell style entrypoint",
  "single local trusted origin",
  "disable extensions",
  "disable sync",
  "disable autofill",
  "disable translate",
  "disable spellcheck",
  "disable safe browsing services not needed for local trusted content",
  "disable downloads UI",
  "disable history/bookmarks UI",
  "disable unnecessary profile services",
  "disable unnecessary background networking",
  "reduce renderer process overhead where possible",
  "evaluate single-process/in-process GPU",
  "evaluate ANGLE backend choices",
  "evaluate platform GPU backends",
  "evaluate passthrough command decoder",
  "evaluate WebGL validation overhead",
  "evaluate shader compilation strategy",
  "evaluate WebGPU pipeline caching/warmup",
  "evaluate compositor bypass or simplified presentation path",
  "evaluate direct GPU texture presentation/export",
  "evaluate removing unused Blink modules",
  "evaluate disabling layout/style/DOM features not required by viewer",
  "evaluate disabling media, printing, PDF, WebRTC, accessibility, password manager, payments",
  "evaluate V8 flags",
  "evaluate memory allocator and process model choices"
)

$Rows = [System.Collections.Generic.List[object]]::new()

function Resolve-RepoPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return (Join-Path $Root $PathValue)
}

function Test-RepoPath {
  param([string]$PathValue)
  return Test-Path (Resolve-RepoPath $PathValue)
}

function Test-ManifestPathOverrideEnabled {
  return $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -eq "1"
}

function Get-OfficialComparisonManifestPathValue {
  if ($env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST) {
    if (-not (Test-ManifestPathOverrideEnabled)) {
      throw "THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
    }
    return $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
  }
  return "benchmarks\reports\official-comparison-manifest.json"
}

function Get-TrustedMatrixManifestPathValue {
  if ($env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST) {
    if (-not (Test-ManifestPathOverrideEnabled)) {
      throw "THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
    }
    return $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST
  }
  return "benchmarks\reports\trusted-experiment-matrix-manifest.json"
}

function Get-OfficialWebGl2ReportPathValue {
  if ($env:THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT) {
    if (-not (Test-ManifestPathOverrideEnabled)) {
      throw "THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
    }
    return $env:THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT
  }
  return "benchmarks\reports\official-webgl2-comparison.md"
}

function Get-OfficialWebGpuReportPathValue {
  if ($env:THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT) {
    if (-not (Test-ManifestPathOverrideEnabled)) {
      throw "THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
    }
    return $env:THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT
  }
  return "benchmarks\reports\official-webgpu-comparison.md"
}

function Get-OptimizationLogPathValue {
  if ($env:THREE_BROWSER_TEST_OPTIMIZATION_LOG) {
    if (-not (Test-ManifestPathOverrideEnabled)) {
      throw "THREE_BROWSER_TEST_OPTIMIZATION_LOG requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
    }
    return $env:THREE_BROWSER_TEST_OPTIMIZATION_LOG
  }
  return "docs\optimization_log.md"
}

function Get-RemovedSubsystemsPathValue {
  if ($env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC) {
    if (-not (Test-ManifestPathOverrideEnabled)) {
      throw "THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
    }
    return $env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC
  }
  return "docs\removed_subsystems.md"
}

function Get-PerformanceClaimDocPathValues {
  if ($env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS) {
    if (-not (Test-ManifestPathOverrideEnabled)) {
      throw "THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS requires THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES=1."
    }
    return @($env:THREE_BROWSER_TEST_PERFORMANCE_CLAIM_DOCS -split ";")
  }

  $Docs = [System.Collections.Generic.List[string]]::new()
  $Docs.Add("README.md") | Out-Null
  $DocsDir = Resolve-RepoPath "docs"
  if (Test-Path -LiteralPath $DocsDir) {
    Get-ChildItem -LiteralPath $DocsDir -Filter "*.md" -File |
      Where-Object { $_.Name -ne "prompt_to_artifact_checklist.md" } |
      Sort-Object FullName |
      ForEach-Object {
        $Docs.Add((Resolve-Path -LiteralPath $_.FullName -Relative)) | Out-Null
      }
  }
  return @($Docs)
}

function Count-RepoFiles {
  param([string]$Pattern)
  return @(Get-ChildItem -Path (Resolve-RepoPath $Pattern) -File -ErrorAction SilentlyContinue).Count
}

function Get-FileHashString {
  param([string]$PathValue)
  $Resolved = Resolve-RepoPath $PathValue
  if (-not (Test-Path $Resolved)) {
    return ""
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Resolved).Hash.ToLowerInvariant()
}

function Escape-Markdown {
  param([string]$Text)
  if ($null -eq $Text) {
    return ""
  }
  return ($Text -replace "\|", "\|") -replace "`r?`n", "<br>"
}

function Add-AuditRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$Status,
    [string]$Evidence,
    [string]$Remaining
  )
  $Rows.Add([pscustomobject]@{
    Area = $Area
    Requirement = $Requirement
    Status = $Status
    Evidence = $Evidence
    Remaining = $Remaining
  }) | Out-Null
}

function Add-FileRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string[]]$Paths,
    [string]$Remaining = ""
  )
  $Missing = @($Paths | Where-Object { -not (Test-RepoPath $_) })
  if ($Missing.Count -eq 0) {
    Add-AuditRow $Area $Requirement "done" ($Paths -join ", ") $Remaining
  } else {
    Add-AuditRow $Area $Requirement "missing" ("Missing: " + ($Missing -join ", ")) $Remaining
  }
}

function Add-BinaryFileRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$PathValue,
    [string]$Remaining = ""
  )

  $Resolved = Resolve-RepoPath $PathValue
  if (-not (Test-Path -LiteralPath $Resolved)) {
    Add-AuditRow $Area $Requirement "missing" "Missing: $PathValue" $Remaining
    return
  }

  $Item = Get-Item -LiteralPath $Resolved
  if (-not $Item.PSIsContainer -and $Item.Length -gt 0) {
    $Hash = Get-FileHashString $PathValue
    Add-AuditRow $Area $Requirement "done" "$PathValue size_bytes=$($Item.Length) sha256=$Hash" $Remaining
    return
  }

  Add-AuditRow $Area $Requirement "pending" "$PathValue exists but is not a non-empty executable file" $Remaining
}

function Add-GnArgsMatchRow {
  param(
    [string]$Requirement,
    [string]$GeneratedPath,
    [string]$TemplatePath,
    [string]$Remaining
  )

  if (-not (Test-RepoPath $TemplatePath)) {
    Add-AuditRow "Build" $Requirement "missing" "Template missing: $TemplatePath" "Restore the checked-in GN args template."
    return
  }
  if (-not (Test-RepoPath $GeneratedPath)) {
    Add-AuditRow "Build" $Requirement "pending" "$GeneratedPath missing" $Remaining
    return
  }

  $GeneratedHash = Get-FileHashString $GeneratedPath
  $TemplateHash = Get-FileHashString $TemplatePath
  if ($GeneratedHash -eq $TemplateHash) {
    Add-AuditRow "Build" $Requirement "done" "$GeneratedPath sha256 matches $TemplatePath ($GeneratedHash)" $Remaining
  } else {
    Add-AuditRow "Build" $Requirement "blocked" "$GeneratedPath sha256=$GeneratedHash differs from $TemplatePath sha256=$TemplateHash" "Refresh generated args through scripts/build_chromium.ps1 -OverwriteArgs or inspect intentional local changes."
  }
}

function Add-GlobCountRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$Pattern,
    [int]$ExpectedCount,
    [string]$Remaining
  )
  $Count = Count-RepoFiles $Pattern
  if ($Count -ge $ExpectedCount) {
    Add-AuditRow $Area $Requirement "done" "$Pattern count=$Count expected>=$ExpectedCount" $Remaining
  } else {
    Add-AuditRow $Area $Requirement "pending" "$Pattern count=$Count expected>=$ExpectedCount" $Remaining
  }
}

function Test-MetricJsonOk {
  param([string]$PathValue)
  if (-not (Test-RepoPath $PathValue)) {
    return $false
  }
  $Validator = Resolve-RepoPath "scripts\validate_metrics.mjs"
  if (-not (Test-Path $Validator)) {
    return $false
  }
  $Resolved = Resolve-RepoPath $PathValue
  $null = (& node $Validator $Resolved 2>&1)
  return $LASTEXITCODE -eq 0
}

function Count-ValidMetricFiles {
  param([string]$Pattern)
  $Files = @(Get-ChildItem -Path (Resolve-RepoPath $Pattern) -File -ErrorAction SilentlyContinue)
  $Valid = 0
  foreach ($File in $Files) {
    if (Test-MetricJsonOk $File.FullName) {
      $Valid += 1
    }
  }
  return [pscustomobject]@{
    Total = $Files.Count
    Valid = $Valid
  }
}

function Add-MetricGlobCountRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$Pattern,
    [int]$ExpectedCount,
    [string]$Remaining
  )
  $Counts = Count-ValidMetricFiles $Pattern
  if ($Counts.Valid -ge $ExpectedCount) {
    Add-AuditRow $Area $Requirement "done" "$Pattern count=$($Counts.Total) valid=$($Counts.Valid) expected>=$ExpectedCount" $Remaining
  } else {
    Add-AuditRow $Area $Requirement "pending" "$Pattern count=$($Counts.Total) valid=$($Counts.Valid) expected>=$ExpectedCount" $Remaining
  }
}

function Invoke-TraceResultValidator {
  param(
    [string]$File,
    [string]$ExpectedScene,
    [string]$ExpectedRenderer,
    [string]$ExpectedBrowser,
    [int]$ExpectedDuration,
    [int]$ExpectedWarmup,
    [int]$ExpectedStartDelayMs,
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @()
  )

  $Validator = Resolve-RepoPath "scripts\validate_trace_result.mjs"
  if (-not (Test-Path $Validator)) {
    return [pscustomobject]@{
      Ok = $false
      Output = "scripts\validate_trace_result.mjs missing"
    }
  }

  $Resolved = Resolve-RepoPath $File
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $CommandArgs = @(
      "--expectedScene", $ExpectedScene,
      "--expectedRenderer", $ExpectedRenderer,
      "--expectedBrowser", $ExpectedBrowser,
      "--expectedDuration", ([string]$ExpectedDuration),
      "--expectedWarmup", ([string]$ExpectedWarmup),
      "--expectedStartDelayMs", ([string]$ExpectedStartDelayMs)
    )
    foreach ($Metadata in $ExpectedFlagMetadata) {
      $CommandArgs += @("--expectedFlagMetadata", $Metadata)
    }
    foreach ($Flag in $RequiredBrowserFlags) {
      $CommandArgs += @("--requiredBrowserFlag", $Flag)
    }
    $CommandArgs += $Resolved
    $Output = & node $Validator @CommandArgs 2>&1
    return [pscustomobject]@{
      Ok = ($LASTEXITCODE -eq 0)
      Output = ($Output | ForEach-Object { [string]$_ }) -join " "
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Invoke-TraceFileValidator {
  param(
    [string]$File,
    [int]$MinEvents = 1
  )

  $Validator = Resolve-RepoPath "scripts\validate_trace_file.mjs"
  if (-not (Test-Path $Validator)) {
    return [pscustomobject]@{
      Ok = $false
      Output = "scripts\validate_trace_file.mjs missing"
    }
  }

  $Resolved = Resolve-RepoPath $File
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node $Validator "--minEvents" ([string]$MinEvents) $Resolved 2>&1
    return [pscustomobject]@{
      Ok = ($LASTEXITCODE -eq 0)
      Output = ($Output | ForEach-Object { [string]$_ }) -join " "
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Invoke-StabilityValidator {
  param(
    [string]$File,
    [string]$ExpectedVariant,
    [switch]$RequireForkRevision,
    [switch]$RequirePackageSize,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [string]$ExpectedForkRevision = "",
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @()
  )

  $Validator = Resolve-RepoPath "scripts\validate_stability_result.mjs"
  if (-not (Test-Path $Validator)) {
    return [pscustomobject]@{
      Ok = $false
      Output = "scripts\validate_stability_result.mjs missing"
    }
  }

  $Args = @(
    $Validator,
    $File,
    "--minMeasuredSeconds", "3600",
    "--minWarmupSeconds", "30",
    "--expectedRenderer", "webgl2",
    "--expectedScene", "instancing",
    "--expectedVariant", $ExpectedVariant,
    "--requireCheckout",
    "--requireBuildArgs",
    "--expectedChromiumRevision", $ExpectedChromiumRevision,
    "--rejectSoftwareRendering",
    "--requireGpuMetadata",
    "--maxRssDeltaMb", ([string]$DefaultStabilityMaxRssDeltaMb),
    "--maxRendererResourceDelta", ([string]$DefaultStabilityMaxRendererResourceDelta)
  )
  if ($ExpectedBrowser) {
    $Args += @("--expectedBrowser", $ExpectedBrowser)
  }
  $Args += @("--pinRefreshManifest", (Resolve-RepoPath "benchmarks\reports\chromium-pin-refresh.json"))
  if ($RequireForkRevision) {
    $Args += "--requireForkRevision"
  }
  if ($RequirePackageSize) {
    $Args += "--requirePackageSize"
  }
  if ($ExpectedForkRevision) {
    $Args += @("--expectedForkRevision", $ExpectedForkRevision)
  }
  foreach ($Metadata in $ExpectedFlagMetadata) {
    $Args += @("--expectedFlagMetadata", $Metadata)
  }
  foreach ($Flag in $RequiredBrowserFlags) {
    $Args += @("--requiredBrowserFlag", $Flag)
  }

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $OutputText = (& node @Args 2>&1)
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  return [pscustomobject]@{
    Ok = ($LASTEXITCODE -eq 0)
    Output = ($OutputText -join " ")
  }
}

function Get-StabilityResultEvidence {
  param(
    [string]$Pattern,
    [string]$ExpectedVariant,
    [switch]$RequireForkRevision,
    [switch]$RequirePackageSize,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [string]$ExpectedForkRevision = "",
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @()
  )

  $Files = @(Get-ChildItem -Path (Resolve-RepoPath $Pattern) -File -ErrorAction SilentlyContinue)
  $Valid = 0
  $LastOutput = ""
  foreach ($File in $Files) {
    $MetricOk = Test-MetricJsonOk $File.FullName
    if (-not $MetricOk) {
      $LastOutput = "$($File.Name): metric schema validation failed"
      continue
    }
    $Validation = Invoke-StabilityValidator `
      -File $File.FullName `
      -ExpectedVariant $ExpectedVariant `
      -RequireForkRevision:$RequireForkRevision `
      -RequirePackageSize:$RequirePackageSize `
      -ExpectedChromiumRevision $ExpectedChromiumRevision `
      -ExpectedBrowser $ExpectedBrowser `
      -ExpectedForkRevision $ExpectedForkRevision `
      -ExpectedFlagMetadata $ExpectedFlagMetadata `
      -RequiredBrowserFlags $RequiredBrowserFlags
    if ($Validation.Ok) {
      $Valid += 1
    } else {
      $LastOutput = "$($File.Name): $($Validation.Output)"
    }
  }

  $Evidence = "$Pattern count=$($Files.Count) valid=$Valid expected>=1 with one-hour duration, checkout/build metadata, pinned Chromium revision, expected browser executable, hardware GPU metadata, package-size evidence, viewer flag metadata, required browser flags, RSS delta <= $DefaultStabilityMaxRssDeltaMb MB, and renderer resource delta <= $DefaultStabilityMaxRendererResourceDelta"
  if ($LastOutput) {
    $Evidence = "$Evidence; last validation: $LastOutput"
  }

  return [pscustomobject]@{
    Ok = ($Valid -ge 1)
    Files = $Files.Count
    Valid = $Valid
    LastOutput = $LastOutput
    Evidence = $Evidence
  }
}

function Add-StabilityResultRow {
  param(
    [string]$Requirement,
    [string]$Pattern,
    [string]$ExpectedVariant,
    [switch]$RequireForkRevision,
    [switch]$RequirePackageSize,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [string]$ExpectedForkRevision = "",
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @(),
    [string]$Remaining
  )

  $Result = Get-StabilityResultEvidence `
    -Pattern $Pattern `
    -ExpectedVariant $ExpectedVariant `
    -RequireForkRevision:$RequireForkRevision `
    -RequirePackageSize:$RequirePackageSize `
    -ExpectedChromiumRevision $ExpectedChromiumRevision `
    -ExpectedBrowser $ExpectedBrowser `
    -ExpectedForkRevision $ExpectedForkRevision `
    -ExpectedFlagMetadata $ExpectedFlagMetadata `
    -RequiredBrowserFlags $RequiredBrowserFlags

  if ($Result.Ok) {
    Add-AuditRow "Stability" $Requirement "done" $Result.Evidence $Remaining
  } else {
    Add-AuditRow "Stability" $Requirement "pending" $Result.Evidence $Remaining
  }
}

function Add-StabilityBehaviorDocumentationRow {
  param(
    [string[]]$BaselineStabilityFlags,
    [string[]]$ForkStabilityFlags,
    [string]$ExpectedForkRevision
  )

  $PathValue = "docs\stability_behavior.md"
  if (-not (Test-RepoPath $PathValue)) {
    Add-AuditRow "Stability" "Stability behavior documentation" "missing" "$PathValue missing" "Restore stability behavior documentation."
    return
  }

  $Content = Get-Content -LiteralPath (Resolve-RepoPath $PathValue) -Raw
  $RequiredTerms = @(
    "WebGL Context Loss",
    "WebGPU Device Loss",
    "GPU process crash/restart",
    "baseline-content-shell-long-stability",
    "fork-viewer-default-long-stability",
    "process_rss_delta_mb <= 128",
    "zero renderer resource growth"
  )
  $MissingTerms = @($RequiredTerms | Where-Object { -not $Content.Contains($_) })
  if ($MissingTerms.Count -gt 0) {
    Add-AuditRow "Stability" "Stability behavior documentation" "pending" "$PathValue missing required stability documentation terms: $($MissingTerms -join ', ')" "Document WebGL/WebGPU loss behavior, GPU process crash/restart behavior, the exact stock/fork one-hour evidence labels, RSS threshold, and renderer resource-growth threshold."
    return
  }

  $BaselineEvidence = Get-StabilityResultEvidence `
    -Pattern "benchmarks\raw\baseline-content-shell*long-stability*.json" `
    -ExpectedVariant "baseline-content-shell-long-stability" `
    -RequirePackageSize `
    -ExpectedChromiumRevision $ExpectedChromiumRevision `
    -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseBaseline\content_shell.exe") `
    -ExpectedFlagMetadata $BaselineStabilityFlags `
    -RequiredBrowserFlags $RequiredBrowserFlags
  $ForkEvidence = Get-StabilityResultEvidence `
    -Pattern "benchmarks\raw\fork-viewer-default*long-stability*.json" `
    -ExpectedVariant "fork-viewer-default-long-stability" `
    -RequireForkRevision `
    -RequirePackageSize `
    -ExpectedChromiumRevision $ExpectedChromiumRevision `
    -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe") `
    -ExpectedForkRevision $ExpectedForkRevision `
    -ExpectedFlagMetadata $ForkStabilityFlags `
    -RequiredBrowserFlags $RequiredBrowserFlags

  if (-not $BaselineEvidence.Ok -or -not $ForkEvidence.Ok) {
    Add-AuditRow "Stability" "Stability behavior documentation" "pending" "$PathValue documents smoke/instrumentation behavior, but official one-hour stability evidence is incomplete: stock=[$($BaselineEvidence.Evidence)] fork=[$($ForkEvidence.Evidence)]" "After stock/fork one-hour stability passes, update this document with actual GPU process crash/restart, WebGL context-loss, WebGPU device-loss, RSS, and renderer resource-growth behavior."
    return
  }

  if ($Content -match "remain pending|still pending|pending until|must still") {
    Add-AuditRow "Stability" "Stability behavior documentation" "pending" "$PathValue has validated stock/fork one-hour evidence available, but still contains pending-evidence language" "Replace pending smoke-only wording with actual stock/fork one-hour stability behavior and result artifact paths."
    return
  }

  Add-AuditRow "Stability" "Stability behavior documentation" "done" "$PathValue documents WebGL context loss, WebGPU device loss, GPU process crash/restart behavior, validated stock/fork one-hour stability labels, RSS threshold, and zero renderer resource growth after warmup" "Keep this in sync with future stability reruns."
}

function Invoke-BenchmarkSuiteValidator {
  param(
    [string[]]$Files,
    [string]$Renderer,
    [string]$Variant = "",
    [switch]$RequireCheckout,
    [switch]$RequireBuildArgs,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [switch]$RequireForkRevision,
    [string]$ExpectedForkRevision = "",
    [switch]$ForbidSmoke,
    [switch]$RejectSoftwareRendering,
    [switch]$RequireGpuMetadata,
    [switch]$RequirePackageSize,
    [double]$ExpectedMeasuredSeconds = -1,
    [double]$ExpectedWarmupSeconds = -1,
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @(),
    [string[]]$ExpectedScenes = @()
  )

  $Validator = Resolve-RepoPath "scripts\validate_benchmark_suite.mjs"
  if (-not (Test-Path $Validator)) {
    return [pscustomobject]@{
      Ok = $false
      Output = "scripts\validate_benchmark_suite.mjs missing"
    }
  }

  $Args = @($Validator, "--renderer", $Renderer)
  if ($ExpectedScenes.Count -gt 0) {
    $Args += @("--expectedScenes", ($ExpectedScenes -join ","))
  }
  if ($Variant) {
    $Args += @("--variant", $Variant)
  }
  if ($RequireCheckout) {
    $Args += "--requireCheckout"
  }
  if ($RequireBuildArgs) {
    $Args += "--requireBuildArgs"
  }
  if ($ExpectedChromiumRevision) {
    $Args += @("--expectedChromiumRevision", $ExpectedChromiumRevision)
  }
  if ($ExpectedBrowser) {
    $Args += @("--expectedBrowser", $ExpectedBrowser)
  }
  if ($RequireForkRevision) {
    $Args += "--requireForkRevision"
  }
  if ($ExpectedForkRevision) {
    $Args += @("--expectedForkRevision", $ExpectedForkRevision)
  }
  if ($ForbidSmoke) {
    $Args += "--forbidSmoke"
  }
  if ($RejectSoftwareRendering) {
    $Args += "--rejectSoftwareRendering"
  }
  if ($RequireGpuMetadata) {
    $Args += "--requireGpuMetadata"
  }
  if ($RequirePackageSize) {
    $Args += "--requirePackageSize"
  }
  if ($ExpectedMeasuredSeconds -ge 0) {
    $Args += @("--expectedMeasuredSeconds", [string]$ExpectedMeasuredSeconds)
  }
  if ($ExpectedWarmupSeconds -ge 0) {
    $Args += @("--expectedWarmupSeconds", [string]$ExpectedWarmupSeconds)
  }
  foreach ($Metadata in $ExpectedFlagMetadata) {
    $Args += @("--expectedFlagMetadata", $Metadata)
  }
  foreach ($Flag in $RequiredBrowserFlags) {
    $Args += @("--requiredBrowserFlag", $Flag)
  }
  $Args += $Files

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $OutputText = (& node @Args 2>&1)
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  return [pscustomobject]@{
    Ok = ($LASTEXITCODE -eq 0)
    Output = ($OutputText -join " ")
  }
}

function Add-BenchmarkSuiteRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$Pattern,
    [string]$Renderer,
    [string]$Variant,
    [string]$Remaining,
    [switch]$RequireForkRevision,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [string]$ExpectedForkRevision = "",
    [switch]$RejectSoftwareRendering,
    [switch]$RequireGpuMetadata,
    [switch]$RequirePackageSize,
    [double]$ExpectedMeasuredSeconds = -1,
    [double]$ExpectedWarmupSeconds = -1,
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @()
  )

  $Files = @(Get-ChildItem -Path (Resolve-RepoPath $Pattern) -File -ErrorAction SilentlyContinue)
  if ($Files.Count -eq 0) {
    Add-AuditRow $Area $Requirement "pending" "$Pattern count=0 expected=$($RequiredScenes.Count)" $Remaining
    return
  }

  $Result = Invoke-BenchmarkSuiteValidator `
    -Files @($Files.FullName) `
    -Renderer $Renderer `
    -Variant $Variant `
    -RequireCheckout `
    -RequireBuildArgs `
    -ExpectedChromiumRevision $ExpectedChromiumRevision `
    -ExpectedBrowser $ExpectedBrowser `
    -ForbidSmoke `
    -RequireForkRevision:$RequireForkRevision `
    -ExpectedForkRevision $ExpectedForkRevision `
    -RejectSoftwareRendering:$RejectSoftwareRendering `
    -RequireGpuMetadata:$RequireGpuMetadata `
    -RequirePackageSize:$RequirePackageSize `
    -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds `
    -ExpectedWarmupSeconds $ExpectedWarmupSeconds `
    -ExpectedFlagMetadata $ExpectedFlagMetadata `
    -RequiredBrowserFlags $RequiredBrowserFlags `
    -ExpectedScenes $RequiredScenes

  if ($Result.Ok) {
    Add-AuditRow $Area $Requirement "done" "$Pattern count=$($Files.Count); $($Result.Output)" $Remaining
  } else {
    Add-AuditRow $Area $Requirement "pending" "$Pattern count=$($Files.Count); validation failed: $($Result.Output)" $Remaining
  }
}

function Add-AnyVariantBenchmarkSuiteRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$Pattern,
    [string]$Renderer,
    [string]$Remaining,
    [switch]$RequireForkRevision,
    [string]$ExpectedChromiumRevision = "",
    [string]$ExpectedBrowser = "",
    [string]$ExpectedForkRevision = "",
    [switch]$RejectSoftwareRendering,
    [switch]$RequireGpuMetadata,
    [switch]$RequirePackageSize,
    [double]$ExpectedMeasuredSeconds = -1,
    [double]$ExpectedWarmupSeconds = -1,
    [string[]]$ExpectedFlagMetadata = @(),
    [string[]]$RequiredBrowserFlags = @()
  )

  $Files = @(Get-ChildItem -Path (Resolve-RepoPath $Pattern) -File -ErrorAction SilentlyContinue)
  if ($Files.Count -eq 0) {
    Add-AuditRow $Area $Requirement "pending" "$Pattern count=0 expected=$($RequiredScenes.Count)" $Remaining
    return
  }

  $ByVariant = @{}
  foreach ($File in $Files) {
    try {
      $Json = Get-Content $File.FullName -Raw | ConvertFrom-Json
      $Variant = if ($Json.benchmark_variant) { [string]$Json.benchmark_variant } else { "unknown" }
      if (-not $ByVariant.ContainsKey($Variant)) {
        $ByVariant[$Variant] = [System.Collections.Generic.List[string]]::new()
      }
      $ByVariant[$Variant].Add($File.FullName)
    } catch {
      continue
    }
  }

  foreach ($Variant in $ByVariant.Keys) {
    $Result = Invoke-BenchmarkSuiteValidator `
      -Files @($ByVariant[$Variant]) `
      -Renderer $Renderer `
      -Variant $Variant `
      -RequireCheckout `
      -RequireBuildArgs `
      -ExpectedChromiumRevision $ExpectedChromiumRevision `
      -ExpectedBrowser $ExpectedBrowser `
      -ForbidSmoke `
      -RequireForkRevision:$RequireForkRevision `
      -ExpectedForkRevision $ExpectedForkRevision `
      -RejectSoftwareRendering:$RejectSoftwareRendering `
      -RequireGpuMetadata:$RequireGpuMetadata `
      -RequirePackageSize:$RequirePackageSize `
      -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds `
      -ExpectedWarmupSeconds $ExpectedWarmupSeconds `
      -ExpectedFlagMetadata $ExpectedFlagMetadata `
      -RequiredBrowserFlags $RequiredBrowserFlags `
      -ExpectedScenes $RequiredScenes

    if ($Result.Ok) {
      Add-AuditRow $Area $Requirement "done" "$Pattern variant=$Variant count=$($ByVariant[$Variant].Count); $($Result.Output)" $Remaining
      return
    }
  }

  Add-AuditRow $Area $Requirement "pending" "$Pattern count=$($Files.Count); no benchmark_variant group forms a complete validated suite" $Remaining
}

function Test-JsonOk {
  param([string]$PathValue)
  if (-not (Test-RepoPath $PathValue)) {
    return $false
  }
  try {
    $null = Get-Content (Resolve-RepoPath $PathValue) -Raw | ConvertFrom-Json
    return $true
  } catch {
    return $false
  }
}

function Test-FileMetadataMatchesDisk {
  param([object]$Metadata)

  if ($null -eq $Metadata -or -not $Metadata.exists -or -not $Metadata.path -or -not $Metadata.sha256) {
    return $false
  }

  $Resolved = Resolve-RepoPath ([string]$Metadata.path)
  if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
    return $false
  }

  $ActualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Resolved).Hash.ToLowerInvariant()
  $ExpectedHash = ([string]$Metadata.sha256).ToLowerInvariant()
  if ($ActualHash -ne $ExpectedHash) {
    return $false
  }

  if ($null -ne $Metadata.size_bytes) {
    $ActualSize = (Get-Item -LiteralPath $Resolved).Length
    if ([int64]$Metadata.size_bytes -ne $ActualSize) {
      return $false
    }
  }

  return $true
}

function Test-RepoPathEquivalent {
  param(
    [string]$ActualPath,
    [string]$ExpectedPath
  )

  if (-not $ActualPath -or -not $ExpectedPath) {
    return $false
  }

  $ActualFullPath = [System.IO.Path]::GetFullPath((Resolve-RepoPath $ActualPath)).TrimEnd('\', '/')
  $ExpectedFullPath = [System.IO.Path]::GetFullPath((Resolve-RepoPath $ExpectedPath)).TrimEnd('\', '/')
  if ($IsWindows -or $env:OS -eq "Windows_NT") {
    return $ActualFullPath.Equals($ExpectedFullPath, [System.StringComparison]::OrdinalIgnoreCase)
  }
  return $ActualFullPath.Equals($ExpectedFullPath, [System.StringComparison]::Ordinal)
}

function Test-DirectoryMetadataMatchesDisk {
  param([object]$Metadata)

  if ($null -eq $Metadata -or -not $Metadata.exists -or -not $Metadata.path -or $Metadata.file_count -lt 1 -or $Metadata.size_bytes -lt 1) {
    return $false
  }

  $Resolved = Resolve-RepoPath ([string]$Metadata.path)
  if (-not (Test-Path -LiteralPath $Resolved -PathType Container)) {
    return $false
  }

  $Files = @(Get-ChildItem -LiteralPath $Resolved -File -Recurse -ErrorAction SilentlyContinue)
  $ActualSize = 0L
  foreach ($File in $Files) {
    $ActualSize += $File.Length
  }

  return ($Files.Count -eq [int]$Metadata.file_count -and $ActualSize -eq [int64]$Metadata.size_bytes)
}

function Get-InvalidFileMetadataLabels {
  param([object[]]$Items)

  $Invalid = [System.Collections.Generic.List[string]]::new()
  foreach ($Item in @($Items)) {
    $HasExpectedPath = $Item.PSObject.Properties.Name -contains "ExpectedPath"
    if ($HasExpectedPath -and $Item.ExpectedPath -and -not (Test-RepoPathEquivalent ([string]$Item.Metadata.path) ([string]$Item.ExpectedPath))) {
      $Invalid.Add([string]$Item.Label) | Out-Null
    } elseif (-not (Test-FileMetadataMatchesDisk $Item.Metadata)) {
      $Invalid.Add([string]$Item.Label) | Out-Null
    }
  }
  return @($Invalid)
}

function Get-InvalidDirectoryMetadataLabels {
  param([object[]]$Items)

  $Invalid = [System.Collections.Generic.List[string]]::new()
  foreach ($Item in @($Items)) {
    $HasExpectedPath = $Item.PSObject.Properties.Name -contains "ExpectedPath"
    if ($HasExpectedPath -and $Item.ExpectedPath -and -not (Test-RepoPathEquivalent ([string]$Item.Metadata.path) ([string]$Item.ExpectedPath))) {
      $Invalid.Add([string]$Item.Label) | Out-Null
    } elseif (-not (Test-DirectoryMetadataMatchesDisk $Item.Metadata)) {
      $Invalid.Add([string]$Item.Label) | Out-Null
    }
  }
  return @($Invalid)
}

function Test-PackageExecutableMatchesBrowserMetadata {
  param(
    [AllowNull()][object]$PackageMetadata,
    [AllowNull()][object]$BrowserMetadata
  )

  if (-not (Test-DirectoryMetadataMatchesDisk $PackageMetadata)) {
    return $false
  }
  if (-not (Test-FileMetadataMatchesDisk $BrowserMetadata)) {
    return $false
  }

  $PackagePath = Resolve-RepoPath ([string]$PackageMetadata.path)
  $PackagedBrowser = Join-Path $PackagePath "content_shell.exe"
  if (-not (Test-Path -LiteralPath $PackagedBrowser -PathType Leaf)) {
    return $false
  }

  $PackagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PackagedBrowser).Hash.ToLowerInvariant()
  $BrowserHash = ([string]$BrowserMetadata.sha256).ToLowerInvariant()
  return ($BrowserHash -and $PackagedHash -eq $BrowserHash)
}

function Get-InvalidPackageExecutableLabels {
  param([object[]]$Items)

  $Invalid = [System.Collections.Generic.List[string]]::new()
  foreach ($Item in @($Items)) {
    if (-not (Test-PackageExecutableMatchesBrowserMetadata -PackageMetadata $Item.PackageMetadata -BrowserMetadata $Item.BrowserMetadata)) {
      $Invalid.Add([string]$Item.Label) | Out-Null
    }
  }
  return @($Invalid)
}

function Test-PinRefreshForCompletedManifest {
  param(
    [string]$ManifestGeneratedAt,
    [string]$ManifestChromiumRevision
  )

  $PinRefreshPath = Resolve-RepoPath "benchmarks\reports\chromium-pin-refresh.json"
  if (-not (Test-Path -LiteralPath $PinRefreshPath -PathType Leaf)) {
    return [pscustomobject]@{
      Ok = $false
      Output = "benchmarks\reports\chromium-pin-refresh.json missing"
    }
  }

  try {
    $PinRefresh = Get-Content -LiteralPath $PinRefreshPath -Raw | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      Ok = $false
      Output = "benchmarks\reports\chromium-pin-refresh.json is invalid JSON"
    }
  }

  if ($PinRefresh.target_revision -ne $ManifestChromiumRevision) {
    return [pscustomobject]@{
      Ok = $false
      Output = "pin refresh target=$($PinRefresh.target_revision) manifest_chromium_revision=$ManifestChromiumRevision"
    }
  }
  if ($PinRefresh.selected_from_upstream_head -ne $true) {
    return [pscustomobject]@{
      Ok = $false
      Output = "pin refresh selected_from_upstream_head=$($PinRefresh.selected_from_upstream_head)"
    }
  }

  try {
    $ManifestGenerated = [datetimeoffset]::Parse($ManifestGeneratedAt)
    $PinSelected = [datetimeoffset]::Parse([string]$PinRefresh.selected_at)
  } catch {
    return [pscustomobject]@{
      Ok = $false
      Output = "manifest generated_at or pin refresh selected_at is missing or invalid"
    }
  }

  if ($ManifestGenerated -lt $PinSelected) {
    return [pscustomobject]@{
      Ok = $false
      Output = "manifest generated_at=$ManifestGeneratedAt predates pin refresh selected_at=$($PinRefresh.selected_at)"
    }
  }

  return [pscustomobject]@{
    Ok = $true
    Output = "pin refresh target=$($PinRefresh.target_revision) selected_at=$($PinRefresh.selected_at)"
  }
}

function Test-OfficialComparisonAfterPinRefresh {
  param([object]$PinRefresh)

  $PathValue = Get-OfficialComparisonManifestPathValue
  if (-not (Test-RepoPath $PathValue)) {
    return [pscustomobject]@{
      Ok = $false
      Output = "$PathValue missing"
    }
  }

  try {
    $Manifest = Get-Content (Resolve-RepoPath $PathValue) -Raw | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      Ok = $false
      Output = "$PathValue is invalid JSON"
    }
  }

  $ExpectedForkRevision = Get-ExpectedViewerForkRevision
  if ($Manifest.dry_run -ne $false) {
    return [pscustomobject]@{
      Ok = $false
      Output = "$PathValue is dry-run or missing dry_run=false"
    }
  }
  if ([string]$Manifest.phase -ne "completed") {
    return [pscustomobject]@{
      Ok = $false
      Output = "$PathValue phase=$($Manifest.phase)"
    }
  }
  if ([string]$Manifest.chromium_revision -ne $ExpectedChromiumRevision) {
    return [pscustomobject]@{
      Ok = $false
      Output = "$PathValue chromium_revision=$($Manifest.chromium_revision) expected=$ExpectedChromiumRevision"
    }
  }
  if ([string]$Manifest.fork_revision -ne $ExpectedForkRevision) {
    return [pscustomobject]@{
      Ok = $false
      Output = "$PathValue fork_revision=$($Manifest.fork_revision) expected=$ExpectedForkRevision"
    }
  }

  try {
    $ManifestGenerated = [datetimeoffset]::Parse([string]$Manifest.generated_at)
    $PinSelected = [datetimeoffset]::Parse([string]$PinRefresh.selected_at)
  } catch {
    return [pscustomobject]@{
      Ok = $false
      Output = "$PathValue generated_at or pin refresh selected_at is missing or invalid"
    }
  }

  if ($ManifestGenerated -lt $PinSelected) {
    return [pscustomobject]@{
      Ok = $false
      Output = "$PathValue generated_at=$($Manifest.generated_at) predates pin refresh selected_at=$($PinRefresh.selected_at)"
    }
  }

  return [pscustomobject]@{
    Ok = $true
    Output = "$PathValue completed for refreshed pin at generated_at=$($Manifest.generated_at)"
  }
}

function Add-MetricJsonRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$PathValue,
    [string]$Remaining
  )
  if (Test-MetricJsonOk $PathValue) {
    Add-AuditRow $Area $Requirement "done" "$PathValue passes metric validation" $Remaining
  } else {
    Add-AuditRow $Area $Requirement "pending" "$PathValue missing, invalid, or fails metric validation" $Remaining
  }
}

function Test-SmokeJsonOk {
  param(
    [string]$PathValue,
    [string]$Type,
    [string]$ExpectedBrowser = "",
    [switch]$ExpectBrowserMode,
    [switch]$ExpectViewerMode,
    [switch]$ExpectViewerTrustedContent,
    [switch]$RequireWebGPU,
    [string[]]$RequiredBrowserFlags = @()
  )
  if (-not (Test-RepoPath $PathValue)) {
    return $false
  }
  return (Invoke-SmokeValidator -Type $Type -Files @($PathValue) -ExpectedBrowser $ExpectedBrowser -ExpectBrowserMode:$ExpectBrowserMode -ExpectViewerMode:$ExpectViewerMode -ExpectViewerTrustedContent:$ExpectViewerTrustedContent -RequireWebGPU:$RequireWebGPU -RequiredBrowserFlags $RequiredBrowserFlags).Ok
}

function Invoke-SmokeValidator {
  param(
    [string]$Type,
    [string[]]$Files,
    [string]$ExpectedBrowser = "",
    [switch]$ExpectBrowserMode,
    [switch]$ExpectViewerMode,
    [switch]$ExpectViewerTrustedContent,
    [switch]$RequireWebGPU,
    [string[]]$RequiredBrowserFlags = @()
  )

  $Validator = Resolve-RepoPath "scripts\validate_smoke_result.mjs"
  if (-not (Test-Path $Validator)) {
    return [pscustomobject]@{
      Ok = $false
      Output = "scripts\validate_smoke_result.mjs missing"
    }
  }

  $ResolvedFiles = @($Files | ForEach-Object { Resolve-RepoPath $_ })
  $Command = @($Validator, "--type", $Type)
  if ($ExpectBrowserMode) {
    $Command += "--expect-browser-mode"
  }
  if ($ExpectViewerMode) {
    $Command += "--expect-viewer-mode"
  }
  if ($ExpectViewerTrustedContent) {
    $Command += "--expect-viewer-trusted-content"
  }
  if ($ExpectedBrowser) {
    $Command += @("--expected-browser", $ExpectedBrowser)
  }
  if ($RequireWebGPU) {
    $Command += "--require-webgpu"
  }
  foreach ($Flag in $RequiredBrowserFlags) {
    $Command += @("--required-browser-flag", $Flag)
  }
  $Command += $ResolvedFiles
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $OutputText = (& node @Command 2>&1)
    return [pscustomobject]@{
      Ok = ($LASTEXITCODE -eq 0)
      Output = ($OutputText | ForEach-Object { [string]$_ }) -join " "
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Add-SmokeJsonRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$PathValue,
    [string]$Type,
    [string]$Remaining,
    [string]$ExpectedBrowser = "",
    [switch]$ExpectBrowserMode,
    [switch]$ExpectViewerMode,
    [switch]$ExpectViewerTrustedContent,
    [switch]$RequireWebGPU,
    [string[]]$RequiredBrowserFlags = @()
  )
  if (Test-SmokeJsonOk -PathValue $PathValue -Type $Type -ExpectedBrowser $ExpectedBrowser -ExpectBrowserMode:$ExpectBrowserMode -ExpectViewerMode:$ExpectViewerMode -ExpectViewerTrustedContent:$ExpectViewerTrustedContent -RequireWebGPU:$RequireWebGPU -RequiredBrowserFlags $RequiredBrowserFlags) {
    $RequirementSuffix = if ($RequireWebGPU) { " with required WebGPU smoke" } else { "" }
    Add-AuditRow $Area $Requirement "done" "$PathValue passes $Type smoke validation$RequirementSuffix" $Remaining
  } else {
    $RequirementSuffix = if ($RequireWebGPU) { " with required WebGPU smoke" } else { "" }
    Add-AuditRow $Area $Requirement "pending" "$PathValue missing, invalid, or fails $Type smoke validation$RequirementSuffix" $Remaining
  }
}

function Add-JsonRow {
  param(
    [string]$Area,
    [string]$Requirement,
    [string]$PathValue,
    [string]$Remaining
  )
  if (Test-JsonOk $PathValue) {
    Add-AuditRow $Area $Requirement "done" "$PathValue parses as JSON" $Remaining
  } else {
    Add-AuditRow $Area $Requirement "pending" "$PathValue missing or invalid" $Remaining
  }
}

function Get-TrustedMatrixExperiment {
  param(
    [object]$Manifest,
    [string]$Label
  )
  $Matches = @($Manifest.experiments | Where-Object { $_.label -eq $Label })
  if ($Matches.Count -ne 1) {
    return $null
  }
  return $Matches[0]
}

function Test-TrustedMatrixFlags {
  param(
    [object]$Manifest,
    [string]$Label,
    [string[]]$ExpectedFlags
  )
  $Experiment = Get-TrustedMatrixExperiment $Manifest $Label
  if (-not $Experiment) {
    return $false
  }
  $Actual = @($Experiment.flags)
  if ($Actual.Count -ne $ExpectedFlags.Count) {
    return $false
  }
  for ($Index = 0; $Index -lt $ExpectedFlags.Count; $Index += 1) {
    if ($Actual[$Index] -ne $ExpectedFlags[$Index]) {
      return $false
    }
  }
  return $true
}

function Get-MissingTrustedMatrixFlagEvidence {
  param([object]$Manifest)

  $Missing = [System.Collections.Generic.List[string]]::new()
  $Expected = @(
    [pscustomobject]@{ Label = "fork-viewer-exp-default"; Flags = @() },
    [pscustomobject]@{ Label = "fork-viewer-exp-aggressive-gpu"; Flags = @("--viewerAggressiveGpu") },
    [pscustomobject]@{ Label = "fork-viewer-exp-in-process-gpu"; Flags = @("--viewerInProcessGpu") },
    [pscustomobject]@{ Label = "fork-viewer-exp-single-process"; Flags = @("--viewerSingleProcess") },
    [pscustomobject]@{ Label = "fork-viewer-exp-relaxed-webgl-validation-gate"; Flags = @("--viewerRelaxedWebglValidation") },
    [pscustomobject]@{ Label = "fork-viewer-exp-disable-unneeded-blink-features-gate"; Flags = @("--viewerDisableUnneededBlinkFeatures") },
    [pscustomobject]@{ Label = "fork-viewer-exp-direct-gpu-presentation-gate"; Flags = @("--viewerDirectGpuPresentation") }
  )

  foreach ($Item in $Expected) {
    if (-not (Test-TrustedMatrixFlags $Manifest $Item.Label $Item.Flags)) {
      $Missing.Add($Item.Label) | Out-Null
    }
  }

  $AngleExperiments = @($Manifest.experiments | Where-Object { $_.label -like "fork-viewer-exp-angle-*" })
  $HasAngleExperiment = $false
  foreach ($Experiment in $AngleExperiments) {
    $Flags = @($Experiment.flags)
    $ExpectedMetadata = @($Experiment.expected_flag_metadata)
    if ($Flags.Count -eq 2 -and
        $Flags[0] -eq "--viewerForceAngleBackend" -and
        $Flags[1] -and
        $ExpectedMetadata -contains "viewer_force_angle_backend=$($Flags[1])" -and
        $ExpectedMetadata -contains "requested_angle_backend=$($Flags[1])") {
      $HasAngleExperiment = $true
      break
    }
  }
  if (-not $HasAngleExperiment) {
    $Missing.Add("fork-viewer-exp-angle-*") | Out-Null
  }

  return @($Missing)
}

function Add-TrustedMatrixManifestRow {
  $PathValue = Get-TrustedMatrixManifestPathValue
  if (-not (Test-RepoPath $PathValue)) {
    Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue missing" "Run scripts/run_trusted_experiment_matrix.ps1 after fork build to measure individual trusted flags."
    return
  }

  try {
    $Manifest = Get-Content (Resolve-RepoPath $PathValue) -Raw | ConvertFrom-Json
    $ExpectedForkRevision = Get-ExpectedViewerForkRevision
    $ExperimentCount = @($Manifest.experiments).Count
    $ResultCount = @($Manifest.result_files.all).Count
    $ExpectedResultCount = $ExperimentCount * $RequiredScenes.Count
    $ResultMetadata = @($Manifest.artifact_metadata.results.all)
    $HashedResultCount = @($ResultMetadata | Where-Object { $_.exists -and $_.sha256 }).Count
    $MissingFlagEvidence = @(Get-MissingTrustedMatrixFlagEvidence $Manifest)
    $PinRefreshValidation = Test-PinRefreshForCompletedManifest `
      -ManifestGeneratedAt ([string]$Manifest.generated_at) `
      -ManifestChromiumRevision ([string]$Manifest.chromium_revision)
    $TrustedFileMetadataChecks = @(
      [pscustomobject]@{ Label = "browser"; Metadata = $Manifest.artifact_metadata.inputs.browser; ExpectedPath = $Manifest.browser },
      [pscustomobject]@{ Label = "build_args"; Metadata = $Manifest.artifact_metadata.inputs.build_args; ExpectedPath = $Manifest.build_args },
      [pscustomobject]@{ Label = "viewer_patch"; Metadata = $Manifest.artifact_metadata.inputs.viewer_patch; ExpectedPath = "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch" },
      [pscustomobject]@{ Label = "report:summary"; Metadata = $Manifest.artifact_metadata.reports.summary; ExpectedPath = $Manifest.report_files.summary },
      [pscustomobject]@{ Label = "report:comparison"; Metadata = $Manifest.artifact_metadata.reports.comparison; ExpectedPath = $Manifest.report_files.comparison }
    )
    $TrustedResultFiles = @($Manifest.result_files.all)
    for ($Index = 0; $Index -lt $ResultMetadata.Count; $Index += 1) {
      $ExpectedResultPath = if ($Index -lt $TrustedResultFiles.Count) { $TrustedResultFiles[$Index] } else { "" }
      $TrustedFileMetadataChecks += [pscustomobject]@{ Label = "result:$Index"; Metadata = $ResultMetadata[$Index]; ExpectedPath = $ExpectedResultPath }
    }
    $TrustedDirectoryMetadataChecks = @()
    if ($Manifest.package_dir) {
      $TrustedDirectoryMetadataChecks += [pscustomobject]@{ Label = "package"; Metadata = $Manifest.artifact_metadata.inputs.package; ExpectedPath = $Manifest.package_dir }
    }
    $TrustedInvalidFiles = @(Get-InvalidFileMetadataLabels $TrustedFileMetadataChecks)
    $TrustedInvalidDirectories = @(Get-InvalidDirectoryMetadataLabels $TrustedDirectoryMetadataChecks)
    $TrustedInvalidPackageExecutables = @()
    if ($Manifest.package_dir) {
      $TrustedInvalidPackageExecutables = @(Get-InvalidPackageExecutableLabels @(
        [pscustomobject]@{
          Label = "package"
          PackageMetadata = $Manifest.artifact_metadata.inputs.package
          BrowserMetadata = $Manifest.artifact_metadata.inputs.browser
        }
      ))
    }
    $TrustedSuiteValidation = [pscustomobject]@{
      Ok = $true
      Output = ""
    }
    if ($TrustedInvalidFiles.Count -eq 0 -and $TrustedInvalidDirectories.Count -eq 0 -and $TrustedInvalidPackageExecutables.Count -eq 0) {
      $TrustedSuiteValidation = Invoke-TrustedMatrixBenchmarkSuiteValidation `
        -Manifest $Manifest `
        -ExpectedForkRevision $ExpectedForkRevision `
        -RequirePackageSize:([bool]$Manifest.package_dir)
    }
    $TrustedReportContentIssues = @()
    if ($TrustedInvalidFiles.Count -eq 0) {
      $TrustedReportContentIssues = @(Get-TrustedMatrixReportContentIssues -Manifest $Manifest)
    }
    $TrustedSuiteSettingIssues = @(Get-TrustedMatrixManifestSuiteValidationIssues `
        -Manifest $Manifest `
        -ExpectedForkRevision $ExpectedForkRevision)
    if ($Manifest.dry_run) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue is a dry-run manifest" "Run without -DryRun after fork build."
    } elseif ($Manifest.phase -ne "completed") {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue phase=$($Manifest.phase)" "Regenerate after the trusted experiment matrix completes successfully."
    } elseif ($Manifest.chromium_revision -ne $ExpectedChromiumRevision) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue chromium_revision=$($Manifest.chromium_revision) expected=$ExpectedChromiumRevision" "Regenerate trusted matrix results from the pinned Chromium checkout."
    } elseif (-not $PinRefreshValidation.Ok) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue does not follow the current Chromium pin refresh: $($PinRefreshValidation.Output)" "Regenerate via scripts/run_post_atl_pipeline.ps1 -RefreshChromiumPin so trusted evidence follows the current upstream-head pin refresh."
    } elseif ($Manifest.fork_revision -ne $ExpectedForkRevision) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue fork_revision=$($Manifest.fork_revision) expected=$ExpectedForkRevision" "Regenerate trusted matrix results from the current viewer patch."
    } elseif ($Manifest.suite_validation.expected_measured_seconds -ne $Manifest.options.duration -or $Manifest.suite_validation.expected_warmup_seconds -ne $Manifest.options.warmup) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue does not record suite duration/warmup validation matching options" "Regenerate with current run_trusted_experiment_matrix.ps1 so trusted results enforce measured_seconds and warmup_seconds."
    } elseif ($TrustedSuiteSettingIssues.Count -gt 0) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue suite validation settings mismatch: $($TrustedSuiteSettingIssues -join '; ')" "Regenerate with current run_trusted_experiment_matrix.ps1 so the matrix manifest records checkout, build-args, revision, GPU, exact-scene, no-smoke, and flag-metadata gates."
    } elseif ($ExperimentCount -lt 1) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue records no experiments" "Run at least one trusted experiment variant."
    } elseif ($MissingFlagEvidence.Count -gt 0) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue missing trusted experiment flag evidence: $($MissingFlagEvidence -join ', ')" "Regenerate with the full trusted experiment matrix including default, aggressive GPU, in-process GPU, single-process, ANGLE backend, relaxed WebGL validation, and reserved no-op gate experiments."
    } elseif ($ResultCount -ne $ExpectedResultCount) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue result file count=$ResultCount expected=$ExpectedResultCount for $ExperimentCount experiments and $($RequiredScenes.Count) scenes" "Regenerate with the complete required scene suite."
    } elseif (-not $Manifest.artifact_metadata.inputs.browser.exists) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue does not record the fork browser binary as existing" "Regenerate after the fork binary exists."
    } elseif (-not $Manifest.artifact_metadata.inputs.build_args.sha256) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue does not record a build-args hash" "Regenerate with -BuildArgs after the fork args.gn exists."
    } elseif ($Manifest.package_dir -and (-not $Manifest.artifact_metadata.inputs.package.exists -or $Manifest.artifact_metadata.inputs.package.file_count -lt 1 -or $Manifest.artifact_metadata.inputs.package.size_bytes -lt 1)) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue package_dir is set but package metadata is missing or empty" "Regenerate after staging the fork package with scripts/stage_viewer_package.ps1."
    } elseif ($HashedResultCount -ne $ExpectedResultCount) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue hashed result count=$HashedResultCount expected=$ExpectedResultCount" "Regenerate after all trusted experiment result JSON files are written."
    } elseif (-not $Manifest.artifact_metadata.reports.summary.exists -or -not $Manifest.artifact_metadata.reports.summary.sha256 -or -not $Manifest.artifact_metadata.reports.comparison.exists -or -not $Manifest.artifact_metadata.reports.comparison.sha256) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue does not record both trusted matrix report hashes" "Regenerate after summary and comparison reports are written."
    } elseif (-not $Manifest.package_dir) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue missing required package_dir" "Regenerate with -PackageDir pointing at the staged fork package."
    } elseif ($TrustedInvalidFiles.Count -gt 0) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue has artifact metadata whose path/hash does not match files on disk: $($TrustedInvalidFiles -join ', ')" "Regenerate the trusted matrix from actual fork binaries, args, result JSON, and report files."
    } elseif ($TrustedInvalidDirectories.Count -gt 0) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue has package metadata whose path/count/size does not match disk: $($TrustedInvalidDirectories -join ', ')" "Regenerate after staging the fork package with scripts/stage_viewer_package.ps1."
    } elseif ($TrustedInvalidPackageExecutables.Count -gt 0) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue has package executable hash that does not match the manifest browser: $($TrustedInvalidPackageExecutables -join ', ')" "Regenerate after staging the fork package from the same fork binary used for the trusted experiment matrix."
    } elseif ($TrustedReportContentIssues.Count -gt 0) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue report content validation failed: $($TrustedReportContentIssues -join '; ')" "Regenerate trusted summary and comparison reports with summarize_results.mjs and compare_results.mjs from the exact trusted matrix result files."
    } elseif (-not $TrustedSuiteValidation.Ok) {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue suite validation failed: $($TrustedSuiteValidation.Output)" "Regenerate after every exact trusted experiment result JSON file in the manifest passes validate_benchmark_suite.mjs with checkout, build-args, revision, GPU, package-size, duration/warmup, and viewer flag metadata checks."
    } else {
      Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "done" "$PathValue records $ExperimentCount trusted experiment suite(s), expected risky flag mappings, $HashedResultCount hashed result files, report hashes with content validation, build-args hash, viewer patch hash, required package metadata with executable hash matched to browser, artifact paths/hashes verified on disk, benchmark suites semantically validated against exact manifest files, expected fork revision, pin-refresh provenance, and full suite-validation settings" "Feed measured effects into docs/optimization_log.md."
    }
  } catch {
    Add-AuditRow "Official performance" "Trusted experiment matrix manifest" "pending" "$PathValue is invalid JSON or could not be audited: $($_.Exception.Message)" "Regenerate after fork build."
  }
}

function Get-ObjectPropertyValue {
  param(
    [AllowNull()][object]$Object,
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

function Format-SuiteValidationValue {
  param([AllowNull()][object]$Value)

  if ($null -eq $Value) {
    return "<null>"
  }

  $Values = @($Value)
  if ($Value -is [System.Array] -or $Values.Count -gt 1) {
    $Formatted = @($Values | ForEach-Object { Format-SuiteValidationValue $_ })
    return "[$($Formatted -join ', ')]"
  }

  if ($Value -is [bool]) {
    return $Value.ToString().ToLowerInvariant()
  }

  return [string]$Value
}

function Test-SuiteValidationValueEqual {
  param(
    [AllowNull()][object]$Actual,
    [AllowNull()][object]$Expected
  )

  $ActualValues = @($Actual)
  $ExpectedValues = @($Expected)
  if ($Actual -is [System.Array] -or $Expected -is [System.Array] -or $ActualValues.Count -gt 1 -or $ExpectedValues.Count -gt 1) {
    if ($ActualValues.Count -ne $ExpectedValues.Count) {
      return $false
    }
    for ($Index = 0; $Index -lt $ExpectedValues.Count; $Index += 1) {
      if (-not (Test-SuiteValidationValueEqual $ActualValues[$Index] $ExpectedValues[$Index])) {
        return $false
      }
    }
    return $true
  }

  if ($null -eq $Actual -or $null -eq $Expected) {
    return ($null -eq $Actual -and $null -eq $Expected)
  }

  return ([string]$Actual -eq [string]$Expected)
}

function Get-SuiteValidationSettingIssues {
  param(
    [AllowNull()][object]$SuiteValidation,
    [object[]]$ExpectedSettings
  )

  $Issues = [System.Collections.Generic.List[string]]::new()
  foreach ($Setting in $ExpectedSettings) {
    $Name = [string]$Setting.Name
    $Expected = $Setting.Expected
    $Actual = Get-ObjectPropertyValue $SuiteValidation $Name
    if (-not (Test-SuiteValidationValueEqual $Actual $Expected)) {
      $Issues.Add("$Name=$(Format-SuiteValidationValue $Actual) expected=$(Format-SuiteValidationValue $Expected)") | Out-Null
    }
  }
  return @($Issues)
}

function Add-SuiteValidationFlagMetadataIssue {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [AllowNull()][object]$ExpectedFlagMetadata,
    [string]$Name
  )

  $Values = @(Get-ObjectPropertyValue $ExpectedFlagMetadata $Name | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_)
    })
  if ($Values.Count -eq 0) {
    $Issues.Add("expected_flag_metadata.$Name missing or empty") | Out-Null
  }
}

function Get-ReportContent {
  param([string]$PathValue)

  if (-not $PathValue) {
    return ""
  }
  $Resolved = Resolve-RepoPath $PathValue
  if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
    return ""
  }
  return Get-Content -LiteralPath $Resolved -Raw
}

function Add-ReportContentIssueIfMissing {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$Content,
    [string]$Needle,
    [string]$Label
  )

  if (-not $Content.Contains($Needle)) {
    $Issues.Add($Label) | Out-Null
  }
}

function Get-ManifestReportSceneNames {
  param([object]$Manifest)

  $Scenes = @($Manifest.scenes | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_)
    } | ForEach-Object { [string]$_ })
  if ($Scenes.Count -gt 0) {
    return @($Scenes)
  }
  return @($RequiredScenes)
}

function Add-ReportContentSceneIssues {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$Content,
    [string[]]$Scenes,
    [string]$ReportLabel
  )

  foreach ($Scene in @($Scenes)) {
    Add-ReportContentIssueIfMissing $Issues $Content $Scene "$ReportLabel missing scene $Scene"
  }
}

function Add-ComparisonReportMetricColumnIssues {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$Content,
    [string]$ReportLabel
  )

  foreach ($Column in @("Dropped Delta", "JS heap Delta", "GPU memory Delta")) {
    Add-ReportContentIssueIfMissing $Issues $Content $Column "$ReportLabel missing comparison metric column $Column"
  }
}

function Get-OfficialComparisonReportContentIssues {
  param([object]$Manifest)

  $Issues = [System.Collections.Generic.List[string]]::new()
  $Scenes = @(Get-ManifestReportSceneNames -Manifest $Manifest)
  $BaselineLabel = Get-OfficialManifestLabel -Manifest $Manifest -Name "baseline" -Fallback "baseline-content-shell"
  $ForkDefaultLabel = Get-OfficialManifestLabel -Manifest $Manifest -Name "fork_default" -Fallback "fork-viewer-default"
  $AggressiveLabelFallback = if ([string]$Manifest.options.aggressive_angle_backend) {
    "fork-viewer-aggressive-gpu-$($Manifest.options.aggressive_angle_backend)"
  } else {
    "fork-viewer-aggressive-gpu"
  }
  $AggressiveLabel = Get-OfficialManifestLabel -Manifest $Manifest -Name "aggressive" -Fallback $AggressiveLabelFallback

  $WebGlReport = Get-ReportContent ([string]$Manifest.report_files.official_webgl2_comparison)
  Add-ReportContentIssueIfMissing $Issues $WebGlReport "# Benchmark Comparison" "official_webgl2_comparison missing comparison heading"
  Add-ReportContentIssueIfMissing $Issues $WebGlReport "Strict official input validation was enabled" "official_webgl2_comparison missing strict official validation note"
  Add-ReportContentIssueIfMissing $Issues $WebGlReport "| Scene | Renderer | Variant | Avg FPS" "official_webgl2_comparison missing comparison table header"
  Add-ComparisonReportMetricColumnIssues $Issues $WebGlReport "official_webgl2_comparison"
  Add-ReportContentIssueIfMissing $Issues $WebGlReport "webgl2" "official_webgl2_comparison missing webgl2 renderer rows"
  Add-ReportContentIssueIfMissing $Issues $WebGlReport $BaselineLabel "official_webgl2_comparison missing baseline label"
  Add-ReportContentIssueIfMissing $Issues $WebGlReport $ForkDefaultLabel "official_webgl2_comparison missing fork default label"
  Add-ReportContentSceneIssues $Issues $WebGlReport $Scenes "official_webgl2_comparison"
  if ($Manifest.options.include_aggressive_gpu) {
    Add-ReportContentIssueIfMissing $Issues $WebGlReport $AggressiveLabel "official_webgl2_comparison missing aggressive label"
  }

  if ($Manifest.options.include_webgpu) {
    $WebGpuReport = Get-ReportContent ([string]$Manifest.report_files.official_webgpu_comparison)
    Add-ReportContentIssueIfMissing $Issues $WebGpuReport "# Benchmark Comparison" "official_webgpu_comparison missing comparison heading"
    Add-ReportContentIssueIfMissing $Issues $WebGpuReport "Strict official input validation was enabled" "official_webgpu_comparison missing strict official validation note"
    Add-ReportContentIssueIfMissing $Issues $WebGpuReport "| Scene | Renderer | Variant | Avg FPS" "official_webgpu_comparison missing comparison table header"
    Add-ComparisonReportMetricColumnIssues $Issues $WebGpuReport "official_webgpu_comparison"
    Add-ReportContentIssueIfMissing $Issues $WebGpuReport "webgpu" "official_webgpu_comparison missing webgpu renderer rows"
    Add-ReportContentIssueIfMissing $Issues $WebGpuReport "$BaselineLabel-webgpu" "official_webgpu_comparison missing WebGPU baseline label"
    Add-ReportContentIssueIfMissing $Issues $WebGpuReport "$ForkDefaultLabel-webgpu" "official_webgpu_comparison missing WebGPU fork default label"
    Add-ReportContentSceneIssues $Issues $WebGpuReport $Scenes "official_webgpu_comparison"
    if ($Manifest.options.include_aggressive_gpu) {
      Add-ReportContentIssueIfMissing $Issues $WebGpuReport "$AggressiveLabel-webgpu" "official_webgpu_comparison missing WebGPU aggressive label"
    }
  }

  return @($Issues)
}

function Add-TraceSummaryReportContentIssues {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$PathValue,
    [string]$TracePath,
    [string]$ReportLabel
  )

  $Content = Get-ReportContent $PathValue
  Add-ReportContentIssueIfMissing $Issues $Content "# Trace Summary" "$ReportLabel missing trace summary heading"
  Add-ReportContentIssueIfMissing $Issues $Content "Trace:" "$ReportLabel missing trace path line"
  if ($TracePath) {
    Add-ReportContentIssueIfMissing $Issues $Content $TracePath "$ReportLabel missing manifest trace path"
  }
  Add-ReportContentIssueIfMissing $Issues $Content "Total events:" "$ReportLabel missing total events line"
  Add-ReportContentIssueIfMissing $Issues $Content "## Classified Events" "$ReportLabel missing classified events heading"
  Add-ReportContentIssueIfMissing $Issues $Content "| Class | Count | Total Duration ms |" "$ReportLabel missing classified events table"
  Add-ReportContentIssueIfMissing $Issues $Content "## Top Duration Events" "$ReportLabel missing top duration events heading"
  Add-ReportContentIssueIfMissing $Issues $Content "| Event | Count | Total ms | Max ms |" "$ReportLabel missing top duration events table"
  Add-ReportContentIssueIfMissing $Issues $Content "Classification is name-based" "$ReportLabel missing trace summary caveat"
}

function Get-OfficialTraceSummaryReportContentIssues {
  param([object]$Manifest)

  $Issues = [System.Collections.Generic.List[string]]::new()
  Add-TraceSummaryReportContentIssues `
    -Issues $Issues `
    -PathValue ([string]$Manifest.report_files.baseline_trace_summary) `
    -TracePath ([string]$Manifest.trace_files.baseline) `
    -ReportLabel "baseline_trace_summary"
  Add-TraceSummaryReportContentIssues `
    -Issues $Issues `
    -PathValue ([string]$Manifest.report_files.fork_trace_summary) `
    -TracePath ([string]$Manifest.trace_files.fork) `
    -ReportLabel "fork_trace_summary"
  return @($Issues)
}

function Get-TrustedMatrixReportContentIssues {
  param([object]$Manifest)

  $Issues = [System.Collections.Generic.List[string]]::new()
  $Renderer = if ([string]$Manifest.renderer) { [string]$Manifest.renderer } else { "webgl2" }
  $Scenes = @(Get-ManifestReportSceneNames -Manifest $Manifest)
  $Summary = Get-ReportContent ([string]$Manifest.report_files.summary)
  Add-ReportContentIssueIfMissing $Issues $Summary "# Benchmark Summary" "trusted summary missing summary heading"
  Add-ReportContentIssueIfMissing $Issues $Summary "| Scene | Renderer | Variant | Avg FPS" "trusted summary missing summary table header"
  Add-ReportContentIssueIfMissing $Issues $Summary $Renderer "trusted summary missing renderer rows"
  Add-ReportContentSceneIssues $Issues $Summary $Scenes "trusted summary"
  foreach ($Experiment in @($Manifest.experiments)) {
    $Label = [string]$Experiment.label
    if ($Label) {
      Add-ReportContentIssueIfMissing $Issues $Summary $Label "trusted summary missing experiment label $Label"
    }
  }

  $Comparison = Get-ReportContent ([string]$Manifest.report_files.comparison)
  Add-ReportContentIssueIfMissing $Issues $Comparison "# Benchmark Comparison" "trusted comparison missing comparison heading"
  Add-ReportContentIssueIfMissing $Issues $Comparison "| Scene | Renderer | Variant | Avg FPS" "trusted comparison missing comparison table header"
  Add-ComparisonReportMetricColumnIssues $Issues $Comparison "trusted comparison"
  Add-ReportContentIssueIfMissing $Issues $Comparison $Renderer "trusted comparison missing renderer rows"
  Add-ReportContentSceneIssues $Issues $Comparison $Scenes "trusted comparison"
  foreach ($Experiment in @($Manifest.experiments)) {
    $Label = [string]$Experiment.label
    if ($Label) {
      Add-ReportContentIssueIfMissing $Issues $Comparison $Label "trusted comparison missing experiment label $Label"
    }
  }

  return @($Issues)
}

function Get-OfficialComparisonReportFileContentIssues {
  param(
    [string]$PathValue,
    [string]$Renderer,
    [string[]]$Labels,
    [string]$ReportLabel
  )

  $Issues = [System.Collections.Generic.List[string]]::new()
  $Content = Get-ReportContent $PathValue
  Add-ReportContentIssueIfMissing $Issues $Content "# Benchmark Comparison" "$ReportLabel missing comparison heading"
  Add-ReportContentIssueIfMissing $Issues $Content "Strict official input validation was enabled" "$ReportLabel missing strict official validation note"
  Add-ReportContentIssueIfMissing $Issues $Content "| Scene | Renderer | Variant | Avg FPS" "$ReportLabel missing comparison table header"
  Add-ComparisonReportMetricColumnIssues $Issues $Content $ReportLabel
  Add-ReportContentIssueIfMissing $Issues $Content $Renderer "$ReportLabel missing $Renderer renderer rows"
  Add-ReportContentSceneIssues $Issues $Content $RequiredScenes $ReportLabel
  foreach ($Label in @($Labels)) {
    Add-ReportContentIssueIfMissing $Issues $Content $Label "$ReportLabel missing variant label $Label"
  }
  return @($Issues)
}

function Add-OfficialComparisonReportFilesRow {
  $WebGlPath = Get-OfficialWebGl2ReportPathValue
  $WebGpuPath = Get-OfficialWebGpuReportPathValue
  $Paths = @($WebGlPath, $WebGpuPath)
  $Missing = @($Paths | Where-Object { -not (Test-RepoPath $_) })
  if ($Missing.Count -gt 0) {
    Add-AuditRow "Official performance" "Human-readable official comparison reports" "missing" ("Missing: " + ($Missing -join ", ")) "Generate after official stock/fork suites."
    return
  }

  $Issues = @(
    Get-OfficialComparisonReportFileContentIssues `
      -PathValue $WebGlPath `
      -Renderer "webgl2" `
      -Labels @("baseline-content-shell", "fork-viewer-default") `
      -ReportLabel "official-webgl2-comparison"
    Get-OfficialComparisonReportFileContentIssues `
      -PathValue $WebGpuPath `
      -Renderer "webgpu" `
      -Labels @("baseline-content-shell-webgpu", "fork-viewer-default-webgpu") `
      -ReportLabel "official-webgpu-comparison"
  )
  if ($Issues.Count -gt 0) {
    Add-AuditRow "Official performance" "Human-readable official comparison reports" "pending" "Report content validation failed: $($Issues -join '; ')" "Regenerate official comparison reports with compare_results.mjs --strictOfficial after complete stock/fork suites."
    return
  }

  $ReportEvidence = @($Paths | ForEach-Object {
      $Resolved = Resolve-RepoPath $_
      $Item = Get-Item -LiteralPath $Resolved
      "$_ size_bytes=$($Item.Length) sha256=$(Get-FileHashString $_)"
    })
  Add-AuditRow "Official performance" "Human-readable official comparison reports" "done" "$($ReportEvidence -join ', ') include comparison headings, strict validation notes, table headers, renderer rows, required scenes, and stock/fork labels" "Keep with official stock/fork result JSON and manifest."
}

function Get-OfficialManifestSuiteValidationIssues {
  param(
    [object]$Manifest,
    [string]$ExpectedForkRevision
  )

  $Issues = [System.Collections.Generic.List[string]]::new()
  $ExpectedSettings = @(
    [pscustomobject]@{ Name = "require_checkout"; Expected = $true },
    [pscustomobject]@{ Name = "require_build_args"; Expected = $true },
    [pscustomobject]@{ Name = "forbid_smoke"; Expected = $true },
    [pscustomobject]@{ Name = "reject_software_rendering"; Expected = $true },
    [pscustomobject]@{ Name = "require_gpu_metadata"; Expected = $true },
    [pscustomobject]@{ Name = "expected_chromium_revision"; Expected = $ExpectedChromiumRevision },
    [pscustomobject]@{ Name = "expected_baseline_browser"; Expected = [string]$Manifest.browsers.baseline },
    [pscustomobject]@{ Name = "expected_fork_browser"; Expected = [string]$Manifest.browsers.fork },
    [pscustomobject]@{ Name = "require_fork_revision_for_fork_suites"; Expected = $true },
    [pscustomobject]@{ Name = "expected_fork_revision"; Expected = $ExpectedForkRevision },
    [pscustomobject]@{ Name = "exact_scene_output_files"; Expected = $true }
  )
  if ($Manifest.options.include_webgpu) {
    $ExpectedSettings += [pscustomobject]@{ Name = "require_webgpu_runtime_smoke"; Expected = $true }
  }
  foreach ($Issue in @(Get-SuiteValidationSettingIssues $Manifest.suite_validation $ExpectedSettings)) {
    $Issues.Add($Issue) | Out-Null
  }

  $ExpectedFlagMetadata = Get-ObjectPropertyValue $Manifest.suite_validation "expected_flag_metadata"
  if ($null -eq $ExpectedFlagMetadata) {
    $Issues.Add("expected_flag_metadata missing") | Out-Null
  } else {
    Add-SuiteValidationFlagMetadataIssue $Issues $ExpectedFlagMetadata "baseline"
    Add-SuiteValidationFlagMetadataIssue $Issues $ExpectedFlagMetadata "fork_default"
    if ($Manifest.options.include_aggressive_gpu) {
      Add-SuiteValidationFlagMetadataIssue $Issues $ExpectedFlagMetadata "aggressive"
    }
    if ($Manifest.options.include_webgpu) {
      Add-SuiteValidationFlagMetadataIssue $Issues $ExpectedFlagMetadata "baseline_webgpu"
      Add-SuiteValidationFlagMetadataIssue $Issues $ExpectedFlagMetadata "fork_default_webgpu"
      if ($Manifest.options.include_aggressive_gpu) {
        Add-SuiteValidationFlagMetadataIssue $Issues $ExpectedFlagMetadata "aggressive_webgpu"
      }
    }
  }

  return @($Issues)
}

function Get-TrustedMatrixManifestSuiteValidationIssues {
  param(
    [object]$Manifest,
    [string]$ExpectedForkRevision
  )

  $ExpectedSettings = @(
    [pscustomobject]@{ Name = "expected_scenes"; Expected = $RequiredScenes },
    [pscustomobject]@{ Name = "require_checkout"; Expected = $true },
    [pscustomobject]@{ Name = "require_build_args"; Expected = $true },
    [pscustomobject]@{ Name = "require_fork_revision"; Expected = $true },
    [pscustomobject]@{ Name = "expected_fork_revision"; Expected = $ExpectedForkRevision },
    [pscustomobject]@{ Name = "forbid_smoke"; Expected = $true },
    [pscustomobject]@{ Name = "reject_software_rendering"; Expected = $true },
    [pscustomobject]@{ Name = "require_gpu_metadata"; Expected = $true },
    [pscustomobject]@{ Name = "expected_chromium_revision"; Expected = $ExpectedChromiumRevision },
    [pscustomobject]@{ Name = "expected_browser"; Expected = [string]$Manifest.browser },
    [pscustomobject]@{ Name = "exact_scene_output_files"; Expected = $true },
    [pscustomobject]@{ Name = "expected_flag_metadata"; Expected = $true }
  )
  return @(Get-SuiteValidationSettingIssues $Manifest.suite_validation $ExpectedSettings)
}

function Get-OfficialManifestLabel {
  param(
    [object]$Manifest,
    [string]$Name,
    [string]$Fallback
  )

  $Value = Get-ObjectPropertyValue $Manifest.labels $Name
  if ([string]$Value) {
    return [string]$Value
  }
  return $Fallback
}

function Invoke-TrustedMatrixBenchmarkSuiteValidation {
  param(
    [object]$Manifest,
    [string]$ExpectedForkRevision,
    [switch]$RequirePackageSize
  )

  $Renderer = if ([string]$Manifest.renderer) { [string]$Manifest.renderer } else { "webgl2" }
  $ExpectedScenes = @($Manifest.scenes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($ExpectedScenes.Count -eq 0) {
    $ExpectedScenes = $RequiredScenes
  }
  $ExpectedMeasuredSeconds = if ($null -ne $Manifest.options.duration) { [double]$Manifest.options.duration } else { -1 }
  $ExpectedWarmupSeconds = if ($null -ne $Manifest.options.warmup) { [double]$Manifest.options.warmup } else { -1 }
  $Ok = $true
  $Outputs = [System.Collections.Generic.List[string]]::new()

  foreach ($Experiment in @($Manifest.experiments)) {
    $Label = [string]$Experiment.label
    if (-not $Label) {
      $Ok = $false
      $Outputs.Add("experiment missing label") | Out-Null
      continue
    }

    $Files = @($Experiment.result_files | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $ExpectedFlagMetadata = @($Experiment.expected_flag_metadata | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($Files.Count -ne $ExpectedScenes.Count) {
      $Ok = $false
      $Outputs.Add("${Label}: file count=$($Files.Count) expected=$($ExpectedScenes.Count)") | Out-Null
      continue
    }
    if ($ExpectedFlagMetadata.Count -eq 0) {
      $Ok = $false
      $Outputs.Add("${Label}: missing expected flag metadata in manifest experiments") | Out-Null
      continue
    }

    $Validation = Invoke-BenchmarkSuiteValidator `
      -Files $Files `
      -Renderer $Renderer `
      -Variant $Label `
      -RequireCheckout `
      -RequireBuildArgs `
      -ExpectedChromiumRevision $ExpectedChromiumRevision `
      -ExpectedBrowser ([string]$Manifest.browser) `
      -ForbidSmoke `
      -RequireForkRevision `
      -ExpectedForkRevision $ExpectedForkRevision `
      -RejectSoftwareRendering `
      -RequireGpuMetadata `
      -RequirePackageSize:$RequirePackageSize `
      -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds `
      -ExpectedWarmupSeconds $ExpectedWarmupSeconds `
      -ExpectedFlagMetadata $ExpectedFlagMetadata `
      -RequiredBrowserFlags $RequiredBrowserFlags `
      -ExpectedScenes $ExpectedScenes

    if (-not $Validation.Ok) {
      $Ok = $false
    }
    $Outputs.Add("${Label}: $($Validation.Output)") | Out-Null
  }

  return [pscustomobject]@{
    Ok = $Ok
    Output = ($Outputs -join " ")
  }
}

function Get-OfficialManifestExpectedFlagMetadata {
  param(
    [object]$Manifest,
    [string]$Name
  )

  $ExpectedFlagMetadata = Get-ObjectPropertyValue $Manifest.suite_validation "expected_flag_metadata"
  $Value = Get-ObjectPropertyValue $ExpectedFlagMetadata $Name
  return @($Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Invoke-OfficialManifestBenchmarkSuiteValidation {
  param(
    [object]$Manifest,
    [string]$ExpectedForkRevision,
    [switch]$BaselinePackageRequired,
    [switch]$ForkPackageRequired
  )

  $ExpectedMeasuredSeconds = if ($null -ne $Manifest.options.duration) { [double]$Manifest.options.duration } else { -1 }
  $ExpectedWarmupSeconds = if ($null -ne $Manifest.options.warmup) { [double]$Manifest.options.warmup } else { -1 }
  $BaselineLabel = Get-OfficialManifestLabel -Manifest $Manifest -Name "baseline" -Fallback "baseline-content-shell"
  $ForkDefaultLabel = Get-OfficialManifestLabel -Manifest $Manifest -Name "fork_default" -Fallback "fork-viewer-default"
  $AggressiveLabelFallback = if ([string]$Manifest.options.aggressive_angle_backend) {
    "fork-viewer-aggressive-gpu-$($Manifest.options.aggressive_angle_backend)"
  } else {
    "fork-viewer-aggressive-gpu"
  }
  $AggressiveLabel = Get-OfficialManifestLabel -Manifest $Manifest -Name "aggressive" -Fallback $AggressiveLabelFallback

  $Cases = [System.Collections.Generic.List[object]]::new()
  $Cases.Add([pscustomobject]@{
      Name = "baseline_webgl2"
      Files = @($Manifest.result_files.baseline_webgl2)
      Renderer = "webgl2"
      Variant = $BaselineLabel
      RequireForkRevision = $false
      RequirePackageSize = [bool]$BaselinePackageRequired
      ExpectedBrowser = [string]$Manifest.browsers.baseline
      ExpectedFlagMetadata = @(Get-OfficialManifestExpectedFlagMetadata -Manifest $Manifest -Name "baseline")
    }) | Out-Null
  $Cases.Add([pscustomobject]@{
      Name = "fork_default_webgl2"
      Files = @($Manifest.result_files.fork_default_webgl2)
      Renderer = "webgl2"
      Variant = $ForkDefaultLabel
      RequireForkRevision = $true
      RequirePackageSize = [bool]$ForkPackageRequired
      ExpectedBrowser = [string]$Manifest.browsers.fork
      ExpectedFlagMetadata = @(Get-OfficialManifestExpectedFlagMetadata -Manifest $Manifest -Name "fork_default")
    }) | Out-Null

  if ($Manifest.options.include_aggressive_gpu) {
    $Cases.Add([pscustomobject]@{
        Name = "aggressive_webgl2"
        Files = @($Manifest.result_files.aggressive_webgl2)
        Renderer = "webgl2"
        Variant = $AggressiveLabel
        RequireForkRevision = $true
        RequirePackageSize = [bool]$ForkPackageRequired
        ExpectedBrowser = [string]$Manifest.browsers.fork
        ExpectedFlagMetadata = @(Get-OfficialManifestExpectedFlagMetadata -Manifest $Manifest -Name "aggressive")
      }) | Out-Null
  }

  if ($Manifest.options.include_webgpu) {
    $Cases.Add([pscustomobject]@{
        Name = "baseline_webgpu"
        Files = @($Manifest.result_files.baseline_webgpu)
        Renderer = "webgpu"
        Variant = "$BaselineLabel-webgpu"
        RequireForkRevision = $false
        RequirePackageSize = [bool]$BaselinePackageRequired
        ExpectedBrowser = [string]$Manifest.browsers.baseline
        ExpectedFlagMetadata = @(Get-OfficialManifestExpectedFlagMetadata -Manifest $Manifest -Name "baseline_webgpu")
      }) | Out-Null
    $Cases.Add([pscustomobject]@{
        Name = "fork_default_webgpu"
        Files = @($Manifest.result_files.fork_default_webgpu)
        Renderer = "webgpu"
        Variant = "$ForkDefaultLabel-webgpu"
        RequireForkRevision = $true
        RequirePackageSize = [bool]$ForkPackageRequired
        ExpectedBrowser = [string]$Manifest.browsers.fork
        ExpectedFlagMetadata = @(Get-OfficialManifestExpectedFlagMetadata -Manifest $Manifest -Name "fork_default_webgpu")
      }) | Out-Null
    if ($Manifest.options.include_aggressive_gpu) {
      $Cases.Add([pscustomobject]@{
          Name = "aggressive_webgpu"
          Files = @($Manifest.result_files.aggressive_webgpu)
          Renderer = "webgpu"
          Variant = "$AggressiveLabel-webgpu"
          RequireForkRevision = $true
          RequirePackageSize = [bool]$ForkPackageRequired
          ExpectedBrowser = [string]$Manifest.browsers.fork
          ExpectedFlagMetadata = @(Get-OfficialManifestExpectedFlagMetadata -Manifest $Manifest -Name "aggressive_webgpu")
        }) | Out-Null
    }
  }

  $Ok = $true
  $Outputs = [System.Collections.Generic.List[string]]::new()
  foreach ($Case in $Cases) {
    $Files = @($Case.Files | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $ExpectedFlagMetadata = @($Case.ExpectedFlagMetadata | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($Files.Count -ne $RequiredScenes.Count) {
      $Ok = $false
      $Outputs.Add("$($Case.Name): file count=$($Files.Count) expected=$($RequiredScenes.Count)") | Out-Null
      continue
    }
    if ($ExpectedFlagMetadata.Count -eq 0) {
      $Ok = $false
      $Outputs.Add("$($Case.Name): missing expected flag metadata in manifest suite_validation") | Out-Null
      continue
    }

    $Validation = Invoke-BenchmarkSuiteValidator `
      -Files $Files `
      -Renderer $Case.Renderer `
      -Variant $Case.Variant `
      -RequireCheckout `
      -RequireBuildArgs `
      -ExpectedChromiumRevision $ExpectedChromiumRevision `
      -ExpectedBrowser $Case.ExpectedBrowser `
      -ForbidSmoke `
      -RequireForkRevision:([bool]$Case.RequireForkRevision) `
      -ExpectedForkRevision $(if ($Case.RequireForkRevision) { $ExpectedForkRevision } else { "" }) `
      -RejectSoftwareRendering `
      -RequireGpuMetadata `
      -RequirePackageSize:([bool]$Case.RequirePackageSize) `
      -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds `
      -ExpectedWarmupSeconds $ExpectedWarmupSeconds `
      -ExpectedFlagMetadata $ExpectedFlagMetadata `
      -RequiredBrowserFlags $RequiredBrowserFlags `
      -ExpectedScenes $RequiredScenes

    if (-not $Validation.Ok) {
      $Ok = $false
    }
    $Outputs.Add("$($Case.Name): $($Validation.Output)") | Out-Null
  }

  return [pscustomobject]@{
    Ok = $Ok
    Output = ($Outputs -join " ")
  }
}

function Add-OfficialComparisonManifestRow {
  $PathValue = Get-OfficialComparisonManifestPathValue
  if (-not (Test-RepoPath $PathValue)) {
    Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue missing" "Run scripts/run_official_comparison.ps1 after stock/fork binaries exist."
    return
  }

  try {
    $Manifest = Get-Content (Resolve-RepoPath $PathValue) -Raw | ConvertFrom-Json
    $ExpectedForkRevision = Get-ExpectedViewerForkRevision
    $BaselineCount = @($Manifest.result_files.baseline_webgl2).Count
    $ForkCount = @($Manifest.result_files.fork_default_webgl2).Count
    $AggressiveCount = @($Manifest.result_files.aggressive_webgl2).Count
    $BaselineWebGpuCount = @($Manifest.result_files.baseline_webgpu).Count
    $ForkWebGpuCount = @($Manifest.result_files.fork_default_webgpu).Count
    $AggressiveWebGpuCount = @($Manifest.result_files.aggressive_webgpu).Count
    $BaselineWebGlHashCount = @($Manifest.artifact_metadata.results.baseline_webgl2 | Where-Object { $_.exists -and $_.sha256 }).Count
    $ForkWebGlHashCount = @($Manifest.artifact_metadata.results.fork_default_webgl2 | Where-Object { $_.exists -and $_.sha256 }).Count
    $AggressiveHashCount = @($Manifest.artifact_metadata.results.aggressive_webgl2 | Where-Object { $_.exists -and $_.sha256 }).Count
    $BaselineWebGpuHashCount = @($Manifest.artifact_metadata.results.baseline_webgpu | Where-Object { $_.exists -and $_.sha256 }).Count
    $ForkWebGpuHashCount = @($Manifest.artifact_metadata.results.fork_default_webgpu | Where-Object { $_.exists -and $_.sha256 }).Count
    $AggressiveWebGpuHashCount = @($Manifest.artifact_metadata.results.aggressive_webgpu | Where-Object { $_.exists -and $_.sha256 }).Count
    $RuntimeSmokeCount = @($Manifest.result_files.runtime_smoke).Count
    $NavigationLockCount = @($Manifest.result_files.navigation_lock).Count
    $RuntimeSmokeHashCount = @($Manifest.artifact_metadata.runtime_tests.smoke | Where-Object { $_.exists -and $_.sha256 }).Count
    $NavigationLockHashCount = @($Manifest.artifact_metadata.runtime_tests.navigation_lock | Where-Object { $_.exists -and $_.sha256 }).Count
    $AggressiveBackendConsistencyOk = $true
    $AggressiveBackendConsistencyOutput = ""
    if ($Manifest.options.include_aggressive_gpu) {
      $AggressiveBackend = [string]$Manifest.options.aggressive_angle_backend
      $ExpectedAggressiveLabel = if ($AggressiveBackend) {
        "fork-viewer-aggressive-gpu-$AggressiveBackend"
      } else {
        ""
      }
      $AggressiveLabel = [string]$Manifest.labels.aggressive
      $AggressiveExpectedFlags = @($Manifest.suite_validation.expected_flag_metadata.aggressive)
      $AggressiveWebGpuExpectedFlags = @($Manifest.suite_validation.expected_flag_metadata.aggressive_webgpu)
      $ExpectedAggressiveBackendFlag = if ($AggressiveBackend) {
        "viewer_force_angle_backend=$AggressiveBackend"
      } else {
        ""
      }
      $ExpectedRequestedBackendFlag = if ($AggressiveBackend) {
        "requested_angle_backend=$AggressiveBackend"
      } else {
        ""
      }
      $AggressiveFileNames = @($Manifest.result_files.aggressive_webgl2 | ForEach-Object {
          [System.IO.Path]::GetFileName([string]$_)
        })
      $AggressiveWebGpuFileNames = @($Manifest.result_files.aggressive_webgpu | ForEach-Object {
          [System.IO.Path]::GetFileName([string]$_)
        })
      $UnexpectedAggressiveFiles = @()
      if ($ExpectedAggressiveLabel) {
        $UnexpectedAggressiveFiles = @($AggressiveFileNames | Where-Object {
            $_ -and -not $_.StartsWith("$ExpectedAggressiveLabel-", [System.StringComparison]::OrdinalIgnoreCase)
          })
        $UnexpectedAggressiveFiles += @($AggressiveWebGpuFileNames | Where-Object {
            $_ -and -not $_.StartsWith("$ExpectedAggressiveLabel-webgpu-", [System.StringComparison]::OrdinalIgnoreCase)
          })
      }

      if (-not $AggressiveBackend) {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "missing aggressive_angle_backend"
      } elseif ($AggressiveLabel -ne $ExpectedAggressiveLabel) {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "labels.aggressive=$AggressiveLabel expected=$ExpectedAggressiveLabel"
      } elseif ($AggressiveExpectedFlags -notcontains "viewer_aggressive_gpu=true") {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "expected aggressive flag metadata missing viewer_aggressive_gpu=true"
      } elseif ($AggressiveExpectedFlags -notcontains $ExpectedAggressiveBackendFlag) {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "expected aggressive flag metadata missing $ExpectedAggressiveBackendFlag"
      } elseif ($AggressiveExpectedFlags -notcontains $ExpectedRequestedBackendFlag) {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "expected aggressive flag metadata missing $ExpectedRequestedBackendFlag"
      } elseif ($Manifest.options.include_webgpu -and ($AggressiveWebGpuExpectedFlags -notcontains "viewer_aggressive_gpu=true")) {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "expected aggressive WebGPU flag metadata missing viewer_aggressive_gpu=true"
      } elseif ($Manifest.options.include_webgpu -and ($AggressiveWebGpuExpectedFlags -notcontains $ExpectedAggressiveBackendFlag)) {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "expected aggressive WebGPU flag metadata missing $ExpectedAggressiveBackendFlag"
      } elseif ($Manifest.options.include_webgpu -and ($AggressiveWebGpuExpectedFlags -notcontains $ExpectedRequestedBackendFlag)) {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "expected aggressive WebGPU flag metadata missing $ExpectedRequestedBackendFlag"
      } elseif ($UnexpectedAggressiveFiles.Count -gt 0) {
        $AggressiveBackendConsistencyOk = $false
        $AggressiveBackendConsistencyOutput = "aggressive result files do not match ${ExpectedAggressiveLabel}: $($UnexpectedAggressiveFiles -join ', ')"
      }
    }
    $PinRefreshValidation = Test-PinRefreshForCompletedManifest `
      -ManifestGeneratedAt ([string]$Manifest.generated_at) `
      -ManifestChromiumRevision ([string]$Manifest.chromium_revision)
    $RuntimeSmokeValidationOk = $true
    $RuntimeSmokeValidationOutput = ""
    if (-not [bool]$Manifest.options.skip_smoke -and $RuntimeSmokeCount -eq 2 -and $RuntimeSmokeHashCount -eq 2) {
      $ExpectedBaselineBrowser = [string]$Manifest.browsers.baseline
      if (-not $ExpectedBaselineBrowser) {
        $ExpectedBaselineBrowser = [string]$Manifest.artifact_metadata.inputs.baseline_browser.path
      }
      $ExpectedForkBrowser = [string]$Manifest.browsers.fork
      if (-not $ExpectedForkBrowser) {
        $ExpectedForkBrowser = [string]$Manifest.artifact_metadata.inputs.fork_browser.path
      }
      $RuntimeSmokeFiles = @($Manifest.result_files.runtime_smoke)
      $BaselineRuntimeSmokeFile = @($RuntimeSmokeFiles | Where-Object { [System.IO.Path]::GetFileName([string]$_) -match "^baseline-content-shell-runtime-smoke\.json$" })
      $ForkRuntimeSmokeFile = @($RuntimeSmokeFiles | Where-Object { [System.IO.Path]::GetFileName([string]$_) -match "^fork-viewer-default-runtime-smoke\.json$" })
      if (-not $ExpectedBaselineBrowser -or -not $ExpectedForkBrowser) {
        $RuntimeSmokeValidationOk = $false
        $RuntimeSmokeValidationOutput = "runtime smoke validation requires manifest baseline and fork browser paths"
      } elseif ($BaselineRuntimeSmokeFile.Count -ne 1 -or $ForkRuntimeSmokeFile.Count -ne 1) {
        $RuntimeSmokeValidationOk = $false
        $RuntimeSmokeValidationOutput = "runtime smoke files must include exactly baseline-content-shell-runtime-smoke.json and fork-viewer-default-runtime-smoke.json"
      } else {
        $RequireWebGpuRuntimeSmoke = [bool]$Manifest.options.include_webgpu
        $BaselineRuntimeSmokeValidation = Invoke-SmokeValidator -Type "runtime" -Files @($BaselineRuntimeSmokeFile[0]) -ExpectedBrowser $ExpectedBaselineBrowser -ExpectBrowserMode -RequireWebGPU:$RequireWebGpuRuntimeSmoke -RequiredBrowserFlags $RequiredBrowserFlags
        $ForkRuntimeSmokeValidation = Invoke-SmokeValidator -Type "runtime" -Files @($ForkRuntimeSmokeFile[0]) -ExpectedBrowser $ExpectedForkBrowser -ExpectViewerMode -ExpectViewerTrustedContent -RequireWebGPU:$RequireWebGpuRuntimeSmoke -RequiredBrowserFlags $RequiredBrowserFlags
        $RuntimeSmokeValidationOk = $BaselineRuntimeSmokeValidation.Ok -and $ForkRuntimeSmokeValidation.Ok
        $RuntimeSmokeValidationOutput = @($BaselineRuntimeSmokeValidation.Output, $ForkRuntimeSmokeValidation.Output) -join " "
      }
    }
    $NavigationLockValidationOk = $true
    $NavigationLockValidationOutput = ""
    if (-not [bool]$Manifest.options.skip_navigation_lock -and $NavigationLockCount -eq 2 -and $NavigationLockHashCount -eq 2) {
      $ExpectedForkNavigationBrowser = [string]$Manifest.browsers.fork
      if (-not $ExpectedForkNavigationBrowser) {
        $ExpectedForkNavigationBrowser = [string]$Manifest.artifact_metadata.inputs.fork_browser.path
      }
      $NavigationFiles = @($Manifest.result_files.navigation_lock)
      $HttpNavigationFile = @($NavigationFiles | Where-Object { [System.IO.Path]::GetFileName([string]$_) -notmatch "file-navigation-lock" } | Select-Object -First 1)
      $FileNavigationFile = @($NavigationFiles | Where-Object { [System.IO.Path]::GetFileName([string]$_) -match "file-navigation-lock" } | Select-Object -First 1)
      if (-not $ExpectedForkNavigationBrowser) {
        $NavigationLockValidationOk = $false
        $NavigationLockValidationOutput = "navigation lock validation requires manifest fork browser path"
      } elseif ($HttpNavigationFile.Count -ne 1 -or $FileNavigationFile.Count -ne 1) {
        $NavigationLockValidationOk = $false
        $NavigationLockValidationOutput = "navigation lock result files must include one HTTP navigation-lock JSON and one file-navigation-lock JSON"
      } else {
        $HttpNavigationValidation = Invoke-SmokeValidator -Type "navigation" -Files @($HttpNavigationFile[0]) -ExpectedBrowser $ExpectedForkNavigationBrowser
        $FileNavigationValidation = Invoke-SmokeValidator -Type "file-navigation" -Files @($FileNavigationFile[0]) -ExpectedBrowser $ExpectedForkNavigationBrowser
        $NavigationLockValidationOk = $HttpNavigationValidation.Ok -and $FileNavigationValidation.Ok
        $NavigationLockValidationOutput = @($HttpNavigationValidation.Output, $FileNavigationValidation.Output) -join " "
      }
    }
    $HasTraceSummaryHashes = (
      $Manifest.artifact_metadata.reports.baseline_trace_summary.exists -and
      $Manifest.artifact_metadata.reports.baseline_trace_summary.sha256 -and
      $Manifest.artifact_metadata.reports.fork_trace_summary.exists -and
      $Manifest.artifact_metadata.reports.fork_trace_summary.sha256
    )
    $HasTraceSidecarHashes = (
      $Manifest.artifact_metadata.traces.baseline_result.exists -and
      $Manifest.artifact_metadata.traces.baseline_result.sha256 -and
      $Manifest.artifact_metadata.traces.fork_result.exists -and
      $Manifest.artifact_metadata.traces.fork_result.sha256
    )
    $TraceFileValidationOk = $true
    $TraceFileValidationOutput = ""
    if ($Manifest.options.capture_trace -and
        $Manifest.artifact_metadata.traces.baseline.exists -and
        $Manifest.artifact_metadata.traces.baseline.sha256 -and
        $Manifest.artifact_metadata.traces.fork.exists -and
        $Manifest.artifact_metadata.traces.fork.sha256) {
      $BaselineTracePath = if ($Manifest.trace_files.baseline) { $Manifest.trace_files.baseline } else { $Manifest.artifact_metadata.traces.baseline.path }
      $ForkTracePath = if ($Manifest.trace_files.fork) { $Manifest.trace_files.fork } else { $Manifest.artifact_metadata.traces.fork.path }
      $BaselineTraceValidation = Invoke-TraceFileValidator -File $BaselineTracePath -MinEvents 1
      $ForkTraceValidation = Invoke-TraceFileValidator -File $ForkTracePath -MinEvents 1
      $TraceFileValidationOk = $BaselineTraceValidation.Ok -and $ForkTraceValidation.Ok
      $TraceFileValidationOutput = @($BaselineTraceValidation.Output, $ForkTraceValidation.Output) -join " "
    }
    $TraceSidecarValidationOk = $true
    $TraceSidecarValidationOutput = ""
    if ($Manifest.options.capture_trace -and $HasTraceSidecarHashes) {
      $TraceStartDelayMs = if ($null -ne $Manifest.options.trace_start_delay_ms) { [int]$Manifest.options.trace_start_delay_ms } else { 2000 }
      $BaselineTraceResultPath = if ($Manifest.trace_result_files.baseline) { $Manifest.trace_result_files.baseline } else { $Manifest.artifact_metadata.traces.baseline_result.path }
      $ForkTraceResultPath = if ($Manifest.trace_result_files.fork) { $Manifest.trace_result_files.fork } else { $Manifest.artifact_metadata.traces.fork_result.path }
      $BaselineTraceExpectedFlags = @(
        "viewer_mode=false",
        "viewer_block_external_navigation=false",
        "viewer_trusted_content=false",
        "viewer_aggressive_gpu=false",
        "viewer_relaxed_webgl_validation=false",
        "viewer_in_process_gpu=false",
        "viewer_single_process=false",
        "viewer_force_angle_backend=null",
        "requested_angle_backend=null",
        "viewer_disable_unneeded_blink_features=false",
        "viewer_direct_gpu_presentation=false"
      )
      $ForkTraceExpectedFlags = @(
        "viewer_mode=true",
        "viewer_block_external_navigation=true",
        "viewer_trusted_content=true",
        "viewer_aggressive_gpu=false",
        "viewer_relaxed_webgl_validation=false",
        "viewer_in_process_gpu=false",
        "viewer_single_process=false",
        "viewer_force_angle_backend=null",
        "requested_angle_backend=null",
        "viewer_disable_unneeded_blink_features=false",
        "viewer_direct_gpu_presentation=false"
      )
      $BaselineTraceResultValidation = Invoke-TraceResultValidator `
        -File $BaselineTraceResultPath `
        -ExpectedScene $Manifest.options.trace_scene `
        -ExpectedRenderer $Manifest.options.trace_renderer `
        -ExpectedBrowser $Manifest.browsers.baseline `
        -ExpectedDuration ([int]$Manifest.options.trace_duration) `
        -ExpectedWarmup ([int]$Manifest.options.trace_warmup) `
        -ExpectedStartDelayMs $TraceStartDelayMs `
        -ExpectedFlagMetadata $BaselineTraceExpectedFlags `
        -RequiredBrowserFlags $RequiredBrowserFlags
      $ForkTraceResultValidation = Invoke-TraceResultValidator `
        -File $ForkTraceResultPath `
        -ExpectedScene $Manifest.options.trace_scene `
        -ExpectedRenderer $Manifest.options.trace_renderer `
        -ExpectedBrowser $Manifest.browsers.fork `
        -ExpectedDuration ([int]$Manifest.options.trace_duration) `
        -ExpectedWarmup ([int]$Manifest.options.trace_warmup) `
        -ExpectedStartDelayMs $TraceStartDelayMs `
        -ExpectedFlagMetadata $ForkTraceExpectedFlags `
        -RequiredBrowserFlags $RequiredBrowserFlags
      $TraceSidecarValidationOk = $BaselineTraceResultValidation.Ok -and $ForkTraceResultValidation.Ok
      $TraceSidecarValidationOutput = @($BaselineTraceResultValidation.Output, $ForkTraceResultValidation.Output) -join " "
    }
    $BaselinePackageRequired = [bool]$Manifest.package_dirs.baseline
    $ForkPackageRequired = [bool]$Manifest.package_dirs.fork
    $BaselinePackageOk = (-not $BaselinePackageRequired) -or (
      $Manifest.artifact_metadata.inputs.baseline_package.exists -and
      $Manifest.artifact_metadata.inputs.baseline_package.file_count -gt 0 -and
      $Manifest.artifact_metadata.inputs.baseline_package.size_bytes -gt 0
    )
    $ForkPackageOk = (-not $ForkPackageRequired) -or (
      $Manifest.artifact_metadata.inputs.fork_package.exists -and
      $Manifest.artifact_metadata.inputs.fork_package.file_count -gt 0 -and
      $Manifest.artifact_metadata.inputs.fork_package.size_bytes -gt 0
    )
    $OfficialFileMetadataChecks = @(
      [pscustomobject]@{ Label = "baseline_browser"; Metadata = $Manifest.artifact_metadata.inputs.baseline_browser; ExpectedPath = $Manifest.browsers.baseline },
      [pscustomobject]@{ Label = "fork_browser"; Metadata = $Manifest.artifact_metadata.inputs.fork_browser; ExpectedPath = $Manifest.browsers.fork },
      [pscustomobject]@{ Label = "baseline_build_args"; Metadata = $Manifest.artifact_metadata.inputs.baseline_build_args; ExpectedPath = $Manifest.build_args.baseline },
      [pscustomobject]@{ Label = "fork_build_args"; Metadata = $Manifest.artifact_metadata.inputs.fork_build_args; ExpectedPath = $Manifest.build_args.fork },
      [pscustomobject]@{ Label = "viewer_patch"; Metadata = $Manifest.artifact_metadata.inputs.viewer_patch; ExpectedPath = "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch" },
      [pscustomobject]@{ Label = "report:official_webgl2_comparison"; Metadata = $Manifest.artifact_metadata.reports.official_webgl2_comparison; ExpectedPath = $Manifest.report_files.official_webgl2_comparison }
    )
    $BaselineWebGlMetadata = @($Manifest.artifact_metadata.results.baseline_webgl2)
    $BaselineWebGlPaths = @($Manifest.result_files.baseline_webgl2)
    for ($Index = 0; $Index -lt $BaselineWebGlMetadata.Count; $Index += 1) {
      $ExpectedPath = if ($Index -lt $BaselineWebGlPaths.Count) { $BaselineWebGlPaths[$Index] } else { "" }
      $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "result:baseline_webgl2:$Index"; Metadata = $BaselineWebGlMetadata[$Index]; ExpectedPath = $ExpectedPath }
    }
    $ForkWebGlMetadata = @($Manifest.artifact_metadata.results.fork_default_webgl2)
    $ForkWebGlPaths = @($Manifest.result_files.fork_default_webgl2)
    for ($Index = 0; $Index -lt $ForkWebGlMetadata.Count; $Index += 1) {
      $ExpectedPath = if ($Index -lt $ForkWebGlPaths.Count) { $ForkWebGlPaths[$Index] } else { "" }
      $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "result:fork_default_webgl2:$Index"; Metadata = $ForkWebGlMetadata[$Index]; ExpectedPath = $ExpectedPath }
    }
    $RuntimeSmokeMetadata = @($Manifest.artifact_metadata.runtime_tests.smoke)
    $RuntimeSmokePaths = @($Manifest.result_files.runtime_smoke)
    for ($Index = 0; $Index -lt $RuntimeSmokeMetadata.Count; $Index += 1) {
      $ExpectedPath = if ($Index -lt $RuntimeSmokePaths.Count) { $RuntimeSmokePaths[$Index] } else { "" }
      $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "runtime_smoke:$Index"; Metadata = $RuntimeSmokeMetadata[$Index]; ExpectedPath = $ExpectedPath }
    }
    $NavigationLockMetadata = @($Manifest.artifact_metadata.runtime_tests.navigation_lock)
    $NavigationLockPaths = @($Manifest.result_files.navigation_lock)
    for ($Index = 0; $Index -lt $NavigationLockMetadata.Count; $Index += 1) {
      $ExpectedPath = if ($Index -lt $NavigationLockPaths.Count) { $NavigationLockPaths[$Index] } else { "" }
      $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "navigation_lock:$Index"; Metadata = $NavigationLockMetadata[$Index]; ExpectedPath = $ExpectedPath }
    }
    if ($Manifest.options.include_aggressive_gpu) {
      $AggressiveWebGlMetadata = @($Manifest.artifact_metadata.results.aggressive_webgl2)
      $AggressiveWebGlPaths = @($Manifest.result_files.aggressive_webgl2)
      for ($Index = 0; $Index -lt $AggressiveWebGlMetadata.Count; $Index += 1) {
        $ExpectedPath = if ($Index -lt $AggressiveWebGlPaths.Count) { $AggressiveWebGlPaths[$Index] } else { "" }
        $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "result:aggressive_webgl2:$Index"; Metadata = $AggressiveWebGlMetadata[$Index]; ExpectedPath = $ExpectedPath }
      }
    }
    if ($Manifest.options.include_webgpu) {
      $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "report:official_webgpu_comparison"; Metadata = $Manifest.artifact_metadata.reports.official_webgpu_comparison; ExpectedPath = $Manifest.report_files.official_webgpu_comparison }
      $BaselineWebGpuMetadata = @($Manifest.artifact_metadata.results.baseline_webgpu)
      $BaselineWebGpuPaths = @($Manifest.result_files.baseline_webgpu)
      for ($Index = 0; $Index -lt $BaselineWebGpuMetadata.Count; $Index += 1) {
        $ExpectedPath = if ($Index -lt $BaselineWebGpuPaths.Count) { $BaselineWebGpuPaths[$Index] } else { "" }
        $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "result:baseline_webgpu:$Index"; Metadata = $BaselineWebGpuMetadata[$Index]; ExpectedPath = $ExpectedPath }
      }
      $ForkWebGpuMetadata = @($Manifest.artifact_metadata.results.fork_default_webgpu)
      $ForkWebGpuPaths = @($Manifest.result_files.fork_default_webgpu)
      for ($Index = 0; $Index -lt $ForkWebGpuMetadata.Count; $Index += 1) {
        $ExpectedPath = if ($Index -lt $ForkWebGpuPaths.Count) { $ForkWebGpuPaths[$Index] } else { "" }
        $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "result:fork_default_webgpu:$Index"; Metadata = $ForkWebGpuMetadata[$Index]; ExpectedPath = $ExpectedPath }
      }
      if ($Manifest.options.include_aggressive_gpu) {
        $AggressiveWebGpuMetadata = @($Manifest.artifact_metadata.results.aggressive_webgpu)
        $AggressiveWebGpuPaths = @($Manifest.result_files.aggressive_webgpu)
        for ($Index = 0; $Index -lt $AggressiveWebGpuMetadata.Count; $Index += 1) {
          $ExpectedPath = if ($Index -lt $AggressiveWebGpuPaths.Count) { $AggressiveWebGpuPaths[$Index] } else { "" }
          $OfficialFileMetadataChecks += [pscustomobject]@{ Label = "result:aggressive_webgpu:$Index"; Metadata = $AggressiveWebGpuMetadata[$Index]; ExpectedPath = $ExpectedPath }
        }
      }
    }
    if ($Manifest.options.capture_trace) {
      $OfficialFileMetadataChecks += @(
        [pscustomobject]@{ Label = "trace:baseline"; Metadata = $Manifest.artifact_metadata.traces.baseline; ExpectedPath = $Manifest.trace_files.baseline },
        [pscustomobject]@{ Label = "trace:fork"; Metadata = $Manifest.artifact_metadata.traces.fork; ExpectedPath = $Manifest.trace_files.fork },
        [pscustomobject]@{ Label = "trace:baseline_result"; Metadata = $Manifest.artifact_metadata.traces.baseline_result; ExpectedPath = $Manifest.trace_result_files.baseline },
        [pscustomobject]@{ Label = "trace:fork_result"; Metadata = $Manifest.artifact_metadata.traces.fork_result; ExpectedPath = $Manifest.trace_result_files.fork },
        [pscustomobject]@{ Label = "report:baseline_trace_summary"; Metadata = $Manifest.artifact_metadata.reports.baseline_trace_summary; ExpectedPath = $Manifest.report_files.baseline_trace_summary },
        [pscustomobject]@{ Label = "report:fork_trace_summary"; Metadata = $Manifest.artifact_metadata.reports.fork_trace_summary; ExpectedPath = $Manifest.report_files.fork_trace_summary }
      )
    }
    $OfficialDirectoryMetadataChecks = @()
    if ($BaselinePackageRequired) {
      $OfficialDirectoryMetadataChecks += [pscustomobject]@{ Label = "baseline_package"; Metadata = $Manifest.artifact_metadata.inputs.baseline_package; ExpectedPath = $Manifest.package_dirs.baseline }
    }
    if ($ForkPackageRequired) {
      $OfficialDirectoryMetadataChecks += [pscustomobject]@{ Label = "fork_package"; Metadata = $Manifest.artifact_metadata.inputs.fork_package; ExpectedPath = $Manifest.package_dirs.fork }
    }
    $OfficialInvalidFiles = @(Get-InvalidFileMetadataLabels $OfficialFileMetadataChecks)
    $OfficialInvalidDirectories = @(Get-InvalidDirectoryMetadataLabels $OfficialDirectoryMetadataChecks)
    $OfficialPackageExecutableChecks = @()
    if ($BaselinePackageRequired) {
      $OfficialPackageExecutableChecks += [pscustomobject]@{
        Label = "baseline_package"
        PackageMetadata = $Manifest.artifact_metadata.inputs.baseline_package
        BrowserMetadata = $Manifest.artifact_metadata.inputs.baseline_browser
      }
    }
    if ($ForkPackageRequired) {
      $OfficialPackageExecutableChecks += [pscustomobject]@{
        Label = "fork_package"
        PackageMetadata = $Manifest.artifact_metadata.inputs.fork_package
        BrowserMetadata = $Manifest.artifact_metadata.inputs.fork_browser
      }
    }
    $OfficialInvalidPackageExecutables = @(Get-InvalidPackageExecutableLabels $OfficialPackageExecutableChecks)
    $OfficialSuiteValidation = [pscustomobject]@{
      Ok = $true
      Output = ""
    }
    if ($OfficialInvalidFiles.Count -eq 0 -and $OfficialInvalidDirectories.Count -eq 0 -and $OfficialInvalidPackageExecutables.Count -eq 0) {
      $OfficialSuiteValidation = Invoke-OfficialManifestBenchmarkSuiteValidation `
        -Manifest $Manifest `
        -ExpectedForkRevision $ExpectedForkRevision `
        -BaselinePackageRequired:$BaselinePackageRequired `
        -ForkPackageRequired:$ForkPackageRequired
    }
    $OfficialReportContentIssues = @()
    if ($OfficialInvalidFiles.Count -eq 0) {
      $OfficialReportContentIssues = @(Get-OfficialComparisonReportContentIssues -Manifest $Manifest)
      if ($Manifest.options.capture_trace) {
        $OfficialReportContentIssues += @(Get-OfficialTraceSummaryReportContentIssues -Manifest $Manifest)
      }
    }
    $OfficialSuiteSettingIssues = @(Get-OfficialManifestSuiteValidationIssues `
        -Manifest $Manifest `
        -ExpectedForkRevision $ExpectedForkRevision)
    if ($Manifest.dry_run) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue is a dry-run manifest" "Run without -DryRun after stock/fork binaries exist."
    } elseif ($Manifest.phase -ne "completed") {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue phase=$($Manifest.phase)" "Regenerate after the official comparison completes successfully."
    } elseif ($Manifest.chromium_revision -ne $ExpectedChromiumRevision) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue chromium_revision=$($Manifest.chromium_revision) expected=$ExpectedChromiumRevision" "Regenerate official comparison manifest from the pinned Chromium checkout."
    } elseif (-not $PinRefreshValidation.Ok) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not follow the current Chromium pin refresh: $($PinRefreshValidation.Output)" "Regenerate via scripts/run_post_atl_pipeline.ps1 -RefreshChromiumPin so official stock/fork evidence follows the current upstream-head pin refresh."
    } elseif ($Manifest.fork_revision -ne $ExpectedForkRevision) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue fork_revision=$($Manifest.fork_revision) expected=$ExpectedForkRevision" "Regenerate official comparison manifest from the current patch."
    } elseif ($Manifest.suite_validation.expected_measured_seconds -ne $Manifest.options.duration -or $Manifest.suite_validation.expected_warmup_seconds -ne $Manifest.options.warmup) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not record suite duration/warmup validation matching options" "Regenerate with current run_official_comparison.ps1 so official results enforce measured_seconds and warmup_seconds."
    } elseif ($OfficialSuiteSettingIssues.Count -gt 0) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue suite validation settings mismatch: $($OfficialSuiteSettingIssues -join '; ')" "Regenerate with current run_official_comparison.ps1 so the official manifest records checkout, build-args, revision, GPU, exact-scene, no-smoke, and flag-metadata gates."
    } elseif (-not $AggressiveBackendConsistencyOk) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue aggressive backend metadata mismatch: $AggressiveBackendConsistencyOutput" "Regenerate with -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 so aggressive result labels and expected flag metadata match the requested backend."
    } elseif ($BaselineCount -ne $RequiredScenes.Count -or $ForkCount -ne $RequiredScenes.Count) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue webgl2 file counts baseline=$BaselineCount fork=$ForkCount expected=$($RequiredScenes.Count)" "Regenerate official comparison with the complete scene suite."
    } elseif ($BaselineWebGlHashCount -ne $RequiredScenes.Count -or $ForkWebGlHashCount -ne $RequiredScenes.Count) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue hashed webgl2 result counts baseline=$BaselineWebGlHashCount fork=$ForkWebGlHashCount expected=$($RequiredScenes.Count)" "Regenerate after all official WebGL2 result JSON files are written."
    } elseif ($Manifest.options.include_aggressive_gpu -and ($AggressiveCount -ne $RequiredScenes.Count -or $AggressiveHashCount -ne $RequiredScenes.Count)) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue aggressive WebGL2 counts files=$AggressiveCount hashes=$AggressiveHashCount expected=$($RequiredScenes.Count)" "Regenerate after the trusted/aggressive WebGL2 suite completes."
    } elseif ($Manifest.options.include_webgpu -and ($BaselineWebGpuCount -ne $RequiredScenes.Count -or $ForkWebGpuCount -ne $RequiredScenes.Count)) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue webgpu file counts baseline=$BaselineWebGpuCount fork=$ForkWebGpuCount expected=$($RequiredScenes.Count)" "Regenerate official comparison with the complete WebGPU scene suite."
    } elseif ($Manifest.options.include_webgpu -and ($BaselineWebGpuHashCount -ne $RequiredScenes.Count -or $ForkWebGpuHashCount -ne $RequiredScenes.Count)) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue hashed webgpu result counts baseline=$BaselineWebGpuHashCount fork=$ForkWebGpuHashCount expected=$($RequiredScenes.Count)" "Regenerate after all official WebGPU result JSON files are written."
    } elseif ($Manifest.options.include_webgpu -and $Manifest.options.include_aggressive_gpu -and ($AggressiveWebGpuCount -ne $RequiredScenes.Count -or $AggressiveWebGpuHashCount -ne $RequiredScenes.Count)) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue aggressive WebGPU counts files=$AggressiveWebGpuCount hashes=$AggressiveWebGpuHashCount expected=$($RequiredScenes.Count)" "Regenerate after the trusted/aggressive WebGPU suite completes."
    } elseif ([bool]$Manifest.options.skip_smoke) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue was generated with skip_smoke=true" "Regenerate without -SkipSmoke so stock and fork runtime smoke artifacts are part of official evidence."
    } elseif ([bool]$Manifest.options.skip_navigation_lock) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue was generated with skip_navigation_lock=true" "Regenerate without -SkipNavigationLock so fork HTTP and file navigation lock artifacts are part of official evidence."
    } elseif ($RuntimeSmokeCount -ne 2 -or $RuntimeSmokeHashCount -ne 2) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue runtime smoke counts files=$RuntimeSmokeCount hashes=$RuntimeSmokeHashCount expected=2" "Regenerate after stock and fork runtime smoke JSON files are written and hashed."
    } elseif ($NavigationLockCount -ne 2 -or $NavigationLockHashCount -ne 2) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue navigation lock counts files=$NavigationLockCount hashes=$NavigationLockHashCount expected=2" "Regenerate after fork HTTP and file navigation lock smoke JSON files are written and hashed."
    } elseif (-not $RuntimeSmokeValidationOk) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue runtime smoke validation failed: $RuntimeSmokeValidationOutput" "Regenerate after stock and fork runtime smoke JSON files pass validate_smoke_result.mjs."
    } elseif (-not $NavigationLockValidationOk) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue navigation lock validation failed: $NavigationLockValidationOutput" "Regenerate after fork HTTP and file navigation lock JSON files pass validate_smoke_result.mjs."
    } elseif (-not $Manifest.artifact_metadata.inputs.baseline_browser.exists -or -not $Manifest.artifact_metadata.inputs.fork_browser.exists) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not record both browser binaries as existing" "Regenerate after stock/fork binaries exist."
    } elseif (-not $Manifest.artifact_metadata.inputs.baseline_build_args.sha256 -or -not $Manifest.artifact_metadata.inputs.fork_build_args.sha256) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not record build-args hashes" "Regenerate after stock/fork args.gn files exist."
    } elseif (-not $BaselinePackageOk -or -not $ForkPackageOk) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue package_dir is set but package metadata is missing or empty" "Regenerate after staging requested packages with scripts/stage_viewer_package.ps1."
    } elseif (-not $Manifest.artifact_metadata.reports.official_webgl2_comparison.exists -or -not $Manifest.artifact_metadata.reports.official_webgl2_comparison.sha256) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not record the official WebGL2 comparison report hash" "Regenerate after official-webgl2-comparison.md is written."
    } elseif ($Manifest.options.include_webgpu -and (-not $Manifest.artifact_metadata.reports.official_webgpu_comparison.exists -or -not $Manifest.artifact_metadata.reports.official_webgpu_comparison.sha256)) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not record the official WebGPU comparison report hash" "Regenerate after official-webgpu-comparison.md is written."
    } elseif ($Manifest.options.capture_trace -and (-not $Manifest.artifact_metadata.traces.baseline.exists -or -not $Manifest.artifact_metadata.traces.baseline.sha256 -or -not $Manifest.artifact_metadata.traces.fork.exists -or -not $Manifest.artifact_metadata.traces.fork.sha256)) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not record both official trace hashes" "Regenerate after stock/fork trace capture completes."
    } elseif ($Manifest.options.capture_trace -and -not $TraceFileValidationOk) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue raw trace validation failed: $TraceFileValidationOutput" "Regenerate stock/fork trace captures so raw trace files are parseable Chrome traces with events."
    } elseif ($Manifest.options.capture_trace -and -not $HasTraceSidecarHashes) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not record both official trace benchmark sidecar hashes" "Regenerate after stock/fork trace capture writes .result.json sidecars."
    } elseif ($Manifest.options.capture_trace -and -not $TraceSidecarValidationOk) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue trace benchmark sidecar validation failed: $TraceSidecarValidationOutput" "Regenerate stock/fork trace captures so sidecars match the manifest browser, scene, renderer, duration, warmup, start delay, and launch flag metadata."
    } elseif ($Manifest.options.capture_trace -and -not $HasTraceSummaryHashes) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue does not record both official trace summary report hashes" "Regenerate after stock/fork trace summaries are written."
    } elseif ($OfficialInvalidFiles.Count -gt 0) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue has artifact metadata whose path/hash does not match files on disk: $($OfficialInvalidFiles -join ', ')" "Regenerate the official comparison from actual stock/fork binaries, args, result JSON, runtime smoke, navigation lock, trace, and report files."
    } elseif ($OfficialInvalidDirectories.Count -gt 0) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue has package metadata whose path/count/size does not match disk: $($OfficialInvalidDirectories -join ', ')" "Regenerate after staging requested packages with scripts/stage_viewer_package.ps1."
    } elseif ($OfficialInvalidPackageExecutables.Count -gt 0) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue has package executable hash that does not match the manifest browser: $($OfficialInvalidPackageExecutables -join ', ')" "Regenerate after staging stock and fork packages from the same browser binaries used for the official comparison."
    } elseif ($OfficialReportContentIssues.Count -gt 0) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue report content validation failed: $($OfficialReportContentIssues -join '; ')" "Regenerate official comparison reports with compare_results.mjs --strictOfficial and trace summaries with summarize_trace.mjs from the exact official stock/fork artifacts."
    } elseif (-not $OfficialSuiteValidation.Ok) {
      Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue suite validation failed: $($OfficialSuiteValidation.Output)" "Regenerate after every exact official result JSON file in the manifest passes validate_benchmark_suite.mjs with checkout, build-args, revision, GPU, package-size, duration/warmup, and viewer flag metadata checks."
    } else {
      Add-AuditRow "Official performance" "Official comparison manifest" "done" "$PathValue records exact stock/fork WebGL2 files, optional WebGPU/default-aggressive files, runtime/navigation smoke hashes, result/report hashes with comparison and trace-summary content validation, browser hashes, build-args hashes, viewer patch hash, package metadata with executable hashes matched to browsers when requested, artifact paths/hashes verified on disk, benchmark suites semantically validated against exact manifest files, validated trace hashes plus trace benchmark sidecars with launch metadata, expected fork revision, pin-refresh provenance, and full suite-validation settings" "Keep with the official reports and raw JSON artifacts."
    }
  } catch {
    Add-AuditRow "Official performance" "Official comparison manifest" "pending" "$PathValue is invalid JSON or could not be audited: $($_.Exception.Message)" "Regenerate after official comparison."
  }
}

function Add-OfficialRequiredOptionsRow {
  $PathValue = Get-OfficialComparisonManifestPathValue
  if (-not (Test-RepoPath $PathValue)) {
    Add-AuditRow "Official performance" "Official comparison required options" "pending" "$PathValue missing" "Run the completion-oriented official comparison with WebGPU, aggressive GPU, -AggressiveAngleBackend d3d11, trace capture, and staged package directories."
    return
  }

  try {
    $Manifest = Get-Content (Resolve-RepoPath $PathValue) -Raw | ConvertFrom-Json
    $Missing = @()
    if (-not [bool]$Manifest.options.include_webgpu) {
      $Missing += "include_webgpu"
    }
    if (-not [bool]$Manifest.options.include_aggressive_gpu) {
      $Missing += "include_aggressive_gpu"
    }
    if (-not [string]$Manifest.options.aggressive_angle_backend) {
      $Missing += "aggressive_angle_backend"
    }
    if (-not [bool]$Manifest.options.capture_trace) {
      $Missing += "capture_trace"
    }
    if (-not [string]$Manifest.package_dirs.baseline) {
      $Missing += "baseline_package_dir"
    }
    if (-not [string]$Manifest.package_dirs.fork) {
      $Missing += "fork_package_dir"
    }

    if ($Missing.Count -eq 0) {
      Add-AuditRow "Official performance" "Official comparison required options" "done" "$PathValue records WebGPU, aggressive GPU, aggressive ANGLE backend, trace capture, baseline package dir, and fork package dir" "Keep the official manifest aligned with the completion-oriented post-ATL command."
    } else {
      Add-AuditRow "Official performance" "Official comparison required options" "pending" "$PathValue missing required option evidence: $($Missing -join ', ')" "Regenerate with -IncludeWebGPU -IncludeAggressiveGpu -AggressiveAngleBackend d3d11 -CaptureTrace -BaselinePackageDir and -ForkPackageDir."
    }
  } catch {
    Add-AuditRow "Official performance" "Official comparison required options" "pending" "$PathValue is invalid JSON" "Regenerate after official comparison."
  }
}

function Add-SceneDefinitionRows {
  $SceneSource = Resolve-RepoPath "viewer\src\scenes.js"
  $Text = if (Test-Path $SceneSource) { Get-Content $SceneSource -Raw } else { "" }
  foreach ($Scene in $RequiredScenes) {
    if ($Text -match [regex]::Escape($Scene)) {
      Add-AuditRow "Benchmark scenes" "Scene definition: $Scene" "done" "viewer/src/scenes.js contains $Scene" "Run stock/fork suites after Chromium binaries exist."
    } else {
      Add-AuditRow "Benchmark scenes" "Scene definition: $Scene" "missing" "viewer/src/scenes.js does not contain $Scene" "Implement scene before official benchmarking."
    }
  }
}

function Add-SceneCoverageConsistencyRow {
  $SceneCoverageTest = "scripts\test_scene_coverage_consistency.ps1"
  if (Test-RepoPath $SceneCoverageTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SceneCoverageTest) *>&1) -join " "
      Add-AuditRow "Benchmark scenes" "Scene coverage consistency regression test" "done" "$SceneCoverageTest passes; $OutputText" "Re-run after changing viewer scenes, benchmark runners, validators, artifact audit scene requirements, or scene coverage docs."
    } catch {
      Add-AuditRow "Benchmark scenes" "Scene coverage consistency regression test" "pending" "$SceneCoverageTest failed: $($_.Exception.Message)" "Keep the required scene suite synchronized across viewer, runners, validators, audit, and docs."
    }
  } else {
    Add-AuditRow "Benchmark scenes" "Scene coverage consistency regression test" "missing" "$SceneCoverageTest missing" "Restore the scene coverage consistency regression test."
  }
}

function Get-ChromiumRevision {
  $Src = Resolve-RepoPath "src"
  if (-not (Test-Path $Src)) {
    return ""
  }
  $Revision = (& git -C $Src rev-parse HEAD 2>$null)
  if ($LASTEXITCODE -ne 0) {
    return ""
  }
  return ($Revision | Select-Object -First 1).Trim()
}

function Get-ShortSha256 {
  param([string]$PathValue)
  if (-not (Test-Path $PathValue)) {
    return ""
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.Substring(0, 12).ToLowerInvariant()
}

function Get-ExpectedViewerForkRevision {
  $PatchPath = Resolve-RepoPath "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
  $PatchHash = Get-ShortSha256 $PatchPath
  if (-not $PatchHash) {
    return ""
  }
  return "$ExpectedChromiumRevision+viewerpatch-$PatchHash"
}

function Invoke-GitApplyCheck {
  param(
    [string]$PatchPath,
    [switch]$Reverse
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Args = @("-C", (Resolve-RepoPath "src"), "apply")
    if ($Reverse) {
      $Args += "--reverse"
    }
    $Args += @("--check", $PatchPath)
    $OutputText = (& git @Args 2>&1)
    return [pscustomobject]@{
      Ok = ($LASTEXITCODE -eq 0)
      Output = ($OutputText -join " ")
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Add-ChromiumRows {
  $Revision = Get-ChromiumRevision
  if ($Revision -eq $ExpectedChromiumRevision) {
    Add-AuditRow "Build" "Pinned Chromium revision" "done" "src HEAD=$Revision" "Refresh only if the target revision is intentionally changed."
  } elseif ($Revision) {
    Add-AuditRow "Build" "Pinned Chromium revision" "blocked" "src HEAD=$Revision expected=$ExpectedChromiumRevision" "Re-sync or update all baseline/fork evidence to the same revision."
  } else {
    Add-AuditRow "Build" "Pinned Chromium revision" "missing" "src revision unavailable" "Run bootstrap/sync."
  }

  $EnvManifestPath = Resolve-RepoPath $EnvironmentManifest
  if (Test-Path $EnvManifestPath) {
    try {
      $EnvManifest = Get-Content $EnvManifestPath -Raw | ConvertFrom-Json
      $PinRefresh = $EnvManifest.chromium.pin_refresh
      $PinWasSelectedFromUpstreamHead = (
        $null -ne $PinRefresh -and
        $PinRefresh.exists -eq $true -and
        $PinRefresh.selected_from_upstream_head -eq $true -and
        $PinRefresh.target_revision -eq $ExpectedChromiumRevision
      )
      if ($PinWasSelectedFromUpstreamHead) {
        Add-AuditRow "Build" "Chromium pin refresh provenance" "done" "benchmarks\reports\chromium-pin-refresh.json target=$($PinRefresh.target_revision) source=$($PinRefresh.source) selected_at=$($PinRefresh.selected_at)" "Keep this provenance artifact with the benchmark artifacts for the stock/fork comparison cycle."
      } elseif ($null -ne $PinRefresh -and $PinRefresh.exists -eq $true -and $PinRefresh.target_revision -eq $ExpectedChromiumRevision) {
        Add-AuditRow "Build" "Chromium pin refresh provenance" "pending" "benchmarks\reports\chromium-pin-refresh.json target=$($PinRefresh.target_revision) source=$($PinRefresh.source) selected_from_upstream_head=$($PinRefresh.selected_from_upstream_head)" "Refresh from upstream HEAD before final stock/fork evidence, or document why an explicit revision was selected."
      } elseif ($null -ne $PinRefresh -and $PinRefresh.exists -eq $true) {
        Add-AuditRow "Build" "Chromium pin refresh provenance" "pending" "benchmarks\reports\chromium-pin-refresh.json target=$($PinRefresh.target_revision) expected=$ExpectedChromiumRevision" "Run scripts/refresh_chromium_pin.ps1 so the provenance artifact matches the active pin."
      } else {
        Add-AuditRow "Build" "Chromium pin refresh provenance" "pending" "benchmarks\reports\chromium-pin-refresh.json missing or not embedded in $EnvironmentManifest" "Run scripts/refresh_chromium_pin.ps1 before final stock/fork evidence."
      }
      if ($EnvManifest.chromium.upstream_head_revision) {
        if ($EnvManifest.chromium.upstream_head_matches_expected -eq $true) {
          Add-AuditRow "Build" "Observed upstream Chromium HEAD freshness" "done" "pin matches observed upstream HEAD $($EnvManifest.chromium.upstream_head_revision) checked at $($EnvManifest.chromium.upstream_head_checked_at)" "Keep the pin fixed for the full stock/fork build and benchmark cycle."
        } elseif ($PinWasSelectedFromUpstreamHead) {
          $OfficialAfterRefresh = Test-OfficialComparisonAfterPinRefresh $PinRefresh
          if ($OfficialAfterRefresh.Ok) {
            Add-AuditRow "Build" "Observed upstream Chromium HEAD freshness" "done" "pin=$ExpectedChromiumRevision was selected from upstream HEAD at $($PinRefresh.selected_at); later observed_upstream_head=$($EnvManifest.chromium.upstream_head_revision) checked at $($EnvManifest.chromium.upstream_head_checked_at); $($OfficialAfterRefresh.Output)" "Keep the refreshed pin fixed with the completed official stock/fork evidence for this revision."
          } else {
            Add-AuditRow "Build" "Observed upstream Chromium HEAD freshness" "pending" "pin=$ExpectedChromiumRevision was selected from upstream HEAD at $($PinRefresh.selected_at), but later observed_upstream_head=$($EnvManifest.chromium.upstream_head_revision) checked at $($EnvManifest.chromium.upstream_head_checked_at) before completed official stock/fork evidence exists: $($OfficialAfterRefresh.Output)" "Run scripts/run_post_atl_pipeline.ps1 -RefreshChromiumPin immediately before the stock/fork build and benchmark cycle, then keep that refreshed revision fixed for all official evidence."
          }
        } else {
          Add-AuditRow "Build" "Observed upstream Chromium HEAD freshness" "pending" "pin=$ExpectedChromiumRevision observed_upstream_head=$($EnvManifest.chromium.upstream_head_revision) checked at $($EnvManifest.chromium.upstream_head_checked_at)" "Run scripts/run_post_atl_pipeline.ps1 -RefreshChromiumPin before the stock/fork build cycle, then keep that refreshed revision fixed for all official evidence."
        }
      } elseif ($PinWasSelectedFromUpstreamHead) {
        $OfficialAfterRefresh = Test-OfficialComparisonAfterPinRefresh $PinRefresh
        if ($OfficialAfterRefresh.Ok) {
          Add-AuditRow "Build" "Observed upstream Chromium HEAD freshness" "done" "pin=$ExpectedChromiumRevision was selected from upstream HEAD at $($PinRefresh.selected_at); current upstream HEAD probe was unavailable; $($OfficialAfterRefresh.Output)" "Keep the refreshed pin fixed with the completed official stock/fork evidence for this revision."
        } else {
          Add-AuditRow "Build" "Observed upstream Chromium HEAD freshness" "pending" "pin=$ExpectedChromiumRevision was selected from upstream HEAD at $($PinRefresh.selected_at), but current upstream HEAD probe was unavailable before completed official stock/fork evidence exists: $($OfficialAfterRefresh.Output)" "Run scripts/run_post_atl_pipeline.ps1 -RefreshChromiumPin immediately before the stock/fork build and benchmark cycle, then keep that refreshed revision fixed for all official evidence."
        }
      } else {
        Add-AuditRow "Build" "Observed upstream Chromium HEAD freshness" "pending" "$EnvManifestPath does not record upstream Chromium HEAD" "Regenerate with scripts/write_environment_manifest.ps1 or run scripts/refresh_chromium_pin.ps1."
      }
      $AtlCheck = @($EnvManifest.checks | Where-Object { $_.name -eq "visual_studio_atl" } | Select-Object -First 1)
      $AtlComponentCheck = @($EnvManifest.checks | Where-Object { $_.name -eq "visual_studio_atl_component" } | Select-Object -First 1)
      $NavigationExternalCheck = @($EnvManifest.checks | Where-Object { $_.name -eq "navigation_external_ipv4" } | Select-Object -First 1)
      if ($AtlCheck.Count -gt 0 -and $AtlCheck[0].ok) {
        $AtlEvidence = $AtlCheck[0].detail
        if ($AtlComponentCheck.Count -gt 0) {
          $AtlEvidence = "$AtlEvidence; $($AtlComponentCheck[0].detail)"
        }
        Add-AuditRow "Build" "Host prerequisite: Visual Studio ATL/MFC" "done" $AtlEvidence "Keep prebuild-environment.json current after toolchain changes."
      } elseif ($AtlCheck.Count -gt 0) {
        $AtlEvidence = $AtlCheck[0].detail
        if ($AtlComponentCheck.Count -gt 0) {
          $AtlEvidence = "$AtlEvidence; $($AtlComponentCheck[0].detail)"
        }
        $LatestFailure = @(
          $EnvManifest.build_failures |
            Where-Object {
              @($_.failed_targets | Where-Object { $_ }).Count -gt 0 -and
                $_.failure_logs_stale_after_gn_gen -ne $true
            } |
            Select-Object -First 1
        )
        if ($LatestFailure.Count -gt 0) {
          $FailedTargets = @($LatestFailure[0].failed_targets) -join ", "
          $FatalError = $LatestFailure[0].first_fatal_error
          if ($FatalError) {
            $AtlEvidence = "$AtlEvidence; latest $($LatestFailure[0].out_dir) failure: $FailedTargets; $FatalError"
          } else {
            $AtlEvidence = "$AtlEvidence; latest $($LatestFailure[0].out_dir) failure: $FailedTargets"
          }
        } else {
          $StaleFailure = @(
            $EnvManifest.build_failures |
              Where-Object {
                @($_.failed_targets | Where-Object { $_ }).Count -gt 0 -and
                  $_.failure_logs_stale_after_gn_gen -eq $true
              } |
              Select-Object -First 1
          )
          if ($StaleFailure.Count -gt 0) {
            $AtlEvidence = "$AtlEvidence; prior $($StaleFailure[0].out_dir) failure logs are older than latest GN generation"
          }
        }
        Add-AuditRow "Build" "Host prerequisite: Visual Studio ATL/MFC" "blocked" $AtlEvidence "Install Microsoft.VisualStudio.Component.VC.ATLMFC from elevated PowerShell, then rerun scripts/verify_prebuild.ps1."
      } else {
        Add-AuditRow "Build" "Host prerequisite: Visual Studio ATL/MFC" "pending" "$EnvManifestPath has no visual_studio_atl check" "Regenerate with scripts/write_environment_manifest.ps1."
      }

      if ($NavigationExternalCheck.Count -gt 0 -and $NavigationExternalCheck[0].ok) {
        Add-AuditRow "Runtime tests" "Host prerequisite: external navigation test interface" "done" $NavigationExternalCheck[0].detail "Keep this current before running fork navigation-lock smoke; it needs a non-loopback IPv4 interface."
      } elseif ($NavigationExternalCheck.Count -gt 0) {
        Add-AuditRow "Runtime tests" "Host prerequisite: external navigation test interface" "blocked" $NavigationExternalCheck[0].detail "Connect or enable a non-loopback IPv4 interface before running scripts/run_navigation_lock_tests.mjs."
      } else {
        Add-AuditRow "Runtime tests" "Host prerequisite: external navigation test interface" "pending" "$EnvManifestPath has no navigation_external_ipv4 check" "Regenerate with scripts/write_environment_manifest.ps1."
      }
    } catch {
      Add-AuditRow "Build" "Host prerequisite: Visual Studio ATL/MFC" "pending" "$EnvManifestPath is invalid JSON" "Regenerate with scripts/write_environment_manifest.ps1."
      Add-AuditRow "Runtime tests" "Host prerequisite: external navigation test interface" "pending" "$EnvManifestPath is invalid JSON" "Regenerate with scripts/write_environment_manifest.ps1."
    }
  } else {
    Add-AuditRow "Build" "Host prerequisite: Visual Studio ATL/MFC" "pending" "$EnvManifestPath missing" "Run scripts/verify_prebuild.ps1 or scripts/write_environment_manifest.ps1."
    Add-AuditRow "Runtime tests" "Host prerequisite: external navigation test interface" "pending" "$EnvManifestPath missing" "Run scripts/verify_prebuild.ps1 or scripts/write_environment_manifest.ps1."
  }

  Add-FileRow "Build" "Reproducible GN arg files" @(
    "build\gn_args\baseline_content_shell.gn",
    "build\gn_args\fork_safe_content_shell.gn",
    "build\gn_args\fork_trusted_aggressive.gn"
  ) "Keep these in sync with build docs."

  $GnArgsProfileTest = "scripts\test_gn_args_profiles.ps1"
  if (Test-RepoPath $GnArgsProfileTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $GnArgsProfileTest) *>&1) -join " "
      Add-AuditRow "Build" "GN args profile policy regression test" "done" "$GnArgsProfileTest passes; $OutputText" "Re-run after changing GN args templates or build-profile policy."
    } catch {
      Add-AuditRow "Build" "GN args profile policy regression test" "pending" "$GnArgsProfileTest failed: $($_.Exception.Message)" "Keep baseline/fork GN args in comparable release mode and keep unsafe viewer experiments out of GN templates."
    }
  } else {
    Add-AuditRow "Build" "GN args profile policy regression test" "missing" "$GnArgsProfileTest missing" "Restore the GN args profile policy regression test."
  }

  Add-GnArgsMatchRow "Generated baseline args.gn matches template" "src\out\ReleaseBaseline\args.gn" "build\gn_args\baseline_content_shell.gn" "Run gn gen through scripts/build_chromium.ps1 after ATL is installed."
  Add-GnArgsMatchRow "Generated fork default args.gn matches template" "src\out\ReleaseViewerDefault\args.gn" "build\gn_args\fork_safe_content_shell.gn" "Run scripts/build_chromium.ps1 -GenOnly to refresh GN metadata, then scripts/build_viewer_fork.ps1 after ATL is installed."
  Add-GnArgsMatchRow "Generated fork trusted/aggressive args.gn matches template" "src\out\ReleaseViewerTrustedAggressive\args.gn" "build\gn_args\fork_trusted_aggressive.gn" "Run scripts/build_chromium.ps1 -GenOnly to refresh trusted/aggressive GN metadata; runtime trusted flags still require the built fork binary."
  Add-BinaryFileRow "Build" "Stock baseline content_shell binary" "src\out\ReleaseBaseline\content_shell.exe" "Build stock content_shell from the pinned revision."
  Add-BinaryFileRow "Build" "Fork default content_shell binary" "src\out\ReleaseViewerDefault\content_shell.exe" "Apply viewer patch after baseline capture and build fork output."
}

function Add-PatchRows {
  $PatchPath = Resolve-RepoPath "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
  if (-not (Test-Path $PatchPath)) {
    Add-AuditRow "Fork patch" "Minimal viewer entrypoint patch file" "missing" "Patch file missing" "Create patch."
    return
  }

  if ($TestAssumeViewerPatchAlreadyApplied) {
    $ApplyCheck = [pscustomobject]@{ Ok = $false; Output = "test hook: viewer patch assumed already applied" }
  } else {
    $ApplyCheck = Invoke-GitApplyCheck $PatchPath
  }
  if ($ApplyCheck.Ok) {
    Add-AuditRow "Fork patch" "Minimal viewer entrypoint patch applies or is already applied" "done" "git apply --check succeeds" "Build and runtime-test the patched fork after baseline is built."
  } else {
    if ($TestAssumeViewerPatchAlreadyApplied) {
      $ReverseCheck = [pscustomobject]@{ Ok = $true; Output = "test hook: viewer patch assumed already applied" }
    } else {
      $ReverseCheck = Invoke-GitApplyCheck $PatchPath -Reverse
    }
    if ($ReverseCheck.Ok) {
      Add-AuditRow "Fork patch" "Minimal viewer entrypoint patch applies or is already applied" "done" "git apply --reverse --check succeeds; patch is already applied" "Continue fork build/benchmark work, or reset only after preserving fork evidence."
    } else {
      Add-AuditRow "Fork patch" "Minimal viewer entrypoint patch applies or is already applied" "blocked" "$($ApplyCheck.Output) $($ReverseCheck.Output)" "Refresh patch against current Chromium checkout."
    }
  }

  Add-PatchNotesRow

  $PatchNotesTest = "scripts\test_patch_notes_consistency.ps1"
  if (Test-RepoPath $PatchNotesTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $PatchNotesTest) *>&1) -join " "
      Add-AuditRow "Fork patch" "Patch notes consistency regression test" "done" "$PatchNotesTest passes; $OutputText" "Re-run after changing the draft patch, patch notes, or trusted-content flag docs."
    } catch {
      Add-AuditRow "Fork patch" "Patch notes consistency regression test" "pending" "$PatchNotesTest failed: $($_.Exception.Message)" "Keep patch notes synchronized with patch source files, viewer switches, behavior notes, and patch policy."
    }
  } else {
    Add-AuditRow "Fork patch" "Patch notes consistency regression test" "missing" "$PatchNotesTest missing" "Restore the patch notes consistency regression test."
  }

  $PatchNotesCompletionTest = "scripts\test_patch_notes_completion_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_PATCH_NOTES_COMPLETION_AUDIT_TEST) {
    Add-AuditRow "Fork patch" "Patch notes completion audit regression test" "done" "$PatchNotesCompletionTest skipped for self-test recursion guard" "Re-run after changing patch notes final-evidence gating."
  } elseif (Test-RepoPath $PatchNotesCompletionTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $PatchNotesCompletionTest) *>&1) -join " "
      Add-AuditRow "Fork patch" "Patch notes completion audit regression test" "done" "$PatchNotesCompletionTest passes; $OutputText" "Re-run after changing patch notes final-evidence gating."
    } catch {
      Add-AuditRow "Fork patch" "Patch notes completion audit regression test" "pending" "$PatchNotesCompletionTest failed: $($_.Exception.Message)" "Ensure patch notes remain pending while they are draft-only or official/trusted evidence is missing."
    }
  } else {
    Add-AuditRow "Fork patch" "Patch notes completion audit regression test" "missing" "$PatchNotesCompletionTest missing" "Restore the patch notes final-evidence regression test."
  }
}

function Add-PatchNotesRow {
  $ReadmePath = "chromium_patches\README.md"
  $NotesPath = "chromium_patches\minimal_viewer_entrypoint.md"
  $Missing = @(@($ReadmePath, $NotesPath) | Where-Object { -not (Test-RepoPath $_) })
  if ($Missing.Count -gt 0) {
    Add-AuditRow "Fork patch" "Patch notes" "missing" "Missing: $($Missing -join ', ')" "Restore patch notes for the fork patch series."
    return
  }

  $Readme = Get-Content -LiteralPath (Resolve-RepoPath $ReadmePath) -Raw
  $Notes = Get-Content -LiteralPath (Resolve-RepoPath $NotesPath) -Raw
  $Combined = "$Readme`n$Notes"
  $RequiredTerms = @(
    "content/shell/app/shell_main_delegate.cc",
    "content/shell/browser/shell.cc",
    "content/shell/browser/shell_browser_main_parts.cc",
    "content/shell/browser/shell_content_browser_client.cc",
    "content/shell/common/shell_switches.h",
    "--viewer-app-url",
    "--viewer-trusted-content",
    "--viewer-block-external-navigation",
    "--viewer-force-angle-backend",
    "--viewer-aggressive-gpu",
    "--viewer-in-process-gpu",
    "--viewer-single-process",
    "--viewer-relaxed-webgl-validation",
    "docs/removed_subsystems.md",
    "docs/optimization_log.md"
  )
  $MissingTerms = @($RequiredTerms | Where-Object { -not $Combined.Contains($_) })
  if ($MissingTerms.Count -gt 0) {
    Add-AuditRow "Fork patch" "Patch notes" "pending" "Patch notes exist but are missing required patch-series terms: $($MissingTerms -join ', ')" "Document touched source files, viewer switches, unsafe-gate policy, removed-subsystem log, and optimization-log handoff."
    return
  }

  $DraftPatterns = @(
    "Current draft patch",
    "Status: draft",
    "draft patch created",
    "not applied yet",
    "Does not yet implement",
    "does not yet implement",
    "remain separate experiments",
    "Update after measured fork runs"
  )
  $DraftMatches = @($DraftPatterns | Where-Object { $Combined -match [regex]::Escape($_) })
  $EvidenceGaps = [System.Collections.Generic.List[string]]::new()
  if (-not (Test-RepoPath (Get-OfficialComparisonManifestPathValue))) {
    $EvidenceGaps.Add("official comparison manifest missing") | Out-Null
  }
  if (-not (Test-RepoPath (Get-TrustedMatrixManifestPathValue))) {
    $EvidenceGaps.Add("trusted experiment matrix manifest missing") | Out-Null
  }
  if ($DraftMatches.Count -gt 0) {
    $EvidenceGaps.Add("draft-only language present: $($DraftMatches -join ', ')") | Out-Null
  }

  if ($EvidenceGaps.Count -gt 0) {
    Add-AuditRow "Fork patch" "Patch notes" "pending" "$ReadmePath and $NotesPath exist and cover the draft patch surface, but final patch-series evidence is incomplete: $($EvidenceGaps -join '; ')" "After stock/fork and trusted measurements complete, replace draft notes with final patch-series notes including measured evidence, final kept/rejected gates, and remaining patch limitations."
    return
  }

  Add-AuditRow "Fork patch" "Patch notes" "done" "$ReadmePath and $NotesPath document touched source files, viewer switches, unsafe-gate policy, removed-subsystem log, optimization-log handoff, and completed official/trusted evidence without draft-only language" "Keep patch notes synchronized with future rebases and measured experiment decisions."
}

function Add-PrebuildEnvironmentManifestRow {
  $EnvManifest = $EnvironmentManifest
  if (Test-JsonOk $EnvManifest) {
    $Manifest = Get-Content (Resolve-RepoPath $EnvManifest) -Raw | ConvertFrom-Json
    if ($Manifest.chromium.actual_revision -eq $ExpectedChromiumRevision -and ($Manifest.patch.applies_cleanly -or $Manifest.patch.already_applied)) {
      $PatchState = if ($Manifest.patch.applies_cleanly) { "clean-applying viewer patch" } else { "already-applied viewer patch" }
      $UpstreamEvidence = if ($Manifest.chromium.upstream_head_revision) { "upstream HEAD observed=$($Manifest.chromium.upstream_head_revision) matches_pin=$($Manifest.chromium.upstream_head_matches_expected)" } else { "upstream HEAD not observed" }
      $FailureEvidenceParts = @()
      foreach ($Failure in @($Manifest.build_failures)) {
        if (@($Failure.failed_targets | Where-Object { $_ }).Count -eq 0) {
          continue
        }
        if ($Failure.failure_logs_stale_after_gn_gen -eq $true) {
          $FailureEvidenceParts += "$($Failure.out_dir) stale failure logs"
        } elseif ($Failure.failure_logs_current_for_generated_build -eq $true) {
          $FailureEvidenceParts += "$($Failure.out_dir) current failure logs"
        } else {
          $FailureEvidenceParts += "$($Failure.out_dir) undated failure logs"
        }
      }
      $FailureEvidence = if ($FailureEvidenceParts.Count -gt 0) {
        "build-failure evidence: $($FailureEvidenceParts -join ', ')"
      } else {
        "no Siso failure logs recorded"
      }
      Add-AuditRow "Automation" "Prebuild environment manifest" "done" "$EnvManifest records pinned revision, $UpstreamEvidence, $PatchState, and $FailureEvidence" "ATL/MFC may still be recorded as a failing host prerequisite until installed."
    } else {
      Add-AuditRow "Automation" "Prebuild environment manifest" "pending" "$EnvManifest exists but does not record the expected revision and patch state" "Regenerate with scripts/write_environment_manifest.ps1."
    }
  } else {
    Add-AuditRow "Automation" "Prebuild environment manifest" "pending" "$EnvManifest missing or invalid" "Run scripts/write_environment_manifest.ps1 or scripts/verify_prebuild.ps1."
  }
}

function Add-ViewerRows {
  Add-FileRow "Viewer app" "Bundled Three.js viewer source and build output" @(
    "viewer\package.json",
    "viewer\src\main.js",
    "viewer\src\metrics.js",
    "viewer\src\scenes.js",
    "viewer\dist\index.html"
  ) "Run npm build after source changes."

  $ViewerBundleTest = "scripts\test_viewer_bundle_integrity.ps1"
  if (Test-RepoPath $ViewerBundleTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $ViewerBundleTest) *>&1) -join " "
      Add-AuditRow "Viewer app" "Viewer bundle integrity regression test" "done" "$ViewerBundleTest passes; $OutputText" "Re-run after changing viewer package config, dist output, or bundled assets."
    } catch {
      Add-AuditRow "Viewer app" "Viewer bundle integrity regression test" "pending" "$ViewerBundleTest failed: $($_.Exception.Message)" "Ensure the viewer bundle uses local-only dist asset references and includes required packaged scene assets."
    }
  } else {
    Add-AuditRow "Viewer app" "Viewer bundle integrity regression test" "missing" "$ViewerBundleTest missing" "Restore local bundle integrity coverage."
  }

  Add-SceneDefinitionRows
  Add-SceneCoverageConsistencyRow
}

function Add-ScriptRows {
  Add-FileRow "Automation" "Build and fork scripts" @(
    "scripts\bootstrap_chromium.ps1",
    "scripts\build_chromium.ps1",
    "scripts\build_viewer_fork.ps1",
    "scripts\check_prereqs.ps1",
    "scripts\inspect_chromium_target.ps1",
    "scripts\install_vs_atl.ps1",
    "scripts\refresh_chromium_pin.ps1",
    "scripts\run_post_atl_pipeline.ps1",
    "scripts\test_atl_blocker_audit.ps1",
    "scripts\test_atl_remediation_handoff.ps1",
    "scripts\test_audit_manifest_override_guard.ps1",
    "scripts\test_benchmark_flag_metadata.ps1",
    "scripts\test_binary_audit_rows.ps1",
    "scripts\test_build_args_guard.ps1",
    "scripts\test_chromium_scope_guard.ps1",
    "scripts\test_documentation_structure.ps1",
    "scripts\test_documentation_completion_audit.ps1",
    "scripts\test_dry_run_manifests.ps1",
    "scripts\test_environment_manifest_coverage.ps1",
    "scripts\test_gn_args_profiles.ps1",
    "scripts\test_gn_gen_only.ps1",
    "scripts\test_hardware_gpu_launch_flags.ps1",
    "scripts\test_official_manifest_runtime_audit.ps1",
    "scripts\test_official_manifest_suite_semantics_audit.ps1",
    "scripts\test_official_manifest_trace_audit.ps1",
    "scripts\test_official_manifest_webgpu_audit.ps1",
    "scripts\test_official_manifest_required_options_audit.ps1",
    "scripts\test_optimization_decision_audit.ps1",
    "scripts\test_optimization_tracking.ps1",
    "scripts\test_patch_notes_completion_audit.ps1",
    "scripts\test_patch_notes_consistency.ps1",
    "scripts\test_performance_claim_guard.ps1",
    "scripts\test_post_atl_pipeline_dry_run.ps1",
    "scripts\test_patch_state_audit.ps1",
    "scripts\test_refresh_chromium_pin_dry_run.ps1",
    "scripts\test_reproduction_handoff_audit.ps1",
    "scripts\test_removed_subsystems_completion_audit.ps1",
    "scripts\test_removed_subsystems_register.ps1",
    "scripts\test_report_metric_coverage.ps1",
    "scripts\test_revision_validation.ps1",
    "scripts\test_scene_coverage_consistency.ps1",
    "scripts\test_smoke_detail_validation.ps1",
    "scripts\test_smoke_coverage.ps1",
    "scripts\test_stability_result_thresholds.ps1",
    "scripts\test_source_investigation_paths.ps1",
    "scripts\test_source_investigation_revision_guard.ps1",
    "scripts\test_strict_official_rejects_software_rendering.ps1",
    "scripts\test_trusted_manifest_flag_audit.ps1",
    "scripts\test_trusted_manifest_provenance_audit.ps1",
    "scripts\test_trusted_manifest_required_options_audit.ps1",
    "scripts\test_trusted_manifest_suite_semantics_audit.ps1",
    "scripts\test_trusted_content_flags_doc.ps1",
    "scripts\test_upstream_freshness_audit.ps1",
    "scripts\test_verify_prebuild_manifest_gate.ps1",
    "scripts\test_viewer_bundle_integrity.ps1",
    "scripts\test_viewer_patch_entrypoint.ps1",
    "scripts\test_viewer_patch_navigation_lock.ps1",
    "scripts\test_viewer_patch_stdout_result.ps1",
    "scripts\test_viewer_patch_trusted_gates.ps1",
    "scripts\test_viewer_runtime_surface.ps1",
    "scripts\verify_prebuild.ps1",
    "scripts\write_environment_manifest.ps1"
  ) "Run from a shell with the required VS ATL/MFC component."
  Add-FileRow "Automation" "Benchmark and verification scripts" @(
    "scripts\run_benchmark.mjs",
    "scripts\run_full_suite.ps1",
    "scripts\run_official_comparison.ps1",
    "scripts\run_trusted_experiment_matrix.ps1",
    "scripts\run_smoke_tests.mjs",
    "scripts\run_navigation_lock_tests.mjs",
    "scripts\run_file_navigation_lock_tests.mjs",
    "scripts\run_long_stability.ps1",
    "scripts\validate_metrics.mjs",
    "scripts\validate_stability_result.mjs",
    "scripts\summarize_results.mjs",
    "scripts\compare_results.mjs",
    "scripts\run_trace_capture.mjs",
    "scripts\summarize_trace.mjs",
    "scripts\stage_viewer_package.ps1",
    "scripts\test_audit_fail_on_incomplete.ps1",
    "scripts\test_audit_official_suite_validation_gates.ps1",
    "scripts\test_benchmark_suite_duration_validation.ps1",
    "scripts\test_benchmark_suite_flag_metadata.ps1",
    "scripts\test_benchmark_suite_package_validation.ps1",
    "scripts\test_benchmark_suite_rejects_software_rendering.ps1",
    "scripts\test_revision_validation.ps1",
    "scripts\test_manifest_artifact_path_audit.ps1",
    "scripts\test_manifest_package_audit.ps1",
    "scripts\test_benchmark_metadata_enrichment.ps1",
    "scripts\test_metric_schema_consistency.ps1",
    "scripts\test_scene_coverage_consistency.ps1",
    "scripts\test_stage_viewer_package.ps1",
    "scripts\test_trace_capture_start_delay.ps1",
    "scripts\test_trace_file_validation.ps1",
    "scripts\test_trace_result_validation.ps1",
    "scripts\test_upstream_freshness_audit.ps1",
    "scripts\test_verify_prebuild_manifest_gate.ps1",
    "scripts\test_trusted_manifest_suite_semantics_audit.ps1",
    "scripts\validate_benchmark_suite.mjs",
    "scripts\validate_trace_file.mjs",
    "scripts\validate_trace_result.mjs",
    "scripts\validate_smoke_result.mjs"
  ) "Run official comparison after stock and fork binaries exist."

  $PackageStageTest = "scripts\test_stage_viewer_package.ps1"
  if (Test-RepoPath $PackageStageTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $PackageStageTest) *>&1) -join " "
      Add-AuditRow "Automation" "Viewer package staging regression test" "done" "$PackageStageTest passes; $OutputText" "Real package staging and launch still require the fork content_shell binary."
    } catch {
      Add-AuditRow "Automation" "Viewer package staging regression test" "pending" "$PackageStageTest failed: $($_.Exception.Message)" "Fix staged runtime asset copying, viewer bundle copying, cleanup, or launcher generation."
    }
  } else {
    Add-AuditRow "Automation" "Viewer package staging regression test" "missing" "$PackageStageTest missing" "Restore the package staging regression test."
  }

  $BinaryAuditRowsTest = "scripts\test_binary_audit_rows.ps1"
  if (Test-RepoPath $BinaryAuditRowsTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $BinaryAuditRowsTest) *>&1) -join " "
      Add-AuditRow "Automation" "Binary artifact audit row regression test" "done" "$BinaryAuditRowsTest passes; $OutputText" "Re-run after changing build binary audit rows."
    } catch {
      Add-AuditRow "Automation" "Binary artifact audit row regression test" "pending" "$BinaryAuditRowsTest failed: $($_.Exception.Message)" "Ensure stock/fork content_shell binary rows require non-empty files and hashes rather than existence only."
    }
  } else {
    Add-AuditRow "Automation" "Binary artifact audit row regression test" "missing" "$BinaryAuditRowsTest missing" "Restore strict binary-row audit coverage."
  }

  $ManifestPackageTest = "scripts\test_manifest_package_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST) {
    Add-AuditRow "Automation" "Manifest package metadata audit regression test" "done" "$ManifestPackageTest skipped for self-test recursion guard" "Re-run after changing official/trusted manifest package metadata checks."
  } elseif (Test-RepoPath $ManifestPackageTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $ManifestPackageTest) *>&1) -join " "
      Add-AuditRow "Automation" "Manifest package metadata audit regression test" "done" "$ManifestPackageTest passes; $OutputText" "Re-run after changing official/trusted manifest package metadata checks."
    } catch {
      Add-AuditRow "Automation" "Manifest package metadata audit regression test" "pending" "$ManifestPackageTest failed: $($_.Exception.Message)" "Ensure completed manifests cannot pass when package_dir is set but package metadata is missing or empty."
    }
  } else {
    Add-AuditRow "Automation" "Manifest package metadata audit regression test" "missing" "$ManifestPackageTest missing" "Restore the manifest package metadata regression test."
  }

  $ManifestArtifactPathTest = "scripts\test_manifest_artifact_path_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST) {
    Add-AuditRow "Automation" "Manifest artifact path/hash audit regression test" "done" "$ManifestArtifactPathTest skipped for self-test recursion guard" "Re-run after changing official/trusted manifest artifact path or hash checks."
  } elseif (Test-RepoPath $ManifestArtifactPathTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $ManifestArtifactPathTest) *>&1) -join " "
      Add-AuditRow "Automation" "Manifest artifact path/hash audit regression test" "done" "$ManifestArtifactPathTest passes; $OutputText" "Re-run after changing official/trusted manifest artifact path or hash checks."
    } catch {
      Add-AuditRow "Automation" "Manifest artifact path/hash audit regression test" "pending" "$ManifestArtifactPathTest failed: $($_.Exception.Message)" "Ensure completed manifests cannot pass when artifact metadata paths are missing on disk or hashes/sizes do not match."
    }
  } else {
    Add-AuditRow "Automation" "Manifest artifact path/hash audit regression test" "missing" "$ManifestArtifactPathTest missing" "Restore the manifest artifact path/hash regression test."
  }

  $TrustedManifestProvenanceTest = "scripts\test_trusted_manifest_provenance_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Trusted manifest provenance audit regression test" "done" "$TrustedManifestProvenanceTest skipped for self-test recursion guard" "Re-run after changing trusted experiment matrix manifest validation."
  } elseif (Test-RepoPath $TrustedManifestProvenanceTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $TrustedManifestProvenanceTest) *>&1) -join " "
      Add-AuditRow "Automation" "Trusted manifest provenance audit regression test" "done" "$TrustedManifestProvenanceTest passes; $OutputText" "Re-run after changing trusted experiment matrix manifest validation."
    } catch {
      Add-AuditRow "Automation" "Trusted manifest provenance audit regression test" "pending" "$TrustedManifestProvenanceTest failed: $($_.Exception.Message)" "Ensure completed trusted matrix manifests require completed phase, current Chromium and fork revisions, pin-refresh provenance, duration/warmup validation, suite-validation gate settings, browser/build-args hashes, result hashes, and report metadata."
    }
  } else {
    Add-AuditRow "Automation" "Trusted manifest provenance audit regression test" "missing" "$TrustedManifestProvenanceTest missing" "Restore the trusted manifest provenance audit regression test."
  }

  $TrustedManifestRequiredOptionsTest = "scripts\test_trusted_manifest_required_options_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_TRUSTED_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Trusted manifest required-options audit regression test" "done" "$TrustedManifestRequiredOptionsTest skipped for self-test recursion guard" "Re-run after changing trusted experiment matrix required-option validation."
  } elseif (Test-RepoPath $TrustedManifestRequiredOptionsTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $TrustedManifestRequiredOptionsTest) *>&1) -join " "
      Add-AuditRow "Automation" "Trusted manifest required-options audit regression test" "done" "$TrustedManifestRequiredOptionsTest passes; $OutputText" "Re-run after changing trusted experiment matrix required-option validation."
    } catch {
      Add-AuditRow "Automation" "Trusted manifest required-options audit regression test" "pending" "$TrustedManifestRequiredOptionsTest failed: $($_.Exception.Message)" "Ensure completed trusted matrix manifests require a staged package directory with matching package metadata."
    }
  } else {
    Add-AuditRow "Automation" "Trusted manifest required-options audit regression test" "missing" "$TrustedManifestRequiredOptionsTest missing" "Restore the trusted manifest required-options regression test."
  }

  $CompareText = if (Test-RepoPath "scripts\compare_results.mjs") { Get-Content (Resolve-RepoPath "scripts\compare_results.mjs") -Raw } else { "" }
  $OfficialText = if (Test-RepoPath "scripts\run_official_comparison.ps1") { Get-Content (Resolve-RepoPath "scripts\run_official_comparison.ps1") -Raw } else { "" }
  if ($CompareText -match "--strictOfficial" -and $CompareText -match "fork_revision" -and $CompareText -match "measured_seconds" -and $CompareText -match "warmup_seconds" -and $OfficialText -match "--strictOfficial") {
    Add-AuditRow "Automation" "Official comparison strict input validation" "done" "compare_results.mjs implements --strictOfficial with provenance, fork-revision, GPU, and duration/warmup consistency checks; run_official_comparison.ps1 invokes it" "Official reports still require stock/fork binaries and benchmark results."
  } else {
    Add-AuditRow "Automation" "Official comparison strict input validation" "pending" "Strict official comparison is not fully wired" "Ensure official reports reject installed-browser, mismatched-revision, missing-build-args, missing-fork-revision, missing-GPU, software-rendered, or mismatched-duration inputs."
  }

  $SuiteText = if (Test-RepoPath "scripts\validate_benchmark_suite.mjs") { Get-Content (Resolve-RepoPath "scripts\validate_benchmark_suite.mjs") -Raw } else { "" }
  if ($SuiteText -match "--requireCheckout" -and $SuiteText -match "--requireBuildArgs" -and $SuiteText -match "--expectedChromiumRevision" -and $SuiteText -match "--expectedBrowser" -and $SuiteText -match "--expectedForkRevision" -and $SuiteText -match "--rejectSoftwareRendering" -and $SuiteText -match "--requireGpuMetadata" -and $SuiteText -match "--requirePackageSize" -and $SuiteText -match "--expectedMeasuredSeconds" -and $SuiteText -match "--expectedWarmupSeconds" -and $SuiteText -match "--expectedFlagMetadata" -and $SuiteText -match "--requiredBrowserFlag" -and $OfficialText -match "validate_benchmark_suite\.mjs" -and $OfficialText -match "--expectedScenes" -and $OfficialText -match "ExpectedChromiumRevision" -and $OfficialText -match "ExpectedBrowser" -and $OfficialText -match "ExpectedForkRevision" -and $OfficialText -match "RequirePackageSize" -and $OfficialText -match "--rejectSoftwareRendering" -and $OfficialText -match "--requireGpuMetadata" -and $OfficialText -match "--expectedMeasuredSeconds" -and $OfficialText -match "--expectedWarmupSeconds" -and $OfficialText -match "ExpectedFlagMetadata" -and $OfficialText -match "RequiredBrowserFlags") {
    Add-AuditRow "Automation" "Official scene-suite validation" "done" "validate_benchmark_suite.mjs is wired into run_official_comparison.ps1 with expected scene list, expected Chromium revision, expected browser executable, expected fork-revision checks, exact scene output files, software-renderer rejection, required GPU metadata, package-size enforcement for packaged runs, expected duration/warmup checks, expected viewer-flag metadata, and required effective browser launch flags" "Official suite artifacts are still pending the stock/fork Chromium builds."
  } else {
    Add-AuditRow "Automation" "Official scene-suite validation" "pending" "Suite validation is not fully wired" "Ensure official runs reject missing scenes, duplicate scenes, wrong renderer labels, and installed-browser inputs."
  }

  $SuiteSoftwareRendererTest = "scripts\test_benchmark_suite_rejects_software_rendering.ps1"
  if (Test-RepoPath $SuiteSoftwareRendererTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SuiteSoftwareRendererTest) *>&1) -join " "
      Add-AuditRow "Automation" "Benchmark suite software-renderer rejection test" "done" "$SuiteSoftwareRendererTest passes; $OutputText" "Re-run after changing benchmark suite validation or official/trusted suite orchestration."
    } catch {
      Add-AuditRow "Automation" "Benchmark suite software-renderer rejection test" "pending" "$SuiteSoftwareRendererTest failed: $($_.Exception.Message)" "Ensure official and trusted suite validation reject known SwiftShader/WARP/llvmpipe/software-rendered inputs."
    }
  } else {
    Add-AuditRow "Automation" "Benchmark suite software-renderer rejection test" "missing" "$SuiteSoftwareRendererTest missing" "Restore the benchmark suite software-renderer regression test."
  }

  $SuiteDurationTest = "scripts\test_benchmark_suite_duration_validation.ps1"
  if (Test-RepoPath $SuiteDurationTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SuiteDurationTest) *>&1) -join " "
      Add-AuditRow "Automation" "Benchmark suite duration validation test" "done" "$SuiteDurationTest passes; $OutputText" "Re-run after changing benchmark suite validation or official/trusted duration settings."
    } catch {
      Add-AuditRow "Automation" "Benchmark suite duration validation test" "pending" "$SuiteDurationTest failed: $($_.Exception.Message)" "Ensure official and trusted suite validation reject mismatched duration or warmup values."
    }
  } else {
    Add-AuditRow "Automation" "Benchmark suite duration validation test" "missing" "$SuiteDurationTest missing" "Restore the benchmark suite duration regression test."
  }

  $SuiteFlagMetadataTest = "scripts\test_benchmark_suite_flag_metadata.ps1"
  if (Test-RepoPath $SuiteFlagMetadataTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SuiteFlagMetadataTest) *>&1) -join " "
      Add-AuditRow "Automation" "Benchmark suite flag metadata validation test" "done" "$SuiteFlagMetadataTest passes; $OutputText" "Re-run after changing trusted viewer flag metadata or suite validation."
    } catch {
      Add-AuditRow "Automation" "Benchmark suite flag metadata validation test" "pending" "$SuiteFlagMetadataTest failed: $($_.Exception.Message)" "Ensure official/trusted suite validation rejects result JSON whose viewer flag metadata does not match the intended experiment."
    }
  } else {
    Add-AuditRow "Automation" "Benchmark suite flag metadata validation test" "missing" "$SuiteFlagMetadataTest missing" "Restore the benchmark suite flag metadata regression test."
  }

  $RevisionValidationTest = "scripts\test_revision_validation.ps1"
  if (Test-RepoPath $RevisionValidationTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $RevisionValidationTest) *>&1) -join " "
      Add-AuditRow "Automation" "Benchmark/stability Chromium revision validation test" "done" "$RevisionValidationTest passes; $OutputText" "Re-run after changing suite, stability, official, trusted, or long-stability provenance validation."
    } catch {
      Add-AuditRow "Automation" "Benchmark/stability Chromium revision validation test" "pending" "$RevisionValidationTest failed: $($_.Exception.Message)" "Ensure official/trusted suites and one-hour stability results reject stale Chromium revisions."
    }
  } else {
    Add-AuditRow "Automation" "Benchmark/stability Chromium revision validation test" "missing" "$RevisionValidationTest missing" "Restore the Chromium revision validation regression test."
  }

  $SuitePackageTest = "scripts\test_benchmark_suite_package_validation.ps1"
  if (Test-RepoPath $SuitePackageTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SuitePackageTest) *>&1) -join " "
      Add-AuditRow "Automation" "Benchmark suite package-size validation test" "done" "$SuitePackageTest passes; $OutputText" "Re-run after changing benchmark suite validation or package staging evidence."
    } catch {
      Add-AuditRow "Automation" "Benchmark suite package-size validation test" "pending" "$SuitePackageTest failed: $($_.Exception.Message)" "Ensure packaged official/trusted suite validation rejects missing or non-positive package_size_mb."
    }
  } else {
    Add-AuditRow "Automation" "Benchmark suite package-size validation test" "missing" "$SuitePackageTest missing" "Restore the benchmark suite package-size regression test."
  }

  $TrustedText = if (Test-RepoPath "scripts\run_trusted_experiment_matrix.ps1") { Get-Content (Resolve-RepoPath "scripts\run_trusted_experiment_matrix.ps1") -Raw } else { "" }
  if ($TrustedText -match "validate_benchmark_suite\.mjs" -and $TrustedText -match "--expectedScenes" -and $TrustedText -match "--expectedChromiumRevision" -and $TrustedText -match "--expectedBrowser" -and $TrustedText -match "--expectedForkRevision" -and $TrustedText -match "--rejectSoftwareRendering" -and $TrustedText -match "--requireGpuMetadata" -and $TrustedText -match "--requirePackageSize" -and $TrustedText -match "--expectedMeasuredSeconds" -and $TrustedText -match "--expectedWarmupSeconds" -and $TrustedText -match "--expectedFlagMetadata" -and $TrustedText -match "--requiredBrowserFlag" -and $TrustedText -match "Get-ExperimentExpectedFlagMetadata" -and $TrustedText -match "BuildArgs is required" -and $TrustedText -match "ResultFiles") {
    Add-AuditRow "Automation" "Trusted experiment suite validation" "done" "run_trusted_experiment_matrix.ps1 validates each experiment suite with expected scenes, build args, Chromium revision, expected browser executable, fork revision, exact current-run files, software-renderer rejection, required GPU metadata, package-size enforcement for packaged runs, expected duration/warmup checks, expected trusted viewer flag metadata, and required effective browser launch flags" "Measured trusted experiment artifacts are still pending the fork build."
  } else {
    Add-AuditRow "Automation" "Trusted experiment suite validation" "pending" "Trusted experiment matrix does not fully validate per-experiment suites" "Wire validate_benchmark_suite.mjs into trusted experiment reporting."
  }

  $TrustedGateTest = "scripts\test_viewer_patch_trusted_gates.ps1"
  if (Test-RepoPath $TrustedGateTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $TrustedGateTest) *>&1) -join " "
      Add-AuditRow "Automation" "Viewer patch trusted-content gate regression test" "done" "$TrustedGateTest passes; $OutputText" "Re-run after changing viewer patch switches or trusted-content aliases."
    } catch {
      Add-AuditRow "Automation" "Viewer patch trusted-content gate regression test" "pending" "$TrustedGateTest failed: $($_.Exception.Message)" "Keep unsafe aliases behind --viewer-trusted-content and leave reserved gates as no-ops until measured experiments exist."
    }
  } else {
    Add-AuditRow "Automation" "Viewer patch trusted-content gate regression test" "missing" "$TrustedGateTest missing" "Restore the trusted-content gate regression test."
  }

  $BenchmarkFlagMetadataTest = "scripts\test_benchmark_flag_metadata.ps1"
  if (Test-RepoPath $BenchmarkFlagMetadataTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $BenchmarkFlagMetadataTest) *>&1) -join " "
      Add-AuditRow "Automation" "Benchmark trusted-flag metadata regression test" "done" "$BenchmarkFlagMetadataTest passes; $OutputText" "Re-run after changing trusted viewer flags, benchmark runner launch switches, or metric validation."
    } catch {
      Add-AuditRow "Automation" "Benchmark trusted-flag metadata regression test" "pending" "$BenchmarkFlagMetadataTest failed: $($_.Exception.Message)" "Ensure raw benchmark JSON records every trusted viewer experiment flag used for a run."
    }
  } else {
    Add-AuditRow "Automation" "Benchmark trusted-flag metadata regression test" "missing" "$BenchmarkFlagMetadataTest missing" "Restore the benchmark trusted-flag metadata regression test."
  }

  $NavigationLockTest = "scripts\test_viewer_patch_navigation_lock.ps1"
  if (Test-RepoPath $NavigationLockTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $NavigationLockTest) *>&1) -join " "
      Add-AuditRow "Automation" "Viewer patch navigation-lock regression test" "done" "$NavigationLockTest passes; $OutputText" "Re-run after changing viewer startup, toolbar, navigation throttle, or file-navigation patch logic."
    } catch {
      Add-AuditRow "Automation" "Viewer patch navigation-lock regression test" "pending" "$NavigationLockTest failed: $($_.Exception.Message)" "Keep startup URL handling, toolbar hiding, current-tab confinement, same-origin navigation, file-directory confinement, and new-window blocking intact."
    }
  } else {
    Add-AuditRow "Automation" "Viewer patch navigation-lock regression test" "missing" "$NavigationLockTest missing" "Restore the navigation-lock patch regression test."
  }

  $ViewerEntrypointTest = "scripts\test_viewer_patch_entrypoint.ps1"
  if (Test-RepoPath $ViewerEntrypointTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $ViewerEntrypointTest) *>&1) -join " "
      Add-AuditRow "Automation" "Viewer patch entrypoint regression test" "done" "$ViewerEntrypointTest passes; $OutputText" "Re-run after changing viewer startup URL handling, toolbar suppression, or content-shell launch behavior."
    } catch {
      Add-AuditRow "Automation" "Viewer patch entrypoint regression test" "pending" "$ViewerEntrypointTest failed: $($_.Exception.Message)" "Keep --viewer-app-url ahead of positional/default URLs and keep viewer-mode toolbar suppression intact."
    }
  } else {
    Add-AuditRow "Automation" "Viewer patch entrypoint regression test" "missing" "$ViewerEntrypointTest missing" "Restore the viewer entrypoint patch regression test."
  }

  $StdoutResultTest = "scripts\test_viewer_patch_stdout_result.ps1"
  if (Test-RepoPath $StdoutResultTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $StdoutResultTest) *>&1) -join " "
      Add-AuditRow "Automation" "Viewer patch stdout result regression test" "done" "$StdoutResultTest passes; $OutputText" "Re-run after changing viewer patch console handling or benchmark result markers."
    } catch {
      Add-AuditRow "Automation" "Viewer patch stdout result regression test" "pending" "$StdoutResultTest failed: $($_.Exception.Message)" "Keep THREE_VIEWER_RESULT forwarding gated to viewer mode and preserve default console handling for other messages."
    }
  } else {
    Add-AuditRow "Automation" "Viewer patch stdout result regression test" "missing" "$StdoutResultTest missing" "Restore the stdout benchmark-result patch regression test."
  }

  $RuntimeSurfaceTest = "scripts\test_viewer_runtime_surface.ps1"
  if (Test-RepoPath $RuntimeSurfaceTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $RuntimeSurfaceTest) *>&1) -join " "
      Add-AuditRow "Automation" "Viewer runtime API surface regression test" "done" "$RuntimeSurfaceTest passes; $OutputText" "Re-run after changing viewer startup, renderer creation, local asset loading, input handling, or benchmark CLI options."
    } catch {
      Add-AuditRow "Automation" "Viewer runtime API surface regression test" "pending" "$RuntimeSurfaceTest failed: $($_.Exception.Message)" "Restore WebGL2, WebGPU, requestAnimationFrame, Canvas, fetch/createImageBitmap, performance.now, input, benchmark result export, and no-primary-readback coverage."
    }
  } else {
    Add-AuditRow "Automation" "Viewer runtime API surface regression test" "missing" "$RuntimeSurfaceTest missing" "Restore the viewer runtime surface regression test."
  }

  $HardwareGpuLaunchTest = "scripts\test_hardware_gpu_launch_flags.ps1"
  if (Test-RepoPath $HardwareGpuLaunchTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $HardwareGpuLaunchTest) *>&1) -join " "
      Add-AuditRow "Automation" "Hardware-GPU launch flag regression test" "done" "$HardwareGpuLaunchTest passes; $OutputText" "Re-run after changing benchmark, smoke, trace, package launchers, or software-rendering validators."
    } catch {
      Add-AuditRow "Automation" "Hardware-GPU launch flag regression test" "pending" "$HardwareGpuLaunchTest failed: $($_.Exception.Message)" "Keep primary launchers fail-closed against software rasterizer fallback and keep official/stability validators rejecting software-rendered evidence."
    }
  } else {
    Add-AuditRow "Automation" "Hardware-GPU launch flag regression test" "missing" "$HardwareGpuLaunchTest missing" "Restore launch-flag coverage for hardware GPU primary runs."
  }

  $SmokeCoverageTest = "scripts\test_smoke_coverage.ps1"
  if (Test-RepoPath $SmokeCoverageTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SmokeCoverageTest) *>&1) -join " "
      Add-AuditRow "Automation" "Runtime smoke coverage regression test" "done" "$SmokeCoverageTest passes; $OutputText" "Re-run after changing runtime smoke tests or smoke-result validation."
    } catch {
      Add-AuditRow "Automation" "Runtime smoke coverage regression test" "pending" "$SmokeCoverageTest failed: $($_.Exception.Message)" "Restore required smoke coverage for viewer launch, WebGL2, WebGPU adapter/device, cube render, texture/createImageBitmap, shader material, benchmark run, crash detection, and smoke result validation."
    }
  } else {
    Add-AuditRow "Automation" "Runtime smoke coverage regression test" "missing" "$SmokeCoverageTest missing" "Restore the runtime smoke coverage regression test."
  }

  $TrustedContentFlagsDocTest = "scripts\test_trusted_content_flags_doc.ps1"
  if (Test-RepoPath $TrustedContentFlagsDocTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $TrustedContentFlagsDocTest) *>&1) -join " "
      Add-AuditRow "Automation" "Trusted-content flag documentation regression test" "done" "$TrustedContentFlagsDocTest passes; $OutputText" "Re-run after changing docs/trusted_content_flags.md or viewer trusted switches."
    } catch {
      Add-AuditRow "Automation" "Trusted-content flag documentation regression test" "pending" "$TrustedContentFlagsDocTest failed: $($_.Exception.Message)" "Ensure unsafe viewer flags document trusted gating, risk, pass-through decoder aliasing, reserved no-op status, and benchmark metadata."
    }
  } else {
    Add-AuditRow "Automation" "Trusted-content flag documentation regression test" "missing" "$TrustedContentFlagsDocTest missing" "Restore structural validation for docs/trusted_content_flags.md."
  }

  $TraceStartDelayTest = "scripts\test_trace_capture_start_delay.ps1"
  if (Test-RepoPath $TraceStartDelayTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $TraceStartDelayTest) *>&1) -join " "
      Add-AuditRow "Automation" "Trace capture start-delay regression test" "done" "$TraceStartDelayTest passes; $OutputText" "Re-run after changing viewer benchmark startup or trace capture launch behavior."
    } catch {
      Add-AuditRow "Automation" "Trace capture start-delay regression test" "pending" "$TraceStartDelayTest failed: $($_.Exception.Message)" "Ensure fork viewer-mode trace capture can start tracing before renderer/context creation."
    }
  } else {
    Add-AuditRow "Automation" "Trace capture start-delay regression test" "missing" "$TraceStartDelayTest missing" "Restore trace capture start-delay regression coverage."
  }

  $TraceFileValidationTest = "scripts\test_trace_file_validation.ps1"
  if (Test-RepoPath $TraceFileValidationTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $TraceFileValidationTest) *>&1) -join " "
      Add-AuditRow "Automation" "Trace file validation regression test" "done" "$TraceFileValidationTest passes; $OutputText" "Re-run after changing trace capture, raw trace parsing, or official trace manifest validation."
    } catch {
      Add-AuditRow "Automation" "Trace file validation regression test" "pending" "$TraceFileValidationTest failed: $($_.Exception.Message)" "Ensure raw trace JSON is parseable and contains named timestamped events before accepting trace evidence."
    }
  } else {
    Add-AuditRow "Automation" "Trace file validation regression test" "missing" "$TraceFileValidationTest missing" "Restore raw trace validation coverage."
  }

  $TraceResultValidationTest = "scripts\test_trace_result_validation.ps1"
  if (Test-RepoPath $TraceResultValidationTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $TraceResultValidationTest) *>&1) -join " "
      Add-AuditRow "Automation" "Trace result sidecar validation regression test" "done" "$TraceResultValidationTest passes; $OutputText" "Re-run after changing trace sidecar schema, trace capture metadata, or official trace manifest validation."
    } catch {
      Add-AuditRow "Automation" "Trace result sidecar validation regression test" "pending" "$TraceResultValidationTest failed: $($_.Exception.Message)" "Ensure trace .result.json sidecars prove the expected browser, scene, renderer, duration, warmup, start delay, launch flag metadata, and embedded benchmark metadata."
    }
  } else {
    Add-AuditRow "Automation" "Trace result sidecar validation regression test" "missing" "$TraceResultValidationTest missing" "Restore trace result sidecar validation coverage."
  }

  $SmokeDetailTest = "scripts\test_smoke_detail_validation.ps1"
  if (Test-RepoPath $SmokeDetailTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SmokeDetailTest) *>&1) -join " "
      Add-AuditRow "Automation" "Smoke detail validation regression test" "done" "$SmokeDetailTest passes; $OutputText" "Re-run after changing smoke-result validation for runtime, navigation, or file-navigation outputs."
    } catch {
      Add-AuditRow "Automation" "Smoke detail validation regression test" "pending" "$SmokeDetailTest failed: $($_.Exception.Message)" "Ensure smoke-result validation rejects navigation/file-navigation artifacts that do not prove the intended allowed and blocked URL outcomes."
    }
  } else {
    Add-AuditRow "Automation" "Smoke detail validation regression test" "missing" "$SmokeDetailTest missing" "Restore the smoke detail validation regression test."
  }

  $OptimizationTrackingTest = "scripts\test_optimization_tracking.ps1"
  if (Test-RepoPath $OptimizationTrackingTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $OptimizationTrackingTest) *>&1) -join " "
      Add-AuditRow "Automation" "Optimization tracking coverage regression test" "done" "$OptimizationTrackingTest passes; $OutputText" "Re-run after changing optimization class docs or prompt-to-artifact audit rows."
    } catch {
      Add-AuditRow "Automation" "Optimization tracking coverage regression test" "pending" "$OptimizationTrackingTest failed: $($_.Exception.Message)" "Ensure every prompt-requested optimization class is explicitly tracked in docs/removed_subsystems.md, docs/optimization_log.md, or docs/source_investigation.md."
    }
  } else {
    Add-AuditRow "Automation" "Optimization tracking coverage regression test" "missing" "$OptimizationTrackingTest missing" "Restore the optimization tracking regression test."
  }

  $OptimizationDecisionAuditTest = "scripts\test_optimization_decision_audit.ps1"
  if (Test-RepoPath $OptimizationDecisionAuditTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $OptimizationDecisionAuditTest) *>&1) -join " "
      Add-AuditRow "Automation" "Optimization decision audit regression test" "done" "$OptimizationDecisionAuditTest passes; $OutputText" "Re-run after changing optimization decision table or artifact audit optimization rows."
    } catch {
      Add-AuditRow "Automation" "Optimization decision audit regression test" "pending" "$OptimizationDecisionAuditTest failed: $($_.Exception.Message)" "Ensure optimization-class audit rows remain pending until structured final measured decisions exist."
    }
  } else {
    Add-AuditRow "Automation" "Optimization decision audit regression test" "missing" "$OptimizationDecisionAuditTest missing" "Restore the optimization decision audit regression test."
  }

  $RemovedSubsystemsTest = "scripts\test_removed_subsystems_register.ps1"
  if (Test-RepoPath $RemovedSubsystemsTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $RemovedSubsystemsTest) *>&1) -join " "
      Add-AuditRow "Automation" "Removed subsystem register regression test" "done" "$RemovedSubsystemsTest passes; $OutputText" "Re-run after changing docs/removed_subsystems.md."
    } catch {
      Add-AuditRow "Automation" "Removed subsystem register regression test" "pending" "$RemovedSubsystemsTest failed: $($_.Exception.Message)" "Ensure each removal/disable candidate row documents rationale, regression risk, and current evidence."
    }
  } else {
    Add-AuditRow "Automation" "Removed subsystem register regression test" "missing" "$RemovedSubsystemsTest missing" "Restore structural validation for docs/removed_subsystems.md."
  }

  $RemovedSubsystemsCompletionTest = "scripts\test_removed_subsystems_completion_audit.ps1"
  if (Test-RepoPath $RemovedSubsystemsCompletionTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $RemovedSubsystemsCompletionTest) *>&1) -join " "
      Add-AuditRow "Automation" "Removed subsystem completion audit regression test" "done" "$RemovedSubsystemsCompletionTest passes; $OutputText" "Re-run after changing removed-subsystem final-evidence gating."
    } catch {
      Add-AuditRow "Automation" "Removed subsystem completion audit regression test" "pending" "$RemovedSubsystemsCompletionTest failed: $($_.Exception.Message)" "Ensure the removed-subsystem register remains pending while it is draft-only or official/trusted evidence is missing."
    }
  } else {
    Add-AuditRow "Automation" "Removed subsystem completion audit regression test" "missing" "$RemovedSubsystemsCompletionTest missing" "Restore removed-subsystem final-evidence regression coverage."
  }

  $SourceInvestigationTest = "scripts\test_source_investigation_paths.ps1"
  if (Test-RepoPath $SourceInvestigationTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SourceInvestigationTest) *>&1) -join " "
      Add-AuditRow "Automation" "Source investigation path regression test" "done" "$SourceInvestigationTest passes; $OutputText" "Re-run after refreshing Chromium or changing docs/source_investigation.md."
    } catch {
      Add-AuditRow "Automation" "Source investigation path regression test" "pending" "$SourceInvestigationTest failed: $($_.Exception.Message)" "Update docs/source_investigation.md against the current Chromium checkout."
    }
  } else {
    Add-AuditRow "Automation" "Source investigation path regression test" "missing" "$SourceInvestigationTest missing" "Restore source-path validation for the Chromium investigation map."
  }

  $SourceInvestigationRevisionTest = "scripts\test_source_investigation_revision_guard.ps1"
  if (Test-RepoPath $SourceInvestigationRevisionTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SourceInvestigationRevisionTest) *>&1) -join " "
      Add-AuditRow "Automation" "Source investigation revision guard regression test" "done" "$SourceInvestigationRevisionTest passes; $OutputText" "Re-run after changing source-investigation revision stamping or Chromium pin refresh workflow."
    } catch {
      Add-AuditRow "Automation" "Source investigation revision guard regression test" "pending" "$SourceInvestigationRevisionTest failed: $($_.Exception.Message)" "Ensure docs/source_investigation.md cannot report stale Chromium verification evidence after a pin refresh."
    }
  } else {
    Add-AuditRow "Automation" "Source investigation revision guard regression test" "missing" "$SourceInvestigationRevisionTest missing" "Restore stale-source-investigation revision regression coverage."
  }

  $AtlRemediationTest = "scripts\test_atl_remediation_handoff.ps1"
  if (Test-RepoPath $AtlRemediationTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $AtlRemediationTest) *>&1) -join " "
      Add-AuditRow "Automation" "ATL remediation handoff regression test" "done" "$AtlRemediationTest passes; $OutputText" "Re-run after changing prerequisite checks, ATL installer flags, or post-ATL pipeline handoff."
    } catch {
      Add-AuditRow "Automation" "ATL remediation handoff regression test" "pending" "$AtlRemediationTest failed: $($_.Exception.Message)" "Ensure the ATL installer requires elevation, installs Microsoft.VisualStudio.Component.VC.ATLMFC, and prints the completion-oriented post-ATL pipeline command."
    }
  } else {
    Add-AuditRow "Automation" "ATL remediation handoff regression test" "missing" "$AtlRemediationTest missing" "Restore the ATL remediation handoff regression test."
  }

  $AtlBlockerAuditTest = "scripts\test_atl_blocker_audit.ps1"
  if (Test-RepoPath $AtlBlockerAuditTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $AtlBlockerAuditTest) *>&1) -join " "
      Add-AuditRow "Automation" "ATL blocker audit evidence regression test" "done" "$AtlBlockerAuditTest passes; $OutputText" "Re-run after changing build-failure freshness evidence, prebuild manifests, or ATL blocker audit rows."
    } catch {
      Add-AuditRow "Automation" "ATL blocker audit evidence regression test" "pending" "$AtlBlockerAuditTest failed: $($_.Exception.Message)" "Ensure the ATL blocker row distinguishes current Siso failure logs, stale logs, and prerequisite-only evidence."
    }
  } else {
    Add-AuditRow "Automation" "ATL blocker audit evidence regression test" "missing" "$AtlBlockerAuditTest missing" "Restore focused validation for ATL blocker audit evidence."
  }

  $PostAtlDryRunTest = "scripts\test_post_atl_pipeline_dry_run.ps1"
  if (Test-RepoPath $PostAtlDryRunTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $PostAtlDryRunTest) *>&1) -join " "
      Add-AuditRow "Automation" "Post-ATL dry-run orchestration regression test" "done" "$PostAtlDryRunTest passes; $OutputText" "Re-run after changing post-ATL, official comparison, or trusted matrix orchestration."
    } catch {
      Add-AuditRow "Automation" "Post-ATL dry-run orchestration regression test" "pending" "$PostAtlDryRunTest failed: $($_.Exception.Message)" "Fix the one-command post-ATL dry-run handoff before relying on the resume pipeline."
    }
  } else {
    Add-AuditRow "Automation" "Post-ATL dry-run orchestration regression test" "missing" "$PostAtlDryRunTest missing" "Restore the dry-run handoff regression test."
  }

  $RefreshPinDryRunTest = "scripts\test_refresh_chromium_pin_dry_run.ps1"
  if (Test-RepoPath $RefreshPinDryRunTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $RefreshPinDryRunTest) *>&1) -join " "
      Add-AuditRow "Automation" "Chromium pin refresh dry-run regression test" "done" "$RefreshPinDryRunTest passes; $OutputText" "Re-run after changing Chromium revision refresh workflow."
    } catch {
      Add-AuditRow "Automation" "Chromium pin refresh dry-run regression test" "pending" "$RefreshPinDryRunTest failed: $($_.Exception.Message)" "Ensure refresh_chromium_pin.ps1 can print the fetch/checkout/sync/GN/environment/patch-check handoff without mutating the pin in dry-run mode."
    }
  } else {
    Add-AuditRow "Automation" "Chromium pin refresh dry-run regression test" "missing" "$RefreshPinDryRunTest missing" "Restore the Chromium pin refresh dry-run regression test."
  }

  $UpstreamFreshnessAuditTest = "scripts\test_upstream_freshness_audit.ps1"
  if (Test-RepoPath $UpstreamFreshnessAuditTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $UpstreamFreshnessAuditTest) *>&1) -join " "
      Add-AuditRow "Automation" "Upstream freshness audit regression test" "done" "$UpstreamFreshnessAuditTest passes; $OutputText" "Re-run after changing upstream Chromium HEAD manifest or audit behavior."
    } catch {
      Add-AuditRow "Automation" "Upstream freshness audit regression test" "pending" "$UpstreamFreshnessAuditTest failed: $($_.Exception.Message)" "Ensure the artifact audit distinguishes matching and stale observed upstream Chromium HEAD metadata."
    }
  } else {
    Add-AuditRow "Automation" "Upstream freshness audit regression test" "missing" "$UpstreamFreshnessAuditTest missing" "Restore the upstream freshness audit regression test."
  }

  $AuditGateTest = "scripts\test_audit_fail_on_incomplete.ps1"
  $PostAtlDryRunText = if (Test-RepoPath $PostAtlDryRunTest) { Get-Content (Resolve-RepoPath $PostAtlDryRunTest) -Raw } else { "" }
  $VerifyPrebuildText = if (Test-RepoPath "scripts\verify_prebuild.ps1") { Get-Content (Resolve-RepoPath "scripts\verify_prebuild.ps1") -Raw } else { "" }
  if ((Test-RepoPath $AuditGateTest) -and $PostAtlDryRunText -match "-FailOnIncomplete" -and $VerifyPrebuildText -match [regex]::Escape($AuditGateTest)) {
    Add-AuditRow "Automation" "Artifact audit final-gate regression test" "done" "$AuditGateTest exists; post-ATL dry-run asserts -FailOnIncomplete; verify_prebuild.ps1 runs the final-gate regression" "Re-run after changing audit final-gate behavior."
  } else {
    Add-AuditRow "Automation" "Artifact audit final-gate regression test" "pending" "Final audit gate regression is not fully wired" "Ensure -FinalGate reaches audit_artifacts.ps1 -FailOnIncomplete and verify_prebuild.ps1 checks that incomplete artifacts fail the gate."
  }

  $EnvironmentManifestCoverageTest = "scripts\test_environment_manifest_coverage.ps1"
  if (Test-RepoPath $EnvironmentManifestCoverageTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $EnvironmentManifestCoverageTest) *>&1) -join " "
      Add-AuditRow "Automation" "Environment manifest coverage regression test" "done" "$EnvironmentManifestCoverageTest passes; $OutputText" "Re-run after changing prebuild environment manifest fields."
    } catch {
      Add-AuditRow "Automation" "Environment manifest coverage regression test" "pending" "$EnvironmentManifestCoverageTest failed: $($_.Exception.Message)" "Ensure prebuild-environment manifests record Chromium revision, patch state, GN args, binary paths, prerequisite checks, and build-failure slots."
    }
  } else {
    Add-AuditRow "Automation" "Environment manifest coverage regression test" "missing" "$EnvironmentManifestCoverageTest missing" "Restore the environment manifest coverage regression test."
  }

  $VerifyManifestGateTest = "scripts\test_verify_prebuild_manifest_gate.ps1"
  if (Test-RepoPath $VerifyManifestGateTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $VerifyManifestGateTest) *>&1) -join " "
      Add-AuditRow "Automation" "Prebuild manifest failure-gate regression test" "done" "$VerifyManifestGateTest passes; $OutputText" "Re-run after changing verify_prebuild.ps1 or prebuild environment manifest checks."
    } catch {
      Add-AuditRow "Automation" "Prebuild manifest failure-gate regression test" "pending" "$VerifyManifestGateTest failed: $($_.Exception.Message)" "Ensure verify_prebuild.ps1 fails on environment-manifest failures except the explicit ATL allowance."
    }
  } else {
    Add-AuditRow "Automation" "Prebuild manifest failure-gate regression test" "missing" "$VerifyManifestGateTest missing" "Restore the verify_prebuild manifest-gate regression test."
  }

  $AuditSuiteGateTest = "scripts\test_audit_official_suite_validation_gates.ps1"
  if (Test-RepoPath $AuditSuiteGateTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $AuditSuiteGateTest) *>&1) -join " "
      Add-AuditRow "Automation" "Artifact audit official suite validation-gate regression test" "done" "$AuditSuiteGateTest passes; $OutputText" "Re-run after changing official suite audit rows."
    } catch {
      Add-AuditRow "Automation" "Artifact audit official suite validation-gate regression test" "pending" "$AuditSuiteGateTest failed: $($_.Exception.Message)" "Ensure audit official suite rows enforce GPU metadata, software-renderer rejection, and expected duration/warmup."
    }
  } else {
    Add-AuditRow "Automation" "Artifact audit official suite validation-gate regression test" "missing" "$AuditSuiteGateTest missing" "Restore the audit official suite validation-gate regression test."
  }

  $DryRunManifestTest = "scripts\test_dry_run_manifests.ps1"
  if (Test-RepoPath $DryRunManifestTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $DryRunManifestTest) *>&1) -join " "
      Add-AuditRow "Automation" "Dry-run manifest structure regression test" "done" "$DryRunManifestTest passes; $OutputText" "Re-run after changing official comparison or trusted matrix manifest fields."
    } catch {
      Add-AuditRow "Automation" "Dry-run manifest structure regression test" "pending" "$DryRunManifestTest failed: $($_.Exception.Message)" "Fix dry-run manifest structure before relying on planned run evidence."
    }
  } else {
    Add-AuditRow "Automation" "Dry-run manifest structure regression test" "missing" "$DryRunManifestTest missing" "Restore the dry-run manifest regression test."
  }

  $ManifestOverrideGuardTest = "scripts\test_audit_manifest_override_guard.ps1"
  if (Test-RepoPath $ManifestOverrideGuardTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $ManifestOverrideGuardTest) *>&1) -join " "
      Add-AuditRow "Automation" "Artifact audit manifest override guard regression test" "done" "$ManifestOverrideGuardTest passes; $OutputText" "Re-run after changing manifest or report path override behavior."
    } catch {
      Add-AuditRow "Automation" "Artifact audit manifest override guard regression test" "pending" "$ManifestOverrideGuardTest failed: $($_.Exception.Message)" "Ensure test-only manifest and report path overrides cannot redirect real audits unless the explicit test override gate is set."
    }
  } else {
    Add-AuditRow "Automation" "Artifact audit manifest override guard regression test" "missing" "$ManifestOverrideGuardTest missing" "Restore the artifact audit manifest/report override guard regression test."
  }

  $OfficialManifestProvenanceTest = "scripts\test_official_manifest_provenance_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Official manifest provenance audit regression test" "done" "$OfficialManifestProvenanceTest skipped for self-test recursion guard" "Re-run after changing official comparison manifest validation."
  } elseif (Test-RepoPath $OfficialManifestProvenanceTest) {
    try {
      $null = (& (Resolve-RepoPath $OfficialManifestProvenanceTest) *>&1)
      Add-AuditRow "Automation" "Official manifest provenance audit regression test" "done" "$OfficialManifestProvenanceTest passes and verifies completed official manifests reject dry-run, incomplete-phase, stale Chromium revision, stale pin-refresh provenance, stale fork revision, mismatched duration/warmup, missing suite-validation gate settings, missing browser, and missing build-args evidence" "Re-run after changing official comparison manifest validation."
    } catch {
      Add-AuditRow "Automation" "Official manifest provenance audit regression test" "pending" "$OfficialManifestProvenanceTest failed: $($_.Exception.Message)" "Ensure completed official manifests require completed phase, current Chromium and fork revisions, pin-refresh provenance, duration/warmup validation, suite-validation gate settings, browser hashes, and build-args hashes."
    }
  } else {
    Add-AuditRow "Automation" "Official manifest provenance audit regression test" "missing" "$OfficialManifestProvenanceTest missing" "Restore the official manifest provenance audit regression test."
  }

  $OfficialManifestSuiteSemanticsTest = "scripts\test_official_manifest_suite_semantics_audit.ps1"
  if (Test-RepoPath $OfficialManifestSuiteSemanticsTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $OfficialManifestSuiteSemanticsTest) *>&1) -join " "
      Add-AuditRow "Automation" "Official manifest exact-suite semantic audit regression test" "done" "$OfficialManifestSuiteSemanticsTest passes; $OutputText" "Re-run after changing official comparison manifest result-file or report-content validation."
    } catch {
      Add-AuditRow "Automation" "Official manifest exact-suite semantic audit regression test" "pending" "$OfficialManifestSuiteSemanticsTest failed: $($_.Exception.Message)" "Ensure completed official manifests cannot pass when exact result JSON files fail validate_benchmark_suite.mjs or report content is invalid even if paths and hashes match."
    }
  } else {
    Add-AuditRow "Automation" "Official manifest exact-suite semantic audit regression test" "missing" "$OfficialManifestSuiteSemanticsTest missing" "Restore exact-suite semantic validation coverage for official comparison manifests."
  }

  $OfficialManifestAggressiveTest = "scripts\test_official_manifest_aggressive_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Official manifest aggressive audit regression test" "done" "$OfficialManifestAggressiveTest skipped for self-test recursion guard" "Re-run after changing official comparison manifest validation."
  } elseif (Test-RepoPath $OfficialManifestAggressiveTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $OfficialManifestAggressiveTest) *>&1) -join " "
      Add-AuditRow "Automation" "Official manifest aggressive audit regression test" "done" "$OfficialManifestAggressiveTest passes; $OutputText" "Re-run after changing official comparison manifest validation."
    } catch {
      Add-AuditRow "Automation" "Official manifest aggressive audit regression test" "pending" "$OfficialManifestAggressiveTest failed: $($_.Exception.Message)" "Ensure completed official manifests with include_aggressive_gpu=true require backend-consistent labels, expected flag metadata, and aggressive WebGL2/WebGPU result hashes."
    }
  } else {
    Add-AuditRow "Automation" "Official manifest aggressive audit regression test" "missing" "$OfficialManifestAggressiveTest missing" "Restore the official manifest aggressive audit regression test."
  }

  $OfficialManifestWebGpuTest = "scripts\test_official_manifest_webgpu_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Official manifest WebGPU audit regression test" "done" "$OfficialManifestWebGpuTest skipped for self-test recursion guard" "Re-run after changing official comparison manifest validation."
  } elseif (Test-RepoPath $OfficialManifestWebGpuTest) {
    try {
      $null = (& (Resolve-RepoPath $OfficialManifestWebGpuTest) *>&1)
      Add-AuditRow "Automation" "Official manifest WebGPU audit regression test" "done" "$OfficialManifestWebGpuTest passes and verifies completed WebGPU manifests require WebGPU result hashes" "Re-run after changing official comparison manifest validation."
    } catch {
      Add-AuditRow "Automation" "Official manifest WebGPU audit regression test" "pending" "$OfficialManifestWebGpuTest failed: $($_.Exception.Message)" "Ensure completed official manifests with include_webgpu=true require WebGPU result and report hashes."
    }
  } else {
    Add-AuditRow "Automation" "Official manifest WebGPU audit regression test" "missing" "$OfficialManifestWebGpuTest missing" "Restore the official manifest WebGPU audit regression test."
  }

  $OfficialManifestReportTest = "scripts\test_official_manifest_report_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Official manifest report audit regression test" "done" "$OfficialManifestReportTest skipped for self-test recursion guard" "Re-run after changing official comparison manifest validation."
  } elseif (Test-RepoPath $OfficialManifestReportTest) {
    try {
      $null = (& (Resolve-RepoPath $OfficialManifestReportTest) *>&1)
      Add-AuditRow "Automation" "Official manifest report audit regression test" "done" "$OfficialManifestReportTest passes and verifies completed official manifests require WebGL2 and WebGPU comparison report hashes; exact-suite semantic coverage also verifies hashed report content" "Re-run after changing official comparison manifest report validation."
    } catch {
      Add-AuditRow "Automation" "Official manifest report audit regression test" "pending" "$OfficialManifestReportTest failed: $($_.Exception.Message)" "Ensure completed official manifests require official WebGL2 and WebGPU comparison report hashes and valid comparison report content."
    }
  } else {
    Add-AuditRow "Automation" "Official manifest report audit regression test" "missing" "$OfficialManifestReportTest missing" "Restore the official manifest report audit regression test."
  }

  $OfficialReportFileContentTest = "scripts\test_official_report_file_content_audit.ps1"
  if (Test-RepoPath $OfficialReportFileContentTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $OfficialReportFileContentTest) *>&1) -join " "
      Add-AuditRow "Automation" "Official report file content audit regression test" "done" "$OfficialReportFileContentTest passes; $OutputText" "Re-run after changing direct official report file validation."
    } catch {
      Add-AuditRow "Automation" "Official report file content audit regression test" "pending" "$OfficialReportFileContentTest failed: $($_.Exception.Message)" "Ensure standalone human-readable report rows reject missing, placeholder, or scene-incomplete official comparison reports."
    }
  } else {
    Add-AuditRow "Automation" "Official report file content audit regression test" "missing" "$OfficialReportFileContentTest missing" "Restore direct official comparison report content audit coverage."
  }

  $OfficialManifestRequiredOptionsTest = "scripts\test_official_manifest_required_options_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Official manifest required-options audit regression test" "done" "$OfficialManifestRequiredOptionsTest skipped for self-test recursion guard" "Re-run after changing official comparison required-option validation."
  } elseif (Test-RepoPath $OfficialManifestRequiredOptionsTest) {
    try {
      $null = (& (Resolve-RepoPath $OfficialManifestRequiredOptionsTest) *>&1)
      Add-AuditRow "Automation" "Official manifest required-options audit regression test" "done" "$OfficialManifestRequiredOptionsTest passes and verifies completed official manifests must request WebGPU, aggressive GPU, trace capture, and package dirs" "Re-run after changing official comparison required-option validation."
    } catch {
      Add-AuditRow "Automation" "Official manifest required-options audit regression test" "pending" "$OfficialManifestRequiredOptionsTest failed: $($_.Exception.Message)" "Ensure completed official manifests cannot omit WebGPU, aggressive GPU, trace capture, or package-size evidence."
    }
  } else {
    Add-AuditRow "Automation" "Official manifest required-options audit regression test" "missing" "$OfficialManifestRequiredOptionsTest missing" "Restore the official manifest required-options regression test."
  }

  $OfficialManifestRuntimeTest = "scripts\test_official_manifest_runtime_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Official manifest runtime audit regression test" "done" "$OfficialManifestRuntimeTest skipped for self-test recursion guard" "Re-run after changing official comparison manifest validation."
  } elseif (Test-RepoPath $OfficialManifestRuntimeTest) {
    try {
      $null = (& (Resolve-RepoPath $OfficialManifestRuntimeTest) *>&1)
      Add-AuditRow "Automation" "Official manifest runtime audit regression test" "done" "$OfficialManifestRuntimeTest passes and verifies completed official manifests reject skipped, missing, wrong-browser, generic fork runtime smoke, semantically invalid runtime smoke including required WebGPU smoke, and invalid navigation lock evidence" "Re-run after changing official comparison manifest validation."
    } catch {
      Add-AuditRow "Automation" "Official manifest runtime audit regression test" "pending" "$OfficialManifestRuntimeTest failed: $($_.Exception.Message)" "Ensure completed official manifests require stock/fork runtime smoke and fork navigation-lock artifact hashes."
    }
  } else {
    Add-AuditRow "Automation" "Official manifest runtime audit regression test" "missing" "$OfficialManifestRuntimeTest missing" "Restore the official manifest runtime audit regression test."
  }

  $OfficialManifestTraceTest = "scripts\test_official_manifest_trace_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST -eq "1") {
    Add-AuditRow "Automation" "Official manifest trace audit regression test" "done" "$OfficialManifestTraceTest skipped for self-test recursion guard" "Re-run after changing official comparison manifest validation."
  } elseif (Test-RepoPath $OfficialManifestTraceTest) {
    try {
      $null = (& (Resolve-RepoPath $OfficialManifestTraceTest) *>&1)
      Add-AuditRow "Automation" "Official manifest trace audit regression test" "done" "$OfficialManifestTraceTest passes and verifies completed trace manifests require valid raw trace, validated trace benchmark sidecar with browser and launch metadata, trace summary hashes, and valid trace summary content" "Re-run after changing official comparison manifest validation."
    } catch {
      Add-AuditRow "Automation" "Official manifest trace audit regression test" "pending" "$OfficialManifestTraceTest failed: $($_.Exception.Message)" "Ensure completed official manifests with capture_trace=true require stock/fork trace hashes, trace sidecar metadata, and trace-summary artifact hashes/content."
    }
  } else {
    Add-AuditRow "Automation" "Official manifest trace audit regression test" "missing" "$OfficialManifestTraceTest missing" "Restore the official manifest trace audit regression test."
  }

  $TrustedManifestSuiteSemanticsTest = "scripts\test_trusted_manifest_suite_semantics_audit.ps1"
  if (Test-RepoPath $TrustedManifestSuiteSemanticsTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $TrustedManifestSuiteSemanticsTest) *>&1) -join " "
      Add-AuditRow "Automation" "Trusted manifest exact-suite semantic audit regression test" "done" "$TrustedManifestSuiteSemanticsTest passes; $OutputText" "Re-run after changing trusted experiment matrix manifest result-file or report-content validation."
    } catch {
      Add-AuditRow "Automation" "Trusted manifest exact-suite semantic audit regression test" "pending" "$TrustedManifestSuiteSemanticsTest failed: $($_.Exception.Message)" "Ensure completed trusted manifests cannot pass when exact experiment result JSON files fail validate_benchmark_suite.mjs or report content is invalid even if paths and hashes match."
    }
  } else {
    Add-AuditRow "Automation" "Trusted manifest exact-suite semantic audit regression test" "missing" "$TrustedManifestSuiteSemanticsTest missing" "Restore exact-suite semantic validation coverage for trusted experiment matrix manifests."
  }

  $SoftwareRendererTest = "scripts\test_strict_official_rejects_software_rendering.ps1"
  if (Test-RepoPath $SoftwareRendererTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $SoftwareRendererTest) *>&1) -join " "
      Add-AuditRow "Automation" "Strict official software-renderer rejection test" "done" "$SoftwareRendererTest passes; $OutputText" "Re-run after changing strict official comparison input validation."
    } catch {
      Add-AuditRow "Automation" "Strict official software-renderer rejection test" "pending" "$SoftwareRendererTest failed: $($_.Exception.Message)" "Ensure official comparison reports reject known SwiftShader/WARP/llvmpipe/software-rendered inputs, missing GPU metadata, missing fork revisions, and mismatched duration/warmup."
    }
  } else {
    Add-AuditRow "Automation" "Strict official software-renderer rejection test" "missing" "$SoftwareRendererTest missing" "Restore the strict official software-renderer regression test."
  }

  $StabilityThresholdTest = "scripts\test_stability_result_thresholds.ps1"
  if (Test-RepoPath $StabilityThresholdTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $StabilityThresholdTest) *>&1) -join " "
      Add-AuditRow "Automation" "Stability threshold regression test" "done" "$StabilityThresholdTest passes; $OutputText" "Re-run after changing long-stability validation or renderer resource counters."
    } catch {
      Add-AuditRow "Automation" "Stability threshold regression test" "pending" "$StabilityThresholdTest failed: $($_.Exception.Message)" "Ensure long-stability evidence can enforce RSS and renderer resource growth thresholds."
    }
  } else {
    Add-AuditRow "Automation" "Stability threshold regression test" "missing" "$StabilityThresholdTest missing" "Restore the stability threshold regression test."
  }

  Add-PrebuildEnvironmentManifestRow

  $PatchStateTest = "scripts\test_patch_state_audit.ps1"
  if (Test-RepoPath $PatchStateTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $PatchStateTest) *>&1) -join " "
      Add-AuditRow "Automation" "Patch-state audit regression test" "done" "$PatchStateTest passes; $OutputText" "Re-run after changing patch-state manifest or audit logic."
    } catch {
      Add-AuditRow "Automation" "Patch-state audit regression test" "pending" "$PatchStateTest failed: $($_.Exception.Message)" "Fix the non-mutating patch-state audit regression before relying on already-applied patch evidence."
    }
  } else {
    Add-AuditRow "Automation" "Patch-state audit regression test" "missing" "$PatchStateTest missing" "Restore the patch-state audit regression test."
  }
}

function Add-MetricRows {
  $Validator = Resolve-RepoPath "scripts\validate_metrics.mjs"
  $Text = if (Test-Path $Validator) { Get-Content $Validator -Raw } else { "" }
  $MissingFields = @($RequiredMetricFields | Where-Object { $Text -notmatch [regex]::Escape($_) })
  if ($MissingFields.Count -eq 0) {
    Add-AuditRow "Metrics" "Required metric schema fields" "done" "validate_metrics.mjs contains all $($RequiredMetricFields.Count) required fields" "Keep installed smoke and official result JSON validated."
  } else {
    Add-AuditRow "Metrics" "Required metric schema fields" "missing" ("Missing fields: " + ($MissingFields -join ", ")) "Add fields to validator and runner."
  }

  $MetricSchemaTest = "scripts\test_metric_schema_consistency.ps1"
  if (Test-RepoPath $MetricSchemaTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $MetricSchemaTest) *>&1) -join " "
      Add-AuditRow "Metrics" "Metric schema consistency regression test" "done" "$MetricSchemaTest passes; $OutputText" "Re-run after changing required metrics, runner output, validator schema, artifact audit fields, or benchmark methodology docs."
    } catch {
      Add-AuditRow "Metrics" "Metric schema consistency regression test" "pending" "$MetricSchemaTest failed: $($_.Exception.Message)" "Keep runner schema, validator schema, artifact audit fields, and documented metric schema in sync."
    }
  } else {
    Add-AuditRow "Metrics" "Metric schema consistency regression test" "missing" "$MetricSchemaTest missing" "Restore the metric schema consistency regression test."
  }

  $BenchmarkMetadataTest = "scripts\test_benchmark_metadata_enrichment.ps1"
  if (Test-RepoPath $BenchmarkMetadataTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $BenchmarkMetadataTest) *>&1) -join " "
      Add-AuditRow "Metrics" "Benchmark metadata enrichment regression test" "done" "$BenchmarkMetadataTest passes; $OutputText" "Re-run after changing benchmark runner provenance, size, RSS, GPU metadata, output writing, or benchmark methodology docs."
    } catch {
      Add-AuditRow "Metrics" "Benchmark metadata enrichment regression test" "pending" "$BenchmarkMetadataTest failed: $($_.Exception.Message)" "Keep benchmark runner host-side provenance and artifact metadata aligned with official evidence requirements."
    }
  } else {
    Add-AuditRow "Metrics" "Benchmark metadata enrichment regression test" "missing" "$BenchmarkMetadataTest missing" "Restore benchmark metadata enrichment regression coverage."
  }

  $ReportMetricCoverageTest = "scripts\test_report_metric_coverage.ps1"
  if (Test-RepoPath $ReportMetricCoverageTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $ReportMetricCoverageTest) *>&1) -join " "
      Add-AuditRow "Metrics" "Report metric coverage regression test" "done" "$ReportMetricCoverageTest passes; $OutputText" "Re-run after changing summary/comparison report columns or benchmark methodology docs."
    } catch {
      Add-AuditRow "Metrics" "Report metric coverage regression test" "pending" "$ReportMetricCoverageTest failed: $($_.Exception.Message)" "Keep human-readable summary and comparison reports aligned with key benchmark metrics."
    }
  } else {
    Add-AuditRow "Metrics" "Report metric coverage regression test" "missing" "$ReportMetricCoverageTest missing" "Restore report metric coverage regression coverage."
  }

  Add-MetricGlobCountRow "Metrics" "Installed-Chrome harness WebGL2 smoke results" "benchmarks\raw\smoke-installed-chrome-v6-*-webgl2.json" 6 "Harness evidence only; not acceptable for fork performance claims."
  Add-MetricGlobCountRow "Metrics" "Installed-Chrome harness WebGPU scene-name smoke results" "benchmarks\raw\smoke-installed-chrome-v7-webgpu-*-webgpu.json" 6 "Harness evidence only; non-equivalent scenes remain documented."
  Add-MetricGlobCountRow "Metrics" "Installed-Chrome current WebGPU scene suite results" "benchmarks\raw\smoke-installed-chrome-v17-webgpu-current-*-webgpu.json" $RequiredScenes.Count "Harness evidence only; re-run against stock/fork binaries after Chromium builds."
  Add-MetricGlobCountRow "Metrics" "Installed-Chrome glTF loader stress smoke results" "benchmarks\raw\smoke-installed-chrome-v12-gltf-loader-stress-*.json" 2 "Harness evidence only; re-run against stock/fork binaries after Chromium builds."
  Add-MetricGlobCountRow "Metrics" "Installed-Chrome file-mode glTF smoke with trusted file access" "benchmarks\raw\smoke-installed-chrome-v13-file-gltf-loader-stress-*-allow-file-access.json" 2 "Harness evidence only; fork must validate the trusted file-launch alias after build."
  Add-MetricJsonRow "Metrics" "Installed-Chrome WebGPU timestamp smoke result" "benchmarks\raw\smoke-installed-chrome-v14-webgpu-timestamp-instancing-webgpu.json" "Harness evidence only; same-revision stock/fork WebGPU GPU timing still required."
  Add-MetricJsonRow "Metrics" "Installed-Chrome WebGPU render-target postprocessing smoke result" "benchmarks\raw\smoke-installed-chrome-v15-webgpu-postprocessing-render-target-webgpu.json" "Harness evidence only; same-revision stock/fork WebGPU postprocessing still required."
  Add-MetricJsonRow "Metrics" "Installed-Chrome WebGPU WGSL shader-heavy smoke result" "benchmarks\raw\smoke-installed-chrome-v16-webgpu-shader-heavy-wgsl-webgpu.json" "Harness evidence only; same-revision stock/fork WebGPU shader-heavy still required."
  Add-MetricGlobCountRow "Metrics" "Installed-Chrome renderer resource counter smoke results" "benchmarks\raw\smoke-installed-chrome-v18-renderer-resource-counters-instancing-*.json" 2 "Harness evidence only; one-hour stock/fork resource growth checks still required."
  Add-MetricJsonRow "Metrics" "Resource warmup smoke result" "benchmarks\raw\smoke-installed-chrome-v10-resource-warmup-shader-heavy-webgl2.json" "Run paired stock/fork warmup experiments after binaries exist."
  Add-MetricJsonRow "Metrics" "Stability fields smoke result" "benchmarks\raw\smoke-installed-chrome-v11-stability-fields-many-draw-calls-webgl2.json" "Run one-hour stock/fork stability loops after binaries exist."
}

function Add-RuntimeRows {
  Add-SmokeJsonRow "Runtime tests" "Installed-Chrome runtime, input, WebGPU, and graphics-loss smoke" "benchmarks\raw\smoke-installed-chrome-v11-stability-smoke.json" "runtime" "Repeat against stock and fork binaries." -RequireWebGPU
  Add-SmokeJsonRow "Runtime tests" "Stock baseline runtime smoke with WebGPU" "benchmarks\raw\baseline-content-shell-runtime-smoke.json" "runtime" "Run official comparison after baseline binary exists." -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseBaseline\content_shell.exe") -ExpectBrowserMode -RequireWebGPU -RequiredBrowserFlags $RequiredBrowserFlags
  Add-SmokeJsonRow "Runtime tests" "Fork runtime smoke with WebGPU" "benchmarks\raw\fork-viewer-default-runtime-smoke.json" "runtime" "Run official comparison after fork binary exists." -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe") -ExpectViewerMode -ExpectViewerTrustedContent -RequireWebGPU -RequiredBrowserFlags $RequiredBrowserFlags
  Add-SmokeJsonRow "Runtime tests" "Fork navigation lock smoke" "benchmarks\raw\fork-viewer-default-navigation-lock.json" "navigation" "Requires patched fork binary." -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe")
  Add-SmokeJsonRow "Runtime tests" "Fork file navigation lock smoke" "benchmarks\raw\fork-viewer-default-file-navigation-lock.json" "file-navigation" "Requires patched fork binary and verifies file-mode directory confinement." -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe")
}

function Add-OfficialBenchmarkRows {
  $ExpectedForkRevision = Get-ExpectedViewerForkRevision
  $ExpectedMeasuredSeconds = -1
  $ExpectedWarmupSeconds = -1
  $BaselinePackageRequired = $false
  $ForkPackageRequired = $false
  $BrowserModeFlags = @(
    "viewer_mode=false",
    "viewer_block_external_navigation=false",
    "viewer_trusted_content=false",
    "viewer_aggressive_gpu=false",
    "viewer_relaxed_webgl_validation=false",
    "viewer_in_process_gpu=false",
    "viewer_single_process=false",
    "viewer_force_angle_backend=null",
    "requested_angle_backend=null",
    "viewer_disable_unneeded_blink_features=false",
    "viewer_direct_gpu_presentation=false"
  )
  $ForkDefaultFlags = @(
    "viewer_mode=true",
    "viewer_block_external_navigation=true",
    "viewer_trusted_content=true",
    "viewer_aggressive_gpu=false",
    "viewer_relaxed_webgl_validation=false",
    "viewer_in_process_gpu=false",
    "viewer_single_process=false",
    "viewer_force_angle_backend=null",
    "requested_angle_backend=null",
    "viewer_disable_unneeded_blink_features=false",
    "viewer_direct_gpu_presentation=false"
  )
  $ForkAggressiveCommonFlags = @(
    "viewer_mode=true",
    "viewer_block_external_navigation=true",
    "viewer_trusted_content=true",
    "viewer_aggressive_gpu=true",
    "viewer_relaxed_webgl_validation=false",
    "viewer_in_process_gpu=false",
    "viewer_single_process=false",
    "viewer_disable_unneeded_blink_features=false",
    "viewer_direct_gpu_presentation=false"
  )
  $ForkAggressiveBackendFlag = ""
  $ForkAggressiveRequestedBackendFlag = ""
  $ManifestPath = Get-OfficialComparisonManifestPathValue
  if (Test-JsonOk $ManifestPath) {
    try {
      $Manifest = Get-Content (Resolve-RepoPath $ManifestPath) -Raw | ConvertFrom-Json
      if (-not $Manifest.dry_run -and $Manifest.phase -eq "completed" -and
          $null -ne $Manifest.options.duration -and $null -ne $Manifest.options.warmup) {
        $ExpectedMeasuredSeconds = [double]$Manifest.options.duration
        $ExpectedWarmupSeconds = [double]$Manifest.options.warmup
        $BaselinePackageRequired = -not [string]::IsNullOrWhiteSpace([string]$Manifest.package_dirs.baseline)
        $ForkPackageRequired = -not [string]::IsNullOrWhiteSpace([string]$Manifest.package_dirs.fork)
        if ([string]$Manifest.options.aggressive_angle_backend) {
          $AggressiveBackend = [string]$Manifest.options.aggressive_angle_backend
          $ForkAggressiveBackendFlag = "viewer_force_angle_backend=$AggressiveBackend"
          $ForkAggressiveRequestedBackendFlag = "requested_angle_backend=$AggressiveBackend"
        }
      }
    } catch {
      $ExpectedMeasuredSeconds = -1
      $ExpectedWarmupSeconds = -1
    }
  }
  if ($ForkAggressiveBackendFlag) {
    $ForkAggressiveCommonFlags += $ForkAggressiveBackendFlag
    $ForkAggressiveCommonFlags += $ForkAggressiveRequestedBackendFlag
  }

  Add-BenchmarkSuiteRow "Official performance" "Stock WebGL2 scene suite results" "benchmarks\raw\baseline-content-shell-*-webgl2.json" "webgl2" "baseline-content-shell" "Run scripts/run_official_comparison.ps1 after baseline build." -ExpectedChromiumRevision $ExpectedChromiumRevision -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseBaseline\content_shell.exe") -RejectSoftwareRendering -RequireGpuMetadata -RequirePackageSize:$BaselinePackageRequired -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds -ExpectedWarmupSeconds $ExpectedWarmupSeconds -ExpectedFlagMetadata $BrowserModeFlags -RequiredBrowserFlags $RequiredBrowserFlags
  Add-BenchmarkSuiteRow "Official performance" "Fork default WebGL2 scene suite results" "benchmarks\raw\fork-viewer-default-*-webgl2.json" "webgl2" "fork-viewer-default" "Run scripts/run_official_comparison.ps1 after fork build." -RequireForkRevision -ExpectedChromiumRevision $ExpectedChromiumRevision -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe") -ExpectedForkRevision $ExpectedForkRevision -RejectSoftwareRendering -RequireGpuMetadata -RequirePackageSize:$ForkPackageRequired -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds -ExpectedWarmupSeconds $ExpectedWarmupSeconds -ExpectedFlagMetadata $ForkDefaultFlags -RequiredBrowserFlags $RequiredBrowserFlags
  Add-AnyVariantBenchmarkSuiteRow "Official performance" "Fork trusted/aggressive WebGL2 scene suite results" "benchmarks\raw\fork-viewer-aggressive-gpu*-*-webgl2.json" "webgl2" "Run with -IncludeAggressiveGpu and document each flag effect." -RequireForkRevision -ExpectedChromiumRevision $ExpectedChromiumRevision -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe") -ExpectedForkRevision $ExpectedForkRevision -RejectSoftwareRendering -RequireGpuMetadata -RequirePackageSize:$ForkPackageRequired -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds -ExpectedWarmupSeconds $ExpectedWarmupSeconds -ExpectedFlagMetadata $ForkAggressiveCommonFlags -RequiredBrowserFlags $RequiredBrowserFlags
  Add-BenchmarkSuiteRow "Official performance" "Stock WebGPU scene suite results" "benchmarks\raw\baseline-content-shell-webgpu-*-webgpu.json" "webgpu" "baseline-content-shell-webgpu" "Run with -IncludeWebGPU." -ExpectedChromiumRevision $ExpectedChromiumRevision -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseBaseline\content_shell.exe") -RejectSoftwareRendering -RequireGpuMetadata -RequirePackageSize:$BaselinePackageRequired -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds -ExpectedWarmupSeconds $ExpectedWarmupSeconds -ExpectedFlagMetadata $BrowserModeFlags -RequiredBrowserFlags $RequiredBrowserFlags
  Add-BenchmarkSuiteRow "Official performance" "Fork WebGPU scene suite results" "benchmarks\raw\fork-viewer-default-webgpu-*-webgpu.json" "webgpu" "fork-viewer-default-webgpu" "Run with -IncludeWebGPU." -RequireForkRevision -ExpectedChromiumRevision $ExpectedChromiumRevision -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe") -ExpectedForkRevision $ExpectedForkRevision -RejectSoftwareRendering -RequireGpuMetadata -RequirePackageSize:$ForkPackageRequired -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds -ExpectedWarmupSeconds $ExpectedWarmupSeconds -ExpectedFlagMetadata $ForkDefaultFlags -RequiredBrowserFlags $RequiredBrowserFlags
  Add-AnyVariantBenchmarkSuiteRow "Official performance" "Fork trusted/aggressive WebGPU scene suite results" "benchmarks\raw\fork-viewer-aggressive-gpu*-webgpu-*-webgpu.json" "webgpu" "Run with -IncludeWebGPU -IncludeAggressiveGpu and document each flag effect." -RequireForkRevision -ExpectedChromiumRevision $ExpectedChromiumRevision -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe") -ExpectedForkRevision $ExpectedForkRevision -RejectSoftwareRendering -RequireGpuMetadata -RequirePackageSize:$ForkPackageRequired -ExpectedMeasuredSeconds $ExpectedMeasuredSeconds -ExpectedWarmupSeconds $ExpectedWarmupSeconds -ExpectedFlagMetadata $ForkAggressiveCommonFlags -RequiredBrowserFlags $RequiredBrowserFlags
  Add-OfficialComparisonReportFilesRow
  Add-OfficialRequiredOptionsRow
  Add-OfficialComparisonManifestRow
  Add-TrustedMatrixManifestRow
}

function Add-StabilityRows {
  $ExpectedForkRevision = Get-ExpectedViewerForkRevision
  $BaselineStabilityFlags = @(
    "viewer_mode=false",
    "viewer_block_external_navigation=false",
    "viewer_trusted_content=false",
    "viewer_aggressive_gpu=false",
    "viewer_relaxed_webgl_validation=false",
    "viewer_in_process_gpu=false",
    "viewer_single_process=false",
    "viewer_force_angle_backend=null",
    "requested_angle_backend=null",
    "viewer_disable_unneeded_blink_features=false",
    "viewer_direct_gpu_presentation=false"
  )
  $ForkStabilityFlags = @(
    "viewer_mode=true",
    "viewer_block_external_navigation=true",
    "viewer_trusted_content=true",
    "viewer_aggressive_gpu=false",
    "viewer_relaxed_webgl_validation=false",
    "viewer_in_process_gpu=false",
    "viewer_single_process=false",
    "viewer_force_angle_backend=null",
    "requested_angle_backend=null",
    "viewer_disable_unneeded_blink_features=false",
    "viewer_direct_gpu_presentation=false"
  )
  Add-StabilityResultRow `
    -Requirement "One-hour stock stability result" `
    -Pattern "benchmarks\raw\baseline-content-shell*long-stability*.json" `
    -ExpectedVariant "baseline-content-shell-long-stability" `
    -RequirePackageSize `
    -ExpectedChromiumRevision $ExpectedChromiumRevision `
    -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseBaseline\content_shell.exe") `
    -ExpectedFlagMetadata $BaselineStabilityFlags `
    -RequiredBrowserFlags $RequiredBrowserFlags `
    -Remaining "Run scripts/run_long_stability.ps1 -Duration 3600 -MaxRssDeltaMb $DefaultStabilityMaxRssDeltaMb -MaxRendererResourceDelta $DefaultStabilityMaxRendererResourceDelta for a stable scene."
  Add-StabilityResultRow `
    -Requirement "One-hour fork stability result" `
    -Pattern "benchmarks\raw\fork-viewer-default*long-stability*.json" `
    -ExpectedVariant "fork-viewer-default-long-stability" `
    -RequireForkRevision `
    -RequirePackageSize `
    -ExpectedChromiumRevision $ExpectedChromiumRevision `
    -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe") `
    -ExpectedForkRevision $ExpectedForkRevision `
    -ExpectedFlagMetadata $ForkStabilityFlags `
    -RequiredBrowserFlags $RequiredBrowserFlags `
    -Remaining "Run scripts/run_long_stability.ps1 -Duration 3600 -ViewerMode -ViewerTrustedContent -MaxRssDeltaMb $DefaultStabilityMaxRssDeltaMb -MaxRendererResourceDelta $DefaultStabilityMaxRendererResourceDelta for a stable scene."
  Add-StabilityBehaviorDocumentationRow `
    -BaselineStabilityFlags $BaselineStabilityFlags `
    -ForkStabilityFlags $ForkStabilityFlags `
    -ExpectedForkRevision $ExpectedForkRevision
}

function Split-MarkdownTableRow {
  param([string]$Line)
  $Trimmed = $Line.Trim()
  if (-not $Trimmed.StartsWith("|") -or -not $Trimmed.EndsWith("|")) {
    return @()
  }
  $Inner = $Trimmed.Trim("|")
  return @($Inner -split "\|" | ForEach-Object { $_.Trim() })
}

function Test-IncompleteOptimizationField {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $true
  }
  $Normalized = $Value.ToLowerInvariant()
  return $Normalized -match "\b(pending|tbd|todo|not measured|awaiting|requires built fork|build pending|same-revision.*pending)\b"
}

function Get-OptimizationDecisionTable {
  $PathValue = Get-OptimizationLogPathValue
  $Resolved = Resolve-RepoPath $PathValue
  $Result = [ordered]@{
    Path = $PathValue
    ResolvedPath = $Resolved
    Rows = @{}
    Error = ""
  }

  if (-not (Test-Path -LiteralPath $Resolved)) {
    $Result.Error = "optimization log missing: $PathValue"
    return [pscustomobject]$Result
  }

  $Lines = Get-Content -LiteralPath $Resolved
  $InSection = $false
  $Header = @()
  foreach ($Line in $Lines) {
    if ($Line -match "^\s*##\s+Prompt Optimization Class Decisions\s*$") {
      $InSection = $true
      continue
    }
    if ($InSection -and $Line -match "^\s*##\s+") {
      break
    }
    if (-not $InSection -or $Line -notmatch "^\s*\|") {
      continue
    }

    $Cells = Split-MarkdownTableRow $Line
    if ($Cells.Count -eq 0) {
      continue
    }
    if ($Cells -join "" -match "^-+$") {
      continue
    }
    if ($Header.Count -eq 0) {
      $Header = @($Cells | ForEach-Object { $_.ToLowerInvariant() })
      continue
    }
    if ($Cells[0] -match "^-+$") {
      continue
    }

    $Row = @{}
    for ($Index = 0; $Index -lt $Header.Count -and $Index -lt $Cells.Count; $Index += 1) {
      $Row[$Header[$Index]] = $Cells[$Index]
    }
    if ($Row.ContainsKey("optimization class") -and $Row["optimization class"]) {
      $Result.Rows[$Row["optimization class"].ToLowerInvariant()] = [pscustomobject]$Row
    }
  }

  $RequiredColumns = @("optimization class", "status", "measured effect", "risk", "relevant evidence", "notes")
  $MissingColumns = @($RequiredColumns | Where-Object { $Header -notcontains $_ })
  if (-not $InSection) {
    $Result.Error = "Prompt Optimization Class Decisions section missing from $PathValue"
  } elseif ($MissingColumns.Count -gt 0) {
    $Result.Error = "Prompt Optimization Class Decisions table missing columns: $($MissingColumns -join ', ')"
  }

  return [pscustomobject]$Result
}

function Add-RemovedSubsystemFinalRegisterRow {
  $PathValue = Get-RemovedSubsystemsPathValue
  if (-not (Test-RepoPath $PathValue)) {
    Add-AuditRow "Optimization documentation" "Removed subsystem final decision register" "missing" "$PathValue missing" "Restore the removed/disabled subsystem register."
    return
  }

  $Text = Get-Content -LiteralPath (Resolve-RepoPath $PathValue) -Raw
  $RequiredTerms = @(
    "Rationale",
    "Regression risk",
    "Current evidence",
    "Prompt Optimization Class Tracking",
    "Subsystems Explicitly Kept For Now",
    "Update Rule"
  )
  $MissingTerms = @($RequiredTerms | Where-Object { -not $Text.Contains($_) })
  if ($MissingTerms.Count -gt 0) {
    Add-AuditRow "Optimization documentation" "Removed subsystem final decision register" "pending" "$PathValue is missing required final-register terms: $($MissingTerms -join ', ')" "Keep rationale, regression risk, current evidence, optimization-class coverage, kept-subsystem notes, and update rules in the register."
    return
  }

  $DraftPatterns = @(
    "no Chromium subsystem has been physically removed",
    "Rows marked pending are not accepted",
    "not a measured fork optimization yet",
    "runtime verification pending",
    "same-revision measurement pending",
    "source-level measurement pending",
    "benchmark pending",
    "result pending",
    "Pending fork build",
    "Pending",
    "measurements pending",
    "pending trace evidence",
    "stock/fork evidence pending"
  )
  $DraftMatches = @($DraftPatterns | Where-Object { $Text -match [regex]::Escape($_) })
  $EvidenceGaps = [System.Collections.Generic.List[string]]::new()
  if (-not (Test-RepoPath (Get-OfficialComparisonManifestPathValue))) {
    $EvidenceGaps.Add("official comparison manifest missing") | Out-Null
  }
  if (-not (Test-RepoPath (Get-TrustedMatrixManifestPathValue))) {
    $EvidenceGaps.Add("trusted experiment matrix manifest missing") | Out-Null
  }
  if ($DraftMatches.Count -gt 0) {
    $EvidenceGaps.Add("pending subsystem/future-decision language present: $($DraftMatches -join ', ')") | Out-Null
  }

  if ($EvidenceGaps.Count -gt 0) {
    Add-AuditRow "Optimization documentation" "Removed subsystem final decision register" "pending" "$PathValue documents the subsystem/removal surface, but final removed/disabled subsystem evidence is incomplete: $($EvidenceGaps -join '; ')" "After official stock/fork and trusted measurements complete, update this register with final kept/reverted/blocked/not-useful decisions, measured effects, regression risks, and artifact paths."
    return
  }

  Add-AuditRow "Optimization documentation" "Removed subsystem final decision register" "done" "$PathValue documents final removed/disabled subsystem decisions with rationale, regression risk, current evidence, official/trusted manifests, and no pending-only language" "Keep the register synchronized with future patch-series and optimization-log changes."
}

function Add-OptimizationRows {
  Add-FileRow "Optimization documentation" "Core optimization and subsystem docs" @(
    "docs\optimization_log.md",
    "docs\removed_subsystems.md",
    "docs\source_investigation.md",
    "docs\trusted_content_flags.md",
    "docs\known_limitations.md",
    "docs\future_work.md",
    "docs\rebase_strategy.md"
  ) "Replace pending rows with measured keep/revert/reject decisions."

  Add-RemovedSubsystemFinalRegisterRow

  $DecisionTable = Get-OptimizationDecisionTable
  $FinalStatuses = @("kept", "reverted", "blocked", "not useful")
  foreach ($Item in $PromptOptimizationClasses) {
    if ($DecisionTable.Error) {
      Add-AuditRow "Optimization classes" $Item "pending" $DecisionTable.Error "Add a Prompt Optimization Class Decisions table with final measured outcomes."
      continue
    }

    $Key = $Item.ToLowerInvariant()
    if (-not $DecisionTable.Rows.ContainsKey($Key)) {
      Add-AuditRow "Optimization classes" $Item "pending" "$($DecisionTable.Path) has no decision row for this optimization class" "Add a measured decision row after stock/fork benchmark evidence exists."
      continue
    }

    $Decision = $DecisionTable.Rows[$Key]
    $Status = ([string]$Decision.status).Trim().ToLowerInvariant()
    $MeasuredEffect = [string]$Decision.'measured effect'
    $Risk = [string]$Decision.risk
    $Evidence = [string]$Decision.'relevant evidence'
    $Notes = [string]$Decision.notes
    $IncompleteReasons = @()
    if ($FinalStatuses -notcontains $Status) {
      $IncompleteReasons += "status must be one of kept/reverted/blocked/not useful"
    }
    if (Test-IncompleteOptimizationField $MeasuredEffect) {
      $IncompleteReasons += "measured effect is missing or still pending"
    }
    if (Test-IncompleteOptimizationField $Risk) {
      $IncompleteReasons += "risk is missing or still pending"
    }
    if (Test-IncompleteOptimizationField $Evidence) {
      $IncompleteReasons += "relevant evidence is missing or still pending"
    }
    if (Test-IncompleteOptimizationField $Notes) {
      $IncompleteReasons += "notes are missing or still pending"
    }

    if ($IncompleteReasons.Count -eq 0) {
      Add-AuditRow "Optimization classes" $Item "done" "$($DecisionTable.Path) decision=$Status; effect=$MeasuredEffect; evidence=$Evidence" "Keep the decision row tied to the exact stock/fork benchmark artifacts."
    } else {
      Add-AuditRow "Optimization classes" $Item "pending" "$($DecisionTable.Path) decision incomplete: $($IncompleteReasons -join '; ')" "After same-revision benchmark evidence exists, record final status, measured effect, risk, evidence, and notes."
    }
  }
}

function Add-DocsRows {
  Add-FileRow "Documentation" "Required documentation set" @(
    "README.md",
    "docs\architecture.md",
    "docs\build.md",
    "docs\benchmark_methodology.md",
    "docs\optimization_log.md",
    "docs\removed_subsystems.md",
    "docs\known_limitations.md",
    "docs\future_work.md",
    "docs\rebase_strategy.md",
    "docs\source_investigation.md",
    "docs\completion_audit.md",
    "docs\requirement_traceability.md"
  ) "Finalize after stock/fork measurements."

  Add-DocumentationFinalizationRow
  Add-PerformanceClaimGuardRow

  $DocumentationStructureTest = "scripts\test_documentation_structure.ps1"
  if (Test-RepoPath $DocumentationStructureTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $DocumentationStructureTest) *>&1) -join " "
      Add-AuditRow "Documentation" "Documentation structure regression test" "done" "$DocumentationStructureTest passes; $OutputText" "Re-run after changing required docs, reproduction commands, blocker notes, benchmark methodology, or completion-audit structure."
    } catch {
      Add-AuditRow "Documentation" "Documentation structure regression test" "pending" "$DocumentationStructureTest failed: $($_.Exception.Message)" "Keep required documentation files, blocker handoff, and post-ATL reproduction commands aligned."
    }
  } else {
    Add-AuditRow "Documentation" "Documentation structure regression test" "missing" "$DocumentationStructureTest missing" "Restore the documentation structure regression test."
  }

  $DocumentationCompletionTest = "scripts\test_documentation_completion_audit.ps1"
  if ($env:THREE_BROWSER_SKIP_DOCUMENTATION_COMPLETION_AUDIT_TEST) {
    Add-AuditRow "Documentation" "Documentation completion audit regression test" "done" "$DocumentationCompletionTest skipped for self-test recursion guard" "Re-run after changing documentation final-evidence gating."
  } elseif (Test-RepoPath $DocumentationCompletionTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $DocumentationCompletionTest) *>&1) -join " "
      Add-AuditRow "Documentation" "Documentation completion audit regression test" "done" "$DocumentationCompletionTest passes; $OutputText" "Re-run after changing documentation final-evidence gating."
    } catch {
      Add-AuditRow "Documentation" "Documentation completion audit regression test" "pending" "$DocumentationCompletionTest failed: $($_.Exception.Message)" "Ensure the documentation set remains pending while final stock/fork, trusted, stability, or measured-result evidence is missing."
    }
  } else {
    Add-AuditRow "Documentation" "Documentation completion audit regression test" "missing" "$DocumentationCompletionTest missing" "Restore documentation final-evidence regression coverage."
  }

  $PerformanceClaimGuardTest = "scripts\test_performance_claim_guard.ps1"
  if ($env:THREE_BROWSER_SKIP_PERFORMANCE_CLAIM_GUARD_TEST) {
    Add-AuditRow "Documentation" "Performance-claim guard regression test" "done" "$PerformanceClaimGuardTest skipped for self-test recursion guard" "Re-run after changing premature performance-claim gating."
  } elseif (Test-RepoPath $PerformanceClaimGuardTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $PerformanceClaimGuardTest) *>&1) -join " "
      Add-AuditRow "Documentation" "Performance-claim guard regression test" "done" "$PerformanceClaimGuardTest passes; $OutputText" "Re-run after changing premature performance-claim gating."
    } catch {
      Add-AuditRow "Documentation" "Performance-claim guard regression test" "pending" "$PerformanceClaimGuardTest failed: $($_.Exception.Message)" "Ensure docs cannot claim stock/fork performance wins before official same-revision evidence exists."
    }
  } else {
    Add-AuditRow "Documentation" "Performance-claim guard regression test" "missing" "$PerformanceClaimGuardTest missing" "Restore premature performance-claim regression coverage."
  }

  $ChromiumScopeGuardTest = "scripts\test_chromium_scope_guard.ps1"
  if (Test-RepoPath $ChromiumScopeGuardTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $ChromiumScopeGuardTest) *>&1) -join " "
      Add-AuditRow "Documentation" "Chromium-only scope guard regression test" "done" "$ChromiumScopeGuardTest passes; $OutputText" "Re-run after changing README.md, docs, or patch notes."
    } catch {
      Add-AuditRow "Documentation" "Chromium-only scope guard regression test" "pending" "$ChromiumScopeGuardTest failed: $($_.Exception.Message)" "Keep authored documentation scoped to the Chromium fork; non-Chromium alternatives may appear only as benchmark references or explicit non-recommendations."
    }
  } else {
    Add-AuditRow "Documentation" "Chromium-only scope guard regression test" "missing" "$ChromiumScopeGuardTest missing" "Restore regression coverage for the fork-first documentation scope."
  }

  $ReproductionHandoffTest = "scripts\test_reproduction_handoff_audit.ps1"
  if (Test-RepoPath $ReproductionHandoffTest) {
    try {
      $OutputText = (& (Resolve-RepoPath $ReproductionHandoffTest) *>&1) -join " "
      Add-AuditRow "Documentation" "Top-level reproduction handoff regression test" "done" "$ReproductionHandoffTest passes; $OutputText" "Re-run after changing README.md, docs/build.md, reproduction commands, or audit handoff terms."
    } catch {
      Add-AuditRow "Documentation" "Top-level reproduction handoff regression test" "pending" "$ReproductionHandoffTest failed: $($_.Exception.Message)" "Ensure README.md, docs/build.md, audit_artifacts.ps1, and documentation tests require the full post-ATL completion command."
    }
  } else {
    Add-AuditRow "Documentation" "Top-level reproduction handoff regression test" "missing" "$ReproductionHandoffTest missing" "Restore focused validation for the top-level post-ATL command handoff."
  }

  $ReadmePath = Resolve-RepoPath "README.md"
  $Readme = if (Test-Path $ReadmePath) { Get-Content $ReadmePath -Raw } else { "" }
  $RequiredReadmeTerms = @(
    "verify_prebuild.ps1",
    "install_vs_atl.ps1",
    "run_post_atl_pipeline.ps1",
    "-RefreshChromiumPin",
    "-IncludeWebGPU",
    "-IncludeAggressiveGpu",
    "-AggressiveAngleBackend d3d11",
    "-CaptureTrace",
    "-RunTrustedExperimentMatrix",
    "-TrustedMatrixInProcessGpu",
    "-TrustedMatrixSingleProcess",
    "-TrustedMatrixAngleBackend d3d11",
    "-TrustedMatrixReservedNoopGates",
    "-RunLongStability",
    "-MaxRssDeltaMb 128",
    "-MaxRendererResourceDelta 0",
    "-FinalGate",
    "not the official same-revision Chromium baseline"
  )
  $MissingReadmeTerms = @($RequiredReadmeTerms | Where-Object { $Readme -notmatch [regex]::Escape($_) })
  if ($MissingReadmeTerms.Count -eq 0) {
    Add-AuditRow "Documentation" "Top-level reproduction handoff" "done" "README.md includes prebuild verification, ATL remediation, post-ATL official/trusted/stability/final-gate command, and smoke-evidence warning" "Keep in sync with docs/build.md and scripts/run_post_atl_pipeline.ps1."
  } else {
    Add-AuditRow "Documentation" "Top-level reproduction handoff" "pending" ("README.md missing terms: " + ($MissingReadmeTerms -join ", ")) "Update README.md so a fresh operator can reach the post-ATL evidence pipeline without relying on stale smoke commands."
  }
}

function Test-OfficialPerformanceEvidenceComplete {
  $ManifestPathValue = Get-OfficialComparisonManifestPathValue
  if (-not (Test-RepoPath $ManifestPathValue)) {
    return $false
  }

  try {
    $Manifest = Get-Content -LiteralPath (Resolve-RepoPath $ManifestPathValue) -Raw | ConvertFrom-Json
  } catch {
    return $false
  }

  return (-not [bool]$Manifest.dry_run) -and ([string]$Manifest.phase -eq "completed")
}

function Get-PrematurePerformanceClaimHits {
  param([string[]]$PathValues)

  $ClaimPatterns = @(
    "\b\d+(\.\d+)?\s*%?\s+(faster|higher|lower|less|more)\b.*\b(stock|baseline|chromium)\b",
    "\b(faster|outperforms?|beats?|lower latency|lower memory|reduced latency|reduced memory|reduced cpu|reduced gpu|reduced startup|improved fps|higher fps)\b.*\b(stock|baseline|chromium)\b",
    "\b(stock|baseline|chromium)\b.*\b(faster|outperforms?|beats?|lower latency|lower memory|reduced latency|reduced memory|improved fps|higher fps)\b",
    "\b(performance improvement|measured improvement)\b.*\b(stock|baseline|same-revision)\b",
    "\b(improved|reduced|lowered)\b.*\b(by|vs\.?|versus|against)\b.*\b(stock|baseline|chromium)\b"
  )
  $AllowedContextPatterns = @(
    "not .*evidence",
    "not accepted",
    "not the official",
    "pending",
    "blocked",
    "requires?",
    "must",
    "should",
    "could",
    "may",
    "hypothesis",
    "before claiming",
    "after .*exist",
    "objective",
    "goal",
    "deliverable",
    "completion",
    "benchmark requirement",
    "prove",
    "needs",
    "future",
    "smoke",
    "harness",
    "draft",
    "expected",
    "planned",
    "verify",
    "reject",
    "avoid",
    "would",
    "will",
    "compare",
    "claim"
  )

  $Hits = [System.Collections.Generic.List[string]]::new()
  foreach ($PathValue in $PathValues) {
    if (-not $PathValue) {
      continue
    }
    $Resolved = Resolve-RepoPath $PathValue
    if (-not (Test-Path -LiteralPath $Resolved)) {
      continue
    }

    $RelativePath = $PathValue
    try {
      $RelativePath = Resolve-Path -LiteralPath $Resolved -Relative
    } catch {
      $RelativePath = $PathValue
    }

    $LineNumber = 0
    foreach ($Line in Get-Content -LiteralPath $Resolved) {
      $LineNumber++
      $LowerLine = $Line.ToLowerInvariant()
      $IsClaim = $false
      foreach ($Pattern in $ClaimPatterns) {
        if ($LowerLine -match $Pattern) {
          $IsClaim = $true
          break
        }
      }
      if (-not $IsClaim) {
        continue
      }

      $IsAllowedContext = $false
      foreach ($Pattern in $AllowedContextPatterns) {
        if ($LowerLine -match $Pattern) {
          $IsAllowedContext = $true
          break
        }
      }
      if (-not $IsAllowedContext) {
        $Hits.Add(("{0}:{1}: {2}" -f $RelativePath, $LineNumber, $Line.Trim())) | Out-Null
      }
    }
  }

  return @($Hits)
}

function Add-PerformanceClaimGuardRow {
  $OfficialEvidenceComplete = Test-OfficialPerformanceEvidenceComplete
  $Hits = @(Get-PrematurePerformanceClaimHits -PathValues (Get-PerformanceClaimDocPathValues))
  if (-not $OfficialEvidenceComplete -and $Hits.Count -gt 0) {
    $Examples = ($Hits | Select-Object -First 5) -join "; "
    Add-AuditRow "Documentation" "Premature performance claims" "pending" "Official comparison manifest missing or incomplete; performance claims would be premature. Potential claim(s): $Examples" "Rewrite as pending/hypothesis language until same-revision stock/fork evidence exists, or complete the official comparison manifest first."
    return
  }

  if ($OfficialEvidenceComplete) {
    Add-AuditRow "Documentation" "Premature performance claims" "done" "Official same-revision comparison manifest is completed; performance claim guard found $($Hits.Count) claim-like line(s) for final-doc review" "Keep measured claims tied to official report artifacts and manifest hashes."
  } else {
    Add-AuditRow "Documentation" "Premature performance claims" "done" "Official comparison evidence is not complete, and authored docs avoid unguarded stock/fork performance-win claims" "Keep docs in pending/hypothesis terms until official stock/fork benchmarks exist."
  }
}

function Add-DocumentationFinalizationRow {
  $RequiredDocs = @(
    "README.md",
    "docs\architecture.md",
    "docs\build.md",
    "docs\benchmark_methodology.md",
    "docs\optimization_log.md",
    "docs\removed_subsystems.md",
    "docs\known_limitations.md",
    "docs\future_work.md",
    "docs\rebase_strategy.md",
    "docs\source_investigation.md",
    "docs\completion_audit.md",
    "docs\requirement_traceability.md",
    "docs\trusted_content_flags.md",
    "docs\stability_behavior.md",
    "docs\webgpu_scene_coverage.md"
  )
  $MissingDocs = @($RequiredDocs | Where-Object { -not (Test-RepoPath $_) })
  if ($MissingDocs.Count -gt 0) {
    Add-AuditRow "Documentation" "Final documentation evidence" "missing" "Missing: $($MissingDocs -join ', ')" "Restore all required documentation files before final completion."
    return
  }

  $Combined = [System.Text.StringBuilder]::new()
  foreach ($Doc in $RequiredDocs) {
    [void]$Combined.AppendLine("`n--- $Doc ---")
    [void]$Combined.AppendLine((Get-Content -LiteralPath (Resolve-RepoPath $Doc) -Raw))
  }
  $Text = $Combined.ToString()

  $PendingPatterns = @(
    "Status: not complete",
    "Blocked",
    "Pending",
    "Partial",
    "ATL/MFC",
    "missing ATL",
    "No stock/fork binaries",
    "No same-revision trace",
    "Installed-Chrome smoke",
    "Installed Chrome smoke",
    "harness validation only",
    "pending official",
    "pending binaries",
    "pending fork binary",
    "runtime verification pending",
    "same-revision stock/fork",
    "Run after baseline/fork binaries exist",
    "Run after stock/fork builds",
    "one-hour stock/fork stability runs remain pending"
  )
  $PendingMatches = @($PendingPatterns | Where-Object { $Text -match [regex]::Escape($_) })
  $EvidenceGaps = [System.Collections.Generic.List[string]]::new()
  if (-not (Test-RepoPath (Get-OfficialComparisonManifestPathValue))) {
    $EvidenceGaps.Add("official comparison manifest missing") | Out-Null
  }
  if (-not (Test-RepoPath (Get-TrustedMatrixManifestPathValue))) {
    $EvidenceGaps.Add("trusted experiment matrix manifest missing") | Out-Null
  }

  $ExpectedForkRevision = Get-ExpectedViewerForkRevision
  $BaselineStabilityFlags = @(
    "viewer_mode=false",
    "viewer_block_external_navigation=false",
    "viewer_trusted_content=false",
    "viewer_aggressive_gpu=false",
    "viewer_in_process_gpu=false",
    "viewer_single_process=false",
    "viewer_relaxed_webgl_validation=false"
  )
  $ForkStabilityFlags = @(
    "viewer_mode=true",
    "viewer_block_external_navigation=true",
    "viewer_trusted_content=true",
    "viewer_aggressive_gpu=false",
    "viewer_in_process_gpu=false",
    "viewer_single_process=false",
    "viewer_relaxed_webgl_validation=false"
  )
  $BaselineEvidence = Get-StabilityResultEvidence `
    -Pattern "benchmarks\raw\baseline-content-shell*long-stability*.json" `
    -ExpectedVariant "baseline-content-shell-long-stability" `
    -RequirePackageSize `
    -ExpectedChromiumRevision $ExpectedChromiumRevision `
    -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseBaseline\content_shell.exe") `
    -ExpectedFlagMetadata $BaselineStabilityFlags
  $ForkEvidence = Get-StabilityResultEvidence `
    -Pattern "benchmarks\raw\fork-viewer-default*long-stability*.json" `
    -ExpectedVariant "fork-viewer-default-long-stability" `
    -RequireForkRevision `
    -RequirePackageSize `
    -ExpectedChromiumRevision $ExpectedChromiumRevision `
    -ExpectedBrowser (Resolve-RepoPath "src\out\ReleaseViewerDefault\content_shell.exe") `
    -ExpectedForkRevision $ExpectedForkRevision `
    -ExpectedFlagMetadata $ForkStabilityFlags
  if (-not $BaselineEvidence.Ok -or -not $ForkEvidence.Ok) {
    $EvidenceGaps.Add("one-hour stock/fork stability evidence incomplete") | Out-Null
  }
  if ($PendingMatches.Count -gt 0) {
    $EvidenceGaps.Add("pending/blocker documentation language present: $($PendingMatches -join ', ')") | Out-Null
  }

  if ($EvidenceGaps.Count -gt 0) {
    Add-AuditRow "Documentation" "Final documentation evidence" "pending" "Documentation files exist, but final documentation evidence is incomplete: $($EvidenceGaps -join '; ')" "After official/trusted/stability evidence exists, rewrite docs from blocker/pending state to final measured outcomes, reproduction artifacts, limitations, bottlenecks, and future work."
    return
  }

  Add-AuditRow "Documentation" "Final documentation evidence" "done" "Required documentation files contain final measured stock/fork, trusted experiment, stability, optimization, removed-subsystem, known-limitation, future-work, and reproduction evidence without pending blocker language" "Keep docs synchronized with future benchmark reruns and Chromium rebases."
}

if ($ManifestAuditOnly) {
  Add-OfficialRequiredOptionsRow
  Add-OfficialComparisonManifestRow
  Add-TrustedMatrixManifestRow
} elseif ($PatchStateOnly) {
  Add-PatchRows
  Add-PrebuildEnvironmentManifestRow
} elseif ($BuildStateOnly) {
  Add-ChromiumRows
  Add-PrebuildEnvironmentManifestRow
} elseif ($ReportStateOnly) {
  Add-OfficialComparisonReportFilesRow
} elseif ($StabilityOnly) {
  Add-StabilityRows
} elseif ($OptimizationOnly) {
  Add-OptimizationRows
} elseif ($DocumentationOnly) {
  Add-DocsRows
} else {
  Add-ChromiumRows
  Add-PatchRows
  Add-ViewerRows
  Add-ScriptRows
  Add-MetricRows
  Add-RuntimeRows
  Add-OfficialBenchmarkRows
  Add-StabilityRows
  Add-OptimizationRows
  Add-DocsRows
}

$Incomplete = @($Rows | Where-Object { $_.Status -ne "done" })
$StatusCounts = $Rows | Group-Object Status | Sort-Object Name
$GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add("# Prompt-To-Artifact Checklist") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Generated: $GeneratedAt") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Objective: fork Chromium into a single-purpose Three.js/WebGL/WebGPU viewer runtime with benchmark viewer, same-revision stock/fork measurements, documented optimizations, and reproducible build/run workflow.") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("This checklist is evidence-oriented. Installed-Chrome smoke artifacts validate harness behavior only; they are not accepted as stock/fork performance evidence.") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("## Summary") | Out-Null
$Lines.Add("") | Out-Null
foreach ($Group in $StatusCounts) {
  $Lines.Add("- $($Group.Name): $($Group.Count)") | Out-Null
}
$Lines.Add("- incomplete: $($Incomplete.Count)") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("## Checklist") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("| Area | Requirement | Status | Evidence | Remaining work |") | Out-Null
$Lines.Add("| --- | --- | --- | --- | --- |") | Out-Null
foreach ($Row in $Rows) {
  $Lines.Add("| $(Escape-Markdown $Row.Area) | $(Escape-Markdown $Row.Requirement) | $(Escape-Markdown $Row.Status) | $(Escape-Markdown $Row.Evidence) | $(Escape-Markdown $Row.Remaining) |") | Out-Null
}

$OutputPath = Resolve-RepoPath $Output
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
Set-Content -Path $OutputPath -Value ($Lines -join "`n") -Encoding UTF8
Write-Host "Wrote $OutputPath"
Write-Host "Audit rows: $($Rows.Count); incomplete: $($Incomplete.Count)"

if ($FailOnIncomplete -and $Incomplete.Count -gt 0) {
  throw "Artifact audit is incomplete. See $OutputPath."
}

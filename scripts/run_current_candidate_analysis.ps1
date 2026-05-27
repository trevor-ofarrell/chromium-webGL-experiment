[CmdletBinding()]
param(
  [string]$OfficialManifest = ".\benchmarks\reports\official-comparison-manifest.json",
  [string[]]$TrustedManifests = @(
    ".\benchmarks\reports\trusted-experiment-matrix-webgl2-manifest.json",
    ".\benchmarks\reports\trusted-experiment-matrix-webgpu-manifest.json",
    ".\benchmarks\reports\trusted-experiment-matrix-manifest.json"
  ),
  [string]$InputList = ".\benchmarks\reports\post-atl-current-candidate-analysis-inputs.txt",
  [string]$Output = ".\benchmarks\reports\post-atl-current-candidate-analysis.md",
  [string]$Json = ".\benchmarks\reports\post-atl-current-candidate-analysis.json",
  [int]$MinMeasuredSeconds = 30,
  [double]$MinAvgFpsDeltaPct = 0.5,
  [double]$SceneRegressionPct = 1.0,
  [double]$DroppedFramesRegression = 0.0,
  [double]$CpuFrameRegressionMs = 0.5,
  [double]$RenderSubmissionRegressionMs = 0.5,
  [double]$PipelineCreateRegressionMs = 1.0,
  [string[]]$RequireCandidateRenderer = @("webgl2", "webgpu"),
  [string]$ExpectedChromiumRevision = "",
  [string]$ExpectedForkRevision = ""
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$RequiredScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

function Resolve-RepoPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return Join-Path $Root $PathValue
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

function Get-BooleanResultProperty {
  param(
    [object]$Result,
    [string]$Name,
    [string]$PathValue,
    [string]$Context
  )

  $Value = Get-ObjectPropertyValue $Result $Name
  if ($null -eq $Value) {
    throw "$Context input is missing ${Name}: $PathValue"
  }
  if ($Value -is [bool]) {
    return [bool]$Value
  }
  $StringValue = ([string]$Value).Trim().ToLowerInvariant()
  if ($StringValue -eq "true") {
    return $true
  }
  if ($StringValue -eq "false") {
    return $false
  }
  throw "$Context input ${Name} must be boolean: $PathValue has '$Value'"
}

function Get-RequiredOfficialManifestOption {
  param(
    [object]$Manifest,
    [string]$Name,
    [switch]$AllowZero
  )

  $Value = Get-ObjectPropertyValue $Manifest.options $Name
  if ($null -eq $Value) {
    throw "Official manifest is missing required option '$Name': $OfficialManifest"
  }
  try {
    $NumericValue = [double]$Value
  } catch {
    throw "Official manifest option '$Name' is not numeric: $Value"
  }
  if ($AllowZero -and $NumericValue -lt 0) {
    throw "Official manifest option '$Name' must be non-negative: $Value"
  }
  if ((-not $AllowZero) -and $NumericValue -le 0) {
    throw "Official manifest option '$Name' must be greater than zero: $Value"
  }
  return $NumericValue
}

function Read-JsonFile {
  param([string]$PathValue)
  $Resolved = Resolve-RepoPath $PathValue
  if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
    throw "Required JSON file not found: $Resolved"
  }
  return Get-Content -LiteralPath $Resolved -Raw | ConvertFrom-Json
}

function Add-ResultFile {
  param(
    [System.Collections.Generic.List[string]]$Target,
    [AllowNull()]$Value
  )
  foreach ($Item in (ConvertTo-Array $Value)) {
    if ($null -eq $Item) {
      continue
    }
    $PathValue = if ($Item -is [string]) {
      [string]$Item
    } elseif ($Item.path) {
      [string]$Item.path
    } else {
      [string]$Item
    }
    if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
      $Target.Add($PathValue) | Out-Null
    }
  }
}

function Add-OfficialManifestFiles {
  param(
    [System.Collections.Generic.List[string]]$Target,
    [object]$Manifest
  )
  foreach ($PropertyName in @(
      "baseline_webgl2",
      "fork_default_webgl2",
      "aggressive_webgl2",
      "baseline_webgpu",
      "fork_default_webgpu",
      "aggressive_webgpu"
    )) {
    Add-ResultFile -Target $Target -Value (Get-ObjectPropertyValue $Manifest.result_files $PropertyName)
  }
}

function Get-ResultFileCount {
  param([AllowNull()]$Value)

  $Count = 0
  foreach ($Item in (ConvertTo-Array $Value)) {
    if ($null -eq $Item) {
      continue
    }
    $PathValue = if ($Item -is [string]) {
      [string]$Item
    } elseif ($Item.path) {
      [string]$Item.path
    } else {
      [string]$Item
    }
    if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
      $Count++
    }
  }
  return $Count
}

function Assert-OfficialManifestRendererCoverage {
  param(
    [object]$Manifest,
    [string[]]$RequiredRenderers
  )

  foreach ($RendererValue in @($RequiredRenderers)) {
    $Renderer = ([string]$RendererValue).Trim().ToLowerInvariant()
    if (-not $Renderer) {
      continue
    }
    if ($Renderer -notin @("webgl2", "webgpu")) {
      throw "Unsupported required candidate renderer '$RendererValue'."
    }

    $BaselineProperty = "baseline_$Renderer"
    $ForkDefaultProperty = "fork_default_$Renderer"
    $AggressiveProperty = "aggressive_$Renderer"
    $BaselineCount = Get-ResultFileCount (Get-ObjectPropertyValue $Manifest.result_files $BaselineProperty)
    $ForkCount = (Get-ResultFileCount (Get-ObjectPropertyValue $Manifest.result_files $ForkDefaultProperty)) +
      (Get-ResultFileCount (Get-ObjectPropertyValue $Manifest.result_files $AggressiveProperty))

    if ($BaselineCount -le 0) {
      throw "Official manifest is missing baseline result files for required renderer '$Renderer' in '$BaselineProperty': $OfficialManifest"
    }
    if ($ForkCount -le 0) {
      throw "Official manifest is missing fork result files for required renderer '$Renderer' in '$ForkDefaultProperty' or '$AggressiveProperty': $OfficialManifest"
    }
  }
}

function Assert-OfficialManifestBucketRendererTypes {
  param([object]$Manifest)

  foreach ($Bucket in @(
      [pscustomobject]@{ Name = "baseline_webgl2"; Renderer = "webgl2" },
      [pscustomobject]@{ Name = "fork_default_webgl2"; Renderer = "webgl2" },
      [pscustomobject]@{ Name = "aggressive_webgl2"; Renderer = "webgl2" },
      [pscustomobject]@{ Name = "baseline_webgpu"; Renderer = "webgpu" },
      [pscustomobject]@{ Name = "fork_default_webgpu"; Renderer = "webgpu" },
      [pscustomobject]@{ Name = "aggressive_webgpu"; Renderer = "webgpu" }
    )) {
    foreach ($PathValue in (ConvertTo-Array (Get-ObjectPropertyValue $Manifest.result_files $Bucket.Name))) {
      if ([string]::IsNullOrWhiteSpace([string]$PathValue)) {
        continue
      }
      $Result = Read-JsonFile ([string]$PathValue)
      $RendererType = ([string](Get-ObjectPropertyValue $Result "renderer_type")).Trim().ToLowerInvariant()
      if (-not $RendererType) {
        throw "Official manifest result bucket '$($Bucket.Name)' input is missing renderer_type: $PathValue"
      }
      if ($RendererType -ne $Bucket.Renderer) {
        throw "Official manifest result bucket '$($Bucket.Name)' expected renderer_type '$($Bucket.Renderer)' but $PathValue has '$RendererType'. Regenerate the official comparison before targeted blocker planning."
      }
    }
  }
}

function Assert-OfficialManifestBucketRoles {
  param(
    [object]$Manifest,
    [string]$ExpectedForkRevision
  )

  foreach ($Bucket in @(
      [pscustomobject]@{ Name = "baseline_webgl2"; RequiresFork = $false },
      [pscustomobject]@{ Name = "baseline_webgpu"; RequiresFork = $false },
      [pscustomobject]@{ Name = "fork_default_webgl2"; RequiresFork = $true },
      [pscustomobject]@{ Name = "aggressive_webgl2"; RequiresFork = $true },
      [pscustomobject]@{ Name = "fork_default_webgpu"; RequiresFork = $true },
      [pscustomobject]@{ Name = "aggressive_webgpu"; RequiresFork = $true }
    )) {
    foreach ($PathValue in (ConvertTo-Array (Get-ObjectPropertyValue $Manifest.result_files $Bucket.Name))) {
      if ([string]::IsNullOrWhiteSpace([string]$PathValue)) {
        continue
      }

      $Result = Read-JsonFile ([string]$PathValue)
      $IsViewerMode = Get-BooleanResultProperty `
        -Result $Result `
        -Name "viewer_mode" `
        -PathValue ([string]$PathValue) `
        -Context "Official manifest result bucket '$($Bucket.Name)'"
      $ForkRevision = [string](Get-ObjectPropertyValue $Result "fork_revision")
      if ($Bucket.RequiresFork) {
        if (-not $IsViewerMode) {
          throw "Official manifest result bucket '$($Bucket.Name)' expected a fork viewer result but $PathValue has viewer_mode=false."
        }
        $IsTrustedContent = Get-BooleanResultProperty `
          -Result $Result `
          -Name "viewer_trusted_content" `
          -PathValue ([string]$PathValue) `
          -Context "Official manifest result bucket '$($Bucket.Name)'"
        if (-not $IsTrustedContent) {
          throw "Official manifest result bucket '$($Bucket.Name)' expected viewer_trusted_content=true but $PathValue has viewer_trusted_content=false."
        }
        if ([string]::IsNullOrWhiteSpace($ForkRevision)) {
          throw "Official manifest result bucket '$($Bucket.Name)' expected fork_revision '$ExpectedForkRevision' but $PathValue has an empty fork_revision."
        }
        if ($ForkRevision -ne $ExpectedForkRevision) {
          throw "Official manifest result bucket '$($Bucket.Name)' expected fork_revision '$ExpectedForkRevision' but $PathValue has '$ForkRevision'."
        }
      } else {
        if ($IsViewerMode) {
          throw "Official manifest result bucket '$($Bucket.Name)' expected a stock baseline result but $PathValue has viewer_mode=true."
        }
        if (-not [string]::IsNullOrWhiteSpace($ForkRevision)) {
          throw "Official manifest result bucket '$($Bucket.Name)' expected an empty stock fork_revision but $PathValue has '$ForkRevision'."
        }
      }
    }
  }
}

function Assert-TrustedManifestInputRoles {
  param(
    [string[]]$PathValues,
    [string]$ExpectedChromiumRevision,
    [string]$ExpectedForkRevision,
    [string]$ExpectedRenderer = "",
    [string]$TrustedManifestPath = ""
  )

  $Renderer = $ExpectedRenderer.Trim().ToLowerInvariant()
  if ($Renderer -and $Renderer -notin @("webgl2", "webgpu")) {
    throw "Trusted manifest has unsupported renderer '$ExpectedRenderer': $TrustedManifestPath"
  }

  foreach ($PathValue in @($PathValues | Select-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace([string]$PathValue)) {
      continue
    }
    $Result = Read-JsonFile ([string]$PathValue)
    $Context = "Trusted manifest result"
    if ($Renderer) {
      $RendererType = ([string](Get-ObjectPropertyValue $Result "renderer_type")).Trim().ToLowerInvariant()
      if (-not $RendererType) {
        throw "$Context input is missing renderer_type: $PathValue"
      }
      if ($RendererType -ne $Renderer) {
        throw "$Context expected renderer_type '$Renderer' from $TrustedManifestPath but $PathValue has '$RendererType'."
      }
    }

    $ChromiumRevision = [string](Get-ObjectPropertyValue $Result "chromium_revision")
    if ($ChromiumRevision -ne $ExpectedChromiumRevision) {
      throw "$Context expected chromium_revision '$ExpectedChromiumRevision' but $PathValue has '$ChromiumRevision'."
    }

    $IsViewerMode = Get-BooleanResultProperty `
      -Result $Result `
      -Name "viewer_mode" `
      -PathValue ([string]$PathValue) `
      -Context $Context
    if (-not $IsViewerMode) {
      throw "$Context expected a fork viewer result but $PathValue has viewer_mode=false."
    }

    $IsTrustedContent = Get-BooleanResultProperty `
      -Result $Result `
      -Name "viewer_trusted_content" `
      -PathValue ([string]$PathValue) `
      -Context $Context
    if (-not $IsTrustedContent) {
      throw "$Context expected viewer_trusted_content=true but $PathValue has viewer_trusted_content=false."
    }

    $ForkRevision = [string](Get-ObjectPropertyValue $Result "fork_revision")
    if ([string]::IsNullOrWhiteSpace($ForkRevision)) {
      throw "$Context expected fork_revision '$ExpectedForkRevision' but $PathValue has an empty fork_revision."
    }
    if ($ForkRevision -ne $ExpectedForkRevision) {
      throw "$Context expected fork_revision '$ExpectedForkRevision' but $PathValue has '$ForkRevision'."
    }
  }
}

function Test-TrustedManifestCompatible {
  param(
    [object]$TrustedManifest,
    [object]$OfficialManifest,
    [string]$PathValue
  )

  if ($TrustedManifest.phase -ne "completed") {
    Write-Host "Skipping $PathValue because phase is '$($TrustedManifest.phase)'."
    return $false
  }
  if ([string]$TrustedManifest.chromium_revision -ne [string]$OfficialManifest.chromium_revision) {
    Write-Host "Skipping $PathValue because Chromium revision does not match the official manifest."
    return $false
  }
  if ([string]$TrustedManifest.fork_revision -ne [string]$OfficialManifest.fork_revision) {
    Write-Host "Skipping $PathValue because fork revision does not match the official manifest."
    return $false
  }
  foreach ($Name in @("duration", "warmup", "complexity")) {
    $TrustedValue = Get-ObjectPropertyValue $TrustedManifest.options $Name
    $OfficialValue = Get-ObjectPropertyValue $OfficialManifest.options $Name
    if ($null -ne $OfficialValue -and ($null -eq $TrustedValue -or [double]$TrustedValue -ne [double]$OfficialValue)) {
      Write-Host "Skipping $PathValue because option '$Name' does not match the official manifest."
      return $false
    }
  }
  return $true
}

function Assert-InputResultMatchesOfficialOptions {
  param(
    [string]$PathValue,
    [double]$ExpectedDuration,
    [double]$ExpectedWarmup,
    [double]$ExpectedComplexity
  )

  $Result = Read-JsonFile $PathValue
  foreach ($Rule in @(
      [pscustomobject]@{ Name = "measured_seconds"; Expected = $ExpectedDuration },
      [pscustomobject]@{ Name = "warmup_seconds"; Expected = $ExpectedWarmup },
      [pscustomobject]@{ Name = "complexity"; Expected = $ExpectedComplexity }
    )) {
    $Value = Get-ObjectPropertyValue $Result $Rule.Name
    if ($null -eq $Value) {
      throw "Current candidate analysis input is missing '$($Rule.Name)': $PathValue"
    }
    try {
      $NumericValue = [double]$Value
    } catch {
      throw "Current candidate analysis input '$($Rule.Name)' is not numeric in $PathValue`: $Value"
    }
    if ([Math]::Abs($NumericValue - [double]$Rule.Expected) -gt 0.000001) {
      throw "Current candidate analysis input '$($Rule.Name)' mismatch in $PathValue`: expected $($Rule.Expected), got $NumericValue"
    }
  }
}

$Official = Read-JsonFile $OfficialManifest
if ($Official.phase -ne "completed") {
  throw "Official manifest must be completed before current candidate analysis can drive targeted blocker planning: $OfficialManifest"
}

$OfficialChromiumRevision = [string]$Official.chromium_revision
$OfficialForkRevision = [string]$Official.fork_revision
if ([string]::IsNullOrWhiteSpace($OfficialChromiumRevision)) {
  throw "Official manifest is missing chromium_revision: $OfficialManifest"
}
if ([string]::IsNullOrWhiteSpace($OfficialForkRevision)) {
  throw "Official manifest is missing fork_revision: $OfficialManifest"
}

if ($ExpectedChromiumRevision) {
  if ($OfficialChromiumRevision -ne $ExpectedChromiumRevision) {
    throw "Official manifest Chromium revision mismatch: expected $ExpectedChromiumRevision, got $OfficialChromiumRevision. Regenerate the official comparison before targeted blocker planning."
  }
} else {
  $ExpectedChromiumRevision = $OfficialChromiumRevision
}
if ($ExpectedForkRevision) {
  if ($OfficialForkRevision -ne $ExpectedForkRevision) {
    throw "Official manifest fork revision mismatch: expected $ExpectedForkRevision, got $OfficialForkRevision. Regenerate the official comparison before targeted blocker planning."
  }
} else {
  $ExpectedForkRevision = $OfficialForkRevision
}

$OfficialDuration = Get-RequiredOfficialManifestOption -Manifest $Official -Name "duration"
$OfficialWarmup = Get-RequiredOfficialManifestOption -Manifest $Official -Name "warmup" -AllowZero
$OfficialComplexity = Get-RequiredOfficialManifestOption -Manifest $Official -Name "complexity"
$RequiredCandidateRenderers = @(Normalize-CommaSeparatedStringList $RequireCandidateRenderer)
Assert-OfficialManifestRendererCoverage -Manifest $Official -RequiredRenderers $RequiredCandidateRenderers

$Inputs = [System.Collections.Generic.List[string]]::new()
$TrustedInputs = [System.Collections.Generic.List[string]]::new()
Add-OfficialManifestFiles -Target $Inputs -Manifest $Official

foreach ($TrustedManifestPath in @($TrustedManifests)) {
  if ([string]::IsNullOrWhiteSpace($TrustedManifestPath)) {
    continue
  }
  $ResolvedTrustedManifest = Resolve-RepoPath $TrustedManifestPath
  if (-not (Test-Path -LiteralPath $ResolvedTrustedManifest -PathType Leaf)) {
    continue
  }
  $Trusted = Read-JsonFile $TrustedManifestPath
  if (Test-TrustedManifestCompatible -TrustedManifest $Trusted -OfficialManifest $Official -PathValue $TrustedManifestPath) {
    $TrustedManifestInputs = [System.Collections.Generic.List[string]]::new()
    Add-ResultFile -Target $TrustedManifestInputs -Value $Trusted.result_files.all
    Assert-TrustedManifestInputRoles `
      -PathValues @($TrustedManifestInputs) `
      -ExpectedChromiumRevision $ExpectedChromiumRevision `
      -ExpectedForkRevision $ExpectedForkRevision `
      -ExpectedRenderer ([string](Get-ObjectPropertyValue $Trusted "renderer")) `
      -TrustedManifestPath $TrustedManifestPath
    foreach ($TrustedInput in @($TrustedManifestInputs)) {
      $TrustedInputs.Add([string]$TrustedInput) | Out-Null
      $Inputs.Add([string]$TrustedInput) | Out-Null
    }
  }
}

$UniqueInputs = @($Inputs | Select-Object -Unique)
if ($UniqueInputs.Count -eq 0) {
  throw "No benchmark result files found in current official/trusted manifests."
}

$MissingInputs = @($UniqueInputs | Where-Object { -not (Test-Path -LiteralPath (Resolve-RepoPath $_) -PathType Leaf) })
if ($MissingInputs.Count -gt 0) {
  throw "Current candidate analysis inputs are missing on disk: $($MissingInputs -join ', ')"
}
Assert-OfficialManifestBucketRendererTypes -Manifest $Official
Assert-OfficialManifestBucketRoles -Manifest $Official -ExpectedForkRevision $ExpectedForkRevision
Assert-TrustedManifestInputRoles `
  -PathValues @($TrustedInputs) `
  -ExpectedChromiumRevision $ExpectedChromiumRevision `
  -ExpectedForkRevision $ExpectedForkRevision
foreach ($InputPath in $UniqueInputs) {
  Assert-InputResultMatchesOfficialOptions `
    -PathValue $InputPath `
    -ExpectedDuration $OfficialDuration `
    -ExpectedWarmup $OfficialWarmup `
    -ExpectedComplexity $OfficialComplexity
}

$InputListPath = Resolve-RepoPath $InputList
$InputListDir = Split-Path -Parent $InputListPath
if ($InputListDir) {
  New-Item -ItemType Directory -Path $InputListDir -Force | Out-Null
}
Set-Content -LiteralPath $InputListPath -Encoding UTF8 -Value $UniqueInputs

$Analyzer = Resolve-RepoPath "scripts\analyze_candidates.mjs"
$AnalyzerArgs = @(
  $Analyzer,
  "--fileList", $InputListPath,
  "--output", $Output,
  "--json", $Json,
  "--minMeasuredSeconds", [string]$MinMeasuredSeconds,
  "--minScenes", [string]$RequiredScenes.Count,
  "--minAvgFpsDeltaPct", [string]$MinAvgFpsDeltaPct,
  "--sceneRegressionPct", [string]$SceneRegressionPct,
  "--droppedFramesRegression", [string]$DroppedFramesRegression,
  "--cpuFrameRegressionMs", [string]$CpuFrameRegressionMs,
  "--renderSubmissionRegressionMs", [string]$RenderSubmissionRegressionMs,
  "--pipelineCreateRegressionMs", [string]$PipelineCreateRegressionMs,
  "--requireFrameTimes",
  "--requireCheckout",
  "--requirePackageSize",
  "--expectedChromiumRevision", $ExpectedChromiumRevision,
  "--expectedForkRevision", $ExpectedForkRevision
)
foreach ($Scene in $RequiredScenes) {
  $AnalyzerArgs += @("--requiredScene", $Scene)
}
foreach ($Renderer in @($RequiredCandidateRenderers | ForEach-Object { [string]$_ } | Where-Object { $_ })) {
  $AnalyzerArgs += @("--requireCandidateRenderer", $Renderer)
}

$OldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
  $AnalyzerOutput = & node @AnalyzerArgs 2>&1
  $AnalyzerExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $OldErrorActionPreference
}

foreach ($Line in @($AnalyzerOutput)) {
  Write-Host ([string]$Line)
}

$JsonPath = Resolve-RepoPath $Json
if (-not (Test-Path -LiteralPath $JsonPath -PathType Leaf)) {
  throw "Candidate analyzer did not write JSON output: $Json"
}
if ($AnalyzerExitCode -ne 0) {
  Write-Host "Candidate analyzer exited with $AnalyzerExitCode because the required speedup gate is not yet satisfied; keeping JSON for targeted blocker planning."
}

Write-Host "Wrote current candidate analysis input list: $InputListPath"

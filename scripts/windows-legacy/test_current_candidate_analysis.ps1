[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\current-candidate-analysis-test"
$Script = Join-Path $Root "scripts\run_current_candidate_analysis.ps1"

function Assert-UnderDirectory {
  param(
    [string]$PathValue,
    [string]$Parent
  )

  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if (-not $FullPath.StartsWith($FullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside expected directory. path=$FullPath parent=$FullParent"
  }
}

function Assert-Matches {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Current candidate-analysis assertion failed: $Description. Pattern: $Pattern Output: $Text"
  }
}

function Write-OfficialManifest {
  param(
    [string]$PathValue,
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [switch]$OmitChromiumRevision,
    [switch]$OmitForkRevision,
    [string[]]$OmitOption = @(),
    [string[]]$ResultFiles = @(),
    [string[]]$BaselineResultFiles = @(),
    [string[]]$ForkResultFiles = @()
  )

  $Options = [ordered]@{}
  if (@($OmitOption) -notcontains "duration") {
    $Options["duration"] = 1
  }
  if (@($OmitOption) -notcontains "warmup") {
    $Options["warmup"] = 1
  }
  if (@($OmitOption) -notcontains "complexity") {
    $Options["complexity"] = 2
  }
  if ($BaselineResultFiles.Count -eq 0) {
    $BaselineResultFiles = @($ResultFiles)
  }
  if ($ForkResultFiles.Count -eq 0) {
    $ForkResultFiles = @($ResultFiles)
  }
  $Manifest = [ordered]@{
    phase = "completed"
    result_files = [ordered]@{
      baseline_webgl2 = @($BaselineResultFiles)
      fork_default_webgl2 = @($ForkResultFiles)
    }
    options = $Options
  }
  if (-not $OmitChromiumRevision) {
    $Manifest.chromium_revision = $ChromiumRevision
  }
  if (-not $OmitForkRevision) {
    $Manifest.fork_revision = $ForkRevision
  }
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PathValue -Encoding UTF8
}

function Write-BenchmarkResult {
  param(
    [string]$PathValue,
    [double]$MeasuredSeconds = 1,
    [double]$WarmupSeconds = 1,
    [double]$Complexity = 2,
    [string]$RendererType = "webgl2",
    [bool]$ViewerMode = $false,
    [bool]$ViewerTrustedContent = $false,
    [string]$ChromiumRevision = "",
    [AllowNull()][string]$ForkRevision = $null
  )

  $Result = [ordered]@{
    renderer_type = $RendererType
    fork_revision = $ForkRevision
    measured_seconds = $MeasuredSeconds
    warmup_seconds = $WarmupSeconds
    complexity = $Complexity
    viewer_mode = $ViewerMode
    viewer_trusted_content = $ViewerTrustedContent
  }
  if ($ChromiumRevision) {
    $Result.chromium_revision = $ChromiumRevision
  }
  $Result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $PathValue -Encoding UTF8
}

function Add-WebGpuManifestBuckets {
  param(
    [string]$ManifestPath,
    [string[]]$ResultFiles
  )

  $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  Add-Member -InputObject $Manifest.result_files -MemberType NoteProperty -Name "baseline_webgpu" -Value @($ResultFiles) -Force
  Add-Member -InputObject $Manifest.result_files -MemberType NoteProperty -Name "fork_default_webgpu" -Value @($ResultFiles) -Force
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
}

function Write-TrustedManifest {
  param(
    [string]$PathValue,
    [string]$ChromiumRevision,
    [string]$ForkRevision,
    [string[]]$ResultFiles,
    [string]$Renderer = "webgl2"
  )

  [ordered]@{
    phase = "completed"
    chromium_revision = $ChromiumRevision
    fork_revision = $ForkRevision
    renderer = $Renderer
    result_files = [ordered]@{
      all = @($ResultFiles)
    }
    options = [ordered]@{
      duration = 1
      warmup = 1
      complexity = 2
    }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PathValue -Encoding UTF8
}

function Invoke-CurrentCandidateAnalysisExpectFailure {
  param(
    [string]$ManifestPath,
    [string]$ExpectedChromiumRevision,
    [string]$ExpectedForkRevision,
    [string]$Description,
    [string[]]$RequireCandidateRenderer = @(),
    [string[]]$TrustedManifests = @()
  )

  $Command = @(
    $Script,
    "-OfficialManifest", $ManifestPath,
    "-InputList", (Join-Path $TempDir "inputs.txt"),
    "-Output", (Join-Path $TempDir "analysis.md"),
    "-Json", (Join-Path $TempDir "analysis.json")
  )
  if ($ExpectedChromiumRevision) {
    $Command += @("-ExpectedChromiumRevision", $ExpectedChromiumRevision)
  }
  if ($ExpectedForkRevision) {
    $Command += @("-ExpectedForkRevision", $ExpectedForkRevision)
  }
  foreach ($Renderer in @($RequireCandidateRenderer)) {
    $Command += @("-RequireCandidateRenderer", $Renderer)
  }
  foreach ($TrustedManifest in @($TrustedManifests)) {
    $Command += @("-TrustedManifests", $TrustedManifest)
  }

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
    throw "Expected current candidate-analysis failure for $Description."
  }
  return ($Output | ForEach-Object { [string]$_ }) -join "`n"
}

$GoodChromiumRevision = "1111111111111111111111111111111111111111"
$OtherChromiumRevision = "2222222222222222222222222222222222222222"
$GoodForkRevision = "$GoodChromiumRevision+viewerpatch-test"
$OtherForkRevision = "$GoodChromiumRevision+viewerpatch-other"

try {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

  $ManifestPath = Join-Path $TempDir "official-manifest.json"
  $BaselineWebGlResultPath = Join-Path $TempDir "baseline-webgl-result.json"
  $ForkWebGlResultPath = Join-Path $TempDir "fork-webgl-result.json"
  Write-BenchmarkResult -PathValue $BaselineWebGlResultPath -MeasuredSeconds 1 -WarmupSeconds 1 -Complexity 2
  Write-BenchmarkResult -PathValue $ForkWebGlResultPath -MeasuredSeconds 1 -WarmupSeconds 1 -Complexity 2 -ViewerMode $true -ViewerTrustedContent $true -ForkRevision $GoodForkRevision
  Write-OfficialManifest `
    -PathValue $ManifestPath `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision `
    -BaselineResultFiles @($BaselineWebGlResultPath) `
    -ForkResultFiles @($ForkWebGlResultPath)

  $StaleChromiumOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $OtherChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "stale official Chromium revision"
  Assert-Matches $StaleChromiumOutput "Official manifest Chromium revision mismatch:\s+expected\s+$OtherChromiumRevision,\s+got\s+$GoodChromiumRevision" "stale official Chromium revision rejection"
  if ($StaleChromiumOutput -match "analyze_candidates\.mjs|No benchmark result files") {
    throw "Stale official Chromium revision reached result analysis instead of failing before targeted blocker planning."
  }

  $StaleForkOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $OtherForkRevision `
    -Description "stale official fork revision"
  Assert-Matches $StaleForkOutput "Official manifest fork revision mismatch:\s+expected\s+$([regex]::Escape($OtherForkRevision)),\s+got\s+$([regex]::Escape($GoodForkRevision))" "stale official fork revision rejection"
  if ($StaleForkOutput -match "analyze_candidates\.mjs|No benchmark result files") {
    throw "Stale official fork revision reached result analysis instead of failing before targeted blocker planning."
  }

  Write-OfficialManifest -PathValue $ManifestPath -ChromiumRevision $GoodChromiumRevision -ForkRevision $GoodForkRevision -OmitChromiumRevision
  $MissingChromiumOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "missing official Chromium revision"
  Assert-Matches $MissingChromiumOutput "Official manifest is missing chromium_revision" "missing official Chromium revision rejection"

  Write-OfficialManifest -PathValue $ManifestPath -ChromiumRevision $GoodChromiumRevision -ForkRevision $GoodForkRevision -OmitForkRevision
  $MissingForkOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "missing official fork revision"
  Assert-Matches $MissingForkOutput "Official manifest is missing fork_revision" "missing official fork revision rejection"

  Write-OfficialManifest -PathValue $ManifestPath -ChromiumRevision $GoodChromiumRevision -ForkRevision $GoodForkRevision -OmitOption @("complexity")
  $MissingComplexityOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "missing official complexity option"
  Assert-Matches $MissingComplexityOutput "Official manifest is missing required option 'complexity'" "missing official complexity option rejection"

  Write-OfficialManifest `
    -PathValue $ManifestPath `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision `
    -BaselineResultFiles @($BaselineWebGlResultPath) `
    -ForkResultFiles @($ForkWebGlResultPath)
  $MissingWebGpuCoverageOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "official manifest missing required WebGPU result coverage" `
    -RequireCandidateRenderer @("webgl2,webgpu")
  Assert-Matches $MissingWebGpuCoverageOutput "Official manifest is missing baseline result files for required renderer 'webgpu'" "missing required WebGPU coverage rejection"
  if ($MissingWebGpuCoverageOutput -match "analyze_candidates\.mjs|Required speedup claim gate|No benchmark result files") {
    throw "Missing required WebGPU coverage reached analyzer instead of failing before targeted blocker planning."
  }

  Write-OfficialManifest `
    -PathValue $ManifestPath `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision `
    -BaselineResultFiles @($BaselineWebGlResultPath) `
    -ForkResultFiles @($ForkWebGlResultPath)
  Add-WebGpuManifestBuckets -ManifestPath $ManifestPath -ResultFiles @($BaselineWebGlResultPath)
  $MismatchedRendererOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "official manifest WebGPU bucket containing WebGL2 result" `
    -RequireCandidateRenderer @("webgl2,webgpu")
  Assert-Matches $MismatchedRendererOutput "Official manifest result bucket 'baseline_webgpu' expected renderer_type 'webgpu'[\s\S]+has\s+'webgl2'" "official WebGPU bucket renderer_type mismatch rejection"
  if ($MismatchedRendererOutput -match "analyze_candidates\.mjs|Required speedup claim gate") {
    throw "Mismatched-renderer official bucket reached analyzer instead of failing before targeted blocker planning."
  }

  $WrongRoleForkResultPath = Join-Path $TempDir "wrong-role-fork-result.json"
  Write-BenchmarkResult -PathValue $WrongRoleForkResultPath -MeasuredSeconds 1 -WarmupSeconds 1 -Complexity 2
  Write-OfficialManifest `
    -PathValue $ManifestPath `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision `
    -BaselineResultFiles @($BaselineWebGlResultPath) `
    -ForkResultFiles @($WrongRoleForkResultPath)
  $WrongRoleOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "official manifest fork bucket containing stock result" `
    -RequireCandidateRenderer @("webgl2")
  Assert-Matches $WrongRoleOutput "Official manifest result bucket 'fork_default_webgl2' expected a fork viewer result[\s\S]+viewer_mode=false" "official fork bucket role mismatch rejection"
  if ($WrongRoleOutput -match "analyze_candidates\.mjs|Required speedup claim gate") {
    throw "Wrong-role official bucket reached analyzer instead of failing before targeted blocker planning."
  }

  $TrustedManifestPath = Join-Path $TempDir "trusted-manifest.json"
  $TrustedStockResultPath = Join-Path $TempDir "trusted-stock-result.json"
  Write-BenchmarkResult `
    -PathValue $TrustedStockResultPath `
    -MeasuredSeconds 1 `
    -WarmupSeconds 1 `
    -Complexity 2 `
    -ChromiumRevision $GoodChromiumRevision
  Write-TrustedManifest `
    -PathValue $TrustedManifestPath `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision `
    -ResultFiles @($TrustedStockResultPath)
  Write-OfficialManifest `
    -PathValue $ManifestPath `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision `
    -BaselineResultFiles @($BaselineWebGlResultPath) `
    -ForkResultFiles @($ForkWebGlResultPath)
  $TrustedWrongRoleOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "trusted manifest result containing stock result" `
    -RequireCandidateRenderer @("webgl2") `
    -TrustedManifests @($TrustedManifestPath)
  Assert-Matches $TrustedWrongRoleOutput "Trusted manifest result expected a fork viewer result[\s\S]+viewer_mode=false" "trusted manifest stock-result rejection"
  if ($TrustedWrongRoleOutput -match "analyze_candidates\.mjs|Required speedup claim gate") {
    throw "Wrong-role trusted manifest result reached analyzer instead of failing before targeted blocker planning."
  }

  $TrustedWebGlForkResultPath = Join-Path $TempDir "trusted-webgl-fork-result.json"
  Write-BenchmarkResult `
    -PathValue $TrustedWebGlForkResultPath `
    -MeasuredSeconds 1 `
    -WarmupSeconds 1 `
    -Complexity 2 `
    -RendererType "webgl2" `
    -ViewerMode $true `
    -ViewerTrustedContent $true `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision
  Write-TrustedManifest `
    -PathValue $TrustedManifestPath `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision `
    -ResultFiles @($TrustedWebGlForkResultPath) `
    -Renderer "webgpu"
  $TrustedWrongRendererOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "trusted WebGPU manifest containing WebGL2 result" `
    -RequireCandidateRenderer @("webgl2") `
    -TrustedManifests @($TrustedManifestPath)
  Assert-Matches $TrustedWrongRendererOutput "Trusted manifest result expected renderer_type 'webgpu'[\s\S]+has 'webgl2'" "trusted manifest renderer_type mismatch rejection"
  if ($TrustedWrongRendererOutput -match "analyze_candidates\.mjs|Required speedup claim gate") {
    throw "Wrong-renderer trusted manifest result reached analyzer instead of failing before targeted blocker planning."
  }

  $WrongDurationResultPath = Join-Path $TempDir "wrong-duration-result.json"
  Write-BenchmarkResult -PathValue $WrongDurationResultPath -MeasuredSeconds 2 -WarmupSeconds 1 -Complexity 2 -ViewerMode $true -ViewerTrustedContent $true -ForkRevision $GoodForkRevision
  Write-OfficialManifest `
    -PathValue $ManifestPath `
    -ChromiumRevision $GoodChromiumRevision `
    -ForkRevision $GoodForkRevision `
    -BaselineResultFiles @($BaselineWebGlResultPath) `
    -ForkResultFiles @($WrongDurationResultPath)
  $WrongDurationOutput = Invoke-CurrentCandidateAnalysisExpectFailure `
    -ManifestPath $ManifestPath `
    -ExpectedChromiumRevision $GoodChromiumRevision `
    -ExpectedForkRevision $GoodForkRevision `
    -Description "official manifest result with mismatched duration" `
    -RequireCandidateRenderer @("webgl2")
  Assert-Matches $WrongDurationOutput "Current candidate analysis input 'measured_seconds' mismatch" "official manifest result duration mismatch rejection"
  if ($WrongDurationOutput -match "analyze_candidates\.mjs|Required speedup claim gate") {
    throw "Mismatched-duration current candidate input reached analyzer instead of failing before targeted blocker planning."
  }
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Current candidate-analysis rejects stale, incomplete, or role-contaminated official/trusted manifests and mismatched result timing before targeted blocker planning."

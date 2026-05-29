[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$ExpectedScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path $Resolved)) {
    throw "Required file not found: $PathValue"
  }
  return Get-Content $Resolved -Raw
}

function Assert-NoDuplicates {
  param(
    [string]$Label,
    [string[]]$Values
  )
  $Duplicates = @($Values | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  if ($Duplicates.Count -gt 0) {
    throw "$Label contains duplicate scenes: $($Duplicates -join ', ')"
  }
}

function Assert-SameSequence {
  param(
    [string]$Label,
    [string[]]$Actual,
    [string[]]$Expected
  )
  Assert-NoDuplicates $Label $Actual
  if ($Actual.Count -ne $Expected.Count) {
    throw "$Label scene count=$($Actual.Count), expected=$($Expected.Count). Actual=$($Actual -join ', ')"
  }
  for ($Index = 0; $Index -lt $Expected.Count; $Index += 1) {
    if ($Actual[$Index] -ne $Expected[$Index]) {
      throw "$Label scene mismatch at index $Index. Actual=$($Actual[$Index]) Expected=$($Expected[$Index])"
    }
  }
}

function Extract-QuotedArray {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Label
  )
  $Match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $Match.Success) {
    throw "Could not locate scene array in $Label."
  }
  return @([regex]::Matches($Match.Groups[1].Value, "['""]([^'""]+)['""]") | ForEach-Object { $_.Groups[1].Value })
}

function Extract-PowerShellArray {
  param(
    [string]$Text,
    [string]$VariableName,
    [string]$Label
  )
  $Pattern = '\$' + [regex]::Escape($VariableName) + '\s*=\s*@\((.*?)\)'
  return Extract-QuotedArray $Text $Pattern $Label
}

function Extract-BenchmarkMethodologyScenes {
  param([string]$Text)
  $Block = [regex]::Match(
    $Text,
    "(?:Implemented viewer scene names:|The viewer runs seven deterministic scenes:)\s*(.*?)\s*Renderer modes:",
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $Block.Success) {
    throw "Could not locate implemented scene list in docs/benchmark_methodology.md."
  }
  return @([regex]::Matches($Block.Groups[1].Value, '(?m)^-\s+`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
}

function Assert-ContainsPattern {
  param(
    [string]$Label,
    [string]$Text,
    [string]$Pattern,
    [string]$MissingMessage
  )
  if ($Text -notmatch $Pattern) {
    throw "$Label missing $MissingMessage."
  }
}

$RunFullSuite = Read-RepoFile "scripts\run_full_suite.ps1"
$RunOfficialComparison = Read-RepoFile "scripts\run_official_comparison.ps1"
$RunTrustedExperimentMatrix = Read-RepoFile "scripts\run_trusted_experiment_matrix.ps1"
$ValidateMetrics = Read-RepoFile "scripts\validate_metrics.mjs"
$ValidateBenchmarkSuite = Read-RepoFile "scripts\validate_benchmark_suite.mjs"
$AuditArtifacts = Read-RepoFile "scripts\audit_artifacts.ps1"
$ViewerScenes = Read-RepoFile "viewer\src\scenes.js"
$BenchmarkDocs = Read-RepoFile "docs\benchmark_methodology.md"
$WebGpuCoverageDocs = Read-RepoFile "docs\webgpu_scene_coverage.md"

Assert-NoDuplicates "expected scene list" $ExpectedScenes
Assert-SameSequence "run_full_suite.ps1 Scenes" (Extract-PowerShellArray $RunFullSuite "Scenes" "scripts\run_full_suite.ps1") $ExpectedScenes
Assert-SameSequence "run_official_comparison.ps1 SceneNames" (Extract-PowerShellArray $RunOfficialComparison "SceneNames" "scripts\run_official_comparison.ps1") $ExpectedScenes
Assert-SameSequence "run_trusted_experiment_matrix.ps1 default Scenes" (Extract-PowerShellArray $RunTrustedExperimentMatrix "Scenes" "scripts\run_trusted_experiment_matrix.ps1") $ExpectedScenes
Assert-SameSequence "audit_artifacts.ps1 RequiredScenes" (Extract-PowerShellArray $AuditArtifacts "RequiredScenes" "scripts\audit_artifacts.ps1") $ExpectedScenes
Assert-SameSequence "validate_metrics.mjs scenes" (Extract-QuotedArray $ValidateMetrics "const\s+scenes\s*=\s*new\s+Set\s*\(\s*\[(.*?)\]\s*\);" "scripts\validate_metrics.mjs") $ExpectedScenes
Assert-SameSequence "validate_benchmark_suite.mjs defaultScenes" (Extract-QuotedArray $ValidateBenchmarkSuite "const\s+defaultScenes\s*=\s*\[(.*?)\];" "scripts\validate_benchmark_suite.mjs") $ExpectedScenes
Assert-SameSequence "docs benchmark methodology scene list" (Extract-BenchmarkMethodologyScenes $BenchmarkDocs) $ExpectedScenes

foreach ($Scene in $ExpectedScenes) {
  $EscapedScene = [regex]::Escape($Scene)
  Assert-ContainsPattern "viewer/src/scenes.js" $ViewerScenes "case\s+['""]$EscapedScene['""]\s*:" "switch case for $Scene"
  $WebGpuRowPattern = '\|\s*`' + $EscapedScene + '`\s*\|'
  Assert-ContainsPattern "docs/webgpu_scene_coverage.md" $WebGpuCoverageDocs $WebGpuRowPattern "WebGPU coverage row for $Scene"
}

Assert-ContainsPattern "viewer/src/scenes.js" $ViewerScenes "GLTFLoader" "GLTFLoader import/use"
Assert-ContainsPattern "viewer/src/scenes.js" $ViewerScenes "viewerAssetUrl\(['""]assets/models/cube-stress\.gltf['""]\)" "bundled glTF stress asset load"
Assert-ContainsPattern "docs/webgpu_scene_coverage.md" $WebGpuCoverageDocs "official WebGPU suite" "official WebGPU suite description"
Assert-ContainsPattern "docs/webgpu_scene_coverage.md" $WebGpuCoverageDocs "timestamp queries caused device loss" "WebGPU timestamp-query device-loss caveat"

Write-Host "Scene coverage consistency checks passed for viewer, runners, validators, artifact audit, and docs."

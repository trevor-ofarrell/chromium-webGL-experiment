[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$ExpectedMetricFields = @(
  "chromium_revision",
  "fork_revision",
  "build_args_hash",
  "platform",
  "gpu_name",
  "driver_version",
  "angle_backend",
  "renderer_type",
  "scene_name",
  "complexity",
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
    throw "$Label contains duplicate metric fields: $($Duplicates -join ', ')"
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
    throw "$Label metric field count=$($Actual.Count), expected=$($Expected.Count)."
  }
  for ($Index = 0; $Index -lt $Expected.Count; $Index += 1) {
    if ($Actual[$Index] -ne $Expected[$Index]) {
      throw "$Label metric field mismatch at index $Index. Actual=$($Actual[$Index]) Expected=$($Expected[$Index])"
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
    throw "Could not locate metric field array in $Label."
  }
  return @([regex]::Matches($Match.Groups[1].Value, "['`"]([^'`"]+)['`"]") | ForEach-Object { $_.Groups[1].Value })
}

function Extract-DocumentedMetricFields {
  param([string]$Text)
  $Block = [regex]::Match($Text, "## Metric Schema\s+Each JSON result must include:\s+(.*?)\s+Unavailable metrics are recorded as", [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $Block.Success) {
    throw "Could not locate the documented metric schema field block."
  }
  return @([regex]::Matches($Block.Groups[1].Value, '(?m)^-\s+`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
}

$RunBenchmark = Read-RepoFile "scripts\run_benchmark.mjs"
$ValidateMetrics = Read-RepoFile "scripts\validate_metrics.mjs"
$AuditArtifacts = Read-RepoFile "scripts\audit_artifacts.ps1"
$BenchmarkDocs = Read-RepoFile "docs\benchmark_methodology.md"

Assert-NoDuplicates "expected schema" $ExpectedMetricFields
Assert-SameSequence "run_benchmark.mjs schemaKeys" (Extract-QuotedArray $RunBenchmark "const\s+schemaKeys\s*=\s*\[(.*?)\];" "scripts\run_benchmark.mjs") $ExpectedMetricFields
Assert-SameSequence "validate_metrics.mjs required" (Extract-QuotedArray $ValidateMetrics "const\s+required\s*=\s*\[(.*?)\];" "scripts\validate_metrics.mjs") $ExpectedMetricFields
Assert-SameSequence "audit_artifacts.ps1 RequiredMetricFields" (Extract-QuotedArray $AuditArtifacts '\$RequiredMetricFields\s*=\s*@\((.*?)\)' "scripts\audit_artifacts.ps1") $ExpectedMetricFields
Assert-SameSequence "docs benchmark metric schema" (Extract-DocumentedMetricFields $BenchmarkDocs) $ExpectedMetricFields

Write-Host "Metric schema consistency checks passed for runner, validator, artifact audit, and docs."

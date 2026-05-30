[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\official-report-file-content-audit"
$OutputPath = Join-Path $TempDir "official-report-file-content-audit.md"
$WebGlReport = Join-Path $TempDir "official-webgl2-comparison.md"
$WebGpuReport = Join-Path $TempDir "official-webgpu-comparison.md"
$RequiredScenes = @(
  "many-draw-calls",
  "instancing",
  "shader-heavy",
  "texture-streaming",
  "postprocessing",
  "large-static",
  "gltf-loader-stress"
)

function Write-TextFile {
  param(
    [string]$PathValue,
    [string]$Content
  )

  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  [System.IO.File]::WriteAllText($PathValue, $Content, [System.Text.UTF8Encoding]::new($false))
}

function New-ComparisonReportContent {
  param(
    [string]$Renderer,
    [string[]]$Labels,
    [string[]]$Scenes = $RequiredScenes
  )

  $Rows = [System.Collections.Generic.List[string]]::new()
  foreach ($Scene in $Scenes) {
    foreach ($Label in $Labels) {
      $Rows.Add("| $Scene | $Renderer | $Label | 60 | 0 | 0 | 0 |") | Out-Null
    }
  }

  @"
# Benchmark Comparison

Generated from synthetic official report file audit fixtures.

Strict official input validation was enabled: synthetic.

| Scene | Renderer | Variant | Avg FPS | Dropped Delta | JS heap Delta | GPU memory Delta |
| --- | --- | --- | ---: | ---: | ---: | ---: |
$($Rows -join "`n")
"@
}

function Invoke-ReportAudit {
  $OldValues = @{}
  foreach ($Name in @(
    "THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES",
    "THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT",
    "THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT"
  )) {
    $OldValues[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
  }

  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT = $WebGlReport
  $env:THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT = $WebGpuReport
  try {
    $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") -ReportStateOnly -Output $OutputPath *>&1
  } finally {
    foreach ($Name in $OldValues.Keys) {
      if ($null -eq $OldValues[$Name]) {
        Remove-Item "Env:\$Name" -ErrorAction SilentlyContinue
      } else {
        Set-Item "Env:\$Name" $OldValues[$Name]
      }
    }
  }

  return Get-Content -LiteralPath $OutputPath -Raw
}

function Assert-AuditMatches {
  param(
    [string]$Pattern,
    [string]$Description
  )

  $Checklist = Invoke-ReportAudit
  if ($Checklist -notmatch $Pattern) {
    throw "Official report file audit did not report $Description. Checklist: $Checklist"
  }
}

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

if (Test-Path -LiteralPath $TempDir) {
  Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
  Assert-AuditMatches "Human-readable official comparison reports.*missing.*official-webgl2-comparison" "missing report files"

  Write-TextFile $WebGlReport "placeholder"
  Write-TextFile $WebGpuReport "placeholder"
  Assert-AuditMatches "Human-readable official comparison reports.*pending.*Report content validation failed.*missing comparison heading" "invalid placeholder report content"

  Write-TextFile $WebGlReport @"
# Benchmark Comparison

Strict official input validation was enabled: synthetic.

| Scene | Renderer | Variant | Avg FPS |
| --- | --- | --- | --- |
| many-draw-calls | webgl2 | baseline-content-shell | 60 |
| many-draw-calls | webgl2 | fork-viewer-default | 60 |
"@
  Write-TextFile $WebGpuReport (New-ComparisonReportContent `
      -Renderer "webgpu" `
      -Labels @("baseline-content-shell-webgpu", "fork-viewer-default-webgpu"))
  Assert-AuditMatches "Human-readable official comparison reports.*pending.*official-webgl2-comparison missing comparison metric column Dropped Delta" "comparison report missing required metric columns"

  Write-TextFile $WebGlReport (New-ComparisonReportContent `
      -Renderer "webgl2" `
      -Labels @("baseline-content-shell", "fork-viewer-default") `
      -Scenes @($RequiredScenes | Select-Object -Skip 1))
  Write-TextFile $WebGpuReport (New-ComparisonReportContent `
      -Renderer "webgpu" `
      -Labels @("baseline-content-shell-webgpu", "fork-viewer-default-webgpu"))
  Assert-AuditMatches "Human-readable official comparison reports.*pending.*official-webgl2-comparison missing scene many-draw-calls" "scene-incomplete WebGL2 report content"

  Write-TextFile $WebGlReport (New-ComparisonReportContent `
      -Renderer "webgl2" `
      -Labels @("baseline-content-shell", "fork-viewer-default"))
  Write-TextFile $WebGpuReport (New-ComparisonReportContent `
      -Renderer "webgpu" `
      -Labels @("baseline-content-shell-webgpu", "fork-viewer-default-webgpu"))
  Assert-AuditMatches "Human-readable official comparison reports.*done.*official-webgl2-comparison.*sha256=.*official-webgpu-comparison.*sha256=.*required scenes" "valid official report content with file hashes"
} finally {
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Official report file audit rejects missing, placeholder, metric-column-incomplete, and scene-incomplete comparison reports."

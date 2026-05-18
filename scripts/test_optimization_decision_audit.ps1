[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\optimization-decision-audit"
$FinalLog = Join-Path $TempDir "optimization-final.md"
$PendingLog = Join-Path $TempDir "optimization-pending.md"
$FinalRemovedSubsystems = Join-Path $TempDir "removed-subsystems-final.md"
$OfficialManifest = Join-Path $TempDir "official-comparison-manifest.json"
$TrustedManifest = Join-Path $TempDir "trusted-experiment-matrix-manifest.json"
$FinalAudit = Join-Path $TempDir "optimization-final-audit.md"
$PendingAudit = Join-Path $TempDir "optimization-pending-audit.md"

$OptimizationClasses = @(
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

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Optimization decision audit assertion failed: $Description. Pattern: $Pattern"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -match $Pattern) {
    throw "Optimization decision audit assertion failed: unexpected $Description. Pattern: $Pattern"
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

function Write-OptimizationLog {
  param(
    [string]$PathValue,
    [switch]$MakeFirstRowPending
  )

  $Lines = [System.Collections.Generic.List[string]]::new()
  $Lines.Add("# Optimization Log") | Out-Null
  $Lines.Add("") | Out-Null
  $Lines.Add("## Prompt Optimization Class Decisions") | Out-Null
  $Lines.Add("") | Out-Null
  $Lines.Add("| Optimization class | Status | Measured effect | Risk | Relevant evidence | Notes |") | Out-Null
  $Lines.Add("| --- | --- | --- | --- | --- | --- |") | Out-Null
  for ($Index = 0; $Index -lt $OptimizationClasses.Count; $Index += 1) {
    $Class = $OptimizationClasses[$Index]
    if ($MakeFirstRowPending -and $Index -eq 0) {
      $Lines.Add("| $Class | pending measurement | Pending same-revision benchmark evidence | Pending risk | Pending evidence | Pending notes |") | Out-Null
    } else {
      $Lines.Add("| $Class | kept | Synthetic measured effect recorded for parser coverage | Synthetic low risk | benchmarks/raw/synthetic-$Index.json and benchmarks/reports/synthetic-$Index.md | Synthetic completed decision for audit parser regression |") | Out-Null
    }
  }
  Set-Content -LiteralPath $PathValue -Value ($Lines -join "`n") -Encoding ASCII
}

function Write-FinalRemovedSubsystemRegister {
  param([string]$PathValue)

  $Lines = @(
    "# Removed Or Disabled Subsystems",
    "",
    "Final register evidence is tied to synthetic completed optimization decisions for parser coverage.",
    "",
    "| Subsystem | Final status | Rationale | Regression risk | Current evidence |",
    "| --- | --- | --- | --- | --- |",
    "| Synthetic subsystem | kept | Synthetic rationale recorded for parser coverage | Low: synthetic test fixture | Synthetic official and trusted manifests |",
    "",
    "## Prompt Optimization Class Tracking",
    "",
    "| Optimization class | Tracking status |",
    "| --- | --- |",
    "| Synthetic class | Final measured decision recorded |",
    "",
    "## Subsystems Explicitly Kept For Now",
    "",
    "| Subsystem | Kept because | Notes |",
    "| --- | --- | --- |",
    "| V8 | Required by objective | Synthetic final evidence fixture |",
    "",
    "## Update Rule",
    "",
    "Keep this register synchronized with measured optimization decisions and official/trusted artifact paths."
  )
  Set-Content -LiteralPath $PathValue -Value ($Lines -join "`n") -Encoding ASCII
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$OldOptimizationLog = $env:THREE_BROWSER_TEST_OPTIMIZATION_LOG
$OldRemovedSubsystemsDoc = $env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC
$OldOfficialManifest = $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST
$OldTrustedManifest = $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST
$OldOverrideGate = $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES

try {
  Write-OptimizationLog -PathValue $FinalLog
  Write-OptimizationLog -PathValue $PendingLog -MakeFirstRowPending
  Write-FinalRemovedSubsystemRegister -PathValue $FinalRemovedSubsystems
  Set-Content -LiteralPath $OfficialManifest -Value "{}" -Encoding ASCII
  Set-Content -LiteralPath $TrustedManifest -Value "{}" -Encoding ASCII

  $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = "1"
  $env:THREE_BROWSER_TEST_OPTIMIZATION_LOG = $FinalLog
  $env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC = $FinalRemovedSubsystems
  $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OfficialManifest
  $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $TrustedManifest
  & (Join-Path $Root "scripts\audit_artifacts.ps1") -OptimizationOnly -Output $FinalAudit -FailOnIncomplete | Out-Null
  $FinalText = Get-Content -LiteralPath $FinalAudit -Raw
  Assert-Contains $FinalText "\| Optimization classes \| remove Chrome browser UI layer \| done \|" "completed optimization class row"
  Assert-Contains $FinalText "\| Optimization documentation \| Removed subsystem final decision register \| done \|" "completed removed-subsystem final-register row"
  Assert-NotContains $FinalText "\| Optimization classes \| .* \| pending \|" "pending optimization class row in synthetic completed audit"
  Assert-Contains $FinalText "- incomplete: 0" "zero incomplete rows for synthetic completed optimization audit"

  $env:THREE_BROWSER_TEST_OPTIMIZATION_LOG = $PendingLog
  $PendingFailed = $false
  try {
    & (Join-Path $Root "scripts\audit_artifacts.ps1") -OptimizationOnly -Output $PendingAudit -FailOnIncomplete | Out-Null
  } catch {
    $PendingFailed = $true
  }
  if (-not $PendingFailed) {
    throw "Optimization-only audit accepted a pending optimization decision row under -FailOnIncomplete."
  }
  $PendingText = Get-Content -LiteralPath $PendingAudit -Raw
  Assert-Contains $PendingText "\| Optimization classes \| remove Chrome browser UI layer \| pending \|" "pending optimization class row"
  Assert-Contains $PendingText "decision incomplete" "pending decision explanation"
} finally {
  if ($null -eq $OldOptimizationLog) {
    Remove-Item Env:\THREE_BROWSER_TEST_OPTIMIZATION_LOG -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_OPTIMIZATION_LOG = $OldOptimizationLog
  }
  if ($null -eq $OldRemovedSubsystemsDoc) {
    Remove-Item Env:\THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_REMOVED_SUBSYSTEMS_DOC = $OldRemovedSubsystemsDoc
  }
  if ($null -eq $OldOfficialManifest) {
    Remove-Item Env:\THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST = $OldOfficialManifest
  }
  if ($null -eq $OldTrustedManifest) {
    Remove-Item Env:\THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST = $OldTrustedManifest
  }
  if ($null -eq $OldOverrideGate) {
    Remove-Item Env:\THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES -ErrorAction SilentlyContinue
  } else {
    $env:THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES = $OldOverrideGate
  }
  if (Test-Path -LiteralPath $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Optimization decision audit keeps pending classes incomplete and accepts synthetic completed decisions."

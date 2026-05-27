[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$Patch = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
$PatchSeries = @(
  "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch",
  "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"
)
$TempDir = Join-Path $Root "benchmarks\tmp\patch-state-audit-test"
$TempManifest = Join-Path $TempDir "prebuild-environment-already-applied.json"
$TempAudit = Join-Path $TempDir "patch-state-checklist.md"

function Test-GitApply {
  param(
    [string]$PatchPath = $Patch,
    [switch]$Reverse
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Arguments = @("-C", $Src, "apply")
    if ($Reverse) {
      $Arguments += "--reverse"
    }
    $Arguments += @("--check", $PatchPath)
    $null = (& git @Arguments 2>$null)
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Get-PatchState {
  $States = @($PatchSeries | ForEach-Object {
      $PatchPath = Join-Path $Root $_
      [pscustomobject]@{
        Path = $_
        Applies = Test-GitApply -PatchPath $PatchPath
        AlreadyApplied = Test-GitApply -PatchPath $PatchPath -Reverse
      }
    })
  return [pscustomobject]@{
    Applies = @($States | Where-Object { -not $_.Applies }).Count -eq 0
    AlreadyApplied = @($States | Where-Object { $_.AlreadyApplied }).Count -gt 0
    Blocked = @($States | Where-Object { -not $_.Applies -and -not $_.AlreadyApplied }).Count -gt 0
    States = $States
  }
}

$InitialState = Get-PatchState
if ($InitialState.Blocked) {
  $BlockedPatches = @($InitialState.States | Where-Object { -not $_.Applies -and -not $_.AlreadyApplied } | ForEach-Object { $_.Path }) -join ", "
  throw "Patch-state audit test requires each viewer patch series entry to either apply cleanly or already be applied. Blocked: $BlockedPatches"
}

if (Test-Path -LiteralPath $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
  $ExpectedRevision = (Get-Content (Join-Path $Root ".chromium_revision") -Raw).Trim()
  $OldTestUpstreamHeadRevision = $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION
  $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION = $ExpectedRevision
  try {
    $null = & (Join-Path $Root "scripts\write_environment_manifest.ps1") `
      -Output "benchmarks\tmp\patch-state-audit-test\prebuild-environment-already-applied.json" `
      -TestAssumeViewerPatchAlreadyApplied *>&1
  } finally {
    $env:THREE_BROWSER_TEST_UPSTREAM_HEAD_REVISION = $OldTestUpstreamHeadRevision
  }

  $Manifest = Get-Content -LiteralPath $TempManifest -Raw | ConvertFrom-Json
  if (-not $Manifest.patch.already_applied) {
    throw "Expected manifest to record patch.already_applied=true under the test hook."
  }
  if (@($Manifest.patch_series).Count -lt 2) {
    throw "Expected manifest to record the full viewer patch series."
  }
  if (-not (@($Manifest.checks | Where-Object { $_.name -eq "viewer_patch_series_state" -and $_.ok }).Count)) {
    throw "Expected manifest checks to record viewer_patch_series_state=true under the test hook."
  }
  if ($Manifest.patch.applies_cleanly) {
    throw "Expected manifest to record patch.applies_cleanly=false under the test hook."
  }
  if (-not $Manifest.environment.test_assumed_viewer_patch_already_applied) {
    throw "Expected manifest to record the patch-state test hook."
  }

  $null = & (Join-Path $Root "scripts\audit_artifacts.ps1") `
    -Output "benchmarks\tmp\patch-state-audit-test\patch-state-checklist.md" `
    -EnvironmentManifest "benchmarks\tmp\patch-state-audit-test\prebuild-environment-already-applied.json" `
    -PatchStateOnly `
    -TestAssumeViewerPatchAlreadyApplied *>&1

  $AuditText = Get-Content -LiteralPath $TempAudit -Raw
  if ($AuditText -notmatch "Minimal viewer entrypoint patch applies or is already applied") {
    throw "Expected audit checklist to contain the patch-state row."
  }
  if ($AuditText -notmatch "patch is already applied") {
    throw "Expected audit checklist to accept the already-applied patch state."
  }
  if ($AuditText -notmatch "already-applied viewer patch") {
    throw "Expected audit checklist to accept already-applied patch state from the environment manifest."
  }
} finally {
  $FinalState = Get-PatchState
  if ($InitialState.Applies -ne $FinalState.Applies -or $InitialState.AlreadyApplied -ne $FinalState.AlreadyApplied) {
    throw "Patch-state audit test changed the src patch state."
  }
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

Write-Host "Patch-state audit test passed without mutating src."

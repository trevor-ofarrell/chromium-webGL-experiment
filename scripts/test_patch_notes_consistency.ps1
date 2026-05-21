[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$PatchPath = "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
$PatchNotesPath = "chromium_patches\minimal_viewer_entrypoint.md"
$PatchReadmePath = "chromium_patches\README.md"
$TrustedFlagsPath = "docs\trusted_content_flags.md"

$ViewerSwitches = @(
  "--viewer-app-url",
  "--viewer-trusted-content",
  "--viewer-block-external-navigation",
  "--viewer-force-angle-backend",
  "--viewer-aggressive-gpu",
  "--viewer-in-process-gpu",
  "--viewer-single-process",
  "--viewer-relaxed-webgl-validation",
  "--viewer-disable-unneeded-blink-features",
  "--viewer-direct-gpu-presentation"
)

$PatchFiles = @(
  "content/shell/app/shell_main_delegate.cc",
  "content/shell/browser/shell.cc",
  "content/shell/browser/shell_browser_main_parts.cc",
  "content/shell/browser/shell_content_browser_client.cc",
  "content/shell/common/shell_switches.h"
)

$PatchBehaviorTerms = @(
  "Content shell toolbar UI is hidden",
  "New-window and tab creation are denied",
  "navigation throttle",
  "confines URL launches",
  "viewer file or files beneath the viewer app directory",
  "THREE_VIEWER_RESULT",
  "reserved gates"
)

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path $Resolved)) {
    throw "Required file not found: $PathValue"
  }
  return Get-Content $Resolved -Raw
}

function Assert-ContainsLiteral {
  param(
    [string]$Label,
    [string]$Text,
    [string]$Term
  )
  if ($Text -notmatch [regex]::Escape($Term)) {
    throw "$Label missing required term: $Term"
  }
}

function Get-PatchDiffPaths {
  param([string]$Text)
  return @([regex]::Matches($Text, '(?m)^diff --git a/(\S+) b/(\S+)$') | ForEach-Object {
    $Left = $_.Groups[1].Value
    $Right = $_.Groups[2].Value
    if ($Left -ne $Right) {
      throw "Patch diff path mismatch: a/$Left b/$Right"
    }
    $Left
  })
}

function Assert-SameSet {
  param(
    [string]$Label,
    [string[]]$Actual,
    [string[]]$Expected
  )
  $Missing = @($Expected | Where-Object { $Actual -notcontains $_ })
  $Unexpected = @($Actual | Where-Object { $Expected -notcontains $_ })
  if ($Missing.Count -gt 0 -or $Unexpected.Count -gt 0) {
    throw "$Label mismatch. Missing=[$($Missing -join ', ')] Unexpected=[$($Unexpected -join ', ')]"
  }
}

$PatchText = Read-RepoFile $PatchPath
$PatchNotes = Read-RepoFile $PatchNotesPath
$PatchReadme = Read-RepoFile $PatchReadmePath
$TrustedFlags = Read-RepoFile $TrustedFlagsPath

Assert-SameSet "patch diff source files" (Get-PatchDiffPaths $PatchText) $PatchFiles

foreach ($PathValue in $PatchFiles) {
  Assert-ContainsLiteral $PatchNotesPath $PatchNotes $PathValue
}

foreach ($Switch in $ViewerSwitches) {
  Assert-ContainsLiteral $PatchPath $PatchText ($Switch.TrimStart("-"))
  Assert-ContainsLiteral $PatchNotesPath $PatchNotes $Switch
  Assert-ContainsLiteral $TrustedFlagsPath $TrustedFlags $Switch
}

foreach ($Term in $PatchBehaviorTerms) {
  Assert-ContainsLiteral $PatchNotesPath $PatchNotes $Term
}

Assert-ContainsLiteral $PatchReadmePath $PatchReadme 'Baseline target: `//content/shell:content_shell`'
Assert-ContainsLiteral $PatchReadmePath $PatchReadme 'Unsafe runtime changes stay behind viewer-specific switches and `--viewer-trusted-content`.'
Assert-ContainsLiteral $PatchReadmePath $PatchReadme 'Any subsystem removal or retained experiment must be reflected in `docs/removed_subsystems.md` and `docs/optimization_log.md`.'
Assert-ContainsLiteral $PatchReadmePath $PatchReadme "Official comparison manifest"
Assert-ContainsLiteral $PatchNotesPath $PatchNotes 'Official stock/fork comparison artifacts are recorded under `benchmarks/reports/official-comparison-manifest.json`.'

Write-Host "Patch notes consistency checks passed for viewer switches, source files, behavior notes, and patch policy."

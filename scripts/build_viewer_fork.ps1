[CmdletBinding()]
param(
  [string]$OutDir = "out\ReleaseViewerDefault",
  [string]$ArgsFile = "build\gn_args\fork_safe_content_shell.gn",
  [string]$Target = "content_shell",
  [int]$Jobs = 0,
  [switch]$ApplyPatch,
  [switch]$OverwriteArgs
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$PatchSeries = @(
  "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch",
  "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"
)

foreach ($PatchRelativePath in $PatchSeries) {
  $PatchPath = Join-Path $Root $PatchRelativePath
  if (-not (Test-Path $PatchPath)) {
    throw "Viewer patch not found: $PatchPath"
  }
}

function Invoke-Checked {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath exited with code $LASTEXITCODE"
  }
}

function Test-GitApply {
  param(
    [string]$Repo,
    [string]$PatchPath,
    [switch]$Reverse
  )

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Arguments = @("-C", $Repo, "apply")
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

& (Join-Path $Root "scripts\check_prereqs.ps1")
if ($LASTEXITCODE -ne 0) {
  throw "Prerequisite check failed. Fix host prerequisites before applying or building the viewer fork."
}

if ($ApplyPatch) {
  foreach ($PatchRelativePath in $PatchSeries) {
    $PatchPath = Join-Path $Root $PatchRelativePath
    if (Test-GitApply $Src $PatchPath) {
      Invoke-Checked "git" @("-C", $Src, "apply", $PatchPath)
      Write-Host "Applied viewer patch $PatchRelativePath."
    } elseif (Test-GitApply $Src $PatchPath -Reverse) {
      Write-Host "Viewer patch is already applied: $PatchRelativePath"
    } else {
      throw "Viewer patch cannot be applied cleanly and is not already applied: $PatchRelativePath"
    }
  }
}

$BuildScript = Join-Path $Root "scripts\build_chromium.ps1"
if ($Jobs -gt 0) {
  & $BuildScript -OutDir $OutDir -Target $Target -ArgsFile $ArgsFile -Jobs $Jobs -AllowViewerPatchApplied -OverwriteArgs:$OverwriteArgs
} else {
  & $BuildScript -OutDir $OutDir -Target $Target -ArgsFile $ArgsFile -AllowViewerPatchApplied -OverwriteArgs:$OverwriteArgs
}
if ($LASTEXITCODE -ne 0) {
  throw "$BuildScript exited with code $LASTEXITCODE"
}

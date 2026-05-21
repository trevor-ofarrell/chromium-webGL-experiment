[CmdletBinding()]
param(
  [string]$OutDir = "out\ReleaseViewerDefault",
  [string]$ArgsFile = "build\gn_args\fork_safe_content_shell.gn",
  [int]$Jobs = 0,
  [switch]$ApplyPatch
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$Patch = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"

if (-not (Test-Path $Patch)) {
  throw "Viewer patch not found: $Patch"
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
  if (Test-GitApply $Src $Patch) {
    Invoke-Checked "git" @("-C", $Src, "apply", $Patch)
  } elseif (Test-GitApply $Src $Patch -Reverse) {
    Write-Host "Viewer patch is already applied."
  } else {
    throw "Viewer patch cannot be applied cleanly and is not already applied."
  }
}

$BuildScript = Join-Path $Root "scripts\build_chromium.ps1"
if ($Jobs -gt 0) {
  & $BuildScript -OutDir $OutDir -Target "content_shell" -ArgsFile $ArgsFile -Jobs $Jobs
} else {
  & $BuildScript -OutDir $OutDir -Target "content_shell" -ArgsFile $ArgsFile
}
if ($LASTEXITCODE -ne 0) {
  throw "$BuildScript exited with code $LASTEXITCODE"
}

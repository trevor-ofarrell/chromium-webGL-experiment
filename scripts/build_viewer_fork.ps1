[CmdletBinding()]
param(
  [string]$OutDir = "out\ReleaseViewerDefault",
  [string]$ArgsFile = "build\gn_args\fork_safe_content_shell.gn",
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

& (Join-Path $Root "scripts\check_prereqs.ps1")
if ($LASTEXITCODE -ne 0) {
  throw "Prerequisite check failed. Fix host prerequisites before applying or building the viewer fork."
}

if ($ApplyPatch) {
  git -C $Src apply --check $Patch 2>$null
  if ($LASTEXITCODE -eq 0) {
    Invoke-Checked "git" @("-C", $Src, "apply", $Patch)
  } else {
    git -C $Src apply --reverse --check $Patch 2>$null
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Viewer patch is already applied."
    } else {
      throw "Viewer patch cannot be applied cleanly and is not already applied."
    }
  }
}

& (Join-Path $Root "scripts\build_chromium.ps1") -OutDir $OutDir -Target content_shell -ArgsFile $ArgsFile

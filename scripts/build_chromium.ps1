[CmdletBinding()]
param(
  [string]$OutDir = "out\ReleaseBaseline",
  [string]$Target = "content_shell",
  [string]$ArgsFile = "build\gn_args\baseline_content_shell.gn",
  [int]$Jobs = 0,
  [switch]$OverwriteArgs,
  [switch]$GenOnly,
  [switch]$AllowViewerPatchApplied,
  [switch]$SkipPrereqCheck
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$DepotTools = Join-Path $Root "tools\depot_tools"
$SourceArgs = Join-Path $Root $ArgsFile
$CommonBuildPatchSeries = @(
  "chromium_patches\0000-draft-win-clang-build-workarounds.patch"
)
$PatchSeries = @(
  "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch",
  "chromium_patches\0002-draft-webgpu-queue-trace-attribution.patch"
)

if (-not (Test-Path $Src)) {
  throw "Chromium checkout not found at $Src. Run .\scripts\bootstrap_chromium.ps1 first."
}

if ($Target -like "content_shell*" -and -not (Test-Path (Join-Path $Src "content\shell\BUILD.gn"))) {
  throw "Chromium checkout is incomplete: content\shell\BUILD.gn is missing. Resume .\scripts\bootstrap_chromium.ps1 before building $Target."
}

if (-not (Test-Path $DepotTools)) {
  throw "depot_tools not found at $DepotTools. Run .\scripts\bootstrap_chromium.ps1 first."
}

if (-not (Test-Path $SourceArgs)) {
  throw "GN args file not found: $SourceArgs"
}

$env:PATH = "$DepotTools;$env:PATH"
if ($IsWindows -or $env:OS -eq "Windows_NT") {
  if (-not $env:DEPOT_TOOLS_WIN_TOOLCHAIN) {
    $env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
  }
  $DefaultVs2022 = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
  if (-not $env:vs2022_install -and (Test-Path $DefaultVs2022)) {
    $env:vs2022_install = $DefaultVs2022
  }
}

if (-not $SkipPrereqCheck) {
  & (Join-Path $Root "scripts\check_prereqs.ps1")
  if ($LASTEXITCODE -ne 0) {
    throw "Prerequisite check failed. Fix host prerequisites before building Chromium."
  }
}

$OutAbs = Join-Path $Src $OutDir
$ArgsDest = Join-Path $OutAbs "args.gn"

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

function Get-FileHashString {
  param([string]$PathValue)
  if (-not (Test-Path $PathValue)) {
    return ""
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
}

function Get-GitRevision {
  param([string]$RepoPath)
  $Revision = (& git -C $RepoPath rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $Revision) {
    throw "Unable to read git revision from $RepoPath"
  }
  return $Revision
}

function Test-ViewerPatchApplyState {
  param(
    [string]$PatchPath = (Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"),
    [switch]$Reverse
  )

  if (-not (Test-Path -LiteralPath $PatchPath)) {
    return $false
  }

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

function Get-PatchSeriesState {
  return @($PatchSeries | ForEach-Object {
    $PatchRelativePath = $_
    $PatchPath = Join-Path $Root $PatchRelativePath
    [pscustomobject]@{
      path = $PatchRelativePath
      exists = Test-Path -LiteralPath $PatchPath -PathType Leaf
      sha256 = Get-FileHashString $PatchPath
      applies_cleanly = [bool](Test-ViewerPatchApplyState -PatchPath $PatchPath)
      already_applied = [bool](Test-ViewerPatchApplyState -PatchPath $PatchPath -Reverse)
    }
  })
}

function Get-CommonBuildPatchSeriesState {
  return @($CommonBuildPatchSeries | ForEach-Object {
    $PatchRelativePath = $_
    $PatchPath = Join-Path $Root $PatchRelativePath
    [pscustomobject]@{
      path = $PatchRelativePath
      exists = Test-Path -LiteralPath $PatchPath -PathType Leaf
      sha256 = Get-FileHashString $PatchPath
      applies_cleanly = [bool](Test-ViewerPatchApplyState -PatchPath $PatchPath)
      already_applied = [bool](Test-ViewerPatchApplyState -PatchPath $PatchPath -Reverse)
    }
  })
}

function Ensure-CommonBuildPatchSeriesApplied {
  foreach ($PatchRelativePath in $CommonBuildPatchSeries) {
    $PatchPath = Join-Path $Root $PatchRelativePath
    if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
      throw "Common Chromium build patch not found: $PatchPath"
    }

    if (Test-ViewerPatchApplyState -PatchPath $PatchPath) {
      Invoke-Checked "git" @("-C", $Src, "apply", $PatchPath)
      Write-Host "Applied common Chromium build patch $PatchRelativePath."
    } elseif (Test-ViewerPatchApplyState -PatchPath $PatchPath -Reverse) {
      Write-Host "Common Chromium build patch is already applied: $PatchRelativePath"
    } else {
      throw "Common Chromium build patch cannot be applied cleanly and is not already applied: $PatchRelativePath"
    }
  }
}

function Test-BaselineBuildProfile {
  $BaselineArgs = [System.IO.Path]::GetFullPath((Join-Path $Root "build\gn_args\baseline_content_shell.gn"))
  $SourceArgsFullPath = [System.IO.Path]::GetFullPath($SourceArgs)
  if ($SourceArgsFullPath.Equals($BaselineArgs, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $OutDirNormalized = $OutDir -replace '/', '\'
  return $OutDirNormalized -match '(^|\\)ReleaseBaseline($|\\)'
}

function Assert-StockBaselineSourceUnpatched {
  if ($AllowViewerPatchApplied -or -not (Test-BaselineBuildProfile)) {
    return
  }

  $PatchStates = @(Get-PatchSeriesState)
  $BlockedPatchStates = @($PatchStates | Where-Object { -not $_.exists -or (-not $_.applies_cleanly -and -not $_.already_applied) })
  if ($BlockedPatchStates.Count -gt 0) {
    $BlockedPatchList = @($BlockedPatchStates | ForEach-Object { $_.path }) -join ", "
    throw "Cannot audit viewer patch series state before stock baseline build: $BlockedPatchList. Restore the patch files or fix the patch/source state before collecting baseline evidence."
  }

  $AppliedPatchStates = @($PatchStates | Where-Object { $_.already_applied })
  if ($AppliedPatchStates.Count -eq 0) {
    return
  }

  $AppliedPatchList = @($AppliedPatchStates | ForEach-Object { $_.path }) -join ", "
  throw "Cannot build stock baseline while viewer patch series entries are already applied to src: $AppliedPatchList. Revert the viewer patch series before building the baseline, or pass -AllowViewerPatchApplied only for non-evidence diagnostics."
}

function Write-BuildProvenance {
  param([string]$StartedAt)

  $ExecutableName = if ($Target -match "\.exe$") { $Target } else { "$Target.exe" }
  $ExecutablePath = Join-Path $OutAbs $ExecutableName
  if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
    throw "Expected build output was not produced: $ExecutablePath"
  }

  $ProvenancePath = Join-Path $OutAbs "three_browser_build_provenance.json"
  $Provenance = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    build_started_at = $StartedAt
    chromium_revision = Get-GitRevision $Src
    out_dir = $OutDir
    target = $Target
    target_artifact = $ExecutablePath
    target_artifact_sha256 = Get-FileHashString $ExecutablePath
    args_gn = $ArgsDest
    args_gn_sha256 = Get-FileHashString $ArgsDest
    source_args = $SourceArgs
    source_args_sha256 = Get-FileHashString $SourceArgs
    build_jobs = [int]$Jobs
    allow_viewer_patch_applied = [bool]$AllowViewerPatchApplied
    baseline_source_guard_enabled = [bool]((Test-BaselineBuildProfile) -and -not $AllowViewerPatchApplied)
    viewer_patch_applies_cleanly = [bool](Test-ViewerPatchApplyState)
    viewer_patch_already_applied = [bool](Test-ViewerPatchApplyState -Reverse)
    viewer_patch_series = Get-PatchSeriesState
    common_build_patch_series = Get-CommonBuildPatchSeriesState
  }
  $Provenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ProvenancePath -Encoding UTF8
  Write-Host "Wrote build provenance $ProvenancePath"
}

New-Item -ItemType Directory -Path $OutAbs -Force | Out-Null
if (-not (Test-Path $ArgsDest)) {
  Copy-Item -LiteralPath $SourceArgs -Destination $ArgsDest
} else {
  $SourceHash = Get-FileHashString $SourceArgs
  $DestHash = Get-FileHashString $ArgsDest
  if ($SourceHash -ne $DestHash) {
    if ($OverwriteArgs) {
      Copy-Item -LiteralPath $SourceArgs -Destination $ArgsDest -Force
      Write-Host "Overwrote $ArgsDest with $SourceArgs for a reproducible build."
    } else {
      throw "Existing GN args differ from $SourceArgs at $ArgsDest. Remove the output args.gn or pass -OverwriteArgs to refresh it."
    }
  }
}

Assert-StockBaselineSourceUnpatched
Ensure-CommonBuildPatchSeriesApplied

$BuildStartedAt = (Get-Date).ToUniversalTime().ToString("o")
Push-Location $Src
try {
  Invoke-Checked "gn" @("gen", $OutDir)
  if ($GenOnly) {
    Write-Host "Generated GN files for $OutDir without invoking autoninja."
    return
  }
  $NinjaArgs = @("-C", $OutDir)
  if ($Jobs -gt 0) {
    $NinjaArgs += @("-j", "$Jobs")
  }
  $NinjaArgs += $Target
  Invoke-Checked "autoninja" $NinjaArgs
  Write-BuildProvenance -StartedAt $BuildStartedAt
} finally {
  Pop-Location
}

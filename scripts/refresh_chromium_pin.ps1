[CmdletBinding()]
param(
  [string]$Revision = "",
  [switch]$SkipSync,
  [switch]$SkipHooks,
  [switch]$SkipGnGen,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Src = Join-Path $Root "src"
$RevisionFile = Join-Path $Root ".chromium_revision"
$PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"
$PinRefreshManifest = Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json"
$SourceInvestigationDoc = Join-Path $Root "docs\source_investigation.md"

function Format-Command {
  param([object[]]$Command)
  return ($Command | ForEach-Object {
    $Text = [string]$_
    if ($Text -match "\s") {
      return '"' + ($Text -replace '"', '\"') + '"'
    }
    return $Text
  }) -join " "
}

function Invoke-Step {
  param(
    [string]$Name,
    [object[]]$Command
  )

  Write-Host ""
  Write-Host "== $Name =="
  Write-Host (Format-Command $Command)
  if ($DryRun) {
    return
  }

  $Executable = [string]$Command[0]
  $Arguments = @($Command | Select-Object -Skip 1)
  if ([System.IO.Path]::GetExtension($Executable) -ieq ".ps1") {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Executable @Arguments
  } else {
    & $Executable @Arguments
  }
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE"
  }
}

function Get-UpstreamHeadRevision {
  $ProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $ProcessInfo.FileName = "git"
  $ProcessInfo.Arguments = "-C `"$Src`" ls-remote origin HEAD"
  $ProcessInfo.RedirectStandardOutput = $true
  $ProcessInfo.RedirectStandardError = $true
  $ProcessInfo.UseShellExecute = $false
  $ProcessInfo.CreateNoWindow = $true

  $Process = [System.Diagnostics.Process]::new()
  $Process.StartInfo = $ProcessInfo
  try {
    if (-not $Process.Start()) {
      throw "Unable to start git ls-remote."
    }
    if (-not $Process.WaitForExit(60000)) {
      try {
        $Process.Kill()
      } catch {
      }
      throw "Timed out reading Chromium origin HEAD."
    }
    if ($Process.ExitCode -ne 0) {
      $ErrorText = $Process.StandardError.ReadToEnd()
      throw "git ls-remote origin HEAD failed: $ErrorText"
    }
    $OutputText = $Process.StandardOutput.ReadToEnd()
  } finally {
    $Process.Dispose()
  }

  $FirstLine = @($OutputText -split "`r?`n" | Where-Object { $_ })[0]
  $Parts = $FirstLine -split "\s+"
  if ($Parts.Count -lt 1 -or $Parts[0] -notmatch "^[0-9a-f]{40}$") {
    throw "Unable to parse Chromium origin HEAD from: $FirstLine"
  }
  return $Parts[0].Trim()
}

function Assert-CleanChromiumCheckout {
  $Status = (& git -C $Src status --porcelain)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect Chromium checkout state."
  }
  if ($Status) {
    throw "Refusing to refresh Chromium pin while src has local changes. Preserve or revert those changes first.`n$($Status -join "`n")"
  }
}

function Write-PinRefreshManifest {
  $ReportsDir = Split-Path -Parent $PinRefreshManifest
  New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null
  $Manifest = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    target_revision = $Revision
    previous_revision = $PreviousRevision
    selected_from_upstream_head = [bool]$SelectedFromUpstreamHead
    selected_at = $SelectedAt
    source = $RevisionSource
    skip_sync = [bool]$SkipSync
    skip_hooks = [bool]$SkipHooks
    skip_gn_gen = [bool]$SkipGnGen
  }
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PinRefreshManifest -Encoding UTF8
}

function Update-SourceInvestigationVerification {
  if (-not (Test-Path -LiteralPath $SourceInvestigationDoc)) {
    throw "Source investigation document not found: $SourceInvestigationDoc"
  }

  $OriginalText = Get-Content -LiteralPath $SourceInvestigationDoc -Raw
  $Pattern = 'Last local verification was at pinned Chromium revision `([0-9a-f]{40})`'
  $Matches = [regex]::Matches($OriginalText, $Pattern)
  if ($Matches.Count -ne 1) {
    throw "Source investigation document must contain exactly one verification revision marker."
  }

  $Replacement = "Last local verification was at pinned Chromium revision ``$Revision``"
  $RevisionRegex = [regex]$Pattern
  $UpdatedText = $RevisionRegex.Replace($OriginalText, $Replacement, 1)
  $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

  try {
    [System.IO.File]::WriteAllText($SourceInvestigationDoc, $UpdatedText, $Utf8NoBom)
    & (Join-Path $Root "scripts\test_source_investigation_paths.ps1")
    if ($LASTEXITCODE -ne 0) {
      throw "Source investigation path verification failed with exit code $LASTEXITCODE."
    }
  } catch {
    [System.IO.File]::WriteAllText($SourceInvestigationDoc, $OriginalText, $Utf8NoBom)
    throw "Updated Chromium pin, but source investigation verification failed; restored previous docs\source_investigation.md marker. $($_.Exception.Message)"
  }
}

if (-not (Test-Path $Src)) {
  throw "Chromium checkout not found at $Src. Run .\scripts\bootstrap_chromium.ps1 first."
}

$PreviousRevision = if (Test-Path $RevisionFile) { (Get-Content -LiteralPath $RevisionFile -Raw).Trim() } else { "" }
$SelectedAt = (Get-Date).ToUniversalTime().ToString("o")
$SelectedFromUpstreamHead = $false
$RevisionSource = "explicit -Revision"
if (-not $Revision) {
  $Revision = Get-UpstreamHeadRevision
  $SelectedFromUpstreamHead = $true
  $RevisionSource = "origin HEAD"
}

if ($Revision -notmatch "^[0-9a-f]{40}$") {
  throw "Revision must be a 40-character Chromium commit SHA: $Revision"
}

Write-Host "Target Chromium revision: $Revision"

if (-not $DryRun) {
  Assert-CleanChromiumCheckout
}

Invoke-Step "fetch Chromium revision" @("git", "-C", $Src, "fetch", "origin", $Revision)
Invoke-Step "checkout Chromium revision" @("git", "-C", $Src, "checkout", "--detach", $Revision)

Write-Host ""
Write-Host "== update .chromium_revision =="
Write-Host "Set-Content $RevisionFile $Revision"
if (-not $DryRun) {
  Set-Content -LiteralPath $RevisionFile -Value ($Revision + "`n") -Encoding ASCII
}

if (-not $SkipSync) {
  $BootstrapCommand = @((Join-Path $Root "scripts\bootstrap_chromium.ps1"), "-Revision", $Revision)
  if ($SkipHooks) {
    $BootstrapCommand += "-SkipHooks"
  }
  Invoke-Step "sync Chromium dependencies" $BootstrapCommand
} else {
  Write-Host ""
  Write-Host "== sync Chromium dependencies =="
  Write-Host "Skipped by -SkipSync."
}

if (-not $SkipGnGen) {
  Invoke-Step "GN gen baseline content shell" @(
    (Join-Path $Root "scripts\build_chromium.ps1"),
    "-OutDir", "out\ReleaseBaseline",
    "-Target", "content_shell",
    "-ArgsFile", "build\gn_args\baseline_content_shell.gn",
    "-SkipPrereqCheck",
    "-GenOnly"
  )
  Invoke-Step "GN gen fork default content shell" @(
    (Join-Path $Root "scripts\build_chromium.ps1"),
    "-OutDir", "out\ReleaseViewerDefault",
    "-Target", "content_shell",
    "-ArgsFile", "build\gn_args\fork_safe_content_shell.gn",
    "-SkipPrereqCheck",
    "-GenOnly"
  )
  Invoke-Step "GN gen fork trusted aggressive content shell" @(
    (Join-Path $Root "scripts\build_chromium.ps1"),
    "-OutDir", "out\ReleaseViewerTrustedAggressive",
    "-Target", "content_shell",
    "-ArgsFile", "build\gn_args\fork_trusted_aggressive.gn",
    "-SkipPrereqCheck",
    "-GenOnly"
  )
} else {
  Write-Host ""
  Write-Host "== GN generation =="
  Write-Host "Skipped by -SkipGnGen."
}

Write-Host ""
Write-Host "== record Chromium pin refresh provenance =="
Write-Host "Set-Content $PinRefreshManifest target=$Revision source=$RevisionSource selected_from_upstream_head=$SelectedFromUpstreamHead"
if (-not $DryRun) {
  Write-PinRefreshManifest
}

Invoke-Step "write prebuild environment manifest" @(
  (Join-Path $Root "scripts\write_environment_manifest.ps1")
)
Invoke-Step "check viewer patch applies" @(
  "git",
  "-C",
  $Src,
  "apply",
  "--check",
  $PatchPath
)

Write-Host ""
Write-Host "== restamp source investigation verification =="
Write-Host "Update $SourceInvestigationDoc to revision $Revision and validate documented Chromium source paths"
if (-not $DryRun) {
  Update-SourceInvestigationVerification
}

Write-Host ""
Write-Host "Chromium pin refresh complete. Next:"
Write-Host "  .\scripts\verify_prebuild.ps1 -AllowMissingAtl"

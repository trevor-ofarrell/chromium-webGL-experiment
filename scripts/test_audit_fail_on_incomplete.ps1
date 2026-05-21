[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\audit-fail-on-incomplete-test"
$Output = Join-Path $TempDir "prompt-to-artifact-checklist.md"

if (Test-Path $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$FailedAsExpected = $false
$Message = ""
$OldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$SkipEnvNames = @(
  "THREE_BROWSER_SKIP_MANIFEST_PACKAGE_AUDIT_TEST",
  "THREE_BROWSER_SKIP_MANIFEST_ARTIFACT_PATH_AUDIT_TEST",
  "THREE_BROWSER_SKIP_TRUSTED_MANIFEST_PROVENANCE_AUDIT_TEST",
  "THREE_BROWSER_SKIP_TRUSTED_MANIFEST_REQUIRED_OPTIONS_AUDIT_TEST",
  "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_AGGRESSIVE_AUDIT_TEST",
  "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_PROVENANCE_AUDIT_TEST",
  "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_WEBGPU_AUDIT_TEST",
  "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_REPORT_AUDIT_TEST",
  "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_RUNTIME_AUDIT_TEST",
  "THREE_BROWSER_SKIP_OFFICIAL_MANIFEST_TRACE_AUDIT_TEST"
)
$OldEnvValues = @{}
$TestOverrideEnv = @{
  "THREE_BROWSER_ALLOW_TEST_MANIFEST_OVERRIDES" = "1"
  "THREE_BROWSER_TEST_OFFICIAL_COMPARISON_MANIFEST" = (Join-Path $TempDir "missing-official-comparison-manifest.json")
  "THREE_BROWSER_TEST_TRUSTED_EXPERIMENT_MATRIX_MANIFEST" = (Join-Path $TempDir "missing-trusted-experiment-matrix-manifest.json")
  "THREE_BROWSER_TEST_OFFICIAL_WEBGL2_REPORT" = (Join-Path $TempDir "missing-official-webgl2-comparison.md")
  "THREE_BROWSER_TEST_OFFICIAL_WEBGPU_REPORT" = (Join-Path $TempDir "missing-official-webgpu-comparison.md")
}
try {
  foreach ($Name in $SkipEnvNames) {
    $OldEnvValues[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    Set-Item "Env:\$Name" "1"
  }
  foreach ($Name in $TestOverrideEnv.Keys) {
    $OldEnvValues[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    Set-Item "Env:\$Name" $TestOverrideEnv[$Name]
  }

  $OutputText = & (Join-Path $Root "scripts\audit_artifacts.ps1") -Output $Output -FailOnIncomplete *>&1
  $Message = ($OutputText | ForEach-Object { [string]$_ }) -join " "
  if ($LASTEXITCODE -ne 0) {
    $FailedAsExpected = $true
  }
} catch {
  $FailedAsExpected = $true
  $Message = $_.Exception.Message
} finally {
  foreach ($Name in @($SkipEnvNames + @($TestOverrideEnv.Keys))) {
    if ($null -eq $OldEnvValues[$Name]) {
      Remove-Item "Env:\$Name" -ErrorAction SilentlyContinue
    } else {
      Set-Item "Env:\$Name" $OldEnvValues[$Name]
    }
  }
  $ErrorActionPreference = $OldErrorActionPreference
}

if (-not $FailedAsExpected) {
  throw "Artifact audit final gate did not fail despite incomplete required artifacts. Output: $Message"
}
if ($Message -notmatch "incomplete") {
  throw "Artifact audit final gate failed without explaining incomplete artifacts. Output: $Message"
}
if (-not (Test-Path -LiteralPath $Output)) {
  throw "Artifact audit final gate did not write its checklist before failing."
}

$Checklist = Get-Content -LiteralPath $Output -Raw
if ($Checklist -notmatch "Stock baseline content_shell binary" -or $Checklist -notmatch "Official comparison manifest") {
  throw "Artifact audit final gate checklist did not include expected missing official evidence rows."
}
if ($Checklist -notmatch "Observed upstream Chromium HEAD freshness") {
  throw "Artifact audit final gate checklist did not include the upstream Chromium HEAD freshness row."
}
if ($Checklist -notmatch "Chromium pin refresh provenance") {
  throw "Artifact audit final gate checklist did not include the Chromium pin refresh provenance row."
}
if ($Checklist -notmatch "Stock baseline content_shell binary.*(Missing: src\\out\\ReleaseBaseline\\content_shell\.exe|sha256=|not a non-empty executable file)") {
  throw "Artifact audit final gate checklist did not include strict stock binary evidence."
}
if ($Checklist -notmatch "Fork default content_shell binary.*(Missing: src\\out\\ReleaseViewerDefault\\content_shell\.exe|sha256=|not a non-empty executable file)") {
  throw "Artifact audit final gate checklist did not include strict fork binary evidence."
}
if ($Checklist -notmatch "missing-official-comparison-manifest\.json") {
  throw "Artifact audit final gate checklist did not include the forced missing official comparison manifest."
}
if ($Checklist -notmatch "missing-trusted-experiment-matrix-manifest\.json") {
  throw "Artifact audit final gate checklist did not include the forced missing trusted matrix manifest."
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Artifact audit -FailOnIncomplete rejects the current incomplete artifact set."

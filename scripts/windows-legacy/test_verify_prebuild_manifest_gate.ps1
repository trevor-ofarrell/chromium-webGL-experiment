[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$VerifierPath = Join-Path $Root "scripts\verify_prebuild.ps1"
$TempDir = Join-Path $Root "benchmarks\tmp\verify-prebuild-manifest-gate"

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

function Write-Manifest {
  param(
    [string]$PathValue,
    [object[]]$Checks
  )

  $Manifest = [pscustomobject]@{
    checks = $Checks
  }
  $Json = $Manifest | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($PathValue, $Json, [System.Text.UTF8Encoding]::new($false))
}

function New-Check {
  param(
    [string]$Name,
    [bool]$Ok,
    [string]$Detail = ""
  )

  [pscustomobject]@{
    name = $Name
    ok = $Ok
    detail = $Detail
  }
}

function Assert-Passes {
  param(
    [string]$ManifestPath,
    [bool]$AllowAtlFailures,
    [string]$Description
  )

  try {
    Assert-EnvironmentManifestChecks -ManifestPath $ManifestPath -AllowAtlFailures $AllowAtlFailures
  } catch {
    throw "$Description should pass. Error: $($_.Exception.Message)"
  }
}

function Assert-FailsWith {
  param(
    [string]$ManifestPath,
    [bool]$AllowAtlFailures,
    [string]$Pattern,
    [string]$Description
  )

  $Failed = $false
  $Message = ""
  try {
    Assert-EnvironmentManifestChecks -ManifestPath $ManifestPath -AllowAtlFailures $AllowAtlFailures
  } catch {
    $Failed = $true
    $Message = $_.Exception.Message
  }

  if (-not $Failed) {
    throw "$Description should fail."
  }
  if ($Message -notmatch $Pattern) {
    throw "$Description failed for the wrong reason. Pattern: $Pattern Message: $Message"
  }
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )

  if ($Text -notmatch $Pattern) {
    throw "verify_prebuild.ps1 is missing $Description. Pattern: $Pattern"
  }
}

try {
  New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
  $VerifierText = Get-Content -LiteralPath $VerifierPath -Raw

  $ParserErrors = $null
  $Tokens = $null
  $Ast = [System.Management.Automation.Language.Parser]::ParseFile($VerifierPath, [ref]$Tokens, [ref]$ParserErrors)
  if ($ParserErrors.Count -gt 0) {
    throw "verify_prebuild.ps1 has parser errors: $($ParserErrors[0].Message)"
  }

  $FunctionAst = $Ast.Find({
      param($Node)
      $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $Node.Name -eq "Assert-EnvironmentManifestChecks"
    }, $true)
  if (-not $FunctionAst) {
    throw "verify_prebuild.ps1 does not define Assert-EnvironmentManifestChecks."
  }

  Assert-Contains $VerifierText "Checking blocker experiment planning" "blocker experiment planning execution"
  Assert-Contains $VerifierText "Checking current candidate-analysis manifest handoff" "current candidate-analysis manifest handoff execution"
  Assert-Contains $VerifierText "scripts\\test_current_candidate_analysis\.ps1" "current candidate-analysis manifest handoff script inventory"
  Assert-Contains $VerifierText "scripts\\test_blocker_experiment_plan\.ps1" "blocker experiment plan script inventory"
  Assert-Contains $VerifierText "Checking trusted matrix label suffix and filters" "trusted matrix label/filter execution"
  Assert-Contains $VerifierText "scripts\\test_trusted_matrix_label_suffix\.ps1" "trusted matrix label/filter script inventory"
  Assert-Contains $VerifierText "Checking stock baseline source-state guard" "stock baseline source-state guard execution"
  Assert-Contains $VerifierText "scripts\\test_baseline_source_guard\.ps1" "stock baseline source-state guard script inventory"

  . ([scriptblock]::Create($FunctionAst.Extent.Text))

  $CleanPath = Join-Path $TempDir "clean.json"
  Write-Manifest $CleanPath @(
    (New-Check "navigation_external_ipv4" $true "192.168.1.84 on Wi-Fi")
  )
  Assert-Passes $CleanPath $false "manifest with all checks passing"

  $AtlOnlyPath = Join-Path $TempDir "atl-only.json"
  Write-Manifest $AtlOnlyPath @(
    (New-Check "visual_studio_atl" $false "missing atldef.h"),
    (New-Check "visual_studio_atl_component" $false "missing ATL component"),
    (New-Check "navigation_external_ipv4" $true "192.168.1.84 on Wi-Fi")
  )
  Assert-Passes $AtlOnlyPath $true "ATL-only manifest failures with allowance"
  Assert-FailsWith $AtlOnlyPath $false "visual_studio_atl" "ATL failures without allowance"

  $CodeIntegrityPath = Join-Path $TempDir "code-integrity.json"
  Write-Manifest $CodeIntegrityPath @(
    (New-Check "visual_studio_atl" $false "missing atldef.h"),
    (New-Check "visual_studio_atl_component" $false "missing ATL component"),
    (New-Check "windows_code_integrity_chromium_rust" $false "current Code Integrity block for Chromium Rust host tools"),
    (New-Check "navigation_external_ipv4" $true "192.168.1.84 on Wi-Fi")
  )
  Assert-FailsWith $CodeIntegrityPath $true "windows_code_integrity_chromium_rust" "Code Integrity failure with ATL allowance"

  $UnexpectedPath = Join-Path $TempDir "unexpected.json"
  Write-Manifest $UnexpectedPath @(
    (New-Check "visual_studio_atl" $false "missing atldef.h"),
    (New-Check "visual_studio_atl_component" $false "missing ATL component"),
    (New-Check "navigation_external_ipv4" $false "no non-loopback IPv4 address")
  )
  Assert-FailsWith $UnexpectedPath $true "navigation_external_ipv4" "non-ATL manifest failure with ATL allowance"

  Write-Host "verify_prebuild.ps1 gates environment-manifest failures, only allows ATL failures when requested, and runs speed-iteration planning regressions."
} finally {
  if (Test-Path $TempDir) {
    Assert-UnderDirectory $TempDir (Join-Path $Root "benchmarks\tmp")
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}

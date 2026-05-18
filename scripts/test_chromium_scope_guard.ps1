[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Assert-ContainsPath {
  param(
    [string[]]$PathValues,
    [string]$Expected
  )

  if ($PathValues -notcontains $Expected) {
    throw "Chromium scope guard scan set is missing $Expected."
  }
}

$ScanFiles = @(
  "README.md"
)
$ScanFiles += @(Get-ChildItem -LiteralPath (Join-Path $Root "docs") -Filter "*.md" -File | ForEach-Object {
    "docs\$($_.Name)"
  })
$ScanFiles += @(Get-ChildItem -LiteralPath (Join-Path $Root "chromium_patches") -Filter "*.md" -File | ForEach-Object {
    "chromium_patches\$($_.Name)"
  })
$ScanFiles = @($ScanFiles | Sort-Object -Unique)

Assert-ContainsPath $ScanFiles "README.md"
Assert-ContainsPath $ScanFiles "docs\architecture.md"
Assert-ContainsPath $ScanFiles "docs\benchmark_methodology.md"
Assert-ContainsPath $ScanFiles "chromium_patches\README.md"

$ForbiddenPatterns = @(
  "\bCEF\b",
  "\bElectron\b",
  "\bUnity\b",
  "\bUnreal\b",
  "\bnative engines?\b",
  "\braw Vulkan\b",
  "\braw WebGPU\b"
)

$AllowedContextPatterns = @(
  "\bbenchmark references?\b",
  "\bnot recommend(ed)?\b",
  "\bnot a recommended path\b",
  "\bout of scope\b",
  "\bnon-Chromium alternatives\b"
)

$Violations = [System.Collections.Generic.List[string]]::new()

foreach ($PathValue in $ScanFiles) {
  $FullPath = Join-Path $Root $PathValue
  $Lines = Get-Content -LiteralPath $FullPath
  for ($Index = 0; $Index -lt $Lines.Count; $Index += 1) {
    $Line = [string]$Lines[$Index]
    $MatchedForbidden = @($ForbiddenPatterns | Where-Object { $Line -match $_ })
    if ($MatchedForbidden.Count -eq 0) {
      continue
    }

    $Allowed = $false
    foreach ($AllowedPattern in $AllowedContextPatterns) {
      if ($Line -match $AllowedPattern) {
        $Allowed = $true
        break
      }
    }

    if (-not $Allowed) {
      $Violations.Add("${PathValue}:$($Index + 1): $Line") | Out-Null
    }
  }
}

if ($Violations.Count -gt 0) {
  throw "Authored docs/patch notes recommend or foreground non-Chromium alternatives despite the Chromium-fork scope:`n$($Violations -join "`n")"
}

Write-Host "Chromium-only scope guard passed for README, docs, and patch notes."

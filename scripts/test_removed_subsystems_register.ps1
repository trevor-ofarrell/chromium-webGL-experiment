[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$DocPath = Join-Path $Root "docs\removed_subsystems.md"

if (-not (Test-Path -LiteralPath $DocPath)) {
  throw "Missing docs\removed_subsystems.md."
}

$Text = Get-Content -LiteralPath $DocPath -Raw
foreach ($RequiredPhrase in @(
    "This register documents what the Chromium viewer fork removes, avoids, disables, keeps, or rejects",
    "Final Register",
    "Prompt Optimization Class Tracking",
    "Subsystems Explicitly Kept For Now",
    "Update Rule"
  )) {
  if ($Text -notmatch [regex]::Escape($RequiredPhrase)) {
    throw "Removed subsystem register is missing required final-register text: $RequiredPhrase"
  }
}

function Get-SectionLines {
  param(
    [string[]]$Lines,
    [string]$Heading
  )

  $Start = -1
  for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
    if ($Lines[$Index] -eq "## $Heading") {
      $Start = $Index + 1
      break
    }
  }
  if ($Start -lt 0) {
    throw "Missing section heading: $Heading"
  }

  $End = $Lines.Count
  for ($Index = $Start; $Index -lt $Lines.Count; $Index++) {
    if ($Lines[$Index] -match '^##\s+') {
      $End = $Index
      break
    }
  }

  return @($Lines[$Start..($End - 1)])
}

function Split-MarkdownRow {
  param([string]$Line)

  $Trimmed = $Line.Trim()
  if (-not $Trimmed.StartsWith("|") -or -not $Trimmed.EndsWith("|")) {
    throw "Invalid markdown table row: $Line"
  }

  return @($Trimmed.Trim("|").Split("|") | ForEach-Object { $_.Trim() })
}

function Get-FirstTable {
  param(
    [string[]]$SectionLines,
    [string]$Heading
  )

  $TableLines = @($SectionLines | Where-Object { $_.Trim().StartsWith("|") })
  if ($TableLines.Count -lt 3) {
    throw "Section '$Heading' does not contain a markdown table with data rows."
  }

  $Header = Split-MarkdownRow $TableLines[0]
  $Rows = @()
  foreach ($Line in @($TableLines | Select-Object -Skip 2)) {
    $Cells = Split-MarkdownRow $Line
    if ($Cells.Count -ne $Header.Count) {
      throw "Section '$Heading' has a row with $($Cells.Count) cells; expected $($Header.Count): $Line"
    }
    $Row = [ordered]@{}
    for ($Index = 0; $Index -lt $Header.Count; $Index++) {
      $Row[$Header[$Index]] = $Cells[$Index]
    }
    $Rows += [pscustomobject]$Row
  }

  return [pscustomobject]@{
    Header = $Header
    Rows = $Rows
  }
}

function Assert-TableColumnsAndCells {
  param(
    [string]$Heading,
    [string[]]$RequiredColumns
  )

  $SectionLines = Get-SectionLines $Lines $Heading
  $Table = Get-FirstTable $SectionLines $Heading
  foreach ($Column in $RequiredColumns) {
    if ($Table.Header -notcontains $Column) {
      throw "Section '$Heading' table is missing required column '$Column'."
    }
  }

  foreach ($Row in @($Table.Rows)) {
    $Name = $Row.($RequiredColumns[0])
    foreach ($Column in $RequiredColumns) {
      $Value = [string]$Row.$Column
      if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Section '$Heading' row '$Name' has an empty '$Column' cell."
      }
    }
    if ($RequiredColumns -contains "Regression risk") {
      $Risk = [string]$Row."Regression risk"
      if ($Risk -notmatch "Low|Medium|High|Very high") {
        throw "Section '$Heading' row '$Name' has an unclassified regression risk: $Risk"
      }
    }
  }

  return @($Table.Rows).Count
}

$Lines = Get-Content -LiteralPath $DocPath
$CheckedRows = 0
$CheckedRows += Assert-TableColumnsAndCells "Final Register" @(
  "Subsystem or feature",
  "Decision",
  "Rationale",
  "Regression risk",
  "Current evidence"
)
$CheckedRows += Assert-TableColumnsAndCells "Prompt Optimization Class Tracking" @(
  "Optimization class",
  "Register decision"
)
$CheckedRows += Assert-TableColumnsAndCells "Subsystems Explicitly Kept For Now" @(
  "Subsystem",
  "Kept because",
  "Notes"
)

if ($CheckedRows -lt 25) {
  throw "Removed subsystem register checked only $CheckedRows rows; expected broad subsystem coverage."
}

Write-Host "Removed subsystem register documents rationale, regression risk, and current evidence for $CheckedRows subsystem/experiment rows."

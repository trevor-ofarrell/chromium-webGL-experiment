[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"

if (-not (Test-Path $PatchPath)) {
  throw "Viewer patch not found: $PatchPath"
}

$PatchText = Get-Content -LiteralPath $PatchPath -Raw
$AddedCode = ((Get-Content -LiteralPath $PatchPath) |
  Where-Object { $_.StartsWith("+") -and -not $_.StartsWith("+++") } |
  ForEach-Object { $_.Substring(1) }) -join "`n"

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )

  if ($Text -notmatch $Pattern) {
    throw "Missing viewer-entrypoint evidence: $Description. Pattern: $Pattern"
  }
}

function Assert-Order {
  param(
    [string]$Text,
    [string]$First,
    [string]$Second,
    [string]$Description
  )

  $FirstMatch = [regex]::Match($Text, $First)
  $SecondMatch = [regex]::Match($Text, $Second)
  if (-not $FirstMatch.Success) {
    throw "Missing first pattern for $Description. Pattern: $First"
  }
  if (-not $SecondMatch.Success) {
    throw "Missing second pattern for $Description. Pattern: $Second"
  }
  if ($FirstMatch.Index -ge $SecondMatch.Index) {
    throw "Wrong order for $Description. First pattern must occur before second pattern."
  }
}

Assert-Contains `
  $AddedCode `
  'inline constexpr char kViewerAppUrl\[\]\s*=\s*"viewer-app-url";' `
  "viewer app URL switch definition"

Assert-Contains `
  $AddedCode `
  'command_line->HasSwitch\(switches::kContentShellHideToolbar\)\s*\|\|\s*command_line->HasSwitch\(switches::kViewerAppUrl\)' `
  "viewer app URL suppresses content-shell toolbar"

Assert-Contains `
  $AddedCode `
  'GetSwitchValuePath\(switches::kViewerAppUrl\)' `
  "viewer startup accepts local path switch values before generic URL parsing"

Assert-Contains `
  $AddedCode `
  'return net::FilePathToFileURL\(\s*base::MakeAbsoluteFilePath\(viewer_app_path\)\)' `
  "viewer startup converts local paths to file URLs"

Assert-Contains `
  $AddedCode `
  'GURL url\(viewer_app_url\)' `
  "viewer startup accepts URL switch values"

Assert-Contains `
  $AddedCode `
  'if \(url\.is_valid\(\) && url\.has_scheme\(\)\)\s*return url;' `
  "viewer startup returns valid scheme URLs directly"

Assert-Order `
  $PatchText `
  'if \(command_line->HasSwitch\(switches::kViewerAppUrl\)\)' `
  'const base::CommandLine::StringVector& args = command_line->GetArgs\(\);' `
  "viewer app URL branch takes precedence over positional command-line URLs"

Assert-Order `
  $PatchText `
  'if \(command_line->HasSwitch\(switches::kViewerAppUrl\)\)' `
  'return GURL\("https://www\.google\.com/"\);' `
  "viewer app URL branch takes precedence over content_shell default URL"

Assert-Contains `
  $PatchText `
  'THREE_VIEWER_RESULT' `
  "viewer mode forwards benchmark result marker to stdout"

Assert-Contains `
  $PatchText `
  'params\.disposition != WindowOpenDisposition::CURRENT_TAB\)\s*\{\s*\+    return nullptr;' `
  "viewer navigation lock prevents new tab/window WebContents creation"

Write-Host "Viewer patch entrypoint launch precedence and chrome suppression are statically verified."

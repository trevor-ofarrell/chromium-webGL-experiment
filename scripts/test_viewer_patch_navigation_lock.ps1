[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$PatchPath = Join-Path $Root "chromium_patches\0001-draft-minimal-three-viewer-entrypoint.patch"

if (-not (Test-Path $PatchPath)) {
  throw "Viewer patch not found: $PatchPath"
}

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
    throw "Missing expected navigation-lock evidence: $Description. Pattern: $Pattern"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -match $Pattern) {
    throw "Found disallowed navigation-lock evidence: $Description. Pattern: $Pattern"
  }
}

function Get-FunctionBody {
  param(
    [string]$Text,
    [string]$FunctionName
  )

  $Match = [regex]::Match($Text, "(?:bool|GURL|void)\s+$([regex]::Escape($FunctionName))\s*\(")
  if (-not $Match.Success) {
    throw "Function not found in patch additions: $FunctionName"
  }

  $BraceStart = $Text.IndexOf("{", $Match.Index)
  if ($BraceStart -lt 0) {
    throw "Opening brace not found for function: $FunctionName"
  }

  $Depth = 0
  for ($Index = $BraceStart; $Index -lt $Text.Length; $Index++) {
    $Char = $Text[$Index]
    if ($Char -eq "{") {
      $Depth += 1
    } elseif ($Char -eq "}") {
      $Depth -= 1
      if ($Depth -eq 0) {
        return $Text.Substring($BraceStart, $Index - $BraceStart + 1)
      }
    }
  }

  throw "Closing brace not found for function: $FunctionName"
}

Assert-Contains `
  $AddedCode `
  'inline constexpr char kViewerAppUrl\[\]\s*=\s*"viewer-app-url";' `
  "viewer app startup switch definition"

Assert-Contains `
  $AddedCode `
  'inline constexpr char kViewerBlockExternalNavigation\[\]\s*=\s*"viewer-block-external-navigation";' `
  "navigation lock switch definition"

Assert-Contains `
  $AddedCode `
  'command_line->HasSwitch\(switches::kContentShellHideToolbar\)\s*\|\|\s*command_line->HasSwitch\(switches::kViewerAppUrl\)' `
  "viewer app startup hides content-shell toolbar"

Assert-Contains `
  $AddedCode `
  'HasSwitch\(\s*switches::kViewerBlockExternalNavigation\)\s*&&\s*params\.disposition != WindowOpenDisposition::CURRENT_TAB\)\s*\{\s*return nullptr;' `
  "viewer navigation lock blocks non-current-tab opens"

Assert-Contains `
  $AddedCode `
  'HasSwitch\(\s*switches::kViewerBlockExternalNavigation\)\)\s*\{\s*if \(was_blocked\)\s*\*was_blocked\s*=\s*true;\s*return nullptr;' `
  "viewer navigation lock blocks AddNewContents window.open path"

Assert-Contains $AddedCode 'command_line->HasSwitch\(switches::kViewerAppUrl\)' "startup URL uses viewer app switch"
Assert-Contains $AddedCode 'GetSwitchValuePath\(switches::kViewerAppUrl\)' "startup URL accepts local path switch values"
Assert-Contains $AddedCode 'viewer_app_path\.IsAbsolute\(\)' "startup URL detects absolute local viewer paths"
Assert-Contains $AddedCode 'net::FilePathToFileURL\(\s*base::MakeAbsoluteFilePath\(viewer_app_path\)\)' "startup URL converts absolute paths to file URLs"
Assert-Contains $AddedCode 'GURL url\(viewer_app_url\)' "startup URL parses URL switch values"
Assert-Contains $AddedCode 'url\.is_valid\(\) && url\.has_scheme\(\)' "startup URL accepts valid scheme URLs"

$GetViewerAppUrlBody = Get-FunctionBody $AddedCode "GetViewerAppUrlFromCommandLine"
Assert-Contains $GetViewerAppUrlBody 'GetSwitchValuePath\(switches::kViewerAppUrl\)' "navigation throttle resolves viewer app path"
Assert-Contains $GetViewerAppUrlBody 'viewer_app_path\.IsAbsolute\(\)' "navigation throttle treats absolute viewer paths as local files"
Assert-Contains $AddedCode 'base::FilePath NormalizeViewerFilePath\(base::FilePath path\)' "navigation throttle has non-blocking viewer path normalization helper"
Assert-Contains $AddedCode 'path = path\.NormalizePathSeparators\(\);' "navigation throttle normalizes path separators without filesystem IO"
Assert-Contains $AddedCode 'path\.ReferencesParent\(\)' "navigation throttle rejects parent-directory path references"
Assert-Contains $AddedCode 'base::PathService::Get\(base::DIR_CURRENT, &current_dir\)' "navigation throttle resolves relative viewer paths from current directory without MakeAbsoluteFilePath"
Assert-Contains $AddedCode 'current_dir\.Append\(path\)\.NormalizePathSeparators\(\)' "navigation throttle resolves relative viewer paths by string composition"
Assert-Contains $AddedCode 'GURL ViewerFilePathToFileUrl\(base::FilePath path\)' "navigation throttle has file path to URL helper"
Assert-Contains $AddedCode 'path = NormalizeViewerFilePath\(std::move\(path\)\)' "navigation throttle file URL helper normalizes paths"
Assert-Contains $AddedCode 'net::FilePathToFileURL\(path\)' "navigation throttle converts normalized paths to file URLs"
Assert-Contains $GetViewerAppUrlBody 'ViewerFilePathToFileUrl\(viewer_app_path\)' "navigation throttle converts viewer path through non-blocking helper"
Assert-NotContains $GetViewerAppUrlBody 'MakeAbsoluteFilePath' "navigation throttle startup URL helper must not call blocking MakeAbsoluteFilePath"
Assert-Contains $GetViewerAppUrlBody 'GURL url\(viewer_app_url\)' "navigation throttle parses viewer URL switch values"

$FileBody = Get-FunctionBody $AddedCode "IsViewerFileNavigationAllowed"
Assert-Contains $FileBody '!navigation_url\.SchemeIsFile\(\)\)\s*return false;' "file navigation rejects non-file URLs"
Assert-Contains $FileBody 'net::FileURLToFilePath\(viewer_app_url, &viewer_app_path\)' "file navigation converts viewer URL"
Assert-Contains $FileBody 'net::FileURLToFilePath\(navigation_url, &navigation_path\)' "file navigation converts target URL"
Assert-Contains $FileBody 'viewer_app_path = NormalizeViewerFilePath\(std::move\(viewer_app_path\)\)' "file navigation normalizes viewer path without filesystem IO"
Assert-Contains $FileBody 'navigation_path = NormalizeViewerFilePath\(std::move\(navigation_path\)\)' "file navigation normalizes target path without filesystem IO"
Assert-NotContains $FileBody 'MakeAbsoluteFilePath' "file navigation throttle must not call blocking MakeAbsoluteFilePath"
Assert-Contains $FileBody 'const base::FilePath viewer_app_dir = viewer_app_path\.DirName\(\);' "file navigation derives viewer app directory"
Assert-Contains $FileBody 'navigation_path == viewer_app_path\s*\|\|\s*viewer_app_dir\.IsParent\(navigation_path\)' "file navigation allows only viewer file or children"

$NavigationBody = Get-FunctionBody $AddedCode "IsViewerNavigationAllowed"
Assert-Contains $NavigationBody '!viewer_app_url\.is_valid\(\) \|\| !navigation_url\.is_valid\(\)\)\s*return false;' "navigation rejects invalid URLs"
Assert-Contains $NavigationBody 'navigation_url == GURL\(url::kAboutBlankURL\)\)\s*return true;' "navigation allows about:blank"
Assert-Contains $NavigationBody 'viewer_app_url\.SchemeIsFile\(\)\)\s*return IsViewerFileNavigationAllowed\(viewer_app_url, navigation_url\);' "navigation delegates file launches to directory confinement"
Assert-Contains $NavigationBody 'url::Origin::Create\(viewer_app_url\)\s*\.IsSameOriginWith\(url::Origin::Create\(navigation_url\)\)' "navigation allows only same-origin non-file URLs"

Assert-Contains $AddedCode 'class ViewerNavigationThrottle : public NavigationThrottle' "viewer navigation throttle class exists"
Assert-Contains $AddedCode 'ThrottleCheckResult WillStartRequest\(\) override \{ return CheckNavigation\(\); \}' "navigation throttle checks initial requests"
Assert-Contains $AddedCode 'ThrottleCheckResult WillRedirectRequest\(\) override \{\s*return CheckNavigation\(\);\s*\}' "navigation throttle checks redirects"
Assert-Contains $AddedCode 'return "ViewerNavigationThrottle";' "navigation throttle has logging name"
Assert-Contains $AddedCode 'return BLOCK_REQUEST;' "navigation throttle blocks disallowed requests"
Assert-Contains $AddedCode 'registry\.AddThrottle\(std::make_unique<ViewerNavigationThrottle>\(registry\)\);' "navigation throttle is registered"
Assert-Contains $AddedCode 'HasSwitch\(\s*switches::kViewerBlockExternalNavigation\)' "navigation throttle registration is gated by viewer block switch"

Write-Host "Viewer patch navigation lock is statically verified."

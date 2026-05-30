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
    throw "Missing expected stdout-result evidence: $Description. Pattern: $Pattern"
  }
}

Assert-Contains $AddedCode '#include <stdio\.h>' "stdio include for stdout forwarding"

Assert-Contains $PatchText 'DidAddMessageToConsole\(WebContents\* source' "console-message delegate hunk"
Assert-Contains $AddedCode 'const bool handled_by_web_tests = switches::IsRunWebTestsSwitchPresent\(\);' "preserves web-test console handling"
Assert-Contains $AddedCode 'HasSwitch\(\s*switches::kViewerAppUrl\)' "stdout forwarding is gated to viewer mode"
Assert-Contains $AddedCode 'base::UTF16ToUTF8\(message\)' "console message conversion to UTF-8"
Assert-Contains $AddedCode 'base::StartsWith\(message_utf8,\s*"THREE_VIEWER_RESULT"' "only benchmark result marker is forwarded"
Assert-Contains $AddedCode 'fprintf\(stdout,\s*"%s\\n",\s*message_utf8\.c_str\(\)\)' "benchmark result marker is written to stdout"
Assert-Contains $AddedCode 'fflush\(stdout\)' "stdout is flushed after benchmark result"
Assert-Contains $AddedCode 'return true;' "benchmark result console message is handled after forwarding"
Assert-Contains $AddedCode 'return handled_by_web_tests;' "non-result console behavior remains content-shell default"

Write-Host "Viewer patch stdout benchmark-result forwarding is statically verified."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path $Resolved)) {
    throw "Required file not found: $PathValue"
  }
  return Get-Content $Resolved -Raw
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Missing trace start-delay evidence: $Description. Pattern: $Pattern"
  }
}

function Assert-Order {
  param(
    [string]$Text,
    [string]$First,
    [string]$Second,
    [string]$Description
  )
  $FirstIndex = $Text.IndexOf($First)
  $SecondIndex = $Text.IndexOf($Second)
  if ($FirstIndex -lt 0 -or $SecondIndex -lt 0 -or $FirstIndex -ge $SecondIndex) {
    throw "Unexpected order for $Description. Expected '$First' before '$Second'."
  }
}

$Main = Read-RepoFile "viewer\src\main.js"
$TraceRunner = Read-RepoFile "scripts\run_trace_capture.mjs"

Assert-Contains $Main "startDelayMs:\s*numberParam\(params,\s*['""]startDelayMs['""]" "viewer parses startDelayMs query parameter"
Assert-Contains $Main "function delay\(ms\)" "viewer delay helper"
Assert-Contains $Main "if \(options\.startDelayMs > 0\)\s*\{\s*await delay\(options\.startDelayMs\);" "viewer waits before benchmark initialization"
Assert-Order $Main "await delay(options.startDelayMs);" "const rendererBundle = await createRenderer" "trace delay must happen before renderer/context creation"

Assert-Contains $TraceRunner "startDelayMs:\s*['""]2000['""]" "trace runner default start delay"
Assert-Contains $TraceRunner "startDelayMs:\s*String\(args\.startDelayMs\)" "trace runner passes startDelayMs query"
Assert-Contains $TraceRunner "parseBenchmarkConsoleResult" "robust trace benchmark console result parser"
Assert-Contains $TraceRunner "values\[0\]\s*===\s*['""]THREE_VIEWER_RESULT['""]" "two-argument trace benchmark result parser"
Assert-Contains $TraceRunner "startsWith\s*\(\s*['""]THREE_VIEWER_RESULT ['""]\s*\)" "single-string trace benchmark result parser"
Assert-Contains $TraceRunner "start_delay_ms:\s*Number\(args\.startDelayMs\)" "trace result sidecar records start delay"
Assert-Contains $TraceRunner "--viewer-app-url=\$\{viewerUrl\}" "trace runner still exercises viewer-mode app URL launch"
Assert-Contains $TraceRunner "Tracing\.start" "trace runner enables CDP tracing"

Write-Host "Trace capture start-delay wiring is statically verified."

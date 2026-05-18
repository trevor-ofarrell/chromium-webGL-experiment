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
    throw "Missing $Description. Pattern: $Pattern"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -match $Pattern) {
    throw "Unexpected $Description. Pattern: $Pattern"
  }
}

$Main = Read-RepoFile "viewer\src\main.js"
$Renderers = Read-RepoFile "viewer\src\renderers.js"
$Scenes = Read-RepoFile "viewer\src\scenes.js"
$Runner = Read-RepoFile "scripts\run_benchmark.mjs"

Assert-Contains $Main "requestAnimationFrame\s*\(" "requestAnimationFrame frame loop"
Assert-Contains $Main "performance\.now\s*\(" "performance.now timing"
Assert-Contains $Main "addEventListener\s*\(\s*['""]resize['""]" "resize event handling"
Assert-Contains $Main "addEventListener\s*\(\s*['""]pointermove['""]" "basic pointer input handling"
Assert-Contains $Main "__THREE_VIEWER_BENCHMARK_RESULT__" "benchmark result export"
Assert-Contains $Main "THREE_VIEWER_RESULT" "stdout/console benchmark result marker"
Assert-Contains $Main 'console\.log\s*\(\s*`\s*THREE_VIEWER_RESULT \$\{JSON\.stringify\(result\)\}' "single-line stdout/console benchmark result payload"

Assert-Contains $Renderers "navigator\.gpu" "WebGPU availability check"
Assert-Contains $Renderers "WebGPURenderer" "Three.js WebGPU renderer path"
Assert-Contains $Renderers "getContext\s*\(\s*['""]webgl2['""]" "WebGL2 context creation"
Assert-Contains $Renderers "desynchronized\s*:\s*true" "low-latency WebGL canvas attribute"
Assert-Contains $Renderers "powerPreference\s*:\s*['""]high-performance['""]" "high-performance GPU preference"
Assert-Contains $Renderers "preserveDrawingBuffer\s*:\s*false" "GPU-resident WebGL presentation default"

Assert-Contains $Scenes "fetch\s*\(" "local asset loading through fetch"
Assert-Contains $Scenes "createImageBitmap\s*\(" "ImageBitmap texture loading path"
Assert-Contains $Scenes "TextureLoader" "texture loader fallback"
Assert-Contains $Scenes "GLTFLoader" "imported glTF loader stress path"

foreach ($Arg in @("scene", "renderer", "duration", "warmup", "output")) {
  Assert-Contains $Runner "$Arg\s*:" "benchmark runner CLI/default option --$Arg"
}
Assert-Contains $Runner "mkdirSync\s*\(\s*path\.dirname\s*\(\s*path\.resolve\s*\(\s*args\.output\s*\)\s*\)" "benchmark runner output directory creation"
Assert-Contains $Runner "writeFileSync\s*\(\s*path\.resolve\s*\(\s*args\.output\s*\)" "benchmark runner JSON output write"
foreach ($QueryKey in @("scene", "renderer")) {
  Assert-Contains $Runner "$QueryKey\s*:\s*args\.$QueryKey" "viewer query propagation for $QueryKey"
}
Assert-Contains $Runner "duration\s*:\s*String\s*\(\s*duration\s*\)" "viewer query propagation for normalized duration"
Assert-Contains $Runner "warmup\s*:\s*String\s*\(\s*warmup\s*\)" "viewer query propagation for normalized warmup"
Assert-Contains $Runner "viewer-app-url" "viewer app URL handoff"
Assert-Contains $Runner "viewer-block-external-navigation" "viewer navigation lock handoff"
Assert-Contains $Runner "parseBenchmarkConsoleResult" "benchmark console result parser"
Assert-Contains $Runner "values\[0\]\s*===\s*['""]THREE_VIEWER_RESULT['""]" "two-argument benchmark console result parser"
Assert-Contains $Runner "startsWith\s*\(\s*['""]THREE_VIEWER_RESULT ['""]\s*\)" "single-string benchmark console result parser"

$ViewerSource = Get-ChildItem (Join-Path $Root "viewer\src") -Filter "*.js" -File |
  ForEach-Object { Get-Content $_.FullName -Raw } |
  Out-String
Assert-NotContains $ViewerSource "\breadPixels\b|getImageData\s*\(|toDataURL\s*\(" "CPU bitmap readback in viewer primary source"

Write-Host "Viewer runtime API surface and no-primary-readback checks passed."

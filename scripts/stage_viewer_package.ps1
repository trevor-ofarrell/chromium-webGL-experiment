[CmdletBinding()]
param(
  [string]$ChromiumOutDir = ".\src\out\ReleaseViewerDefault",
  [string]$ViewerDist = ".\viewer\dist",
  [string]$PackageDir = ".\benchmarks\packages\viewer-default",
  [switch]$Clean
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Resolve-RepoPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }
  return (Join-Path $Root $PathValue)
}

$ChromiumOutDir = Resolve-RepoPath $ChromiumOutDir
$ViewerDist = Resolve-RepoPath $ViewerDist
$PackageDir = Resolve-RepoPath $PackageDir

if (-not (Test-Path (Join-Path $ChromiumOutDir "content_shell.exe"))) {
  throw "content_shell.exe not found under $ChromiumOutDir"
}
if (-not (Test-Path (Join-Path $ViewerDist "index.html"))) {
  throw "viewer dist not found under $ViewerDist"
}

$ResolvedRoot = Resolve-Path $Root
if ($Clean -and (Test-Path $PackageDir)) {
  $ResolvedPackage = Resolve-Path $PackageDir
  $PackageText = $ResolvedPackage.ProviderPath.TrimEnd('\')
  $AllowedText = (Join-Path $ResolvedRoot.ProviderPath "benchmarks\packages").TrimEnd('\')
  if (-not $PackageText.StartsWith($AllowedText, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean package dir outside benchmarks\packages: $PackageText"
  }
  Remove-Item -LiteralPath $PackageText -Recurse -Force
}

New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null

$RuntimePatterns = @(
  "content_shell.exe",
  "*.dll",
  "*.pak",
  "*.bin",
  "*.dat",
  "*.json"
)

foreach ($Pattern in $RuntimePatterns) {
  Get-ChildItem -Path $ChromiumOutDir -File -Filter $Pattern -ErrorAction SilentlyContinue |
    ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $PackageDir $_.Name) -Force
    }
}

foreach ($DirName in @("locales", "swiftshader", "angledata", "MEIPreload")) {
  $SourceDir = Join-Path $ChromiumOutDir $DirName
  if (Test-Path $SourceDir) {
    Copy-Item -LiteralPath $SourceDir -Destination (Join-Path $PackageDir $DirName) -Recurse -Force
  }
}

$AppDir = Join-Path $PackageDir "viewer"
Copy-Item -LiteralPath $ViewerDist -Destination $AppDir -Recurse -Force

$LaunchScript = @'
[CmdletBinding()]
param(
  [switch]$Benchmark,
  [string]$Scene = "many-draw-calls",
  [ValidateSet("webgl2", "webgpu")]
  [string]$Renderer = "webgl2",
  [int]$Duration = 30,
  [int]$Warmup = 5,
  [double]$Complexity = 1,
  [switch]$Precompile,
  [int]$PrerenderFrames = 0,
  [switch]$DisableGpuTiming,
  [int]$StartDelayMs = 0,
  [switch]$UnsafeFullSizeWindow,
  [string[]]$ExtraArgs = @()
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Viewer = Join-Path $Root "viewer\index.html"
$Exe = Join-Path $Root "content_shell.exe"
$ProfileDir = Join-Path $Root "profile"
New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null

$ViewerUrl = [System.Uri]::new($Viewer).AbsoluteUri
if ($Benchmark) {
  $Query = [ordered]@{
    benchmark = "1"
    scene = $Scene
    renderer = $Renderer
    complexity = [string]$Complexity
    duration = [string]$Duration
    warmup = [string]$Warmup
    precompile = if ($Precompile) { "1" } else { "0" }
    prerenderFrames = [string]$PrerenderFrames
    gpuTiming = if ($DisableGpuTiming) { "0" } else { "1" }
    startDelayMs = [string]$StartDelayMs
  }
  $Pairs = foreach ($Item in $Query.GetEnumerator()) {
    "{0}={1}" -f [System.Uri]::EscapeDataString([string]$Item.Key), [System.Uri]::EscapeDataString([string]$Item.Value)
  }
  $ViewerUrl = "$ViewerUrl`?$($Pairs -join '&')"
}

$ViewerArgs = @(
  "--user-data-dir=$ProfileDir",
  "--no-first-run",
  "--disable-default-apps",
  "--disable-background-networking",
  "--disable-component-update",
  "--disable-sync",
  "--disable-extensions",
  "--disable-popup-blocking",
  "--disable-software-rasterizer",
  "--viewer-app-url=$ViewerUrl",
  "--viewer-block-external-navigation",
  "--viewer-trusted-content",
  "--enable-unsafe-webgpu",
  "--enable-webgpu-developer-features",
  "--autoplay-policy=no-user-gesture-required",
  "--disable-renderer-backgrounding",
  "--disable-background-timer-throttling",
  "--disable-features=Translate,OptimizationHints,AutofillServerCommunication"
)

if (-not $UnsafeFullSizeWindow) {
  $ViewerArgs += @(
    "--force-high-performance-gpu",
    "--window-size=640,480",
    "--window-position=40,40",
    "--force-device-scale-factor=1"
  )
}

& $Exe @ViewerArgs @ExtraArgs
exit $LASTEXITCODE
'@

Set-Content -LiteralPath (Join-Path $PackageDir "run_viewer.ps1") -Value $LaunchScript -Encoding ASCII

$SizeBytes = (Get-ChildItem -LiteralPath $PackageDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
$SizeMb = $SizeBytes / 1MB

Write-Host "Staged viewer package: $PackageDir"
Write-Host ("package_size_mb={0:N2}" -f $SizeMb)

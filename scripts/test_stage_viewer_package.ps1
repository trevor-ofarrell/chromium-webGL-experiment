[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$PackagesRoot = Join-Path $Root "benchmarks\packages"
New-Item -ItemType Directory -Path $PackagesRoot -Force | Out-Null

$PackagesRootFull = [System.IO.Path]::GetFullPath($PackagesRoot).TrimEnd('\') + '\'
$Prefix = "StagePackageTest-$([guid]::NewGuid().ToString('N'))"
$FakeOut = Join-Path $PackagesRoot "$Prefix-out"
$FakeViewerDist = Join-Path $PackagesRoot "$Prefix-dist"
$PackageDir = Join-Path $PackagesRoot "$Prefix-package"
$CreatedDirs = @($FakeOut, $FakeViewerDist, $PackageDir)

function Assert-UnderPackagesRoot {
  param([string]$PathValue)
  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  if (-not $FullPath.StartsWith($PackagesRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside benchmarks\packages: $FullPath"
  }
  return $FullPath
}

function Write-TestFile {
  param(
    [string]$PathValue,
    [string]$Value = "test"
  )
  New-Item -ItemType Directory -Path (Split-Path $PathValue -Parent) -Force | Out-Null
  Set-Content -LiteralPath $PathValue -Value $Value -Encoding ASCII
}

function Assert-PathExists {
  param(
    [string]$PathValue,
    [string]$Description
  )
  if (-not (Test-Path $PathValue)) {
    throw "Missing staged package artifact: $Description ($PathValue)"
  }
}

try {
  foreach ($Dir in $CreatedDirs) {
    $null = Assert-UnderPackagesRoot $Dir
  }

  Write-TestFile (Join-Path $FakeOut "content_shell.exe") "fake executable"
  Write-TestFile (Join-Path $FakeOut "viewer_resources.pak")
  Write-TestFile (Join-Path $FakeOut "icudtl.dat")
  Write-TestFile (Join-Path $FakeOut "v8_context_snapshot.bin")
  Write-TestFile (Join-Path $FakeOut "runtime-metadata.json") "{}"
  Write-TestFile (Join-Path $FakeOut "ignored.txt") "should not be copied"
  Write-TestFile (Join-Path $FakeOut "locales\en-US.pak")
  Write-TestFile (Join-Path $FakeOut "swiftshader\vk_swiftshader.dll")
  Write-TestFile (Join-Path $FakeOut "angledata\angle.json") "{}"
  Write-TestFile (Join-Path $FakeOut "MEIPreload\manifest.json") "{}"

  Write-TestFile (Join-Path $FakeViewerDist "index.html") "<!doctype html><title>viewer</title>"
  Write-TestFile (Join-Path $FakeViewerDist "assets\app.js") "console.log('viewer');"

  Write-TestFile (Join-Path $PackageDir "stale.txt") "stale"

  $Output = (& (Join-Path $Root "scripts\stage_viewer_package.ps1") `
    -ChromiumOutDir $FakeOut `
    -ViewerDist $FakeViewerDist `
    -PackageDir $PackageDir `
    -Clean *>&1) -join "`n"

  if ($Output -notmatch "Staged viewer package:" -or $Output -notmatch "package_size_mb=") {
    throw "Package staging output did not include package path and size. Output: $Output"
  }

  $RequiredArtifacts = @(
    @("content_shell.exe", "content shell executable"),
    @("viewer_resources.pak", "pak runtime asset"),
    @("icudtl.dat", "ICU data"),
    @("v8_context_snapshot.bin", "V8 snapshot"),
    @("runtime-metadata.json", "JSON runtime metadata"),
    @("locales\en-US.pak", "locales directory"),
    @("swiftshader\vk_swiftshader.dll", "swiftshader directory"),
    @("angledata\angle.json", "angledata directory"),
    @("MEIPreload\manifest.json", "MEIPreload directory"),
    @("viewer\index.html", "viewer index"),
    @("viewer\assets\app.js", "viewer asset"),
    @("run_viewer.ps1", "package launcher")
  )
  foreach ($Artifact in $RequiredArtifacts) {
    Assert-PathExists (Join-Path $PackageDir $Artifact[0]) $Artifact[1]
  }

  if (Test-Path (Join-Path $PackageDir "ignored.txt")) {
    throw "Package staging copied an unlisted top-level runtime file."
  }
  if (Test-Path (Join-Path $PackageDir "stale.txt")) {
    throw "Package staging -Clean did not remove a stale package file."
  }

  $Launcher = Get-Content (Join-Path $PackageDir "run_viewer.ps1") -Raw
  $null = [scriptblock]::Create($Launcher)
  foreach ($Expected in @(
    '[switch]$Benchmark',
    '[string]$Scene = "many-draw-calls"',
    '[ValidateSet("webgl2", "webgpu")]',
    '[string]$Renderer = "webgl2"',
    '[int]$Duration = 30',
    '[int]$Warmup = 5',
    'benchmark = "1"',
    'scene = $Scene',
    'renderer = $Renderer',
    'duration = [string]$Duration',
    'warmup = [string]$Warmup',
    'startDelayMs = [string]$StartDelayMs',
    '$ProfileDir = Join-Path $Root "profile"',
    'New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null',
    '--user-data-dir=$ProfileDir',
    "--no-first-run",
    "--disable-default-apps",
    "--disable-background-networking",
    "--disable-component-update",
    "--disable-sync",
    "--disable-extensions",
    "--disable-popup-blocking",
    "--disable-software-rasterizer",
    '--viewer-app-url=$ViewerUrl',
    "--viewer-block-external-navigation",
    "--viewer-trusted-content",
    "--enable-unsafe-webgpu",
    "--enable-webgpu-developer-features",
    "--autoplay-policy=no-user-gesture-required",
    "--disable-renderer-backgrounding",
    "--disable-background-timer-throttling",
    "--disable-features=Translate,OptimizationHints,AutofillServerCommunication",
    '[switch]$UnsafeFullSizeWindow',
    "--force-high-performance-gpu",
    "--window-size=640,480",
    "--window-position=40,40",
    "--force-device-scale-factor=1",
    '@ExtraArgs'
  )) {
    if ($Launcher -notmatch [regex]::Escape($Expected)) {
      throw "Launcher is missing expected argument: $Expected"
    }
  }

  Write-Host "Viewer package staging regression checks passed."
} finally {
  foreach ($Dir in $CreatedDirs) {
    $FullDir = Assert-UnderPackagesRoot $Dir
    if (Test-Path $FullDir) {
      Remove-Item -LiteralPath $FullDir -Recurse -Force
    }
  }
}

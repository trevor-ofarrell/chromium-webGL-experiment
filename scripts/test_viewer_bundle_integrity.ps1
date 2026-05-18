[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ViewerDir = Join-Path $Root "viewer"
$DistDir = Join-Path $ViewerDir "dist"

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) {
    throw $Message
  }
}

function Assert-Contains {
  param(
    [string]$Label,
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "$Label missing $Description. Pattern: $Pattern"
  }
}

$PackagePath = Join-Path $ViewerDir "package.json"
$ViteConfigPath = Join-Path $ViewerDir "vite.config.js"
$IndexPath = Join-Path $DistDir "index.html"
$ScenesPath = Join-Path $ViewerDir "src\scenes.js"

foreach ($PathValue in @($PackagePath, $ViteConfigPath, $IndexPath, $ScenesPath)) {
  Assert-True (Test-Path -LiteralPath $PathValue) "Required viewer bundle file missing: $PathValue"
}

$Package = Get-Content -LiteralPath $PackagePath -Raw | ConvertFrom-Json
Assert-True ($Package.private -eq $true) "viewer/package.json must remain private for the local benchmark bundle."
Assert-True ($Package.type -eq "module") "viewer/package.json must use ESM modules."
Assert-True ($Package.scripts.build -eq "vite build") "viewer/package.json build script must remain 'vite build'."
Assert-True ($Package.dependencies.three -match '^\d+\.\d+\.\d+$') "viewer/package.json must pin a concrete three dependency version."
Assert-True ($Package.dependencies.vite -match '^\d+\.\d+\.\d+$') "viewer/package.json must pin a concrete vite dependency version."

$ViteConfig = Get-Content -LiteralPath $ViteConfigPath -Raw
Assert-Contains "viewer/vite.config.js" $ViteConfig "base\s*:\s*['""]\./['""]" "relative base path for file/package launches"

$IndexHtml = Get-Content -LiteralPath $IndexPath -Raw
Assert-Contains "viewer/dist/index.html" $IndexHtml "<canvas\s+id=['""]viewer['""]" "viewer canvas"
Assert-Contains "viewer/dist/index.html" $IndexHtml "type=['""]module['""]" "module script entrypoint"

$ReferenceMatches = [regex]::Matches($IndexHtml, '(?:src|href)=["'']([^"'']+)["'']')
Assert-True ($ReferenceMatches.Count -gt 0) "viewer/dist/index.html must reference built local assets."
foreach ($Match in $ReferenceMatches) {
  $Reference = $Match.Groups[1].Value
  Assert-True ($Reference -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*:') "viewer/dist/index.html contains an absolute URL dependency: $Reference"
  Assert-True (-not $Reference.StartsWith("//")) "viewer/dist/index.html contains a protocol-relative dependency: $Reference"
  Assert-True (-not $Reference.StartsWith("/")) "viewer/dist/index.html contains a root-relative dependency that breaks file/package launches: $Reference"

  $RelativePath = $Reference.TrimStart(".", "/", "\") -replace '/', [System.IO.Path]::DirectorySeparatorChar
  $Resolved = Join-Path $DistDir $RelativePath
  Assert-True (Test-Path -LiteralPath $Resolved) "viewer/dist/index.html references missing local asset: $Reference"
}

foreach ($Asset in @("assets\checker.svg", "assets\models\cube-stress.gltf")) {
  Assert-True (Test-Path -LiteralPath (Join-Path $DistDir $Asset)) "Required bundled viewer asset missing from dist: $Asset"
}
Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $DistDir "assets") -Filter "index-*.js" -File).Count -ge 1) "viewer/dist/assets must contain the bundled app JS chunk."
Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $DistDir "assets") -Filter "three.webgpu-*.js" -File).Count -ge 1) "viewer/dist/assets must contain the bundled Three.js WebGPU chunk."

$Scenes = Get-Content -LiteralPath $ScenesPath -Raw
Assert-Contains "viewer/src/scenes.js" $Scenes "viewerAssetUrl\('assets/checker\.svg'\)" "local checker texture asset reference"
Assert-Contains "viewer/src/scenes.js" $Scenes "viewerAssetUrl\('assets/models/cube-stress\.gltf'\)" "local glTF stress asset reference"
Assert-Contains "viewer/src/scenes.js" $Scenes "\bfetch\s*\(\s*viewerAssetUrl\(" "local fetch asset loading"
Assert-Contains "viewer/src/scenes.js" $Scenes "\bcreateImageBitmap\s*\(" "ImageBitmap texture path"
Assert-Contains "viewer/src/scenes.js" $Scenes "TextureLoader" "TextureLoader fallback"
Assert-Contains "viewer/src/scenes.js" $Scenes "GLTFLoader" "GLTFLoader import path"

$RemoteSourcePattern = "from\s+['""]https?://|import\s*\(\s*['""]https?://|fetch\s*\(\s*['""]https?://|new\s+URL\s*\(\s*['""]https?://"
$ViewerSource = Get-ChildItem -LiteralPath (Join-Path $ViewerDir "src") -Filter "*.js" -File |
  ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
  Out-String
Assert-True ($ViewerSource -notmatch $RemoteSourcePattern) "Viewer source contains a remote import/fetch/URL dependency."

Write-Host "Viewer bundle integrity checks passed for local-only Vite output, packaged assets, and pinned Three.js inputs."

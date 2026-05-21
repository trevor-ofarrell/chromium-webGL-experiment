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
    throw "Missing expected trusted-gate evidence: $Description. Pattern: $Pattern"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -match $Pattern) {
    throw "Unexpected trusted-gate evidence: $Description. Pattern: $Pattern"
  }
}

function Get-FunctionBody {
  param(
    [string]$Text,
    [string]$FunctionName
  )

  $Start = $Text.IndexOf("void $FunctionName(")
  if ($Start -lt 0) {
    throw "Function not found in patch additions: $FunctionName"
  }

  $BraceStart = $Text.IndexOf("{", $Start)
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

$TrustedFunction = Get-FunctionBody $AddedCode "ConfigureViewerTrustedContentSwitches"

Assert-Contains `
  $TrustedFunction `
  "if \(!command_line\.HasSwitch\(switches::kViewerAppUrl\)\s*\|\|\s*!command_line\.HasSwitch\(switches::kViewerTrustedContent\)\)\s+return;" `
  "viewer-app-url and trusted-content early return before unsafe aliases"

Assert-Contains `
  $AddedCode `
  "ConfigureViewerTrustedContentSwitches\(command_line\);" `
  "startup invokes trusted-content alias configuration"

$UnsafeNativeSwitches = @(
  "kAllowFileAccessFromFiles",
  "kUseANGLE",
  "kUseCmdDecoder",
  "kInProcessGPU",
  "kSingleProcess",
  "kDisableSoftwareRasterizer",
  "kEnableUnsafeWebGPU",
  "kEnableWebGPUDeveloperFeatures",
  "kForceHighPerformanceGPU",
  "kNoDelayForDX12VulkanInfoCollection"
)

foreach ($SwitchName in $UnsafeNativeSwitches) {
  Assert-Contains `
    $TrustedFunction `
    "switches::$SwitchName" `
    "unsafe alias $SwitchName remains inside ConfigureViewerTrustedContentSwitches"

  $OutsideTrustedFunction = $AddedCode.Replace($TrustedFunction, "")
  Assert-NotContains `
    $OutsideTrustedFunction `
    "switches::$SwitchName" `
    "unsafe alias $SwitchName outside trusted-content configuration"
}

$ViewerGateSwitches = @(
  "kViewerTrustedContent",
  "kViewerAggressiveGpu",
  "kViewerInProcessGpu",
  "kViewerSingleProcess",
  "kViewerForceAngleBackend",
  "kViewerRelaxedWebGLValidation",
  "kViewerDisableUnneededBlinkFeatures",
  "kViewerDirectGpuPresentation"
)

foreach ($SwitchName in $ViewerGateSwitches) {
  Assert-Contains `
    $AddedCode `
    "inline constexpr char $SwitchName\[\]" `
    "viewer switch definition $SwitchName"
}

$ReservedNoopGates = @(
  "kViewerDisableUnneededBlinkFeatures",
  "kViewerDirectGpuPresentation"
)
$AddedCodeWithoutDefinitions = $AddedCode -replace "inline constexpr char kViewerDisableUnneededBlinkFeatures\[\]\s*=\s*`n\s*`"viewer-disable-unneeded-blink-features`";", ""
$AddedCodeWithoutDefinitions = $AddedCodeWithoutDefinitions -replace "inline constexpr char kViewerDirectGpuPresentation\[\]\s*=\s*`n\s*`"viewer-direct-gpu-presentation`";", ""

Assert-Contains `
  $TrustedFunction `
  "HasSwitch\(switches::kViewerRelaxedWebGLValidation\)[\s\S]*?AppendSwitchASCIIIfAbsent\(command_line,\s*switches::kUseCmdDecoder,\s*gl::kCmdDecoderPassthroughName\)" `
  "relaxed WebGL validation gate maps to pass-through command decoder inside trusted-content configuration"

foreach ($SwitchName in $ReservedNoopGates) {
  Assert-NotContains `
    $AddedCodeWithoutDefinitions `
    "HasSwitch\(switches::$SwitchName\)|AppendSwitch(?:ASCII)?IfAbsent\(command_line,\s*switches::$SwitchName" `
    "reserved no-op gate $SwitchName has runtime behavior before a measured source experiment"
}

Assert-Contains `
  $PatchText `
  "Unsafe optimizations must\s*`r?`n\+// also require --viewer-app-url and their own explicit switches\." `
  "patch documents viewer-mode and explicit switches for unsafe optimizations"

Write-Host "Viewer patch trusted-content gates require viewer mode and are statically verified."

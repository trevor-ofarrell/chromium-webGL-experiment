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

$Runner = Read-RepoFile "scripts\run_smoke_tests.mjs"
$NavigationRunner = Read-RepoFile "scripts\run_navigation_lock_tests.mjs"
$Validator = Read-RepoFile "scripts\validate_smoke_result.mjs"
$Verifier = Read-RepoFile "scripts\verify_prebuild.ps1"
$Audit = Read-RepoFile "scripts\audit_artifacts.ps1"

$RequiredRuntimePass = @(
  "viewer_launch",
  "webgl2_context",
  "web_platform_basics",
  "basic_input_events",
  "three_cube_render",
  "texture_load",
  "shader_material",
  "benchmark_run"
)

$AllowedRuntimeSkip = @(
  "webgl_context_loss_event",
  "webgpu_adapter_device",
  "webgpu_device_loss_signal",
  "three_webgpu_render"
)

foreach ($Name in ($RequiredRuntimePass + $AllowedRuntimeSkip)) {
  Assert-Contains $Runner "name:\s*['""]$Name['""]|name:\s*$([regex]::Escape("'$Name'"))" "runtime smoke implementation for $Name"
  Assert-Contains $Validator "'$Name'" "smoke validator expectation for $Name"
}

Assert-Contains $Runner "canvas\.getContext\s*\(\s*['""]webgl2['""]" "WebGL2 context smoke"
Assert-Contains $Runner "requestAnimationFrame" "requestAnimationFrame smoke"
Assert-Contains $Runner "performance\.now" "performance.now smoke"
Assert-Contains $Runner "canvas\.getContext\s*\(\s*['""]2d['""]" "Canvas 2D smoke"
Assert-Contains $Runner "fetch\s*\(\s*['""]/assets/checker\.svg['""]" "local fetch smoke"
Assert-Contains $Runner "PointerEvent" "basic pointer input event smoke"
Assert-Contains $Runner "WheelEvent" "basic wheel input event smoke"
Assert-Contains $Runner "KeyboardEvent" "basic keyboard input event smoke"
Assert-Contains $Runner "navigator\.gpu\.requestAdapter\s*\(" "WebGPU adapter smoke"
Assert-Contains $Runner "adapter\.requestDevice\s*\(" "WebGPU device smoke"
Assert-Contains $Runner "requiresWebGPU:\s*true" "WebGPU-required smoke metadata"
Assert-Contains $Runner "const requireThisTest = args\.requireWebGPU && test\.requiresWebGPU" "WebGPU-only require flag handling"
Assert-Contains $Runner "three\.webgpu\.js" "Three.js WebGPU module smoke"
Assert-Contains $Runner "new THREE\.WebGPURenderer" "Three.js WebGPU renderer smoke"
Assert-Contains $Runner "await renderer\.init" "Three.js WebGPU renderer initialization smoke"
Assert-Contains $Runner "new THREE\.BoxGeometry" "Three.js cube render smoke"
Assert-Contains $Runner "TextureLoader" "texture loader smoke"
Assert-Contains $Runner "createImageBitmap" "createImageBitmap texture smoke"
Assert-Contains $Runner "new THREE\.ShaderMaterial" "shader material smoke"
Assert-Contains $Runner "THREE_VIEWER_RESULT" "benchmark result capture"
Assert-Contains $Runner "parseBenchmarkConsoleResult" "robust benchmark console result parser"
Assert-Contains $Runner "values\[0\]\s*===\s*['""]THREE_VIEWER_RESULT['""]" "two-argument benchmark result parser"
Assert-Contains $Runner "startsWith\s*\(\s*['""]THREE_VIEWER_RESULT ['""]\s*\)" "single-string benchmark result parser"
Assert-Contains $Runner "Browser exited before benchmark result" "browser crash detection during benchmark smoke"
Assert-Contains $Runner "ok:\s*failures\.length\s*===\s*0" "smoke result failure aggregation"
Assert-Contains $Runner "viewerMode" "viewer-mode runtime smoke argument"
Assert-Contains $Runner "--viewer-app-url=.*startupUrl" "viewer-mode runtime smoke startup URL"
Assert-Contains $Runner "--viewer-block-external-navigation" "viewer-mode runtime smoke navigation lock"
Assert-Contains $Runner "viewer_mode:\s*args\.viewerMode" "viewer-mode runtime smoke metadata"
Assert-Contains $Runner "viewer_trusted_content:\s*args\.viewerTrustedContent" "trusted-content runtime smoke metadata"
Assert-Contains $Runner "browser_flags:\s*browserArgs" "effective launch-argument runtime smoke metadata"
Assert-Contains $Runner "browser_extra_flags:\s*args\.browserFlag" "pass-through extra-flag runtime smoke metadata"

Assert-Contains $Validator "requiredPass" "required pass list"
Assert-Contains $Validator "allowedSkip" "allowed skip list"
Assert-Contains $Validator "--require-webgpu" "required WebGPU smoke validation option"
Assert-Contains $Validator "validateRuntimeRequiredWebGpuSmoke" "required WebGPU smoke validation"
Assert-Contains $Validator "must pass when --require-webgpu" "Three.js WebGPU required-pass validation"
Assert-Contains $Validator "ok must be true" "smoke ok validation"
Assert-Contains $Validator "missing required test" "missing-test validation"
Assert-Contains $Validator "must pass" "required-pass validation"
Assert-Contains $Validator "skipped but skip is not allowed" "unexpected skip rejection"
Assert-Contains $Validator "benchmarkRun\.details" "benchmark run details validation"
Assert-Contains $Validator "validateRuntimeWebPlatformDetails" "web-platform smoke detail validation"
Assert-Contains $Validator "web_platform_basics\.details\.canvas_2d" "Canvas 2D smoke detail validation"
Assert-Contains $Validator "web_platform_basics\.details\.fetch_content_type" "local fetch smoke detail validation"
Assert-Contains $Validator "validateRuntimeInputDetails" "input smoke detail validation"
Assert-Contains $Validator "basic_input_events\.details\.events" "input event-list detail validation"
Assert-Contains $Validator "basic_input_events\.details\.key" "keyboard input detail validation"
Assert-Contains $Validator "validateRuntimeWebGpuAdapterDetails" "WebGPU adapter smoke detail validation"
Assert-Contains $Validator "webgpu_adapter_device\.details\.features" "WebGPU adapter feature-list detail validation"
Assert-Contains $Validator "webgpu_adapter_device\.details\.max_texture_dimension_2d" "WebGPU adapter limit detail validation"
Assert-Contains $Validator "validateRuntimeWebGpuDeviceLossDetails" "WebGPU device-loss smoke detail validation"
Assert-Contains $Validator "webgpu_device_loss_signal\.details\.reason" "WebGPU device-loss reason detail validation"
Assert-Contains $Validator "validateRuntimeThreeWebgpuDetails" "Three.js WebGPU smoke detail validation"
Assert-Contains $Validator "three_webgpu_render\.details\.is_webgpu_renderer" "Three.js WebGPU renderer detail validation"
Assert-Contains $Validator "three_webgpu_render\.details\.render_ms" "Three.js WebGPU render timing detail validation"
Assert-Contains $Validator "scene_name" "benchmark scene detail validation"
Assert-Contains $Validator "renderer_type" "benchmark renderer detail validation"
Assert-Contains $Validator "avg_fps" "benchmark FPS detail validation"
Assert-Contains $Validator "frame_count" "benchmark frame-count detail validation"
Assert-Contains $Validator "startup_ms_to_first_frame" "benchmark startup detail validation"
Assert-Contains $Validator "expectViewerMode" "viewer-mode runtime smoke validation option"
Assert-Contains $Validator "expectBrowserMode" "browser-mode runtime smoke validation option"
Assert-Contains $Validator "expectedBrowser" "expected browser validation option"
Assert-Contains $Validator "browser_executable must match expected browser" "expected browser mismatch validation"
Assert-Contains $Validator "viewer_mode must be false" "browser-mode runtime smoke metadata validation"
Assert-Contains $Validator "viewer_mode must be true" "viewer-mode runtime smoke metadata validation"
Assert-Contains $Validator "viewer_trusted_content must be true" "trusted-content runtime smoke metadata validation"
Assert-Contains $Validator "validateOptionalStringArray\(errors,\s*data,\s*'browser_flags'\)" "browser_flags metadata validation"
Assert-Contains $Validator "validateOptionalStringArray\(errors,\s*data,\s*'browser_extra_flags'\)" "browser_extra_flags metadata validation"
Assert-Contains $Validator "\$\{key\} must be an array" "browser flag metadata array validation helper"
Assert-Contains $Validator "--required-browser-flag" "required effective browser flag validation option"
Assert-Contains $Validator "browser_flags must include" "required effective browser flag validation"
Assert-Contains $Validator "many-draw-calls" "benchmark smoke scene expectation"
Assert-Contains $Validator "webgl2" "benchmark smoke renderer expectation"
Assert-Contains $Verifier "validate_smoke_result\.mjs.*--type runtime --require-webgpu" "installed-Chrome smoke verifier requires WebGPU"
Assert-Contains $Audit "Installed-Chrome runtime, input, WebGPU, and graphics-loss smoke" "installed-Chrome smoke audit row names WebGPU"
Assert-Contains $Audit "Installed-Chrome runtime, input, WebGPU, and graphics-loss smoke.*-RequireWebGPU" "installed-Chrome smoke audit requires WebGPU"
Assert-Contains $Audit "Stock baseline runtime smoke with WebGPU.*-ExpectBrowserMode.*-RequireWebGPU" "stock runtime smoke audit requires WebGPU"
Assert-Contains $Audit "Fork runtime smoke with WebGPU.*-ExpectViewerMode.*-ExpectViewerTrustedContent.*-RequireWebGPU" "fork runtime smoke audit requires WebGPU"
Assert-Contains $Validator "validateNavigationDetails" "navigation smoke detail validation"
Assert-Contains $Validator "viewer_app_url" "viewer app URL detail validation"
Assert-Contains $Validator "blocked_origin" "blocked origin detail validation"
Assert-Contains $Validator "external_blocked_url" "external blocked URL detail validation"
Assert-Contains $Validator "blocks_external_http_navigation" "external HTTP navigation smoke validation"
Assert-Contains $Validator "non-loopback host" "external navigation non-loopback host validation"
Assert-Contains $Validator "external_blocked_hits.*must be 0" "external navigation request-hit validation"
Assert-Contains $Validator "blocked_origin_hits" "blocked origin hit-count validation"
Assert-Contains $NavigationRunner "getNonLoopbackIPv4Address" "non-loopback external navigation host selection"
Assert-Contains $NavigationRunner "blocks_external_http_navigation" "external HTTP navigation smoke implementation"
Assert-Contains $NavigationRunner "external_blocked_url" "external HTTP navigation smoke result field"
Assert-Contains $NavigationRunner "external_blocked_hits" "external HTTP navigation request-hit result field"
Assert-Contains $Validator "validateFileNavigationDetails" "file-navigation smoke detail validation"
Assert-Contains $Validator "allowed_file_url" "allowed file URL detail validation"
Assert-Contains $Validator "blocked_file_url" "blocked file URL detail validation"
Assert-Contains $Validator "before_pages" "window-open before-pages validation"
Assert-Contains $Validator "after_pages" "window-open after-pages validation"

Write-Host "Smoke coverage regression checks passed."

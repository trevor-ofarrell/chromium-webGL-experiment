[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempDir = Join-Path $Root "benchmarks\tmp\smoke-detail-validation"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Data
  )
  $Json = $Data | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($PathValue, $Json, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Validator {
  param(
    [string]$Type,
    [string]$PathValue,
    [string[]]$ExtraArgs = @()
  )
  $ProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $ProcessInfo.FileName = "node"
  $ProcessInfo.UseShellExecute = $false
  $ProcessInfo.RedirectStandardOutput = $true
  $ProcessInfo.RedirectStandardError = $true
  $ValidatorPath = Join-Path $Root "scripts\validate_smoke_result.mjs"
  $EscapedValidatorPath = $ValidatorPath -replace '"', '\"'
  $EscapedPathValue = $PathValue -replace '"', '\"'
  $ExtraText = if ($ExtraArgs.Count -gt 0) { " " + ($ExtraArgs -join " ") } else { "" }
  $ProcessInfo.Arguments = "`"$EscapedValidatorPath`" --type $Type$ExtraText `"$EscapedPathValue`""

  $Process = [System.Diagnostics.Process]::Start($ProcessInfo)
  $Stdout = $Process.StandardOutput.ReadToEnd()
  $Stderr = $Process.StandardError.ReadToEnd()
  $Process.WaitForExit()
  $Output = @()
  if ($Stdout) { $Output += $Stdout.TrimEnd() }
  if ($Stderr) { $Output += $Stderr.TrimEnd() }
  return [pscustomobject]@{
    ExitCode = $Process.ExitCode
    Output = @($Output)
  }
}

function Assert-Passes {
  param(
    [string]$Type,
    [string]$PathValue,
    [string]$Description
  )
  $Result = Invoke-Validator -Type $Type -PathValue $PathValue
  if ($Result.ExitCode -ne 0) {
    throw "$Description should pass validation. Output: $($Result.Output -join "`n")"
  }
}

function Assert-FailsWith {
  param(
    [string]$Type,
    [string]$PathValue,
    [string]$Pattern,
    [string]$Description
  )
  $Result = Invoke-Validator -Type $Type -PathValue $PathValue
  if ($Result.ExitCode -eq 0) {
    throw "$Description should fail validation."
  }
  $Text = ($Result.Output | ForEach-Object { [string]$_ }) -join "`n"
  if ($Text -notmatch $Pattern) {
    throw "$Description failed for the wrong reason. Pattern: $Pattern Output: $Text"
  }
}

$RuntimeValid = [pscustomobject]@{
  generated_at = "2026-05-16T00:00:00.000Z"
  platform = "synthetic"
  browser_executable = "synthetic-browser.exe"
  browser_version = "synthetic"
  viewer_mode = $true
  viewer_trusted_content = $true
  viewer_app_url = "http://127.0.0.1:1111/__smoke.html"
  ok = $true
  tests = @(
    [pscustomobject]@{ name = "viewer_launch"; status = "pass" },
    [pscustomobject]@{ name = "webgl2_context"; status = "pass" },
    [pscustomobject]@{ name = "web_platform_basics"; status = "pass"; details = [pscustomobject]@{ canvas_2d = $true; raf_timestamp_ms = 16; performance_delta_ms = 1; fetch_content_type = "image/svg+xml"; fetch_bytes = 100 } },
    [pscustomobject]@{ name = "basic_input_events"; status = "pass"; details = [pscustomobject]@{ events = @("pointerdown", "pointermove", "pointerup", "wheel", "keydown"); pointer_event_constructor = $true; wheel_delta_y = 42; key = "ArrowLeft" } },
    [pscustomobject]@{ name = "webgpu_adapter_device"; status = "pass"; details = [pscustomobject]@{ features = @("timestamp-query"); max_texture_dimension_2d = 8192 } },
    [pscustomobject]@{ name = "webgpu_device_loss_signal"; status = "pass"; details = [pscustomobject]@{ reason = "destroyed"; message = "synthetic destroy" } },
    [pscustomobject]@{ name = "three_webgpu_render"; status = "pass"; details = [pscustomobject]@{ is_webgpu_renderer = $true; backend = "WebGPUBackend"; render_ms = 1.5; canvas_width = 64; canvas_height = 64 } },
    [pscustomobject]@{ name = "three_cube_render"; status = "pass" },
    [pscustomobject]@{ name = "texture_load"; status = "pass" },
    [pscustomobject]@{ name = "shader_material"; status = "pass" },
    [pscustomobject]@{ name = "benchmark_run"; status = "pass"; details = [pscustomobject]@{ scene_name = "many-draw-calls"; renderer_type = "webgl2"; avg_fps = 60; frame_count = 60; startup_ms_to_first_frame = 10 } }
  )
}
$RuntimeBrowserModeValid = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$RuntimeBrowserModeValid.viewer_mode = $false
$RuntimeBrowserModeValid.viewer_trusted_content = $false
$RuntimeBrowserModeValid.viewer_app_url = $null
$RuntimeBrowserModeValidPath = Join-Path $TempDir "runtime-browser-mode-valid.json"
Write-Json $RuntimeBrowserModeValidPath $RuntimeBrowserModeValid
$RuntimeBrowserModeResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeBrowserModeValidPath -ExtraArgs @("--expect-browser-mode")
if ($RuntimeBrowserModeResult.ExitCode -ne 0) {
  throw "valid browser-mode runtime smoke should pass browser-mode validation. Output: $($RuntimeBrowserModeResult.Output -join "`n")"
}
$RuntimeExpectedBrowserResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeBrowserModeValidPath -ExtraArgs @("--expected-browser", "synthetic-browser.exe")
if ($RuntimeExpectedBrowserResult.ExitCode -ne 0) {
  throw "valid runtime smoke should pass expected-browser validation. Output: $($RuntimeExpectedBrowserResult.Output -join "`n")"
}

$RuntimeRequiredFlag = $RuntimeBrowserModeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$RuntimeRequiredFlag | Add-Member -NotePropertyName browser_flags -NotePropertyValue @("--disable-software-rasterizer") -Force
$RuntimeRequiredFlagPath = Join-Path $TempDir "runtime-required-browser-flag-valid.json"
Write-Json $RuntimeRequiredFlagPath $RuntimeRequiredFlag
$RuntimeRequiredFlagResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeRequiredFlagPath -ExtraArgs @("--required-browser-flag", "--disable-software-rasterizer")
if ($RuntimeRequiredFlagResult.ExitCode -ne 0) {
  throw "valid runtime smoke should pass required browser flag validation. Output: $($RuntimeRequiredFlagResult.Output -join "`n")"
}
$RuntimeMissingRequiredFlagResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeBrowserModeValidPath -ExtraArgs @("--required-browser-flag", "--disable-software-rasterizer")
if ($RuntimeMissingRequiredFlagResult.ExitCode -eq 0) {
  throw "runtime smoke without browser_flags should fail required browser flag validation."
}
if (($RuntimeMissingRequiredFlagResult.Output -join "`n") -notmatch "browser_flags.*required-browser-flag") {
  throw "runtime required-browser-flag validation failed for the wrong reason. Output: $($RuntimeMissingRequiredFlagResult.Output -join "`n")"
}

$RuntimeWrongBrowserResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeBrowserModeValidPath -ExtraArgs @("--expected-browser", "other-browser.exe")
if ($RuntimeWrongBrowserResult.ExitCode -eq 0) {
  throw "runtime smoke with the wrong browser_executable should fail expected-browser validation."
}
if (($RuntimeWrongBrowserResult.Output -join "`n") -notmatch "browser_executable must match expected browser") {
  throw "runtime expected-browser validation failed for the wrong reason. Output: $($RuntimeWrongBrowserResult.Output -join "`n")"
}

$RuntimeInvalidBrowserMode = $RuntimeBrowserModeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$RuntimeInvalidBrowserMode.viewer_mode = $true
$RuntimeInvalidBrowserModePath = Join-Path $TempDir "runtime-invalid-browser-mode.json"
Write-Json $RuntimeInvalidBrowserModePath $RuntimeInvalidBrowserMode
$RuntimeInvalidBrowserModeResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeInvalidBrowserModePath -ExtraArgs @("--expect-browser-mode")
if ($RuntimeInvalidBrowserModeResult.ExitCode -eq 0) {
  throw "runtime smoke with viewer_mode=true should fail browser-mode validation."
}
if (($RuntimeInvalidBrowserModeResult.Output -join "`n") -notmatch "viewer_mode must be false") {
  throw "runtime browser-mode validation failed for the wrong reason. Output: $($RuntimeInvalidBrowserModeResult.Output -join "`n")"
}
$RuntimeValidPath = Join-Path $TempDir "runtime-viewer-mode-valid.json"
Write-Json $RuntimeValidPath $RuntimeValid
$RuntimeValidResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeValidPath
if ($RuntimeValidResult.ExitCode -ne 0) {
  throw "valid runtime smoke should pass default validation. Output: $($RuntimeValidResult.Output -join "`n")"
}
$RuntimeMissingInput = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$RuntimeMissingInput.tests = @($RuntimeMissingInput.tests | Where-Object { $_.name -ne "basic_input_events" })
$RuntimeMissingInputPath = Join-Path $TempDir "runtime-missing-basic-input.json"
Write-Json $RuntimeMissingInputPath $RuntimeMissingInput
$RuntimeMissingInputResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeMissingInputPath
if ($RuntimeMissingInputResult.ExitCode -eq 0) {
  throw "runtime smoke without basic_input_events should fail validation."
}
if (($RuntimeMissingInputResult.Output -join "`n") -notmatch "missing required test: basic_input_events") {
  throw "runtime missing-basic-input validation failed for the wrong reason. Output: $($RuntimeMissingInputResult.Output -join "`n")"
}
$RuntimeMissingWebPlatform = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$RuntimeMissingWebPlatform.tests = @($RuntimeMissingWebPlatform.tests | Where-Object { $_.name -ne "web_platform_basics" })
$RuntimeMissingWebPlatformPath = Join-Path $TempDir "runtime-missing-web-platform-basics.json"
Write-Json $RuntimeMissingWebPlatformPath $RuntimeMissingWebPlatform
$RuntimeMissingWebPlatformResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeMissingWebPlatformPath
if ($RuntimeMissingWebPlatformResult.ExitCode -eq 0) {
  throw "runtime smoke without web_platform_basics should fail validation."
}
if (($RuntimeMissingWebPlatformResult.Output -join "`n") -notmatch "missing required test: web_platform_basics") {
  throw "runtime missing-web-platform-basics validation failed for the wrong reason. Output: $($RuntimeMissingWebPlatformResult.Output -join "`n")"
}
$RuntimeInvalidWebPlatform = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($RuntimeInvalidWebPlatform.tests | Where-Object { $_.name -eq "web_platform_basics" }).details.fetch_bytes = 0
$RuntimeInvalidWebPlatformPath = Join-Path $TempDir "runtime-invalid-web-platform-basics.json"
Write-Json $RuntimeInvalidWebPlatformPath $RuntimeInvalidWebPlatform
$RuntimeInvalidWebPlatformResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeInvalidWebPlatformPath
if ($RuntimeInvalidWebPlatformResult.ExitCode -eq 0) {
  throw "runtime smoke with invalid web_platform_basics details should fail validation."
}
if (($RuntimeInvalidWebPlatformResult.Output -join "`n") -notmatch "web_platform_basics\.details\.fetch_bytes") {
  throw "runtime invalid-web-platform-basics validation failed for the wrong reason. Output: $($RuntimeInvalidWebPlatformResult.Output -join "`n")"
}
$RuntimeInvalidInput = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($RuntimeInvalidInput.tests | Where-Object { $_.name -eq "basic_input_events" }).details.events = @("pointerdown", "pointerup", "wheel", "keydown")
$RuntimeInvalidInputPath = Join-Path $TempDir "runtime-invalid-basic-input.json"
Write-Json $RuntimeInvalidInputPath $RuntimeInvalidInput
$RuntimeInvalidInputResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeInvalidInputPath
if ($RuntimeInvalidInputResult.ExitCode -eq 0) {
  throw "runtime smoke with invalid basic_input_events details should fail validation."
}
if (($RuntimeInvalidInputResult.Output -join "`n") -notmatch "basic_input_events\.details\.events must include pointermove") {
  throw "runtime invalid-basic-input validation failed for the wrong reason. Output: $($RuntimeInvalidInputResult.Output -join "`n")"
}
$RuntimeInvalidWebGpuAdapter = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($RuntimeInvalidWebGpuAdapter.tests | Where-Object { $_.name -eq "webgpu_adapter_device" }).details.max_texture_dimension_2d = 0
$RuntimeInvalidWebGpuAdapterPath = Join-Path $TempDir "runtime-invalid-webgpu-adapter-device.json"
Write-Json $RuntimeInvalidWebGpuAdapterPath $RuntimeInvalidWebGpuAdapter
$RuntimeInvalidWebGpuAdapterResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeInvalidWebGpuAdapterPath
if ($RuntimeInvalidWebGpuAdapterResult.ExitCode -eq 0) {
  throw "runtime smoke with invalid webgpu_adapter_device details should fail validation."
}
if (($RuntimeInvalidWebGpuAdapterResult.Output -join "`n") -notmatch "webgpu_adapter_device\.details\.max_texture_dimension_2d") {
  throw "runtime invalid-webgpu-adapter-device validation failed for the wrong reason. Output: $($RuntimeInvalidWebGpuAdapterResult.Output -join "`n")"
}
$RuntimeInvalidWebGpuDeviceLoss = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($RuntimeInvalidWebGpuDeviceLoss.tests | Where-Object { $_.name -eq "webgpu_device_loss_signal" }).details.reason = "unknown"
$RuntimeInvalidWebGpuDeviceLossPath = Join-Path $TempDir "runtime-invalid-webgpu-device-loss.json"
Write-Json $RuntimeInvalidWebGpuDeviceLossPath $RuntimeInvalidWebGpuDeviceLoss
$RuntimeInvalidWebGpuDeviceLossResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeInvalidWebGpuDeviceLossPath
if ($RuntimeInvalidWebGpuDeviceLossResult.ExitCode -eq 0) {
  throw "runtime smoke with invalid webgpu_device_loss_signal details should fail validation."
}
if (($RuntimeInvalidWebGpuDeviceLossResult.Output -join "`n") -notmatch "webgpu_device_loss_signal\.details\.reason") {
  throw "runtime invalid-webgpu-device-loss validation failed for the wrong reason. Output: $($RuntimeInvalidWebGpuDeviceLossResult.Output -join "`n")"
}
$RuntimeInvalidWebGpu = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($RuntimeInvalidWebGpu.tests | Where-Object { $_.name -eq "three_webgpu_render" }).details.is_webgpu_renderer = $false
$RuntimeInvalidWebGpuPath = Join-Path $TempDir "runtime-invalid-three-webgpu-render.json"
Write-Json $RuntimeInvalidWebGpuPath $RuntimeInvalidWebGpu
$RuntimeInvalidWebGpuResult = Invoke-Validator -Type "runtime" -PathValue $RuntimeInvalidWebGpuPath
if ($RuntimeInvalidWebGpuResult.ExitCode -eq 0) {
  throw "runtime smoke with invalid three_webgpu_render details should fail validation."
}
if (($RuntimeInvalidWebGpuResult.Output -join "`n") -notmatch "three_webgpu_render\.details\.is_webgpu_renderer") {
  throw "runtime invalid-three-webgpu-render validation failed for the wrong reason. Output: $($RuntimeInvalidWebGpuResult.Output -join "`n")"
}
$RuntimeWebGpuSkipped = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($RuntimeWebGpuSkipped.tests | Where-Object { $_.name -eq "three_webgpu_render" }).status = "skip"
($RuntimeWebGpuSkipped.tests | Where-Object { $_.name -eq "three_webgpu_render" }).details = [pscustomobject]@{ smoke_status = "skip"; reason = "synthetic WebGPU unavailable" }
$RuntimeWebGpuSkippedPath = Join-Path $TempDir "runtime-skipped-three-webgpu-render.json"
Write-Json $RuntimeWebGpuSkippedPath $RuntimeWebGpuSkipped
$RuntimeWebGpuSkippedDefault = Invoke-Validator -Type "runtime" -PathValue $RuntimeWebGpuSkippedPath
if ($RuntimeWebGpuSkippedDefault.ExitCode -ne 0) {
  throw "runtime smoke with skipped optional WebGPU renderer should pass default validation. Output: $($RuntimeWebGpuSkippedDefault.Output -join "`n")"
}
$RuntimeWebGpuSkippedRequired = Invoke-Validator -Type "runtime" -PathValue $RuntimeWebGpuSkippedPath -ExtraArgs @("--require-webgpu")
if ($RuntimeWebGpuSkippedRequired.ExitCode -eq 0) {
  throw "runtime smoke with skipped WebGPU renderer should fail --require-webgpu validation."
}
if (($RuntimeWebGpuSkippedRequired.Output -join "`n") -notmatch "three_webgpu_render must pass when --require-webgpu") {
  throw "runtime skipped-three-webgpu-render validation failed for the wrong reason. Output: $($RuntimeWebGpuSkippedRequired.Output -join "`n")"
}
$ProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
$ProcessInfo.FileName = "node"
$ProcessInfo.UseShellExecute = $false
$ProcessInfo.RedirectStandardOutput = $true
$ProcessInfo.RedirectStandardError = $true
$ValidatorPath = Join-Path $Root "scripts\validate_smoke_result.mjs"
$ProcessInfo.Arguments = "`"$ValidatorPath`" --type runtime --expect-viewer-mode --expect-viewer-trusted-content `"$RuntimeValidPath`""
$Process = [System.Diagnostics.Process]::Start($ProcessInfo)
$Stdout = $Process.StandardOutput.ReadToEnd()
$Stderr = $Process.StandardError.ReadToEnd()
$Process.WaitForExit()
if ($Process.ExitCode -ne 0) {
  throw "valid viewer-mode runtime smoke should pass viewer-mode validation. Output: $Stdout`n$Stderr"
}

$RuntimeInvalidViewerMode = $RuntimeValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$RuntimeInvalidViewerMode.viewer_mode = $false
$RuntimeInvalidViewerModePath = Join-Path $TempDir "runtime-invalid-viewer-mode.json"
Write-Json $RuntimeInvalidViewerModePath $RuntimeInvalidViewerMode
$ProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
$ProcessInfo.FileName = "node"
$ProcessInfo.UseShellExecute = $false
$ProcessInfo.RedirectStandardOutput = $true
$ProcessInfo.RedirectStandardError = $true
$ProcessInfo.Arguments = "`"$ValidatorPath`" --type runtime --expect-viewer-mode `"$RuntimeInvalidViewerModePath`""
$Process = [System.Diagnostics.Process]::Start($ProcessInfo)
$Stdout = $Process.StandardOutput.ReadToEnd()
$Stderr = $Process.StandardError.ReadToEnd()
$Process.WaitForExit()
if ($Process.ExitCode -eq 0) {
  throw "runtime smoke without viewer_mode=true should fail viewer-mode validation."
}
if ((@($Stdout, $Stderr) -join "`n") -notmatch "viewer_mode must be true") {
  throw "runtime viewer-mode validation failed for the wrong reason. Output: $Stdout`n$Stderr"
}

$NavigationValid = [pscustomobject]@{
  generated_at = "2026-05-16T00:00:00.000Z"
  platform = "synthetic"
  browser_executable = "synthetic-browser.exe"
  browser_version = "synthetic"
  viewer_app_url = "http://127.0.0.1:1111/index.html"
  blocked_origin = "http://127.0.0.1:2222"
  external_blocked_url = "http://203.0.113.10/blocked.html"
  ok = $true
  tests = @(
    [pscustomobject]@{ name = "launches_viewer_app_url"; status = "pass"; details = [pscustomobject]@{ url = "http://127.0.0.1:1111/index.html" } },
    [pscustomobject]@{ name = "allows_same_origin_navigation"; status = "pass"; details = [pscustomobject]@{ url = "http://127.0.0.1:1111/allowed.html" } },
    [pscustomobject]@{ name = "blocks_cross_origin_navigation"; status = "pass"; details = [pscustomobject]@{ url = "http://127.0.0.1:1111/allowed.html"; blocked_origin_hits = 0 } },
    [pscustomobject]@{ name = "blocks_external_http_navigation"; status = "pass"; details = [pscustomobject]@{ url = "http://127.0.0.1:1111/allowed.html"; blocked_url = "http://203.0.113.10/blocked.html"; external_blocked_hits = 0 } },
    [pscustomobject]@{ name = "blocks_window_open"; status = "pass"; details = [pscustomobject]@{ before_pages = 1; after_pages = 1 } }
  )
}
$NavigationValidPath = Join-Path $TempDir "navigation-valid.json"
Write-Json $NavigationValidPath $NavigationValid
Assert-Passes "navigation" $NavigationValidPath "valid navigation smoke details"
$NavigationExpectedBrowserResult = Invoke-Validator -Type "navigation" -PathValue $NavigationValidPath -ExtraArgs @("--expected-browser", "synthetic-browser.exe")
if ($NavigationExpectedBrowserResult.ExitCode -ne 0) {
  throw "valid navigation smoke should pass expected-browser validation. Output: $($NavigationExpectedBrowserResult.Output -join "`n")"
}

$NavigationInvalid = $NavigationValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($NavigationInvalid.tests | Where-Object { $_.name -eq "blocks_cross_origin_navigation" }).details.url = "http://127.0.0.1:2222/blocked.html"
$NavigationInvalidPath = Join-Path $TempDir "navigation-invalid-blocked-origin.json"
Write-Json $NavigationInvalidPath $NavigationInvalid
Assert-FailsWith "navigation" $NavigationInvalidPath "must not land on blocked origin" "navigation smoke with blocked-origin landing"

$NavigationInvalidExternal = $NavigationValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($NavigationInvalidExternal.tests | Where-Object { $_.name -eq "blocks_external_http_navigation" }).details.url = "http://203.0.113.10/blocked.html"
$NavigationInvalidExternalPath = Join-Path $TempDir "navigation-invalid-external-http.json"
Write-Json $NavigationInvalidExternalPath $NavigationInvalidExternal
Assert-FailsWith "navigation" $NavigationInvalidExternalPath "must not equal external_blocked_url" "navigation smoke with external HTTP landing"

$NavigationInvalidExternalHit = $NavigationValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($NavigationInvalidExternalHit.tests | Where-Object { $_.name -eq "blocks_external_http_navigation" }).details.external_blocked_hits = 1
$NavigationInvalidExternalHitPath = Join-Path $TempDir "navigation-invalid-external-hit.json"
Write-Json $NavigationInvalidExternalHitPath $NavigationInvalidExternalHit
Assert-FailsWith "navigation" $NavigationInvalidExternalHitPath "external_blocked_hits must be 0" "navigation smoke with external HTTP request hit"

$NavigationInvalidLoopbackExternal = $NavigationValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$NavigationInvalidLoopbackExternal.external_blocked_url = "http://127.0.0.1:3333/blocked.html"
($NavigationInvalidLoopbackExternal.tests | Where-Object { $_.name -eq "blocks_external_http_navigation" }).details.blocked_url = "http://127.0.0.1:3333/blocked.html"
$NavigationInvalidLoopbackExternalPath = Join-Path $TempDir "navigation-invalid-loopback-external.json"
Write-Json $NavigationInvalidLoopbackExternalPath $NavigationInvalidLoopbackExternal
Assert-FailsWith "navigation" $NavigationInvalidLoopbackExternalPath "non-loopback host" "navigation smoke with loopback external URL"

$FileNavigationValid = [pscustomobject]@{
  generated_at = "2026-05-16T00:00:00.000Z"
  platform = "synthetic"
  browser_executable = "synthetic-browser.exe"
  browser_version = "synthetic"
  viewer_app_path = "C:\synthetic\viewer\index.html"
  viewer_app_url = "file:///C:/synthetic/viewer/index.html"
  allowed_file_url = "file:///C:/synthetic/viewer/assets/allowed.html"
  blocked_file_url = "file:///C:/synthetic/outside/blocked.html"
  ok = $true
  tests = @(
    [pscustomobject]@{ name = "launches_file_viewer_app_path"; status = "pass"; details = [pscustomobject]@{ url = "file:///C:/synthetic/viewer/index.html" } },
    [pscustomobject]@{ name = "allows_viewer_directory_file_navigation"; status = "pass"; details = [pscustomobject]@{ url = "file:///C:/synthetic/viewer/assets/allowed.html" } },
    [pscustomobject]@{ name = "blocks_file_navigation_outside_viewer_directory"; status = "pass"; details = [pscustomobject]@{ url = "file:///C:/synthetic/viewer/assets/allowed.html"; blocked_url = "file:///C:/synthetic/outside/blocked.html" } },
    [pscustomobject]@{ name = "blocks_file_window_open_outside_viewer_directory"; status = "pass"; details = [pscustomobject]@{ before_pages = 1; after_pages = 1 } }
  )
}
$FileNavigationValidPath = Join-Path $TempDir "file-navigation-valid.json"
Write-Json $FileNavigationValidPath $FileNavigationValid
Assert-Passes "file-navigation" $FileNavigationValidPath "valid file-navigation smoke details"
$FileNavigationExpectedBrowserResult = Invoke-Validator -Type "file-navigation" -PathValue $FileNavigationValidPath -ExtraArgs @("--expected-browser", "synthetic-browser.exe")
if ($FileNavigationExpectedBrowserResult.ExitCode -ne 0) {
  throw "valid file-navigation smoke should pass expected-browser validation. Output: $($FileNavigationExpectedBrowserResult.Output -join "`n")"
}

$FileNavigationInvalid = $FileNavigationValid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
($FileNavigationInvalid.tests | Where-Object { $_.name -eq "blocks_file_navigation_outside_viewer_directory" }).details.url = "file:///C:/synthetic/outside/blocked.html"
$FileNavigationInvalidPath = Join-Path $TempDir "file-navigation-invalid-blocked-file.json"
Write-Json $FileNavigationInvalidPath $FileNavigationInvalid
Assert-FailsWith "file-navigation" $FileNavigationInvalidPath "must not equal blocked_file_url" "file-navigation smoke with outside-file landing"

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Smoke detail validation regression checks passed."

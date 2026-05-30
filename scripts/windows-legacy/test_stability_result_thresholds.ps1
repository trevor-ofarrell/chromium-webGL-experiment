[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Source = Join-Path $Root "benchmarks\raw\smoke-installed-chrome-v18-renderer-resource-counters-instancing-webgl2.json"
$TempDir = Join-Path $Root "benchmarks\tmp\stability-threshold-test"
$AuditText = Get-Content (Join-Path $Root "scripts\audit_artifacts.ps1") -Raw
$LongStabilityText = Get-Content (Join-Path $Root "scripts\run_long_stability.ps1") -Raw
$PostAtlText = Get-Content (Join-Path $Root "scripts\run_post_atl_pipeline.ps1") -Raw
$StabilityDocText = Get-Content (Join-Path $Root "docs\stability_behavior.md") -Raw

if (-not (Test-Path $Source)) {
  throw "Required source artifact missing: $Source"
}

if (Test-Path $TempDir) {
  Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function Write-StabilityJson {
  param(
    [string]$PathValue,
    [object]$Value
  )

  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PathValue -Encoding ASCII
}

function Set-JsonProperty {
  param(
    [object]$Target,
    [string]$Name,
    [AllowNull()][object]$Value
  )

  $Target | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Invoke-StabilityValidation {
  param(
    [string]$PathValue,
    [double]$MaxRssDeltaMb = -1,
    [double]$MaxRendererResourceDelta = -1,
    [string[]]$ExtraArgs = @()
  )

  $Command = @(
    (Join-Path $Root "scripts\validate_stability_result.mjs"),
    $PathValue
  )
  if ($MaxRssDeltaMb -ge 0) {
    $Command += @("--maxRssDeltaMb", [string]$MaxRssDeltaMb)
  }
  if ($MaxRendererResourceDelta -ge 0) {
    $Command += @("--maxRendererResourceDelta", [string]$MaxRendererResourceDelta)
  }
  $Command += $ExtraArgs

  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node @Command 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output | ForEach-Object { [string]$_ }) -join " "
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Invoke-LongStabilityExpectFailure {
  param(
    [object[]]$Arguments,
    [string]$Description
  )

  $Command = @((Join-Path $Root "scripts\run_long_stability.ps1"))
  $Command += $Arguments
  $CommandArgs = @($Command | Select-Object -Skip 1)
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Command[0] @CommandArgs *>&1
    $ExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($ExitCode -eq 0) {
    throw "Expected long-stability failure for $Description."
  }
  return ($Output | ForEach-Object { [string]$_ }) -join " "
}

$StablePath = Join-Path $TempDir "stable.json"
$PinRefreshPath = Join-Path $TempDir "chromium-pin-refresh.json"
([pscustomobject]@{
  target_revision = "test-chromium-revision"
  selected_from_upstream_head = $true
  selected_at = "2026-01-01T00:00:00.000Z"
  source = "origin HEAD"
} | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $PinRefreshPath -Encoding ASCII

$Stable = Get-Content $Source -Raw | ConvertFrom-Json
Write-StabilityJson $StablePath $Stable

$Success = Invoke-StabilityValidation $StablePath -MaxRssDeltaMb 1024 -MaxRendererResourceDelta 0
if ($Success.ExitCode -ne 0) {
  throw "Stability validator rejected stable renderer resource counters. Output: $($Success.Output)"
}

$ResourceLeakPath = Join-Path $TempDir "resource-leak.json"
$ResourceLeak = Get-Content $Source -Raw | ConvertFrom-Json
$ResourceLeak.renderer_programs_delta = 1
Write-StabilityJson $ResourceLeakPath $ResourceLeak
$ResourceFailure = Invoke-StabilityValidation $ResourceLeakPath -MaxRendererResourceDelta 0
if ($ResourceFailure.ExitCode -eq 0) {
  throw "Stability validator accepted renderer program growth above threshold."
}
if ($ResourceFailure.Output -notmatch "renderer_programs_delta") {
  throw "Stability validator did not explain renderer program growth. Output: $($ResourceFailure.Output)"
}

$MissingResourcePath = Join-Path $TempDir "missing-resource.json"
$MissingResource = Get-Content $Source -Raw | ConvertFrom-Json
$MissingResource.renderer_memory_textures_delta = $null
Write-StabilityJson $MissingResourcePath $MissingResource
$MissingResourceFailure = Invoke-StabilityValidation $MissingResourcePath -MaxRendererResourceDelta 0
if ($MissingResourceFailure.ExitCode -eq 0) {
  throw "Stability validator accepted missing renderer texture delta under a resource threshold."
}
if ($MissingResourceFailure.Output -notmatch "renderer_memory_textures_delta") {
  throw "Stability validator did not explain missing renderer texture delta. Output: $($MissingResourceFailure.Output)"
}

$RssLeakPath = Join-Path $TempDir "rss-leak.json"
$RssLeak = Get-Content $Source -Raw | ConvertFrom-Json
$RssLeak.process_rss_delta_mb = 129
Write-StabilityJson $RssLeakPath $RssLeak
$RssFailure = Invoke-StabilityValidation $RssLeakPath -MaxRssDeltaMb 128
if ($RssFailure.ExitCode -eq 0) {
  throw "Stability validator accepted RSS growth above threshold."
}
if ($RssFailure.Output -notmatch "process_rss_delta_mb") {
  throw "Stability validator did not explain RSS growth. Output: $($RssFailure.Output)"
}

$OfficialPath = Join-Path $TempDir "official-long-stability.json"
$ExpectedBaselineStabilityBrowser = Join-Path $TempDir "baseline-content_shell.exe"
$ExpectedForkStabilityBrowser = Join-Path $TempDir "fork-content_shell.exe"
$Official = Get-Content $Source -Raw | ConvertFrom-Json
$Official.measured_seconds = 3600
$Official.warmup_seconds = 30
$Official.renderer_type = "webgl2"
$Official.scene_name = "instancing"
$Official.benchmark_variant = "baseline-content-shell-long-stability"
$Official.browser_is_from_checkout = $true
$Official.chromium_revision = "test-chromium-revision"
$Official.build_args_hash = "test-build-args-hash"
Set-JsonProperty $Official "generated_at" "2026-01-02T00:00:00.000Z"
$Official.gpu_name = "ANGLE (NVIDIA, NVIDIA GeForce RTX Test Direct3D11, D3D11)"
$Official.driver_version = "test-driver"
$Official.angle_backend = "ANGLE (NVIDIA, D3D11)"
Set-JsonProperty $Official "browser_executable" $ExpectedBaselineStabilityBrowser
Set-JsonProperty $Official "complexity" 1
$Official.process_rss_delta_mb = 0
$Official.package_size_mb = 120
Set-JsonProperty $Official "viewer_mode" $false
Set-JsonProperty $Official "viewer_block_external_navigation" $false
Set-JsonProperty $Official "viewer_trusted_content" $false
Set-JsonProperty $Official "viewer_aggressive_gpu" $false
Set-JsonProperty $Official "viewer_relaxed_webgl_validation" $false
Set-JsonProperty $Official "viewer_zero_copy" $false
Set-JsonProperty $Official "viewer_in_process_gpu" $false
Set-JsonProperty $Official "viewer_single_process" $false
Set-JsonProperty $Official "viewer_force_angle_backend" $null
Set-JsonProperty $Official "requested_angle_backend" $null
Set-JsonProperty $Official "viewer_disable_unneeded_blink_features" $false
Set-JsonProperty $Official "viewer_direct_gpu_presentation" $false
Set-JsonProperty $Official "viewer_defer_webgpu_pipeline_flush" $false
Set-JsonProperty $Official "viewer_defer_webgpu_queue_flush" $false
Set-JsonProperty $Official "viewer_defer_webgpu_submit_flush" $false
Set-JsonProperty $Official "viewer_skip_webgpu_canvas_texture_validation" $false
Set-JsonProperty $Official "viewer_skip_webgpu_canvas_memory_accounting" $false
Set-JsonProperty $Official "viewer_skip_webgpu_copy_external_image_color_conversion" $false
Set-JsonProperty $Official "viewer_skip_webgpu_copy_external_image_color_space_validation" $false
Set-JsonProperty $Official "viewer_skip_webgpu_copy_external_image_dest_validation" $false
Set-JsonProperty $Official "viewer_skip_webgpu_copy_external_image_source_validation" $false
Set-JsonProperty $Official "viewer_skip_webgpu_copy_external_image_copy_size_validation" $false
Set-JsonProperty $Official "viewer_skip_webgpu_write_texture_layout_validation" $false
Set-JsonProperty $Official "viewer_reject_webgpu_cpu_texture_fallback" $false
Set-JsonProperty $Official "viewer_skip_webgpu_use_counters" $false
Set-JsonProperty $Official "viewer_cache_webgpu_bind_group_layouts" $false
Set-JsonProperty $Official "viewer_skip_webgpu_command_labels" $false
Set-JsonProperty $Official "viewer_skip_webgpu_resource_labels" $false
Set-JsonProperty $Official "viewer_skip_webgpu_shader_source_null_check" $false
Set-JsonProperty $Official "viewer_skip_webgpu_shader_memory_accounting" $false
Set-JsonProperty $Official "viewer_skip_webgpu_redundant_pipeline_sets" $false
Set-JsonProperty $Official "viewer_skip_webgpu_redundant_bind_group_sets" $false
Set-JsonProperty $Official "viewer_skip_webgpu_redundant_buffer_sets" $false
Set-JsonProperty $Official "viewer_skip_webgpu_redundant_render_state_sets" $false
Set-JsonProperty $Official "viewer_trace_webgpu_queue" $false
Set-JsonProperty $Official "resource_warmup_enabled" $false
Set-JsonProperty $Official "resource_warmup_precompile" $false
Set-JsonProperty $Official "resource_warmup_prerender_frames" 0
Set-JsonProperty $Official "browser_flags" @("--disable-software-rasterizer")
Write-StabilityJson $OfficialPath $Official
$OfficialSuccess = Invoke-StabilityValidation `
  $OfficialPath `
  -MaxRssDeltaMb 128 `
  -MaxRendererResourceDelta 0 `
  -ExtraArgs @(
    "--minMeasuredSeconds", "3600",
    "--minWarmupSeconds", "30",
    "--expectedRenderer", "webgl2",
    "--expectedScene", "instancing",
    "--expectedVariant", "baseline-content-shell-long-stability",
    "--requireCheckout",
    "--requireBuildArgs",
    "--expectedBuildArgsHash", "test-build-args-hash",
    "--requireGpuMetadata",
    "--requirePackageSize",
    "--rejectSoftwareRendering",
    "--expectedBrowser", $ExpectedBaselineStabilityBrowser,
    "--expectedFlagMetadata", "viewer_mode=false",
    "--expectedFlagMetadata", "viewer_block_external_navigation=false",
    "--expectedFlagMetadata", "viewer_trusted_content=false",
    "--expectedFlagMetadata", "viewer_defer_webgpu_pipeline_flush=false",
    "--expectedFlagMetadata", "viewer_defer_webgpu_queue_flush=false",
    "--expectedFlagMetadata", "viewer_defer_webgpu_submit_flush=false",
    "--expectedFlagMetadata", "viewer_reject_webgpu_cpu_texture_fallback=false",
    "--expectedFlagMetadata", "viewer_trace_webgpu_queue=false",
    "--expectedFlagMetadata", "resource_warmup_enabled=false",
    "--expectedFlagMetadata", "resource_warmup_precompile=false",
    "--expectedFlagMetadata", "resource_warmup_prerender_frames=0",
    "--pinRefreshManifest", $PinRefreshPath
  )
if ($OfficialSuccess.ExitCode -ne 0) {
  throw "Stability validator rejected official one-hour provenance gates. Output: $($OfficialSuccess.Output)"
}

$DiagnosticOptInPath = Join-Path $TempDir "diagnostic-opt-in-long-stability.json"
$DiagnosticOptIn = Get-Content $OfficialPath -Raw | ConvertFrom-Json
Set-JsonProperty $DiagnosticOptIn "allow_software_rendering" $true
Write-StabilityJson $DiagnosticOptInPath $DiagnosticOptIn
$DiagnosticOptInFailure = Invoke-StabilityValidation `
  $DiagnosticOptInPath `
  -ExtraArgs @("--rejectSoftwareRendering")
if ($DiagnosticOptInFailure.ExitCode -eq 0) {
  throw "Stability validator accepted diagnostic software-rendering opt-in metadata under --rejectSoftwareRendering."
}
if ($DiagnosticOptInFailure.Output -notmatch "diagnostic software-rendering opt-in") {
  throw "Stability validator did not explain diagnostic software-rendering opt-in metadata. Output: $($DiagnosticOptInFailure.Output)"
}

$WrongBuildArgsPath = Join-Path $TempDir "wrong-build-args-long-stability.json"
$WrongBuildArgs = Get-Content $OfficialPath -Raw | ConvertFrom-Json
$WrongBuildArgs.build_args_hash = "different-build-args-hash"
Write-StabilityJson $WrongBuildArgsPath $WrongBuildArgs
$WrongBuildArgsFailure = Invoke-StabilityValidation `
  $WrongBuildArgsPath `
  -ExtraArgs @("--expectedBuildArgsHash", "test-build-args-hash")
if ($WrongBuildArgsFailure.ExitCode -eq 0) {
  throw "Stability validator accepted a result from the wrong GN args hash."
}
if ($WrongBuildArgsFailure.Output -notmatch "build_args_hash") {
  throw "Stability validator did not explain build args hash mismatch. Output: $($WrongBuildArgsFailure.Output)"
}

$WrongBrowserPath = Join-Path $TempDir "wrong-browser-long-stability.json"
$WrongBrowser = Get-Content $OfficialPath -Raw | ConvertFrom-Json
Set-JsonProperty $WrongBrowser "browser_executable" (Join-Path $TempDir "other-content_shell.exe")
Write-StabilityJson $WrongBrowserPath $WrongBrowser
$WrongBrowserFailure = Invoke-StabilityValidation `
  $WrongBrowserPath `
  -ExtraArgs @("--expectedBrowser", $ExpectedBaselineStabilityBrowser)
if ($WrongBrowserFailure.ExitCode -eq 0) {
  throw "Stability validator accepted a result from the wrong browser executable."
}
if ($WrongBrowserFailure.Output -notmatch "browser_executable") {
  throw "Stability validator did not explain browser executable mismatch. Output: $($WrongBrowserFailure.Output)"
}

$StaleGeneratedAtPath = Join-Path $TempDir "stale-generated-at-long-stability.json"
$StaleGeneratedAt = Get-Content $OfficialPath -Raw | ConvertFrom-Json
$StaleGeneratedAt.generated_at = "2000-01-01T00:00:00.000Z"
Write-StabilityJson $StaleGeneratedAtPath $StaleGeneratedAt
$StaleGeneratedAtFailure = Invoke-StabilityValidation `
  $StaleGeneratedAtPath `
  -ExtraArgs @("--pinRefreshManifest", $PinRefreshPath)
if ($StaleGeneratedAtFailure.ExitCode -eq 0) {
  throw "Stability validator accepted a result generated before the pin refresh."
}
if ($StaleGeneratedAtFailure.Output -notmatch "generated_at") {
  throw "Stability validator did not explain stale generated_at. Output: $($StaleGeneratedAtFailure.Output)"
}

$MissingPackagePath = Join-Path $TempDir "missing-package-long-stability.json"
$MissingPackage = Get-Content $OfficialPath -Raw | ConvertFrom-Json
$MissingPackage.package_size_mb = $null
Write-StabilityJson $MissingPackagePath $MissingPackage
$MissingPackageFailure = Invoke-StabilityValidation `
  $MissingPackagePath `
  -ExtraArgs @("--requirePackageSize")
if ($MissingPackageFailure.ExitCode -eq 0) {
  throw "Stability validator accepted missing package_size_mb under --requirePackageSize."
}
if ($MissingPackageFailure.Output -notmatch "package_size_mb") {
  throw "Stability validator did not explain missing package_size_mb. Output: $($MissingPackageFailure.Output)"
}

$ZeroPackagePath = Join-Path $TempDir "zero-package-long-stability.json"
$ZeroPackage = Get-Content $OfficialPath -Raw | ConvertFrom-Json
$ZeroPackage.package_size_mb = 0
Write-StabilityJson $ZeroPackagePath $ZeroPackage
$ZeroPackageFailure = Invoke-StabilityValidation `
  $ZeroPackagePath `
  -ExtraArgs @("--requirePackageSize")
if ($ZeroPackageFailure.ExitCode -eq 0) {
  throw "Stability validator accepted zero package_size_mb under --requirePackageSize."
}
if ($ZeroPackageFailure.Output -notmatch "positive") {
  throw "Stability validator did not explain zero package_size_mb. Output: $($ZeroPackageFailure.Output)"
}

$ShortPath = Join-Path $TempDir "short-long-stability.json"
$Short = Get-Content $OfficialPath -Raw | ConvertFrom-Json
$Short.measured_seconds = 60
Write-StabilityJson $ShortPath $Short
$ShortFailure = Invoke-StabilityValidation `
  $ShortPath `
  -ExtraArgs @("--minMeasuredSeconds", "3600")
if ($ShortFailure.ExitCode -eq 0) {
  throw "Stability validator accepted a short run under --minMeasuredSeconds."
}
if ($ShortFailure.Output -notmatch "measured_seconds") {
  throw "Stability validator did not explain short measured_seconds. Output: $($ShortFailure.Output)"
}

$ForkPath = Join-Path $TempDir "fork-long-stability.json"
$Fork = Get-Content $OfficialPath -Raw | ConvertFrom-Json
$Fork.benchmark_variant = "fork-viewer-default-long-stability"
$Fork.fork_revision = "test-chromium-revision+viewerpatch-test"
Set-JsonProperty $Fork "browser_executable" $ExpectedForkStabilityBrowser
Set-JsonProperty $Fork "viewer_mode" $true
Set-JsonProperty $Fork "viewer_block_external_navigation" $true
Set-JsonProperty $Fork "viewer_trusted_content" $true
Write-StabilityJson $ForkPath $Fork
$ForkSuccess = Invoke-StabilityValidation `
  $ForkPath `
  -ExtraArgs @(
    "--requireForkRevision",
    "--expectedForkRevision", "test-chromium-revision+viewerpatch-test",
    "--expectedVariant", "fork-viewer-default-long-stability",
    "--expectedBrowser", $ExpectedForkStabilityBrowser,
    "--expectedFlagMetadata", "viewer_mode=true",
    "--expectedFlagMetadata", "viewer_block_external_navigation=true",
    "--expectedFlagMetadata", "viewer_trusted_content=true",
    "--expectedFlagMetadata", "viewer_defer_webgpu_pipeline_flush=false",
    "--expectedFlagMetadata", "viewer_defer_webgpu_queue_flush=false",
    "--expectedFlagMetadata", "viewer_defer_webgpu_submit_flush=false",
    "--expectedFlagMetadata", "viewer_reject_webgpu_cpu_texture_fallback=false",
    "--expectedFlagMetadata", "viewer_trace_webgpu_queue=false",
    "--expectedFlagMetadata", "resource_warmup_enabled=false",
    "--expectedFlagMetadata", "resource_warmup_precompile=false",
    "--expectedFlagMetadata", "resource_warmup_prerender_frames=0"
  )
if ($ForkSuccess.ExitCode -ne 0) {
  throw "Stability validator rejected fork revision gates. Output: $($ForkSuccess.Output)"
}

$MissingForkPath = Join-Path $TempDir "missing-fork-long-stability.json"
$MissingFork = Get-Content $ForkPath -Raw | ConvertFrom-Json
$MissingFork.fork_revision = ""
Write-StabilityJson $MissingForkPath $MissingFork
$MissingForkFailure = Invoke-StabilityValidation `
  $MissingForkPath `
  -ExtraArgs @("--requireForkRevision")
if ($MissingForkFailure.ExitCode -eq 0) {
  throw "Stability validator accepted missing fork_revision."
}
if ($MissingForkFailure.Output -notmatch "fork_revision") {
  throw "Stability validator did not explain missing fork_revision. Output: $($MissingForkFailure.Output)"
}

$WrongViewerFlagPath = Join-Path $TempDir "wrong-viewer-flag-long-stability.json"
$WrongViewerFlag = Get-Content $ForkPath -Raw | ConvertFrom-Json
Set-JsonProperty $WrongViewerFlag "viewer_block_external_navigation" $false
Write-StabilityJson $WrongViewerFlagPath $WrongViewerFlag
$WrongViewerFlagFailure = Invoke-StabilityValidation `
  $WrongViewerFlagPath `
  -ExtraArgs @("--expectedFlagMetadata", "viewer_block_external_navigation=true")
if ($WrongViewerFlagFailure.ExitCode -eq 0) {
  throw "Stability validator accepted mismatched viewer_block_external_navigation metadata."
}
if ($WrongViewerFlagFailure.Output -notmatch "viewer_block_external_navigation") {
  throw "Stability validator did not explain viewer_block_external_navigation mismatch. Output: $($WrongViewerFlagFailure.Output)"
}

if ($AuditText -notmatch '--maxRssDeltaMb",\s*\(\[string\]\$DefaultStabilityMaxRssDeltaMb\)' -or
    $AuditText -notmatch '\$DefaultStabilityMaxRssDeltaMb\s*=\s*128') {
  throw "Artifact audit does not enforce the default one-hour stability RSS delta threshold."
}
if ($AuditText -notmatch '--maxRendererResourceDelta",\s*\(\[string\]\$DefaultStabilityMaxRendererResourceDelta\)' -or
    $AuditText -notmatch '\$DefaultStabilityMaxRendererResourceDelta\s*=\s*0') {
  throw "Artifact audit does not enforce the default one-hour stability renderer resource threshold."
}
if ($AuditText -notmatch '--requirePackageSize' -or
    $AuditText -notmatch '-RequirePackageSize') {
  throw "Artifact audit does not require package-size evidence for final one-hour stability rows."
}
if ($AuditText -notmatch '--expectedBuildArgsHash' -or
    $AuditText -notmatch 'ExpectedBuildArgsHash' -or
    $AuditText -notmatch 'src\\out\\ReleaseBaseline\\args\.gn' -or
    $AuditText -notmatch 'src\\out\\ReleaseViewerDefault\\args\.gn') {
  throw "Artifact audit does not bind final one-hour stability rows to expected stock/fork GN args hashes."
}
if ($AuditText -notmatch '--pinRefreshManifest') {
  throw "Artifact audit does not require final one-hour stability rows to follow the current Chromium pin refresh."
}
if ($AuditText -notmatch '--expectedBrowser' -or
    $AuditText -notmatch 'src\\out\\ReleaseBaseline\\content_shell\.exe' -or
    $AuditText -notmatch 'src\\out\\ReleaseViewerDefault\\content_shell\.exe') {
  throw "Artifact audit does not bind final one-hour stability rows to the expected stock/fork browser executables."
}
$StabilityOnlyAuditOutput = Join-Path $TempDir "stability-only-audit.md"
$CanonicalValidAuditPath = Join-Path $Root "benchmarks\raw\baseline-content-shell-long-stability-valid-test.json"
$CanonicalWrongBrowserAuditPath = Join-Path $Root "benchmarks\raw\baseline-content-shell-long-stability-wrong-browser-test.json"
try {
  $ActualChromiumRevision = (Get-Content (Join-Path $Root ".chromium_revision") -Raw).Trim()
  $PinRefresh = Get-Content (Join-Path $Root "benchmarks\reports\chromium-pin-refresh.json") -Raw | ConvertFrom-Json
  $ActualBaselineBuildArgsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root "src\out\ReleaseBaseline\args.gn")).Hash.ToLowerInvariant()
  $ValidAudit = Get-Content $OfficialPath -Raw | ConvertFrom-Json
  $ValidAudit.chromium_revision = $ActualChromiumRevision
  $ValidAudit.build_args_hash = $ActualBaselineBuildArgsHash
  Set-JsonProperty $ValidAudit "generated_at" ([DateTime]::Parse($PinRefresh.selected_at).AddMinutes(1).ToUniversalTime().ToString("o"))
  Set-JsonProperty $ValidAudit "browser_executable" (Join-Path $Root "src\out\ReleaseBaseline\content_shell.exe")
  Write-StabilityJson $CanonicalValidAuditPath $ValidAudit

  $WrongBrowserAudit = Get-Content $OfficialPath -Raw | ConvertFrom-Json
  $WrongBrowserAudit.chromium_revision = $ActualChromiumRevision
  $WrongBrowserAudit.build_args_hash = $ActualBaselineBuildArgsHash
  Set-JsonProperty $WrongBrowserAudit "generated_at" ([DateTime]::Parse($PinRefresh.selected_at).AddMinutes(1).ToUniversalTime().ToString("o"))
  Set-JsonProperty $WrongBrowserAudit "browser_executable" (Join-Path $TempDir "not-the-baseline-content_shell.exe")
  Write-StabilityJson $CanonicalWrongBrowserAuditPath $WrongBrowserAudit

  $AuditCommand = @(
    (Join-Path $Root "scripts\audit_artifacts.ps1"),
    "-StabilityOnly",
    "-Output",
    $StabilityOnlyAuditOutput
  )
  $AuditArgs = @($AuditCommand | Select-Object -Skip 1)
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $AuditOutputText = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AuditCommand[0] @AuditArgs *>&1
    $AuditExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
  if ($AuditExitCode -ne 0) {
    throw "Stability-only artifact audit failed unexpectedly. Output: $(($AuditOutputText | ForEach-Object { [string]$_ }) -join ' ')"
  }
  $StabilityAuditText = Get-Content $StabilityOnlyAuditOutput -Raw
  if ($StabilityAuditText -notmatch "One-hour stock stability result.*done" -or
      $StabilityAuditText -notmatch "valid=1" -or
      $StabilityAuditText -notmatch "browser_executable") {
    throw "Stability-only artifact audit did not reject the wrong-browser long-stability JSON while accepting the valid official artifact. Output: $StabilityAuditText"
  }
} finally {
  if (Test-Path $CanonicalValidAuditPath) {
    Remove-Item -LiteralPath $CanonicalValidAuditPath -Force
  }
  if (Test-Path $CanonicalWrongBrowserAuditPath) {
    Remove-Item -LiteralPath $CanonicalWrongBrowserAuditPath -Force
  }
}
if ($AuditText -notmatch 'Add-StabilityBehaviorDocumentationRow' -or
    $AuditText -notmatch 'validated stock/fork one-hour stability labels' -or
    $AuditText -notmatch 'GPU process crash/restart') {
  throw "Artifact audit does not gate stability behavior documentation on stock/fork one-hour evidence and GPU process crash/restart documentation."
}
foreach ($RequiredTerm in @(
    "GPU process crash/restart",
    "baseline-content-shell-long-stability",
    "fork-viewer-default-long-stability",
    "process_rss_delta_mb <= 128",
    "zero renderer resource growth"
  )) {
  if (-not $StabilityDocText.Contains($RequiredTerm)) {
    throw "docs/stability_behavior.md missing required stability completion term: $RequiredTerm"
  }
}
if ($LongStabilityText -notmatch '\[double\]\$MaxRssDeltaMb\s*=\s*128' -or
    $LongStabilityText -notmatch '\[double\]\$MaxRendererResourceDelta\s*=\s*0') {
  throw "run_long_stability.ps1 does not default to the project stability thresholds."
}
if ($LongStabilityText -notmatch '\$PackageDir\)\s*\{\s*\$StabilityValidation \+= "--requirePackageSize"') {
  throw "run_long_stability.ps1 does not require package_size_mb validation when PackageDir is supplied."
}
if ($LongStabilityText -notmatch 'Require-PackageDirectory' -or
    $LongStabilityText -notmatch 'Long-stability package directory' -or
    $LongStabilityText -notmatch 'viewer\\index\.html' -or
    $LongStabilityText -notmatch 'run_viewer\.ps1') {
  throw "run_long_stability.ps1 does not preflight staged package directories before benchmark execution."
}
if ($LongStabilityText -notmatch 'Require-InputFile' -or
    $LongStabilityText -notmatch 'Browser executable' -or
    $LongStabilityText -notmatch 'Build args') {
  throw "run_long_stability.ps1 does not preflight browser and build-args files before benchmark execution."
}
if ($LongStabilityText -notmatch '--pinRefreshManifest') {
  throw "run_long_stability.ps1 does not require pin-refresh validation when ExpectedChromiumRevision is supplied."
}
if ($LongStabilityText -notmatch '--expectedBrowser') {
  throw "run_long_stability.ps1 does not validate that stability output came from the launched browser executable."
}
if ($LongStabilityText -notmatch 'Get-Sha256' -or
    $LongStabilityText -notmatch '--requireBuildArgs' -or
    $LongStabilityText -notmatch '--expectedBuildArgsHash') {
  throw "run_long_stability.ps1 does not validate stability output against the exact supplied build args hash."
}
if ($LongStabilityText -notmatch '--requiredBrowserFlag') {
  throw "run_long_stability.ps1 does not validate required effective browser launch flags."
}
if ($PostAtlText -notmatch '\[double\]\$MaxRssDeltaMb\s*=\s*128' -or
    $PostAtlText -notmatch '\[double\]\$MaxRendererResourceDelta\s*=\s*0') {
  throw "run_post_atl_pipeline.ps1 does not default to the project stability thresholds."
}

$SyntheticBrowser = Join-Path $TempDir "synthetic-browser.exe"
$SyntheticBuildArgs = Join-Path $TempDir "synthetic-args.gn"
Set-Content -LiteralPath $SyntheticBrowser -Value "synthetic" -Encoding ASCII
Set-Content -LiteralPath $SyntheticBuildArgs -Value "synthetic" -Encoding ASCII

$MissingExpectedRevisionBuildArgsText = Invoke-LongStabilityExpectFailure @(
  "-Browser", $SyntheticBrowser,
  "-ExpectedChromiumRevision", "test-chromium-revision",
  "-Duration", "1",
  "-Warmup", "1",
  "-Label", "expected-revision-without-build-args-preflight"
) "long-stability expected Chromium revision without build args"
if ($MissingExpectedRevisionBuildArgsText -notmatch "Build args is required when ExpectedChromiumRevision is supplied") {
  throw "run_long_stability.ps1 did not clearly reject expected Chromium revision evidence without build args. Output: $MissingExpectedRevisionBuildArgsText"
}
if ($MissingExpectedRevisionBuildArgsText -match "run_benchmark\.mjs|validate_metrics\.mjs|validate_stability_result\.mjs") {
  throw "run_long_stability.ps1 ran benchmark or validation work before rejecting missing build args for expected revision evidence."
}

$EmptyBuildArgs = Join-Path $TempDir "empty-args.gn"
New-Item -ItemType File -Path $EmptyBuildArgs -Force | Out-Null
$EmptyBuildArgsText = Invoke-LongStabilityExpectFailure @(
  "-Browser", $SyntheticBrowser,
  "-BuildArgs", $EmptyBuildArgs,
  "-Duration", "1",
  "-Warmup", "1",
  "-Label", "empty-build-args-preflight"
) "empty long-stability build args"
if ($EmptyBuildArgsText -notmatch "Build args is empty") {
  throw "run_long_stability.ps1 did not clearly reject an empty build args file. Output: $EmptyBuildArgsText"
}
if ($EmptyBuildArgsText -match "run_benchmark\.mjs|validate_metrics\.mjs|validate_stability_result\.mjs") {
  throw "run_long_stability.ps1 input preflight ran benchmark or validation work before rejecting the empty build args file."
}

$MismatchedLongPackage = Join-Path $TempDir "mismatched-long-stability-package"
New-Item -ItemType Directory -Path (Join-Path $MismatchedLongPackage "viewer") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $MismatchedLongPackage "content_shell.exe") -Value "different-browser" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $MismatchedLongPackage "viewer\index.html") -Value "<!doctype html>" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $MismatchedLongPackage "run_viewer.ps1") -Value "Write-Host synthetic" -Encoding ASCII
$MismatchedLongPackageText = Invoke-LongStabilityExpectFailure @(
  "-Browser", $SyntheticBrowser,
  "-Duration", "1",
  "-Warmup", "1",
  "-Label", "mismatched-package-preflight",
  "-PackageDir", $MismatchedLongPackage
) "mismatched long-stability package executable"
if ($MismatchedLongPackageText -notmatch "Long-stability package directory executable does not match expected browser") {
  throw "run_long_stability.ps1 did not clearly reject a package executable mismatch. Output: $MismatchedLongPackageText"
}
if ($MismatchedLongPackageText -match "run_benchmark\.mjs|validate_metrics\.mjs|validate_stability_result\.mjs") {
  throw "run_long_stability.ps1 package preflight ran benchmark or validation work before rejecting the mismatched package executable."
}

$MissingLongPackageText = Invoke-LongStabilityExpectFailure @(
  "-Browser", $SyntheticBrowser,
  "-Duration", "1",
  "-Warmup", "1",
  "-Label", "missing-package-preflight",
  "-PackageDir", (Join-Path $TempDir "missing-long-stability-package")
) "missing supplied long-stability package directory"
if ($MissingLongPackageText -notmatch "Long-stability package directory not found") {
  throw "run_long_stability.ps1 did not clearly reject a missing supplied package directory. Output: $MissingLongPackageText"
}
if ($MissingLongPackageText -match "run_benchmark\.mjs|validate_metrics\.mjs|validate_stability_result\.mjs") {
  throw "run_long_stability.ps1 package preflight ran benchmark or validation work before rejecting the missing package directory."
}

$RequiredFlagPath = Join-Path $TempDir "required-browser-flag.json"
$RequiredFlag = Get-Content $Source -Raw | ConvertFrom-Json
Set-JsonProperty $RequiredFlag "browser_flags" @("--disable-software-rasterizer")
Write-StabilityJson $RequiredFlagPath $RequiredFlag
$RequiredFlagSuccess = Invoke-StabilityValidation $RequiredFlagPath -ExtraArgs @("--requiredBrowserFlag", "--disable-software-rasterizer")
if ($RequiredFlagSuccess.ExitCode -ne 0) {
  throw "stability validator rejected a result with the required browser launch flag. Output: $($RequiredFlagSuccess.Output)"
}
$RequiredFlag.browser_flags = @()
Write-StabilityJson $RequiredFlagPath $RequiredFlag
$RequiredFlagFailure = Invoke-StabilityValidation $RequiredFlagPath -ExtraArgs @("--requiredBrowserFlag", "--disable-software-rasterizer")
if ($RequiredFlagFailure.ExitCode -eq 0) {
  throw "stability validator accepted a result without the required browser launch flag."
}
if ($RequiredFlagFailure.Output -notmatch "browser_flags.*--disable-software-rasterizer") {
  throw "stability validator missing-browser-flag failure did not name browser_flags and --disable-software-rasterizer. Output: $($RequiredFlagFailure.Output)"
}

Remove-Item -LiteralPath $TempDir -Recurse -Force
Write-Host "Stability result validation enforces RSS, renderer resource, duration, provenance, browser executable, build-args hash, package size, fork revision, viewer flag thresholds, required launch flags, and long-stability input/package preflights."

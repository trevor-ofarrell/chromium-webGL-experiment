[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$DocPath = if ($env:THREE_BROWSER_TEST_SOURCE_INVESTIGATION_DOC) {
  if ($env:THREE_BROWSER_ALLOW_TEST_SOURCE_INVESTIGATION_DOC -ne "1") {
    throw "THREE_BROWSER_TEST_SOURCE_INVESTIGATION_DOC requires THREE_BROWSER_ALLOW_TEST_SOURCE_INVESTIGATION_DOC=1."
  }
  $env:THREE_BROWSER_TEST_SOURCE_INVESTIGATION_DOC
} else {
  Join-Path $Root "docs\source_investigation.md"
}

if (-not (Test-Path -LiteralPath $DocPath)) {
  throw "Missing docs\source_investigation.md."
}

$Text = Get-Content -LiteralPath $DocPath -Raw
$RevisionFile = Join-Path $Root ".chromium_revision"
if (-not (Test-Path -LiteralPath $RevisionFile)) {
  throw "Missing .chromium_revision."
}
$ExpectedRevision = (Get-Content -LiteralPath $RevisionFile -Raw).Trim()
if ($ExpectedRevision -notmatch "^[0-9a-f]{40}$") {
  throw ".chromium_revision does not contain a 40-character Chromium revision: $ExpectedRevision"
}

$ActualRevision = (& git -C (Join-Path $Root "src") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualRevision -notmatch "^[0-9a-f]{40}$") {
  throw "Unable to read Chromium checkout revision."
}
if ($ActualRevision -ne $ExpectedRevision) {
  throw "Chromium checkout revision mismatch: .chromium_revision=$ExpectedRevision actual=$ActualRevision"
}

$RevisionMatches = [regex]::Matches($Text, 'Last local verification was at pinned Chromium revision `([0-9a-f]{40})`')
if ($RevisionMatches.Count -ne 1) {
  throw "docs\source_investigation.md must contain exactly one 'Last local verification was at pinned Chromium revision `<sha>`' marker."
}
$DocumentedRevision = $RevisionMatches[0].Groups[1].Value
if ($DocumentedRevision -ne $ExpectedRevision) {
  throw "docs\source_investigation.md verification revision is stale: documented=$DocumentedRevision expected=$ExpectedRevision"
}

$PathMatches = [regex]::Matches($Text, '`(src[\\/][^`]+)`')
if ($PathMatches.Count -eq 0) {
  throw "No backtick-quoted src paths found in docs\source_investigation.md."
}

$SourcePaths = @($PathMatches | ForEach-Object {
    $_.Groups[1].Value.Replace("/", "\").TrimEnd("\")
  } | Sort-Object -Unique)

$MissingPaths = @()
foreach ($SourcePath in $SourcePaths) {
  $FullPath = Join-Path $Root $SourcePath
  if ($SourcePath -match '[*?]') {
    $Matches = @(Get-ChildItem -Path $FullPath -ErrorAction SilentlyContinue)
    if ($Matches.Count -eq 0) {
      $MissingPaths += $SourcePath
    }
  } elseif (-not (Test-Path -LiteralPath $FullPath)) {
    $MissingPaths += $SourcePath
  }
}

if ($MissingPaths.Count -gt 0) {
  throw "Source investigation doc references missing Chromium paths: $($MissingPaths -join '; ')"
}

$SymbolChecks = @(
  @{ Path = "src\content\shell\browser\shell.cc"; Pattern = "Shell::CreateNewWindow"; Name = "content shell window entrypoint" },
  @{ Path = "src\content\shell\browser\shell_content_browser_client.cc"; Pattern = "ShellContentBrowserClient::CreateThrottlesForNavigation"; Name = "content shell navigation throttle hook" },
  @{ Path = "src\third_party\blink\renderer\modules\webgl\webgl_rendering_context_base.cc"; Pattern = "WebGLRenderingContextBase::ValidateDrawArrays"; Name = "WebGL draw validation" },
  @{ Path = "src\third_party\blink\renderer\modules\webgl\webgl_rendering_context_base.cc"; Pattern = "WebGLRenderingContextBase::OnBeforeDrawCall"; Name = "WebGL draw hook" },
  @{ Path = "src\third_party\blink\renderer\modules\webgpu\gpu_canvas_context.cc"; Pattern = "GPUCanvasContext::getCurrentTexture"; Name = "WebGPU canvas presentation" },
  @{ Path = "src\gpu\command_buffer\service\webgpu_decoder_impl.cc"; Pattern = "WebGPUDecoderImpl::RequestAdapterImpl"; Name = "WebGPU adapter request" },
  @{ Path = "src\gpu\command_buffer\service\webgpu_decoder_impl.cc"; Pattern = "WebGPUDecoderImpl::HandleDawnCommands"; Name = "WebGPU Dawn command handling" },
  @{ Path = "src\gpu\command_buffer\service\dawn_caching_interface.cc"; Pattern = "DawnCachingInterface::StoreData"; Name = "Dawn cache store" },
  @{ Path = "src\components\viz\service\display\surface_aggregator.cc"; Pattern = "SurfaceAggregator::Aggregate"; Name = "Viz surface aggregation" },
  @{ Path = "src\content\browser\gpu\gpu_process_host.cc"; Pattern = "GpuProcessHost::LaunchGpuProcess"; Name = "GPU process launch" }
)

$MissingSymbols = @()
foreach ($Check in $SymbolChecks) {
  $FullPath = Join-Path $Root $Check.Path
  if (-not (Test-Path -LiteralPath $FullPath)) {
    $MissingSymbols += "$($Check.Name): missing file $($Check.Path)"
    continue
  }
  $Match = Select-String -LiteralPath $FullPath -SimpleMatch -Pattern $Check.Pattern -Quiet
  if (-not $Match) {
    $MissingSymbols += "$($Check.Name): missing symbol '$($Check.Pattern)' in $($Check.Path)"
  }
}

if ($MissingSymbols.Count -gt 0) {
  throw "Source investigation sentinel checks failed: $($MissingSymbols -join '; ')"
}

Write-Host "Source investigation map resolves $($SourcePaths.Count) Chromium paths and $($SymbolChecks.Count) sentinel symbols at $ActualRevision."

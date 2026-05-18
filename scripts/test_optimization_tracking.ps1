[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$Docs = @(
  "docs\removed_subsystems.md",
  "docs\optimization_log.md",
  "docs\source_investigation.md",
  "docs\trusted_content_flags.md",
  "docs\completion_audit.md",
  "docs\requirement_traceability.md"
)

$CorpusParts = foreach ($Doc in $Docs) {
  $Resolved = Join-Path $Root $Doc
  if (-not (Test-Path $Resolved)) {
    throw "Required documentation file not found: $Doc"
  }
  Get-Content $Resolved -Raw
}
$Corpus = ($CorpusParts -join "`n").ToLowerInvariant()

$RequiredPatterns = @(
  @{ Name = "prompt optimization class decision table"; Pattern = "prompt optimization class decisions" },
  @{ Name = "measured effect column"; Pattern = "measured effect" },
  @{ Name = "final optimization statuses"; Pattern = 'kept`, `reverted`, `blocked`, or `not useful' },
  @{ Name = "remove Chrome browser UI layer"; Pattern = "remove chrome browser ui layer" },
  @{ Name = "minimal content shell style entrypoint"; Pattern = "minimal content shell style entrypoint" },
  @{ Name = "single local trusted origin"; Pattern = "single local trusted origin" },
  @{ Name = "disable extensions"; Pattern = "disable extensions" },
  @{ Name = "disable sync"; Pattern = "disable sync" },
  @{ Name = "disable autofill"; Pattern = "disable autofill" },
  @{ Name = "disable translate"; Pattern = "disable translate" },
  @{ Name = "disable spellcheck"; Pattern = "disable spellcheck" },
  @{ Name = "disable Safe Browsing"; Pattern = "safe browsing" },
  @{ Name = "disable downloads UI"; Pattern = "disable downloads ui" },
  @{ Name = "disable history/bookmarks UI"; Pattern = "disable history/bookmarks ui" },
  @{ Name = "disable unnecessary profile services"; Pattern = "disable unnecessary profile services" },
  @{ Name = "disable unnecessary background networking"; Pattern = "disable unnecessary background networking" },
  @{ Name = "reduce renderer process overhead"; Pattern = "reduce renderer process overhead" },
  @{ Name = "single-process/in-process GPU"; Pattern = "single-process/in-process gpu" },
  @{ Name = "ANGLE backend choices"; Pattern = "angle backend" },
  @{ Name = "Vulkan backend"; Pattern = "vulkan" },
  @{ Name = "D3D11 backend"; Pattern = "d3d11" },
  @{ Name = "OpenGL/EGL backend"; Pattern = "opengl/egl" },
  @{ Name = "Metal backend"; Pattern = "metal" },
  @{ Name = "passthrough command decoder"; Pattern = "passthrough command decoder" },
  @{ Name = "WebGL validation overhead"; Pattern = "webgl validation" },
  @{ Name = "shader compilation strategy"; Pattern = "shader compilation" },
  @{ Name = "WebGPU pipeline caching/warmup"; Pattern = "webgpu pipeline" },
  @{ Name = "compositor bypass or simplified presentation path"; Pattern = "compositor bypass" },
  @{ Name = "direct GPU texture presentation/export"; Pattern = "direct gpu texture presentation/export" },
  @{ Name = "removing unused Blink modules"; Pattern = "removing unused blink modules" },
  @{ Name = "disabling layout/style/DOM features"; Pattern = "layout/style/dom" },
  @{ Name = "disabling media"; Pattern = "media" },
  @{ Name = "printing"; Pattern = "printing" },
  @{ Name = "PDF"; Pattern = "pdf" },
  @{ Name = "WebRTC"; Pattern = "webrtc" },
  @{ Name = "accessibility"; Pattern = "accessibility" },
  @{ Name = "password manager"; Pattern = "password manager" },
  @{ Name = "payments"; Pattern = "payments" },
  @{ Name = "V8 flags"; Pattern = "v8 flags" },
  @{ Name = "memory allocator"; Pattern = "memory allocator" },
  @{ Name = "process model choices"; Pattern = "process model choices" }
)

$Missing = @()
foreach ($Entry in $RequiredPatterns) {
  if (-not $Corpus.Contains($Entry.Pattern.ToLowerInvariant())) {
    $Missing += "$($Entry.Name) [$($Entry.Pattern)]"
  }
}

if ($Missing.Count -gt 0) {
  throw "Optimization tracking docs are missing: $($Missing -join '; ')"
}

Write-Host "Optimization class tracking documentation covers all prompt-required families."

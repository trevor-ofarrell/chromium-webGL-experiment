[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile {
  param([string]$PathValue)
  $Resolved = Join-Path $Root $PathValue
  if (-not (Test-Path $Resolved)) {
    throw "Required documentation file not found: $PathValue"
  }
  return Get-Content $Resolved -Raw
}

function Assert-ContainsLiteral {
  param(
    [string]$PathValue,
    [string]$Text,
    [string]$Term
  )
  if ($Text -notmatch [regex]::Escape($Term)) {
    throw "$PathValue missing required documentation term: $Term"
  }
}

function Assert-MarkdownDocument {
  param(
    [string]$PathValue,
    [string[]]$Terms
  )

  $Text = Read-RepoFile $PathValue
  if ($Text.Trim().Length -lt 120) {
    throw "$PathValue is too small to be useful documentation."
  }
  if ($Text -notmatch '(?m)^#\s+') {
    throw "$PathValue does not contain a top-level Markdown heading."
  }
  foreach ($Term in $Terms) {
    Assert-ContainsLiteral $PathValue $Text $Term
  }
}

$DocumentSpecs = @(
  [pscustomobject]@{
    Path = "README.md"
    Terms = @(
      "single-purpose Three.js/WebGL/WebGPU 3D viewer runtime",
      ".chromium_revision",
      "verify_prebuild.ps1",
      "install_vs_atl.ps1",
      "run_post_atl_pipeline.ps1",
      "-RefreshChromiumPin",
      "-IncludeWebGPU",
      "-IncludeAggressiveGpu",
      "-AggressiveAngleBackend d3d11",
      "-CaptureTrace",
      "-RunTrustedExperimentMatrix",
      "-TrustedMatrixInProcessGpu",
      "-TrustedMatrixSingleProcess",
      "-TrustedMatrixAngleBackend d3d11",
      "-TrustedMatrixReservedNoopGates",
      "-RunLongStability",
      "-MaxRssDeltaMb 128",
      "-MaxRendererResourceDelta 0",
      "-FinalGate",
      "not the official same-revision Chromium baseline"
    )
  },
  [pscustomobject]@{
    Path = "docs\architecture.md"
    Terms = @(
      "content_shell",
      "Blink",
      "V8",
      "WebGL2",
      "WebGPU",
      "GPU process",
      "WebContents",
      "Trusted-content aggressive modes"
    )
  },
  [pscustomobject]@{
    Path = "docs\build.md"
    Terms = @(
      "Microsoft.VisualStudio.Component.VC.ATLMFC",
      "install_vs_atl.ps1",
      "verify_prebuild.ps1",
      "refresh_chromium_pin.ps1",
      "ReleaseBaseline",
      "ReleaseViewerDefault",
      "stage_viewer_package.ps1",
      "-ChromiumOutDir",
      "run_post_atl_pipeline.ps1",
      "-RefreshChromiumPin",
      "-IncludeWebGPU",
      "-IncludeAggressiveGpu",
      "-AggressiveAngleBackend d3d11",
      "-CaptureTrace",
      "-RunTrustedExperimentMatrix",
      "-TrustedMatrixAngleBackend d3d11",
      "-MaxRssDeltaMb 128",
      "-MaxRendererResourceDelta 0",
      "-FinalGate"
    )
  },
  [pscustomobject]@{
    Path = "docs\benchmark_methodology.md"
    Terms = @(
      "Required Scene Suite",
      "Official Comparison",
      "Metric Schema",
      "chromium_revision",
      "startup_ms_to_first_frame",
      "software-renderer rejection",
      "Trusted matrix manifest",
      "Stability",
      "Trace Capture"
    )
  },
  [pscustomobject]@{
    Path = "docs\optimization_log.md"
    Terms = @(
      "| Optimization class | Status | Measured effect | Risk | Relevant evidence | Notes |",
      "content_shell",
      "trusted-content",
      "official-comparison-manifest.json",
      "Prompt Optimization Class Decisions"
    )
  },
  [pscustomobject]@{
    Path = "docs\removed_subsystems.md"
    Terms = @(
      "Rationale",
      "Regression risk",
      "Current evidence",
      "Final Register",
      "Prompt Optimization Class Tracking",
      "Subsystems Explicitly Kept For Now",
      "Update Rule"
    )
  },
  [pscustomobject]@{
    Path = "docs\known_limitations.md"
    Terms = @(
      "Windows NVIDIA ANGLE D3D11",
      "WebGPU GPU timestamp timing is disabled",
      "does not improve average WebGL2 FPS",
      "smaller friendly window"
    )
  },
  [pscustomobject]@{
    Path = "docs\future_work.md"
    Terms = @(
      "additional GPUs and drivers",
      "direct presentation prototype",
      "source-level",
      "WebGPU pipeline cache",
      "Automate rebase checks"
    )
  },
  [pscustomobject]@{
    Path = "docs\rebase_strategy.md"
    Terms = @(
      ".chromium_revision",
      'run the post-ATL pipeline with `-RefreshChromiumPin`',
      "stock baseline and fork from the same revision",
      "Gate unsafe experiments with viewer-specific switches"
    )
  },
  [pscustomobject]@{
    Path = "docs\source_investigation.md"
    Terms = @(
      "Minimal Viewer Entrypoint",
      "WebGL Path",
      "WebGPU Path",
      "Compositor And Presentation Path",
      "GPU Process, ANGLE, And Backend Choice",
      "Content Shell Services And Feature Removal Candidates"
    )
  },
  [pscustomobject]@{
    Path = "docs\trusted_content_flags.md"
    Terms = @(
      "--viewer-app-url",
      "--viewer-trusted-content",
      "--viewer-aggressive-gpu",
      "--viewer-force-angle-backend",
      "Reserved gate only",
      "Benchmark metadata fields"
    )
  },
  [pscustomobject]@{
    Path = "docs\stability_behavior.md"
    Terms = @(
      "WebGL Context Loss",
      "WebGPU Device Loss",
      "Resource Growth Fields",
      "process_rss_delta_mb <= 128",
      "NVIDIA ANGLE D3D11"
    )
  },
  [pscustomobject]@{
    Path = "docs\webgpu_scene_coverage.md"
    Terms = @(
      "official WebGPU suite",
      "WebGPURenderer",
      "gltf-loader-stress",
      "timestamp queries caused device loss"
    )
  },
  [pscustomobject]@{
    Path = "docs\completion_audit.md"
    Terms = @(
      "Deliverables",
      "Build Completion",
      "Runtime Completion",
      "Performance Completion",
      "Stability Completion",
      "Remaining Bottlenecks",
      "Final Gate",
      "audit_artifacts.ps1"
    )
  },
  [pscustomobject]@{
    Path = "docs\requirement_traceability.md"
    Terms = @(
      "Start from current Chromium source",
      "official-comparison-manifest.json",
      "same Chromium revision",
      "Trusted matrix manifest",
      "run_post_atl_pipeline.ps1",
      "-FinalGate"
    )
  }
)

foreach ($Spec in $DocumentSpecs) {
  Assert-MarkdownDocument -PathValue $Spec.Path -Terms $Spec.Terms
}

Write-Host "Documentation structure checks passed for $($DocumentSpecs.Count) required documentation files."

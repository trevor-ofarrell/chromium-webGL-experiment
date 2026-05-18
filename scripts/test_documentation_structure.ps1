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
      "bootstrap_chromium.ps1",
      "verify_prebuild.ps1",
      "refresh_chromium_pin.ps1",
      "ReleaseBaseline",
      "ReleaseViewerDefault",
      "run_post_atl_pipeline.ps1",
      "-IncludeWebGPU",
      "-IncludeAggressiveGpu",
      "-AggressiveAngleBackend d3d11",
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
      "Required Comparisons",
      "Scene Suite",
      "Metric Schema",
      "chromium_revision",
      "startup_ms_to_first_frame",
      "Official comparison workflow",
      "Trusted experiment matrix",
      "Long-run stability",
      "Prompt-to-artifact audit"
    )
  },
  [pscustomobject]@{
    Path = "docs\optimization_log.md"
    Terms = @(
      "| ID | Optimization | Status | Mode | Evidence | Risk | Relevant files | Notes |",
      "content_shell",
      "trusted-content",
      "same-revision",
      "O-124"
    )
  },
  [pscustomobject]@{
    Path = "docs\removed_subsystems.md"
    Terms = @(
      "Rationale",
      "Regression risk",
      "Current evidence",
      "no Chromium subsystem has been physically removed",
      "not accepted as completed optimization work"
    )
  },
  [pscustomobject]@{
    Path = "docs\known_limitations.md"
    Terms = @(
      "ATL/MFC",
      "Installed Chrome smoke results are harness validation only",
      "not accepted as baseline evidence",
      "one-hour stock and fork stability runs"
    )
  },
  [pscustomobject]@{
    Path = "docs\future_work.md"
    Terms = @(
      'Build the stock `content_shell` baseline',
      "Apply the viewer entrypoint patch",
      "WebGL2 and WebGPU benchmark suites",
      "trusted-only aggressive flags",
      "one-hour stock and fork stability loops"
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
      "Raw benchmark JSON records"
    )
  },
  [pscustomobject]@{
    Path = "docs\stability_behavior.md"
    Terms = @(
      "WebGL Context Loss",
      "WebGPU Device Loss",
      "Resource Growth Fields",
      "process_rss_delta_mb <= 128",
      "one-hour stock/fork stability runs remain pending"
    )
  },
  [pscustomobject]@{
    Path = "docs\webgpu_scene_coverage.md"
    Terms = @(
      "installed Chrome only",
      "not same-revision stock/fork performance evidence",
      "gltf-loader-stress",
      "Required Follow-Up"
    )
  },
  [pscustomobject]@{
    Path = "docs\completion_audit.md"
    Terms = @(
      "Status: not complete",
      "Primary Deliverables",
      "Build Completion",
      "Runtime Completion",
      "Performance Completion",
      "Optimization Completion",
      "Stability Completion",
      "Documentation Completion",
      "Current Blocking Command",
      "run_post_atl_pipeline.ps1"
    )
  },
  [pscustomobject]@{
    Path = "docs\requirement_traceability.md"
    Terms = @(
      "Current Hard Blocker",
      "Microsoft.VisualStudio.Component.VC.ATLMFC",
      "same-revision",
      "Trusted experiment matrix",
      "Prompt-to-artifact audit",
      "-FinalGate"
    )
  }
)

foreach ($Spec in $DocumentSpecs) {
  Assert-MarkdownDocument -PathValue $Spec.Path -Terms $Spec.Terms
}

Write-Host "Documentation structure checks passed for $($DocumentSpecs.Count) required documentation files."

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
    [string]$Label,
    [string]$Text,
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "$Label missing benchmark metadata enrichment evidence: $Description. Pattern: $Pattern"
  }
}

$Runner = Read-RepoFile "scripts\run_benchmark.mjs"
$Validator = Read-RepoFile "scripts\validate_metrics.mjs"
$BenchmarkDocs = Read-RepoFile "docs\benchmark_methodology.md"
$OfficialWorkflow = Read-RepoFile "scripts\run_official_comparison.ps1"
$TrustedWorkflow = Read-RepoFile "scripts\run_trusted_experiment_matrix.ps1"

Assert-Contains "run_benchmark.mjs" $Runner "crypto\.createHash\('sha256'\)\.update\(text\)\.digest\('hex'\)" "build args hash uses SHA-256"
Assert-Contains "run_benchmark.mjs" $Runner "buildArgsPath\s*=\s*args\.buildArgs\s*\?\s*path\.resolve\(args\.buildArgs\)" "build args path is resolved"
Assert-Contains "run_benchmark.mjs" $Runner "buildArgsText\s*=\s*buildArgsPath\s*&&\s*fs\.existsSync\(buildArgsPath\)" "build args text is read only from an existing file"
Assert-Contains "run_benchmark.mjs" $Runner "result\.build_args_hash\s*=\s*result\.build_args_hash\s*\|\|\s*\(buildArgsText\s*\?\s*sha256Text\(buildArgsText\)\s*:\s*null\)" "result build_args_hash is populated from the GN args file"

Assert-Contains "run_benchmark.mjs" $Runner "checkoutRevision\s*=\s*getGitRevision\(path\.join\(rootDir,\s*'src'\)\)" "checkout revision is read from src"
Assert-Contains "run_benchmark.mjs" $Runner "pinnedChromiumRevision\s*=\s*readTextIfExists\(path\.join\(rootDir,\s*'\.chromium_revision'\)\)\.trim\(\)\s*\|\|\s*checkoutRevision" "pinned Chromium revision is read from .chromium_revision"
Assert-Contains "run_benchmark.mjs" $Runner "browserIsFromCheckout\s*=\s*browser\.startsWith\([^)]*srcDir[^)]*path\.sep[^)]*\)" "checkout-built browser detection uses the src path"
Assert-Contains "run_benchmark.mjs" $Runner "chromiumRevision\s*=\s*browserIsFromCheckout\s*\?\s*pinnedChromiumRevision\s*:\s*browserVersion" "checkout-built results use pinned Chromium revision"
Assert-Contains "run_benchmark.mjs" $Runner "forkRevision\s*=\s*args\.forkRevision\s*\|\|\s*\(browserIsFromCheckout\s*&&\s*isForkVariant\s*\?\s*checkoutRevision\s*:\s*null\)" "fork revision is explicit or checkout-derived for fork variants"
Assert-Contains "run_benchmark.mjs" $Runner "result\.chromium_revision\s*=\s*result\.chromium_revision\s*\|\|\s*chromiumRevision\s*\|\|\s*null" "chromium_revision is added to result JSON"
Assert-Contains "run_benchmark.mjs" $Runner "result\.fork_revision\s*=\s*result\.fork_revision\s*\|\|\s*forkRevision\s*\|\|\s*null" "fork_revision is added to result JSON"
Assert-Contains "run_benchmark.mjs" $Runner "result\.browser_is_from_checkout\s*=\s*browserIsFromCheckout" "checkout-built metadata is added to result JSON"

Assert-Contains "run_benchmark.mjs" $Runner "SystemInfo\.getInfo" "GPU metadata is collected through CDP SystemInfo"
Assert-Contains "run_benchmark.mjs" $Runner "Performance\.getMetrics" "JS heap metadata is collected through CDP Performance"
Assert-Contains "run_benchmark.mjs" $Runner "result\.gpu_name\s*=\s*result\.gpu_name\s*\|\|\s*gpuDevice\?\.deviceString\s*\|\|\s*null" "gpu_name is populated"
Assert-Contains "run_benchmark.mjs" $Runner "result\.driver_version\s*=\s*result\.driver_version\s*\|\|\s*gpuDevice\?\.driverVendor\s*\|\|\s*gpuDevice\?\.driverVersion\s*\|\|\s*null" "driver_version is populated"
Assert-Contains "run_benchmark.mjs" $Runner "requestedAngleBackend\s*=\s*args\.angleBackend\s*\|\|\s*args\.viewerForceAngleBackend\s*\|\|\s*null" "requested backend is derived from direct ANGLE or viewer alias"
Assert-Contains "run_benchmark.mjs" $Runner "result\.requested_angle_backend\s*=\s*requestedAngleBackend" "requested backend metadata is populated"
Assert-Contains "run_benchmark.mjs" $Runner "result\.angle_backend\s*=\s*result\.angle_backend\s*\|\|\s*requestedAngleBackend" "angle_backend falls back to requested backend"

Assert-Contains "run_benchmark.mjs" $Runner "function getProcessTreeRssMb\(pid\)" "process-tree RSS sampler exists"
Assert-Contains "run_benchmark.mjs" $Runner "Get-CimInstance Win32_Process" "Windows RSS sampler walks process tree"
Assert-Contains "run_benchmark.mjs" $Runner "ps', \['-e', '-o', 'pid=,ppid=,rss='\]" "POSIX RSS sampler walks process tree"
Assert-Contains "run_benchmark.mjs" $Runner "rssSamples\.push" "RSS samples are collected during benchmark run"
Assert-Contains "run_benchmark.mjs" $Runner "result\.process_rss_start_mb\s*=" "process RSS start is recorded"
Assert-Contains "run_benchmark.mjs" $Runner "result\.process_rss_peak_mb\s*=" "process RSS peak is recorded"
Assert-Contains "run_benchmark.mjs" $Runner "result\.process_rss_delta_mb\s*=" "process RSS delta is recorded"

Assert-Contains "run_benchmark.mjs" $Runner "result\.browser_binary_size_mb\s*=\s*fileSizeMb\(browser\)" "browser executable size is recorded"
Assert-Contains "run_benchmark.mjs" $Runner "result\.viewer_bundle_size_mb\s*=\s*directorySizeMb\(viewerDir\)" "viewer bundle size is recorded"
Assert-Contains "run_benchmark.mjs" $Runner "result\.package_size_mb\s*=\s*packageDir\s*\?\s*directorySizeMb\(packageDir\)\s*:\s*null" "package size is recorded only when package dir is supplied"
Assert-Contains "run_benchmark.mjs" $Runner "result\.generated_at\s*=\s*result\.generated_at\s*\|\|\s*new Date\(\)\.toISOString\(\)" "generated_at timestamp is recorded for pin-refresh provenance checks"

Assert-Contains "run_benchmark.mjs" $Runner "fs\.mkdirSync\(path\.dirname\(path\.resolve\(args\.output\)\),\s*\{\s*recursive:\s*true\s*\}\)" "runner creates benchmark output directory"
Assert-Contains "run_benchmark.mjs" $Runner "fs\.writeFileSync\(path\.resolve\(args\.output\),[\s\S]*JSON\.stringify\(result,\s*null,\s*2\)" "runner writes enriched JSON output"
Assert-Contains "run_benchmark.mjs" $Runner "ensureSchema\(result\)" "runner fills required schema fields before writing"

foreach ($Field in @(
    "browser_executable",
    "browser_version",
    "generated_at",
    "benchmark_variant",
    "browser_is_from_checkout",
    "process_rss_start_mb",
    "process_rss_peak_mb",
    "process_rss_end_mb",
    "process_rss_delta_mb"
  )) {
  Assert-Contains "validate_metrics.mjs" $Validator "'$Field'" "validator recognizes optional metadata field $Field"
}

Assert-Contains "docs/benchmark_methodology.md" $BenchmarkDocs "package metadata, creates the output directory, and writes the final\s+machine-readable JSON file" "benchmark docs describe harness-owned output writing"
Assert-Contains "docs/benchmark_methodology.md" $BenchmarkDocs "Fork benchmark results must identify the actual fork patch content" "benchmark docs describe patch-derived fork revision"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "Get-ViewerForkRevision" "official workflow computes patch-derived fork revision"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow "Get-ViewerForkRevision" "trusted workflow computes patch-derived fork revision"

Write-Host "Benchmark metadata enrichment checks passed for provenance, GPU/RSS/size metadata, and output ownership."

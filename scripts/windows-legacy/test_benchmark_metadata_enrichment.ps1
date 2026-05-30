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
$FullSuiteWorkflow = Read-RepoFile "scripts\run_full_suite.ps1"
$BlockerWorkflow = Read-RepoFile "scripts\run_blocker_experiments.ps1"

Assert-Contains "run_benchmark.mjs" $Runner "crypto\.createHash\('sha256'\)\.update\(text\)\.digest\('hex'\)" "build args hash uses SHA-256"
Assert-Contains "run_benchmark.mjs" $Runner "buildArgsPath\s*=\s*args\.buildArgs\s*\?\s*path\.resolve\(args\.buildArgs\)" "build args path is resolved"
Assert-Contains "run_benchmark.mjs" $Runner "buildArgsText\s*=\s*buildArgsPath\s*&&\s*fs\.existsSync\(buildArgsPath\)" "build args text is read only from an existing file"
Assert-Contains "run_benchmark.mjs" $Runner "result\.build_args_hash\s*=\s*result\.build_args_hash\s*\|\|\s*\(buildArgsText\s*\?\s*sha256Text\(buildArgsText\)\s*:\s*null\)" "result build_args_hash is populated from the GN args file"
Assert-Contains "run_benchmark.mjs" $Runner "function assertFiniteBenchmarkNumber\(value, name" "benchmark runner has explicit numeric input validation"
Assert-Contains "run_benchmark.mjs" $Runner "assertFiniteBenchmarkNumber\(duration,\s*['""]duration['""]\)" "benchmark runner rejects invalid duration before launch"
Assert-Contains "run_benchmark.mjs" $Runner "assertFiniteBenchmarkNumber\(warmup,\s*['""]warmup['""],\s*\{\s*allowZero:\s*true\s*\}\)" "benchmark runner accepts only finite non-negative warmup before launch"
Assert-Contains "run_benchmark.mjs" $Runner "assertFiniteBenchmarkNumber\(complexity,\s*['""]complexity['""]\)" "benchmark runner rejects invalid or zero complexity before launch"
Assert-Contains "run_benchmark.mjs" $Runner "function assertNonNegativeIntegerBenchmarkNumber\(value, name\)" "benchmark runner has explicit integer input validation"
Assert-Contains "run_benchmark.mjs" $Runner "assertNonNegativeIntegerBenchmarkNumber\(prerenderFrames,\s*['""]prerenderFrames['""]\)" "benchmark runner rejects invalid prerender frame count before launch"
Assert-Contains "run_benchmark.mjs" $Runner "assertNonNegativeIntegerBenchmarkNumber\(pipelineQuietFrames,\s*['""]pipelineQuietFrames['""]\)" "benchmark runner rejects invalid WebGPU pipeline-quiet frame count before launch"
Assert-Contains "run_benchmark.mjs" $Runner "assertNonNegativeIntegerBenchmarkNumber\(pipelineQuietMaxFrames,\s*['""]pipelineQuietMaxFrames['""]\)" "benchmark runner rejects invalid WebGPU pipeline-quiet max frame count before launch"
Assert-Contains "run_benchmark.mjs" $Runner "pipelineQuietFrames > 0 && pipelineQuietMaxFrames < pipelineQuietFrames" "benchmark runner rejects pipeline-quiet max frame normalization"
Assert-Contains "run_benchmark.mjs" $Runner "prerenderFrames:\s*String\(prerenderFrames\)" "benchmark runner forwards normalized prerender frame count"
Assert-Contains "run_benchmark.mjs" $Runner "pipelineQuietFrames:\s*String\(pipelineQuietFrames\)" "benchmark runner forwards normalized pipeline-quiet frame count"
Assert-Contains "run_benchmark.mjs" $Runner "pipelineQuietMaxFrames:\s*String\(pipelineQuietMaxFrames\)" "benchmark runner forwards normalized pipeline-quiet max frame count"

Assert-Contains "run_benchmark.mjs" $Runner "checkoutRevision\s*=\s*getGitRevision\(path\.join\(rootDir,\s*'src'\)\)" "checkout revision is read from src"
Assert-Contains "run_benchmark.mjs" $Runner "pinnedChromiumRevision\s*=\s*readTextIfExists\(path\.join\(rootDir,\s*'\.chromium_revision'\)\)\.trim\(\)\s*\|\|\s*checkoutRevision" "pinned Chromium revision is read from .chromium_revision"
Assert-Contains "run_benchmark.mjs" $Runner "browserIsFromCheckout\s*=\s*browser\.startsWith\([^)]*srcDir[^)]*path\.sep[^)]*\)" "checkout-built browser detection uses the src path"
Assert-Contains "run_benchmark.mjs" $Runner "chromiumRevision\s*=\s*browserIsFromCheckout\s*\?\s*pinnedChromiumRevision\s*:\s*browserVersion" "checkout-built results use pinned Chromium revision"
Assert-Contains "run_benchmark.mjs" $Runner "function getViewerPatchRevision\(chromiumRevision\)" "viewer patch fork revision helper exists"
Assert-Contains "run_benchmark.mjs" $Runner "viewerPatchSeries" "viewer patch hash source is the full Chromium patch series"
Assert-Contains "run_benchmark.mjs" $Runner "0001-draft-minimal-three-viewer-entrypoint\.patch" "viewer patch series includes the minimal entrypoint patch"
Assert-Contains "run_benchmark.mjs" $Runner "0002-draft-webgpu-queue-trace-attribution\.patch" "viewer patch series includes the WebGPU queue trace attribution patch"
Assert-Contains "run_benchmark.mjs" $Runner "entries\.push\([\s\S]*patchRelativePath[\s\S]*sha256Text\(fs\.readFileSync\(patchPath\)\)" "viewer patch fork revision hashes each patch-series entry"
Assert-Contains "run_benchmark.mjs" $Runner "\$\{chromiumRevision\}\+viewerpatch-\$\{patchHash\}" "fork revision is derived from Chromium revision plus viewer patch-series hash"
Assert-Contains "run_benchmark.mjs" $Runner "forkRevision\s*=\s*args\.forkRevision\s*\|\|\s*\r?\n\s*\(browserIsFromCheckout\s*&&\s*isForkVariant\s*\?\s*getViewerPatchRevision\(chromiumRevision\)\s*:\s*null\)" "fork revision is explicit or viewer-patch-series-derived for fork variants"
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

Assert-Contains "run_benchmark.mjs" $Runner "function planUserDataProfile\(args\)" "explicit benchmark profile planning exists"
Assert-Contains "run_benchmark.mjs" $Runner "--userDataDir must resolve under" "explicit benchmark profiles are constrained to the benchmark tmp directory"
Assert-Contains "run_benchmark.mjs" $Runner "--userDataDir requires --profileCacheKey" "explicit benchmark profile reuse requires a compatibility key"
Assert-Contains "run_benchmark.mjs" $Runner "profile_cache_mode:\s*'fresh-temp'" "default fresh temp profile cache mode is recorded"
Assert-Contains "run_benchmark.mjs" $Runner "profile_cache_mode:\s*'explicit-reuse'" "explicit reused profile cache mode is recorded"
Assert-Contains "run_benchmark.mjs" $Runner "result\.profile_cache_mode\s*=" "profile cache mode metadata is added to result JSON"
Assert-Contains "run_benchmark.mjs" $Runner "result\.profile_cache_key\s*=" "profile cache key metadata is added to result JSON"
Assert-Contains "run_benchmark.mjs" $Runner "result\.profile_reuse_enabled\s*=" "profile reuse metadata is added to result JSON"
Assert-Contains "run_benchmark.mjs" $Runner "result\.profile_dir\s*=" "profile directory metadata is added to result JSON"
Assert-Contains "run_benchmark.mjs" $Runner "result\.profile_dir_created_by_runner\s*=" "profile creation metadata is added to result JSON"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow '\[string\]\$ProfileCacheKey' "full-suite runner accepts explicit profile-cache key"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow '\[string\]\$UserDataDirRoot' "full-suite runner accepts explicit profile root"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow '\[string\]\$WebGpuBundleMode\s*=\s*"off"' "full-suite runner accepts explicit WebGPU BundleGroup scene mode"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow "Test-ResultProfileCacheMode" "full-suite runner validates profile-cache metadata before reusing results"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow "Test-ResultComplexityMode" "full-suite runner validates scene complexity before reusing results"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow "Test-ResultWebGpuBundleMode" "full-suite runner validates WebGPU BundleGroup scene mode before reusing results"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow "--userDataDir" "full-suite runner forwards explicit profile directory to benchmark runner"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow "--profileCacheKey" "full-suite runner forwards explicit profile-cache key to benchmark runner"
Assert-Contains "run_full_suite.ps1" $FullSuiteWorkflow "--webgpuBundleMode" "full-suite runner forwards WebGPU BundleGroup scene mode to benchmark runner"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow '\[double\]\$Complexity\s*=\s*2\.0' "official workflow defaults to the stress scene complexity"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "--expectedComplexity" "official workflow validates scene complexity in suite outputs"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow '\[string\]\$WebGpuProfileCacheKey' "official workflow accepts WebGPU profile-cache key"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow '\[string\]\$WebGpuBundleMode\s*=\s*"off"' "official workflow accepts explicit WebGPU BundleGroup scene mode"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "-WebGpuBundleMode" "official workflow forwards WebGPU BundleGroup mode to full-suite commands"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "--webgpuBundleMode" "official workflow forwards WebGPU BundleGroup mode to trace capture"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "webgpu_bundle_mode" "official workflow records WebGPU BundleGroup mode metadata"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "Add-WebGpuProfileCacheArgs" "official workflow applies profile-cache args to WebGPU suites"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "PrimeWebGpuProfileCache" "official workflow can run an explicit WebGPU profile-cache priming pass"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "prime-before-measured-run" "official manifest records profile-cache priming policy"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "profile_cache_policy" "official manifest records profile-cache comparison policy"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow '\[string\]\$ProfileCacheKey' "trusted matrix accepts explicit profile-cache key"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow '\[double\]\$Complexity\s*=\s*2\.0' "trusted matrix defaults to stress scene complexity"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow "--expectedComplexity" "trusted matrix validates scene complexity in suite outputs"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow '\[switch\]\$PrimeProfileCache' "trusted matrix can run an explicit profile-cache priming pass"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow "--userDataDir" "trusted matrix forwards explicit profile directory to benchmark runner"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow "--profileCacheKey" "trusted matrix forwards explicit profile-cache key to benchmark runner"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow "profile_cache_policy" "trusted matrix manifest records profile-cache comparison policy"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow '\[string\]\$WebGpuBundleMode\s*=\s*"off"' "trusted matrix accepts explicit WebGPU BundleGroup scene mode"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow "--webgpuBundleMode" "trusted matrix forwards WebGPU BundleGroup scene mode to benchmark runner"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow "webgpu_bundle_mode" "trusted matrix records WebGPU BundleGroup scene mode metadata"
Assert-Contains "run_blocker_experiments.ps1" $BlockerWorkflow '\[string\]\$WebGpuBundleMode\s*=\s*"off"' "targeted blocker runner accepts explicit WebGPU BundleGroup scene mode"
Assert-Contains "run_blocker_experiments.ps1" $BlockerWorkflow "-WebGpuBundleMode" "targeted blocker runner forwards WebGPU BundleGroup mode to suite and matrix commands"
Assert-Contains "run_blocker_experiments.ps1" $BlockerWorkflow "--webgpuBundleMode" "targeted blocker trace runner forwards WebGPU BundleGroup mode to trace capture"
Assert-Contains "run_blocker_experiments.ps1" $BlockerWorkflow "webgpu_bundle_mode" "targeted blocker manifest records WebGPU BundleGroup scene mode"

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
    "complexity",
    "generated_at",
    "benchmark_variant",
    "browser_is_from_checkout",
    "benchmark_hud_enabled",
    "webgpu_bundle_mode",
    "webgpu_bundle_groups",
    "resource_warmup_settle_gpu",
    "resource_warmup_pipeline_quiet_frames",
    "resource_warmup_pipeline_quiet_max_frames",
    "resource_warmup_pipeline_quiet_actual_frames",
    "resource_warmup_pipeline_quiet_achieved",
    "resource_warmup_texture_targets",
    "resource_warmup_render_targets",
    "resource_warmup_settle_gpu_ms",
    "resource_warmup_texture_init_ms",
    "resource_warmup_render_target_init_ms",
    "resource_warmup_pipeline_quiet_ms",
    "resource_warmup_settle_gpu_method",
    "resource_warmup_settle_gpu_error",
    "resource_warmup_texture_init_error",
    "resource_warmup_render_target_init_error",
    "resource_warmup_pipeline_quiet_error",
    "process_rss_start_mb",
    "process_rss_peak_mb",
    "process_rss_end_mb",
    "process_rss_delta_mb",
    "webgpu_queue_submit_command_buffer_count",
    "webgpu_queue_submit_avg_command_buffers",
    "webgpu_queue_submit_single_command_buffer_count",
    "webgpu_queue_submit_small_batch_count",
    "webgpu_queue_submit_max_command_buffers",
    "profile_cache_mode",
    "profile_cache_key",
    "profile_reuse_enabled",
    "profile_dir",
    "profile_dir_created_by_runner"
  )) {
  Assert-Contains "validate_metrics.mjs" $Validator "'$Field'" "validator recognizes optional metadata field $Field"
}

Assert-Contains "docs/benchmark_methodology.md" $BenchmarkDocs "package metadata, creates the output directory, and writes the final\s+machine-readable JSON file" "benchmark docs describe harness-owned output writing"
Assert-Contains "docs/benchmark_methodology.md" $BenchmarkDocs "Fork benchmark results must identify the actual fork patch-series content" "benchmark docs describe patch-series-derived fork revision"
Assert-Contains "docs/benchmark_methodology.md" $BenchmarkDocs "GPU-settle warmup mode" "benchmark docs describe resource warmup GPU-settle compatibility"
Assert-Contains "docs/benchmark_methodology.md" $BenchmarkDocs "profile-cache mode/key" "benchmark docs describe profile-cache compatibility"
Assert-Contains "run_benchmark.mjs" $Runner "settleGpuAfterWarmup" "runner forwards resource warmup GPU-settle query option"
Assert-Contains "run_benchmark.mjs" $Runner "pipelineQuietFrames" "runner forwards WebGPU pipeline-quiet warmup query option"
Assert-Contains "run_benchmark.mjs" $Runner "webgpuBundleMode" "runner forwards WebGPU BundleGroup/render-bundle scene mode"
Assert-Contains "run_official_comparison.ps1" $OfficialWorkflow "Get-ViewerForkRevision" "official workflow computes patch-series-derived fork revision"
Assert-Contains "run_trusted_experiment_matrix.ps1" $TrustedWorkflow "Get-ViewerForkRevision" "trusted workflow computes patch-series-derived fork revision"

Write-Host "Benchmark metadata enrichment checks passed for provenance, GPU/RSS/size metadata, and output ownership."

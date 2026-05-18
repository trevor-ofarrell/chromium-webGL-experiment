[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$AuditPath = Join-Path $Root "scripts\audit_artifacts.ps1"
$Text = Get-Content -LiteralPath $AuditPath -Raw

function Assert-Matches {
  param(
    [string]$Pattern,
    [string]$Description
  )
  if ($Text -notmatch $Pattern) {
    throw "Audit official suite validation gate missing: $Description. Pattern: $Pattern"
  }
}

Assert-Matches "--rejectSoftwareRendering" "suite validator software-rendering rejection argument"
Assert-Matches "--requireGpuMetadata" "suite validator GPU metadata requirement argument"
Assert-Matches "--expectedChromiumRevision" "suite validator expected Chromium revision argument"
Assert-Matches "--expectedBrowser" "suite validator expected browser executable argument"
Assert-Matches "--expectedMeasuredSeconds" "suite validator measured-seconds argument"
Assert-Matches "--expectedWarmupSeconds" "suite validator warmup-seconds argument"
Assert-Matches "--expectedFlagMetadata" "suite validator expected flag metadata argument"
Assert-Matches "Official performance.*Stock WebGL2 scene suite results[\s\S]*-RejectSoftwareRendering[\s\S]*-RequireGpuMetadata" "stock WebGL2 audit row strict GPU validation"
Assert-Matches 'Official performance.*Stock WebGL2 scene suite results[\s\S]*-ExpectedChromiumRevision\s+\$ExpectedChromiumRevision' "stock WebGL2 audit row expected Chromium revision"
Assert-Matches 'Official performance.*Stock WebGL2 scene suite results[\s\S]*-ExpectedBrowser\s+\(Resolve-RepoPath "src\\out\\ReleaseBaseline\\content_shell\.exe"\)' "stock WebGL2 audit row expected browser executable"
Assert-Matches 'Official performance.*Stock WebGL2 scene suite results[\s\S]*-ExpectedFlagMetadata\s+\$BrowserModeFlags' "stock WebGL2 audit row browser-mode flag metadata"
Assert-Matches "Official performance.*Fork default WebGL2 scene suite results[\s\S]*-RejectSoftwareRendering[\s\S]*-RequireGpuMetadata" "fork WebGL2 audit row strict GPU validation"
Assert-Matches 'Official performance.*Fork default WebGL2 scene suite results[\s\S]*-ExpectedChromiumRevision\s+\$ExpectedChromiumRevision' "fork WebGL2 audit row expected Chromium revision"
Assert-Matches 'Official performance.*Fork default WebGL2 scene suite results[\s\S]*-ExpectedBrowser\s+\(Resolve-RepoPath "src\\out\\ReleaseViewerDefault\\content_shell\.exe"\)' "fork WebGL2 audit row expected browser executable"
Assert-Matches 'Official performance.*Fork default WebGL2 scene suite results[\s\S]*-ExpectedFlagMetadata\s+\$ForkDefaultFlags' "fork WebGL2 audit row viewer flag metadata"
Assert-Matches 'Official performance.*Fork trusted/aggressive WebGL2 scene suite results[\s\S]*-ExpectedFlagMetadata\s+\$ForkAggressiveCommonFlags' "aggressive WebGL2 audit row common aggressive flag metadata"
Assert-Matches "Official performance.*Stock WebGPU scene suite results[\s\S]*-RejectSoftwareRendering[\s\S]*-RequireGpuMetadata" "stock WebGPU audit row strict GPU validation"
Assert-Matches 'Official performance.*Stock WebGPU scene suite results[\s\S]*-ExpectedChromiumRevision\s+\$ExpectedChromiumRevision' "stock WebGPU audit row expected Chromium revision"
Assert-Matches 'Official performance.*Stock WebGPU scene suite results[\s\S]*-ExpectedBrowser\s+\(Resolve-RepoPath "src\\out\\ReleaseBaseline\\content_shell\.exe"\)' "stock WebGPU audit row expected browser executable"
Assert-Matches 'Official performance.*Stock WebGPU scene suite results[\s\S]*-ExpectedFlagMetadata\s+\$BrowserModeFlags' "stock WebGPU audit row browser-mode flag metadata"
Assert-Matches "Official performance.*Fork WebGPU scene suite results[\s\S]*-RejectSoftwareRendering[\s\S]*-RequireGpuMetadata" "fork WebGPU audit row strict GPU validation"
Assert-Matches 'Official performance.*Fork WebGPU scene suite results[\s\S]*-ExpectedChromiumRevision\s+\$ExpectedChromiumRevision' "fork WebGPU audit row expected Chromium revision"
Assert-Matches 'Official performance.*Fork WebGPU scene suite results[\s\S]*-ExpectedBrowser\s+\(Resolve-RepoPath "src\\out\\ReleaseViewerDefault\\content_shell\.exe"\)' "fork WebGPU audit row expected browser executable"
Assert-Matches 'Official performance.*Fork WebGPU scene suite results[\s\S]*-ExpectedFlagMetadata\s+\$ForkDefaultFlags' "fork WebGPU audit row viewer flag metadata"
Assert-Matches 'Official performance.*Fork trusted/aggressive WebGPU scene suite results[\s\S]*-ExpectedFlagMetadata\s+\$ForkAggressiveCommonFlags' "aggressive WebGPU audit row common aggressive flag metadata"
Assert-Matches "official-comparison-manifest\.json[\s\S]*ExpectedMeasuredSeconds[\s\S]*Manifest\.options\.duration" "official manifest duration feeds audit suite validation"
Assert-Matches "official-comparison-manifest\.json[\s\S]*ExpectedWarmupSeconds[\s\S]*Manifest\.options\.warmup" "official manifest warmup feeds audit suite validation"
Assert-Matches "Invoke-OfficialManifestBenchmarkSuiteValidation" "official manifest validates exact result-file suites"
Assert-Matches "Official comparison manifest[\s\S]*suite validation failed" "official manifest row rejects exact-suite semantic validation failures"
Assert-Matches "benchmark suites semantically validated" "official manifest done row records semantic benchmark suite validation"
Assert-Matches 'Official performance.*Stock WebGL2 scene suite results[\s\S]*-RequirePackageSize:\$BaselinePackageRequired' "stock WebGL2 audit row inherits package-size requirement from official manifest"
Assert-Matches 'Official performance.*Fork default WebGL2 scene suite results[\s\S]*-RequirePackageSize:\$ForkPackageRequired' "fork WebGL2 audit row inherits package-size requirement from official manifest"

Write-Host "Artifact audit official suite rows enforce GPU/software, Chromium revision, browser executable, duration/warmup, and viewer flag metadata validation gates."

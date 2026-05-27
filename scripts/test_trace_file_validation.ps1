[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TmpDir = Join-Path $Root "benchmarks\tmp\trace-file-validation-test"
$Validator = Join-Path $Root "scripts\validate_trace_file.mjs"
$Summarizer = Join-Path $Root "scripts\summarize_trace.mjs"

function Write-Json {
  param(
    [string]$PathValue,
    [object]$Value
  )
  $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PathValue -Encoding UTF8
}

function Invoke-Validator {
  param([string[]]$ValidatorArgs)
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node $Validator @ValidatorArgs 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output | ForEach-Object { [string]$_ }) -join "`n"
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

function Invoke-Summarizer {
  param([string[]]$SummarizerArgs)
  $OldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & node $Summarizer @SummarizerArgs 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($Output | ForEach-Object { [string]$_ }) -join "`n"
    }
  } finally {
    $ErrorActionPreference = $OldErrorActionPreference
  }
}

if (Test-Path -LiteralPath $TmpDir) {
  Remove-Item -LiteralPath $TmpDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null

try {
  $Valid = Join-Path $TmpDir "valid-trace.json"
  Write-Json $Valid ([pscustomobject]@{
    traceEvents = @(
      [pscustomobject]@{ name = "RunTask"; ph = "X"; ts = 1; dur = 1000; pid = 1; tid = 1 },
      [pscustomobject]@{ name = "SubmitCompositorFrame"; ph = "X"; ts = 2; dur = 500; pid = 1; tid = 2 }
    )
  })
  $Result = Invoke-Validator -ValidatorArgs @("--minEvents", "2", $Valid)
  if ($Result.ExitCode -ne 0) {
    throw "Expected valid trace to pass. Output: $($Result.Output)"
  }

  $QueueTrace = Join-Path $TmpDir "queue-trace.json"
  $QueueSidecar = [System.IO.Path]::ChangeExtension($QueueTrace, ".result.json")
  $QueueSummary = Join-Path $TmpDir "queue-trace-summary.md"
  Write-Json $QueueTrace ([pscustomobject]@{
    traceEvents = @(
      [pscustomobject]@{ name = "GPUQueue::WriteTextureImpl"; ph = "X"; ts = 1; dur = 2500; pid = 1; tid = 1; args = [pscustomobject]@{ bytes = 1048576; pixels = 4096 } },
      [pscustomobject]@{ name = "GPUQueue::submit"; ph = "X"; ts = 2; dur = 500; pid = 1; tid = 1; args = [pscustomobject]@{ command_buffers = 2 } },
      [pscustomobject]@{ name = "GPUQueue::CopyFromCanvasSourceImage::CPUFallbackReadPixels"; ph = "I"; ts = 3; pid = 1; tid = 1; args = [pscustomobject]@{ bytes = 2097152; pixels = 8192 } }
    )
  })
  Write-Json $QueueSidecar ([pscustomobject]@{
    webgpu_queue_write_texture_common_layout_count = 8
    webgpu_queue_write_texture_common_extent_count = 9
    webgpu_queue_copy_external_image_default_origin_count = 6
    webgpu_queue_copy_external_image_common_origin_count = 7
    webgpu_queue_copy_external_image_explicit_common_origin_count = 1
    webgpu_queue_copy_external_image_srgb_destination_count = 5
    webgpu_queue_copy_external_image_full_source_count = 4
    webgpu_pipeline_descriptor_stack_fast_path_eligible_count = 3
    webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count = 2
    benchmark_result = [pscustomobject]@{
      webgpu_queue_write_texture_count = 10
      webgpu_queue_copy_external_image_count = 7
    }
  })
  $SummaryOutput = & node $Summarizer $QueueTrace --output $QueueSummary 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Expected trace summary to pass. Output: $($SummaryOutput -join "`n")"
  }
  $Summary = Get-Content -LiteralPath $QueueSummary -Raw
  if ($Summary -notmatch "## Focused WebGPU Queue Events" -or
      $Summary -notmatch "## WebGPU Texture Copy Path Verdict" -or
      $Summary -notmatch "Sidecar: ``.*queue-trace\.result\.json``" -or
      $Summary -notmatch "## WebGPU Fast-Path Coverage" -or
      $Summary -notmatch "Status: ``cpu-fallback-detected``" -or
      $Summary -notmatch "GPUQueue::WriteTextureImpl" -or
      $Summary -notmatch "GPUQueue::submit" -or
      $Summary -notmatch "GPUQueue::CopyFromCanvasSourceImage::CPUFallbackReadPixels" -or
      $Summary -notmatch "\|\s*GPUQueue::WriteTextureImpl\s*\|\s*1\s*\|\s*2\.50\s*\|\s*2\.50\s*\|\s*1\.00\s*\|\s*4096" -or
      $Summary -notmatch "\|\s*GPUQueue::CopyFromCanvasSourceImage::CPUFallbackReadPixels\s*\|\s*1\s*\|\s*0\.00\s*\|\s*0\.00\s*\|\s*2\.00\s*\|\s*8192" -or
      $Summary -notmatch "\|\s*CPU fallback/readback copy\s*\|\s*1\s*\|\s*2\.00\s*\|\s*8192" -or
      $Summary -notmatch "\|\s*10\s*\|\s*8\s*\|\s*9\s*\|\s*7\s*\|\s*6\s*\|\s*7\s*\|\s*1\s*\|\s*5\s*\|\s*4\s*\|\s*3\s*\|\s*2\s*\|") {
    throw "Trace summary did not include focused WebGPU queue attribution rows. Summary: $Summary"
  }
  $RejectSummary = Invoke-Summarizer -SummarizerArgs @($QueueTrace, "--rejectWebGpuCpuFallback")
  if ($RejectSummary.ExitCode -eq 0 -or $RejectSummary.Output -notmatch "WebGPU CPU texture fallback/readback path detected") {
    throw "Trace summary did not reject CPU fallback paths when requested. Output: $($RejectSummary.Output)"
  }
  $Result = Invoke-Validator -ValidatorArgs @("--rejectWebGpuCpuFallback", $QueueTrace)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "WebGPU CPU texture fallback/readback events were present") {
    throw "Trace validator did not reject CPU fallback paths when requested. Output: $($Result.Output)"
  }

  $GpuResidentTrace = Join-Path $TmpDir "gpu-resident-trace.json"
  Write-Json $GpuResidentTrace ([pscustomobject]@{
    traceEvents = @(
      [pscustomobject]@{ name = "GPUQueue::CopyFromCanvasSourceImage::ExistingSharedImage"; ph = "I"; ts = 4; pid = 1; tid = 1; args = [pscustomobject]@{ bytes = 1048576; pixels = 4096 } }
    )
  })
  $Result = Invoke-Validator -ValidatorArgs @("--rejectWebGpuCpuFallback", $GpuResidentTrace)
  if ($Result.ExitCode -ne 0) {
    throw "Trace validator rejected a GPU-resident WebGPU texture-copy trace. Output: $($Result.Output)"
  }

  $Empty = Join-Path $TmpDir "empty-trace.json"
  Write-Json $Empty ([pscustomobject]@{ traceEvents = @() })
  $Result = Invoke-Validator -ValidatorArgs @("--minEvents", "1", $Empty)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "below required minimum") {
    throw "Expected empty trace to fail. Output: $($Result.Output)"
  }

  $Malformed = Join-Path $TmpDir "malformed-trace.json"
  Set-Content -LiteralPath $Malformed -Value "{ not json" -Encoding UTF8
  $Result = Invoke-Validator -ValidatorArgs @($Malformed)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "invalid JSON") {
    throw "Expected malformed trace to fail. Output: $($Result.Output)"
  }

  $Unnamed = Join-Path $TmpDir "unnamed-trace.json"
  Write-Json $Unnamed ([pscustomobject]@{
    traceEvents = @(
      [pscustomobject]@{ ph = "X"; ts = 1; dur = 1000; pid = 1; tid = 1 }
    )
  })
  $Result = Invoke-Validator -ValidatorArgs @($Unnamed)
  if ($Result.ExitCode -eq 0 -or $Result.Output -notmatch "named event") {
    throw "Expected unnamed trace to fail. Output: $($Result.Output)"
  }
} finally {
  if (Test-Path -LiteralPath $TmpDir) {
    Remove-Item -LiteralPath $TmpDir -Recurse -Force
  }
}

Write-Host "Trace file validation accepts parseable event traces and rejects empty, malformed, unnamed, and WebGPU CPU-fallback traces when requested."

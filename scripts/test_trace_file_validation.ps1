[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TmpDir = Join-Path $Root "benchmarks\tmp\trace-file-validation-test"
$Validator = Join-Path $Root "scripts\validate_trace_file.mjs"

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

Write-Host "Trace file validation accepts parseable event traces and rejects empty, malformed, and unnamed traces."

[CmdletBinding()]
param()

function Get-ViewerPatchSeriesRelativePaths {
  return @(
    "chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch",
    "chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch"
  )
}

function Get-ShortSha256Text {
  param([string]$Text)

  $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return (([System.BitConverter]::ToString($Sha.ComputeHash($Bytes)) -replace "-", "").Substring(0, 12)).ToLowerInvariant()
  } finally {
    $Sha.Dispose()
  }
}

function Get-ViewerPatchSeriesHash {
  param([string]$Root)

  $Entries = @(Get-ViewerPatchSeriesRelativePaths | ForEach-Object {
      $PatchPath = Join-Path $Root $_
      if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
        throw "Viewer patch not found for fork revision hash: $PatchPath"
      }
      $CanonicalPath = $_ -replace "\\", "/"
      "$CanonicalPath=$((Get-FileHash -Algorithm SHA256 -LiteralPath $PatchPath).Hash.ToLowerInvariant())"
    })
  return Get-ShortSha256Text ($Entries -join "`n")
}

function Get-ViewerForkRevisionForChromiumRevision {
  param(
    [string]$ChromiumRevision,
    [string]$Root
  )

  if (-not $ChromiumRevision) {
    return ""
  }
  return "$ChromiumRevision+viewerpatch-$(Get-ViewerPatchSeriesHash -Root $Root)"
}

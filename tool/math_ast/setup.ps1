param(
  [string] $Root = 'D:\dev\local-ai\math-ast',
  [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'
$moduleRoot = $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'MathAstPaths.psm1') -Force

$llamaRelease = 'b10516'
$llamaArchiveName = 'llama-b10516-bin-win-cpu-x64.zip'
$llamaArchiveUrl = "https://github.com/ggml-org/llama.cpp/releases/download/$llamaRelease/$llamaArchiveName"
$llamaArchiveSha256 = 'fbbbc55e0eb2e1b07f9dcb9488616c98ed47d9003b90e15e7c8c7812c4307cd3'
$modelFileName = 'Qwen3-1.7B-Q4_K_M.gguf'
$modelUrl = "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/$modelFileName?download=true"
$modelSha256 = 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5'
$paths = Get-MathAstPaths -Root $Root
$archiveDownload = Join-Path $paths.Temp "download-$llamaArchiveName"
$extractDirectory = Join-Path $paths.Temp 'llama-b10516-extract'
$modelDownload = Join-Path $paths.Temp "$modelFileName.download"

$configuration = [pscustomobject][ordered]@{
  root = $paths.Root
  llamaRelease = $llamaRelease
  llamaArchiveUrl = $llamaArchiveUrl
  llamaArchiveSha256 = $llamaArchiveSha256
  llamaArchiveDownload = $archiveDownload
  modelUrl = $modelUrl
  modelSha256 = $modelSha256
  serverExe = $paths.ServerExe
  modelFile = $paths.ModelFile
  manifestFile = $paths.ManifestFile
}
if ($ValidateOnly) {
  $configuration | ConvertTo-Json -Depth 4
  return
}

$cBefore = Get-MathAstDriveFreeBytes -DriveName 'C'
$dBefore = Get-MathAstDriveFreeBytes -DriveName 'D'
foreach ($directory in @(
  $paths.Bin, $paths.Models, $paths.Cache, $paths.Logs,
  $paths.Runtime, $paths.Temp, $paths.Benchmarks
)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
Set-MathAstProcessEnvironment -Paths $paths

function Assert-DownloadedHash {
  param(
    [Parameter(Mandatory)][string] $Path,
    [Parameter(Mandatory)][string] $ExpectedSha256,
    [Parameter(Mandatory)][string] $Label
  )
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $ExpectedSha256) {
    Remove-Item -LiteralPath $Path -Force
    throw "$Label SHA256 mismatch"
  }
}

try {
  if (-not (Test-Path -LiteralPath $paths.ServerExe -PathType Leaf)) {
    Invoke-WebRequest -Uri $llamaArchiveUrl -OutFile $archiveDownload -UseBasicParsing
    Assert-DownloadedHash -Path $archiveDownload -ExpectedSha256 $llamaArchiveSha256 -Label 'llama.cpp archive'
    if (Test-Path -LiteralPath $extractDirectory) {
      Assert-MathAstChildPath -Root $paths.Root -Path $extractDirectory
      Remove-Item -LiteralPath $extractDirectory -Recurse -Force
    }
    Expand-Archive -LiteralPath $archiveDownload -DestinationPath $extractDirectory -Force
    $server = Get-ChildItem -LiteralPath $extractDirectory -Recurse -File -Filter 'llama-server.exe' | Select-Object -First 1
    if ($null -eq $server) { throw 'llama.cpp archive did not contain llama-server.exe' }
    Get-ChildItem -LiteralPath $server.Directory.FullName -File | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $paths.Bin $_.Name) -Force
    }
  }

  if (Test-Path -LiteralPath $paths.ModelFile -PathType Leaf) {
    $existingModelHash = (Get-FileHash -LiteralPath $paths.ModelFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($existingModelHash -ne $modelSha256) {
      throw 'Existing Qwen model hash mismatch; preserve or remove it manually before setup'
    }
  } else {
    Invoke-WebRequest -Uri $modelUrl -OutFile $modelDownload -UseBasicParsing
    Assert-DownloadedHash -Path $modelDownload -ExpectedSha256 $modelSha256 -Label 'Qwen model'
    Move-Item -LiteralPath $modelDownload -Destination $paths.ModelFile
  }

  $serverSha256 = (Get-FileHash -LiteralPath $paths.ServerExe -Algorithm SHA256).Hash.ToLowerInvariant()
  $manifest = [pscustomobject][ordered]@{
    llamaRelease = $llamaRelease
    llamaArchiveSha256 = $llamaArchiveSha256
    serverSha256 = $serverSha256
    modelFileName = $modelFileName
    modelSha256 = $modelSha256
    createdAt = [DateTime]::UtcNow.ToString('o')
  }
  [IO.File]::WriteAllText(
    $paths.ManifestFile,
    ($manifest | ConvertTo-Json -Depth 4),
    [Text.UTF8Encoding]::new($false)
  )
} finally {
  foreach ($temporaryFile in @($archiveDownload, $modelDownload)) {
    if (Test-Path -LiteralPath $temporaryFile -PathType Leaf) {
      Remove-Item -LiteralPath $temporaryFile -Force
    }
  }
  if (Test-Path -LiteralPath $extractDirectory) {
    Assert-MathAstChildPath -Root $paths.Root -Path $extractDirectory
    Remove-Item -LiteralPath $extractDirectory -Recurse -Force
  }
}

$cAfter = Get-MathAstDriveFreeBytes -DriveName 'C'
$dAfter = Get-MathAstDriveFreeBytes -DriveName 'D'
Assert-MathAstCDriveUsage -FreeBytesBefore $cBefore -FreeBytesAfter $cAfter

[pscustomobject][ordered]@{
  status = 'ready'
  root = $paths.Root
  serverExe = $paths.ServerExe
  modelFile = $paths.ModelFile
  cDriveBytesBefore = $cBefore
  cDriveBytesAfter = $cAfter
  dDriveBytesBefore = $dBefore
  dDriveBytesAfter = $dAfter
} | ConvertTo-Json -Depth 4

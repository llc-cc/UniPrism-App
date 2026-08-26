$ErrorActionPreference = 'Stop'

$toolRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $toolRoot 'MathAstPaths.psm1') -Force

$paths = Get-MathAstPaths -Root 'D:\dev\local-ai\math-ast'
if ($paths.Root -ne 'D:\dev\local-ai\math-ast') { throw 'Root mismatch' }

$rootBoundary = "$($paths.Root.TrimEnd('\'))\"
foreach ($property in @(
  'Bin', 'Models', 'Cache', 'Logs', 'Runtime', 'Temp', 'Benchmarks'
)) {
  $value = [string]$paths.$property
  if (-not $value.StartsWith($rootBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$property escaped the D-drive root: $value"
  }
}

if ($paths.ServerExe -ne 'D:\dev\local-ai\math-ast\bin\llama-server.exe') {
  throw "Server path mismatch: $($paths.ServerExe)"
}
if ($paths.ModelFile -ne 'D:\dev\local-ai\math-ast\models\Qwen3-1.7B-Q4_K_M.gguf') {
  throw "Model path mismatch: $($paths.ModelFile)"
}
if ($paths.ManifestFile -ne 'D:\dev\local-ai\math-ast\runtime\artifacts.json') {
  throw "Manifest path mismatch: $($paths.ManifestFile)"
}

try {
  Get-MathAstPaths -Root 'C:\math-ast' | Out-Null
  throw 'C-drive root should have been rejected'
} catch {
  if ($_.Exception.Message -eq 'C-drive root should have been rejected') { throw }
}

try {
  Get-MathAstPaths -Root 'D:\dev\local-ai\math-ast-escape\..\math-ast-escape' | Out-Null
} catch {
  throw "A normalized D-drive root should be accepted: $($_.Exception.Message)"
}

Assert-MathAstLoopbackUrl -BaseUrl 'http://127.0.0.1:8081'
Assert-MathAstLoopbackUrl -BaseUrl 'http://localhost:8081'
foreach ($unsafeUrl in @(
  'http://0.0.0.0:8081',
  'http://192.168.1.20:8081',
  'https://example.com',
  'ftp://127.0.0.1:8081'
)) {
  try {
    Assert-MathAstLoopbackUrl -BaseUrl $unsafeUrl
    throw "Unsafe URL should have been rejected: $unsafeUrl"
  } catch {
    if ($_.Exception.Message -eq "Unsafe URL should have been rejected: $unsafeUrl") { throw }
  }
}

Set-MathAstProcessEnvironment -Paths $paths
if ($env:HF_HOME -ne (Join-Path $paths.Cache 'huggingface')) { throw 'HF_HOME mismatch' }
if ($env:XDG_CACHE_HOME -ne $paths.Cache) { throw 'XDG_CACHE_HOME mismatch' }
if ($env:TEMP -ne $paths.Temp -or $env:TMP -ne $paths.Temp) {
  throw 'Temporary directory mismatch'
}

Assert-MathAstChildPath -Root $paths.Root -Path (Join-Path $paths.Temp 'extract')
foreach ($unsafePath in @(
  $paths.Root,
  "$($paths.Root)-escape\extract",
  'D:\dev\local-ai',
  'C:\temp\extract'
)) {
  try {
    Assert-MathAstChildPath -Root $paths.Root -Path $unsafePath
    throw "Unsafe child path should have been rejected: $unsafePath"
  } catch {
    if ($_.Exception.Message -eq "Unsafe child path should have been rejected: $unsafePath") { throw }
  }
}

$setup = & (Join-Path $toolRoot 'setup.ps1') -ValidateOnly | ConvertFrom-Json
if ($setup.root -ne 'D:\dev\local-ai\math-ast') { throw 'Setup root mismatch' }
if ($setup.llamaRelease -ne 'b10516') { throw 'llama.cpp release mismatch' }
if ($setup.llamaArchiveSha256 -ne 'fbbbc55e0eb2e1b07f9dcb9488616c98ed47d9003b90e15e7c8c7812c4307cd3') {
  throw 'llama.cpp archive hash mismatch'
}
if ($setup.modelSha256 -ne 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5') {
  throw 'Qwen model hash mismatch'
}
if (-not ([string]$setup.llamaArchiveUrl).StartsWith('https://github.com/ggml-org/llama.cpp/releases/download/')) {
  throw 'llama.cpp URL must use the official release host'
}
if (-not ([string]$setup.modelUrl).StartsWith('https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/')) {
  throw 'Model URL must use the selected repository'
}

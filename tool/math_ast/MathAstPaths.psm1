Set-StrictMode -Version Latest

$script:DefaultModelFileName = 'Qwen3-1.7B-Q4_K_M.gguf'

# Keep this script ASCII-only because Windows PowerShell 5.1 misreads UTF-8 without BOM.
# Resolve every local model asset beneath one guarded D-drive root.
function Get-MathAstPaths {
  [CmdletBinding()]
  param([string] $Root = 'D:\dev\local-ai\math-ast')

  $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  if (-not $resolvedRoot.StartsWith('D:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Math AST root must stay on D drive: $resolvedRoot"
  }
  if ($resolvedRoot -eq 'D:') {
    throw 'Math AST root cannot be the whole D drive'
  }

  $bin = Join-Path $resolvedRoot 'bin'
  $models = Join-Path $resolvedRoot 'models'
  $cache = Join-Path $resolvedRoot 'cache'
  $logs = Join-Path $resolvedRoot 'logs'
  $runtime = Join-Path $resolvedRoot 'runtime'
  $temp = Join-Path $resolvedRoot 'tmp'

  [pscustomobject][ordered]@{
    Root = $resolvedRoot
    Bin = $bin
    Models = $models
    Cache = $cache
    Logs = $logs
    Runtime = $runtime
    Temp = $temp
    Benchmarks = Join-Path $resolvedRoot 'benchmarks'
    ServerExe = Join-Path $bin 'llama-server.exe'
    ModelFile = Join-Path $models $script:DefaultModelFileName
    ManifestFile = Join-Path $runtime 'artifacts.json'
    PidFile = Join-Path $runtime 'llama-server.pid'
    StdOutLog = Join-Path $logs 'llama-server.stdout.log'
    StdErrLog = Join-Path $logs 'llama-server.stderr.log'
  }
}

# Keep the unauthenticated llama.cpp endpoint on loopback.
function Assert-MathAstLoopbackUrl {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string] $BaseUrl)

  try {
    $uri = [Uri]$BaseUrl
  } catch {
    throw "Math AST base URL is invalid: $BaseUrl"
  }
  if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'http') {
    throw "Math AST base URL must use loopback HTTP: $BaseUrl"
  }
  if ($uri.Host -notin @('127.0.0.1', 'localhost')) {
    throw "Math AST base URL must stay on loopback: $BaseUrl"
  }
  if (-not [string]::IsNullOrEmpty($uri.UserInfo) -or
      -not [string]::IsNullOrEmpty($uri.Query) -or
      -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "Math AST base URL cannot contain credentials, query, or fragment: $BaseUrl"
  }
}

# Scope Hugging Face and temporary caches to this D-drive process only.
function Set-MathAstProcessEnvironment {
  [CmdletBinding()]
  param([Parameter(Mandatory)] $Paths)

  $env:HF_HOME = Join-Path $Paths.Cache 'huggingface'
  $env:XDG_CACHE_HOME = $Paths.Cache
  $env:TEMP = $Paths.Temp
  $env:TMP = $Paths.Temp
}

# Validate exact directory containment before any recursive cleanup.
function Assert-MathAstChildPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $Path
  )

  $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  $resolvedPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
  $rootBoundary = "$resolvedRoot\"
  if (-not $resolvedPath.StartsWith($rootBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Math AST path escaped its guarded root: $resolvedPath"
  }
}

function Get-MathAstDriveFreeBytes {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string] $DriveName)

  $normalized = $DriveName.Trim().TrimEnd(':', '\', '/')
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    throw "Math AST cannot read free space for drive: $DriveName"
  }
  try {
    $drive = [IO.DriveInfo]::new("$normalized`:\")
    if (-not $drive.IsReady) { throw 'drive is not ready' }
    return [int64]$drive.AvailableFreeSpace
  } catch {
    throw "Math AST cannot read free space for drive ${DriveName}: $($_.Exception.Message)"
  }
}

# Fail when setup unexpectedly consumes more than 512MB on the system drive.
function Assert-MathAstCDriveUsage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][int64] $FreeBytesBefore,
    [Parameter(Mandatory)][int64] $FreeBytesAfter
  )

  if ($FreeBytesBefore -lt 0 -or $FreeBytesAfter -lt 0) {
    throw 'Math AST C-drive readings must be non-negative'
  }
  $usedBytes = $FreeBytesBefore - $FreeBytesAfter
  if ($usedBytes -gt 512MB) {
    throw "Math AST setup consumed more than 512MB on C drive: $usedBytes bytes"
  }
}

Export-ModuleMember -Function `
  Get-MathAstPaths, `
  Assert-MathAstLoopbackUrl, `
  Set-MathAstProcessEnvironment, `
  Assert-MathAstChildPath, `
  Get-MathAstDriveFreeBytes, `
  Assert-MathAstCDriveUsage

Set-StrictMode -Version Latest

function Get-SenseVoicePaths {
  [CmdletBinding()]
  param([string] $Root = 'D:\dev\local-ai\sensevoice')

  $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  # 安全边界：仅接受 D 盘根目录下的路径，避免大模型资产写入系统盘.
  if (-not $resolvedRoot.StartsWith('D:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "SenseVoice root must stay on D drive: $resolvedRoot"
  }

  [pscustomobject]@{
    Root = $resolvedRoot
    Runtime = Join-Path $resolvedRoot 'runtime'
    Venv = Join-Path $resolvedRoot 'venv'
    Models = Join-Path $resolvedRoot 'models'
    PipCache = Join-Path $resolvedRoot 'cache\pip'
    ModelScopeCache = Join-Path $resolvedRoot 'cache\modelscope'
    HuggingFaceCache = Join-Path $resolvedRoot 'cache\huggingface'
    TorchCache = Join-Path $resolvedRoot 'cache\torch'
    Temp = Join-Path $resolvedRoot 'tmp'
    Benchmarks = Join-Path $resolvedRoot 'benchmarks'
  }
}

function Set-SenseVoiceProcessEnvironment {
  [CmdletBinding()]
  param([Parameter(Mandatory)] $Paths)

  $env:PIP_CACHE_DIR = $Paths.PipCache
  $env:MODELSCOPE_CACHE = $Paths.ModelScopeCache
  $env:HF_HOME = $Paths.HuggingFaceCache
  $env:TORCH_HOME = $Paths.TorchCache
  $env:TEMP = $Paths.Temp
  $env:TMP = $Paths.Temp
  $env:PYTHONPYCACHEPREFIX = Join-Path $Paths.Temp 'pycache'
}

function Get-SenseVoiceDriveFreeBytes {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string] $DriveName)

  $normalizedDriveName = $DriveName.Trim().TrimEnd(':', '\', '/')
  if ([string]::IsNullOrWhiteSpace($normalizedDriveName)) {
    throw "SenseVoice cannot read free space for drive: $DriveName"
  }

  $psDrive = Get-PSDrive -Name $normalizedDriveName -ErrorAction SilentlyContinue
  if ($null -ne $psDrive -and $null -ne $psDrive.Free) {
    $freeBytes = [int64]$psDrive.Free
    if ($freeBytes -ge 0) {
      return $freeBytes
    }
  }

  # 部分 PowerShell 运行时会把 Get-PSDrive.Free 置空，必须回退到 DriveInfo；两者均不可读时停止安装.
  try {
    $driveInfo = [System.IO.DriveInfo]::new("$normalizedDriveName`:\")
    if (-not $driveInfo.IsReady) {
      throw 'Drive is not ready'
    }
    $freeBytes = [int64]$driveInfo.AvailableFreeSpace
    if ($freeBytes -lt 0) {
      throw 'Drive returned a negative free-space value'
    }
    return $freeBytes
  } catch {
    throw "SenseVoice cannot read free space for drive ${DriveName}: $($_.Exception.Message)"
  }
}

function Assert-SenseVoiceCDriveUsage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][int64] $FreeBytesBefore,
    [Parameter(Mandatory)][int64] $FreeBytesAfter
  )

  if ($FreeBytesBefore -lt 0 -or $FreeBytesAfter -lt 0) {
    throw 'SenseVoice C-drive free-space readings must be non-negative'
  }

  $cDriveBytesUsed = $FreeBytesBefore - $FreeBytesAfter
  if ($cDriveBytesUsed -gt 1GB) {
    throw "SenseVoice setup consumed more than 1GB on C drive: $cDriveBytesUsed bytes"
  }
}

Export-ModuleMember -Function Get-SenseVoicePaths, Set-SenseVoiceProcessEnvironment, Get-SenseVoiceDriveFreeBytes, Assert-SenseVoiceCDriveUsage

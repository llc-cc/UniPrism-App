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

Export-ModuleMember -Function Get-SenseVoicePaths, Set-SenseVoiceProcessEnvironment

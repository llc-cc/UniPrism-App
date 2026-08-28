Set-StrictMode -Version Latest

function New-SenseVoiceServiceInvocation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Paths,
    [Parameter(Mandatory)][string] $ServerPath,
    [ValidateRange(1, 65535)][int] $Port = 8000,
    [Parameter(Mandatory)][string] $CorsOrigin
  )

  $executable = Join-Path $Paths.Venv 'Scripts\python.exe'
  $resolvedServer = [IO.Path]::GetFullPath($ServerPath)
  $arguments = @(
    $resolvedServer,
    '--host', '127.0.0.1',
    '--port', [string]$Port,
    '--device', 'cpu',
    '--model', 'sensevoice',
    '--cors-origin', $CorsOrigin
  )

  # descriptor 是验证与实际执行共享的唯一 argv 来源，避免安全检查和生产命令发生漂移.
  [pscustomobject][ordered]@{
    executable = $executable
    server = $resolvedServer
    arguments = $arguments
    host = '127.0.0.1'
    port = $Port
    device = 'cpu'
    model = 'sensevoice'
    corsOrigin = $CorsOrigin
  }
}

function Invoke-SenseVoiceServiceInvocation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Invocation,
    [scriptblock] $ProcessInvoker
  )

  if (-not (Test-Path -LiteralPath $Invocation.executable -PathType Leaf)) {
    throw "SenseVoice virtual-environment interpreter is missing: $($Invocation.executable). Run setup.ps1 first."
  }
  if (-not (Test-Path -LiteralPath $Invocation.server -PathType Leaf)) {
    throw "SenseVoice server adapter is missing: $($Invocation.server)"
  }

  if ($null -eq $ProcessInvoker) {
    $ProcessInvoker = {
      param($Executable, $Arguments)
      # 子进程保持前台运行；stdout 直接写到宿主，函数只返回可判定的退出码.
      & $Executable @Arguments | Out-Host
      return [int]$LASTEXITCODE
    }
  }

  $exitCode = & $ProcessInvoker $Invocation.executable $Invocation.arguments
  if ($exitCode -isnot [int] -and $exitCode -isnot [long]) {
    throw 'SenseVoice process invoker must return one integer exit code'
  }
  if ([int]$exitCode -ne 0) {
    throw "SenseVoice server exited with $exitCode"
  }
}

Export-ModuleMember -Function New-SenseVoiceServiceInvocation, Invoke-SenseVoiceServiceInvocation

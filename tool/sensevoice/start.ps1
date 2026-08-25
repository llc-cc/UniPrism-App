[CmdletBinding()]
param(
  [string] $Root = 'D:\dev\local-ai\sensevoice',
  [ValidateRange(1, 65535)][int] $Port = 8000,
  [string] $CorsOrigin = 'http://localhost:5174',
  [switch] $ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'SenseVoicePaths.psm1'
Import-Module $modulePath -Force
$paths = Get-SenseVoicePaths -Root $Root
$python = Join-Path $paths.Venv 'Scripts\python.exe'
$server = Join-Path $PSScriptRoot 'server.py'

# 本地开发服务固定为回环地址和 CPU；验证模式复用同一参数对象，供测试无副作用地检查安全边界.
$configuration = [ordered]@{
  host = '127.0.0.1'
  port = $Port
  device = 'cpu'
  model = 'sensevoice'
  corsOrigin = $CorsOrigin
  python = $python
  server = $server
}

if ($ValidateOnly) {
  $configuration | ConvertTo-Json -Compress
  return
}

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
  throw "SenseVoice virtual-environment interpreter is missing: $python. Run setup.ps1 first."
}
if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
  throw "SenseVoice server adapter is missing: $server"
}

Set-SenseVoiceProcessEnvironment -Paths $paths
$arguments = @(
  $server,
  '--host', $configuration.host,
  '--port', [string]$configuration.port,
  '--device', $configuration.device,
  '--model', $configuration.model,
  '--cors-origin', $configuration.corsOrigin
)

Write-Host "SenseVoice health endpoint: http://$($configuration.host):$($configuration.port)/health"
Write-Host 'Press Ctrl+C to stop the foreground service.'
& $python @arguments
if ($LASTEXITCODE -ne 0) {
  throw "SenseVoice server exited with $LASTEXITCODE"
}

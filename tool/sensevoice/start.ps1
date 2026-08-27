[CmdletBinding()]
param(
  [string] $Root = 'D:\dev\local-ai\sensevoice',
  [ValidateRange(1, 65535)][int] $Port = 8000,
  [string] $CorsOrigin = 'http://localhost:5174',
  [switch] $ValidateOnly,
  [scriptblock] $ProcessInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'SenseVoicePaths.psm1'
Import-Module $modulePath -Force
$serviceModulePath = Join-Path $PSScriptRoot 'SenseVoiceService.psm1'
Import-Module $serviceModulePath -Force
$paths = Get-SenseVoicePaths -Root $Root
$server = Join-Path $PSScriptRoot 'server.py'
$invocation = New-SenseVoiceServiceInvocation `
  -Paths $paths `
  -ServerPath $server `
  -Port $Port `
  -CorsOrigin $CorsOrigin

if ($ValidateOnly) {
  $invocation | ConvertTo-Json -Compress
  return
}

Set-SenseVoiceProcessEnvironment -Paths $paths
$localModelPath = Join-Path $paths.ModelScopeCache 'models\iic--SenseVoiceSmall\snapshots\master'
# 模型已经由 setup 固化到 D 盘时必须直接加载本地快照，离线开发不应再次访问模型站.
if (Test-Path -LiteralPath (Join-Path $localModelPath 'model.pt')) {
  $env:SENSEVOICE_MODEL_PATH = $localModelPath
} else {
  Remove-Item Env:SENSEVOICE_MODEL_PATH -ErrorAction SilentlyContinue
}
Write-Host "SenseVoice health endpoint: http://$($invocation.host):$($invocation.port)/health"
Write-Host 'Press Ctrl+C to stop the foreground service.'
Invoke-SenseVoiceServiceInvocation -Invocation $invocation -ProcessInvoker $ProcessInvoker

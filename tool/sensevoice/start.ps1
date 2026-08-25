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
Write-Host "SenseVoice health endpoint: http://$($invocation.host):$($invocation.port)/health"
Write-Host 'Press Ctrl+C to stop the foreground service.'
Invoke-SenseVoiceServiceInvocation -Invocation $invocation -ProcessInvoker $ProcessInvoker

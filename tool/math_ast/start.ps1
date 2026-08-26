param(
  [string] $Root = 'D:\dev\local-ai\math-ast',
  [ValidateRange(1, 65535)][int] $Port = 8081,
  [ValidateRange(1, 64)][int] $Threads = 8,
  [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MathAstPaths.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'MathAstService.psm1') -Force

$paths = Get-MathAstPaths -Root $Root
$invocation = New-MathAstServiceInvocation -Paths $paths -Port $Port -Threads $Threads
if ($ValidateOnly) {
  $invocation | ConvertTo-Json -Depth 5
  return
}

Start-MathAstService -Paths $paths -Invocation $invocation | ConvertTo-Json -Depth 4

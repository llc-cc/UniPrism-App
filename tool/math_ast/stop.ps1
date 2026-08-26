param(
  [string] $Root = 'D:\dev\local-ai\math-ast',
  [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MathAstPaths.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'MathAstService.psm1') -Force

$paths = Get-MathAstPaths -Root $Root
if ($ValidateOnly) {
  [pscustomobject][ordered]@{
    pidFile = $paths.PidFile
    expectedExecutable = $paths.ServerExe
  } | ConvertTo-Json -Depth 3
  return
}

Stop-MathAstService -Paths $paths | ConvertTo-Json -Depth 3

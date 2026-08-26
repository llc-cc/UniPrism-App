$ErrorActionPreference = 'Stop'

$toolRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $toolRoot 'MathAstPaths.psm1') -Force
Import-Module (Join-Path $toolRoot 'MathAstService.psm1') -Force

$paths = Get-MathAstPaths -Root 'D:\dev\local-ai\math-ast'
$invocation = New-MathAstServiceInvocation -Paths $paths

if ($invocation.executable -ne $paths.ServerExe) { throw 'Executable mismatch' }
if ($invocation.healthUrl -ne 'http://127.0.0.1:8081/health') { throw 'Health URL mismatch' }
if ($invocation.host -ne '127.0.0.1') { throw 'Service must bind to loopback' }
if ($invocation.port -ne 8081) { throw 'Service port mismatch' }

$expectedArguments = @(
  '--model', $paths.ModelFile,
  '--host', '127.0.0.1',
  '--port', '8081',
  '--threads', '8',
  '--ctx-size', '2048',
  '--n-predict', '512',
  '--batch-size', '128',
  '--ubatch-size', '128',
  '--no-webui'
)
if (($invocation.arguments -join '|') -ne ($expectedArguments -join '|')) {
  throw "Service arguments mismatch: $($invocation.arguments -join '|')"
}

$customInvocation = New-MathAstServiceInvocation -Paths $paths -Port 8128 -Threads 4
if ($customInvocation.healthUrl -ne 'http://127.0.0.1:8128/health') {
  throw 'Custom health URL mismatch'
}
if (($customInvocation.arguments -join '|') -notlike '*--threads|4*') {
  throw 'Custom thread count was not applied'
}

$startDescriptor = & (Join-Path $toolRoot 'start.ps1') -ValidateOnly | ConvertFrom-Json
if ($startDescriptor.executable -ne $paths.ServerExe) { throw 'Start executable mismatch' }
if (($startDescriptor.arguments -join '|') -ne ($expectedArguments -join '|')) {
  throw 'Start script did not reuse the service descriptor'
}

$expectedExe = [IO.Path]::GetFullPath($paths.ServerExe)
Assert-MathAstServiceProcessMatch -ExpectedExecutable $expectedExe -ActualExecutable $expectedExe
foreach ($actual in @(
  'D:\dev\local-ai\math-ast\bin\llama-cli.exe',
  'D:\other\llama-server.exe'
)) {
  try {
    Assert-MathAstServiceProcessMatch -ExpectedExecutable $expectedExe -ActualExecutable $actual
    throw "Wrong process path should have been rejected: $actual"
  } catch {
    if ($_.Exception.Message -eq "Wrong process path should have been rejected: $actual") { throw }
  }
}

$missingRoot = Join-Path $PSScriptRoot ('.missing-' + [Guid]::NewGuid().ToString('N'))
try {
  & (Join-Path $toolRoot 'start.ps1') -Root $missingRoot
  throw 'Start should reject missing artifacts'
} catch {
  if ($_.Exception.Message -eq 'Start should reject missing artifacts') { throw }
  if ($_.Exception.Message -notlike '*Run setup.ps1 first*') {
    throw "Missing artifact error was unclear: $($_.Exception.Message)"
  }
}

$stopDescriptor = & (Join-Path $toolRoot 'stop.ps1') -ValidateOnly | ConvertFrom-Json
if ($stopDescriptor.pidFile -ne $paths.PidFile) { throw 'Stop PID path mismatch' }
if ($stopDescriptor.expectedExecutable -ne $paths.ServerExe) {
  throw 'Stop executable boundary mismatch'
}

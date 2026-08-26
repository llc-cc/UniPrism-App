Set-StrictMode -Version Latest

$script:ExpectedModelSha256 = 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5'

# Build one descriptor so validation and execution share the same argv.
function New-MathAstServiceInvocation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Paths,
    [ValidateRange(1, 65535)][int] $Port = 8081,
    [ValidateRange(1, 64)][int] $Threads = 8
  )

  $arguments = @(
    '--model', $Paths.ModelFile,
    '--host', '127.0.0.1',
    '--port', [string]$Port,
    '--threads', [string]$Threads,
    '--ctx-size', '2048',
    '--n-predict', '512',
    '--batch-size', '128',
    '--ubatch-size', '128',
    '--no-webui'
  )
  [pscustomobject][ordered]@{
    executable = $Paths.ServerExe
    arguments = $arguments
    host = '127.0.0.1'
    port = $Port
    threads = $Threads
    healthUrl = "http://127.0.0.1:$Port/health"
  }
}

# Reject a reused PID before stopping any process.
function Assert-MathAstServiceProcessMatch {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $ExpectedExecutable,
    [Parameter(Mandatory)][string] $ActualExecutable
  )

  $expected = [IO.Path]::GetFullPath($ExpectedExecutable)
  $actual = [IO.Path]::GetFullPath($ActualExecutable)
  if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Math AST PID belongs to a different executable: $actual"
  }
}

# Recheck the manifest and hashes before using downloaded executables or weights.
function Assert-MathAstArtifacts {
  [CmdletBinding()]
  param([Parameter(Mandatory)] $Paths)

  foreach ($file in @($Paths.ServerExe, $Paths.ModelFile, $Paths.ManifestFile)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
      throw "Math AST artifact is missing: $file. Run setup.ps1 first."
    }
  }
  try {
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $Paths.ManifestFile | ConvertFrom-Json
  } catch {
    throw 'Math AST artifact manifest is invalid. Run setup.ps1 first.'
  }
  $modelHash = (Get-FileHash -LiteralPath $Paths.ModelFile -Algorithm SHA256).Hash.ToLowerInvariant()
  $serverHash = (Get-FileHash -LiteralPath $Paths.ServerExe -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($manifest.modelSha256 -ne $script:ExpectedModelSha256 -or $modelHash -ne $script:ExpectedModelSha256) {
    throw 'Math AST model hash mismatch. Run setup.ps1 first.'
  }
  if ([string]::IsNullOrWhiteSpace([string]$manifest.serverSha256) -or
      $serverHash -ne ([string]$manifest.serverSha256).ToLowerInvariant()) {
    throw 'Math AST server hash mismatch. Run setup.ps1 first.'
  }
}

# Start one hidden resident process and reclaim only that PID on health failure.
function Start-MathAstService {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Paths,
    [Parameter(Mandatory)] $Invocation,
    [ValidateRange(1, 180)][int] $HealthTimeoutSeconds = 90
  )

  Assert-MathAstArtifacts -Paths $Paths
  New-Item -ItemType Directory -Force -Path $Paths.Runtime, $Paths.Logs | Out-Null

  if (Test-Path -LiteralPath $Paths.PidFile -PathType Leaf) {
    $existingPidText = [IO.File]::ReadAllText($Paths.PidFile).Trim()
    $existingPid = 0
    if ([int]::TryParse($existingPidText, [ref]$existingPid)) {
      $existing = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
      if ($null -ne $existing) {
        Assert-MathAstServiceProcessMatch `
          -ExpectedExecutable $Paths.ServerExe `
          -ActualExecutable $existing.Path
        return [pscustomobject]@{ status = 'already-running'; pid = $existingPid }
      }
    }
    Remove-Item -LiteralPath $Paths.PidFile -Force
  }

  $process = Start-Process `
    -FilePath $Invocation.executable `
    -ArgumentList $Invocation.arguments `
    -RedirectStandardOutput $Paths.StdOutLog `
    -RedirectStandardError $Paths.StdErrLog `
    -WindowStyle Hidden `
    -PassThru
  [IO.File]::WriteAllText($Paths.PidFile, [string]$process.Id)

  $deadline = [DateTime]::UtcNow.AddSeconds($HealthTimeoutSeconds)
  try {
    do {
      if ($process.HasExited) {
        throw "Math AST service exited with code $($process.ExitCode)"
      }
      try {
        Invoke-RestMethod -Method Get -Uri $Invocation.healthUrl -TimeoutSec 2 | Out-Null
        return [pscustomobject]@{ status = 'started'; pid = $process.Id }
      } catch {
        Start-Sleep -Milliseconds 250
      }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Math AST service health check timed out after $HealthTimeoutSeconds seconds"
  } catch {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $Paths.PidFile) { Remove-Item -LiteralPath $Paths.PidFile -Force }
    throw
  }
}

# Stop only the recorded PID after its executable path matches exactly.
function Stop-MathAstService {
  [CmdletBinding()]
  param([Parameter(Mandatory)] $Paths)

  if (-not (Test-Path -LiteralPath $Paths.PidFile -PathType Leaf)) {
    return [pscustomobject]@{ status = 'not-running'; pid = $null }
  }
  $pidText = [IO.File]::ReadAllText($Paths.PidFile).Trim()
  $servicePid = 0
  if (-not [int]::TryParse($pidText, [ref]$servicePid)) {
    throw "Math AST PID file is invalid: $($Paths.PidFile)"
  }
  $process = Get-Process -Id $servicePid -ErrorAction SilentlyContinue
  if ($null -eq $process) {
    Remove-Item -LiteralPath $Paths.PidFile -Force
    return [pscustomobject]@{ status = 'stale-pid-removed'; pid = $servicePid }
  }
  Assert-MathAstServiceProcessMatch `
    -ExpectedExecutable $Paths.ServerExe `
    -ActualExecutable $process.Path
  Stop-Process -Id $servicePid -Force -ErrorAction Stop
  Remove-Item -LiteralPath $Paths.PidFile -Force
  [pscustomobject]@{ status = 'stopped'; pid = $servicePid }
}

Export-ModuleMember -Function `
  New-MathAstServiceInvocation, `
  Assert-MathAstServiceProcessMatch, `
  Assert-MathAstArtifacts, `
  Start-MathAstService, `
  Stop-MathAstService

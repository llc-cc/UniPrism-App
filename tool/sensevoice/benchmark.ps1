[CmdletBinding()]
param(
  [string] $Root = 'D:\dev\local-ai\sensevoice',
  [string] $AudioDirectory = 'D:\dev\local-ai\sensevoice\benchmarks\audio',
  [string] $ServiceBaseUri = 'http://127.0.0.1:8000'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SenseVoicePaths.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SenseVoiceBenchmark.psm1') -Force
$paths = Get-SenseVoicePaths -Root $Root
$manifestPath = Join-Path $PSScriptRoot 'benchmark-cases.json'
$resultsDirectory = Join-Path $paths.Benchmarks 'results'

$run = Invoke-SenseVoiceBenchmarkRun `
  -ManifestPath $manifestPath `
  -AudioDirectory $AudioDirectory `
  -ResultsDirectory $resultsDirectory `
  -ServiceBaseUri $ServiceBaseUri

$summary = $run.Document.summary
Write-Host ("Median: {0} ms, RTF {1}" -f $summary.medianElapsedMs, $summary.medianRtf)
Write-Host ("P95: {0} ms, RTF {1}" -f $summary.p95ElapsedMs, $summary.p95Rtf)
Write-Host "Raw benchmark JSON: $($run.ResultPath)"

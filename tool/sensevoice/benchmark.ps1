[CmdletBinding()]
param(
  [string] $Root = 'D:\dev\local-ai\sensevoice',
  [string] $AudioDirectory = 'D:\dev\local-ai\sensevoice\benchmarks\audio',
  [string] $ServiceBaseUri = 'http://127.0.0.1:8000'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WavDurationSeconds {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string] $Path)

  $stream = [IO.File]::OpenRead($Path)
  $reader = [IO.BinaryReader]::new($stream)
  try {
    if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'RIFF') {
      throw "WAV fixture is not RIFF: $Path"
    }
    [void]$reader.ReadUInt32()
    if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'WAVE') {
      throw "WAV fixture is not WAVE: $Path"
    }

    $byteRate = $null
    $dataBytes = $null
    while ($stream.Position + 8 -le $stream.Length) {
      $chunkId = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
      $chunkSize = [uint32]$reader.ReadUInt32()
      $chunkStart = $stream.Position
      if ($chunkId -eq 'fmt ') {
        if ($chunkSize -lt 16) { throw "WAV fmt chunk is too short: $Path" }
        $formatTag = $reader.ReadUInt16()
        [void]$reader.ReadUInt16()
        [void]$reader.ReadUInt32()
        $byteRate = [uint32]$reader.ReadUInt32()
        [void]$reader.ReadUInt16()
        [void]$reader.ReadUInt16()
        if ($formatTag -ne 1) { throw "WAV fixture must use PCM encoding: $Path" }
      } elseif ($chunkId -eq 'data') {
        $dataBytes = [uint32]$chunkSize
      }

      $nextChunk = $chunkStart + $chunkSize + ($chunkSize % 2)
      if ($nextChunk -gt $stream.Length) { throw "WAV chunk exceeds file length: $Path" }
      $stream.Position = $nextChunk
    }

    if ($null -eq $byteRate -or $byteRate -le 0 -or $null -eq $dataBytes) {
      throw "WAV fixture is missing a valid fmt or data chunk: $Path"
    }
    return [double]$dataBytes / [double]$byteRate
  } finally {
    $reader.Dispose()
    $stream.Dispose()
  }
}

function Invoke-SenseVoiceTranscription {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Uri,
    [Parameter(Mandatory)][string] $AudioPath
  )

  $invokeRestMethod = Get-Command Invoke-RestMethod
  if ($invokeRestMethod.Parameters.ContainsKey('Form')) {
    $form = @{
      file = Get-Item -LiteralPath $AudioPath
      model = 'sensevoice'
      response_format = 'json'
    }
    return Invoke-RestMethod -Uri $Uri -Method Post -Form $form
  }

  # Windows PowerShell 5.1 没有 Invoke-RestMethod -Form，使用同等 multipart 协议保持本机可执行.
  Add-Type -AssemblyName System.Net.Http
  $client = [Net.Http.HttpClient]::new()
  $multipart = [Net.Http.MultipartFormDataContent]::new()
  $fileStream = [IO.File]::OpenRead($AudioPath)
  $fileContent = [Net.Http.StreamContent]::new($fileStream)
  try {
    $fileContent.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('audio/wav')
    $multipart.Add($fileContent, 'file', [IO.Path]::GetFileName($AudioPath))
    $multipart.Add([Net.Http.StringContent]::new('sensevoice'), 'model')
    $multipart.Add([Net.Http.StringContent]::new('json'), 'response_format')
    $response = $client.PostAsync($Uri, $multipart).GetAwaiter().GetResult()
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $response.IsSuccessStatusCode) {
      throw "SenseVoice transcription failed with HTTP $([int]$response.StatusCode): $body"
    }
    return $body | ConvertFrom-Json
  } finally {
    $multipart.Dispose()
    $fileStream.Dispose()
    $client.Dispose()
  }
}

function Get-Percentile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][double[]] $Values,
    [Parameter(Mandatory)][ValidateRange(0, 1)][double] $Percentile
  )

  if ($Values.Count -eq 0) { throw 'Cannot calculate a percentile for an empty sample' }
  $sorted = @($Values | Sort-Object)
  $index = [Math]::Max(0, [Math]::Ceiling($Percentile * $sorted.Count) - 1)
  return [double]$sorted[$index]
}

$modulePath = Join-Path $PSScriptRoot 'SenseVoicePaths.psm1'
Import-Module $modulePath -Force
$paths = Get-SenseVoicePaths -Root $Root
$manifestPath = Join-Path $PSScriptRoot 'benchmark-cases.json'
$manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json

# 先完整校验录音清单，避免缺文件时仍触发模型加载或产生不完整的基准结果.
$missingFiles = @(
  $manifest.cases |
    ForEach-Object { Join-Path $AudioDirectory $_.file } |
    Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
)
if ($missingFiles.Count -gt 0) {
  throw "Missing benchmark audio fixtures:`n$($missingFiles -join "`n")"
}

$healthUri = "$($ServiceBaseUri.TrimEnd('/'))/health"
$transcriptionUri = "$($ServiceBaseUri.TrimEnd('/'))/v1/audio/transcriptions"
$health = Invoke-RestMethod -Uri $healthUri -Method Get
if ($health.status -ne 'healthy') {
  throw "SenseVoice health check did not report healthy: $($health | ConvertTo-Json -Compress)"
}

$firstAudio = Join-Path $AudioDirectory $manifest.cases[0].file
Write-Host "Warming up with $firstAudio (excluded from statistics)..."
Invoke-SenseVoiceTranscription -Uri $transcriptionUri -AudioPath $firstAudio | Out-Null

$samples = @()
foreach ($case in $manifest.cases) {
  $audioPath = Join-Path $AudioDirectory $case.file
  $audioSeconds = Get-WavDurationSeconds -Path $audioPath
  if ($audioSeconds -le 0) { throw "WAV fixture has zero duration: $audioPath" }

  foreach ($iteration in 1..3) {
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-SenseVoiceTranscription -Uri $transcriptionUri -AudioPath $audioPath
    $stopwatch.Stop()
    $elapsedMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
    $samples += [pscustomobject][ordered]@{
      caseId = [string]$case.id
      audioSeconds = [Math]::Round($audioSeconds, 6)
      elapsedMs = $elapsedMs
      rtf = [Math]::Round(($elapsedMs / 1000) / $audioSeconds, 6)
      text = [string]$response.text
      runtime = [string]$health.runtime
      device = [string]$health.device
      timestamp = [DateTime]::UtcNow.ToString('o')
    }
    Write-Host ("{0} run {1}: {2} ms, RTF {3}, text={4}" -f `
      $case.id, $iteration, $elapsedMs, $samples[-1].rtf, $response.text)
  }
}

$elapsedValues = [double[]]@($samples | ForEach-Object { $_.elapsedMs })
$rtfValues = [double[]]@($samples | ForEach-Object { $_.rtf })
$summary = [pscustomobject][ordered]@{
  medianElapsedMs = Get-Percentile -Values $elapsedValues -Percentile 0.5
  p95ElapsedMs = Get-Percentile -Values $elapsedValues -Percentile 0.95
  medianRtf = Get-Percentile -Values $rtfValues -Percentile 0.5
  p95Rtf = Get-Percentile -Values $rtfValues -Percentile 0.95
}

$resultsDirectory = Join-Path $paths.Benchmarks 'results'
New-Item -ItemType Directory -Force -Path $resultsDirectory | Out-Null
$generatedAt = [DateTime]::UtcNow
$resultPath = Join-Path $resultsDirectory ($generatedAt.ToString('yyyyMMddTHHmmssfffZ') + '.json')
[pscustomobject][ordered]@{
  version = 1
  generatedAt = $generatedAt.ToString('o')
  samples = $samples
  summary = $summary
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8

Write-Host ("Median: {0} ms, RTF {1}" -f $summary.medianElapsedMs, $summary.medianRtf)
Write-Host ("P95: {0} ms, RTF {1}" -f $summary.p95ElapsedMs, $summary.p95Rtf)
Write-Host "Raw benchmark JSON: $resultPath"

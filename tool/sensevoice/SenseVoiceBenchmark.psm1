Set-StrictMode -Version Latest

function Get-SenseVoiceWavDurationSeconds {
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

      # RIFF chunk payloads use one padding byte when their declared length is odd.
      $nextChunk = $chunkStart + $chunkSize + ($chunkSize % 2)
      if ($nextChunk -gt $stream.Length) { throw "WAV chunk exceeds file length: $Path" }
      $stream.Position = $nextChunk
    }

    if ($null -eq $byteRate -or $byteRate -le 0 -or $null -eq $dataBytes) {
      throw "WAV fixture is missing a valid fmt or data chunk: $Path"
    }
    $duration = [double]$dataBytes / [double]$byteRate
    if ($duration -le 0) { throw "WAV fixture has zero duration: $Path" }
    return $duration
  } finally {
    $reader.Dispose()
    $stream.Dispose()
  }
}

function Get-SenseVoicePercentile {
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

function New-SenseVoiceBenchmarkClock {
  [CmdletBinding()]
  param()

  [pscustomobject]@{
    Frequency = [long][Diagnostics.Stopwatch]::Frequency
    GetTimestamp = { return [Diagnostics.Stopwatch]::GetTimestamp() }
    GetUtcNow = { return [DateTime]::UtcNow }
  }
}

function Invoke-SenseVoiceMultipartWithHttpClient {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Uri,
    [Parameter(Mandatory)][string] $AudioPath,
    [scriptblock] $HttpClientFactory = { return [Net.Http.HttpClient]::new() }
  )

  Add-Type -AssemblyName System.Net.Http
  $client = & $HttpClientFactory
  if ($client -isnot [Net.Http.HttpClient]) {
    throw 'SenseVoice HttpClient factory must return System.Net.Http.HttpClient'
  }

  try {
    $multipart = [Net.Http.MultipartFormDataContent]::new()
    try {
      $fileStream = [IO.File]::OpenRead($AudioPath)
      try {
        $fileContent = [Net.Http.StreamContent]::new($fileStream)
        try {
          $fileContent.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('audio/wav')
          $multipart.Add($fileContent, 'file', [IO.Path]::GetFileName($AudioPath))
          $multipart.Add([Net.Http.StringContent]::new('sensevoice'), 'model')
          $multipart.Add([Net.Http.StringContent]::new('json'), 'response_format')

          $response = $null
          try {
            $response = $client.PostAsync($Uri, $multipart).GetAwaiter().GetResult()
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
              throw "SenseVoice transcription failed with HTTP $([int]$response.StatusCode): $body"
            }
            return $body | ConvertFrom-Json
          } finally {
            if ($null -ne $response) { $response.Dispose() }
          }
        } finally {
          # Multipart owns request content after Add; duplicate Dispose is idempotent and closes early-failure paths too.
          $fileContent.Dispose()
        }
      } finally {
        $fileStream.Dispose()
      }
    } finally {
      $multipart.Dispose()
    }
  } finally {
    $client.Dispose()
  }
}

function Invoke-SenseVoiceDefaultHttpTransport {
  [CmdletBinding()]
  param([Parameter(Mandatory)] $Request)

  if ($Request.Method -eq 'GET') {
    return Invoke-RestMethod -Uri $Request.Uri -Method Get
  }
  if ($Request.Method -ne 'POST') {
    throw "Unsupported SenseVoice HTTP method: $($Request.Method)"
  }

  $invokeRestMethod = Get-Command Invoke-RestMethod
  if ($invokeRestMethod.Parameters.ContainsKey('Form')) {
    return Invoke-RestMethod -Uri $Request.Uri -Method Post -Form $Request.Fields
  }
  return Invoke-SenseVoiceMultipartWithHttpClient `
    -Uri $Request.Uri `
    -AudioPath $Request.Fields.file
}

function Invoke-SenseVoiceBenchmarkRun {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $AudioDirectory,
    [Parameter(Mandatory)][string] $ResultsDirectory,
    [Parameter(Mandatory)][string] $ServiceBaseUri,
    [scriptblock] $HttpTransport = { param($Request) Invoke-SenseVoiceDefaultHttpTransport -Request $Request },
    $Clock = (New-SenseVoiceBenchmarkClock)
  )

  $manifest = Get-Content -Raw -Encoding UTF8 $ManifestPath | ConvertFrom-Json
  $missingFiles = @(
    $manifest.cases |
      ForEach-Object { Join-Path $AudioDirectory $_.file } |
      Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
  )
  if ($missingFiles.Count -gt 0) {
    throw "Missing benchmark audio fixtures:`n$($missingFiles -join "`n")"
  }

  $serviceRoot = $ServiceBaseUri.TrimEnd('/')
  $healthRequest = [pscustomobject][ordered]@{
    Method = 'GET'
    Uri = "$serviceRoot/health"
    Fields = $null
  }
  $health = & $HttpTransport $healthRequest
  if ($health.status -ne 'healthy') {
    throw "SenseVoice health check did not report healthy: $($health | ConvertTo-Json -Compress)"
  }

  $transcriptionUri = "$serviceRoot/v1/audio/transcriptions"
  $newTranscriptionRequest = {
    param($AudioPath)
    [pscustomobject][ordered]@{
      Method = 'POST'
      Uri = $transcriptionUri
      Fields = [ordered]@{
        file = $AudioPath
        model = 'sensevoice'
        response_format = 'json'
      }
    }
  }

  $firstAudio = Join-Path $AudioDirectory $manifest.cases[0].file
  & $HttpTransport (& $newTranscriptionRequest $firstAudio) | Out-Null

  $samples = [Collections.ArrayList]::new()
  foreach ($case in $manifest.cases) {
    $audioPath = Join-Path $AudioDirectory $case.file
    $audioSeconds = Get-SenseVoiceWavDurationSeconds -Path $audioPath
    foreach ($iteration in 1..3) {
      $started = [long](& $Clock.GetTimestamp)
      $response = & $HttpTransport (& $newTranscriptionRequest $audioPath)
      $finished = [long](& $Clock.GetTimestamp)
      $elapsedMs = [Math]::Round((($finished - $started) * 1000.0) / [double]$Clock.Frequency, 3)
      $timestamp = (& $Clock.GetUtcNow).ToUniversalTime()
      [void]$samples.Add([pscustomobject][ordered]@{
        caseId = [string]$case.id
        audioSeconds = [Math]::Round($audioSeconds, 6)
        elapsedMs = $elapsedMs
        rtf = [Math]::Round(($elapsedMs / 1000) / $audioSeconds, 6)
        text = [string]$response.text
        runtime = [string]$health.runtime
        device = [string]$health.device
        timestamp = $timestamp.ToString('o')
      })
    }
  }

  $elapsedValues = [double[]]@($samples | ForEach-Object { $_.elapsedMs })
  $rtfValues = [double[]]@($samples | ForEach-Object { $_.rtf })
  $summary = [pscustomobject][ordered]@{
    medianElapsedMs = Get-SenseVoicePercentile -Values $elapsedValues -Percentile 0.5
    p95ElapsedMs = Get-SenseVoicePercentile -Values $elapsedValues -Percentile 0.95
    medianRtf = Get-SenseVoicePercentile -Values $rtfValues -Percentile 0.5
    p95Rtf = Get-SenseVoicePercentile -Values $rtfValues -Percentile 0.95
  }

  $generatedAt = (& $Clock.GetUtcNow).ToUniversalTime()
  $document = [pscustomobject][ordered]@{
    version = 1
    generatedAt = $generatedAt.ToString('o')
    samples = @($samples)
    summary = $summary
  }
  New-Item -ItemType Directory -Force -Path $ResultsDirectory | Out-Null
  $resultPath = Join-Path $ResultsDirectory ($generatedAt.ToString('yyyyMMddTHHmmssfffZ') + '.json')
  $document | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8

  [pscustomobject]@{
    ResultPath = $resultPath
    Document = $document
  }
}

Export-ModuleMember -Function `
  Get-SenseVoiceWavDurationSeconds, `
  Get-SenseVoicePercentile, `
  New-SenseVoiceBenchmarkClock, `
  Invoke-SenseVoiceMultipartWithHttpClient, `
  Invoke-SenseVoiceDefaultHttpTransport, `
  Invoke-SenseVoiceBenchmarkRun

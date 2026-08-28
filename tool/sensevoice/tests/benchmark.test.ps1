$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Net.Http

function Write-TestPcmWav {
  param(
    [Parameter(Mandatory)][string] $Path,
    [uint16] $FormatTag = 1,
    [uint32] $DataBytes = 16000,
    [uint32] $DeclaredDataBytes = $DataBytes,
    [switch] $OddSizedChunk
  )

  $stream = [IO.File]::Create($Path)
  $writer = [IO.BinaryWriter]::new($stream)
  try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([uint32]0)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
    if ($OddSizedChunk) {
      $writer.Write([Text.Encoding]::ASCII.GetBytes('JUNK'))
      $writer.Write([uint32]1)
      $writer.Write([byte]0x7f)
      $writer.Write([byte]0)
    }
    $writer.Write([Text.Encoding]::ASCII.GetBytes('fmt '))
    $writer.Write([uint32]16)
    $writer.Write($FormatTag)
    $writer.Write([uint16]1)
    $writer.Write([uint32]8000)
    $writer.Write([uint32]16000)
    $writer.Write([uint16]2)
    $writer.Write([uint16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write($DeclaredDataBytes)
    if ($DataBytes -gt 0) {
      $writer.Write((New-Object byte[] $DataBytes))
    }
    $writer.Flush()
    $stream.Position = 4
    $writer.Write([uint32]($stream.Length - 8))
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

function Assert-ThrowsLike {
  param(
    [Parameter(Mandatory)][scriptblock] $Action,
    [Parameter(Mandatory)][string] $Pattern
  )

  try {
    & $Action
    throw "Expected error matching: $Pattern"
  } catch {
    if ($_.Exception.Message -eq "Expected error matching: $Pattern") { throw }
    if ($_.Exception.Message -notlike $Pattern) {
      throw "Error '$($_.Exception.Message)' did not match '$Pattern'"
    }
  }
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("sensevoice-benchmark-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
try {
  $modulePath = Join-Path $PSScriptRoot '..\SenseVoiceBenchmark.psm1'
  Import-Module $modulePath -Force

  $normalWav = Join-Path $temporaryRoot 'normal.wav'
  Write-TestPcmWav -Path $normalWav
  $normalDuration = Get-SenseVoiceWavDurationSeconds -Path $normalWav
  if ([Math]::Abs($normalDuration - 1.0) -gt 0.000001) {
    throw "Normal PCM WAV duration mismatch: $normalDuration"
  }

  $oddChunkWav = Join-Path $temporaryRoot 'odd-chunk.wav'
  Write-TestPcmWav -Path $oddChunkWav -OddSizedChunk
  $oddChunkDuration = Get-SenseVoiceWavDurationSeconds -Path $oddChunkWav
  if ([Math]::Abs($oddChunkDuration - 1.0) -gt 0.000001) {
    throw "Odd-sized chunk padding changed WAV duration: $oddChunkDuration"
  }

  $nonPcmWav = Join-Path $temporaryRoot 'non-pcm.wav'
  Write-TestPcmWav -Path $nonPcmWav -FormatTag 3
  Assert-ThrowsLike -Pattern '*must use PCM*' -Action {
    Get-SenseVoiceWavDurationSeconds -Path $nonPcmWav | Out-Null
  }

  $truncatedWav = Join-Path $temporaryRoot 'truncated.wav'
  Write-TestPcmWav -Path $truncatedWav -DataBytes 2 -DeclaredDataBytes 100
  Assert-ThrowsLike -Pattern '*exceeds file length*' -Action {
    Get-SenseVoiceWavDurationSeconds -Path $truncatedWav | Out-Null
  }

  $zeroDurationWav = Join-Path $temporaryRoot 'zero-duration.wav'
  Write-TestPcmWav -Path $zeroDurationWav -DataBytes 0
  Assert-ThrowsLike -Pattern '*zero duration*' -Action {
    Get-SenseVoiceWavDurationSeconds -Path $zeroDurationWav | Out-Null
  }

  $audioDirectory = Join-Path $temporaryRoot 'audio'
  $resultsDirectory = Join-Path $temporaryRoot 'results'
  New-Item -ItemType Directory -Force -Path $audioDirectory | Out-Null
  $manifestPath = Join-Path $PSScriptRoot '..\benchmark-cases.json'
  $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
  foreach ($case in $manifest.cases) {
    Write-TestPcmWav -Path (Join-Path $audioDirectory $case.file)
  }
  $hashesBefore = @{}
  foreach ($case in $manifest.cases) {
    $path = Join-Path $audioDirectory $case.file
    $hashesBefore[$case.file] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  }

  $httpCalls = [Collections.ArrayList]::new()
  $httpTransport = {
    param($Request)
    [void]$httpCalls.Add($Request)
    if ($Request.Method -eq 'GET') {
      return [pscustomobject]@{
        status = 'healthy'
        runtime = 'funasr-1.3.29'
        device = 'cpu'
      }
    }
    return [pscustomobject]@{ text = "text-$($httpCalls.Count)" }
  }

  $timestamps = [Collections.Generic.Queue[long]]::new()
  foreach ($elapsed in 100..1500 | Where-Object { $_ % 100 -eq 0 }) {
    $timestamps.Enqueue(0)
    $timestamps.Enqueue([long]$elapsed)
  }
  $fixedUtc = [DateTime]::SpecifyKind([DateTime]'2026-08-25T12:34:56', [DateTimeKind]::Utc)
  $clock = [pscustomobject]@{
    Frequency = [long]1000
    GetTimestamp = { return $timestamps.Dequeue() }
    GetUtcNow = { return $fixedUtc }
  }

  $run = Invoke-SenseVoiceBenchmarkRun `
    -ManifestPath $manifestPath `
    -AudioDirectory $audioDirectory `
    -ResultsDirectory $resultsDirectory `
    -ServiceBaseUri 'http://127.0.0.1:8000' `
    -HttpTransport $httpTransport `
    -Clock $clock

  if ($httpCalls.Count -ne 17) { throw "HTTP call count mismatch: $($httpCalls.Count)" }
  if ($httpCalls[0].Method -ne 'GET' -or $httpCalls[0].Uri -ne 'http://127.0.0.1:8000/health') {
    throw "Health request mismatch: $($httpCalls[0] | ConvertTo-Json -Compress)"
  }
  $postCalls = @($httpCalls | Where-Object { $_.Method -eq 'POST' })
  if ($postCalls.Count -ne 16) { throw "Warmup plus sample POST count mismatch: $($postCalls.Count)" }
  foreach ($post in $postCalls) {
    if ($post.Fields -isnot [Collections.IDictionary]) {
      throw "PowerShell 7 -Form requires IDictionary fields, got: $($post.Fields.GetType().FullName)"
    }
    if ($post.Uri -ne 'http://127.0.0.1:8000/v1/audio/transcriptions') {
      throw "Transcription URI mismatch: $($post.Uri)"
    }
    if ($post.Fields.model -ne 'sensevoice' -or $post.Fields.response_format -ne 'json') {
      throw "Multipart fields mismatch: $($post.Fields | ConvertTo-Json -Compress)"
    }
    if (-not (Test-Path -LiteralPath $post.Fields.file -PathType Leaf)) {
      throw "Multipart file field was not a fixture path: $($post.Fields.file)"
    }
  }

  if ($run.Document.samples.Count -ne 15) {
    throw "Recorded sample count mismatch: $($run.Document.samples.Count)"
  }
  if ($run.Document.samples[0].elapsedMs -ne 100 -or $run.Document.samples[0].rtf -ne 0.1) {
    throw "First elapsed/RTF mismatch: $($run.Document.samples[0] | ConvertTo-Json -Compress)"
  }
  if ($run.Document.samples[0].timestamp -ne '2026-08-25T12:34:56.0000000Z') {
    throw "Sample timestamp is not deterministic UTC: $($run.Document.samples[0].timestamp)"
  }
  if ($run.Document.summary.medianElapsedMs -ne 800 -or $run.Document.summary.p95ElapsedMs -ne 1500) {
    throw "Elapsed summary mismatch: $($run.Document.summary | ConvertTo-Json -Compress)"
  }
  if ($run.Document.summary.medianRtf -ne 0.8 -or $run.Document.summary.p95Rtf -ne 1.5) {
    throw "RTF summary mismatch: $($run.Document.summary | ConvertTo-Json -Compress)"
  }
  $expectedResultPath = Join-Path $resultsDirectory '20260825T123456000Z.json'
  if ($run.ResultPath -ne $expectedResultPath -or -not (Test-Path -LiteralPath $expectedResultPath -PathType Leaf)) {
    throw "UTC result path mismatch: $($run.ResultPath)"
  }
  $rawResult = Get-Content -Raw -Encoding UTF8 $expectedResultPath | ConvertFrom-Json
  if ($rawResult.samples.Count -ne 15 -or $rawResult.generatedAt -ne '2026-08-25T12:34:56.0000000Z') {
    throw "Raw benchmark JSON mismatch: $($rawResult | ConvertTo-Json -Compress)"
  }
  foreach ($case in $manifest.cases) {
    $path = Join-Path $audioDirectory $case.file
    $hashAfter = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hashAfter -ne $hashesBefore[$case.file]) {
      throw "Benchmark modified fixture: $($case.file)"
    }
  }

  if (-not ('SenseVoice.Tests.TrackingHandler' -as [type])) {
    Add-Type -ReferencedAssemblies ([Net.Http.HttpClient].Assembly.Location) -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace SenseVoice.Tests {
  public sealed class TrackingContent : HttpContent {
    private readonly string body;
    private readonly bool throwOnRead;
    public bool WasDisposed { get; private set; }

    public TrackingContent(string body, bool throwOnRead) {
      this.body = body;
      this.throwOnRead = throwOnRead;
    }

    protected override Task SerializeToStreamAsync(Stream stream, TransportContext context) {
      if (throwOnRead) {
        var failed = new TaskCompletionSource<object>();
        failed.SetException(new InvalidOperationException("read failed"));
        return failed.Task;
      }
      byte[] bytes = Encoding.UTF8.GetBytes(body);
      return stream.WriteAsync(bytes, 0, bytes.Length);
    }

    protected override bool TryComputeLength(out long length) {
      length = Encoding.UTF8.GetByteCount(body);
      return true;
    }

    protected override void Dispose(bool disposing) {
      WasDisposed = true;
      base.Dispose(disposing);
    }
  }

  public sealed class TrackingResponse : HttpResponseMessage {
    public bool WasDisposed { get; private set; }

    public TrackingResponse(HttpStatusCode status, HttpContent content) {
      StatusCode = status;
      Content = content;
    }

    protected override void Dispose(bool disposing) {
      WasDisposed = true;
      base.Dispose(disposing);
    }
  }

  public sealed class TrackingHandler : HttpMessageHandler {
    private readonly HttpResponseMessage response;
    public bool WasDisposed { get; private set; }
    public string CapturedBody { get; private set; }
    public string CapturedContentType { get; private set; }

    public TrackingHandler(HttpResponseMessage response) {
      this.response = response;
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) {
      CapturedContentType = request.Content.Headers.ContentType.MediaType;
      CapturedBody = await request.Content.ReadAsStringAsync();
      return response;
    }

    protected override void Dispose(bool disposing) {
      WasDisposed = true;
      base.Dispose(disposing);
    }
  }
}
'@
  }

  function New-TrackingHttpFixture {
    param(
      [Net.HttpStatusCode] $Status,
      [string] $Body,
      [switch] $ThrowOnRead
    )

    $content = [SenseVoice.Tests.TrackingContent]::new($Body, $ThrowOnRead.IsPresent)
    $response = [SenseVoice.Tests.TrackingResponse]::new($Status, $content)
    $handler = [SenseVoice.Tests.TrackingHandler]::new($response)
    $factory = { return [Net.Http.HttpClient]::new($handler) }.GetNewClosure()
    [pscustomobject]@{
      Content = $content
      Response = $response
      Handler = $handler
      Factory = $factory
    }
  }

  $successFixture = New-TrackingHttpFixture -Status OK -Body '{"text":"ok"}'
  $success = Invoke-SenseVoiceMultipartWithHttpClient `
    -Uri 'http://127.0.0.1:8000/v1/audio/transcriptions' `
    -AudioPath $normalWav `
    -HttpClientFactory $successFixture.Factory
  if ($success.text -ne 'ok') { throw "2xx multipart response mismatch: $($success | ConvertTo-Json -Compress)" }
  if (-not $successFixture.Response.WasDisposed -or -not $successFixture.Content.WasDisposed -or -not $successFixture.Handler.WasDisposed) {
    throw '2xx multipart request leaked response, content, or client handler'
  }
  if ($successFixture.Handler.CapturedContentType -ne 'multipart/form-data') {
    throw "Fallback content type mismatch: $($successFixture.Handler.CapturedContentType)"
  }
  foreach ($fieldText in @('name=file', 'name=model', 'sensevoice', 'name=response_format', 'json')) {
    if ($successFixture.Handler.CapturedBody -notlike "*$fieldText*") {
      throw "Fallback multipart body omitted $fieldText"
    }
  }

  $errorFixture = New-TrackingHttpFixture -Status BadRequest -Body '{"detail":"bad"}'
  Assert-ThrowsLike -Pattern '*HTTP 400*bad*' -Action {
    Invoke-SenseVoiceMultipartWithHttpClient `
      -Uri 'http://127.0.0.1:8000/v1/audio/transcriptions' `
      -AudioPath $normalWav `
      -HttpClientFactory $errorFixture.Factory | Out-Null
  }
  if (-not $errorFixture.Response.WasDisposed -or -not $errorFixture.Content.WasDisposed -or -not $errorFixture.Handler.WasDisposed) {
    throw 'Non-2xx multipart request leaked response, content, or client handler'
  }

  $readFailureFixture = New-TrackingHttpFixture -Status OK -Body '' -ThrowOnRead
  Assert-ThrowsLike -Pattern '*read failed*' -Action {
    Invoke-SenseVoiceMultipartWithHttpClient `
      -Uri 'http://127.0.0.1:8000/v1/audio/transcriptions' `
      -AudioPath $normalWav `
      -HttpClientFactory $readFailureFixture.Factory | Out-Null
  }
  if (-not $readFailureFixture.Response.WasDisposed -or -not $readFailureFixture.Content.WasDisposed -or -not $readFailureFixture.Handler.WasDisposed) {
    throw 'Response read failure leaked response, content, or client handler'
  }
} finally {
  # 唯一临时目录由本测试创建且位于系统临时根，递归清理不会触及 benchmark fixture 目录.
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}

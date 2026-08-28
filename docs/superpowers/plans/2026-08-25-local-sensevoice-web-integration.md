# Local SenseVoice Web Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run SenseVoiceSmall locally from D drive, measure this Windows laptop's real CPU/Vulkan performance, and make the Flutter Web formula page obtain its transcript from the local ASR service.

**Architecture:** A D-drive FunASR Python service preloads SenseVoiceSmall and exposes the official OpenAI-compatible transcription endpoint on loopback. Flutter Web records 16kHz mono PCM, wraps it as WAV, uploads it through a typed ASR client, and forwards only the final transcript into the existing formula conversion controller. The existing browser `speech_to_text` adapter remains an explicit development fallback, while GGUF CPU/Vulkan is benchmarked separately rather than used as a per-request subprocess in the primary page path.

**Tech Stack:** Windows PowerShell 7, Python 3.11 virtual environment, FunASR 1.3.29, SenseVoiceSmall, PyTorch CPU, Flutter 3 / Dart 3.12, `record` 7.1.1, `http` 1.2.2, Flutter tests.

**Spec:** `docs/superpowers/specs/2026-08-25-local-sensevoice-spoken-formula-design.md`

## Global Constraints

- Read and follow `docs/DEVELOPMENT_CODE_STANDARD.md` before code changes.
- Execute feature work in an isolated worktree created through `superpowers:using-git-worktrees`; do not mix it with the current dirty checkout.
- Put runtime, virtual environment, weights, caches, temporary audio, and raw benchmark output under `D:\dev\local-ai\sensevoice`.
- Do not install Docker Desktop or place a model cache on C drive.
- Bind the development ASR service to `127.0.0.1:8000`; never expose the unauthenticated service on `0.0.0.0`.
- Accept at most 15 seconds and 5MB of audio per request; use one local inference at a time.
- Do not commit virtual environments, model weights, test recordings, generated benchmark JSON, or temporary audio.
- Do not send audio to MiniMax or any cloud ASR provider.
- Preserve formula preview and explicit user confirmation before answer insertion.
- Distinguish cold-start time from warm inference time in every benchmark report.

---

## File Structure

Runtime tooling in the Flutter repository:

- `tool/sensevoice/SenseVoicePaths.psm1`: resolves and validates all D-drive paths and process-local cache environment variables.
- `tool/sensevoice/setup.ps1`: creates the D-drive Python environment and installs the pinned CPU runtime.
- `tool/sensevoice/start.ps1`: starts the loopback-only persistent SenseVoice service.
- `tool/sensevoice/benchmark.ps1`: sends a versioned audio manifest to the local endpoint and records latency/RTF without moving data to C drive.
- `tool/sensevoice/benchmark-cases.json`: committed test-case metadata; audio files remain under the external D-drive benchmark directory.
- `tool/sensevoice/tests/paths.test.ps1`: dependency-free PowerShell assertions for path and environment safety.
- `docs/operations/SENSEVOICE_LOCAL_RUNBOOK.md`: exact setup, start, stop, benchmark, disk, and troubleshooting commands.

Flutter production files:

- `lib/features/practice_assessment/core/spoken_formula.dart`: adds typed recognition failures and an optional recognition error callback.
- `lib/features/practice_assessment/core/speech_audio_capture.dart`: defines the PCM capture port used by the local recognizer.
- `lib/features/practice_assessment/adapters/record_speech_audio_capture.dart`: wraps the `record` plugin and emits 16kHz mono PCM16 chunks.
- `lib/features/practice_assessment/adapters/pcm_wav_encoder.dart`: pure PCM16-to-WAV encoder.
- `lib/features/practice_assessment/adapters/sensevoice_asr_client.dart`: health check and multipart transcription client.
- `lib/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart`: owns one short recording, upload, timeout, cancellation, and final callback.
- `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer*.dart`: selects browser or local implementation without importing Web APIs on unsupported targets.
- `lib/features/practice_assessment/application/speech_formula_controller.dart`: maps typed recognition failures and does not recursively stop after a local final result.
- `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`: accepts the configured recognizer through composition.
- `lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart`: displays the active recognition source.
- `lib/app_config.dart` and `lib/developer_tools.dart`: define and consume local ASR compile-time configuration.
- `pubspec.yaml` and `pubspec.lock`: pin `record: 7.1.1` and its resolved graph.

Tests mirror each production responsibility under `test/features/practice_assessment/`.

---

### Task 1: D-drive runtime path guard and setup script

**Files:**
- Create: `tool/sensevoice/SenseVoicePaths.psm1`
- Create: `tool/sensevoice/setup.ps1`
- Create: `tool/sensevoice/tests/paths.test.ps1`
- Create: `tool/sensevoice/requirements.in`
- Create: `tool/sensevoice/README.md`

**Interfaces:**
- Produces: `Get-SenseVoicePaths([string] $Root)` returning `Root`, `Runtime`, `Venv`, `Models`, `PipCache`, `ModelScopeCache`, `HuggingFaceCache`, `TorchCache`, `Temp`, and `Benchmarks` absolute paths.
- Produces: `Set-SenseVoiceProcessEnvironment($Paths)` setting only process-scoped cache/temp variables.
- Produces: `setup.ps1 -Root D:\dev\local-ai\sensevoice -PythonLauncher py`.

- [ ] **Step 1: Write the failing path-safety test**

Create `tool/sensevoice/tests/paths.test.ps1` with dependency-free assertions:

```powershell
$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\SenseVoicePaths.psm1'
Import-Module $module -Force

$paths = Get-SenseVoicePaths -Root 'D:\dev\local-ai\sensevoice'
if ($paths.Root -ne 'D:\dev\local-ai\sensevoice') { throw 'Root mismatch' }
foreach ($property in @(
  'Runtime', 'Venv', 'Models', 'PipCache', 'ModelScopeCache',
  'HuggingFaceCache', 'TorchCache', 'Temp', 'Benchmarks'
)) {
  $value = [string]$paths.$property
  if (-not $value.StartsWith($paths.Root, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$property escaped the D-drive root: $value"
  }
}

try {
  Get-SenseVoicePaths -Root 'C:\sensevoice' | Out-Null
  throw 'C-drive root should have been rejected'
} catch {
  if ($_.Exception.Message -eq 'C-drive root should have been rejected') { throw }
}

Set-SenseVoiceProcessEnvironment -Paths $paths
if ($env:PIP_CACHE_DIR -ne $paths.PipCache) { throw 'PIP cache mismatch' }
if ($env:MODELSCOPE_CACHE -ne $paths.ModelScopeCache) { throw 'ModelScope cache mismatch' }
if ($env:HF_HOME -ne $paths.HuggingFaceCache) { throw 'HF cache mismatch' }
if ($env:TORCH_HOME -ne $paths.TorchCache) { throw 'Torch cache mismatch' }
if ($env:TEMP -ne $paths.Temp -or $env:TMP -ne $paths.Temp) {
  throw 'Temporary directory mismatch'
}
```

- [ ] **Step 2: Run the path test and verify RED**

Run:

```powershell
pwsh -NoProfile -File tool/sensevoice/tests/paths.test.ps1
```

Expected: FAIL because `SenseVoicePaths.psm1` does not exist.

- [ ] **Step 3: Implement the D-drive path module**

Create `SenseVoicePaths.psm1` with these exact invariants:

```powershell
Set-StrictMode -Version Latest

function Get-SenseVoicePaths {
  [CmdletBinding()]
  param([string] $Root = 'D:\dev\local-ai\sensevoice')

  $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  if (-not $resolvedRoot.StartsWith('D:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "SenseVoice root must stay on D drive: $resolvedRoot"
  }
  [pscustomobject]@{
    Root = $resolvedRoot
    Runtime = Join-Path $resolvedRoot 'runtime'
    Venv = Join-Path $resolvedRoot 'venv'
    Models = Join-Path $resolvedRoot 'models'
    PipCache = Join-Path $resolvedRoot 'cache\pip'
    ModelScopeCache = Join-Path $resolvedRoot 'cache\modelscope'
    HuggingFaceCache = Join-Path $resolvedRoot 'cache\huggingface'
    TorchCache = Join-Path $resolvedRoot 'cache\torch'
    Temp = Join-Path $resolvedRoot 'tmp'
    Benchmarks = Join-Path $resolvedRoot 'benchmarks'
  }
}

function Set-SenseVoiceProcessEnvironment {
  [CmdletBinding()]
  param([Parameter(Mandatory)] $Paths)
  $env:PIP_CACHE_DIR = $Paths.PipCache
  $env:MODELSCOPE_CACHE = $Paths.ModelScopeCache
  $env:HF_HOME = $Paths.HuggingFaceCache
  $env:TORCH_HOME = $Paths.TorchCache
  $env:TEMP = $Paths.Temp
  $env:TMP = $Paths.Temp
  $env:PYTHONPYCACHEPREFIX = Join-Path $Paths.Temp 'pycache'
}

Export-ModuleMember -Function Get-SenseVoicePaths, Set-SenseVoiceProcessEnvironment
```

- [ ] **Step 4: Run the path test and verify GREEN**

Run: `pwsh -NoProfile -File tool/sensevoice/tests/paths.test.ps1`

Expected: exit code 0 and no output.

- [ ] **Step 5: Add pinned runtime requirements and guarded setup**

Create `requirements.in`:

```text
funasr==1.3.29
fastapi
uvicorn
python-multipart
```

Create `setup.ps1` so it:

1. imports `SenseVoicePaths.psm1`;
2. records `Get-PSDrive C,D` free bytes before installation;
3. creates every resolved directory with `New-Item -ItemType Directory -Force`;
4. sets the process-local cache variables;
5. creates `D:\dev\local-ai\sensevoice\venv` with `py -3.11 -m venv`;
6. upgrades pip in that virtual environment;
7. installs CPU-only `torch` and `torchaudio` from `https://download.pytorch.org/whl/cpu`;
8. installs `-r tool/sensevoice/requirements.in`;
9. runs `python -c "import torch, funasr; print(torch.__version__); print(funasr.__version__)"`;
10. writes `pip freeze` to `D:\dev\local-ai\sensevoice\runtime\requirements.lock.txt`;
11. records C/D free bytes again and fails if C lost more than 1GB.

Use `& $python` argument arrays rather than `Invoke-Expression`. The script must stop on the first non-zero external process exit code and print the exact external D-drive paths it created.

- [ ] **Step 6: Document setup and commit Task 1**

In `tool/sensevoice/README.md`, document only these commands:

```powershell
pwsh -NoProfile -File tool/sensevoice/setup.ps1
pwsh -NoProfile -File tool/sensevoice/start.ps1
pwsh -NoProfile -File tool/sensevoice/benchmark.ps1
```

State that weights, caches, audio, and generated results are outside Git under `D:\dev\local-ai\sensevoice`.

Commit:

```powershell
git add tool/sensevoice/SenseVoicePaths.psm1 tool/sensevoice/setup.ps1 tool/sensevoice/tests/paths.test.ps1 tool/sensevoice/requirements.in tool/sensevoice/README.md
git commit -m "build(speech): guard SenseVoice assets on D drive"
```

---

### Task 2: Persistent local service and repeatable benchmark harness

**Files:**
- Create: `tool/sensevoice/start.ps1`
- Create: `tool/sensevoice/benchmark.ps1`
- Create: `tool/sensevoice/benchmark-cases.json`
- Create: `docs/operations/SENSEVOICE_LOCAL_RUNBOOK.md`

**Interfaces:**
- Consumes: path module and D-drive virtual environment from Task 1.
- Produces: health endpoint `GET http://127.0.0.1:8000/health`.
- Produces: transcription endpoint `POST http://127.0.0.1:8000/v1/audio/transcriptions` with multipart fields `file`, `model=sensevoice`, and `response_format=json`.
- Produces: benchmark JSON containing `caseId`, `audioSeconds`, `elapsedMs`, `rtf`, `text`, `runtime`, `device`, and timestamp.

- [ ] **Step 1: Add a start-script static safety test**

Append to `tool/sensevoice/tests/paths.test.ps1`:

```powershell
$startScript = Get-Content -Raw (Join-Path $PSScriptRoot '..\start.ps1')
if ($startScript -notmatch "--host',\s*'127\.0\.0\.1'") {
  throw 'SenseVoice must bind to loopback only'
}
if ($startScript -match "--host',\s*'0\.0\.0\.0'") {
  throw 'Public bind is forbidden for local development'
}
if ($startScript -notmatch "--device',\s*'cpu'") {
  throw 'The primary laptop runtime must use CPU'
}
```

- [ ] **Step 2: Run the safety test and verify RED**

Run: `pwsh -NoProfile -File tool/sensevoice/tests/paths.test.ps1`

Expected: FAIL because `start.ps1` does not exist.

- [ ] **Step 3: Implement the persistent service launcher**

Create `start.ps1` with parameters `Root`, `Port=8000`, and `CorsOrigin='http://localhost:5174'`. Resolve `$python` to `venv\Scripts\python.exe`, set D-drive environment variables, and launch:

```powershell
$arguments = @(
  '-m', 'funasr.bin.server',
  '--host', '127.0.0.1',
  '--port', [string]$Port,
  '--device', 'cpu',
  '--model', 'sensevoice',
  '--cors-origin', $CorsOrigin
)
& $python @arguments
if ($LASTEXITCODE -ne 0) { throw "SenseVoice server exited with $LASTEXITCODE" }
```

Before launch, reject a missing virtual-environment interpreter and print the health URL. Do not use `Start-Process`; the foreground process makes shutdown explicit with Ctrl+C.

- [ ] **Step 4: Implement the benchmark manifest and runner**

Create `benchmark-cases.json`:

```json
{
  "version": 1,
  "cases": [
    {"id":"polynomial","file":"01-polynomial.wav","expected":"x的平方减三x加二"},
    {"id":"fraction","file":"02-fraction.wav","expected":"根号下x加一整体除以x减一"},
    {"id":"relation","file":"03-relation.wav","expected":"零小于x并且x小于等于一"},
    {"id":"ambiguity","file":"04-ambiguity.wav","expected":"负二的平方"},
    {"id":"function","file":"05-function.wav","expected":"正弦x加余弦x"}
  ]
}
```

`benchmark.ps1` must:

- accept `-AudioDirectory` defaulting to `D:\dev\local-ai\sensevoice\benchmarks\audio`;
- fail with a list of missing case files before sending any request;
- call `/health` once;
- warm up with the first audio once and exclude that call from statistics;
- send every case three times with `Invoke-RestMethod -Form`;
- obtain WAV duration from the PCM WAV header instead of using wall-clock recording duration;
- compute `rtf = elapsedSeconds / audioSeconds`;
- write raw JSON to `D:\dev\local-ai\sensevoice\benchmarks\results\<UTC timestamp>.json`;
- print median and P95 elapsed time and RTF;
- never delete or overwrite an audio fixture.

- [ ] **Step 5: Re-run static tests and perform the real CPU smoke test**

Run:

```powershell
pwsh -NoProfile -File tool/sensevoice/tests/paths.test.ps1
pwsh -NoProfile -File tool/sensevoice/setup.ps1
pwsh -NoProfile -File tool/sensevoice/start.ps1
```

From a second terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected: path tests pass, the service reports healthy after one model load, and Task Manager shows CPU inference with no CUDA device.

- [ ] **Step 6: Add the runbook and commit Task 2**

Document startup, Ctrl+C shutdown, health check, the five exact recording phrases, benchmark command, C/D free-space check, and recovery for port conflict/model download failure in `docs/operations/SENSEVOICE_LOCAL_RUNBOOK.md`.

Commit:

```powershell
git add tool/sensevoice/start.ps1 tool/sensevoice/benchmark.ps1 tool/sensevoice/benchmark-cases.json tool/sensevoice/tests/paths.test.ps1 docs/operations/SENSEVOICE_LOCAL_RUNBOOK.md
git commit -m "feat(speech): run and benchmark local SenseVoice"
```

---

### Task 3: PCM capture port and deterministic WAV encoding

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/features/practice_assessment/core/speech_audio_capture.dart`
- Create: `lib/features/practice_assessment/adapters/record_speech_audio_capture.dart`
- Create: `lib/features/practice_assessment/adapters/pcm_wav_encoder.dart`
- Create: `test/features/practice_assessment/pcm_wav_encoder_test.dart`
- Create: `test/features/practice_assessment/record_speech_audio_capture_test.dart`

**Interfaces:**
- Produces: `SpeechAudioCapture.requestPermission()`, `start()`, `stop()`, and `cancel()`.
- Produces: `Uint8List encodePcm16MonoWav(Uint8List pcm, {int sampleRate = 16000})`.
- Produces: `RecordSpeechAudioCapture` configured as PCM16, 16kHz, one channel.

- [ ] **Step 1: Add `record` and write the failing WAV test**

Add `record: 7.1.1` to dependencies and run `flutter pub get`.

Create `pcm_wav_encoder_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/pcm_wav_encoder.dart';

void main() {
  test('PCM16 单声道被编码为 16kHz WAV', () {
    final wav = encodePcm16MonoWav(Uint8List.fromList(<int>[0, 0, 1, 0]));
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 16000);
    expect(ByteData.sublistView(wav).getUint16(22, Endian.little), 1);
    expect(ByteData.sublistView(wav).getUint16(34, Endian.little), 16);
    expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 4);
    expect(wav.sublist(44), <int>[0, 0, 1, 0]);
  });

  test('奇数字节 PCM 被拒绝', () {
    expect(
      () => encodePcm16MonoWav(Uint8List.fromList(<int>[0])),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run the WAV test and verify RED**

Run: `flutter test test/features/practice_assessment/pcm_wav_encoder_test.dart`

Expected: FAIL because `pcm_wav_encoder.dart` does not exist.

- [ ] **Step 3: Implement the WAV encoder and capture port**

The encoder writes a fixed 44-byte RIFF/WAVE header using little-endian values:

```dart
Uint8List encodePcm16MonoWav(
  Uint8List pcm, {
  int sampleRate = 16000,
}) {
  if (pcm.length.isOdd) throw ArgumentError.value(pcm.length, 'pcm.length');
  const channels = 1;
  const bitsPerSample = 16;
  final output = Uint8List(44 + pcm.length);
  final data = ByteData.sublistView(output);
  void ascii(int offset, String value) =>
      output.setRange(offset, offset + value.length, value.codeUnits);
  ascii(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
  data.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, pcm.length, Endian.little);
  output.setRange(44, output.length, pcm);
  return output;
}
```

Define the capture port:

```dart
abstract interface class SpeechAudioCapture {
  Future<bool> requestPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> cancel();
}
```

`RecordSpeechAudioCapture.start()` delegates to `AudioRecorder.startStream` with:

```dart
const RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  autoGain: true,
  echoCancel: true,
  noiseSuppress: true,
)
```

It checks `isEncoderSupported(AudioEncoder.pcm16bits)` and throws a typed `StateError` before recording when PCM streaming is unavailable.

- [ ] **Step 4: Test the adapter through an injected recorder port**

Do not mock `AudioRecorder` directly. Add a public, test-oriented `SpeechRecordDriver` interface to `record_speech_audio_capture.dart` with the five plugin calls used by the adapter and a production private `_PluginRecordDriver`. Expose `RecordSpeechAudioCapture({SpeechRecordDriver? driver})` so the test can inject a fake without accessing a Dart-private type. Inject that fake in `record_speech_audio_capture_test.dart` and assert:

- permission denial returns `false` without starting;
- PCM unsupported throws before `startStream`;
- the exact `RecordConfig` has `pcm16bits`, 16000, and one channel;
- `cancel()` calls plugin cancellation and does not call stop.

Run:

```powershell
flutter test test/features/practice_assessment/pcm_wav_encoder_test.dart test/features/practice_assessment/record_speech_audio_capture_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 3**

```powershell
git add pubspec.yaml pubspec.lock lib/features/practice_assessment/core/speech_audio_capture.dart lib/features/practice_assessment/adapters/record_speech_audio_capture.dart lib/features/practice_assessment/adapters/pcm_wav_encoder.dart test/features/practice_assessment/pcm_wav_encoder_test.dart test/features/practice_assessment/record_speech_audio_capture_test.dart
git commit -m "feat(practice): capture local formula audio as wav"
```

---

### Task 4: Typed SenseVoice HTTP client

**Files:**
- Create: `lib/features/practice_assessment/adapters/sensevoice_asr_client.dart`
- Create: `test/features/practice_assessment/sensevoice_asr_client_test.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

**Interfaces:**
- Produces: `SenseVoiceAsrClient({required String baseUrl, http.Client? client, Duration timeout = const Duration(seconds: 15)})`.
- Produces: `Future<bool> isHealthy()`.
- Produces: `Future<String> transcribe(Uint8List wavBytes)`.
- Produces: `SenseVoiceAsrException.message` for safe UI mapping.

- [ ] **Step 1: Write failing client tests**

Add the direct MIME dependency `http_parser: 4.1.2` to `pubspec.yaml` and run `flutter pub get` before importing `MediaType`.

Use `MockClient` and cover exact protocol behavior:

```dart
test('健康检查只接受 2xx', () async {
  final client = SenseVoiceAsrClient(
    baseUrl: 'http://127.0.0.1:8000',
    client: MockClient((request) async => http.Response('{"status":"ok"}', 200)),
  );
  expect(await client.isHealthy(), isTrue);
});

test('转写上传 WAV 并返回清洗后的 text', () async {
  final client = SenseVoiceAsrClient(
    baseUrl: 'http://127.0.0.1:8000/',
    client: MockClient.streaming((request, bodyStream) async {
      expect(request.url.path, '/v1/audio/transcriptions');
      expect(request.method, 'POST');
      final body = await bodyStream.bytesToString();
      expect(body, contains('name="model"'));
      expect(body, contains('sensevoice'));
      expect(body, contains('filename="formula.wav"'));
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"text":"  x 的平方  "}')),
        200,
      );
    }),
  );
  expect(await client.transcribe(Uint8List(44)), 'x 的平方');
});
```

Also assert that payloads over 5MB are rejected before sending, non-2xx responses do not expose server bodies, invalid JSON is rejected, blank text is rejected, and timeout maps to `SenseVoiceAsrException('本机语音识别超时，请重新说一次。')`.

- [ ] **Step 2: Run client tests and verify RED**

Run: `flutter test test/features/practice_assessment/sensevoice_asr_client_test.dart`

Expected: FAIL because the client does not exist.

- [ ] **Step 3: Implement health and multipart transcription**

Normalize the base URL by trimming one trailing slash. `isHealthy` calls `/health` with a 2-second timeout. `transcribe` creates `http.MultipartRequest`, adds:

```dart
fields['model'] = 'sensevoice';
fields['response_format'] = 'json';
files.add(http.MultipartFile.fromBytes(
  'file',
  wavBytes,
  filename: 'formula.wav',
  contentType: MediaType('audio', 'wav'),
));
```

Send through the injected client, cap the response body at 64KB while reading, decode JSON, and accept only a non-empty string `text`. Never include the response body or endpoint in the public exception message.

- [ ] **Step 4: Run tests and commit Task 4**

Run:

```powershell
flutter test test/features/practice_assessment/sensevoice_asr_client_test.dart
dart analyze lib/features/practice_assessment/adapters/sensevoice_asr_client.dart test/features/practice_assessment/sensevoice_asr_client_test.dart
```

Expected: tests and analysis pass.

Commit:

```powershell
git add pubspec.yaml pubspec.lock lib/features/practice_assessment/adapters/sensevoice_asr_client.dart test/features/practice_assessment/sensevoice_asr_client_test.dart
git commit -m "feat(practice): call local SenseVoice transcription API"
```

---

### Task 5: Local recognizer state machine and controller integration

**Files:**
- Modify: `lib/features/practice_assessment/core/spoken_formula.dart`
- Create: `lib/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart`
- Modify: `lib/features/practice_assessment/application/speech_formula_controller.dart`
- Create: `test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart`
- Modify: `test/features/practice_assessment/speech_formula_controller_test.dart`
- Modify: all test fakes implementing `SpeechFormulaRecognizer` found by `rg -l "implements SpeechFormulaRecognizer" test lib`

**Interfaces:**
- Adds: `typedef SpeechFormulaErrorCallback = void Function(SpokenFormulaRecognitionException error)`.
- Changes: `listen({required SpeechFormulaResultCallback onResult, SpeechFormulaErrorCallback? onError})`.
- Produces: `LocalSenseVoiceSpeechFormulaRecognizer(capture, client, maxDuration: 15 seconds)`.

- [ ] **Step 1: Write failing local-recognizer tests**

With fake `SpeechAudioCapture` and fake ASR client, assert:

1. `initialize()` checks health and then microphone permission;
2. `listen()` starts a fresh PCM buffer;
3. `stop()` stops capture, concatenates chunks, creates WAV, transcribes once, and emits one final result;
4. duplicate `stop()` calls share one in-flight future and do not upload twice;
5. `cancel()` cancels recording, cancels the chunk subscription, and a late HTTP result cannot emit;
6. 15-second auto-stop emits a final transcript using `fake_async` or an injected timer factory;
7. empty PCM emits `SpokenFormulaRecognitionException('没有录到有效语音，请重新说一次。')`;
8. ASR failure emits the safe typed message without a final result.

The successful assertion is:

```dart
expect(results, <String>['x 的平方']);
expect(finalFlags, <bool>[true]);
expect(fakeClient.callCount, 1);
expect(fakeClient.lastBytes!.sublist(0, 4), 'RIFF'.codeUnits);
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```powershell
flutter test test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/speech_formula_controller_test.dart
```

Expected: FAIL because the local recognizer and error callback do not exist.

- [ ] **Step 3: Extend the recognition contract and implement local stop-once behavior**

Add to `spoken_formula.dart`:

```dart
typedef SpeechFormulaErrorCallback =
    void Function(SpokenFormulaRecognitionException error);

final class SpokenFormulaRecognitionException implements Exception {
  const SpokenFormulaRecognitionException(this.message);
  final String message;
  @override
  String toString() => message;
}
```

The local recognizer stores `_generation`, `_chunks`, `_subscription`, `_timer`, `_onResult`, `_onError`, and `_stopFuture`. `listen` increments generation and starts capture. `_stopInternal(generation)` may emit only when the generation is still current. `cancel` increments generation before cancelling resources so that HTTP completion cannot win a race.

For automatic stop, use an injected `Timer Function(Duration, void Function())` with production default `Timer.new`; invoke `unawaited(stop().catchError(_emitSafeError))` after 15 seconds.

- [ ] **Step 4: Remove recursive stop and map typed recognition errors in the controller**

Pass `onError` from `SpeechFormulaController.startListening`. The handler checks the operation ID and calls `_showError(error.message, currentTranscript)`.

Change `_finishFinalRecognition` to call `_convert` directly; it must no longer call `recognizer.stop()` because the local adapter emits its final result from inside `stop()`. Manual `stopListening()` awaits `recognizer.stop()` and then only reports “没有识别到语音” if the state is still `listening` and no final callback was emitted.

Update browser adapter and every fake to accept the optional named `onError`. The browser adapter tracks its last partial words and, if `speech_to_text.stop()` ends without a final callback, emits the last non-empty text once as final.

- [ ] **Step 5: Run controller/recognizer tests and commit Task 5**

Run:

```powershell
flutter test test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/math_answer_field_test.dart
dart analyze lib/features/practice_assessment test/features/practice_assessment
```

Expected: all named tests pass; analysis reports no new issues.

Commit all files returned by the exact recognizer-implementation search plus the new local recognizer:

```powershell
git add lib/features/practice_assessment test/features/practice_assessment
git commit -m "feat(practice): recognize formula audio with local SenseVoice"
```

Before committing, verify `git diff --cached --name-only` contains only practice-assessment files from this task.

---

### Task 6: Compile-time selection, composition, and visible source label

**Files:**
- Modify: `lib/app_config.dart`
- Modify: `lib/developer_tools.dart`
- Modify: `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer.dart`
- Modify: `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart`
- Modify: `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_stub.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`
- Modify: `lib/features/practice_assessment/application/speech_formula_controller.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart`
- Modify: `test/features/practice_assessment/platform_speech_formula_recognizer_test.dart`
- Modify: `test/features/practice_assessment/practice_spoken_formula_composition_test.dart`
- Modify: `test/features/practice_assessment/practice_formula_voice_panel_test.dart`

**Interfaces:**
- Adds compile-time `SPOKEN_FORMULA_ASR_MODE=browser|sensevoiceLocal`.
- Adds compile-time `SENSEVOICE_BASE_URL`, default `http://127.0.0.1:8000` only in development.
- Changes factory to `createPlatformSpeechFormulaRecognizer({required String mode, required String senseVoiceBaseUrl})`.
- Adds `SpeechFormulaController.sourceLabel`, default `浏览器语音`.

- [ ] **Step 1: Write failing configuration and composition tests**

Add tests asserting:

- mode `browser` returns `WebSpeechFormulaRecognizer` on Web;
- mode `sensevoiceLocal` returns `LocalSenseVoiceSpeechFormulaRecognizer` on Web;
- an unknown mode throws `ArgumentError` instead of silently choosing cloud/browser behavior;
- `PracticeAssessmentLabPage.mock` accepts an injected recognizer and preserves identity;
- the idle voice panel displays `识别方式：本机 SenseVoice` when the controller label is set.

- [ ] **Step 2: Run tests and verify RED**

Run the factory test on Chrome so the Web conditional export is active; run the composition/widget tests on the regular Flutter test VM:

```powershell
flutter test --platform chrome test/features/practice_assessment/platform_speech_formula_recognizer_test.dart
flutter test test/features/practice_assessment/practice_spoken_formula_composition_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart
```

Expected: FAIL because mode selection and the source label do not exist.

- [ ] **Step 3: Implement explicit development configuration**

Add to `AppConfig`:

```dart
static const spokenFormulaAsrMode = String.fromEnvironment(
  'SPOKEN_FORMULA_ASR_MODE',
  defaultValue: 'browser',
);
static const senseVoiceBaseUrl = String.fromEnvironment(
  'SENSEVOICE_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
```

`developer_tools.dart` constructs the recognizer once through the platform factory and injects it into the lab page. `PracticeAssessmentLabPage.mock` and `.remote` accept an optional `SpeechFormulaRecognizer`; when absent they retain the browser default for backwards compatibility.

In the local branch, construct `RecordSpeechAudioCapture`, `SenseVoiceAsrClient`, and `LocalSenseVoiceSpeechFormulaRecognizer`. Set controller label to `本机 SenseVoice`; browser mode uses `浏览器语音`.

The panel idle state renders a small secondary `Text('识别方式：${controller.sourceLabel}')` beside or below the start button without changing the button key.

- [ ] **Step 4: Run focused and full practice voice tests**

Run:

```powershell
flutter test --platform chrome test/features/practice_assessment/platform_speech_formula_recognizer_test.dart
flutter test test/features/practice_assessment/practice_spoken_formula_composition_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/math_answer_field_test.dart
```

Expected: all tests pass and the 375px layout test remains free of overflow.

- [ ] **Step 5: Commit Task 6**

```powershell
git add lib/app_config.dart lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment
git commit -m "feat(practice): select local SenseVoice in web lab"
```

Verify staged files contain no unrelated dialogue-exploration changes before committing.

---

### Task 7: Real-device benchmark, Web build, and acceptance page

**Files:**
- Modify: `docs/operations/SENSEVOICE_LOCAL_RUNBOOK.md`
- Create: `docs/operations/SENSEVOICE_LOCAL_BENCHMARK_2026-08-25.md`

**Interfaces:**
- Consumes: local service from Tasks 1–2 and Flutter integration from Tasks 3–6.
- Produces: evidence-backed selected runtime and a locally testable route `http://localhost:5174/#/practice-assessment-lab`.

- [ ] **Step 1: Run complete static verification**

Run:

```powershell
pwsh -NoProfile -File tool/sensevoice/tests/paths.test.ps1
flutter test --platform chrome test/features/practice_assessment/platform_speech_formula_recognizer_test.dart
flutter test test/features/practice_assessment/pcm_wav_encoder_test.dart test/features/practice_assessment/record_speech_audio_capture_test.dart test/features/practice_assessment/sensevoice_asr_client_test.dart test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/math_answer_field_test.dart
dart analyze lib/features/practice_assessment test/features/practice_assessment
```

Expected: all selected tests pass; analysis has no new errors.

- [ ] **Step 2: Build the exact Web configuration**

Run:

```powershell
flutter build web --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=PRACTICE_ASSESSMENT_REMOTE=false --dart-define=PRACTICE_SPOKEN_FORMULA_REMOTE=true --dart-define=SPOKEN_FORMULA_ASR_MODE=sensevoiceLocal --dart-define=SENSEVOICE_BASE_URL=http://127.0.0.1:8000
```

Expected: build exits 0 and the bundle contains both the local ASR endpoint and `/practice-assessment-lab`.

- [ ] **Step 3: Measure disk, model startup, warm CPU, and optional Vulkan**

Record C/D free space before and after. Run the five-case manifest three times on the persistent CPU service. Separately download the official Windows GGUF Q8 CPU and Vulkan portable runtime under `D:\dev\local-ai\sensevoice\runtime\gguf`, run the same WAV files through the binary, and include process startup in the end-to-end GGUF timing.

Choose Vulkan only if all five conditions hold:

1. every formula audio completes without a driver/device error;
2. transcript accuracy is not lower than persistent CPU;
3. P95 end-to-end latency is lower than persistent CPU;
4. peak memory remains below 4GB;
5. three consecutive runs produce stable results.

Otherwise select persistent CPU and record the exact failed condition.

- [ ] **Step 4: Perform the ten-utterance human page check**

Start the backend on port 3000, SenseVoice on port 8000, and Flutter Web on port 5174. Open:

```text
http://localhost:5174/#/practice-assessment-lab
```

Speak these ten phrases once each:

1. `x 的平方减三 x 加二`
2. `二 x 加一`
3. `负二的平方`
4. `根号下 x 加一`
5. `x 加一整体除以 x 减一`
6. `零小于 x 并且 x 小于等于一`
7. `正弦 x 加余弦 x`
8. `以二为底 x 的对数`
9. `x 下标一加 x 下标二`
10. `x 属于从零到一的闭区间`

For each case record transcript, final formula, ASR time, total time, and whether manual correction was needed. Confirm that no formula enters the answer before the user presses `插入公式`.

- [ ] **Step 5: Write the benchmark report**

`SENSEVOICE_LOCAL_BENCHMARK_2026-08-25.md` must contain:

- hardware and Windows version;
- runtime/model revisions and D-drive paths;
- cold startup time;
- CPU and Vulkan P50/P95/RTF and peak memory;
- the ten transcript/formula outcomes;
- C/D free-space delta;
- selected main runtime with the measured reason;
- failed cases and reproducible wording;
- whether the design gates `RTF <= 0.5`, transcript P95 <=2s, preview P95 <=2.5s, memory <=4GB, and formula exact match >=90% passed.

- [ ] **Step 6: Final diff verification and commit Task 7**

Run:

```powershell
git diff --check
git status --short
git log --oneline --decorate -7
```

Confirm weights, `.venv`, WAV files, caches, and raw benchmark JSON are not tracked.

Commit:

```powershell
git add docs/operations/SENSEVOICE_LOCAL_RUNBOOK.md docs/operations/SENSEVOICE_LOCAL_BENCHMARK_2026-08-25.md
git commit -m "docs(speech): record local SenseVoice acceptance"
```

The task is complete only when the page is left running for user testing or exact startup commands are handed off if the user asks to stop the processes.

# Local Math AST Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed spoken-formula demo mapping with a genuine fully local flow: real microphone → SenseVoice → local Qwen → validated Math AST V1 → deterministic LaTeX → user-confirmed answer insertion.

**Architecture:** Flutter keeps mock questions but always calls the shared backend for formula semantics. The backend selects a formula-specific `local` provider, sends only the final transcript to a loopback llama.cpp server running Qwen3-1.7B Q4_K_M, validates its JSON against Math AST V1, then renders safe LaTeX. A 30-case benchmark is a hard gate: no Web integration or “completed” claim is allowed unless the measured local route meets all accuracy and latency thresholds.

**Tech Stack:** Flutter 3 / Dart 3.12, Next.js 16 / TypeScript / Vitest, Windows PowerShell 7, llama.cpp `b10516` CPU x64, Qwen3-1.7B Q4_K_M GGUF, existing SenseVoice service.

**Spec:** `docs/superpowers/specs/2026-08-26-local-math-ast-model-design.md`

## Global Constraints

- Read and follow `docs/DEVELOPMENT_CODE_STANDARD.md` before every implementation task.
- Flutter work happens in `D:\dev\Uniprism\uniprism_app\.worktrees\local-sensevoice-web-integration` on `feature/local-sensevoice-web-integration`.
- Backend work starts in `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend` on `feature/spoken-formula-math-ast-backend`; verified commits are then integrated into `feature/dialogue-exploration-1-2-backend`.
- Preserve unrelated dirty files. Stage only the paths listed in each task and inspect `git diff --cached --name-only` before every commit.
- Put binaries, models, caches, logs, temporary files, PIDs and generated benchmark results under `D:\dev\local-ai\math-ast`; reject C-drive runtime roots.
- llama.cpp must bind only to `127.0.0.1:8081`; Flutter must never call port 8081 directly.
- Runtime conversion must not use phrase-to-formula tables, exact-match demos, regular-expression answer maps or unvalidated model-authored LaTeX.
- Do not log audio, transcript text, complete model output or complete AST. Log only stage, duration, provider and fixed reason code.
- Do not expose MiniMax credentials to Flutter. `PRACTICE_FORMULA_MODEL_PROVIDER=local` must not read or call MiniMax configuration.
- Keep preview and explicit user confirmation before formula insertion.
- The benchmark gate is mandatory: AST parseability 100%, semantic correctness at least 90%, median conversion at most 6,000 ms and P95 at most 12,000 ms.
- If Qwen3-1.7B fails the gate, stop before Task 7. Only when speed passes but accuracy fails may a separately approved Qwen3.5-2B comparison be downloaded.

---

### Task 1: Preserve and commit the verified browser PCM normalization fix

**Repository:** Flutter worktree

**Files:**
- Modify: `lib/features/practice_assessment/adapters/record_speech_audio_capture.dart`
- Modify: `test/features/practice_assessment/record_speech_audio_capture_test.dart`

**Why first:** Chrome may deliver 48 kHz or multi-channel PCM even when 16 kHz mono is requested. SenseVoice receives valid audio only after deterministic downmix and resampling; these already-present uncommitted changes must not be mixed with the local model work.

- [ ] **Step 1: Inspect the existing focused diff**

Run:

```powershell
git diff -- lib/features/practice_assessment/adapters/record_speech_audio_capture.dart test/features/practice_assessment/record_speech_audio_capture_test.dart
```

Confirm the production adapter normalizes actual stream format to 16 kHz mono PCM16 and the tests cover 48 kHz and multi-channel inputs. Do not rewrite the change unless the assertions reveal a defect.

- [ ] **Step 2: Re-run the focused regression tests**

Run:

```powershell
flutter test test/features/practice_assessment/record_speech_audio_capture_test.dart test/features/practice_assessment/pcm_wav_encoder_test.dart test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart
dart analyze lib/features/practice_assessment/adapters/record_speech_audio_capture.dart test/features/practice_assessment/record_speech_audio_capture_test.dart
```

Expected: all tests pass and analysis reports no issue.

- [ ] **Step 3: Commit only the capture fix**

```powershell
git add lib/features/practice_assessment/adapters/record_speech_audio_capture.dart test/features/practice_assessment/record_speech_audio_capture_test.dart
git diff --cached --name-only
git commit -m "fix(practice): normalize browser formula audio"
```

---

### Task 2: Add D-drive llama.cpp runtime guards and lifecycle scripts

**Repository:** Flutter worktree

**Files:**
- Create: `tool/math_ast/MathAstPaths.psm1`
- Create: `tool/math_ast/MathAstService.psm1`
- Create: `tool/math_ast/setup.ps1`
- Create: `tool/math_ast/start.ps1`
- Create: `tool/math_ast/stop.ps1`
- Create: `tool/math_ast/tests/paths.test.ps1`
- Create: `tool/math_ast/tests/service.test.ps1`
- Create: `tool/math_ast/README.md`

**Pinned artifacts:**

```text
llama.cpp release: b10516
asset: llama-b10516-bin-win-cpu-x64.zip
SHA256: fbbbc55e0eb2e1b07f9dcb9488616c98ed47d9003b90e15e7c8c7812c4307cd3

model repository: ggml-org/Qwen3-1.7B-GGUF
file: Qwen3-1.7B-Q4_K_M.gguf
SHA256: d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5
```

**Interfaces:**
- `Get-MathAstPaths([string] $Root)` returns absolute `Root`, `Bin`, `Models`, `Cache`, `Logs`, `Runtime`, `Temp`, `Benchmarks`, `ServerExe`, `ModelFile`, `PidFile` and `LogFile`.
- `Assert-MathAstLoopbackUrl([string] $BaseUrl)` accepts only HTTP URLs whose host is `127.0.0.1` or `localhost`.
- `Start-MathAstService` starts one hidden persistent `llama-server.exe` and waits for `/health`.
- `Stop-MathAstService` stops only the PID recorded under the validated runtime root after checking its executable path.

- [ ] **Step 1: Write failing path and static safety tests**

Create `tool/math_ast/tests/paths.test.ps1` with assertions equivalent to:

```powershell
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\MathAstPaths.psm1') -Force

$paths = Get-MathAstPaths -Root 'D:\dev\local-ai\math-ast'
foreach ($name in 'Bin','Models','Cache','Logs','Runtime','Temp','Benchmarks') {
  if (-not ([string]$paths.$name).StartsWith($paths.Root, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$name escaped the D-drive root"
  }
}
if ($paths.ServerExe -ne 'D:\dev\local-ai\math-ast\bin\llama-server.exe') { throw 'server path mismatch' }
if ($paths.ModelFile -ne 'D:\dev\local-ai\math-ast\models\Qwen3-1.7B-Q4_K_M.gguf') { throw 'model path mismatch' }

try { Get-MathAstPaths -Root 'C:\math-ast' | Out-Null; throw 'C drive accepted' }
catch { if ($_.Exception.Message -eq 'C drive accepted') { throw } }

Assert-MathAstLoopbackUrl -BaseUrl 'http://127.0.0.1:8081'
foreach ($unsafe in 'http://0.0.0.0:8081','http://192.168.1.20:8081','https://example.com') {
  try { Assert-MathAstLoopbackUrl -BaseUrl $unsafe; throw "unsafe URL accepted: $unsafe" }
  catch { if ($_.Exception.Message -like 'unsafe URL accepted:*') { throw } }
}
```

Create `service.test.ps1` as a static test that requires `start.ps1` to pass `--host 127.0.0.1`, `--port 8081`, `--threads 8`, `--ctx-size 2048`, `--n-predict 512`, and `--no-webui`, and forbids `0.0.0.0` and `Invoke-Expression`.

- [ ] **Step 2: Run tests and verify RED**

```powershell
pwsh -NoProfile -File tool/math_ast/tests/paths.test.ps1
pwsh -NoProfile -File tool/math_ast/tests/service.test.ps1
```

Expected: fail because modules/scripts do not exist.

- [ ] **Step 3: Implement path guards and lifecycle boundaries**

`MathAstPaths.psm1` must resolve with `[IO.Path]::GetFullPath`, require the normalized root to start with `D:\`, and never mutate machine- or user-scoped environment variables.

`MathAstService.psm1` must:

1. reject missing or hash-mismatched binary/model files;
2. use `Start-Process -WindowStyle Hidden -PassThru` with an argument array;
3. redirect stdout/stderr to D-drive logs;
4. write only the numeric PID into `runtime\llama-server.pid`;
5. poll `http://127.0.0.1:8081/health` for at most 90 seconds;
6. on stop, resolve the PID, verify the process path equals `$paths.ServerExe`, then stop that exact process;
7. never kill by process name or port.

`start.ps1` uses these fixed inference parameters:

```text
--host 127.0.0.1 --port 8081 --threads 8 --ctx-size 2048
--n-predict 512 --batch-size 128 --ubatch-size 128 --no-webui
```

Do not pass `--jinja` or enable thinking implicitly; the request body will also send `chat_template_kwargs.enable_thinking=false`.

- [ ] **Step 4: Implement guarded setup**

`setup.ps1` must:

1. print C/D free bytes before and after;
2. create only the validated D-drive directories;
3. download pinned artifacts to `$paths.Temp` before moving them into place;
4. verify both SHA256 values before extraction/use;
5. expand the llama archive under a temporary D-drive directory and copy only the CPU runtime files into `$paths.Bin`;
6. set `HF_HOME`, `XDG_CACHE_HOME`, `TEMP` and `TMP` process-locally to D-drive paths;
7. fail if C loses more than 512 MB;
8. never commit or copy the model into the repository.

Use `Invoke-WebRequest -OutFile` with explicit HTTPS URLs and no embedded token. A failed hash must delete only the mismatched temporary file after validating it remains under `$paths.Temp`.

- [ ] **Step 5: Verify GREEN and commit tooling**

```powershell
pwsh -NoProfile -File tool/math_ast/tests/paths.test.ps1
pwsh -NoProfile -File tool/math_ast/tests/service.test.ps1
git diff --check
git add tool/math_ast
git diff --cached --name-only
git commit -m "build(formula): add guarded local qwen runtime"
```

Do not run the download yet; Task 6 performs external setup only after the code paths are reviewed.

---

### Task 3: Add a strict local llama.cpp client to the shared backend

**Repository:** Backend feature worktree

**Files:**
- Create: `lib/practice-formula/mathAstJsonSchema.ts`
- Create: `lib/practice-formula/localModelClient.ts`
- Create: `lib/practice-formula/modelProvider.ts`
- Modify: `lib/practice-formula/converter.ts`
- Create: `tests/unit/practiceFormulaLocalModelClient.test.ts`
- Create: `tests/unit/practiceFormulaModelProvider.test.ts`
- Modify: `tests/unit/practiceSpokenFormula.test.ts`
- Modify: `.env.example`

**Environment contract:**

```dotenv
PRACTICE_FORMULA_MODEL_PROVIDER=minimax
PRACTICE_FORMULA_LOCAL_BASE_URL=http://127.0.0.1:8081
PRACTICE_FORMULA_LOCAL_MODEL=Qwen3-1.7B-Q4_K_M.gguf
PRACTICE_FORMULA_LOCAL_TIMEOUT_MS=15000
```

These variables are formula-specific and must not change the AI-teacher provider.

**Interfaces:**

```ts
export type SpokenFormulaModelProvider = 'minimax' | 'local';

export type LocalFormulaModelConfig = {
  baseUrl: URL;
  model: string;
  timeoutMs: number;
};

export function createLocalSpokenFormulaModelCall(
  config: LocalFormulaModelConfig,
  fetchImpl?: typeof fetch,
): SpokenFormulaModelCall;

export function resolveSpokenFormulaModelCall(
  env?: NodeJS.ProcessEnv,
  dependencies?: { fetchImpl?: typeof fetch },
): SpokenFormulaModelCall;
```

- [ ] **Step 1: Write failing local client tests**

Use an injected `fetch` and assert:

1. URL is exactly `http://127.0.0.1:8081/v1/chat/completions`;
2. only system prompt and transcript/repair prompt are sent—no audio or answer history;
3. body uses `temperature: 0`, `max_tokens: 512`, `stream: false` and `chat_template_kwargs: { enable_thinking: false }`;
4. `response_format.type` is `json_schema`, `strict` is true and schema rejects extra fields;
5. the returned value is only `choices[0].message.content`;
6. non-2xx, timeout, empty content, malformed response and response over 16 KB map to fixed `SERVICE_UNAVAILABLE` or `LLM_INVALID_JSON` errors without leaking response bodies;
7. `0.0.0.0`, LAN and public URLs are rejected in local development mode.

Representative request assertion:

```ts
expect(body).toMatchObject({
  model: 'Qwen3-1.7B-Q4_K_M.gguf',
  temperature: 0,
  max_tokens: 512,
  stream: false,
  chat_template_kwargs: { enable_thinking: false },
  response_format: {
    type: 'json_schema',
    json_schema: { name: 'math_ast_v1', strict: true },
  },
});
expect(JSON.stringify(body)).not.toContain('audio');
```

- [ ] **Step 2: Write failing provider-selection tests**

Assert:

- `local` returns the local client without reading `ANTHROPIC_AUTH_TOKEN`;
- `minimax` keeps current behavior;
- blank/unknown provider produces a fixed configuration error instead of silently choosing Demo or cloud;
- injected `callModel` in `convertSpokenFormula` still overrides provider selection for unit tests.

Run:

```powershell
npm test -- --run tests/unit/practiceFormulaLocalModelClient.test.ts tests/unit/practiceFormulaModelProvider.test.ts tests/unit/practiceSpokenFormula.test.ts
```

Expected: RED because the new modules do not exist.

- [ ] **Step 3: Implement the recursive Math AST JSON Schema**

`mathAstJsonSchema.ts` must describe every existing Math AST V1 node from `mathAst.ts`, use a recursive `$defs.node`, set `additionalProperties: false` on every object, cap alternatives/warnings arrays, and constrain enums/numeric strings exactly as the Zod contract does.

Add a schema parity test that supplies one valid sample for every node type and known invalid samples (`raw`, extra `latex`, extra properties, invalid derivative order). The JSON Schema is a generation constraint only; the existing Zod and semantic validators remain authoritative.

- [ ] **Step 4: Implement the local client and provider factory**

Use global `fetch` plus `AbortSignal.timeout(config.timeoutMs)`. Read response text with a 16 KB cap before parsing the OpenAI-compatible envelope. Never log request/response content.

Move the current MiniMax function behind `modelProvider.ts` without changing its prompt, timeout or test injection behavior. Change only this line in `converter.ts` conceptually:

```ts
const callModel = options.callModel ?? resolveSpokenFormulaModelCall();
```

Update the converter documentation from “MiniMax” to “模型提供方” because AST generation is now provider-neutral.

- [ ] **Step 5: Run backend GREEN verification and commit**

```powershell
npm test -- --run tests/unit/practiceFormulaLocalModelClient.test.ts tests/unit/practiceFormulaModelProvider.test.ts tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
git diff --check
git add .env.example lib/practice-formula tests/unit/practiceFormulaLocalModelClient.test.ts tests/unit/practiceFormulaModelProvider.test.ts tests/unit/practiceSpokenFormula.test.ts
git diff --cached --name-only
git commit -m "feat(practice): convert spoken formulas with local qwen"
```

---

### Task 4: Build a truthful 30-case local semantic benchmark

**Repository:** Backend feature worktree

**Files:**
- Create: `lib/practice-formula/localBenchmark.ts`
- Create: `scripts/benchmark-local-spoken-formulas.ts`
- Create: `tests/fixtures/practice-spoken-formula-local-v1.json`
- Create: `tests/unit/practiceFormulaLocalBenchmark.test.ts`
- Modify: `package.json`

**Interfaces:**

```ts
export type LocalBenchmarkThresholds = {
  minParseRate: 1;
  minCorrectRate: 0.9;
  maxMedianMs: 6000;
  maxP95Ms: 12000;
};

export function summarizeLocalBenchmark(
  results: readonly LocalBenchmarkCaseResult[],
  thresholds: LocalBenchmarkThresholds,
): LocalBenchmarkSummary;
```

The script writes generated output only to `D:\dev\local-ai\math-ast\benchmarks`; the committed fixture is test input, never imported by runtime conversion code.

- [ ] **Step 1: Write failing aggregation tests**

Cover exact percentile calculation, warm-up exclusion, parse-rate failure, correctness failure, latency failure and non-zero process exit when any threshold fails. A correct formula may match one of a small explicitly declared set of semantically equivalent renderer outputs; matching remains benchmark-only.

- [ ] **Step 2: Add the versioned 30-case fixture**

Use these distinct free-form utterances and categories; record renderer-normalized expected LaTeX from existing AST tests, not hand-rendered UI markup:

```text
01 algebra       x 的平方减去三倍 x 再加二
02 algebra       先把 x 自乘，然后加上它的两倍，最后再加一
03 equation      二 x 加三等于七
04 inequality    x 大于负一并且小于等于三
05 fraction      x 加一这一整项除以 x 减一
06 root          根号里面是 x 的平方加一
07 power         二的 x 次方
08 absolute      x 减三的绝对值
09 function      f 括号 x 括号等于 x 平方
10 trigonometry  正弦 x 的平方加余弦 x 的平方
11 logarithm     以二为底 x 的对数
12 logarithm     x 的自然对数
13 set           x 属于实数集
14 set           一二三组成的集合
15 interval      从负一到三左开右闭
16 sequence      a 下标 n 等于二 n 加一
17 summation     从 k 等于一到 n 的 k 求和
18 product       从 i 等于一到 n 的 i 连乘
19 limit         x 趋近于零时正弦 x 除以 x 的极限
20 derivative    x 的三次方对 x 求导
21 derivative    函数 x 的三次方在 x 等于二处的导数
22 integral      x 平方关于 x 的不定积分
23 integral      从零到一的 x 平方定积分
24 combination   从 n 个里面选两个的组合数
25 arrangement   从 n 个里面取两个的排列数
26 vector        向量 a 加向量 b
27 geometry      直线 a 垂直于直线 b
28 piecewise     当 x 大于等于零时 f x 等于 x 平方，否则等于负 x
29 ambiguity     负二的平方
30 unsupported   请证明这个函数为什么是连续的
```

Each record contains `id`, `category`, `spokenText`, expected `status`, and expected renderer output(s). Case 30 is correct only when status is `unsupported` and no formula candidate is returned.

- [ ] **Step 3: Implement benchmark execution without privacy leaks**

The runner must:

1. require `PRACTICE_FORMULA_MODEL_PROVIDER=local`;
2. perform one unmeasured warm-up;
3. call `convertSpokenFormula` for all 30 cases sequentially;
4. record case ID, category, elapsed milliseconds, parse success, semantic success and fixed reason code;
5. omit `spokenText`, model raw output and AST from the generated report;
6. calculate median and nearest-rank P95;
7. write timestamped JSON under the validated D-drive benchmark directory;
8. print summary only and exit 1 when the gate fails.

Add the package script:

```json
"qa:local-spoken-formula": "tsx scripts/benchmark-local-spoken-formulas.ts"
```

- [ ] **Step 4: Run unit tests and commit the harness**

```powershell
npm test -- --run tests/unit/practiceFormulaLocalBenchmark.test.ts
npm run typecheck
git diff --check
git add package.json lib/practice-formula/localBenchmark.ts scripts/benchmark-local-spoken-formulas.ts tests/fixtures/practice-spoken-formula-local-v1.json tests/unit/practiceFormulaLocalBenchmark.test.ts
git diff --cached --name-only
git commit -m "test(practice): benchmark local spoken formula semantics"
```

---

### Task 5: Integrate the verified Math AST backend into the designated shared branch

**Repository:** Backend repository

**Target branch:** `feature/dialogue-exploration-1-2-backend`

- [ ] **Step 1: Verify the source branch is clean and complete**

```powershell
git status --short
git log --oneline --decorate -5
npm test -- --run tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceFormulaLocalModelClient.test.ts tests/unit/practiceFormulaModelProvider.test.ts tests/unit/practiceFormulaLocalBenchmark.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
```

Expected: clean status, all tests pass. Record the exact source commit range beginning with existing Math AST commit `aed6844` through Tasks 3–4.

- [ ] **Step 2: Inspect target-branch divergence before mutating it**

```powershell
git worktree list
git log --oneline --left-right feature/dialogue-exploration-1-2-backend...feature/spoken-formula-math-ast-backend --max-count=40
```

If the target branch has overlapping practice-formula edits, stop and review conflicts rather than forcing a merge. Do not reset either branch.

- [ ] **Step 3: Integrate through an isolated target worktree**

Create or reuse a clean worktree for `feature/dialogue-exploration-1-2-backend`. After Step 2 confirms that the source-only range contains only the spoken-formula feature, capture the exact current hashes and cherry-pick that verified range; do not copy files manually.

```powershell
$integrationBase = git merge-base feature/dialogue-exploration-1-2-backend feature/spoken-formula-math-ast-backend
$sourceTip = git rev-parse feature/spoken-formula-math-ast-backend
git log --oneline "$integrationBase..$sourceTip"
git cherry-pick "$integrationBase..$sourceTip"
```

If conflicts occur, abort the cherry-pick before changing strategy. Preserve the shared AI-teacher MiniMax behavior.

- [ ] **Step 4: Verify the target branch**

Run the same focused Vitest set and `npm run typecheck` in the target worktree. Confirm:

- `/api/practice/formulas/from-spoken-text` exists;
- local provider selection affects only practice formula conversion;
- AI-teacher dialogue still reads its existing provider configuration;
- no token or local `.env` value is committed.

---

### Task 6: Install, start and benchmark Qwen3-1.7B on this laptop

**Repositories:** Flutter tooling + designated backend worktree

**External state:** All files must remain under `D:\dev\local-ai\math-ast`. This task requires the user's download/network approval when executed.

- [ ] **Step 1: Record the disk and process baseline**

Record C/D free bytes and current SenseVoice RSS. Confirm D has at least 5 GB free and C has at least 8 GB free. Do not stop SenseVoice; benchmark the intended concurrent runtime.

- [ ] **Step 2: Run guarded setup and verify hashes**

```powershell
pwsh -NoProfile -File tool/math_ast/setup.ps1 -Root D:\dev\local-ai\math-ast
Get-FileHash D:\dev\local-ai\math-ast\bin\llama-server.exe -Algorithm SHA256
Get-FileHash D:\dev\local-ai\math-ast\models\Qwen3-1.7B-Q4_K_M.gguf -Algorithm SHA256
```

The archive hash must match the pinned archive before extraction; the model file hash must match the pinned model hash. Record but do not commit the resulting runtime manifest.

- [ ] **Step 3: Start llama.cpp and perform protocol smoke tests**

```powershell
pwsh -NoProfile -File tool/math_ast/start.ps1
Invoke-RestMethod http://127.0.0.1:8081/health
```

Send one JSON-Schema-constrained smoke request through the backend client. It must produce a valid Math AST result for an utterance not present in any prior demo table. Confirm the llama process remains resident after the request.

- [ ] **Step 4: Run the real benchmark gate**

In the designated backend worktree set only process-local variables:

```powershell
$env:PRACTICE_FORMULA_MODEL_PROVIDER='local'
$env:PRACTICE_FORMULA_LOCAL_BASE_URL='http://127.0.0.1:8081'
$env:PRACTICE_FORMULA_LOCAL_MODEL='Qwen3-1.7B-Q4_K_M.gguf'
$env:PRACTICE_FORMULA_LOCAL_TIMEOUT_MS='15000'
npm run qa:local-spoken-formula
```

Required gate:

```text
parseRate == 1.00
correctRate >= 0.90
medianMs <= 6000
p95Ms <= 12000
```

- [ ] **Step 5: Enforce the stop decision**

If any metric fails, do not enable the Web remote repository and do not describe the feature as complete. Save the anonymous report on D, show the measured failed metric, and stop for a product decision. If all metrics pass, continue to Task 7.

---

### Task 7: Remove the Demo path from real microphone composition and show the transcript on every outcome

**Repository:** Flutter worktree

**Files:**
- Modify: `lib/developer_tools.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart`
- Modify: `test/features/practice_assessment/practice_spoken_formula_composition_test.dart`
- Modify: `test/features/practice_assessment/practice_formula_voice_panel_test.dart`
- Modify: `test/developer_tools_web_test.dart`

**Interfaces and UI behavior:**

- Mock questions and formula conversion remain separately selectable.
- When `SPOKEN_FORMULA_ASR_MODE=sensevoiceLocal`, the lab must construct `RemoteSpokenFormulaRepository` regardless of `PRACTICE_ASSESSMENT_REMOTE`; it must never construct `DemoSpokenFormulaRepository`.
- The UI label becomes provider-neutral: `本机 SenseVoice + 本地数学模型`.
- Error state renders `识别内容：{transcript}` whenever the controller retained a non-empty transcript.

- [ ] **Step 1: Write failing composition tests**

Assert that this configuration:

```text
PRACTICE_ASSESSMENT_REMOTE=false
PRACTICE_SPOKEN_FORMULA_REMOTE=true
SPOKEN_FORMULA_ASR_MODE=sensevoiceLocal
```

uses mock questions, local SenseVoice recognition and `RemoteSpokenFormulaRepository`. Add a regression assertion that a real/local ASR mode cannot fall back to `DemoSpokenFormulaRepository` even if a formula-remote flag is accidentally false; configuration must fail visibly or force the remote repository.

- [ ] **Step 2: Write the failing transcript-on-error widget test**

Drive the controller through a successful ASR result followed by a repository error, then assert both are visible:

```dart
expect(find.text('识别内容：x 的平方减去三倍 x 再加二'), findsOneWidget);
expect(find.textContaining('本地数学模型'), findsOneWidget);
```

Also assert the old misleading message `演示版暂未覆盖这条表达` is absent from this path.

- [ ] **Step 3: Run tests and verify RED**

```powershell
flutter test test/features/practice_assessment/practice_spoken_formula_composition_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/developer_tools_web_test.dart
```

- [ ] **Step 4: Implement composition and UI changes**

Keep network construction in `developer_tools.dart`, not in the page Widget. Reuse `RemoteSpokenFormulaRepository`; do not duplicate API parsing. In the error panel, render the retained transcript before the safe error message. Add concise Chinese comments explaining why real ASR must never route to the demo repository and why transcript remains visible across semantic failures.

- [ ] **Step 5: Verify and commit Flutter integration**

```powershell
flutter test test/features/practice_assessment/practice_spoken_formula_composition_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/math_answer_field_test.dart test/developer_tools_web_test.dart
dart analyze lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment test/developer_tools_web_test.dart
git diff --check
git add lib/developer_tools.dart lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/developer_tools_web_test.dart
git diff --cached --name-only
git commit -m "feat(practice): route real speech through local math model"
```

---

### Task 8: Full local end-to-end verification and user test page

**Repositories:** Designated backend branch + Flutter worktree

**Files:**
- Create: `docs/operations/MATH_AST_LOCAL_RUNBOOK.md`
- Create only after a passing run: `docs/operations/LOCAL_SPOKEN_FORMULA_BENCHMARK_2026-08-26.md`

- [ ] **Step 1: Document exact local startup and failure boundaries**

The runbook must include:

1. D-drive setup/start/stop commands;
2. required process-local backend environment variables;
3. startup order: SenseVoice 8000 → llama.cpp 8081 → backend 3000 → Flutter 5174;
4. health checks for all three services;
5. no-token/no-cloud statement for `local` mode;
6. troubleshooting for microphone permission, ASR unavailable, local model unavailable, timeout and invalid AST;
7. disk cleanup targets limited to the exact `D:\dev\local-ai\math-ast` subdirectories.

- [ ] **Step 2: Run backend verification on the designated branch**

```powershell
npm test -- --run tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceFormulaLocalModelClient.test.ts tests/unit/practiceFormulaModelProvider.test.ts tests/unit/practiceFormulaLocalBenchmark.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
```

- [ ] **Step 3: Run Flutter verification**

```powershell
pwsh -NoProfile -File tool/math_ast/tests/paths.test.ps1
pwsh -NoProfile -File tool/math_ast/tests/service.test.ps1
flutter test test/features/practice_assessment/record_speech_audio_capture_test.dart test/features/practice_assessment/pcm_wav_encoder_test.dart test/features/practice_assessment/sensevoice_asr_client_test.dart test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/math_answer_field_test.dart test/developer_tools_web_test.dart
dart analyze lib/main.dart lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment test/developer_tools_web_test.dart
```

- [ ] **Step 4: Build the exact real local Web configuration**

```powershell
flutter build web --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=PRACTICE_ASSESSMENT_REMOTE=false --dart-define=PRACTICE_SPOKEN_FORMULA_REMOTE=true --dart-define=SPOKEN_FORMULA_ASR_MODE=sensevoiceLocal --dart-define=SENSEVOICE_BASE_URL=http://127.0.0.1:8000
```

Expected: build succeeds; no Demo formula repository is reachable in this configuration.

- [ ] **Step 5: Start all services and perform ten real-microphone utterances**

Open:

```text
http://localhost:5174/#/practice-assessment-lab
```

Speak ten utterances not copied verbatim from the benchmark fixture, covering algebra, equation, fraction, root, trigonometry, logarithm, interval, limit, derivative and integral. For each case record only anonymous case ID, ASR milliseconds, semantic milliseconds, total milliseconds, success/failure reason and manual correctness; do not persist audio or transcript.

Verify on every case:

- the visible transcript matches what SenseVoice returned;
- local model activity appears in backend/llama timing logs without content;
- preview contains only AST-rendered LaTeX;
- answer remains unchanged until `插入公式`/confirm is pressed;
- failures retain the transcript and never show a guessed formula.

- [ ] **Step 6: Write evidence and commit documentation**

Only after the 30-case gate and ten microphone cases pass, write the benchmark report with hardware, pinned hashes, parameters, parse/correct rates, median/P95 stage timings, memory peak, C/D disk delta and known failed wording.

```powershell
git add docs/operations/MATH_AST_LOCAL_RUNBOOK.md docs/operations/LOCAL_SPOKEN_FORMULA_BENCHMARK_2026-08-26.md
git diff --cached --name-only
git commit -m "docs(formula): record local qwen acceptance"
```

- [ ] **Step 7: Final completion gate**

Before claiming completion, run `git diff --check`, inspect both repository statuses, confirm model/binary/log files are untracked outside Git, and use `superpowers:verification-before-completion`. Leave the page and required services running only if the user asks to test immediately; otherwise provide exact startup commands.

## Expected Delivery State

- Real microphone audio is normalized and transcribed by the already-running local SenseVoice service.
- The shared backend branch selected by the user owns Math AST conversion and calls a real local Qwen service.
- No runtime template can turn a recognized phrase into a canned formula.
- A failed semantic conversion displays the actual transcript and a truthful layer-specific error.
- Local mode requires no MiniMax balance or token and sends no audio/transcript outside the machine.
- Completion is supported by benchmark and real-microphone evidence, including measured limitations.

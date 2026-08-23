# AI Teacher Streaming Latency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让网页端 AI 老师在正常暖机请求中 2～3 秒内开始显示正文，同时保持教学状态、历史记录和幂等写入只在完整结果校验后提交。

**Architecture:** 后端保留现有非流式 `/turns`，新增 `/turns/stream` SSE 端点。MiniMax 客户端流式接收结构化 JSON，用独立增量提取器只转发 `answer` 字符串，完整 JSON 校验成功并原子持久化后发送 `committed` 快照；Flutter Gateway 将 SSE 转为强类型事件，Controller 用临时正文状态原位渲染并在提交事件到达时切换为正式快照。

**Tech Stack:** Next.js 16 Route Handlers、TypeScript、Vitest、MiniMax Anthropic-compatible SSE、Flutter/Dart、package:http、flutter_test。

**Spec:** `docs/superpowers/specs/2026-08-20-ai-teacher-streaming-latency-design.md`

## Global Constraints

- 正常暖机请求的首段可见正文目标为 P50 ≤ 2 秒、P90 ≤ 3 秒。
- 完整教学结果校验和持久化之前，不得改变学习进度、历史记录或巩固验证状态。
- 原 `/api/learning-sessions/{id}/turns` 端点保持兼容。
- 日志不得记录密钥、系统提示词、学生原文或模型完整回答。
- 不新增数据表，不改变现有教学节点结构。
- 所有新增异步状态、流式边界和失败分支必须使用简洁中文注释说明原因和边界。
- 后端实际工程根目录为 `D:/ywkeji/Uniprism/UniPrism_New-main`；Flutter 工程根目录为本仓库。

---

### Task 1: MiniMax JSON Answer 增量提取器

**Files:**
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/jsonAnswerDeltaExtractor.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/jsonAnswerDeltaExtractor.test.ts`

**Interfaces:**
- Produces: `createJsonStringFieldDeltaExtractor(fieldName: string): { push(chunk: string): string; finish(): void }`
- Guarantees: 只输出目标 JSON 字符串字段解码后的新增字符；正确跨 chunk 处理引号、反斜杠、`\uXXXX` 与字段前空白；JSON 不完整时 `finish()` 抛出稳定错误。

- [ ] **Step 1: Write failing extractor tests**

```ts
import { describe, expect, it } from 'vitest';
import { createJsonStringFieldDeltaExtractor } from '@/lib/learning-session/jsonAnswerDeltaExtractor';

describe('JSON answer delta extractor', () => {
  it('emits only decoded answer text across arbitrary chunks', () => {
    const extractor = createJsonStringFieldDeltaExtractor('answer');
    expect(extractor.push('{"answer":"你')).toBe('你');
    expect(extractor.push('好\\n同')).toBe('好\n同');
    expect(extractor.push('学","followUpQuestion":"为什么"}')).toBe('学');
    expect(() => extractor.finish()).not.toThrow();
  });

  it('waits for a split unicode escape before emitting it', () => {
    const extractor = createJsonStringFieldDeltaExtractor('answer');
    expect(extractor.push('{"answer":"\\u4f')).toBe('');
    expect(extractor.push('60\\u597d"}')).toBe('你好');
    extractor.finish();
  });

  it('rejects a stream that ends before answer closes', () => {
    const extractor = createJsonStringFieldDeltaExtractor('answer');
    extractor.push('{"answer":"未结束');
    expect(() => extractor.finish()).toThrow('answer JSON string is incomplete');
  });
});
```

- [ ] **Step 2: Run the extractor test and verify RED**

Run from backend root:

```powershell
npm test -- --run tests/unit/jsonAnswerDeltaExtractor.test.ts
```

Expected: FAIL because `jsonAnswerDeltaExtractor.ts` does not exist.

- [ ] **Step 3: Implement the minimal stateful extractor**

Implement a character-state parser that searches for the exact JSON property token, enters its string value after `:`, decodes JSON escapes incrementally, stops emitting at the closing unescaped quote, and makes `finish()` verify that the field was found and closed. Keep this parser independent from HTTP and model code.

- [ ] **Step 4: Run the extractor test and verify GREEN**

Run the same Vitest command. Expected: all three tests PASS.

- [ ] **Step 5: Commit backend extractor**

```powershell
git add -- lib/learning-session/jsonAnswerDeltaExtractor.ts tests/unit/jsonAnswerDeltaExtractor.test.ts
git commit -m "feat: extract streamed teacher answer JSON"
```

### Task 2: Stream MiniMax while preserving complete structured output

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/learningModelClient.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningModelClient.test.ts`

**Interfaces:**
- Consumes: `createJsonStringFieldDeltaExtractor('answer')` from Task 1.
- Produces: `LearningModelStreamObserver` with `onAnswerDelta(delta: string): void` and optional `onMetrics(metrics: LearningModelMetrics): void`.
- Produces: `callLearningModelJson(options, observer?)` returning the existing complete content/model/usage fields plus `latencyMs`; callers without an observer retain current non-stream behavior.
- `LearningModelMetrics`: `{ headersMs: number; firstAnswerDeltaMs: number | null; totalMs: number; inputTokens?: number; outputTokens?: number; model: string; finishReason?: string }`.

- [ ] **Step 1: Write failing MiniMax SSE tests**

Stub `global.fetch` with a `ReadableStream<Uint8Array>` containing Anthropic events: `message_start`, two `content_block_delta` text chunks carrying split JSON, `message_delta`, and `message_stop`. Assert:

```ts
const deltas: string[] = [];
const result = await callLearningModelJson(options, {
  onAnswerDelta: (delta) => deltas.push(delta),
});
expect(deltas.join('')).toBe('你好，同学');
expect(JSON.parse(result.content).followUpQuestion).toBe('为什么？');
expect(result.usage).toMatchObject({ inputTokens: 120, outputTokens: 48 });
```

Add a second test asserting that an upstream non-2xx response throws the existing `ApiError`, and a third asserting that no observer still sends no `stream` flag and parses the non-stream JSON response.

- [ ] **Step 2: Run model client tests and verify RED**

```powershell
npm test -- --run tests/unit/learningModelClient.test.ts
```

Expected: FAIL because the observer overload and SSE parser do not exist.

- [ ] **Step 3: Implement streaming MiniMax transport**

When provider is MiniMax and an observer is supplied, send `stream: true`, parse SSE line frames with `TextDecoderStream` or a reader plus `TextDecoder`, append all text deltas to the complete raw JSON, and forward only extractor output. Capture headers, first answer delta, completion, usage, model and finish reason. Preserve AbortController timeout and existing error mapping. Keep DeepSeek and observer-less MiniMax behavior unchanged.

- [ ] **Step 4: Run model client tests and existing engine tests**

```powershell
npm test -- --run tests/unit/learningModelClient.test.ts tests/unit/learningSessionTeachingEngine.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit backend model streaming**

```powershell
git add -- lib/learning-session/learningModelClient.ts tests/unit/learningModelClient.test.ts
git commit -m "feat: stream MiniMax teacher responses"
```

### Task 3: Propagate answer deltas without partial persistence

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/dialogueEngine.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionTeachingEngine.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionService.test.ts`

**Interfaces:**
- Consumes: `LearningModelStreamObserver` from Task 2.
- Produces: `LearningTurnStreamObserver` with `onAnswerDelta` and `onModelMetrics` callbacks.
- Changes: `LearningDialogueEngine.generateTurn(input, observer?)` and `LearningSessionService.submitTurn(sessionId, input, access, clientTraceId, observer?)`.
- Keeps: `repository.appendTurn(...)` executes exactly once and only after generated JSON passes schema and teaching decisions finish.

- [ ] **Step 1: Write failing engine callback and token-budget test**

Update the existing “uses non-thinking mode” test to expect `maxTokens: 500`. Add a fake `callJson` that invokes `observer.onAnswerDelta('第一段')` before resolving a valid complete result, then assert `generateTurn(..., observer)` forwards that delta once.

- [ ] **Step 2: Run engine test and verify RED**

```powershell
npm test -- --run tests/unit/learningSessionTeachingEngine.test.ts
```

Expected: FAIL because `generateTurn` does not accept an observer and still requests 1200 tokens.

- [ ] **Step 3: Implement the engine observer and 500-token budget**

Pass the observer to `callLearningModelJson`, change only the teaching generation budget from 1200 to 500, and leave evaluator/practice budgets unchanged. Add a short prompt rule requiring `answer` to be the first JSON field and limiting it to four concise sentences so the extractor can emit useful text early.

- [ ] **Step 4: Write failing service atomicity test**

Use the existing repository fake. Make the teaching engine emit one delta and then reject. Assert the observer receives the delta while `repository.appendTurn` is never called and the stored session revision/node count remains unchanged.

- [ ] **Step 5: Run service test and verify RED**

```powershell
npm test -- --run tests/unit/learningSessionService.test.ts
```

Expected: FAIL because `submitTurn` cannot accept or propagate the observer.

- [ ] **Step 6: Implement service propagation and verify GREEN**

Pass the observer only through the generation phase. Keep all current decision construction and the final `appendTurn` ordering unchanged.

```powershell
npm test -- --run tests/unit/learningSessionTeachingEngine.test.ts tests/unit/learningSessionService.test.ts
```

Expected: PASS.

- [ ] **Step 7: Commit backend orchestration**

```powershell
git add -- lib/learning-session/dialogueEngine.ts lib/learning-session/prompts.ts lib/learning-session/sessionService.ts tests/unit/learningSessionTeachingEngine.test.ts tests/unit/learningSessionService.test.ts
git commit -m "feat: propagate teacher answer deltas safely"
```

### Task 4: Add authenticated, idempotent SSE turn route and timings

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/http.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/server.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/app/api/learning-sessions/[id]/turns/stream/route.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRoutes.test.ts`

**Interfaces:**
- Consumes: streaming `service.submitTurn(..., observer)` from Task 3.
- Produces: `learningSessionApi.submitTurnStream(request): Promise<Response>`.
- Event encoding: `event: <name>\ndata: <single-line JSON>\n\n` for `metadata`, `answer_delta`, `committed`, `error`, and `done`.
- `committed.data` uses the same `{ ok: true, data: snapshot }` payload semantics expected by the existing client parser.

- [ ] **Step 1: Write failing route tests**

Extend the route test service fake so `submitTurn` emits two deltas and returns a snapshot. Assert the response status is 200, content type begins `text/event-stream`, events preserve order, and `committed` contains the snapshot. Add failure assertions for invalid origin/auth before streaming, and an async model failure after headers that yields one `error` event without saving an idempotent result.

- [ ] **Step 2: Run route tests and verify RED**

```powershell
npm test -- --run tests/unit/learningSessionRoutes.test.ts
```

Expected: FAIL because `submitTurnStream` and the stream route do not exist.

- [ ] **Step 3: Implement the stream handler**

Reuse the existing request schema, access assertion, mutation rate limit, session lock, idempotency scope and snapshot saving. Perform validation/auth/rate limiting before creating the `ReadableStream`. Inside the stream, encode callbacks as SSE events, catch post-header errors into a stable error payload, close the writer exactly once, and cancel downstream work when `request.signal` aborts where possible.

Record `knowledgeMs`, model metrics, `persistenceMs`, and `totalMs` under the client trace ID. Add a `Server-Timing` header for known pre-stream phases and include final timings in the `done` event because response headers cannot be changed after streaming starts. Log only numeric metrics, model name, finish reason and trace ID.

- [ ] **Step 4: Verify existing CORS cache contract**

Add/retain a route assertion that OPTIONS returns `access-control-max-age: 86400`. Do not add a duplicate CORS implementation; the current `learningApiOptions` already supplies it.

- [ ] **Step 5: Run backend route and type checks**

```powershell
npm test -- --run tests/unit/learningSessionRoutes.test.ts tests/unit/learningChapterRouteCors.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 6: Commit stream route**

```powershell
git add -- lib/learning-session/http.ts lib/learning-session/server.ts app/api/learning-sessions/[id]/turns/stream/route.ts tests/unit/learningSessionRoutes.test.ts
git commit -m "feat: expose streamed learning turns"
```

### Task 5: Parse SSE into a typed Flutter event stream

**Files:**
- Create: `lib/features/dialogue_exploration/adapters/remote_turn_stream.dart`
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`
- Create: `test/features/dialogue_exploration/remote_turn_stream_test.dart`

**Interfaces:**
- Produces sealed events: `RemoteTurnAnswerDelta(text)`, `RemoteTurnCommitted(snapshot)`, `RemoteTurnFailed(message, canFallback)`, and `RemoteTurnDone(timings)`.
- Changes `RemoteExplorationGateway` to add `Stream<RemoteTurnStreamEvent> submitTurnStream(...)` while retaining `submitTurn(...)` for fallback and test doubles.

- [ ] **Step 1: Write failing Dart SSE parser tests**

Feed byte chunks that split UTF-8 Chinese characters and SSE line boundaries. Assert two `answer_delta` events are decoded in order and the `committed` event parses through `RemoteLearningSessionSnapshot.fromJson`. Add malformed JSON and `error` event tests.

- [ ] **Step 2: Run parser tests and verify RED**

```powershell
flutter test test/features/dialogue_exploration/remote_turn_stream_test.dart
```

Expected: FAIL because the stream parser and event types do not exist.

- [ ] **Step 3: Implement typed stream parsing and API request**

Use `http.Client.send` and consume `StreamedResponse.stream` directly; do not call `http.Response.fromStream` for the stream endpoint. Decode UTF-8 incrementally, split blank-line SSE frames, parse `event` and `data`, map errors to `RemoteExplorationException`, and cancel the subscription when the caller stops listening. Reuse all existing auth, anonymous ID, JSON and idempotency headers.

- [ ] **Step 4: Verify parser and existing API behavior**

```powershell
flutter test test/features/dialogue_exploration/remote_turn_stream_test.dart test/features/dialogue_exploration/remote_exploration_identity_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Flutter stream adapter**

```powershell
git add -- lib/features/dialogue_exploration/adapters/remote_turn_stream.dart lib/features/dialogue_exploration/adapters/remote_exploration_api.dart test/features/dialogue_exploration/remote_turn_stream_test.dart
git commit -m "feat: consume streamed teacher turns"
```

### Task 6: Render incremental teacher text and commit it atomically

**Files:**
- Modify: `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: `submitTurnStream` and typed events from Task 5.
- Adds state: `streamingAnswer`, `streamingTraceId`, and statuses `connecting`, `streaming`, `committing`.
- UI reads only controller state; the temporary answer is not inserted into the persisted snapshot.

- [ ] **Step 1: Write failing controller tests**

Extend `_FakeRemoteApi` with a controllable stream. Assert that after the first delta, `state.status == RemoteExplorationStatus.streaming` and `state.streamingAnswer` contains the text while `state.snapshot` is unchanged. After `RemoteTurnCommitted`, assert the snapshot is replaced, temporary text is cleared and status returns to active. Add tests for one automatic non-stream fallback before the first delta and no automatic fallback after a delta.

- [ ] **Step 2: Run controller tests and verify RED**

```powershell
flutter test test/features/dialogue_exploration/remote_exploration_session_controller_test.dart
```

Expected: FAIL because streaming states and Gateway method are absent.

- [ ] **Step 3: Implement controller stream lifecycle**

Use one stable idempotency key for the stream and any pre-first-delta fallback. Accumulate deltas into immutable state, move to `committing` after the answer ends, replace the snapshot only on `committed`, and clear temporary state on completion. Guard every async state update after disposal and preserve the current duplicate-submission lock.

- [ ] **Step 4: Write failing widget test**

Pump the exploration page with a controllable Gateway. Emit `answer_delta: "先看定义"` and assert the teacher bubble becomes visible before the committed snapshot is emitted; then emit committed and assert there is only one final teacher answer rather than a temporary/final duplicate.

- [ ] **Step 5: Run widget test and verify RED**

```powershell
flutter test test/features/dialogue_exploration/live_tree_page_test.dart
```

Expected: FAIL because the page does not render `streamingAnswer`.

- [ ] **Step 6: Implement the temporary teacher bubble**

Render the accumulated text in the existing conversation area using current teacher-card styling. Keep the typing indicator only during `connecting`; during `streaming` show the growing text, and during `committing` keep the final temporary text visible with a subtle saving state. Do not add a second history node.

- [ ] **Step 7: Run Flutter regression tests and analysis**

```powershell
dart analyze lib/main.dart lib/features/dialogue_exploration test/features/dialogue_exploration
flutter test test/features/dialogue_exploration/remote_turn_stream_test.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/live_tree_page_test.dart
```

Expected: PASS without new warnings.

- [ ] **Step 8: Commit Flutter lifecycle and UI**

```powershell
git add -- lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart lib/features/dialogue_exploration/presentation/remote_exploration_page.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/live_tree_page_test.dart
git commit -m "feat: render teacher answers as they stream"
```

### Task 7: End-to-end latency verification and rollback check

**Files:**
- Modify only if measurements expose a defect in Tasks 1–6; do not add benchmark artifacts containing prompts or answers to Git.

**Interfaces:**
- Consumes the complete backend SSE route and Flutter stream UI.
- Produces a handoff table with preflight, backend headers, MiniMax first answer delta, committed result and total visible time.

- [ ] **Step 1: Run the complete focused backend suite**

```powershell
npm test -- --run tests/unit/jsonAnswerDeltaExtractor.test.ts tests/unit/learningModelClient.test.ts tests/unit/learningSessionTeachingEngine.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts tests/unit/learningChapterRouteCors.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 2: Run the complete focused Flutter suite**

```powershell
dart analyze lib/main.dart lib/features/dialogue_exploration test/features/dialogue_exploration
flutter test test/features/dialogue_exploration/remote_turn_stream_test.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/live_tree_page_test.dart
```

Expected: PASS.

- [ ] **Step 3: Measure three warmed browser turns**

Run the backend and Flutter Web normally, submit three anonymous public-math questions, and record only trace ID, numeric timings, model, token counts and status. Success is P50 first visible answer ≤ 2 seconds and each observed first visible answer ≤ 3 seconds for this smoke sample. Do not print or save credentials, prompts or answer text.

- [ ] **Step 4: Verify fallback**

Disable streaming capability in the test client and confirm the original `/turns` flow still completes with one history node. Restore the normal setting after the check.

- [ ] **Step 5: Produce final handoff**

Report changed modules, security/data impact, exact test results, observed timing table, and any remaining provider-side P90/P99 limitation. Do not claim the 2～3 second target if the measured first-visible timings do not meet it.

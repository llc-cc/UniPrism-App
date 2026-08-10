# Guided Teaching Flow V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有预习探索会话上增加可恢复的教案引导模式，让素材操作经过后端形成证据并驱动下一步教学，同时保持自由探索模式兼容。

**Architecture:** 继续使用现有 `LearningSession` 聚合、素材使用记录、练习尝试和会话 API。后端新增确定性的引导流程协议与协调器，将版本化流程快照存入 `LearningSession.teachingFlow`，将素材事件存入现有 `LearningMaterialUsage.interactionEvents`；Flutter 只渲染后端动作并提交事件，不自行推导掌握度。

**Tech Stack:** Next.js、TypeScript、Zod、Prisma/MySQL、Vitest、Flutter/Dart、flutter_test。

## Global Constraints

- 保留现有 `OPEN_EXPLORATION` 行为；旧客户端未传 `flowMode` 时不得进入引导模式。
- 第一阶段使用 Mock 教案和 Mock 素材，不调用真实 MCP，也不新增知识库凭证。
- 不新增业务表；只在 `LearningSession` 增加可空 `teachingFlow Json?` 字段。
- 素材事件继续保存在 `LearningMaterialUsage.interactionEvents`；微测继续复用现有练习尝试和 mastery evidence。
- 证据强度只由后端推导；客户端 payload 不能直接写 `INDEPENDENT` 或掌握结论。
- 新增状态机、异步流程和数据安全分支必须写简洁中文注释。
- 每个生产改动先写失败测试并确认 RED，再写最小实现并确认 GREEN。
- 不覆盖当前两个仓库中与本功能无关的未提交改动。

---

## File Map

### Backend: `D:/ywkeji/Uniprism/UniPrism_New-main`

- Create `lib/learning-session/guidedTeachingFlow.ts`: V1 协议、Mock 教案 Provider 和纯流程协调器。
- Modify `lib/learning-session/contracts.ts`: 创建会话与素材事件 Zod 请求协议。
- Modify `lib/learning-session/repository.ts`: 聚合字段、事件追加输入和 Prisma 事务持久化。
- Modify `lib/learning-session/memoryRepository.ts`: 开发内存仓库的等价事件追加行为。
- Modify `lib/learning-session/sessionService.ts`: 创建、答题、素材事件、微测与快照编排。
- Modify `lib/learning-session/http.ts`: 素材事件 Handler、鉴权、限流和幂等。
- Create `app/api/learning-sessions/[id]/materials/[materialUsageId]/events/route.ts`: Next.js 路由。
- Modify `prisma/schema.prisma`: `LearningSession.teachingFlow Json?`。
- Create `prisma/migrations/20260810120000_guided_teaching_flow_v1/migration.sql`: 可空 JSON 字段迁移。
- Create `tests/unit/guidedTeachingFlow.test.ts`: 纯状态机规则测试。
- Modify `tests/unit/learningSessionService.test.ts`: 服务完整闭环测试。
- Modify `tests/unit/learningSessionRepository.test.ts`: 持久化、恢复和事件幂等测试。
- Modify `tests/unit/learningSessionRoutes.test.ts`: HTTP 校验、归属和重复请求测试。
- Modify `tests/unit/learningSessionMigration.test.ts`: 迁移结构测试。

### Flutter: `D:/dev/Uniprism/uniprism_app`

- Create `lib/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart`: 引导流程 DTO 与容错解析。
- Modify `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`: 快照和素材事件字段。
- Modify `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`: `flowMode` 与素材事件请求。
- Modify `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`: 引导入口、素材事件和微测动作。
- Create `lib/features/dialogue_exploration/presentation/guided_teaching_panel.dart`: 目标、阶段、微测与反思面板。
- Modify `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`: 接入面板和互动事件回调。
- Modify `test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`: Controller 模式和异步事件测试。
- Modify `test/features/dialogue_exploration/live_tree_page_test.dart`: 引导页面、素材事件、微测和旧模式回归测试。
- Modify `docs/PRESTUDY_MODULE_HANDOFF.md`: 记录 V1 接口、Mock 边界和正式 MCP 替换点。

---

### Task 1: Backend Guided Flow Domain

**Files:**
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/guidedTeachingFlow.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/contracts.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/guidedTeachingFlow.test.ts`

**Interfaces:**
- Consumes: existing material IDs, practice verdicts `MASTERED | PARTIAL | RETRY`.
- Produces: `FlowModeV1`, `TeachingFlowV1`, `TeacherActionV1`, `AssetEventV1`, `EvidenceStateV1`, `GuidedLessonProvider`, `MockGuidedLessonProvider`, `createGuidedTeachingFlow()`, `advanceGuidedTeachingFlow()`.

- [ ] **Step 1: Write the failing coordinator tests**

```ts
import {
  advanceGuidedTeachingFlow,
  createGuidedTeachingFlow,
  MockGuidedLessonProvider,
} from '../../lib/learning-session/guidedTeachingFlow';

test('guided flow starts with a diagnostic question', () => {
  const lesson = new MockGuidedLessonProvider().getLesson('opposite-number');
  const flow = createGuidedTeachingFlow(lesson);
  expect(flow.stage).toBe('DIALOGUE');
  expect(flow.currentAction.type).toBe('ASK_QUESTION');
  expect(flow.evidence.missingCodes).toEqual(lesson.requiredEvidenceCodes);
});

test('an unhinted completed asset event opens the micro check', () => {
  const flow = createGuidedTeachingFlow(
    new MockGuidedLessonProvider().getLesson('opposite-number'),
  );
  const assetFlow = advanceGuidedTeachingFlow(flow, {
    type: 'DIAGNOSTIC_ANSWERED',
    materialUsageId: 'material-1',
  });
  const focusFlow = advanceGuidedTeachingFlow(assetFlow, {
    type: 'ASSET_COMPLETED',
    sourceId: 'event-1',
    hintUsed: false,
  });
  expect(focusFlow.stage).toBe('FOCUS');
  expect(focusFlow.currentAction.type).toBe('REQUEST_MICRO_CHECK');
  expect(focusFlow.evidence.items).toHaveLength(1);
  expect(focusFlow.evidence.items[0]?.strength).toBe('OBSERVED');
});

test('only an unhinted mastered practice creates independent evidence', () => {
  const lesson = new MockGuidedLessonProvider().getLesson('opposite-number');
  const focus = advanceGuidedTeachingFlow(
    advanceGuidedTeachingFlow(createGuidedTeachingFlow(lesson), {
      type: 'DIAGNOSTIC_ANSWERED', materialUsageId: 'material-1',
    }),
    { type: 'ASSET_COMPLETED', sourceId: 'event-1', hintUsed: true },
  );
  const reflected = advanceGuidedTeachingFlow(focus, {
    type: 'PRACTICE_ASSESSED',
    sourceId: 'practice-1',
    verdict: 'MASTERED',
    hintUsed: false,
  });
  expect(reflected.stage).toBe('REFLECT');
  expect(reflected.evidence.items.at(-1)?.strength).toBe('INDEPENDENT');
});
```

- [ ] **Step 2: Run the domain test and verify RED**

Run: `npx vitest run tests/unit/guidedTeachingFlow.test.ts`

Expected: FAIL because `guidedTeachingFlow.ts` and exported contracts do not exist.

- [ ] **Step 3: Implement the V1 contracts and pure coordinator**

Implement discriminated action and transition types with `schemaVersion: 1`. The coordinator must be a pure function and reject transitions that do not match the current stage. Use this public surface:

```ts
export type FlowModeV1 = 'OPEN_EXPLORATION' | 'GUIDED_LESSON';
export type TeachingStageV1 = 'DIALOGUE' | 'ASSET' | 'FOCUS' | 'REFLECT';
export type EvidenceStrengthV1 = 'OBSERVED' | 'ASSISTED' | 'INDEPENDENT';

export interface GuidedLessonV1 {
  id: string;
  atomId: string;
  goal: string;
  diagnosticQuestion: string;
  requiredEvidenceCodes: string[];
  materialIds: string[];
  fallbackMaterialId: string;
  practiceId: string;
}

export interface GuidedLessonProvider {
  getLesson(atomId: string): GuidedLessonV1;
}

export function createGuidedTeachingFlow(lesson: GuidedLessonV1): TeachingFlowV1;

export function advanceGuidedTeachingFlow(
  flow: TeachingFlowV1,
  event:
    | { type: 'DIAGNOSTIC_ANSWERED'; materialUsageId: string }
    | { type: 'ASSET_COMPLETED'; sourceId: string; hintUsed: boolean }
    | {
        type: 'PRACTICE_ASSESSED';
        sourceId: string;
        verdict: 'MASTERED' | 'PARTIAL' | 'RETRY';
        hintUsed: boolean;
      },
): TeachingFlowV1;
```

In `contracts.ts`, add `flowMode` to `createLearningSessionSchema` and add strict `submitMaterialEventSchema`. The payload must be a JSON object with no more than 20 keys and a serialized length no greater than 8 KiB.

- [ ] **Step 4: Run the coordinator tests and verify GREEN**

Run: `npx vitest run tests/unit/guidedTeachingFlow.test.ts`

Expected: PASS with no warnings.

- [ ] **Step 5: Commit the domain layer**

```bash
git add lib/learning-session/guidedTeachingFlow.ts lib/learning-session/contracts.ts tests/unit/guidedTeachingFlow.test.ts
git commit -m "feat(prestudy): add guided teaching flow domain"
```

---

### Task 2: Persist Guided Flow and Material Events

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/prisma/schema.prisma`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/prisma/migrations/20260810120000_guided_teaching_flow_v1/migration.sql`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/repository.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/memoryRepository.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRepository.test.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionMigration.test.ts`

**Interfaces:**
- Consumes: `TeachingFlowV1`, validated `AssetEventV1`.
- Produces: aggregate field `teachingFlow`, repository method `appendMaterialEvent()` and optional flow updates on existing turn/practice mutations.

- [ ] **Step 1: Write failing persistence and migration tests**

Add assertions that the schema contains `teachingFlow Json?`, the migration uses `ALTER TABLE learning_sessions ADD COLUMN teachingFlow JSON NULL`, restored aggregates preserve the flow, and duplicate `eventId` leaves the interaction event list length unchanged.

```ts
expect(schema).toMatch(/model LearningSession[\s\S]*teachingFlow\s+Json\?/);
expect(migration).toContain('ADD COLUMN `teachingFlow` JSON NULL');
```

- [ ] **Step 2: Run repository tests and verify RED**

Run: `npx vitest run tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionMigration.test.ts`

Expected: FAIL because the field and repository mutation do not exist.

- [ ] **Step 3: Add the nullable field and repository mutation**

Extend `LearningSessionAggregate` with `teachingFlow: TeachingFlowV1 | null`. Add:

```ts
appendMaterialEvent(
  sessionId: string,
  expectedRevision: number,
  input: {
    materialUsageId: string;
    event: AssetEventV1;
    teachingFlow: TeachingFlowV1;
  },
): Promise<LearningSessionAggregate>;
```

The Prisma implementation must read the material by `id + sessionId`, normalize a missing event list to `[]`, return the current aggregate when the same `eventId` already exists, and otherwise update the material JSON and session `teachingFlow/revision` in one transaction. Add equivalent deterministic behavior to `MemoryLearningSessionRepository`.

Existing create, append-turn and append-practice operations accept an optional next `teachingFlow` so each state transition is persisted with the mutation that caused it.

- [ ] **Step 4: Run repository tests and verify GREEN**

Run: `npx vitest run tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionMigration.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit persistence**

```bash
git add prisma/schema.prisma prisma/migrations/20260810120000_guided_teaching_flow_v1 lib/learning-session/repository.ts lib/learning-session/memoryRepository.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionMigration.test.ts
git commit -m "feat(prestudy): persist guided flow evidence events"
```

---

### Task 3: Orchestrate the Backend End-to-End Flow

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/http.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/app/api/learning-sessions/[id]/materials/[materialUsageId]/events/route.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionService.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRoutes.test.ts`

**Interfaces:**
- Consumes: Task 1 coordinator and Task 2 repository methods.
- Produces: snapshot field `teachingFlow` and authenticated material-event endpoint.

- [ ] **Step 1: Write failing service and route tests**

Add one service test that creates `GUIDED_LESSON`, submits a diagnostic answer, submits an asset event, submits the configured practice, and observes stages `DIALOGUE → ASSET → FOCUS → REFLECT`. Add route tests for unknown material usage, wrong owner, invalid payload, and repeated idempotency key.

```ts
const created = await service.create({
  exploreSessionId: 'explore-1',
  scenarioId: 'chapter',
  atomId: 'opposite-number',
  flowMode: 'GUIDED_LESSON',
}, access, 'create-1');
expect(created.teachingFlow?.stage).toBe('DIALOGUE');
```

- [ ] **Step 2: Run service and route tests and verify RED**

Run: `npx vitest run tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts`

Expected: FAIL because guided orchestration and the route handler are missing.

- [ ] **Step 3: Implement service transitions and HTTP handler**

Inject `GuidedLessonProvider` into `LearningSessionService`, defaulting to `MockGuidedLessonProvider` only in the existing mock/development configuration. For production modes without a guided provider, return a typed business error instead of silently falling back.

Add service method:

```ts
submitMaterialEvent(
  sessionId: string,
  materialUsageId: string,
  input: SubmitMaterialEventInput,
  access: LearningSessionAccess,
): Promise<LearningSessionSnapshot>;
```

Creation initializes the flow. `submitTurn` advances DIALOGUE only after the normal model/quality-gate turn succeeds and selects a material usage owned by the new node. `submitMaterialEvent` derives `hintUsed` from the server flow, advances to FOCUS, and persists both event and flow. `submitPracticeAttempt` advances to REFLECT only for an unhinted `MASTERED`; otherwise it returns to DIALOGUE. `toLearningSessionSnapshot` serializes the optional flow.

The HTTP handler must use existing `assertAccess`, `limitMutation` and `mutateSession` helpers. The route reads `materialUsageId` from the URL and exports `POST` through `withLearningApi`.

- [ ] **Step 4: Run backend flow tests and verify GREEN**

Run: `npx vitest run tests/unit/guidedTeachingFlow.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionMigration.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit backend orchestration**

```bash
git add lib/learning-session/sessionService.ts lib/learning-session/http.ts app/api/learning-sessions tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts
git commit -m "feat(prestudy): connect guided teaching flow API"
```

---

### Task 4: Add Flutter Contracts, API, and Controller Actions

**Files:**
- Create: `lib/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart`
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`
- Modify: `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`
- Modify: `test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`

**Interfaces:**
- Consumes: backend `TeachingFlowV1` snapshot and material-event endpoint.
- Produces: `RemoteTeachingFlow`, `RemoteTeacherAction`, `RemoteEvidenceState`, `RemoteAssetEvent`, `submitMaterialEvent()` and guided micro-check Controller methods.

- [ ] **Step 1: Write failing DTO and Controller tests**

Add tests that parse a guided snapshot, tolerate an absent flow, send `GUIDED_LESSON` from `startFromChapterNode`, send `OPEN_EXPLORATION` from the free-question entry, submit a material event, reuse the pending event ID after a network failure, and clear it after success.

```dart
expect(controller.state.snapshot?.teachingFlow?.stage, TeachingStage.asset);
expect(api.lastCreateFlowMode, RemoteFlowMode.guidedLesson);
await controller.submitMaterialEvent(
  materialUsageId: 'material-1',
  eventType: 'SIGN_FLIPPED',
  payload: const {'input': -3, 'output': 3},
);
expect(api.lastMaterialEvent?.eventType, 'SIGN_FLIPPED');
```

- [ ] **Step 2: Run Controller tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`

Expected: FAIL because the DTO fields and methods do not exist.

- [ ] **Step 3: Implement tolerant DTO parsing and API calls**

Create enums with an `unknown`/safe fallback where applicable. `RemoteLearningSessionSnapshot.fromJson` reads nullable `teachingFlow`. Extend the API surface:

```dart
Future<RemoteLearningSessionSnapshot> createSession({
  required String scenarioId,
  String? atomId,
  String? directionId,
  String? question,
  required RemoteFlowMode flowMode,
});

Future<RemoteLearningSessionSnapshot> submitMaterialEvent({
  required String sessionId,
  required String materialUsageId,
  required RemoteAssetEvent event,
});
```

The Controller owns pending event IDs because it owns retries. Use a private map keyed by `materialUsageId:eventType`; remove the key only after the backend returns a snapshot. `submitGuidedPractice()` delegates to the existing API `submitPracticeAttempt` and accepts reasoning plus answer.

- [ ] **Step 4: Run Controller tests and verify GREEN**

Run: `flutter test test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit Flutter contracts and Controller**

```bash
git add lib/features/dialogue_exploration/adapters lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart
git commit -m "feat(prestudy): add guided flow client contracts"
```

---

### Task 5: Render and Operate the Guided Classroom

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/guided_teaching_panel.dart`
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: Controller state and `RemoteTeachingFlow` from Task 4.
- Produces: target/stage banner, action panel, material-event callback, micro-check form and reflection CTA.

- [ ] **Step 1: Write failing widget tests**

Add tests for:

1. Free exploration snapshot does not display the guided target banner.
2. Guided DIALOGUE displays the lesson goal and diagnostic action.
3. Guided ASSET interaction calls fake API with the material usage ID and event payload.
4. Guided FOCUS displays reasoning/answer fields and submits the configured practice ID.
5. Guided REFLECT displays the completion action.
6. Busy state disables duplicate material and practice submissions.

```dart
expect(find.byKey(const ValueKey('guided-teaching-goal')), findsOneWidget);
await tester.tap(find.byKey(const ValueKey('sign-flip-apply')));
await tester.pumpAndSettle();
expect(api.lastMaterialEvent?.materialUsageId, 'material-1');
```

- [ ] **Step 2: Run widget tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: FAIL because the guided panel and event callback are absent.

- [ ] **Step 3: Implement the guided panel and callbacks**

`GuidedTeachingPanel` receives immutable flow data and explicit callbacks. It does not call APIs directly. In `RemoteLearningSessionPage`, insert it above the dialogue classroom only when `teachingFlow != null`.

Pass an async completion callback through `_LearningMaterialCard` into `_InteractiveLearningMaterial`. For the initial Mock components:

- sign flip button submits `SIGN_FLIPPED` with input/output;
- parabola slider submits `PARABOLA_PARAMETERS_COMMITTED` from `onChangeEnd` with `a/h/k`;
- other interactive components submit a component-specific completion event only at their existing verification action.

Local visual state remains responsive, but the page advances teaching stage only after the backend snapshot returns. Show existing failure UI on request errors and leave the action retryable.

- [ ] **Step 4: Run widget and Controller tests and verify GREEN**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the guided classroom UI**

```bash
git add lib/features/dialogue_exploration/presentation test/features/dialogue_exploration/live_tree_page_test.dart
git commit -m "feat(prestudy): render guided teaching evidence loop"
```

---

### Task 6: Handoff Documentation and Full Verification

**Files:**
- Modify: `docs/PRESTUDY_MODULE_HANDOFF.md`

**Interfaces:**
- Consumes: completed backend and Flutter behavior.
- Produces: exact current capability, Mock limitations, API route and MCP replacement boundary.

- [ ] **Step 1: Update the handoff document**

Document both modes, the material-event route, `TeachingFlowV1` recovery semantics, the fact that evidence is server-derived, and the current `MockGuidedLessonProvider` limitation. State that real MCP replaces `GuidedLessonProvider` without changing client contracts.

- [ ] **Step 2: Run focused backend verification**

Run in `D:/ywkeji/Uniprism/UniPrism_New-main`:

```bash
npx vitest run tests/unit/guidedTeachingFlow.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionMigration.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts
```

Expected: PASS.

- [ ] **Step 3: Run backend type and Prisma checks**

Run:

```bash
npx prisma validate
npx tsc --noEmit
```

Expected: PASS, or report pre-existing unrelated failures separately with exact output.

- [ ] **Step 4: Run focused and full Flutter verification**

Run in `D:/dev/Uniprism/uniprism_app`:

```bash
dart analyze lib/main.dart test
flutter test test/features/dialogue_exploration
flutter test
```

Expected: PASS, or report pre-existing unrelated failures separately with exact output.

- [ ] **Step 5: Commit handoff documentation**

```bash
git add docs/PRESTUDY_MODULE_HANDOFF.md
git commit -m "docs(prestudy): document guided teaching flow v1"
```

- [ ] **Step 6: Review final diffs**

Run `git diff --check` and inspect `git status --short` in both repositories. Confirm that commits and remaining dirty files do not contain unrelated user changes.

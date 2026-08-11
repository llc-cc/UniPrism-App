# Adaptive Pre-study Mastery Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 1.2 预习会话上实现“诊断决定讲解深度、所有学生必做独立基础题、答错后教到新题答对、完成后自主选择进阶方向”的可靠闭环。

**Architecture:** 继续使用后端 `LearningSession` 聚合和 `DIALOGUE → ASSET → FOCUS → REFLECT` 阶段，不建立第二套课堂。后端将教案、诊断、题目变体、判定、修复焦点和后继关系编排成版本 2 教学快照；Flutter 只渲染服务端事实并提交学生动作。旧版本教学快照和 `OPEN_EXPLORATION` 保持兼容。

**Tech Stack:** Next.js/TypeScript、Zod、Prisma JSON、Vitest；Flutter/Dart、ChangeNotifier、Widget Test。

## Global Constraints

- 即使诊断显示学生已经会，也只能跳过重复讲解，不能跳过无提示独立基础题。
- 只有“答案正确 + 关键原理成立 + 未使用提示”的提交可以产生 `INDEPENDENT` 证据。
- `PARTIAL`/`RETRY` 必须显示具体缺口并换一道同层题复验；连续三次失败后进入完整示范，但绝不自动通过。
- 每个可启动的 Mock 引导教案必须有至少三道题目变体和可达的 `MASTERED` 路径。
- 非终点知识点返回 2～3 个已审核后继方向；后继 Provider 暂时不可用时不能阻断当前知识点完成。
- 不记录模型思维链，不允许 Flutter 写入诊断等级、证据强度或掌握结论。
- 保留账号历史、会话恢复、素材事件幂等、revision、思维树、只读完成页和开放探索行为。
- 新增或实质修改的状态机、异步流程和安全边界写简洁中文注释；不为显然赋值和样式堆注释。
- 两个仓库当前都有用户未提交改动；每次只暂存本任务列出的文件，不清理、不重置、不覆盖无关改动。
- Backend root: `D:/ywkeji/Uniprism/UniPrism_New-main`；Flutter root: `D:/dev/Uniprism/uniprism_app`。

## File Structure

### Backend

- Modify `lib/learning-session/guidedTeachingFlow.ts`: 版本 2 教案/流程类型、Mock 教案目录、阶段协调器和旧快照规范化。
- Modify `lib/learning-session/chapterPracticeEngine.ts`: 五个 Mock 原子的诊断与练习确定性判定，不负责会话推进。
- Modify `lib/learning-session/contracts.ts`: 章节目录 DTO，不改变现有 mutation 请求边界。
- Modify `lib/learning-session/knowledgeProvider.ts`: 增加章节目录读取接口。
- Modify `lib/learning-session/mockKnowledgeProvider.ts`: 返回三个已审核章节的目录。
- Modify `lib/learning-session/noKnowledgeProvider.ts`: 以空目录安全降级。
- Modify `lib/learning-session/remoteKnowledgeProvider.ts`: 上游未提供目录时返回空目录，不伪造章节。
- Modify `lib/learning-session/sessionService.ts`: 诊断、题目判定、修复、恢复和进阶选项编排。
- Modify `lib/learning-session/repository.ts`: 持久化 V1/V2 教学快照联合类型。
- Modify `lib/learning-session/memoryRepository.ts`: 与 Prisma Repository 保持相同联合类型语义。
- Modify `lib/learning-session/http.ts`: 提供章节目录 handler。
- Create `app/api/learning-chapters/route.ts`: 暴露 `GET /api/learning-chapters`。
- Tests: `tests/unit/guidedTeachingFlow.test.ts`, `chapterPracticeEngine.test.ts`, `learningSessionService.test.ts`, `learningSessionRepository.test.ts`, `learningSessionRoutes.test.ts`, `learningChapterOverview.test.ts`。

### Flutter

- Modify `lib/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart`: 容错解析诊断、活动题目、修复焦点和进阶方向。
- Modify `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`: 章节目录 DTO。
- Modify `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`: 章节目录请求。
- Modify `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`: 章节选择和进阶会话启动。
- Create `lib/features/dialogue_exploration/presentation/chapter_catalog_picker.dart`: 只负责章节目录展示与选择。
- Create `lib/features/dialogue_exploration/presentation/guided_practice_dialog.dart`: 展示服务端题干并返回推理/答案草稿。
- Create `lib/features/dialogue_exploration/presentation/next_learning_options_sheet.dart`: 展示继续学习或结束选择。
- Modify `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`: 组合章节入口、自适应动作、练习弹窗和完成页。
- Tests: `remote_exploration_session_controller_test.dart`, `live_tree_page_test.dart`, `remote_learning_graph_test.dart`。

---

### Task 1: Establish Baselines and Add Deterministic Lesson Assessments

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/guidedTeachingFlow.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/chapterPracticeEngine.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/chapterPracticeEngine.test.ts`

**Interfaces:**
- Consumes: existing `GuidedLessonProvider`, `PracticeVerdict` and the current four guided Mock atoms; this task also registers the already existing knowledge atom `inequality-proof` as a terminal guided successor.
- Produces: `GuidedDiagnosticLevelV2`, `GuidedDiagnosticAssessmentV2`, `GuidedPracticeVariantV2`, `NextLearningOptionV2`, `GuidedLessonV2`, `assessGuidedDiagnostic()` and a complete `assessChapterPracticeAttempt()` implementation for every registered lesson.

- [ ] **Step 1: Run the current focused baselines before changing code**

Backend:

```powershell
cd D:/ywkeji/Uniprism/UniPrism_New-main
npx vitest run tests/unit/guidedTeachingFlow.test.ts tests/unit/chapterPracticeEngine.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionRoutes.test.ts tests/unit/learningChapterOverview.test.ts
```

Flutter:

```powershell
cd D:/dev/Uniprism/uniprism_app
flutter test test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/live_tree_page_test.dart test/features/dialogue_exploration/remote_learning_graph_test.dart
```

Expected: existing tests pass, or record exact pre-existing failures before implementation so later verification does not misattribute them.

- [ ] **Step 2: Write failing assessment coverage for all registered lessons**

Add tests with the exact public shapes:

```ts
expect(assessGuidedDiagnostic({
  atomId: 'negative-times-negative',
  studentText: '连续取两次相反数会回到原方向，同号相乘为正。',
})).toMatchObject({ level: 'READY_FOR_CHECK' });

expect(assessGuidedDiagnostic({
  atomId: 'force-and-motion',
  studentText: '不知道',
})).toMatchObject({ level: 'NEEDS_TEACHING' });

it.each([
  ['negative-times-negative', 'negative-sign-v1', '两个因数同号，所以乘积为正。', '正数'],
  ['quadratic-function', 'quadratic-vertex-v1', 'h 决定横坐标，k 决定纵坐标，a 为正所以开口向上。', '顶点(3,1)，开口向上'],
  ['inequality-proof', 'inequality-condition-v1', '均值不等式要求两个数为正，且相等时取等号。', 'a=b 时取等号'],
  ['chemical-reaction-conservation', 'chemical-balance-v1', '只能改变系数并保持每种原子数量相等。', '2H2 + O2 = 2H2O'],
  ['force-and-motion', 'force-motion-v1', 'F=ma，推力不变时质量加倍会让加速度减半。', '减半'],
])('%s has a reachable mastered practice path', (atomId, practiceId, reasoning, answer) => {
  expect(assessChapterPracticeAttempt({ atomId, practiceId, reasoning, answer }))
    .toMatchObject({ verdict: 'MASTERED', score: 100 });
});
```

Also assert each `MockGuidedLessonProvider` lesson contains three unique practice IDs and either 2～3 next options or `isTerminal: true`.

- [ ] **Step 3: Run the assessment test to verify RED**

```powershell
npx vitest run tests/unit/chapterPracticeEngine.test.ts
```

Expected: FAIL because diagnostic contracts and the non-negative assessors do not exist.

- [ ] **Step 4: Add exact version 2 lesson contracts and Mock data**

Define:

```ts
export type GuidedDiagnosticLevelV2 =
  | 'READY_FOR_CHECK'
  | 'NEEDS_CLARIFICATION'
  | 'NEEDS_TEACHING';

export type GuidedDiagnosticAssessmentV2 = {
  level: GuidedDiagnosticLevelV2;
  repairFocus: string | null;
};

export type GuidedPracticeVariantV2 = {
  id: string;
  title: string;
  prompt: string;
  reasoningLabel: string;
  answerLabel: string;
  assessorVersion: 1;
};

export type NextLearningOptionV2 = {
  atomId: string;
  chapterId: string;
  title: string;
  relation: string;
  difficultyReason: string;
  estimatedMinutes: number;
  hookQuestion: string;
  prerequisitesSatisfied: boolean;
};

export type GuidedLessonV2 = GuidedLessonV1 & {
  schemaVersion: 2;
  practiceVariants: GuidedPracticeVariantV2[];
  nextLearningOptions: NextLearningOptionV2[];
  isTerminal: boolean;
};

export interface GuidedLessonProvider {
  getLesson(atomId: string): GuidedLessonV2;
}
```

Register these exact practice families:

| Atom | Variant IDs | Required result |
|---|---|---|
| `negative-times-negative` | `negative-sign-v1..v3` | distinguish two negative factors and explain same-sign-positive |
| `quadratic-function` | `quadratic-vertex-v1..v3` | identify vertex `(h,k)` and opening from the sign of `a` |
| `inequality-proof` | `inequality-condition-v1..v3` | identify positivity conditions, equality conditions and a numeric AM-GM check |
| `chemical-reaction-conservation` | `chemical-balance-v1..v3` | provide correct coefficients and explain atom conservation without changing subscripts |
| `force-and-motion` | `force-motion-v1..v3` | apply `F=ma` to direct-force or inverse-mass changes |

The negative multiplication lesson is the first non-terminal proof path and returns exactly two guided successors: `quadratic-function` and `inequality-proof`. Both must resolve through `KnowledgeProvider.getLearningEntry()` and `MockGuidedLessonProvider.getLesson()`. Mark the remaining initial Mock lessons terminal until their audited successors exist; do not invent cross-subject “advanced” links merely to fill the UI.

- [ ] **Step 5: Implement deterministic diagnostic and practice assessment**

Keep the existing signature for practice submissions and add `repairFocus` to the result:

```ts
export type ChapterPracticeAssessment = {
  verdict: PracticeVerdict;
  score: number;
  feedback: string;
  repairFocus: string | null;
  solutionSteps: string[];
};

export function assessGuidedDiagnostic(input: {
  atomId: string;
  studentText: string;
}): GuidedDiagnosticAssessmentV2;
```

Use explicit per-atom rules. A fully correct answer returns `READY_FOR_CHECK`; a relevant but incomplete answer returns `NEEDS_CLARIFICATION`; blank, “不知道”, or a contradictory answer returns `NEEDS_TEACHING`. Unknown atoms must not return `READY_FOR_CHECK`.

- [ ] **Step 6: Run domain tests to verify GREEN**

```powershell
npx vitest run tests/unit/chapterPracticeEngine.test.ts tests/unit/guidedTeachingFlow.test.ts
```

Expected: PASS.

- [ ] **Step 7: Commit the assessment bundle**

```powershell
git add lib/learning-session/guidedTeachingFlow.ts lib/learning-session/chapterPracticeEngine.ts tests/unit/chapterPracticeEngine.test.ts
git commit -m "feat(prestudy): add adaptive lesson assessments"
```

---

### Task 2: Upgrade the Guided Flow Coordinator Without Skipping Practice

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/guidedTeachingFlow.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/guidedTeachingFlow.test.ts`

**Interfaces:**
- Consumes: Task 1 `GuidedLessonV2`, `GuidedDiagnosticLevelV2`, practice verdicts and feedback.
- Produces: `TeachingFlowV2`, `PersistedTeachingFlow`, `normalizeTeachingFlow()`, and adaptive transitions for diagnostic, asset, practice repair and reflection.

- [ ] **Step 1: Write failing coordinator tests for the two main paths**

```ts
const known = advanceGuidedTeachingFlow(createGuidedTeachingFlow(lesson, now), {
  type: 'DIAGNOSTIC_ASSESSED',
  level: 'READY_FOR_CHECK',
  repairFocus: null,
  occurredAt: now,
});
expect(known).toMatchObject({
  schemaVersion: 2,
  stage: 'FOCUS',
  diagnosticLevel: 'READY_FOR_CHECK',
  attemptRound: 0,
  activePractice: { id: lesson.practiceVariants[0]!.id },
});

const needsTeaching = advanceGuidedTeachingFlow(createGuidedTeachingFlow(lesson, now), {
  type: 'DIAGNOSTIC_ASSESSED',
  level: 'NEEDS_TEACHING',
  repairFocus: '先理解连续两次取相反数',
  materialUsageId: 'material-1',
  occurredAt: now,
});
expect(needsTeaching.stage).toBe('ASSET');
```

Add assertions that `MASTERED` is the only event entering `REFLECT`, `PARTIAL`/`RETRY` increments `attemptRound`, stores feedback, and selects a different practice variant. After the third failed round, assert `supportLevel === 3` and `currentAction.reasonCode === 'GUIDED_WORKED_EXAMPLE_REQUIRED'` without adding independent evidence.

- [ ] **Step 2: Run coordinator tests to verify RED**

```powershell
npx vitest run tests/unit/guidedTeachingFlow.test.ts
```

Expected: FAIL because V2 flow fields and diagnostic branching do not exist.

- [ ] **Step 3: Define the persisted V2 flow and normalizer**

```ts
export type TeacherActionV2 = Omit<TeacherActionV1, 'reasonCode'> & {
  reasonCode:
    | TeacherActionV1['reasonCode']
    | 'GUIDED_CLARIFICATION_REQUIRED'
    | 'GUIDED_REPAIR_REQUIRED'
    | 'GUIDED_WORKED_EXAMPLE_REQUIRED';
};

export type TeachingFlowV2 = Omit<
  TeachingFlowV1,
  'schemaVersion' | 'currentAction'
> & {
  schemaVersion: 2;
  currentAction: TeacherActionV2;
  diagnosticLevel: GuidedDiagnosticLevelV2 | 'UNKNOWN';
  diagnosticRound: number;
  attemptRound: number;
  supportLevel: number;
  practiceVariants: GuidedPracticeVariantV2[];
  activePractice: GuidedPracticeVariantV2;
  repairFocus: string | null;
  nextLearningOptions: NextLearningOptionV2[];
};

export type PersistedTeachingFlow = TeachingFlowV1 | TeachingFlowV2;

export function normalizeTeachingFlow(
  flow: PersistedTeachingFlow,
  lesson: GuidedLessonV2,
): TeachingFlowV2;
```

Persist the question-facing `practiceVariants` in V2 so retries and restored sessions keep the same wording even if the Provider is later updated; answer keys remain server-only in the assessor. For a V1 `FOCUS` snapshot, select the lesson variant matching `flow.practiceId`, falling back to variant zero. For a V1 `REFLECT` snapshot, add the lesson's next options. Never convert a V1 non-mastered snapshot directly to `REFLECT`.

- [ ] **Step 4: Implement exact adaptive transitions**

Extend the event union:

```ts
type GuidedFlowEventV2 =
  | {
      type: 'DIAGNOSTIC_ASSESSED';
      level: GuidedDiagnosticLevelV2;
      repairFocus: string | null;
      materialUsageId?: string;
      occurredAt: string;
    }
  | {
      type: 'ASSET_COMPLETED';
      sourceId: string;
      hintUsed: boolean;
      occurredAt: string;
    }
  | {
      type: 'PRACTICE_ASSESSED';
      sourceId: string;
      verdict: 'MASTERED' | 'PARTIAL' | 'RETRY';
      feedback: string;
      repairFocus: string | null;
      hintUsed: boolean;
      occurredAt: string;
    };
```

Rules:

- `READY_FOR_CHECK` always enters `FOCUS`, never `REFLECT`.
- First `NEEDS_CLARIFICATION` stays in `DIALOGUE`; a second non-ready diagnostic escalates to `ASSET`.
- `NEEDS_TEACHING` enters `ASSET` and requires `materialUsageId`.
- `ASSET_COMPLETED` enters `FOCUS` with the current variant.
- `MASTERED && !hintUsed` records independent evidence and enters `REFLECT` with next options.
- Every other practice result returns to `DIALOGUE`, increments the round and rotates `practiceVariants[attemptRound % length]`.
- Whenever the active variant changes, keep legacy `flow.practiceId` and `currentAction.practiceId` synchronized with `activePractice.id`; V1 Flutter clients must never submit a stale practice ID.

- [ ] **Step 5: Run coordinator tests to verify GREEN**

```powershell
npx vitest run tests/unit/guidedTeachingFlow.test.ts tests/unit/chapterPracticeEngine.test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit the coordinator**

```powershell
git add lib/learning-session/guidedTeachingFlow.ts tests/unit/guidedTeachingFlow.test.ts
git commit -m "feat(prestudy): branch guided lessons by mastery"
```

---

### Task 3: Orchestrate Diagnosis, Repair, Persistence, and Recovery

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/repository.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/memoryRepository.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionService.test.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRepository.test.ts`

**Interfaces:**
- Consumes: Task 1 assessors and Task 2 `PersistedTeachingFlow`/coordinator.
- Produces: complete service paths for known, partial and unknown students; V1/V2 snapshot round-trip and retry-safe evidence persistence.

- [ ] **Step 1: Write failing end-to-end service tests**

Add three service tests:

```ts
it('lets a knowledgeable student skip the asset but not the independent practice', async () => {
  const created = await createGuided('negative-times-negative');
  const focused = await service.submitTurn(created.session.id, {
    exploreSessionId: owner,
    question: '连续两次取相反数回到原方向，同号相乘为正。',
  }, access, 'diagnostic-known');
  expect(focused.teachingFlow).toMatchObject({ stage: 'FOCUS' });
  expect(focused.teachingFlow?.currentAction.type).toBe('REQUEST_MICRO_CHECK');
});

it('teaches an unknown student, repairs a failed answer, then accepts a new variant', async () => {
  const { service } = createService();
  const created = await service.create({
    exploreSessionId: 'explore-repair',
    atomId: 'negative-times-negative',
    scenarioId: 'prestudy',
    flowMode: 'GUIDED_LESSON',
  }, access, 'create-repair');
  const asset = await service.submitTurn(created.session.id, {
    exploreSessionId: 'explore-repair', question: '不知道',
  }, access, 'diagnostic-unknown');
  const materialUsageId = asset.teachingFlow!.currentAction.materialUsageId!;
  const focused = await service.submitMaterialEvent(created.session.id, materialUsageId, {
    exploreSessionId: 'explore-repair', schemaVersion: 1,
    eventId: 'repair-event-1', eventType: 'SIGN_FLIPPED',
    occurredAt: '2026-08-11T02:00:00.000Z', payload: { input: -3, output: 3 },
  }, access);
  const firstPracticeId = focused.teachingFlow!.activePractice.id;
  const repaired = await service.submitPracticeAttempt(created.session.id, {
    exploreSessionId: 'explore-repair', practiceId: firstPracticeId,
    reasoning: '一正一负，所以我猜是负数。', answer: '负数',
  }, access);
  expect(repaired.teachingFlow).toMatchObject({ stage: 'DIALOGUE', attemptRound: 1 });
  expect(repaired.teachingFlow!.activePractice.id).not.toBe(firstPracticeId);
  const refocused = await service.submitTurn(created.session.id, {
    exploreSessionId: 'explore-repair', question: '两个因数都是负数，属于同号，同号相乘为正。',
  }, access, 'repair-answer');
  const reflected = await service.submitPracticeAttempt(created.session.id, {
    exploreSessionId: 'explore-repair', practiceId: refocused.teachingFlow!.activePractice.id,
    reasoning: '两个因数同号，同号相乘为正。', answer: '正数',
  }, access);
  expect(reflected.teachingFlow).toMatchObject({ stage: 'REFLECT' });
  expect(reflected.teachingFlow!.evidence.items.filter(
    (item) => item.strength === 'INDEPENDENT',
  )).toHaveLength(1);
});

it('restores V1 and V2 guided snapshots without losing the current action', async () => {
  const { service, repository } = createService();
  const created = await service.create({
    exploreSessionId: 'explore-restore', atomId: 'negative-times-negative',
    scenarioId: 'prestudy', flowMode: 'GUIDED_LESSON',
  }, access, 'create-restore');
  const stored = repository.sessions.get(created.session.id)!;
  repository.sessions.set(created.session.id, {
    ...stored,
    teachingFlow: { ...stored.teachingFlow!, schemaVersion: 1 } as TeachingFlowV1,
  });
  const restored = await service.get(created.session.id, 'explore-restore', access);
  expect(restored.teachingFlow).toMatchObject({ stage: 'DIALOGUE' });
  expect(restored.teachingFlow?.currentAction.type).toBe('ASK_QUESTION');
});
```

The second test must assert the second practice ID differs from the first and that only the successful attempt creates `INDEPENDENT` evidence.

- [ ] **Step 2: Run service tests to verify RED**

```powershell
npx vitest run tests/unit/learningSessionService.test.ts tests/unit/learningSessionRepository.test.ts
```

Expected: FAIL on the new adaptive branches and V2 persistence typing.

- [ ] **Step 3: Update repository aggregate types**

Change every `teachingFlow` repository boundary from `TeachingFlowV1 | null` to:

```ts
teachingFlow: PersistedTeachingFlow | null;
```

Keep the existing Prisma JSON column and migration unchanged. Both memory and Prisma implementations must preserve unknown V1 fields on reads and write complete V2 JSON atomically with the turn, material event or practice attempt that caused the transition.

- [ ] **Step 4: Integrate diagnostic assessment in `submitTurn`**

When a non-branch turn is submitted while the normalized flow is `DIALOGUE`:

```ts
const diagnostic = assessGuidedDiagnostic({
  atomId: lesson.atomId,
  studentText: input.question,
});
nextFlow = advanceGuidedTeachingFlow(flow, {
  type: 'DIAGNOSTIC_ASSESSED',
  ...diagnostic,
  ...(diagnostic.level === 'NEEDS_TEACHING'
    ? { materialUsageId: selectedGuidedMaterial.id }
    : {}),
  occurredAt: generatedAt.toISOString(),
});
```

Side branches continue using the existing open branch behavior and must not silently advance the main guided stage.

- [ ] **Step 5: Integrate active practice assessment and repair**

Require `input.practiceId === flow.activePractice.id`. Call the expanded `assessChapterPracticeAttempt()`, persist its feedback and `repairFocus`, then pass both into `PRACTICE_ASSESSED`. A retry uses the same idempotency wrapping as today; duplicate mutation keys cannot add a second attempt or rotate the variant twice.

- [ ] **Step 6: Run service and repository tests to verify GREEN**

```powershell
npx vitest run tests/unit/guidedTeachingFlow.test.ts tests/unit/chapterPracticeEngine.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRepository.test.ts
```

Expected: PASS.

- [ ] **Step 7: Commit orchestration and persistence**

```powershell
git add lib/learning-session/sessionService.ts lib/learning-session/repository.ts lib/learning-session/memoryRepository.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRepository.test.ts
git commit -m "feat(prestudy): persist adaptive mastery repair"
```

---

### Task 4: Expose an Audited Chapter Catalog

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/contracts.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/knowledgeProvider.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/mockKnowledgeProvider.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/noKnowledgeProvider.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/remoteKnowledgeProvider.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/http.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/app/api/learning-chapters/route.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningChapterOverview.test.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRoutes.test.ts`

**Interfaces:**
- Consumes: existing chapter overviews and `withLearningApi` route wrapper.
- Produces: `LearningChapterCatalogItemDto`, `KnowledgeProvider.listChapterCatalog()`, `LearningSessionService.listChapterCatalog()` and `GET /api/learning-chapters`.

- [ ] **Step 1: Write failing provider and route tests**

```ts
expect(await new MockKnowledgeProvider().listChapterCatalog()).toEqual([
  expect.objectContaining({ chapterId: 'negative-number-operations', title: '负数运算' }),
  expect.objectContaining({ chapterId: 'chemistry-matter-change', title: '物质变化' }),
  expect.objectContaining({ chapterId: 'physics-force-motion', title: '力与运动' }),
]);

const response = await withLearningApi(api.listChapterCatalog)(request('/api/learning-chapters'));
expect(response.status).toBe(200);
```

- [ ] **Step 2: Run catalog tests to verify RED**

```powershell
npx vitest run tests/unit/learningChapterOverview.test.ts tests/unit/learningSessionRoutes.test.ts
```

Expected: FAIL because catalog contracts and handler are absent.

- [ ] **Step 3: Add the catalog contract and provider boundary**

```ts
export type LearningChapterCatalogItemDto = {
  chapterId: string;
  title: string;
  description: string;
  estimatedMinutes: number;
  availableNodeCount: number;
};

export interface KnowledgeProvider {
  listChapterCatalog(): Promise<LearningChapterCatalogItemDto[]>;
  getChapterOverview(chapterId: string): Promise<LearningChapterOverviewDto | null>;
  getLearningEntry(atomId: string): Promise<LearningEntryDto | null>;
  resolveQuestion(
    question: string,
    studentStage?: string,
    lockedAtomId?: string,
  ): Promise<KnowledgeContext>;
  getAllowedMaterials(context: KnowledgeContext): Promise<KnowledgeMaterial[]>;
}
```

`MockKnowledgeProvider` derives catalog rows from its three registered chapter objects. `NoKnowledgeProvider` and the current remote provider return `[]` until an audited upstream catalog is available; add a Chinese comment explaining why they do not invent content.

- [ ] **Step 4: Add service, HTTP handler and route**

```ts
async listChapterCatalog() {
  return this.knowledgeProvider.listChapterCatalog();
}
```

Expose the handler through the existing API factory and create:

```ts
import { learningSessionApi, withLearningApi } from '@/lib/learning-session/server';

export const GET = withLearningApi(learningSessionApi.listChapterCatalog);
```

- [ ] **Step 5: Run catalog and route tests to verify GREEN**

```powershell
npx vitest run tests/unit/learningChapterOverview.test.ts tests/unit/learningSessionRoutes.test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit the catalog API**

```powershell
git add lib/learning-session/contracts.ts lib/learning-session/knowledgeProvider.ts lib/learning-session/mockKnowledgeProvider.ts lib/learning-session/noKnowledgeProvider.ts lib/learning-session/remoteKnowledgeProvider.ts lib/learning-session/sessionService.ts lib/learning-session/http.ts app/api/learning-chapters/route.ts tests/unit/learningChapterOverview.test.ts tests/unit/learningSessionRoutes.test.ts
git commit -m "feat(prestudy): expose audited chapter catalog"
```

---

### Task 5: Parse V2 Teaching State and Orchestrate Client Navigation

**Files:**
- Modify: `lib/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart`
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`
- Modify: `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`
- Test: `test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`
- Test: `test/features/dialogue_exploration/remote_learning_graph_test.dart`

**Interfaces:**
- Consumes: Tasks 2–4 snapshot and catalog JSON.
- Produces: `RemoteDiagnosticLevel`, `RemoteGuidedPractice`, `RemoteNextLearningOption`, `LearningChapterCatalogItem`, `loadChapterCatalog()`, `selectChapter()` and `startNextLearningOption()`.

- [ ] **Step 1: Write failing DTO and Controller tests**

```dart
expect(flow.schemaVersion, 2);
expect(flow.diagnosticLevel, RemoteDiagnosticLevel.readyForCheck);
expect(flow.activePractice?.prompt, contains('(-7)'));
expect(flow.attemptRound, 1);
expect(flow.nextLearningOptions.first.atomId, 'quadratic-function');

await controller.loadChapterCatalog();
expect(controller.state.chapterCatalog, hasLength(3));
await controller.selectChapter('physics-force-motion');
expect(controller.state.chapter?.chapterId, 'physics-force-motion');

await controller.startNextLearningOption(option);
expect(api.lastCreateAtomId, option.atomId);
expect(api.lastCreateFlowMode, RemoteFlowMode.guidedLesson);
```

Also parse a legacy schema version 1 flow and assert missing V2 fields use `unknown`, `0`, `null` and an empty option list without throwing.

- [ ] **Step 2: Run Flutter unit tests to verify RED**

```powershell
flutter test test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/remote_learning_graph_test.dart
```

Expected: FAIL because V2 and catalog DTOs are absent.

- [ ] **Step 3: Add tolerant DTOs**

```dart
enum RemoteDiagnosticLevel {
  unknown,
  readyForCheck,
  needsClarification,
  needsTeaching;
}

final class RemoteGuidedPractice {
  const RemoteGuidedPractice({
    required this.id,
    required this.title,
    required this.prompt,
    required this.reasoningLabel,
    required this.answerLabel,
  });
  // fromJson uses empty-safe parsing; invalid/missing activePractice becomes null.
}

final class RemoteNextLearningOption {
  const RemoteNextLearningOption({
    required this.atomId,
    required this.chapterId,
    required this.title,
    required this.relation,
    required this.difficultyReason,
    required this.estimatedMinutes,
    required this.hookQuestion,
    required this.prerequisitesSatisfied,
  });
}
```

Extend `RemoteTeachingFlow` with nullable/defaulted V2 fields and keep every current V1 constructor call compiling.

- [ ] **Step 4: Add catalog API and Controller actions**

Extend `RemoteExplorationGateway`:

```dart
Future<List<LearningChapterCatalogItem>> listChapterCatalog();
```

Extend Controller state with immutable `chapterCatalog`. Implement:

```dart
Future<void> loadChapterCatalog();
Future<void> selectChapter(String chapterId) => loadChapter(chapterId);
Future<void> startNextLearningOption(RemoteNextLearningOption option);
```

`startNextLearningOption()` creates a guided session using `option.atomId`, `option.hookQuestion`, the existing `prestudy` scenario and a stable retry closure. It must reject `prerequisitesSatisfied == false` locally without sending a request.

- [ ] **Step 5: Run DTO and Controller tests to verify GREEN**

```powershell
flutter test test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/remote_learning_graph_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit Flutter contracts and Controller**

```powershell
git add lib/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart lib/features/dialogue_exploration/adapters/remote_exploration_api.dart lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/remote_learning_graph_test.dart
git commit -m "feat(prestudy): add adaptive teaching client state"
```

---

### Task 6: Replace the Fixed Chapter Entry With the Provider Catalog

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/chapter_catalog_picker.dart`
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Test: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: Task 5 `chapterCatalog` state and `selectChapter()`.
- Produces: a real chapter selection entry that loads the selected provider outline and preserves history restore.

- [ ] **Step 1: Write failing chapter-entry widget tests**

```dart
expect(find.byKey(const ValueKey('chapter-catalog-picker')), findsOneWidget);
expect(find.text('负数运算'), findsOneWidget);
expect(find.text('物质变化'), findsOneWidget);

await tester.tap(find.byKey(const ValueKey('chapter-catalog-physics-force-motion')));
await tester.pumpAndSettle();
expect(api.lastChapterId, 'physics-force-motion');
expect(find.text('力与运动'), findsWidgets);
```

Add tests for an empty catalog, catalog request failure with retry, and automatic history restoration taking priority over the picker.

- [ ] **Step 2: Run the widget test to verify RED**

```powershell
flutter test test/features/dialogue_exploration/live_tree_page_test.dart
```

Expected: FAIL because startup still hardcodes `negative-number-operations` and the private picker is unused.

- [ ] **Step 3: Implement the focused catalog picker**

```dart
/// 展示服务端已审核章节目录；不在客户端补造课程事实。
final class ChapterCatalogPicker extends StatelessWidget {
  const ChapterCatalogPicker({
    super.key,
    required this.chapters,
    required this.busy,
    required this.onSelect,
  });

  final List<LearningChapterCatalogItem> chapters;
  final bool busy;
  final ValueChanged<String> onSelect;
}
```

Use keys `chapter-catalog-picker` and `chapter-catalog-{chapterId}`. Empty state text is `当前暂无已审核的预习章节`.

- [ ] **Step 4: Integrate startup and outline selection**

Change `_initialize()` to load history first; if no active session was restored, call `loadChapterCatalog()` and show the picker. Remove the unused private subject types and both hardcoded calls to `loadChapter('negative-number-operations')`. After selecting a catalog item, continue using the existing `ChapterOverviewPanel` and node start path.

- [ ] **Step 5: Run chapter-entry tests to verify GREEN**

```powershell
flutter test test/features/dialogue_exploration/live_tree_page_test.dart
```

Expected: PASS for catalog, selection, empty, retry and restore cases.

- [ ] **Step 6: Commit the chapter entry**

```powershell
git add lib/features/dialogue_exploration/presentation/chapter_catalog_picker.dart lib/features/dialogue_exploration/presentation/remote_exploration_page.dart test/features/dialogue_exploration/live_tree_page_test.dart
git commit -m "feat(prestudy): add chapter outline selection"
```

---

### Task 7: Render Mandatory Practice, Repair Feedback, and Next Choices

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/guided_practice_dialog.dart`
- Create: `lib/features/dialogue_exploration/presentation/next_learning_options_sheet.dart`
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `lib/features/dialogue_exploration/presentation/student_learning_narrative.dart`
- Test: `test/features/dialogue_exploration/live_tree_page_test.dart`
- Test: `test/features/dialogue_exploration/student_learning_narrative_test.dart`

**Interfaces:**
- Consumes: Task 5 V2 DTOs and Controller actions.
- Produces: visible question prompt, adaptive repair messaging, mandatory practice for known students and opt-in next-session navigation.

- [ ] **Step 1: Write failing adaptive classroom widget tests**

Add exact cases:

```dart
testWidgets('known student skips asset but still receives the server practice', (tester) async {
  // snapshot is FOCUS with diagnosticLevel READY_FOR_CHECK
  expect(find.byKey(const ValueKey('guided-start-micro-check-button')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('guided-start-micro-check-button')));
  await tester.pumpAndSettle();
  expect(find.text('不计算绝对值，(-7)×(-4) 的结果是正还是负？'), findsOneWidget);
});

testWidgets('failed practice shows repair focus and the next variant', (tester) async {
  expect(find.byKey(const ValueKey('guided-repair-focus')), findsOneWidget);
  expect(find.textContaining('同号'), findsOneWidget);
});

testWidgets('completed lesson offers next learning choices without auto starting', (tester) async {
  expect(find.byKey(const ValueKey('next-learning-options')), findsOneWidget);
  expect(api.createCalls, 0);
  await tester.tap(find.byKey(const ValueKey('next-learning-quadratic-function')));
  await tester.pumpAndSettle();
  expect(api.lastCreateAtomId, 'quadratic-function');
});
```

Also assert a V1 flow still renders, busy state disables duplicate submit, failure keeps the dialog content, and a locked prerequisite cannot be tapped.

- [ ] **Step 2: Run adaptive UI tests to verify RED**

```powershell
flutter test test/features/dialogue_exploration/live_tree_page_test.dart test/features/dialogue_exploration/student_learning_narrative_test.dart
```

Expected: FAIL because the current dialog has no prompt and the summary has no next-choice UI.

- [ ] **Step 3: Implement the guided practice dialog**

```dart
final class GuidedPracticeDraft {
  const GuidedPracticeDraft({required this.reasoning, required this.answer});
  final String reasoning;
  final String answer;
}

/// 题目完全来自服务端快照；弹窗不读取答案或自行判题。
final class GuidedPracticeDialog extends StatefulWidget {
  const GuidedPracticeDialog({super.key, required this.practice});
  final RemoteGuidedPractice practice;
}
```

Render `practice.title`, `practice.prompt`, `reasoningLabel` and `answerLabel`. Disable submit until both normalized fields are non-empty. `_showGuidedPractice()` passes the current `activePractice`; if absent, show a recoverable error instead of opening an empty form.

- [ ] **Step 4: Render repair state and three-round support**

In the guided action panel, show `repairFocus` under key `guided-repair-focus` only when non-empty. For `supportLevel >= 3`, use student copy `我们先完整走一遍例子，再换一道新题由你独立完成。` Do not expose `PARTIAL`, `RETRY`, evidence codes or numeric scores.

- [ ] **Step 5: Implement the next-learning choice sheet**

```dart
final class NextLearningOptionsSheet extends StatelessWidget {
  const NextLearningOptionsSheet({
    super.key,
    required this.options,
    required this.busy,
    required this.onContinue,
    required this.onFinish,
  });
  final List<RemoteNextLearningOption> options;
  final bool busy;
  final ValueChanged<RemoteNextLearningOption> onContinue;
  final VoidCallback onFinish;
}
```

Show title, relation, difficulty reason and estimated minutes. Keys are `next-learning-options` and `next-learning-{atomId}`. The sheet opens after reflection completion; it does not start a session until the student taps an unlocked option. Empty options show `当前暂无已审核的进阶方向` and retain the finish action.

- [ ] **Step 6: Run UI tests to verify GREEN**

```powershell
flutter test test/features/dialogue_exploration/live_tree_page_test.dart test/features/dialogue_exploration/student_learning_narrative_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit adaptive classroom UI**

```powershell
git add lib/features/dialogue_exploration/presentation/guided_practice_dialog.dart lib/features/dialogue_exploration/presentation/next_learning_options_sheet.dart lib/features/dialogue_exploration/presentation/remote_exploration_page.dart lib/features/dialogue_exploration/presentation/student_learning_narrative.dart test/features/dialogue_exploration/live_tree_page_test.dart test/features/dialogue_exploration/student_learning_narrative_test.dart
git commit -m "feat(prestudy): complete adaptive mastery classroom"
```

---

### Task 8: Audit the Existing Pre-study Framework and Complete Verification

**Files:**
- Modify: `docs/PRESTUDY_MODULE_HANDOFF.md`
- Modify: `docs/superpowers/specs/2026-08-11-adaptive-prestudy-mastery-gate-design.md` only if implementation reveals an explicitly approved contract correction.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: an evidence-backed framework handoff covering entry, conversation, material, practice, recovery, completion and next-step behavior.

- [ ] **Step 1: Update the framework handoff**

Document these verified facts with their actual API/DTO names:

```text
章节目录 → 章节大纲 → GUIDED_LESSON 创建
→ DIALOGUE 诊断 → 可选 ASSET → 必经 FOCUS
→ PARTIAL/RETRY 修复与换题 → MASTERED/INDEPENDENT
→ REFLECT/完成 → nextLearningOptions → 新 GUIDED_LESSON 或结束
```

Also document V1 snapshot compatibility, Mock lesson coverage, remote Provider empty-catalog behavior, idempotency and the fact that next-choice does not auto-start.

- [ ] **Step 2: Run focused backend verification**

```powershell
cd D:/ywkeji/Uniprism/UniPrism_New-main
npx vitest run tests/unit/guidedTeachingFlow.test.ts tests/unit/chapterPracticeEngine.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionRoutes.test.ts tests/unit/learningChapterOverview.test.ts
```

Expected: PASS.

- [ ] **Step 3: Run backend schema and type verification**

```powershell
npx prisma validate
npx tsc --noEmit
```

Expected: PASS, or report exact pre-existing unrelated failures separately.

- [ ] **Step 4: Run focused and full Flutter verification**

```powershell
cd D:/dev/Uniprism/uniprism_app
dart analyze lib/main.dart test
flutter test test/features/dialogue_exploration
flutter test
```

Expected: PASS, or report exact pre-existing unrelated failures separately.

- [ ] **Step 5: Review scope and dirty worktrees**

```powershell
git diff --check
git status --short
```

Run in both repositories. Confirm every staged/committed file belongs to this plan and no existing user change was overwritten, deleted or silently reformatted.

- [ ] **Step 6: Commit the handoff documentation**

```powershell
git add docs/PRESTUDY_MODULE_HANDOFF.md
git commit -m "docs(prestudy): verify adaptive mastery framework"
```

If `docs/PRESTUDY_MODULE_HANDOFF.md` lives only in the Flutter repository, commit it there; do not create a duplicate backend copy.

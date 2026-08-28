# Practice Real Adaptive Recommendation V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真实练习提交后由后端基于最新画像、知识掌握、历史和题目难度生成稳定的下一题推荐，并分别向学生 App 和管理端输出最小公开投影与完整脱敏审查明细。

**Architecture:** 复用现有 `adaptive-rule-v1`，新增会话候选提供器和纯推荐快照构建器。提交事务在写入 attempt/画像后读取最新上下文、持久化推荐快照；学生 DTO 白名单剥离内部分数，管理端真实作答审查白名单展示完整快照。Flutter 只保存 DTO 并在学生点击卡片时使用现有题号导航定位。

**Tech Stack:** Next.js 16 / TypeScript / Prisma / Vitest，Flutter 3 / Dart 3.12 / Widget Tests。

## Global Constraints

- 生产推荐只在后端计算；Flutter 请求不得上传能力、知识掌握或权重。
- `displayBand: null` 或 `evidenceCount == 0` 必须映射为未知，不能按 0 档处理。
- 当前候选是会话中的 19 题，当前刚提交题目必须排除。
- 学生 DTO 不返回 `totalScore`、`targetDimension`、知识掌握分、score breakdown 或 risks。
- 管理端真实审查不返回学生身份、会话 ID、答案或过程原文。
- 推荐失败不得留下“attempt 成功但画像/推荐一半写入”的状态；幂等重试读取已存推荐。
- 新增状态、事务、安全投影和失败分支写简洁中文注释。
- 保留所有无关 dirty-worktree 文件，只暂存本计划列出的文件。

---

### Task 1: Build the pure production recommendation adapter

**Files:**
- Modify: backend `lib/practice-assessment/adaptive/contracts.ts`
- Modify: backend `lib/practice-assessment/adaptive/questionDemand.ts`
- Create: backend `lib/practice-assessment/adaptive/sessionRecommendation.ts`
- Create: backend `tests/unit/practiceAdaptiveSessionRecommendation.test.ts`

**Interfaces:**
- Produces: `AdaptiveCandidateProvider`, `CurrentSessionCandidateProvider`, `AdaptiveRecommendationSnapshot`, `buildAdaptiveRecommendationSnapshot(input)` and `projectStudentRecommendation(facts)`.
- Consumes: `recommendPracticeQuestions()` and server-owned question/profile/attempt inputs only.

- [ ] **Step 1: Write the failing pure adapter tests**

Cover these public behaviors with real `demoPracticePaper` data:

```ts
const snapshot = buildAdaptiveRecommendationSnapshot({
  now: '2026-08-13T12:00:00.000Z',
  currentQuestionId: 'q-current',
  fallbackKnowledgePoints: ['函数'],
  profiles: [
    { dimension: 'READING', displayBand: null, evidenceCount: 0 },
    { dimension: 'CALCULATION', displayBand: 2, evidenceCount: 3 },
  ],
  recentAttempts,
  questions,
});
expect(snapshot?.selected.questionId).not.toBe('q-current');
expect(snapshot?.targetDimension).toBe('CALC');
expect(snapshot?.abilities.READ).toBeNull();
expect(snapshot?.knowledgeMastery.targetKnowledgePoint).toBe('函数');
expect(projectStudentRecommendation({ adaptiveRecommendationV1: snapshot }))
  .not.toHaveProperty('totalScore');
```

Also inject a fake `AdaptiveCandidateProvider` and assert the rule uses its candidates unchanged; assert no candidates returns `null`; assert malformed/zero-evidence profiles remain `null`; assert knowledge with no attempt is absent rather than band 0.

- [ ] **Step 2: Run the new test and verify RED**

Run:

```powershell
npm test -- --run tests/unit/practiceAdaptiveSessionRecommendation.test.ts
```

Expected: FAIL because `sessionRecommendation.ts` and the exported interfaces do not exist.

- [ ] **Step 3: Implement exact adapter contracts**

Add to `adaptive/contracts.ts`:

```ts
export type AdaptiveKnowledgeMastery = {
  targetKnowledgePoint: string | null;
  targetBand: number | null;
  evidenceCount: number;
};

export type AdaptiveRecommendationSnapshot = {
  ruleVersion: typeof ADAPTIVE_RULE_VERSION;
  demandVersion: typeof QUESTION_DEMAND_VERSION;
  generatedAt: string;
  targetBucket: AdaptiveBucket;
  targetDimension: CognitionDimension | null;
  abilities: Record<CognitionDimension, number | null>;
  knowledgeMastery: AdaptiveKnowledgeMastery;
  selected: AdaptiveRankedCandidate;
  fallbackReason: string | null;
  risks: string[];
};
```

In `sessionRecommendation.ts`, define the exact server source contracts:

```ts
export type AdaptiveRecommendationProfileSource = {
  dimension: AbilityDimension;
  displayBand: number | null;
  evidenceCount: number;
};

export type AdaptiveRecommendationAttemptSource = {
  questionId: string;
  outcome: AttemptOutcome;
  submittedAt: Date;
  knowledgePoints: unknown;
  structureFamily: string;
};

export type AdaptiveRecommendationQuestionSource = {
  id: string;
  number: number;
  prompt: string;
  type: PracticeQuestionType;
  knowledgePoints: unknown;
  difficultyFeatures: unknown;
  contentDifficulty: unknown;
  rubric: unknown;
};
```

Implement the fixed V1→cognition dimension map, outcome bands `CORRECT=4`, `PARTIALLY_CORRECT=2`, `INCORRECT=0`, and maximum 50 recent attempts. `CurrentSessionCandidateProvider` must parse difficulty/features, safely inspect rubric steps, derive demands, and skip the current question. Invalid candidates are omitted so recommendation cannot make a valid submission fail.

`buildAdaptiveRecommendationSnapshot` must select the weakest observed knowledge point, otherwise use `fallbackKnowledgePoints` as a neutral scope; call `recommendPracticeQuestions`, take only `ranked[0]`, and return `null` when no candidate remains. `projectStudentRecommendation` must runtime-validate the persisted object and return only:

```ts
{
  questionId,
  questionNumber,
  prompt,
  knowledgePoints,
  publicReason,
  ruleVersion,
}
```

Map `TARGET_GAP` to “根据近期学习表现，为你选择了一道针对性练习。”，`CONSOLIDATION` to “这道题适合巩固当前知识。”，`REVIEW_TRANSFER` to “这道题适合复习并验证知识迁移。”

- [ ] **Step 4: Run the pure tests and related selector tests**

```powershell
npm test -- --run tests/unit/practiceAdaptiveSessionRecommendation.test.ts tests/unit/practiceAdaptiveRuleSelector.test.ts
npm run typecheck -- --incremental false
```

Expected: both files PASS and typecheck exits 0.

- [ ] **Step 5: Commit Task 1**

```powershell
git add lib/practice-assessment/adaptive/contracts.ts lib/practice-assessment/adaptive/questionDemand.ts lib/practice-assessment/adaptive/sessionRecommendation.ts tests/unit/practiceAdaptiveSessionRecommendation.test.ts
git commit -m "feat(practice): build real adaptive recommendations"
```

---

### Task 2: Persist recommendation with the attempt and expose the student projection

**Files:**
- Modify: backend `lib/practice-assessment/contracts.ts`
- Modify: backend `lib/practice-assessment/repository.ts`
- Modify: backend `lib/practice-assessment/sessionService.ts`
- Modify: backend `tests/unit/practiceAssessmentService.test.ts`
- Modify: backend `tests/unit/practiceAssessmentProfile.test.ts`
- Modify: backend `tests/unit/practiceAssessmentRoutes.test.ts`

**Interfaces:**
- Consumes: Task 1 `buildAdaptiveRecommendationSnapshot()` and `projectStudentRecommendation()`.
- Produces: `StudentAttemptDto.nextRecommendation`, transactional `getAdaptiveRecommendationContext()` and `updateAttemptFacts()`.

- [ ] **Step 1: Write failing service and transaction tests**

Add a service test whose repository double records call order and returns one zero-evidence profile, one observed profile, recent attempts and 19 candidates. Assert:

```ts
expect(callOrder).toEqual([
  'createAttemptWithObservationsAndProfile',
  'getAdaptiveRecommendationContext',
  'updateAttemptFacts',
]);
expect(response.nextRecommendation?.questionId).not.toBe(currentQuestion.id);
expect(JSON.stringify(response)).not.toMatch(/totalScore|targetDimension|scoreBreakdown|targetBand/);
expect(savedFacts.adaptiveRecommendationV1.abilities.READ).toBeNull();
```

Add an idempotency test where `findAttemptByIdempotencyKey` returns facts containing a recommendation; assert neither context nor update is called and the same public recommendation returns. Add a repository transaction test that asserts both new methods execute on the provided transaction client, not the outer Prisma client.

- [ ] **Step 2: Run backend submission tests and verify RED**

```powershell
npm test -- --run tests/unit/practiceAssessmentService.test.ts tests/unit/practiceAssessmentProfile.test.ts tests/unit/practiceAssessmentRoutes.test.ts
```

Expected: FAIL because attempt DTO and locked repository methods are missing.

- [ ] **Step 3: Extend the repository narrow transaction boundary**

Add to `LockedPracticeSessionRepository`:

```ts
getAdaptiveRecommendationContext(participantId: string): Promise<{
  profiles: PracticeStoredProfile[];
  recentAttempts: AdaptiveRecommendationAttemptSource[];
}>;
updateAttemptFacts(attemptId: string, facts: unknown): ReturnType<
  PrismaPracticeRepository['updateAttemptFacts']
>;
```

The Prisma implementation queries at most 50 attempts where `session.participantId` matches, ordered by `submittedAt desc`, and selects only outcome/time plus question ID/type/knowledge/difficulty metadata. `updateAttemptFacts` updates the JSON facts and re-reads the attempt with observations and rubric. Implement both methods in the locked transaction object using `tx`.

- [ ] **Step 4: Generate and save the snapshot after profile update**

In `submitAttempt`, after `createAttemptWithObservationsAndProfile` returns, call the new context method, build the snapshot using `snapshot.paperVersion.questions`, merge it as `adaptiveRecommendationV1` into the existing facts, call `updateAttemptFacts`, and pass the updated row to `toStudentAttempt`. Existing/duplicate idempotency paths only call `toStudentAttempt` on stored facts.

Add `nextRecommendation: StudentPracticeRecommendationDto | null` to `StudentAttemptDto`; `toStudentAttempt` obtains it only through `projectStudentRecommendation`. App inputs and request schemas remain unchanged.

- [ ] **Step 5: Verify transaction, service, route, and type safety**

```powershell
npm test -- --run tests/unit/practiceAssessmentService.test.ts tests/unit/practiceAssessmentProfile.test.ts tests/unit/practiceAssessmentRoutes.test.ts tests/unit/practiceAdaptiveSessionRecommendation.test.ts
npm run typecheck -- --incremental false
npx eslint lib/practice-assessment/adaptive/sessionRecommendation.ts lib/practice-assessment/repository.ts lib/practice-assessment/sessionService.ts
```

Expected: all tests PASS; typecheck and ESLint exit 0.

- [ ] **Step 6: Commit Task 2**

```powershell
git add lib/practice-assessment/contracts.ts lib/practice-assessment/repository.ts lib/practice-assessment/sessionService.ts tests/unit/practiceAssessmentService.test.ts tests/unit/practiceAssessmentProfile.test.ts tests/unit/practiceAssessmentRoutes.test.ts
git commit -m "feat(practice): persist next question recommendation"
```

---

### Task 3: Show the exact recommendation decision in the admin audit

**Files:**
- Modify: backend `lib/practice-assessment/benchmark/realAttemptReplay.ts`
- Modify: backend `lib/practice-assessment/benchmark/realAttemptAudit.ts`
- Modify: backend `app/admin/practice-benchmark/components/RealAttemptAuditPanel.tsx`
- Modify: backend `tests/unit/practiceRealAttemptAudit.test.ts`
- Modify: backend `tests/unit/practiceRealAttemptAuditPanel.test.ts`
- Modify: backend `tests/unit/practiceRealAttemptRoutes.test.ts`

**Interfaces:**
- Consumes: persisted `adaptiveRecommendationV1` snapshot.
- Produces: nullable `RealAttemptAuditDto.target.recommendation` and the admin “真实推荐决策” block.

- [ ] **Step 1: Write failing audit projection and panel tests**

Add facts to a stored real attempt and assert the audit DTO includes the exact selected question, `totalScore`, seven score fields, target dimension/knowledge and reasons. Assert the serialized DTO still excludes `answerSnapshot`, `reasoningSnapshot`, `sessionId`, `participantId`, and student profile identifiers. Add source/render assertions for labels “真实推荐决策”“命中能力缺口”“知识点掌握”“推荐原因”“风险”。Add a legacy attempt case with no snapshot and assert `recommendation === null`.

- [ ] **Step 2: Run audit tests and verify RED**

```powershell
npm test -- --run tests/unit/practiceRealAttemptAudit.test.ts tests/unit/practiceRealAttemptAuditPanel.test.ts tests/unit/practiceRealAttemptRoutes.test.ts
```

Expected: FAIL because replay rows discard facts and the panel has no recommendation block.

- [ ] **Step 3: Add a strict admin projection**

Add `facts: unknown` to `StoredRealAttempt` and the Prisma row projection. In `projectRealAttemptAudit`, parse only `facts.adaptiveRecommendationV1` through Task 1’s runtime parser and assign it to `target.recommendation`; do not forward the rest of facts. Historical rows return `null`.

Render a `RecommendationDecisionBlock` that shows selected question/score, rule versions, target dimension, knowledge mastery/evidence count, every `AdaptiveScoreBreakdown` item, reasons and risks. The component must not render hidden identity or response fields.

- [ ] **Step 4: Run admin tests and typecheck**

```powershell
npm test -- --run tests/unit/practiceRealAttemptAudit.test.ts tests/unit/practiceRealAttemptAuditPanel.test.ts tests/unit/practiceRealAttemptRoutes.test.ts
npm run typecheck -- --incremental false
```

Expected: all PASS; typecheck exits 0.

- [ ] **Step 5: Commit Task 3**

```powershell
git add lib/practice-assessment/benchmark/realAttemptReplay.ts lib/practice-assessment/benchmark/realAttemptAudit.ts app/admin/practice-benchmark/components/RealAttemptAuditPanel.tsx tests/unit/practiceRealAttemptAudit.test.ts tests/unit/practiceRealAttemptAuditPanel.test.ts tests/unit/practiceRealAttemptRoutes.test.ts
git commit -m "feat(admin): explain real adaptive recommendation"
```

---

### Task 4: Add Flutter recommendation state, navigation, and card

**Files:**
- Modify: `lib/features/practice_assessment/core/practice_models.dart`
- Modify: `lib/features/practice_assessment/adapters/practice_dto_mapper.dart`
- Modify: `lib/features/practice_assessment/adapters/mock_gaokao_math_repository.dart`
- Modify: `lib/features/practice_assessment/application/practice_session_controller.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`
- Modify: `test/features/practice_assessment/remote_practice_repository_test.dart`
- Modify: `test/features/practice_assessment/practice_session_controller_test.dart`
- Modify: `test/features/practice_assessment/practice_assessment_lab_page_test.dart`

**Interfaces:**
- Consumes: backend `nextRecommendation` student DTO.
- Produces: `PracticeNextRecommendation`, `AttemptAssessment.nextRecommendation`, `openCurrentRecommendation()` and `practice-next-recommendation` card.

- [ ] **Step 1: Write failing mapper/controller/widget tests**

Add a DTO test with `nextRecommendation` and unexpected internal keys; assert only public fields map and internal fields have no Dart model destination. Add controller tests asserting submit does not auto-jump, `openCurrentRecommendation()` selects the returned ID, and missing ID leaves the index unchanged with an explicit error. Add widget tests asserting the card appears only after submit, has `practice-open-recommendation`, tapping it changes the displayed question, and the numbered navigator remains visible.

- [ ] **Step 2: Run Flutter tests and verify RED**

```powershell
flutter test test/features/practice_assessment/remote_practice_repository_test.dart test/features/practice_assessment/practice_session_controller_test.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart
```

Expected: FAIL because the recommendation model, controller action and card do not exist.

- [ ] **Step 3: Add the public Flutter model and mapper**

Define immutable `PracticeNextRecommendation` with `questionId`, `questionNumber`, `prompt`, `knowledgePoints`, `publicReason`, `ruleVersion`. Add nullable `nextRecommendation` to `AttemptAssessment` without changing existing constructor call sites. Map only those six keys from `nextRecommendation`; missing/invalid IDs map to `null`.

Mock repository wraps its local assessment with the next numbered question (or the first different question at the end) and public reason “Mock 演示推荐；真实模式由后端画像计算。” This is only for UI testing under the existing Mock banner.

- [ ] **Step 4: Add explicit navigation and card UI**

Implement `openCurrentRecommendation()` by exact question ID lookup. It calls existing `selectQuestion(index)` only when found; otherwise emits failure text “推荐题不在当前会话题库中，请刷新后重试。”

Render `_NextRecommendationCard` after `_AssessmentCard`, showing “推荐下一题”、`第 N 题`、prompt、knowledge chips, public reason and an outlined “进入推荐题” button. Do not display a score, ability dimension or mastery band.

- [ ] **Step 5: Run Flutter tests and analysis**

```powershell
flutter test test/features/practice_assessment/remote_practice_repository_test.dart test/features/practice_assessment/practice_session_controller_test.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart
flutter analyze lib/features/practice_assessment test/features/practice_assessment
```

Expected: all tests PASS; analyze reports no issues.

- [ ] **Step 6: Commit Task 4**

```powershell
git add lib/features/practice_assessment/core/practice_models.dart lib/features/practice_assessment/adapters/practice_dto_mapper.dart lib/features/practice_assessment/adapters/mock_gaokao_math_repository.dart lib/features/practice_assessment/application/practice_session_controller.dart lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart test/features/practice_assessment/remote_practice_repository_test.dart test/features/practice_assessment/practice_session_controller_test.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart
git commit -m "feat(practice): show recommended next question"
```

---

### Task 5: Complete verification and handoff

**Files:**
- Modify: `docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`
- Modify: backend `docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: repeatable Mock/Remote/admin acceptance instructions and current limits.

- [ ] **Step 1: Update handoff documents**

Document the server-only input boundary, stored recommendation snapshot, Mock UI disclaimer, student card flow, admin real recommendation block, knowledge mastery V1 formula, candidate provider replacement contract, and current database blocker without adding credentials.

- [ ] **Step 2: Run full backend gate**

```powershell
$practiceTests = Get-ChildItem tests/unit -Filter 'practice*.test.ts' | ForEach-Object { $_.FullName }
npm test -- --run $practiceTests
npm run typecheck -- --incremental false
```

Expected: all practice files PASS; typecheck exits 0.

- [ ] **Step 3: Run full Flutter gate**

```powershell
flutter test test/features/practice_assessment --reporter expanded
flutter analyze lib/features/practice_assessment test/features/practice_assessment
```

Expected: all practice tests PASS; analyze has no issues.

- [ ] **Step 4: Perform browser smoke**

Restart the current Flutter Web source on 5173 with developer tools and Mock mode, open `/#/practice-assessment-lab`, submit a question, verify the recommendation card appears without auto-jump, click it, then use number navigation back. If an authorized migrated test database is available, repeat in Remote mode and inspect the same attempt in `/admin/practice-benchmark`; otherwise explicitly record Remote persistence as blocked rather than modifying `alphatest`.

- [ ] **Step 5: Commit handoff documents**

Frontend:

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md
git commit -m "docs(practice): hand off adaptive recommendation testing"
```

Backend:

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md
git commit -m "docs(practice): operate adaptive recommendations"
```

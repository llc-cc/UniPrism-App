# Practice Assessment Backend Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将练习评分实验室接入真实 Next.js/MySQL 后端，并先交付可复现的题目六维难度、单次七维能力证据和长期能力画像底层逻辑。

**Architecture:** 后端新增独立 `practice-assessment` 领域，纯函数引擎先生成难度、确定事实、能力观察和画像更新，再由 Prisma Repository 与 HTTP Service 持久化编排。Flutter 保留现有页面和 Controller 边界，新增远程 Repository、匿名身份和事件采集；规则模式是测试默认，混合模式通过同一评分端口可选启用。

**Tech Stack:** Next.js 16、TypeScript、Zod、Prisma 5、MySQL、Vitest、Flutter/Dart、`http`、现有原生 `uniprism/auth_storage` MethodChannel。

## Global Constraints

- 题目难度和人的能力证据必须使用独立输入、实现和数据库派生结果。
- 题目和能力档位均为 `0..4`，但 `INSUFFICIENT_EVIDENCE` 与 `NOT_APPLICABLE` 的 `band` 必须为 `null`。
- 核心能力为阅读、理解、计算、技巧；辅助能力为推理、自我纠错、表达，七项都必须保存。
- 标准答案、完整 rubric、模型提示词、内部置信度和训练标签只保存在服务端。
- 远程失败不能静默回退 Mock；模型失败可以显式回退规则评分且不阻断提交。
- 不创建人工审核队列；自动评分冲突样本直接排除训练候选。
- 训练授权默认关闭；本期不训练或部署真实小模型。
- 当前 19 题均为项目自造演示题，页面和 API 必须如实标识，不得冒充官方真题。
- 所有新增模块、异步流程、状态转换和安全分支写简洁中文注释。
- 每项生产行为先写失败测试并观察 RED，再写最小实现观察 GREEN。

---

## File Map

### Next.js backend: `D:\ywkeji\Uniprism\UniPrism_New-main`

- `lib/practice-assessment/contracts.ts`：枚举、Zod 输入、领域输出和 API DTO。
- `lib/practice-assessment/difficultyEngine.ts`：六维规则先验和综合档位。
- `lib/practice-assessment/factExtractor.ts`：答案规范化、rubric 覆盖和事件事实。
- `lib/practice-assessment/evidenceEngine.ts`：七维证据状态、档位、提示封顶和规则降级。
- `lib/practice-assessment/profileUpdater.ts`：难度映射、在线 theta 和成熟度。
- `lib/practice-assessment/trainingProjector.ts`：授权、冲突与去标识化投影。
- `lib/practice-assessment/demoCatalog.ts`：19 道自造演示题的服务端完整版本。
- `lib/practice-assessment/modelAssessor.ts`：可选 DeepSeek 双评与结构化校验。
- `lib/practice-assessment/repository.ts`：Prisma 读写和事务。
- `lib/practice-assessment/participantAccess.ts`：匿名令牌哈希、Cookie/Bearer 和登录绑定。
- `lib/practice-assessment/sessionService.ts`：会话、草稿、事件、提交、完成和画像编排。
- `lib/practice-assessment/http.ts`：API 校验、CORS、限流、幂等和错误映射。
- `lib/practice-assessment/server.ts`：生产依赖装配。
- `app/api/practice/papers/[paperCode]/route.ts`：读取已发布试卷。
- `app/api/practice/sessions/route.ts`：创建或恢复会话。
- `app/api/practice/sessions/[id]/route.ts`：恢复会话快照。
- `app/api/practice/sessions/[id]/drafts/[questionId]/route.ts`：乐观保存草稿。
- `app/api/practice/sessions/[id]/events/route.ts`：批量写入过程事件。
- `app/api/practice/sessions/[id]/attempts/route.ts`：创建不可变提交。
- `app/api/practice/sessions/[id]/complete/route.ts`：完成整卷。
- `app/api/practice/sessions/[id]/bind/route.ts`：绑定匿名参与者。
- `app/api/practice/ability-profile/route.ts`：读取能力画像。
- `prisma/schema.prisma` 与 `prisma/migrations/20260812_practice_assessment_v1/migration.sql`：练习领域表。
- `scripts/seed-practice-demo-paper.ts`：显式写入演示卷。
- `tests/unit/practiceAssessment*.test.ts`：纯逻辑、持久化契约、身份和 HTTP 测试。

### Flutter: `D:\dev\Uniprism\uniprism_app`

- `lib/features/practice_assessment/core/practice_models.dart`：增加会话、版本、连接和服务端结果字段。
- `lib/features/practice_assessment/core/practice_ports.dart`：远程会话仓储契约。
- `lib/features/practice_assessment/adapters/practice_api_client.dart`：HTTP 与错误解码。
- `lib/features/practice_assessment/adapters/practice_dto_mapper.dart`：学生可见 JSON 映射。
- `lib/features/practice_assessment/adapters/practice_participant_token_store.dart`：原生安全存储/Web Cookie 模式。
- `lib/features/practice_assessment/adapters/practice_event_recorder.dart`：事件聚合与刷新。
- `lib/features/practice_assessment/adapters/remote_practice_repository.dart`：远程仓储实现。
- `lib/features/practice_assessment/application/practice_session_controller.dart`：恢复、草稿保存、事件和完成。
- `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`：连接与会话状态。
- `lib/app_config.dart`、`lib/developer_tools.dart`：显式 Mock/远程开关和装配。
- `test/features/practice_assessment/remote_*.dart`：映射、错误、事件、恢复和页面回归。

---

### Task 1: Backend branch and deterministic question difficulty engine

**Files:**
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\contracts.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\difficultyEngine.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentDifficulty.test.ts`

**Interfaces:**
- Produces: `QuestionDifficultyFeaturesV1`, `QuestionDifficultyProfile`, `calculateQuestionDifficulty(features)`.
- `QuestionDifficultyProfile` fields: `knowledgeLoad`, `readingLoad`, `reasoningLoad`, `calculationLoad`, `techniqueDependency`, `stepDepth`, `overallBand`, `algorithmVersion`.

- [ ] **Step 1: Create and switch the backend feature branch**

```powershell
git switch -c feat/practice-assessment-v1-backend
```

- [ ] **Step 2: Write failing difficulty tests**

```ts
it('maps a reproducible feature vector to six bands and one weighted overall band', () => {
  expect(calculateQuestionDifficulty({
    knowledgePointCount: 3,
    maxPrerequisiteDepth: 2,
    crossTopicLinkCount: 1,
    hasAbstractConcept: true,
    effectiveChineseCharCount: 180,
    explicitConditionCount: 3,
    implicitConditionCount: 1,
    representationTransformCount: 1,
    requiredInferenceEdgeCount: 4,
    caseBranchCount: 1,
    requiresConstruction: false,
    requiresBidirectionalProof: false,
    symbolicOperationCount: 4,
    errorProneTransformCount: 1,
    numericScaleLevel: 1,
    nonRoutinePatternCount: 1,
    requiresSpecialConstruction: true,
    routineMethodExceedsTimeBudget: false,
    longestRequiredStepPath: 4,
  })).toMatchObject({
    knowledgeLoad: 3,
    readingLoad: 3,
    reasoningLoad: 3,
    calculationLoad: 3,
    techniqueDependency: 2,
    stepDepth: 3,
    overallBand: 3,
    algorithmVersion: 'difficulty-rule-v1',
  });
});

it('rejects a cyclic rubric dependency graph before publication', () => {
  expect(() => assertAcyclicRequiredSteps([
    { id: 's1', dependsOn: ['s2'] },
    { id: 's2', dependsOn: ['s1'] },
  ])).toThrow('rubric 必要步骤存在环');
});
```

- [ ] **Step 3: Run RED**

Run: `npm test -- --run tests/unit/practiceAssessmentDifficulty.test.ts`
Expected: FAIL because `difficultyEngine.ts` does not exist.

- [ ] **Step 4: Implement contracts and pure rules**

```ts
export const DIFFICULTY_RULE_VERSION = 'difficulty-rule-v1';

export type QuestionDifficultyProfile = {
  knowledgeLoad: number;
  readingLoad: number;
  reasoningLoad: number;
  calculationLoad: number;
  techniqueDependency: number;
  stepDepth: number;
  overallBand: number;
  algorithmVersion: typeof DIFFICULTY_RULE_VERSION;
};

const rawBand = (raw: number) => raw <= 1 ? 0 : raw <= 3 ? 1 : raw <= 5 ? 2 : raw <= 8 ? 3 : 4;
const stepBand = (depth: number) => depth <= 1 ? 0 : depth === 2 ? 1 : depth === 3 ? 2 : depth <= 5 ? 3 : 4;
```

Implement every formula exactly as section 6 of the approved design and validate all counters with Zod non-negative integers.

- [ ] **Step 5: Run GREEN and typecheck**

Run: `npm test -- --run tests/unit/practiceAssessmentDifficulty.test.ts`
Run: `npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit backend Task 1**

```powershell
git add lib/practice-assessment/contracts.ts lib/practice-assessment/difficultyEngine.ts tests/unit/practiceAssessmentDifficulty.test.ts
git commit -m "feat(practice): calculate deterministic question difficulty"
```

---

### Task 2: Attempt facts, seven-dimensional evidence, profile updates and training projection

**Files:**
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\factExtractor.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\evidenceEngine.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\profileUpdater.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\trainingProjector.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentEvidence.test.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentProfile.test.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentTraining.test.ts`

**Interfaces:**
- Consumes: Task 1 contracts and `QuestionDifficultyProfile`.
- Produces: `extractAttemptFacts(input)`, `assessAttemptWithRules(input)`, `updateAbilityProfile(input)`, `projectTrainingCandidate(input)`.
- Ability observation invariant: `OBSERVED` has `band 0..4`; other statuses have `band: null`.

- [ ] **Step 1: Write failing evidence tests**

```ts
it('does not turn a correct final answer without process into understanding evidence', () => {
  const result = assessAttemptWithRules(answerOnlyFixture);
  expect(result.outcome).toBe('CORRECT');
  expect(result.observations.understanding).toMatchObject({
    status: 'INSUFFICIENT_EVIDENCE',
    band: null,
  });
});

it('caps solution-hint evidence at band two and preserves self-correction facts', () => {
  const result = assessAttemptWithRules(solutionHintCorrectionFixture);
  expect(result.observations.reasoning.band).toBeLessThanOrEqual(2);
  expect(result.observations.selfCorrection.factCodes).toContain('SELF_CORRECTED');
});
```

- [ ] **Step 2: Write failing profile and projector tests**

```ts
it('moves theta more for success on a hard item than a simple item', () => {
  const hard = updateAbilityProfile(profileAtZero, observedBand3, hardDifficulty);
  const easy = updateAbilityProfile(profileAtZero, observedBand3, easyDifficulty);
  expect(hard.theta).toBeGreaterThan(easy.theta);
});

it('does not update a profile from insufficient evidence', () => {
  expect(updateAbilityProfile(profileAtZero, insufficient, hardDifficulty)).toEqual(profileAtZero);
});

it('rejects a training candidate without explicit consent or with model conflict', () => {
  expect(projectTrainingCandidate({ ...fixture, trainingConsentVersion: null })).toMatchObject({ status: 'REJECTED_NO_CONSENT' });
  expect(projectTrainingCandidate({ ...fixture, hasAssessmentConflict: true })).toMatchObject({ status: 'REJECTED_CONFLICT' });
});
```

- [ ] **Step 3: Run RED**

Run: `npm test -- --run tests/unit/practiceAssessmentEvidence.test.ts tests/unit/practiceAssessmentProfile.test.ts tests/unit/practiceAssessmentTraining.test.ts`
Expected: FAIL because the engines do not exist.

- [ ] **Step 4: Implement deterministic facts and evidence**

Implement answer normalization by question type, rubric dependency coverage, the ordered evidence state rules, hint caps and self-correction rules from sections 7.2–7.5. Every observation includes `confidence`, `evidenceStepIds`, `factCodes`, `errorTags`, `assessorVersion`, and `rubricVersion`.

```ts
export type AbilityObservation = {
  dimension: AbilityDimension;
  status: EvidenceStatus;
  band: number | null;
  confidence: number;
  evidenceStepIds: string[];
  factCodes: string[];
  errorTags: string[];
  assessorVersion: string;
  rubricVersion: string;
};
```

- [ ] **Step 5: Implement profile update and training filter**

Use the approved ability-to-difficulty mapping, performance probabilities, `thetaNext` formula, evidence quality values and repeat penalties. `projectTrainingCandidate` removes every identity/session field and returns a rejection status instead of throwing for ineligible data.

- [ ] **Step 6: Run GREEN**

Run: `npm test -- --run tests/unit/practiceAssessmentEvidence.test.ts tests/unit/practiceAssessmentProfile.test.ts tests/unit/practiceAssessmentTraining.test.ts`
Expected: PASS.

- [ ] **Step 7: Commit backend Task 2**

```powershell
git add lib/practice-assessment tests/unit/practiceAssessmentEvidence.test.ts tests/unit/practiceAssessmentProfile.test.ts tests/unit/practiceAssessmentTraining.test.ts
git commit -m "feat(practice): derive ability evidence and profiles"
```

---

### Task 3: Prisma schema, migration, demo catalog and repository

**Files:**
- Modify: `D:\ywkeji\Uniprism\UniPrism_New-main\prisma\schema.prisma`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\prisma\migrations\20260812_practice_assessment_v1\migration.sql`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\demoCatalog.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\repository.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\scripts\seed-practice-demo-paper.ts`
- Modify: `D:\ywkeji\Uniprism\UniPrism_New-main\package.json`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentMigration.test.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentCatalog.test.ts`

**Interfaces:**
- Consumes: Tasks 1–2 contracts.
- Produces: ten Prisma models from design section 10 plus `PrismaPracticeRepository` methods used by Task 4.

- [ ] **Step 1: Write failing migration and catalog tests**

```ts
it('defines all practice tables with attempt and event idempotency constraints', () => {
  expect(schema).toMatch(/model PracticeParticipant/);
  expect(schema).toMatch(/model PracticeAbilityProfile/);
  expect(migration).toContain('UNIQUE INDEX `practice_events_sessionId_clientEventId_key`');
  expect(migration).toContain('UNIQUE INDEX `practice_attempts_sessionId_questionVersionId_attemptNumber_key`');
});

it('publishes exactly 19 demonstration questions with the gaokao structure', () => {
  expect(demoPaper.questions.map((item) => item.type)).toEqual([
    ...Array(8).fill('SINGLE_CHOICE'),
    ...Array(3).fill('MULTIPLE_CHOICE'),
    ...Array(3).fill('FILL_BLANK'),
    ...Array(5).fill('SOLUTION'),
  ]);
  expect(demoPaper.source).toBe('DEMONSTRATION');
});
```

- [ ] **Step 2: Run RED**

Run: `npm test -- --run tests/unit/practiceAssessmentMigration.test.ts tests/unit/practiceAssessmentCatalog.test.ts`
Expected: FAIL because schema, migration and catalog are absent.

- [ ] **Step 3: Add schema and SQL migration**

Add `PracticeParticipant`, `PracticePaperVersion`, `PracticeQuestionVersion`, `PracticeSession`, `PracticeQuestionProgress`, `PracticeEvent`, `PracticeAttempt`, `PracticeAbilityObservation`, `PracticeAbilityProfile`, and `PracticeDifficultyCalibration` exactly as section 10 specifies. Add `practiceParticipants PracticeParticipant[]` to `User`.

Create explicit MySQL SQL for tables, foreign keys, cascading rules, unique keys and query indexes. Do not execute migration against production.

- [ ] **Step 4: Add demo catalog and seed command**

Move the 19 self-authored prompts into a backend catalog with complete server-only answers, rubric dependencies and `QuestionDifficultyFeaturesV1`. Add:

```json
"practice:seed:demo": "tsx scripts/seed-practice-demo-paper.ts"
```

The seed uses `(paperCode, contentVersion)` and `(paperVersionId, questionCode)` upserts and verifies the resulting count is 19.

- [ ] **Step 5: Implement Prisma repository**

Expose focused methods: `findPublishedPaper`, `createParticipant`, `findParticipantByTokenHash`, `createOrResumeSession`, `getSessionSnapshot`, `saveDraft`, `appendEvents`, `createAttemptWithObservationsAndProfile`, `completeSession`, `bindParticipant`, and `getAbilityProfile`.

- [ ] **Step 6: Run GREEN and Prisma validation**

Run: `npm test -- --run tests/unit/practiceAssessmentMigration.test.ts tests/unit/practiceAssessmentCatalog.test.ts`
Run: `npx prisma format`
Run: `npx prisma validate`
Run: `npm run db:generate`
Run: `npm run typecheck`
Expected: all PASS without applying the migration.

- [ ] **Step 7: Commit backend Task 3**

```powershell
git add prisma lib/practice-assessment/demoCatalog.ts lib/practice-assessment/repository.ts scripts/seed-practice-demo-paper.ts package.json tests/unit/practiceAssessmentMigration.test.ts tests/unit/practiceAssessmentCatalog.test.ts
git commit -m "feat(practice): persist versioned assessment data"
```

---

### Task 4: Participant access, session service and HTTP API

**Files:**
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\participantAccess.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\sessionService.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\http.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\server.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\papers\[paperCode]\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\sessions\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\sessions\[id]\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\sessions\[id]\drafts\[questionId]\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\sessions\[id]\events\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\sessions\[id]\attempts\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\sessions\[id]\complete\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\sessions\[id]\bind\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\practice\ability-profile\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentAccess.test.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentService.test.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentRoutes.test.ts`

**Interfaces:**
- Consumes: `PrismaPracticeRepository`, deterministic engines and current `withApiHandler`, `assertSafeMutationRequest`, rate-limit utilities.
- Produces: API routes from design section 11 with standard `{ok,data}` / `{ok:false,error}` envelopes.

- [ ] **Step 1: Write failing access tests**

```ts
it('stores only a sha256 token hash and accepts the raw token once', async () => {
  const issued = await access.issueAnonymousParticipant();
  expect(issued.rawToken).toHaveLength(43);
  expect(repository.created.anonymousTokenHash).not.toContain(issued.rawToken);
});

it('binds once to the authenticated user and rejects another account', async () => {
  await access.bindParticipant(participant, 'user-1');
  await expect(access.bindParticipant(participant, 'user-2')).rejects.toMatchObject({ status: 409 });
});
```

- [ ] **Step 2: Write failing service and route tests**

Test create/resume, draft version conflicts, event deduplication, maximum three attempts, idempotent submit, all-question completion, answer/rubric redaction, CORS credentials and unified errors.

- [ ] **Step 3: Run RED**

Run: `npm test -- --run tests/unit/practiceAssessmentAccess.test.ts tests/unit/practiceAssessmentService.test.ts tests/unit/practiceAssessmentRoutes.test.ts`
Expected: FAIL because access/service/routes are absent.

- [ ] **Step 4: Implement participant access**

Native clients use `Authorization: PracticeParticipant <token>`; Web uses `uniprism_practice_participant` HttpOnly cookie. Logged-in access uses existing `auth()` or mini-app bearer auth. Bind rotates anonymous credentials and never accepts a request-body user ID.

- [ ] **Step 5: Implement service transactions**

`submitAttempt` loads server draft and rubric, extracts facts, assesses evidence, updates profile in one transaction, and returns a redacted student result. The same idempotency key returns the same attempt. A model failure is a successful rules submission with a `RULE_FALLBACK` code.

- [ ] **Step 6: Implement HTTP and thin routes**

Use Zod sizes from design section 11, `assertSafeMutationRequest`, exact Flutter origins, credentials CORS, per-participant and per-IP limits, and current API envelope. Add `OPTIONS` for browser routes.

- [ ] **Step 7: Run GREEN**

Run: `npm test -- --run tests/unit/practiceAssessmentAccess.test.ts tests/unit/practiceAssessmentService.test.ts tests/unit/practiceAssessmentRoutes.test.ts`
Expected: PASS.

- [ ] **Step 8: Commit backend Task 4**

```powershell
git add lib/practice-assessment app/api/practice tests/unit/practiceAssessmentAccess.test.ts tests/unit/practiceAssessmentService.test.ts tests/unit/practiceAssessmentRoutes.test.ts
git commit -m "feat(practice): expose persistent assessment API"
```

---

### Task 5: Optional structured model double assessment with rules fallback

**Files:**
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\modelAssessor.ts`
- Modify: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\practice-assessment\server.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\practiceAssessmentModelAssessor.test.ts`

**Interfaces:**
- Consumes: `callDeepSeekJson`, deterministic facts, rubric and assessment contracts.
- Produces: `HybridQuestionDifficultyAssessor` and `HybridAttemptAssessor`; `PRACTICE_ASSESSOR_MODE=rules|hybrid` selects implementation.

- [ ] **Step 1: Write failing model tests**

```ts
it('accepts two blind structured observations that agree within one band', async () => {
  const result = await assessor.assess(input);
  expect(result.mode).toBe('HYBRID_CONSENSUS');
});

it('keeps the rule prior when two blind question-difficulty assessments conflict', async () => {
  const result = await conflictingDifficultyAssessor.assess(questionInput);
  expect(result.mode).toBe('RULE_FALLBACK');
  expect(result.profile).toEqual(ruleDifficulty);
  expect(result.trainingEligible).toBe(false);
});

it('falls back per dimension when the blind assessments conflict', async () => {
  const result = await conflictingAssessor.assess(input);
  expect(result.observations.reasoning.factCodes).toContain('RULE_FALLBACK');
});

it('does not fail submission when the provider times out', async () => {
  await expect(timeoutAssessor.assess(input)).resolves.toMatchObject({ mode: 'RULE_FALLBACK' });
});
```

- [ ] **Step 2: Run RED**

Run: `npm test -- --run tests/unit/practiceAssessmentModelAssessor.test.ts`
Expected: FAIL because `HybridAttemptAssessor` is absent.

- [ ] **Step 3: Implement two blind calls and verifier**

Use Zod structured outputs. The second call receives the same canonical inputs but never the first result. Reject nonexistent evidence steps, non-null bands for non-observed states, bands outside `0..4`, differences above one and facts contradicted by deterministic extraction.

- [ ] **Step 4: Run GREEN and commit**

Run: `npm test -- --run tests/unit/practiceAssessmentModelAssessor.test.ts`
Expected: PASS without a network call because tests inject a model client.

```powershell
git add lib/practice-assessment/modelAssessor.ts lib/practice-assessment/server.ts tests/unit/practiceAssessmentModelAssessor.test.ts
git commit -m "feat(practice): verify structured ability assessments"
```

---

### Task 6: Flutter remote DTO, API client, identity token and event recorder

**Files:**
- Modify: `lib/features/practice_assessment/core/practice_models.dart`
- Modify: `lib/features/practice_assessment/core/practice_ports.dart`
- Create: `lib/features/practice_assessment/adapters/practice_api_client.dart`
- Create: `lib/features/practice_assessment/adapters/practice_dto_mapper.dart`
- Create: `lib/features/practice_assessment/adapters/practice_participant_token_store.dart`
- Create: `lib/features/practice_assessment/adapters/practice_event_recorder.dart`
- Create: `lib/features/practice_assessment/adapters/remote_practice_repository.dart`
- Create: `test/features/practice_assessment/remote_practice_repository_test.dart`
- Create: `test/features/practice_assessment/practice_event_recorder_test.dart`

**Interfaces:**
- Consumes: backend API Task 4.
- Produces: `RemotePracticeRepository`, `PracticeEventRecorder`, and expanded repository contract used by Task 7.

- [ ] **Step 1: Write failing DTO and repository tests**

```dart
test('maps a redacted remote paper without requiring answer or rubric fields', () async {
  final paper = await repository.loadPaper();
  expect(paper.questions, hasLength(19));
  expect(paper.contentVersion, 'demo-v1');
});

test('surfaces request id and never switches to mock after a remote failure', () async {
  await expectLater(repository.loadPaper(), throwsA(isA<PracticeApiException>()
    .having((e) => e.requestId, 'requestId', 'req_test')));
});
```

- [ ] **Step 2: Write failing event tests**

Test 5-second aggregation, batches of at most 50, length-only change metadata, submit-before-flush ordering, failed-batch retention and idempotent `clientEventId`.

- [ ] **Step 3: Run RED**

Run: `flutter test test/features/practice_assessment/remote_practice_repository_test.dart test/features/practice_assessment/practice_event_recorder_test.dart`
Expected: FAIL because remote classes are absent.

- [ ] **Step 4: Implement API client and token store**

The client uses a 15-second timeout, JSON envelopes, exact request IDs, credentials on Web and `PracticeParticipant` token on native. `PracticeParticipantTokenStore` uses `uniprism/auth_storage` for native and no JS-readable token on Web.

- [ ] **Step 5: Implement mapper, event recorder and remote repository**

Expand the repository with `loadOrCreateSession`, `saveDraft`, `recordEvents`, `submitAttempt`, `completeSession`, `bindSession`, and `loadAbilityProfile`. Preserve the Mock implementation using in-memory versions of the same methods.

- [ ] **Step 6: Run GREEN**

Run: `dart analyze lib/features/practice_assessment test/features/practice_assessment`
Run: `flutter test test/features/practice_assessment/remote_practice_repository_test.dart test/features/practice_assessment/practice_event_recorder_test.dart`
Expected: no issues and PASS.

- [ ] **Step 7: Commit Flutter Task 6**

```powershell
git add lib/features/practice_assessment test/features/practice_assessment
git commit -m "feat(practice): add remote assessment repository"
```

---

### Task 7: Flutter session recovery, remote laboratory and user-visible testing state

**Files:**
- Modify: `lib/features/practice_assessment/application/practice_session_controller.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`
- Modify: `lib/features/practice_assessment/practice_assessment.dart`
- Modify: `lib/app_config.dart`
- Modify: `lib/developer_tools.dart`
- Modify: `test/features/practice_assessment/practice_session_controller_test.dart`
- Modify: `test/features/practice_assessment/practice_assessment_lab_page_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: Task 6 remote repository and recorder.
- Produces: a manually testable remote practice lab with explicit Mock/remote configuration.

- [ ] **Step 1: Write failing controller recovery tests**

```dart
test('load restores server drafts, results and current question', () async {
  await controller.load();
  expect(controller.state.sessionId, 'practice-session-1');
  expect(controller.state.currentIndex, 4);
  expect(controller.state.drafts['q5']?.answer, 'B');
});

test('submission flushes events and saves the latest draft first', () async {
  await controller.submitCurrent();
  expect(repository.calls, ['saveDraft', 'flushEvents', 'submitAttempt']);
});
```

- [ ] **Step 2: Write failing page/config tests**

Verify the lab shows `后端已连接`, paper/rule/session versions, remote request IDs on errors, restored progress, and an explicit `演示 Mock` label only in Mock mode.

- [ ] **Step 3: Run RED**

Run: `flutter test test/features/practice_assessment/practice_session_controller_test.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart test/widget_test.dart`
Expected: FAIL because remote state is not implemented.

- [ ] **Step 4: Implement recovery and ordered writes**

Add loading generations and dispose guards to every async callback. Save drafts with optimistic versions, record view/start/change/revisit events, flush before submit, and keep drafts/events after network failure.

- [ ] **Step 5: Implement explicit configuration and UI**

Add compile-time `PRACTICE_ASSESSMENT_REMOTE=true|false`. Developer Tools constructs `RemotePracticeRepository` only when true; otherwise it constructs Mock and labels it. Remote failure stays remote and provides retry.

- [ ] **Step 6: Run GREEN and regression**

Run: `dart analyze lib/main.dart lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment test/widget_test.dart`
Run: `flutter test test/features/practice_assessment test/widget_test.dart test/developer_tools_web_test.dart`
Expected: tests PASS; any existing `main.dart` info diagnostics are recorded separately from new-module diagnostics.

- [ ] **Step 7: Commit Flutter Task 7**

```powershell
git add lib/app_config.dart lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment test/widget_test.dart
git commit -m "feat(practice): connect assessment lab to backend"
```

---

### Task 8: Verification, local launch guide and handoff

**Files:**
- Modify: `docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\docs\PRACTICE_ASSESSMENT_V1_OPERATIONS.md`

**Interfaces:**
- Consumes: complete backend and Flutter implementation.
- Produces: exact database, backend, Flutter and manual test commands.

- [ ] **Step 1: Verify backend**

```powershell
npx prisma format
npx prisma validate
npm run db:generate
npm run typecheck
npm test -- --run tests/unit/practiceAssessment*.test.ts
npm run build
```

Expected: all commands exit 0.

- [ ] **Step 2: Verify Flutter**

```powershell
dart analyze lib/features/practice_assessment test/features/practice_assessment
flutter test
```

Expected: new module has no analyzer issues and full Flutter suite passes.

- [ ] **Step 3: Validate separation and diffs**

```powershell
rg -n "dialogue_exploration|learning-session" lib/features/practice_assessment test/features/practice_assessment
git diff --check
```

Expected: no direct pre-study module imports and no whitespace errors.

- [ ] **Step 4: Write exact local test guide**

Document test database backup/migration, `npm run practice:seed:demo`, `PRACTICE_ASSESSOR_MODE=rules npm run dev`, Flutter `API_BASE_URL`, `PRACTICE_ASSESSMENT_REMOTE=true`, anonymous recovery, failure retry and optional hybrid checks. Include a non-production test-data reset command that requires an explicit database URL guard.

- [ ] **Step 5: Commit both handoffs in their respective repositories**

Backend:

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md
git commit -m "docs(practice): document backend assessment testing"
```

Flutter:

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md
git commit -m "docs(practice): document remote assessment testing"
```

- [ ] **Step 6: Report branch state without merging or pushing**

Report both branch names, commit lists, verification evidence, database changes and known limitations. Leave integration choice to the user.

# 1.2 Dialogue Exploration Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在现有 Next.js 后端实现可供 Flutter App 与 Flutter Web 共用的正式 1.2 学习 Session 服务；除 1.1 知识库与素材目录使用 Mock Provider 外，其余会话、AI、评估、树、总结、证据和记忆候选链路全部落库并可联调。

**Architecture:** API Route 只负责鉴权、校验、限流和 CORS；`LearningSessionService` 负责编排；`TeachingEngine` 负责策略选择、DeepSeek 结构化生成、反问质量复核与确定性兜底；MySQL 是事实源，Redis 仅保存 15 分钟运行态、幂等结果和短锁。知识来源经 `KnowledgeProvider` 接口隔离，当前注入 `MockKnowledgeProvider`，未来替换 1.1 Provider 不改会话主流程。

**Tech Stack:** Next.js 16 App Router、TypeScript、Prisma 5/MySQL、ioredis、Zod 4、DeepSeek JSON API、Vitest。

## Global Constraints

- 后端仓库：`D:\ywkeji\Uniprism\UniPrism_New-main`。
- 从 `feature/app-support` 创建 `feature/dialogue-exploration-1-2-backend`，不提交 `.idea/`。
- 先写失败测试，再写最少实现，再运行对应测试；每个任务完成后只提交该任务文件。
- 新模块、状态机、异步容错、鉴权和数据安全分支写简洁中文注释，解释原因与边界。
- 客户端只提交 `exploreSessionId`，服务端用 `assertSessionAccess` 推导 `userId/anonymousId`，绝不信任客户端 user ID。
- 硬限制统一为：10 分钟、20 个思维节点、深度 5、单节点子分支 3、单轮素材 2。
- DeepSeek 输出必须经过 Zod、素材白名单和反问质量评估；两次修正仍不合格时使用服务端确定性反问，不把低质量内容直接交给学生。
- Redis 不可用时降级到 MySQL；MySQL 写入失败时不得只返回 Redis 中的“成功”。
- 所有修改请求支持 `Idempotency-Key`；同一会话写操作使用短锁，避免 App/Web 双端重复生成节点。

---

## Task 1: 建立分支、学习域契约与 Mock 知识 Provider

**Files:**

- Create: `lib/learning-session/contracts.ts`
- Create: `lib/learning-session/knowledgeProvider.ts`
- Create: `lib/learning-session/mockKnowledgeProvider.ts`
- Test: `tests/unit/learningSessionContracts.test.ts`
- Test: `tests/unit/learningSessionKnowledgeProvider.test.ts`

**Step 1: 创建隔离分支并确认工作区**

Run:

```powershell
git switch feature/app-support
git switch -c feature/dialogue-exploration-1-2-backend
git status --short
```

Expected: 当前分支为新分支，仅显示既有未跟踪 `.idea/`，不修改或提交它们。

**Step 2: 先写契约失败测试**

测试固定以下行为：

```ts
expect(learningSessionLimits).toEqual({
  durationSeconds: 600,
  maxNodes: 20,
  maxDepth: 5,
  maxChildrenPerNode: 3,
  maxMaterialsPerTurn: 2,
});

expect(createLearningSessionSchema.safeParse({
  exploreSessionId: 'exp_1',
  entryType: 'QUESTION',
  question: '为什么负负得正？',
  scenarioId: 'negative-times-negative',
}).success).toBe(true);
```

同时覆盖空问题、超过 500 字、非法入口、客户端夹带 `userId` 和非法幂等键。

**Step 3: 运行测试确认失败**

Run: `npm test -- --run tests/unit/learningSessionContracts.test.ts tests/unit/learningSessionKnowledgeProvider.test.ts`

Expected: FAIL，模块尚不存在。

**Step 4: 实现稳定枚举、Zod Schema 与 Provider 接口**

`contracts.ts` 导出以下核心定义：

```ts
export const learningSessionLimits = {
  durationSeconds: 10 * 60,
  maxNodes: 20,
  maxDepth: 5,
  maxChildrenPerNode: 3,
  maxMaterialsPerTurn: 2,
} as const;

export const teachingStrategySchema = z.enum([
  'QUESTION_CHAIN',
  'SOCRATIC',
  'ERROR_TRACKING',
  'ANALOGY_TRANSFER',
  'SELF_EXPLANATION',
]);

export const createLearningSessionSchema = z.object({
  exploreSessionId: z.string().min(1).max(191),
  entryType: z.enum(['ATOM', 'QUESTION']),
  scenarioId: z.string().min(1).max(100),
  atomId: z.string().max(191).optional(),
  question: z.string().trim().min(1).max(500),
  studentStage: z.string().trim().max(50).optional(),
}).strict();
```

另外定义 `KnowledgeContext`、`KnowledgeMaterial`、`TurnGeneration`、`QuestionEvaluationResult`、`SessionSnapshot` 和各 API 输入 Schema。接口保持知识库可替换：

```ts
export interface KnowledgeProvider {
  getScenario(scenarioId: string): Promise<KnowledgeContext | null>;
  resolveQuestion(question: string, studentStage?: string): Promise<KnowledgeContext>;
  listAllowedMaterials(context: KnowledgeContext): Promise<KnowledgeMaterial[]>;
}
```

**Step 5: 实现四个可完整演示的 Mock 场景**

`mockKnowledgeProvider.ts` 固定提供：

- `negative-times-negative`：负负得正，数轴图、规律公式卡、符号翻转交互。
- `quadratic-vertex`：二次函数顶点，抛物线图、可拖动参数交互、配方法推导卡。
- `inequality-proof`：证明不等式，条件公式卡、错误路径对比图、步骤重排交互。
- `coffee-business-model`：咖啡店怎么赚钱，商业画布图、成本结构短视频、单位经济交互、公式卡。

每个素材包含 `id/type/title/payload/atomId/relationScope`；`listAllowedMaterials` 只返回当前原子及 `PREREQUISITE_OF/COMPARED_WITH/APPLIED_IN` 邻边覆盖素材。

**Step 6: 运行测试并提交**

Run: `npm test -- --run tests/unit/learningSessionContracts.test.ts tests/unit/learningSessionKnowledgeProvider.test.ts`

Expected: PASS。

Commit:

```powershell
git add lib/learning-session/contracts.ts lib/learning-session/knowledgeProvider.ts lib/learning-session/mockKnowledgeProvider.ts tests/unit/learningSessionContracts.test.ts tests/unit/learningSessionKnowledgeProvider.test.ts
git commit -m "feat(learning): add dialogue contracts and mock knowledge provider"
```

---

## Task 2: 实现教学策略、节点约束与反问质量评估

**Files:**

- Create: `lib/learning-session/strategyEngine.ts`
- Create: `lib/learning-session/questionEvaluator.ts`
- Create: `lib/learning-session/fallbackQuestion.ts`
- Test: `tests/unit/learningSessionStrategyEngine.test.ts`
- Test: `tests/unit/learningSessionQuestionEvaluator.test.ts`

**Step 1: 写策略优先级与限制失败测试**

覆盖：已收口/到期 → 自我解释；确认错误 → 错误追踪；“不懂/太抽象” → 类比迁移；首轮 → 问题链；其余 → 苏格拉底。错误证据必须优先于普通追问，但硬限制收口优先于错误追踪。

```ts
expect(selectTeachingStrategy({ ...base, consecutiveErrors: 2 }).strategy)
  .toBe('ERROR_TRACKING');
expect(selectTeachingStrategy({ ...base, nodeCount: 20 }).strategy)
  .toBe('SELF_EXPLANATION');
```

评估测试覆盖五维各 0–5、总分 25、阈值 18；`你觉得呢`、`为什么呢`、`还有吗` 必须失败；“这一步用了哪个结论，它成立需要什么条件？”必须通过。

**Step 2: 运行测试确认失败**

Run: `npm test -- --run tests/unit/learningSessionStrategyEngine.test.ts tests/unit/learningSessionQuestionEvaluator.test.ts`

Expected: FAIL。

**Step 3: 实现单一策略引擎**

```ts
export function selectTeachingStrategy(input: StrategyInput): StrategyDecision {
  if (input.isExpired || input.nodeCount >= 20 || input.depth >= 5 || input.closingRequested) {
    return decision('SELF_EXPLANATION', 'VERIFY_UNDERSTANDING', '会话进入收口边界');
  }
  if (input.consecutiveErrors > 0) {
    return decision('ERROR_TRACKING', 'REPAIR_MISCONCEPTION', '检测到可验证的错误证据');
  }
  if (input.isStuck) {
    return decision('ANALOGY_TRANSFER', 'TRANSFER_UNDERSTANDING', '学生表达卡住或概念过于抽象');
  }
  if (input.turnIndex === 0) {
    return decision('QUESTION_CHAIN', 'MAP_QUESTION', '先建立可继续探索的问题结构');
  }
  return decision('SOCRATIC', 'CONCEPT_UNDERSTANDING', '继续追问原理与成立条件');
}
```

`assertCanAppendNode` 分别返回 `SESSION_EXPIRED/NODE_LIMIT/DEPTH_LIMIT/BRANCH_LIMIT`，便于 API 显示可理解错误。

**Step 4: 实现本地确定性评估与兜底反问**

本地评估先做禁用空反问、当前知识词命中、条件/结论/反例/关系提示、长度和可回答性检查；模型评估在 Task 5 叠加。本地兜底按策略产生指向原理的问题，例如：

```ts
const fallbackByStrategy = {
  SOCRATIC: '你刚才这一步用了哪个结论？这个结论成立需要满足什么条件？',
  ERROR_TRACKING: '把当前思路代入一个最小反例后，最先出现矛盾的是哪一步？',
  ANALOGY_TRANSFER: '类比中的每个角色分别对应原问题中的哪个量，哪一部分不能直接类比？',
  QUESTION_CHAIN: '要回答这个问题，最先需要确认的定义和前置条件分别是什么？',
  SELF_EXPLANATION: '请用自己的话说出结论、成立条件和一个反例边界。',
} as const;
```

**Step 5: 运行测试并提交**

Run: `npm test -- --run tests/unit/learningSessionStrategyEngine.test.ts tests/unit/learningSessionQuestionEvaluator.test.ts`

Expected: PASS。

Commit: `git commit -m "feat(learning): add adaptive teaching strategy and evaluator"`

---

## Task 3: 增加 Prisma 持久化模型与 Repository

**Files:**

- Modify: `prisma/schema.prisma`
- Create: `prisma/migrations/20260806090000_learning_session_backend/migration.sql`
- Create: `lib/learning-session/repository.ts`
- Create: `lib/learning-session/serializers.ts`
- Test: `tests/unit/learningSessionRepository.test.ts`

**Step 1: 写 Repository 失败测试**

使用 Vitest mock Prisma，验证：创建 Session 同时创建根学生节点；按 `sessionId + clientTraceId` 幂等；树按 `createdAt,id` 稳定排序；完成操作在事务内写总结、证据和候选卡。

**Step 2: 运行测试确认失败**

Run: `npm test -- --run tests/unit/learningSessionRepository.test.ts`

Expected: FAIL。

**Step 3: 扩展 Prisma Schema**

新增枚举 `LearningSessionStatus`、`LearningEntryType`、`ThinkingNodeType`、`LearningMaterialType`；新增模型：

- `LearningSession`：`id/exploreSessionId/userId/topic/entryType/scenarioId/atomId/status/currentNodeId/nodeCount/maxNodes/maxDepth/expiresAt/completedAt/createdAt/updatedAt`。
- `ThinkingNode`：`id/sessionId/parentId/clientTraceId/type/question/answer/followUpQuestion/strategy/strategyReason/depth/isSideBranch/backtrackTargetId/knowledgeId/confidence/promptVersion/model/createdAt`。
- `MaterialUsage`：素材快照、类型、顺序、交互事件 JSON。
- `QuestionEvaluation`：五维分、总分、是否通过、尝试序号、原问题、修正原因。
- `LearningSummary`：理解报告、错误模型、兴趣方向、复述和完成原因 JSON。
- `MemoryCandidate`：稳定业务键 `sessionId_nodeId`、正反面、状态。
- `MasteryEvidence` 与 `InterestEvidence`：来源节点、强度、payload、可选 userId。

关系要求：`User` 增加学习会话/证据/候选关系；`ExploreSession` 增加 `learningSessions`；`ThinkingNode.parent` 自关联；会话删除级联节点、素材、评估、总结与候选。

关键索引：

```prisma
@@index([exploreSessionId, createdAt])
@@index([userId, createdAt])
@@unique([sessionId, clientTraceId])
@@index([sessionId, parentId, createdAt])
@@unique([sessionId, nodeId])
```

**Step 4: 写显式 SQL migration 并生成 Client**

Run:

```powershell
npm run db:generate
npx prisma validate
```

Expected: schema valid、Prisma Client 生成成功。不要在计划执行阶段自动对生产数据库运行 migrate deploy。

**Step 5: 实现 Repository 和序列化器**

Repository 只做数据访问，不调用 AI 或做策略决策；所有 JSON 通过现有 `toPrismaJson`。提供：

```ts
createSessionWithRoot(input): Promise<LearningSessionAggregate>
findOwnedSession(id, access): Promise<LearningSessionAggregate | null>
appendTurnAtomically(input): Promise<LearningSessionAggregate>
recordBacktrack(input): Promise<void>
completeSessionAtomically(input): Promise<LearningSessionAggregate>
upsertMemoryCandidate(input): Promise<MemoryCandidate>
```

**Step 6: 测试并提交**

Run: `npm test -- --run tests/unit/learningSessionRepository.test.ts`

Expected: PASS。

Commit: `git commit -m "feat(learning): persist learning sessions and thinking trees"`

---

## Task 4: 实现 Redis 运行态、短锁与幂等结果缓存

**Files:**

- Create: `lib/learning-session/sessionRuntimeStore.ts`
- Test: `tests/unit/learningSessionRuntimeStore.test.ts`

**Step 1: 写失败测试**

覆盖键格式、15 分钟滑动 TTL、Redis 不存在/报错时返回 null、从数据库快照重建、短锁 token 必须在 finally 释放。

```ts
expect(runtimeKey('ls_1')).toBe('learning-session:runtime:ls_1');
expect(idempotencyKey('ls_1', 'trace_1')).toBe('learning-session:idempotency:ls_1:trace_1');
expect(learningSessionRuntimeTtlSeconds).toBe(900);
```

**Step 2: 实现运行态 Store**

运行态只缓存：`currentNodeId/strategy/depth/recentNodeIds/consecutiveErrors/expiresAt/version`；幂等缓存保存已经提交的 API 响应摘要。DB 的 10 分钟 `expiresAt` 是硬截止，Redis TTL 不延长业务会话。

```ts
export async function withSessionLock<T>(sessionId: string, action: () => Promise<T>) {
  const token = await acquireRedisLock(`learning-session:${sessionId}`, 15_000);
  if (!token && isRedisConfigured()) throw conflict('会话正在处理上一条消息，请稍后重试。');
  try { return await action(); }
  finally { if (token) await releaseRedisLock(`learning-session:${sessionId}`, token); }
}
```

Redis 未配置时依赖 DB 唯一约束保证幂等，不把“无 Redis”误判为冲突。

**Step 3: 测试并提交**

Run: `npm test -- --run tests/unit/learningSessionRuntimeStore.test.ts`

Expected: PASS。

Commit: `git commit -m "feat(learning): cache learning session runtime safely"`

---

## Task 5: 实现 DeepSeek Teaching Engine 与双阶段质量闸门

**Files:**

- Create: `lib/learning-session/prompts.ts`
- Create: `lib/learning-session/dialogueEngine.ts`
- Create: `lib/learning-session/materialScheduler.ts`
- Test: `tests/unit/learningSessionDialogueEngine.test.ts`
- Test: `tests/unit/learningSessionMaterialScheduler.test.ts`

**Step 1: 写失败测试**

Mock `callDeepSeekJson`，覆盖：有效 JSON 一次通过；非法 JSON 修正；低于 18 分最多重新生成两次；第三次仍失败使用确定性反问；AI 返回越界素材被过滤；纯定义回答不强塞素材；单轮最多两个且形态不全相同。

**Step 2: 定义结构化生成和评估 Schema**

```ts
const generatedTurnSchema = z.object({
  answer: z.string().trim().min(1).max(1800),
  followUpQuestion: z.string().trim().min(1).max(240),
  detectedMisconception: z.string().trim().max(300).nullable(),
  confidence: z.number().min(0).max(1),
  materialIds: z.array(z.string()).max(4),
  isSideBranchSuggested: z.boolean(),
  shouldClose: z.boolean(),
});

const evaluatorSchema = z.object({
  principleDirection: z.number().int().min(0).max(5),
  contextRelevance: z.number().int().min(0).max(5),
  explorationValue: z.number().int().min(0).max(5),
  difficultyFit: z.number().int().min(0).max(5),
  answerability: z.number().int().min(0).max(5),
  reason: z.string().max(300),
});
```

**Step 3: 构建受控 Prompt**

System prompt 固化：学生必须通过提问推进；回答只是燃料；反问必须指向结论、条件、反例或连接；禁止“你觉得呢”；只使用提供的知识片段与素材 ID；超纲标记、不相关引导、不适宜拒绝；按所选策略行动。User prompt 只给当前根到叶路径最多 5 层、学生阶段、错误证据、Mock 知识上下文与允许素材清单。

**Step 4: 实现生成—评估—修正循环**

`dialogueEngine.generateTurn`：

1. 使用 `DEEPSEEK_LEARNING_MODEL`，默认 `deepseek-v4-flash`，`LEARNING_SESSION_PROMPT_VERSION` 默认 `learning-session-v1`。
2. JSON.parse + Zod；失败视为一次无效生成。
3. 先跑本地禁句/可回答性检查，再调用模型 Evaluator。
4. 总分 `>=18` 且本地检查通过才接受。
5. 不通过时把具体维度分和原因放入修正 prompt，最多两次修正。
6. 仍不通过时保留安全回答并替换为 `fallbackQuestion`；记录每次 `QuestionEvaluation`。
7. 素材 ID 经 `MaterialScheduler` 与允许集合取交集，最多 2 个，优先交互+公式/图等异构组合。

**Step 5: 记录 AI 使用量**

沿用 `ApiUsageLog`，endpoint 分为 `learning.turn.generate`、`learning.turn.evaluate`、`learning.summary`，写 model、promptVersion、token、latency、success/errorCode；日志失败不得回滚已经成功的学习节点。

**Step 6: 测试并提交**

Run: `npm test -- --run tests/unit/learningSessionDialogueEngine.test.ts tests/unit/learningSessionMaterialScheduler.test.ts`

Expected: PASS。

Commit: `git commit -m "feat(learning): add evaluated DeepSeek teaching engine"`

---

## Task 6: 实现 Session Service 的创建、读取和单轮推进

**Files:**

- Create: `lib/learning-session/sessionMapper.ts`
- Create: `lib/learning-session/sessionService.ts`
- Test: `tests/unit/learningSessionService.test.ts`

**Step 1: 写服务失败测试**

覆盖：问题入口和原子入口；创建时立即生成首轮导师响应；读取只允许所属用户/匿名身份；turn 使用当前路径而非全量聊天；双端相同幂等键只生成一次；超时自动进入收口；越过 20/5/3 返回明确冲突；Redis 丢失从 DB 重建。

**Step 2: 实现创建流程**

```ts
createSession(request, access) =>
  provider.getScenario/resolveQuestion
  -> repository.createSessionWithRoot
  -> engine.generateTurn(QUESTION_CHAIN)
  -> repository.appendTurnAtomically
  -> runtimeStore.save
  -> mapSessionResponse
```

Session 的 `userId` 仅在 `access.authType === 'user'` 时写入；匿名会话依赖 `ExploreSession.anonymousId` 所有权。

**Step 3: 实现 turn 流程**

`submitTurn` 在 `withSessionLock` 内按以下顺序执行：幂等读取 → 所有权检查 → DB 硬截止/树限制 → 读取根到当前节点路径 → 选择策略 → Mock 知识与素材边界 → Teaching Engine → DB 事务追加学生节点、导师节点、素材与评估 → 更新运行态 → 缓存幂等响应。

所有响应返回服务端树快照，客户端不自行猜测节点 ID：

```ts
type LearningSessionResponse = {
  session: { id: string; status: string; topic: string; expiresAt: string; limits: Limits };
  currentNodeId: string;
  nodes: ThinkingNodeDto[];
  materials: MaterialDto[];
  activeStrategy: StrategyDto;
  summary: LearningSummaryDto | null;
};
```

**Step 4: 测试并提交**

Run: `npm test -- --run tests/unit/learningSessionService.test.ts`

Expected: PASS。

Commit: `git commit -m "feat(learning): orchestrate production learning sessions"`

---

## Task 7: 实现分支、回溯、收口、证据、记忆卡与导出

**Files:**

- Create: `lib/learning-session/sessionActions.ts`
- Create: `lib/learning-session/summaryService.ts`
- Create: `lib/learning-session/evidenceService.ts`
- Create: `lib/learning-session/exportService.ts`
- Test: `tests/unit/learningSessionActions.test.ts`
- Test: `tests/unit/learningSessionSummary.test.ts`

**Step 1: 写失败测试**

覆盖：从任一所属节点开新支线；错误路径保留且回溯节点指向上一步；结束操作幂等；总结即使 AI 失败也有确定性结果；记忆候选只允许导师解释/总结节点；重复勾选 upsert；导出树包含节点关系、策略、素材和总结，不泄露模型原始 prompt。

**Step 2: 实现动作服务**

- `createBranch` 验证父节点属于该 Session 且子节点数小于 3，然后调用与 turn 相同的教学流程并标记 `isSideBranch=true`。
- `backtrack` 只改变 `currentNodeId` 并写回溯事件节点/目标，不删除错误路径。
- `complete` 生成 SELF_EXPLANATION 收口、学习总结与证据，并把 Session 置为 `COMPLETED`。
- 到期后的首次写请求走同一 complete 流程，完成后返回快照；后续写请求幂等返回已完成结果。

**Step 3: 实现总结、证据和记忆候选**

总结输出：`understanding`（概念/应用/边界 0–100）、`misconceptions`、`interestDirections`、`studentRestatement`、`recommendedReview`。理解度是证据估计，不展示伪精确诊断；每个分数必须带来源节点 ID。

记忆候选存 `front/back/sourceNodeId/sourceSessionId/status=PENDING`，为 2.2 正式接口预留；当前不直接宣称进入复习队列。

**Step 4: 实现 JSON 导出**

`exportService` 返回 `application/json; charset=utf-8`，文件名 `learning-session-{id}.json`，包含稳定 schemaVersion `learning-session-export-v1`。

**Step 5: 测试并提交**

Run: `npm test -- --run tests/unit/learningSessionActions.test.ts tests/unit/learningSessionSummary.test.ts`

Expected: PASS。

Commit: `git commit -m "feat(learning): complete sessions with evidence and memory candidates"`

---

## Task 8: 暴露 REST API、鉴权、限流、幂等与 Flutter Web CORS

**Files:**

- Create: `lib/learning-session/http.ts`
- Create: `app/api/learning-sessions/route.ts`
- Create: `app/api/learning-sessions/[id]/route.ts`
- Create: `app/api/learning-sessions/[id]/turns/route.ts`
- Create: `app/api/learning-sessions/[id]/branches/route.ts`
- Create: `app/api/learning-sessions/[id]/backtracks/route.ts`
- Create: `app/api/learning-sessions/[id]/complete/route.ts`
- Create: `app/api/learning-sessions/[id]/memory-candidates/route.ts`
- Create: `app/api/learning-sessions/[id]/export/route.ts`
- Test: `tests/unit/learningSessionRoutes.test.ts`
- Test: `tests/unit/learningSessionCors.test.ts`

**Step 1: 写 Route/CORS 失败测试**

覆盖：无权访问 403、未知 Session 404、非法 body 400、重复请求返回同一快照、会话/IP 限流、允许配置的 Flutter Web origin、拒绝未知 origin、OPTIONS 返回允许的方法与 headers、App 无 Origin 请求仍可通过现有安全策略。

**Step 2: 实现学习域专用 CORS 包装器**

不放宽全局 Origin。`FLUTTER_WEB_ORIGINS` 使用逗号分隔精确 origin；开发默认允许 `http://localhost:3001` 与 `http://127.0.0.1:3001`。响应包含：

```ts
Access-Control-Allow-Origin: <精确请求 origin>
Access-Control-Allow-Credentials: true
Access-Control-Allow-Methods: GET,POST,OPTIONS
Access-Control-Allow-Headers: Content-Type,Authorization,X-Anonymous-Id,X-Miniapp-Client,Idempotency-Key
Vary: Origin
```

禁止返回 `*` 与 credentials 同用。OPTIONS 不访问数据库。

**Step 3: 实现 Routes**

每个修改 Route 顺序固定：CORS/origin → `validateJsonBody` → `assertSessionAccess` → session/IP rate limit → `Idempotency-Key` 校验 → Service。建议速率：turn/branch 每会话 20/min、每 IP 40/min；complete/memory 10/min。

API 清单：

```text
POST /api/learning-sessions
GET  /api/learning-sessions/:id?exploreSessionId=...
POST /api/learning-sessions/:id/turns
POST /api/learning-sessions/:id/branches
POST /api/learning-sessions/:id/backtracks
POST /api/learning-sessions/:id/complete
POST /api/learning-sessions/:id/memory-candidates
GET  /api/learning-sessions/:id/export?exploreSessionId=...
```

**Step 4: 测试并提交**

Run: `npm test -- --run tests/unit/learningSessionRoutes.test.ts tests/unit/learningSessionCors.test.ts`

Expected: PASS。

Commit: `git commit -m "feat(api): expose secure dialogue exploration sessions"`

---

## Task 9: 环境配置、迁移检查与后端总验证

**Files:**

- Modify: `.env.example`
- Create: `docs/operations/dialogue-exploration-backend.md`
- Modify if required: `scripts/assert-prisma-migrated.mjs`

**Step 1: 补齐无密钥配置说明**

`.env.example` 新增：

```dotenv
DEEPSEEK_LEARNING_MODEL=deepseek-v4-flash
LEARNING_SESSION_PROMPT_VERSION=learning-session-v1
FLUTTER_WEB_ORIGINS=http://localhost:3001,http://127.0.0.1:3001
```

操作文档写清：MySQL/Redis/DeepSeek 必需项、无 Redis 降级行为、MockKnowledgeProvider 范围、Prisma migration 命令、localhost:3000 启动命令和健康检查。

**Step 2: 运行完整验证**

Run:

```powershell
npm run db:generate
npx prisma validate
npm test -- --run tests/unit/learningSessionContracts.test.ts tests/unit/learningSessionKnowledgeProvider.test.ts tests/unit/learningSessionStrategyEngine.test.ts tests/unit/learningSessionQuestionEvaluator.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionRuntimeStore.test.ts tests/unit/learningSessionDialogueEngine.test.ts tests/unit/learningSessionMaterialScheduler.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionActions.test.ts tests/unit/learningSessionSummary.test.ts tests/unit/learningSessionRoutes.test.ts tests/unit/learningSessionCors.test.ts
npm run typecheck
npm run build
```

Expected: 全部退出码 0。若 build 因本机已有无关模块失败，记录准确文件与错误，但学习域测试和 typecheck 必须先通过。

**Step 3: 本地 API 冒烟**

后端运行于 3000 后，用同一个 ExploreSession 身份依次调用 create → turn → branch → backtrack → complete → memory → export；验证数据库有树、素材、评估、总结与证据，Redis 删除后 GET 能从 DB 恢复。

**Step 4: 提交操作文档**

Commit: `git commit -m "docs(learning): document dialogue backend operations"`

---

## Definition of Done

- 四个 Mock 场景能走完 10 分钟 Session，知识边界与素材白名单为零越界。
- 五种策略由同一引擎自动组合，客户端无模式选择页。
- 所有导师反问通过 18 分门槛或明确使用确定性兜底，抽样无空反问。
- 错误路径、分支、回溯均持久保存；树限制 20/5/3 在服务端强制。
- Session 可恢复、完成、导出、生成总结/证据/记忆候选。
- App 与 Flutter Web 使用同一 API、同一身份、同一 MySQL 事实源。
- Redis、DeepSeek 单次暂时故障都有明确降级或可重试行为，不造成重复节点。
- 相关 Vitest、Prisma validate、TypeScript typecheck 通过，并记录 build 结果。

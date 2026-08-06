# Dialogue Exploration Entry and Live Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付可在 Flutter Web 直接体验的 1.2 纵向切片：Learning Entry 创建真实 AI Session，支持保存/恢复、继续、支线、回溯、完成、记忆候选和导出，并在桌面端常驻展示实时知识树。

**Architecture:** Next.js 提供 Learning Entry、Session Manager、DeepSeek Teaching Engine、Prisma 持久化与 Redis 运行态；知识边界和首批素材由可替换的 `MockKnowledgeProvider` 提供。Flutter 通过跨端 HTTP Transport 使用同一 API，服务端完整树快照为事实源；桌面端对话与树双栏，手机端常驻当前路径并可展开全树。

**Tech Stack:** Next.js 16、TypeScript、Zod 4、Prisma/MySQL、ioredis、DeepSeek JSON API、Vitest、Flutter/Dart、package:http、flutter_test。

## Global Constraints

- Flutter 仓库/分支：`D:\dev\Uniprism\uniprism_app` / `feature/student-dialogue-exploration-1-2`。
- 后端仓库/分支：`D:\ywkeji\Uniprism\UniPrism_New-main` / `feature/dialogue-exploration-1-2-backend`。
- 仅 1.1 知识内容与素材目录使用 Mock；AI、会话、树、总结、记忆候选和导出走正式后端。
- 会话硬限制：10 分钟、20 个节点、深度 5、单节点 3 个直接分支、单轮 2 个素材。
- 反问五维评分至少 18/25；最多重生成两次；仍失败使用确定性反问；禁止“你觉得呢”式空反问。
- 单击树节点只读；只有显式“从这里继续 / 新开支线 / 回溯到这里 / 转为记忆候选”才写服务端。
- 所有写请求使用 `Idempotency-Key`；客户端不提交 user ID，不生成正式节点 ID。
- 远程失败不静默切本地 Mock；MySQL 是事实源，Redis 故障必须可从 DB 恢复。
- 后端全量基线已有 8 个与本功能无关的失败；本计划要求新增定向测试、typecheck 和相关回归通过，并在最终报告保留该基线。

---

### Task 1: Learning Entry 契约与 Mock Knowledge Provider

**Files:**
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\contracts.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\knowledgeProvider.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\mockKnowledgeProvider.ts`
- Test: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\learningSessionEntry.test.ts`

**Interfaces:**
- Consumes: Zod 4。
- Produces: `LearningEntryDto`、`KnowledgeContext`、`KnowledgeProvider`、`MockKnowledgeProvider`、所有 Session 写入 Schema。

- [ ] **Step 1: 写 Learning Entry 和输入边界失败测试**

```ts
it('returns a recommended quadratic entry without teaching the lesson', async () => {
  const entry = await new MockKnowledgeProvider().getLearningEntry('quadratic-function');
  expect(entry).toMatchObject({
    atomId: 'quadratic-function',
    estimatedMinutes: 10,
    recommendedDirectionId: 'graph-secret',
  });
  expect(entry?.directions).toHaveLength(3);
  expect(entry?.directions[1].hookQuestion).toBe('二次函数的顶点为什么在这里？');
});

it('rejects a client supplied user id', () => {
  expect(createLearningSessionSchema.safeParse({
    exploreSessionId: 'exp-1', scenarioId: 'quadratic-function',
    question: '为什么？', userId: 'forged-user',
  }).success).toBe(false);
});
```

- [ ] **Step 2: 运行测试确认因模块缺失失败**

Run: `npm test -- --run tests/unit/learningSessionEntry.test.ts`

Expected: FAIL with module-not-found。

- [ ] **Step 3: 实现契约与 Provider**

```ts
export interface KnowledgeProvider {
  getLearningEntry(atomId: string): Promise<LearningEntryDto | null>;
  resolveQuestion(question: string, studentStage?: string): Promise<KnowledgeContext>;
  getAllowedMaterials(context: KnowledgeContext): Promise<KnowledgeMaterial[]>;
}

export const createLearningSessionSchema = z.object({
  exploreSessionId: z.string().min(1).max(191),
  atomId: z.string().min(1).max(191).optional(),
  scenarioId: z.string().min(1).max(100),
  directionId: z.string().min(1).max(100).optional(),
  question: z.string().trim().min(1).max(500).optional(),
}).strict();
```

Provider 实现四套内容：`negative-times-negative`、`quadratic-function`、`inequality-proof`、`coffee-business-model`，每套含入口、关系边、种子问题和四类素材元数据。

- [ ] **Step 4: 运行测试确认通过**

Run: `npm test -- --run tests/unit/learningSessionEntry.test.ts`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/learning-session tests/unit/learningSessionEntry.test.ts
git commit -m "feat(learning): add entry contracts and mock knowledge provider"
```

---

### Task 2: Prisma Session、树和学习产出模型

**Files:**
- Modify: `D:\ywkeji\Uniprism\UniPrism_New-main\prisma\schema.prisma`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\prisma\migrations\20260806113000_learning_session\migration.sql`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\repository.ts`
- Test: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\learningSessionRepository.test.ts`

**Interfaces:**
- Consumes: Prisma singleton `prisma`、`toPrismaJson`。
- Produces: `LearningSessionRepository` 的 create/get/append/backtrack/complete/memory 方法。

- [ ] **Step 1: 写 Repository 行为失败测试**

```ts
it('keeps the contradicted branch when backtracking', async () => {
  const aggregate = await repository.backtrack({
    sessionId: 'session-1', targetNodeId: 'question-1', clientTraceId: 'trace-backtrack',
  });
  expect(aggregate.nodes.map((node) => node.id)).toContain('wrong-question');
  expect(aggregate.currentNodeId).toBe('question-1');
  expect(aggregate.revision).toBe(4);
});
```

同时覆盖 `(sessionId, clientTraceId)` 幂等、稳定树排序、完成事务和记忆候选 upsert。

- [ ] **Step 2: 运行测试确认失败**

Run: `npm test -- --run tests/unit/learningSessionRepository.test.ts`

Expected: FAIL。

- [ ] **Step 3: 增加 Prisma 模型和 migration**

新增 `LearningSession`、`ThinkingNode`、`MaterialUsage`、`QuestionEvaluation`、`LearningSummary`、`MemoryCandidate`、`MasteryEvidence`、`InterestEvidence`；为 `User` 与 `ExploreSession` 补关系。关键约束：

```prisma
@@index([exploreSessionId, createdAt])
@@unique([sessionId, clientTraceId])
@@index([sessionId, parentId, createdAt])
@@unique([sessionId, nodeId])
```

- [ ] **Step 4: 实现 Repository 事务方法**

```ts
export interface LearningSessionRepository {
  create(input: CreatePersistedSession): Promise<LearningSessionAggregate>;
  get(sessionId: string): Promise<LearningSessionAggregate | null>;
  appendTurn(input: AppendTurnInput): Promise<LearningSessionAggregate>;
  setCurrentNode(input: SetCurrentNodeInput): Promise<LearningSessionAggregate>;
  complete(input: CompleteSessionInput): Promise<LearningSessionAggregate>;
  upsertMemoryCandidate(input: MemoryCandidateInput): Promise<PersistedMemoryCandidate>;
}
```

- [ ] **Step 5: 验证 Schema 和测试**

Run:

```powershell
npm run db:generate
npx prisma validate
npm test -- --run tests/unit/learningSessionRepository.test.ts
```

Expected: 全部通过；不自动执行生产 migrate deploy。

- [ ] **Step 6: 提交**

Commit: `git commit -m "feat(learning): persist sessions and thinking trees"`

---

### Task 3: Teaching Engine、DeepSeek 与反问质量闸门

**Files:**
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\strategyEngine.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\prompts.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\questionEvaluator.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\dialogueEngine.ts`
- Test: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\learningSessionTeachingEngine.test.ts`

**Interfaces:**
- Consumes: `callDeepSeekJson`、`KnowledgeContext`、允许素材集合。
- Produces: `TeachingEngine.generateTurn(input): Promise<EvaluatedTurn>`。

- [ ] **Step 1: 写策略与质量失败测试**

```ts
expect(selectTeachingStrategy({ ...base, turnIndex: 0 }).strategy).toBe('QUESTION_CHAIN');
expect(selectTeachingStrategy({ ...base, consecutiveErrors: 1 }).strategy).toBe('ERROR_TRACKING');
expect(evaluateLocally('你觉得呢？', context).pass).toBe(false);
expect(evaluateLocally('这一步用了哪个结论，它成立需要什么条件？', context).pass).toBe(true);
```

另测低于 18 分最多修正两次、无效 JSON、安全兜底和素材白名单裁剪。

- [ ] **Step 2: 运行测试确认失败**

Run: `npm test -- --run tests/unit/learningSessionTeachingEngine.test.ts`

Expected: FAIL。

- [ ] **Step 3: 实现五策略选择与限制判断**

硬限制/收口优先，其次明确错误、卡住、首轮、普通苏格拉底追问。确定性兜底问题必须分别指向条件、反例、类比映射、前置定义或自我解释。

- [ ] **Step 4: 实现 DeepSeek 结构化生成和评估循环**

```ts
const generatedTurnSchema = z.object({
  answer: z.string().trim().min(1).max(1800),
  followUpQuestion: z.string().trim().min(1).max(240),
  detectedMisconception: z.string().max(300).nullable(),
  materialIds: z.array(z.string()).max(4),
  sideBranchSuggested: z.boolean(),
});
```

使用 `DEEPSEEK_LEARNING_MODEL`（默认 `deepseek-v4-flash`）和 `LEARNING_SESSION_PROMPT_VERSION`（默认 `learning-session-v1`）。每次尝试记录五维分数，最终素材最多 2 个且只来自 Provider 白名单。

- [ ] **Step 5: 运行测试并提交**

Run: `npm test -- --run tests/unit/learningSessionTeachingEngine.test.ts`

Expected: PASS。

Commit: `git commit -m "feat(learning): add evaluated AI teaching engine"`

---

### Task 4: Session Manager、Redis 与九个 API

**Files:**
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\sessionRuntimeStore.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\sessionService.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\lib\learning-session\http.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-entries\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-sessions\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-sessions\[id]\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-sessions\[id]\turns\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-sessions\[id]\branches\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-sessions\[id]\backtracks\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-sessions\[id]\complete\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-sessions\[id]\memory-candidates\route.ts`
- Create: `D:\ywkeji\Uniprism\UniPrism_New-main\app\api\learning-sessions\[id]\export\route.ts`
- Test: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\learningSessionService.test.ts`
- Test: `D:\ywkeji\Uniprism\UniPrism_New-main\tests\unit\learningSessionRoutes.test.ts`

**Interfaces:**
- Consumes: Provider、Repository、TeachingEngine、现有 `assertSessionAccess`/rate limit/Redis helpers。
- Produces: Learning Entry 与完整 Session REST API、`LearningSessionSnapshotDto`。

- [ ] **Step 1: 写会话状态机和 Route 失败测试**

覆盖根问题优先级、创建即生成首轮、GET 恢复、继续、显式支线、只读节点选择、回溯不删树、完成幂等、记忆候选 upsert、JSON 导出、10/20/5/3 限制、身份归属、CORS 和 Redis 重建。

```ts
it('prefers the student question over the selected direction hook', async () => {
  const snapshot = await service.create({
    exploreSessionId: 'exp-1', atomId: 'quadratic-function',
    scenarioId: 'quadratic-function', directionId: 'graph-secret',
    question: '如果 a=0 呢？',
  }, access);
  expect(snapshot.nodes[0].question).toBe('如果 a=0 呢？');
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `npm test -- --run tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts`

Expected: FAIL。

- [ ] **Step 3: 实现运行态与 Session Manager**

Redis 使用 `learning-session:runtime:{id}`、`learning-session:idempotency:{id}:{key}` 和 15 秒短锁；运行态 TTL 900 秒，但 DB `expiresAt` 固定开始后 600 秒。Redis 未配置时用 DB 唯一键保证幂等。

- [ ] **Step 4: 实现 API 与 Flutter Web CORS**

所有写 Route 顺序：精确 Origin → Zod → `assertSessionAccess` → 限流 → 幂等 → Service。`FLUTTER_WEB_ORIGINS` 开发允许 `http://localhost:3001,http://127.0.0.1:3001`，credentials 时禁止 `*`。

- [ ] **Step 5: 运行测试和 typecheck**

Run:

```powershell
npm test -- --run tests/unit/learningSessionEntry.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionTeachingEngine.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts
npm run typecheck
```

Expected: 新增测试和 typecheck 全通过。

- [ ] **Step 6: 提交**

Commit: `git commit -m "feat(api): expose persistent dialogue exploration sessions"`

---

### Task 5: Flutter 跨端网络与远程 Session Controller

**Files:**
- Create: `lib/network/app_http_transport.dart`
- Create: `lib/network/app_http_transport_io.dart`
- Create: `lib/network/app_http_transport_web.dart`
- Create: `lib/network/app_http_transport_stub.dart`
- Modify: `lib/main.dart`
- Create: `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`
- Create: `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`
- Create: `lib/features/dialogue_exploration/core/exploration_session_coordinator.dart`
- Create: `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`
- Test: `test/network/app_http_transport_test.dart`
- Test: `test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`

**Interfaces:**
- Consumes: 后端 `LearningSessionSnapshotDto`、现有 `AuthService` 身份和 ExploreSession。
- Produces: `AuthService.requestJson`、`RemoteExplorationApi`、`ExplorationSessionCoordinator`。

- [ ] **Step 1: 写 Web Transport 和远程状态机失败测试**

覆盖移除 `dart:io` Web 阻塞、BrowserClient credentials、App headers、幂等重试复用 key、远程失败保留旧树、restore 和 dispose 后不通知。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/network/app_http_transport_test.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现 conditional transport 与公开 JSON 请求**

```dart
abstract interface class AppHttpTransport {
  Future<AppHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Object? jsonBody,
    required Duration timeout,
  });
}
```

Web 使用 `BrowserClient()..withCredentials = true`，不手工设置 Origin/Cookie；IO 使用 `IOClient`。`AuthService.requestJson` 接受附加 headers 和 timeout。

- [ ] **Step 4: 实现 DTO、API 和远程 Controller**

Controller 的服务端快照为唯一树事实源；失败保存 `PendingOperation`，重试复用 `clientTraceId`；选中节点只更新本地 `inspectedNodeId`，不调用写接口。

- [ ] **Step 5: 测试和 Web 编译**

Run:

```powershell
flutter test test/network/app_http_transport_test.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart
flutter analyze lib/network lib/features/dialogue_exploration lib/main.dart
flutter build web --debug --dart-define=API_BASE_URL=http://localhost:3000
```

Expected: 全部通过。

- [ ] **Step 6: 提交**

Commit: `git commit -m "feat(dialogue): connect app and web to learning sessions"`

---

### Task 6: Learning Entry 与 A+C 实时树页面

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/exploration_lab_page.dart`
- Modify: `lib/features/dialogue_exploration/presentation/exploration_session_page.dart`
- Modify: `lib/features/dialogue_exploration/presentation/exploration_tree_panel.dart`
- Modify: `lib/features/dialogue_exploration/materials/exploration_material_card.dart`
- Modify: `lib/developer_tools.dart`
- Test: `test/features/dialogue_exploration/learning_entry_page_test.dart`
- Test: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: `ExplorationSessionCoordinator`、Learning Entry DTO、完整树快照。
- Produces: App/Web 共用的入口卡、桌面双栏、手机常驻路径和显式节点动作。

- [ ] **Step 1: 写入口和响应式树失败测试**

```dart
testWidgets('desktop keeps chat and live tree visible together', (tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  await tester.pumpWidget(buildRemoteSessionPage());
  expect(find.byKey(const ValueKey('exploration-chat-stage')), findsOneWidget);
  expect(find.byKey(const ValueKey('exploration-live-tree')), findsOneWidget);
});

testWidgets('selecting a historical node does not create a branch', (tester) async {
  await tester.tap(find.byKey(const ValueKey('tree-node-node-2')));
  await tester.pump();
  expect(fakeApi.branchCalls, 0);
  expect(find.text('新开支线'), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/dialogue_exploration/learning_entry_page_test.dart test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现 Learning Entry**

展示核心问题、三方向、推荐标记、自由输入和预计时间；自由问题 > 选中方向 > 推荐方向决定创建根问题。学生不选择教学模式或掌握程度。

- [ ] **Step 4: 实现 A+C 页面**

宽度 >= 900 时对话/树双栏；小屏顶部常驻根到当前节点路径并可展开全树。点击节点只切换查看路径，显示四个显式动作；分支和回溯成功后以服务端快照刷新。

- [ ] **Step 5: 完成素材、总结、记忆与导出 UI**

交互素材真实可操作；完成前要求学生复述；记忆候选显示 `PENDING`；Web 下载版本化 JSON，失败均提供幂等重试。

- [ ] **Step 6: 运行全部 1.2 测试并提交**

Run:

```powershell
flutter test test/features/dialogue_exploration
flutter analyze lib/features/dialogue_exploration
```

Expected: PASS。

Commit: `git commit -m "feat(dialogue): add learning entry and persistent live tree"`

---

### Task 7: 浏览器纵向联调与可见验收

**Files:**
- Create: `docs/operations/dialogue-exploration-entry-live-tree-testing.md`

**Interfaces:**
- Consumes: localhost:3000 后端和 localhost:3001 Flutter Web。
- Produces: 可重复的联调步骤和已知限制记录。

- [ ] **Step 1: 启动后端与 Flutter Web**

```powershell
# 后端仓库
npm run dev

# Flutter 仓库
flutter run -d chrome --web-port 3001 --dart-define=API_BASE_URL=http://localhost:3000
```

- [ ] **Step 2: 验证完整用户路径**

从二次函数 Learning Entry 选择“图像秘密”创建 Session；连续提问使树增长；选旧节点确认只读；显式开支线；提出错误想法并回溯；刷新恢复；完成复述；生成记忆候选；导出 JSON。

- [ ] **Step 3: 验证真实 AI 与 Mock 边界**

确认后端 ApiUsageLog 有 `learning.turn.generate/evaluate`，素材全部来自 Mock Provider 白名单，页面只有知识内容标记为 Mock，不把 AI 会话标成 Mock。

- [ ] **Step 4: 写测试说明并提交**

记录 URL、启动参数、数据库 migration、DeepSeek/Redis 前置条件、现存后端 8 个无关基线失败和未来替换 1.1 Provider 的位置。

Commit: `git commit -m "docs(dialogue): document live tree browser testing"`

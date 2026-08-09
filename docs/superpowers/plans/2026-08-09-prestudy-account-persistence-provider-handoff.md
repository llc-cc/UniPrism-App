# Prestudy Account Persistence, Provider, and Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让预习模块按登录账号持久化并恢复完整节点树，在没有真实知识库时通过正式 Provider 边界如实回退到模型知识，并输出练习模块可独立消费的 `PrestudyHandoffV1`。

**Architecture:** MySQL/Prisma 是长期事实源，Redis 仅保存锁、幂等结果和短期快照；Flutter 通过注入身份提供器携带 Bearer Token，从服务端恢复账号历史。知识能力由 `KnowledgeProvider` 工厂选择 `none | mock | remote`，对话引擎只消费统一上下文；现有导出接口返回版本化预习交接 DTO。

**Tech Stack:** Next.js Route Handlers、TypeScript、Prisma/MySQL、Zod、Vitest、Flutter/Dart、`package:http`、Flutter Test。

## Global Constraints

- 在现有 `feature/dialogue-exploration-1-2-backend` 和 `feature/student-dialogue-exploration-1-2` 分支内实施，不创建新 worktree。
- 保留工作区中与本任务无关的既有修改；提交时只暂存本计划明确列出的文件。
- 新增或实质修改的状态机、异步流程、数据安全分支写简洁中文注释。
- 非测试环境以 Prisma/MySQL 为唯一长期事实源；数据库失败时不得静默回退内存。
- `userId` 只取自服务端鉴权，不接受客户端提交。
- 知识库不可用时回答来源必须是 `MODEL_PRIOR`，不得伪装成 `KNOWLEDGE_BASE`。
- 预习置信度不等于练习掌握度；预习交接不得生成正式练习结论。
- 新行为严格执行 RED → GREEN → REFACTOR；后端至少运行相关 Vitest，Flutter 至少运行相关测试和静态分析。

---

### Task 1: Durable repository selection and account-scoped session history

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/server.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/storageMode.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/repository.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/memoryRepository.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/http.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/app/api/learning-sessions/route.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/.env.example`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionStorageMode.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRepository.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionService.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRoutes.test.ts`

**Interfaces:**
- Produces: `resolveLearningSessionStorage(env): 'memory' | 'prisma'`.
- Produces: `LearningSessionListInput`, `LearningSessionSummary`, and `LearningSessionRepository.list(input)`.
- Produces: `LearningSessionService.list(input, access)` and `learningSessionApi.listSessions`.
- Consumes: existing `LearningSessionAccess` returned by `assertSessionAccess`.

- [ ] **Step 1: Write failing storage-mode tests**

```ts
expect(resolveLearningSessionStorage({ NODE_ENV: 'development' })).toBe('prisma');
expect(resolveLearningSessionStorage({ NODE_ENV: 'test' })).toBe('memory');
expect(() => resolveLearningSessionStorage({
  NODE_ENV: 'production',
  LEARNING_SESSION_STORAGE: 'memory',
})).toThrow('生产环境不能使用内存学习会话仓储');
```

- [ ] **Step 2: Run the storage-mode test and verify RED**

Run: `npx vitest run tests/unit/learningSessionStorageMode.test.ts`

Expected: FAIL because `storageMode.ts` and `resolveLearningSessionStorage` do not exist.

- [ ] **Step 3: Implement the storage selector and wire server assembly**

```ts
export type LearningSessionStorage = 'memory' | 'prisma';

export function resolveLearningSessionStorage(
  env: NodeJS.ProcessEnv = process.env,
): LearningSessionStorage {
  const configured = env.LEARNING_SESSION_STORAGE?.trim().toLowerCase();
  if (configured && configured !== 'memory' && configured !== 'prisma') {
    throw new Error('LEARNING_SESSION_STORAGE 只允许 memory 或 prisma');
  }
  if (env.NODE_ENV === 'production' && configured === 'memory') {
    throw new Error('生产环境不能使用内存学习会话仓储');
  }
  return configured ?? (env.NODE_ENV === 'test' ? 'memory' : 'prisma');
}
```

Update `server.ts` to create the shared development runtime only when the resolved mode is `memory`.

- [ ] **Step 4: Run the storage-mode test and verify GREEN**

Run: `npx vitest run tests/unit/learningSessionStorageMode.test.ts tests/unit/learningSessionServerRuntime.test.ts`

Expected: both test files pass.

- [ ] **Step 5: Write failing repository and service history tests**

Add literal expectations for:

```ts
expect(await service.list(
  { exploreSessionId: 'explore-a', scenarioId: 'prestudy', limit: 20 },
  { authType: 'user', userId: 'user-a' },
)).toEqual([
  expect.objectContaining({ id: 'learning-new', nodeCount: 3 }),
  expect.objectContaining({ id: 'learning-old', nodeCount: 1 }),
]);
```

Verify anonymous listing is scoped to `exploreSessionId`, authenticated listing is scoped to `userId`, ordering is `updatedAt DESC, id DESC`, and limit is clamped to `1..50`.

- [ ] **Step 6: Run repository/service tests and verify RED**

Run: `npx vitest run tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionService.test.ts`

Expected: FAIL because `list` and the summary contracts do not exist.

- [ ] **Step 7: Implement history contracts in both repositories and the service**

```ts
export type LearningSessionListInput = {
  owner: { authType: 'user'; userId: string } |
    { authType: 'anonymous'; exploreSessionId: string };
  scenarioId?: string;
  status?: LearningSessionAggregate['status'];
  limit: number;
  cursor?: string;
};

export type LearningSessionSummary = Pick<
  LearningSessionAggregate,
  'id' | 'exploreSessionId' | 'topic' | 'scenarioId' | 'atomId' |
  'status' | 'nodeCount' | 'startedAt' | 'expiresAt' | 'completedAt'
> & { updatedAt: Date };
```

Prisma authenticated queries use `where.userId`; anonymous queries use both `exploreSessionId` and `userId: null`. Memory queries apply the same ownership rules.

- [ ] **Step 8: Write failing list-route tests**

Test `GET /api/learning-sessions?exploreSessionId=explore-1&scenarioId=prestudy&limit=20`, assert that `assertAccess` is called before `service.list`, and assert a stable envelope containing `items` and `nextCursor`.

- [ ] **Step 9: Run route tests and verify RED**

Run: `npx vitest run tests/unit/learningSessionRoutes.test.ts`

Expected: FAIL because `listSessions` and the GET route export do not exist.

- [ ] **Step 10: Implement validated list query and route**

Add a strict Zod query schema with `scenarioId`, `status`, `limit` and `cursor`. Export both handlers:

```ts
export const GET = withLearningApi(learningSessionApi.listSessions);
export const POST = withLearningApi(learningSessionApi.createSession);
```

- [ ] **Step 11: Run Task 1 verification**

Run: `npx vitest run tests/unit/learningSessionStorageMode.test.ts tests/unit/learningSessionServerRuntime.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts`

Expected: all selected tests pass.

- [ ] **Step 12: Commit Task 1 if the listed files contain no unrelated user changes**

```bash
git add .env.example app/api/learning-sessions/route.ts lib/learning-session/storageMode.ts lib/learning-session/server.ts lib/learning-session/repository.ts lib/learning-session/memoryRepository.ts lib/learning-session/sessionService.ts lib/learning-session/http.ts tests/unit/learningSessionStorageMode.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts
git commit -m "feat(learning): persist account session history"
```

If any listed file contains unrelated pre-existing edits, do not stage it; preserve the working tree and record the verification checkpoint instead.

---

### Task 2: Anonymous-to-account adoption and authorization regression coverage

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/app/api/miniapp/explore/session/route.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionOwnership.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionOwnership.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRoutes.test.ts`

**Interfaces:**
- Produces: `claimAnonymousLearningSessions(client, { exploreSessionId, userId })`.
- Consumes: existing mini-app JWT verification and `ExploreSession` anonymous binding flow.

- [ ] **Step 1: Write failing ownership tests**

Use a fake Prisma client that records `learningSession.updateMany` input. Assert:

```ts
expect(update).toEqual({
  where: { exploreSessionId: 'explore-anon', userId: null },
  data: { userId: 'user-a' },
});
```

Also assert no update occurs when either identifier is blank.

- [ ] **Step 2: Run ownership tests and verify RED**

Run: `npx vitest run tests/unit/learningSessionOwnership.test.ts`

Expected: FAIL because `claimAnonymousLearningSessions` does not exist.

- [ ] **Step 3: Implement the ownership helper**

```ts
export async function claimAnonymousLearningSessions(
  client: Pick<PrismaClient, 'learningSession'>,
  input: { exploreSessionId: string; userId: string },
) {
  if (!input.exploreSessionId.trim() || !input.userId.trim()) return 0;
  const result = await client.learningSession.updateMany({
    where: { exploreSessionId: input.exploreSessionId, userId: null },
    data: { userId: input.userId },
  });
  return result.count;
}
```

- [ ] **Step 4: Integrate adoption into the existing authenticated anonymous-session binding path**

Call the helper immediately after `ExploreSession.userId` is updated and before selecting the account's most recent exploration session. Do not accept an arbitrary learning session ID from the request body.

- [ ] **Step 5: Add authorization regression tests**

Cover authenticated list/read/export for account A, rejection for account B, anonymous access limited to the bound exploration session, and adopted sessions appearing in account A history.

- [ ] **Step 6: Run Task 2 verification**

Run: `npx vitest run tests/unit/learningSessionOwnership.test.ts tests/unit/learningSessionRoutes.test.ts`

Expected: all selected tests pass.

- [ ] **Step 7: Commit Task 2 under the same dirty-tree safeguard**

```bash
git add app/api/miniapp/explore/session/route.ts lib/learning-session/sessionOwnership.ts tests/unit/learningSessionOwnership.test.ts tests/unit/learningSessionRoutes.test.ts
git commit -m "feat(learning): adopt anonymous sessions on login"
```

---

### Task 3: Configurable knowledge-provider framework and provenance persistence

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/contracts.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/knowledgeProvider.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/mockKnowledgeProvider.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/noKnowledgeProvider.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/remoteKnowledgeProvider.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/knowledgeProviderFactory.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/server.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/repository.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/memoryRepository.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/prisma/schema.prisma`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/prisma/migrations/20260809_learning_knowledge_provenance/migration.sql`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/.env.example`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningKnowledgeProvider.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRepository.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionService.test.ts`

**Interfaces:**
- Produces: `KnowledgeProviderMode = 'none' | 'mock' | 'remote'`.
- Produces: `KnowledgeReference` and required `provider`, `providerVersion`, `references` fields on `KnowledgeContext`.
- Produces: `createKnowledgeProvider({ env, fetchImpl })`.
- Persists per-node `knowledgeProvider`, `knowledgeVersion`, and `knowledgeReferences`.

- [ ] **Step 1: Write failing provider-mode and no-knowledge tests**

Assert development defaults to `none`, tests may inject `mock`, production rejects `mock`, and `NoKnowledgeProvider.resolveQuestion('海水为什么是蓝色？')` returns empty facts with `provider: 'none'`.

- [ ] **Step 2: Write failing remote-adapter contract tests**

Inject a fake `fetch` and test valid context, malformed JSON, timeout/abort, non-2xx response and empty result. A failure must return an unavailable/empty knowledge context or a typed provider error that the factory safely converts; it must never synthesize facts.

- [ ] **Step 3: Run provider tests and verify RED**

Run: `npx vitest run tests/unit/learningKnowledgeProvider.test.ts`

Expected: FAIL because the modes, providers, factory and provenance fields do not exist.

- [ ] **Step 4: Implement provider contracts and factory**

```ts
export type KnowledgeReference = {
  id: string;
  title: string;
  url?: string;
  version?: string;
};

export type KnowledgeContext = {
  atomId: string;
  title: string;
  studentStage: string;
  boundary: KnowledgeBoundary;
  facts: string[];
  relations: KnowledgeRelation[];
  allowedMaterialIds: string[];
  provider: 'none' | 'mock' | 'remote';
  providerVersion: string | null;
  references: KnowledgeReference[];
};
```

`RemoteKnowledgeProvider` uses an injected `fetchImpl`, `AbortSignal.timeout`, Zod response schemas and the configured base URL. The factory rejects `mock` in production and rejects `remote` without a base URL.

- [ ] **Step 5: Add provenance migration and repository round-trip test**

Migration SQL:

```sql
ALTER TABLE `thinking_nodes`
  ADD COLUMN `knowledgeProvider` VARCHAR(50) NULL,
  ADD COLUMN `knowledgeVersion` VARCHAR(100) NULL,
  ADD COLUMN `knowledgeReferences` JSON NULL;
```

The repository test creates a node with literal provenance and asserts the aggregate reads the same values back.

- [ ] **Step 6: Run repository test and verify RED before production persistence edits**

Run: `npx vitest run tests/unit/learningSessionRepository.test.ts`

Expected: FAIL because node persistence does not round-trip the new fields.

- [ ] **Step 7: Persist provider metadata and assemble the selected provider**

Map provider metadata in `buildNode`, Prisma create/read conversion and the memory aggregate. Replace the unconditional `new MockKnowledgeProvider()` in `server.ts` with the factory.

- [ ] **Step 8: Run Task 3 verification**

Run: `npx vitest run tests/unit/learningKnowledgeProvider.test.ts tests/unit/learningSessionAiPolicy.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionTeachingEngine.test.ts`

Expected: all selected tests pass and model-prior behavior remains covered.

- [ ] **Step 9: Validate Prisma schema without applying a remote migration**

Run: `npx prisma validate`

Expected: schema is valid. Do not run `prisma migrate deploy` against a non-local database during implementation.

- [ ] **Step 10: Commit Task 3 under the dirty-tree safeguard**

```bash
git add .env.example lib/learning-session/contracts.ts lib/learning-session/knowledgeProvider.ts lib/learning-session/mockKnowledgeProvider.ts lib/learning-session/noKnowledgeProvider.ts lib/learning-session/remoteKnowledgeProvider.ts lib/learning-session/knowledgeProviderFactory.ts lib/learning-session/server.ts lib/learning-session/repository.ts lib/learning-session/memoryRepository.ts lib/learning-session/sessionService.ts prisma/schema.prisma prisma/migrations/20260809_learning_knowledge_provenance/migration.sql tests/unit/learningKnowledgeProvider.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionService.test.ts
git commit -m "feat(learning): add configurable knowledge provider"
```

---

### Task 4: Versioned prestudy handoff contract

**Files:**
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/prestudyHandoff.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/http.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/prestudyHandoff.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRoutes.test.ts`

**Interfaces:**
- Produces: `PrestudyHandoffV1` and `buildPrestudyHandoff(aggregate)`.
- Keeps: existing `GET /api/learning-sessions/{id}/export` route, now returning the public handoff DTO.

- [ ] **Step 1: Write a failing literal handoff snapshot test**

Create a two-node aggregate with one branch and one contradicted node. Assert exact high-level output:

```ts
expect(buildPrestudyHandoff(aggregate)).toMatchObject({
  schemaVersion: 1,
  module: 'PRESTUDY',
  session: { id: 'session-1', status: 'COMPLETED' },
  observations: {
    misconceptionNodeIds: ['node-2'],
    interestBranchNodeIds: ['node-2'],
  },
  nextModule: { kind: 'PRACTICE' },
});
```

Also assert every concept `evidenceNodeId` resolves to an exported dialogue node.

- [ ] **Step 2: Run handoff test and verify RED**

Run: `npx vitest run tests/unit/prestudyHandoff.test.ts`

Expected: FAIL because the public contract builder does not exist.

- [ ] **Step 3: Implement the handoff builder**

The builder receives a complete aggregate, calls the existing concept projection, preserves all node IDs and parent IDs, exposes knowledge provenance, lists unvalidated concepts, and never emits practice mastery.

- [ ] **Step 4: Route export through the handoff builder**

Keep ownership checks in `LearningSessionService.exportTree`; replace the ad-hoc payload with `buildPrestudyHandoff(aggregate)` so downstream consumers receive a stable versioned DTO.

- [ ] **Step 5: Run Task 4 verification**

Run: `npx vitest run tests/unit/prestudyHandoff.test.ts tests/unit/learningSessionRoutes.test.ts tests/unit/learningSessionService.test.ts`

Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 4 under the dirty-tree safeguard**

```bash
git add lib/learning-session/prestudyHandoff.ts lib/learning-session/sessionService.ts lib/learning-session/http.ts tests/unit/prestudyHandoff.test.ts tests/unit/learningSessionRoutes.test.ts
git commit -m "feat(learning): publish prestudy handoff contract"
```

---

### Task 5: Flutter authenticated restore and account history UI

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/developer_tools.dart`
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`
- Modify: `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`
- Create: `test/features/dialogue_exploration/remote_exploration_identity_test.dart`

**Interfaces:**
- Produces: `RemoteExplorationIdentity` and `RemoteExplorationIdentityProvider`.
- Produces: `RemoteLearningSessionSummary` DTO.
- Extends gateway with `listSessions()` and `restoreSession(summary)`.
- Extends controller state with immutable `history` and explicit `openHistorySession(id)`.

- [ ] **Step 1: Write failing identity/header tests**

Use a recording `http.Client`. Assert a logged-in identity emits:

```dart
expect(request.headers['authorization'], 'Bearer token-a');
expect(request.headers['x-miniapp-client'], 'uniprism-weapp');
```

Assert an anonymous identity emits `x-anonymous-id` and no Authorization header.

- [ ] **Step 2: Run identity test and verify RED**

Run: `flutter test test/features/dialogue_exploration/remote_exploration_identity_test.dart`

Expected: FAIL because identity injection does not exist.

- [ ] **Step 3: Implement identity injection without importing `main.dart` into the feature**

```dart
final class RemoteExplorationIdentity {
  const RemoteExplorationIdentity({
    required this.exploreSessionId,
    this.bearerToken,
    this.anonymousId,
  });

  final String exploreSessionId;
  final String? bearerToken;
  final String? anonymousId;
}

typedef RemoteExplorationIdentityProvider =
    Future<RemoteExplorationIdentity> Function();
```

`DeveloperToolsPage`, which is already a `part of main.dart`, adapts `AuthService.instance` into this interface. The dialogue feature remains independent of the application auth implementation.

- [ ] **Step 4: Write failing DTO/controller restore tests**

Test literal history JSON parsing, newest ACTIVE selection, no-history behavior, account identity refresh, opening a completed session read-only, and failure/retry behavior.

- [ ] **Step 5: Run controller tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`

Expected: FAIL because server-backed history methods and state do not exist.

- [ ] **Step 6: Implement list and restore flow**

`RemoteExplorationApi.listSessions()` calls the new collection GET endpoint. `restoreLatest()` selects the newest ACTIVE summary, then calls the existing detail endpoint with that summary's `exploreSessionId`. The controller exposes immutable history and only enables composer mutations for ACTIVE, unexpired sessions.

- [ ] **Step 7: Write failing Widget tests for history and read-only sessions**

Assert the lab shows “历史预习”, selecting a completed item shows its node map, the composer is disabled with “该预习已结束，仅支持查看”, and account history load failures expose a retry button.

- [ ] **Step 8: Run Widget tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: FAIL because history UI and read-only presentation are absent.

- [ ] **Step 9: Implement the minimal history UI**

Add a compact history section/sheet using server summaries. Keep write actions in the controller, keep API calls in the gateway, and keep DTO parsing in adapters. Existing mainline, branch and node-map behavior must remain unchanged.

- [ ] **Step 10: Run Task 5 verification**

Run: `flutter test test/features/dialogue_exploration/remote_exploration_identity_test.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/live_tree_page_test.dart test/features/dialogue_exploration/remote_learning_graph_test.dart`

Expected: all selected tests pass.

- [ ] **Step 11: Run module analysis**

Run: `dart analyze lib/main.dart lib/developer_tools.dart lib/features/dialogue_exploration test/features/dialogue_exploration`

Expected: no issues.

- [ ] **Step 12: Commit Task 5 under the dirty-tree safeguard**

```bash
git add lib/main.dart lib/developer_tools.dart lib/features/dialogue_exploration/adapters/remote_exploration_api.dart lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart lib/features/dialogue_exploration/presentation/remote_exploration_page.dart test/features/dialogue_exploration/remote_exploration_identity_test.dart test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/live_tree_page_test.dart
git commit -m "feat(prestudy): restore account learning history"
```

---

### Task 6: Delivery documentation, smoke verification, and acceptance audit

**Files:**
- Create: `docs/PRESTUDY_MODULE_HANDOFF.md`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/scripts/run-learning-dialogue-smoke.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/.env.example`
- Modify: `docs/superpowers/plans/2026-08-09-prestudy-account-persistence-provider-handoff.md`

**Interfaces:**
- Documents: account restore, provider modes, `PrestudyHandoffV1`, downstream practice integration and completion matrix.
- Extends: smoke script to verify history listing and exported handoff after the multi-turn branch scenario.

- [ ] **Step 1: Extend the smoke script assertions before changing runtime code**

After creating three main nodes and one branch, call the history endpoint and export endpoint. Assert the created session appears first, `schemaVersion === 1`, `module === 'PRESTUDY'`, every parent ID resolves, and every concept evidence ID resolves.

- [ ] **Step 2: Run the smoke script and verify the new assertions fail**

Run: `npx tsx scripts/run-learning-dialogue-smoke.ts`

Expected: FAIL until the running backend contains account/history and `PrestudyHandoffV1` changes. The script must continue to reject non-local targets unless explicitly allowed.

- [ ] **Step 3: Write the handoff document**

Document exact responsibilities, DTO fields, API calls, environment variables, login/restore flow, provider fallback behavior, sample JSON, test commands, known limitations and a completion table with `已完成 | 条件可用 | 未实现` states.

- [ ] **Step 4: Run complete backend verification**

Run: `npx vitest run tests/unit/learningSessionStorageMode.test.ts tests/unit/learningSessionOwnership.test.ts tests/unit/learningKnowledgeProvider.test.ts tests/unit/prestudyHandoff.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRoutes.test.ts tests/unit/learningSessionTeachingEngine.test.ts tests/unit/learningSessionAiPolicy.test.ts`

Run: `npx tsc --noEmit`

Run: `npx prisma validate`

Expected: all selected tests pass, TypeScript exits 0, Prisma schema validates.

- [ ] **Step 5: Run complete Flutter verification**

Run: `flutter test`

Run: `dart analyze lib/main.dart lib/developer_tools.dart lib/features/dialogue_exploration test/features/dialogue_exploration`

Expected: all Flutter tests pass and analysis reports no issues.

- [ ] **Step 6: Run local HTTP smoke verification**

Run with `LEARNING_SESSION_STORAGE=prisma`, `LEARNING_KNOWLEDGE_PROVIDER=none`, a local backend URL and a local/test database whose learning migrations are applied:

```bash
npx tsx scripts/run-learning-dialogue-smoke.ts
```

Expected: real AI multi-turn dialogue, branch creation, history listing, restart-safe detail fetch and `PrestudyHandoffV1` export all pass. Do not apply migrations to a remote shared database without explicit user authorization.

- [ ] **Step 7: Update the plan checkboxes and document actual limitations**

Mark only executed steps complete. If a real-account re-login or process restart test cannot run because a local database or login credential is unavailable, keep that acceptance item incomplete and state the exact external prerequisite in `docs/PRESTUDY_MODULE_HANDOFF.md`.

- [ ] **Step 8: Commit documentation and smoke updates under the dirty-tree safeguard**

```bash
git add docs/PRESTUDY_MODULE_HANDOFF.md docs/superpowers/plans/2026-08-09-prestudy-account-persistence-provider-handoff.md
git commit -m "docs(prestudy): publish module handoff guide"
```

In the backend repository, stage only `scripts/run-learning-dialogue-smoke.ts` and `.env.example` if they contain no unrelated edits, then commit with `test(learning): verify persistent prestudy handoff`.

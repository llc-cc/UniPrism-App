# Model-Prior Dialogue Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让没有知识库命中的自由问题也能使用真实模型完成“直接回答 → 基于用户表达追问 → 保存节点 → 展示路径/支线”的闭环，并为未来知识库接入保留稳定优先级与来源元数据。

**Architecture:** 后端新增独立 AI 模式策略，将 `auto / remote / local` 与 `MODEL_PRIOR / KNOWLEDGE_BASE / SAFE_FALLBACK` 分离；教学引擎在单次结构化模型调用中生成回答、追问、意图和 `mapLabel`。Session Service 原子性保存来源元数据，Flutter 继续使用现有 `nodes/conceptNodes`，仅补充兼容解析与来源提示。

**Tech Stack:** Next.js 16、TypeScript、Vitest、Prisma/MySQL、DeepSeek JSON API、Flutter/Dart、flutter_test。

## Global Constraints

- 正式知识库不是本计划的依赖；`KnowledgeProvider` 返回空事实时必须允许 `MODEL_PRIOR`。
- 知识事实存在时必须使用 `KNOWLEDGE_BASE`，且知识库事实优先于模型记忆。
- 回答来源值固定为 `MODEL_PRIOR | KNOWLEDGE_BASE | SAFE_FALLBACK`。
- 轮次意图值固定为 `NEW_QUESTION | ANSWER_TO_TUTOR | HELP_REQUEST | TOPIC_SWITCH`。
- 开发默认 `auto`，生产固定 `remote`；`LEARNING_REMOTE_AI_IN_DEV=1` 兼容映射到 `remote`。
- 不新增前端模型密钥、数据库配置或模型调用；所有外部 AI 请求只发生在后端。
- 保持现有 HTTP 路径、`nodes`、`conceptNodes` 和节点交互向后兼容。
- 新增或实质修改的业务决策、异步失败分支和数据安全逻辑写简洁中文注释。
- 两个仓库均有既有未提交改动；执行时先记录目标文件基线，不自动提交包含用户原有改动的文件。只有完全新增且独立的文件可单独提交，其他改动在最终验收后由用户决定如何整理提交。

## File Structure

### Backend: `D:/ywkeji/Uniprism/UniPrism_New-main`

- Create: `lib/learning-session/aiPolicy.ts` — AI 运行模式、回答来源与远程失败策略。
- Modify: `lib/learning-session/contracts.ts` — 共享的回答来源和轮次意图类型。
- Modify: `lib/learning-session/dialogueEngine.ts` — 真实模型调用、结构化输出、来源和意图。
- Modify: `lib/learning-session/prompts.ts` — `MODEL_PRIOR` 与 `KNOWLEDGE_BASE` 提示词。
- Modify: `lib/learning-session/sessionService.ts` — 将来源和意图写入 ThinkingNode。
- Modify: `lib/learning-session/repository.ts` — Prisma 往返字段。
- Modify: `prisma/schema.prisma` — ThinkingNode 可空元数据字段。
- Create: `prisma/migrations/20260808_learning_turn_ai_metadata/migration.sql` — 数据库增量迁移。
- Modify: `tests/unit/learningSessionTeachingEngine.test.ts` — 无知识库真实模型与模式行为。
- Modify: `tests/unit/learningSessionService.test.ts` — 节点保存与支线上下文。
- Modify: `tests/unit/learningSessionRepository.test.ts` — Prisma 元数据往返。
- Modify: `tests/unit/learningSessionRoutes.test.ts` — API 响应兼容。
- Create: `scripts/run-learning-dialogue-smoke.ts` — 本地三轮和支线 HTTP 验收。
- Modify: `.env.example` — AI 模式配置说明。

### Flutter: `D:/dev/Uniprism/uniprism_app`

- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart` — 可空解析 `answerSource` 与 `turnIntent`。
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart` — 展示真实模型/知识库/安全兜底来源。
- Modify: `test/features/dialogue_exploration/remote_learning_graph_test.dart` — DTO 兼容。
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart` — 来源提示和节点交互回归。

---

### Task 1: AI 模式与回答来源策略

**Files:**
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/aiPolicy.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/contracts.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionAiPolicy.test.ts`

**Interfaces:**
- Produces: `LearningAiMode`, `LearningAnswerSource`, `LearningTurnIntent`。
- Produces: `resolveLearningAiMode(env?: NodeJS.ProcessEnv): LearningAiMode`。
- Produces: `answerSourceForKnowledge(context: KnowledgeContext): Exclude<LearningAnswerSource, 'SAFE_FALLBACK'>`。
- Produces: `shouldUseRemoteLearningAi(mode: LearningAiMode): boolean`。

- [ ] **Step 1: 写 AI 模式失败测试**

```ts
import { describe, expect, it } from 'vitest';
import {
  answerSourceForKnowledge,
  resolveLearningAiMode,
  shouldUseRemoteLearningAi,
} from '@/lib/learning-session/aiPolicy';

describe('learning AI policy', () => {
  it('defaults development to auto and production to remote', () => {
    expect(resolveLearningAiMode({ NODE_ENV: 'development' })).toBe('auto');
    expect(resolveLearningAiMode({ NODE_ENV: 'production', LEARNING_AI_MODE: 'local' })).toBe('remote');
  });

  it('keeps the legacy development switch compatible', () => {
    expect(resolveLearningAiMode({ NODE_ENV: 'development', LEARNING_REMOTE_AI_IN_DEV: '1' })).toBe('remote');
  });

  it('derives the answer source from optional knowledge facts', () => {
    expect(answerSourceForKnowledge({
      atomId: 'free-question', title: '自由问题', studentStage: '未提供',
      boundary: 'UNRELATED', facts: [], relations: [], allowedMaterialIds: [],
    })).toBe('MODEL_PRIOR');
  });

  it('calls remote AI in auto and remote modes only', () => {
    expect(shouldUseRemoteLearningAi('auto')).toBe(true);
    expect(shouldUseRemoteLearningAi('remote')).toBe(true);
    expect(shouldUseRemoteLearningAi('local')).toBe(false);
  });
});
```

- [ ] **Step 2: 运行测试并确认因模块不存在而失败**

Run:

```powershell
npx vitest run tests/unit/learningSessionAiPolicy.test.ts
```

Expected: FAIL，提示无法解析 `aiPolicy` 或缺少导出类型。

- [ ] **Step 3: 添加共享类型和纯策略函数**

在 `contracts.ts` 导出：

```ts
export type LearningAiMode = 'auto' | 'remote' | 'local';
export type LearningAnswerSource = 'MODEL_PRIOR' | 'KNOWLEDGE_BASE' | 'SAFE_FALLBACK';
export type LearningTurnIntent =
  | 'NEW_QUESTION'
  | 'ANSWER_TO_TUTOR'
  | 'HELP_REQUEST'
  | 'TOPIC_SWITCH';
```

在 `aiPolicy.ts` 实现：

```ts
import type { KnowledgeContext, LearningAiMode, LearningAnswerSource } from './contracts';

export function resolveLearningAiMode(env: NodeJS.ProcessEnv = process.env): LearningAiMode {
  if (env.NODE_ENV === 'production') return 'remote';
  if (env.LEARNING_REMOTE_AI_IN_DEV === '1') return 'remote';
  const configured = env.LEARNING_AI_MODE?.trim().toLowerCase();
  if (configured === 'remote' || configured === 'local' || configured === 'auto') return configured;
  return 'auto';
}

export function shouldUseRemoteLearningAi(mode: LearningAiMode) {
  return mode !== 'local';
}

export function answerSourceForKnowledge(
  context: KnowledgeContext,
): Exclude<LearningAnswerSource, 'SAFE_FALLBACK'> {
  return context.facts.length > 0 ? 'KNOWLEDGE_BASE' : 'MODEL_PRIOR';
}
```

- [ ] **Step 4: 运行策略测试并确认通过**

Run:

```powershell
npx vitest run tests/unit/learningSessionAiPolicy.test.ts
```

Expected: 4 tests passed。

- [ ] **Step 5: 检查任务差异，不暂存既有修改**

Run:

```powershell
git diff --check -- lib/learning-session/aiPolicy.ts lib/learning-session/contracts.ts tests/unit/learningSessionAiPolicy.test.ts
```

Expected: exit 0；记录新增文件和 `contracts.ts` 的任务差异，保留用户原有未提交内容。

### Task 2: 无知识库的真实结构化回答与追问

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/dialogueEngine.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/prompts.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionTeachingEngine.test.ts`

**Interfaces:**
- Consumes: `resolveLearningAiMode`、`shouldUseRemoteLearningAi`、`answerSourceForKnowledge`。
- Produces: `EvaluatedTeachingTurn.answerSource: LearningAnswerSource`。
- Produces: `EvaluatedTeachingTurn.turnIntent: LearningTurnIntent`。
- Produces: `buildTeachingSystemPrompt(decision, scenarioId, answerSource)`。
- Produces: `buildTeachingUserPrompt(...)` 中的 `answerSource` 与最近五轮 `activePath`。

- [ ] **Step 1: 写空知识事实使用真实模型的失败测试**

在 `learningSessionTeachingEngine.test.ts` 添加一个注入 `callJson` 的测试，捕获提示词并返回：

```ts
const callJson = vi.fn(async () => ({
  content: JSON.stringify({
    answer: '海水呈蓝色主要因为水对长波光吸收更强，并伴随散射。',
    followUpQuestion: '如果水层变得更深，颜色变化最可能体现在哪一部分，依据是什么？',
    mapLabel: '海水颜色形成',
    turnIntent: 'NEW_QUESTION',
    detectedMisconception: null,
    confidence: 0.82,
    materialIds: [],
    sideBranchSuggested: false,
  }),
  model: 'deepseek-test',
  usage: {},
  latencyMs: 8,
}));
const engine = new LearningDialogueEngine({ callJson });
const result = await engine.generateTurn(freeQuestionInput('海水为什么是蓝色？'));

expect(result.answerSource).toBe('MODEL_PRIOR');
expect(result.turnIntent).toBe('NEW_QUESTION');
expect(result.model).toBe('deepseek-test');
expect(callJson).toHaveBeenCalledOnce();
expect(JSON.stringify(callJson.mock.calls[0]![0].messages)).toContain('允许使用模型自身通识知识');
```

同时添加：

- `KNOWLEDGE_BASE` 提示词声明知识事实优先；
- 当前问题是“我还是不懂”时输出 `HELP_REQUEST`；
- 当前路径包含上一轮回答时，user prompt 含该回答；
- `remote` 模式调用失败时拒绝 Promise；
- `auto` 模式调用失败时返回 `SAFE_FALLBACK`；
- `local` 模式不调用 `callJson` 并返回 `SAFE_FALLBACK`。

- [ ] **Step 2: 运行目标测试并确认新断言失败**

Run:

```powershell
npx vitest run tests/unit/learningSessionTeachingEngine.test.ts
```

Expected: 新用例因缺少 `answerSource`、`turnIntent` 和模式控制失败。

- [ ] **Step 3: 扩展结构 Schema 和提示词**

在 `generatedTurnSchema` 增加：

```ts
turnIntent: z.enum([
  'NEW_QUESTION',
  'ANSWER_TO_TUTOR',
  'HELP_REQUEST',
  'TOPIC_SWITCH',
]),
```

提示词调用改为：

```ts
const answerSource = answerSourceForKnowledge(input.knowledge);
buildTeachingSystemPrompt(decision, input.scenarioId, answerSource);
buildTeachingUserPrompt({
  ...existingInput,
  answerSource,
});
```

`MODEL_PRIOR` 系统规则明确写入：

```ts
'当前没有知识库事实。允许使用模型自身通识知识直接回答；不得编造引用、教材出处、实验数据或已经验证的学生掌握结论。'
```

`KNOWLEDGE_BASE` 系统规则明确写入：

```ts
'当前存在知识库事实。回答以 knowledgeBoundary.facts 为最高优先级；模型记忆与其冲突时以输入事实为准。'
```

- [ ] **Step 4: 用模式策略替换开发环境硬编码短路**

核心控制流实现为：

```ts
const mode = resolveLearningAiMode();
if (!shouldUseRemoteLearningAi(mode)) {
  return localDevelopmentTurn(input, decision, localMisconception);
}

// 成功模型结果使用 answerSourceForKnowledge(input.knowledge)。
// remote 失败重新抛出；auto 失败进入 SAFE_FALLBACK。
if (mode === 'remote' && generationError) throw generationError;
```

本地兜底补充确定性意图：

```ts
function inferTurnIntent(input: TeachingEngineInput): LearningTurnIntent {
  if (input.isStuck || /不懂|不知道|不会|卡住/.test(input.question)) return 'HELP_REQUEST';
  if (input.path.length === 0) return 'NEW_QUESTION';
  if (/什么|为什么|如何|怎么|哪/.test(input.question)) return 'NEW_QUESTION';
  return 'ANSWER_TO_TUTOR';
}
```

- [ ] **Step 5: 运行教学引擎测试并确认通过**

Run:

```powershell
npx vitest run tests/unit/learningSessionTeachingEngine.test.ts
```

Expected: 全部通过；空知识事实用例的 `model` 为 `deepseek-test` 而不是 `local-safe-fallback`。

- [ ] **Step 6: 运行提示词与策略相关回归测试**

Run:

```powershell
npx vitest run tests/unit/learningSessionTeachingEngine.test.ts tests/unit/learningSessionAiPolicy.test.ts tests/unit/learningSessionService.test.ts
```

Expected: 全部通过。

### Task 3: ThinkingNode 来源与意图持久化

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/prisma/schema.prisma`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/prisma/migrations/20260808_learning_turn_ai_metadata/migration.sql`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/repository.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRepository.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionService.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionRoutes.test.ts`

**Interfaces:**
- Consumes: `EvaluatedTeachingTurn.answerSource` 与 `turnIntent`。
- Produces: `LearningThinkingNode.answerSource: LearningAnswerSource | null`。
- Produces: `LearningThinkingNode.turnIntent: LearningTurnIntent | null`。
- Produces: API `nodes[*].answerSource` 与 `nodes[*].turnIntent`。

- [ ] **Step 1: 写仓储与服务失败测试**

服务测试在创建自由问题后断言：

```ts
expect(snapshot.nodes[0]).toMatchObject({
  answerSource: 'MODEL_PRIOR',
  turnIntent: 'NEW_QUESTION',
  model: 'deepseek-test',
});
```

支线测试让假教学引擎记录 `input.path`：

```ts
expect(branchInput.path.map((item) => item.question)).toEqual([
  '根问题',
  '从根节点开的支线问题',
]);
expect(branchInput.path).not.toContainEqual(
  expect.objectContaining({ question: '主线后续问题' }),
);
```

仓储测试完成 create/get 往返后断言两个字段保持不变；路由测试断言响应 JSON 包含两个字段。

- [ ] **Step 2: 运行服务、仓储和路由测试并确认失败**

Run:

```powershell
npx vitest run tests/unit/learningSessionService.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionRoutes.test.ts
```

Expected: 新字段不存在或 Prisma 类型不接受字段。

- [ ] **Step 3: 添加 Prisma 字段和迁移**

`ThinkingNode` 增加：

```prisma
answerSource      String?            @db.VarChar(32)
turnIntent       String?            @db.VarChar(32)
```

迁移内容：

```sql
ALTER TABLE `ThinkingNode`
  ADD COLUMN `answerSource` VARCHAR(32) NULL,
  ADD COLUMN `turnIntent` VARCHAR(32) NULL;
```

- [ ] **Step 4: 贯通 TypeScript 仓储和 Session Service**

`LearningThinkingNode` 增加：

```ts
answerSource: LearningAnswerSource | null;
turnIntent: LearningTurnIntent | null;
```

`buildNode` 写入：

```ts
answerSource: input.generated.answerSource,
turnIntent: input.generated.turnIntent,
```

`nodeCreateData` 与 `toAggregate` 对称映射两个字段。回溯和反思节点显式使用 `null`，避免伪造 AI 来源。

- [ ] **Step 5: 生成 Prisma Client 并运行目标测试**

Run:

```powershell
npm run db:generate
```

Run:

```powershell
npx vitest run tests/unit/learningSessionService.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionRoutes.test.ts
```

Expected: Prisma 生成成功，目标测试全部通过。

- [ ] **Step 6: 运行后端类型检查**

Run:

```powershell
npm run typecheck
```

Expected: exit 0。

### Task 4: Flutter 兼容解析与来源展示

**Files:**
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `test/features/dialogue_exploration/remote_learning_graph_test.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: API 可空字段 `answerSource` 与 `turnIntent`。
- Produces: `RemoteLearningNode.answerSource`、`RemoteLearningNode.turnIntent`。
- Produces: `_answerSourceLabel(RemoteLearningNode): String?`。

- [ ] **Step 1: 写 DTO 和 Widget 失败测试**

DTO 测试增加：

```dart
expect(snapshot.nodes.single.answerSource, 'MODEL_PRIOR');
expect(snapshot.nodes.single.turnIntent, 'NEW_QUESTION');
```

Widget fixture 分别传入 `MODEL_PRIOR` 与 `SAFE_FALLBACK`，断言：

```dart
expect(find.text('真实 AI · 模型知识'), findsOneWidget);
expect(find.text('安全兜底'), findsNothing);
```

安全兜底用例断言 `find.text('安全兜底')` 为一个；旧响应缺少字段时不显示来源标签且页面不抛异常。

- [ ] **Step 2: 运行目标 Flutter 测试并确认失败**

Run:

```powershell
flutter test --no-pub test/features/dialogue_exploration/remote_learning_graph_test.dart test/features/dialogue_exploration/live_tree_page_test.dart
```

Expected: DTO 缺少字段或页面找不到来源文字。

- [ ] **Step 3: 添加可空 DTO 字段**

`RemoteLearningNode.fromJson` 增加：

```dart
answerSource: _nullableString(json['answerSource']),
turnIntent: _nullableString(json['turnIntent']),
```

构造器字段：

```dart
final String? answerSource;
final String? turnIntent;
```

- [ ] **Step 4: 在回答卡片显示真实来源**

在回答正文上方或下方添加紧凑标签，旧数据不显示：

```dart
final sourceLabel = _answerSourceLabel(node);
if (sourceLabel != null) ...[
  const SizedBox(height: 6),
  Text(sourceLabel, style: const TextStyle(fontSize: 12, color: _muted)),
]
```

映射规则：

```dart
String? _answerSourceLabel(RemoteLearningNode node) => switch (node.answerSource) {
  'MODEL_PRIOR' => '真实 AI · 模型知识',
  'KNOWLEDGE_BASE' => '真实 AI · 知识库依据',
  'SAFE_FALLBACK' => '安全兜底',
  _ => null,
};
```

- [ ] **Step 5: 运行目标测试与模块分析**

Run:

```powershell
flutter test --no-pub test/features/dialogue_exploration/remote_learning_graph_test.dart test/features/dialogue_exploration/live_tree_page_test.dart
```

Run:

```powershell
flutter analyze --no-pub lib/features/dialogue_exploration test/features/dialogue_exploration
```

Expected: 测试全部通过，分析无问题。

### Task 5: 配置、真实 HTTP 烟测与全量回归

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/.env.example`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/scripts/run-learning-dialogue-smoke.ts`

**Interfaces:**
- Consumes: `LEARNING_AI_MODE=auto|remote|local`、`API_BASE_URL`。
- Produces: 本地三轮与支线验收命令，失败时进程 exit code 为 1。

- [ ] **Step 1: 在 `.env.example` 记录明确配置**

加入：

```dotenv
# auto: 有密钥时真实 AI、失败时安全兜底；remote: 必须真实 AI；local: 确定性离线模式
LEARNING_AI_MODE="auto"
DEEPSEEK_LEARNING_MODEL="deepseek-v4-flash"
LEARNING_MODEL_TIMEOUT_MS="25000"
```

保留 `DEEPSEEK_API_KEY` 空值示例，不写入真实密钥。

- [ ] **Step 2: 编写 HTTP 烟测脚本**

脚本依次：

```ts
const baseUrl = (process.env.API_BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
const identity = await post('/api/explore/session', {});
const created = await post('/api/learning-sessions', {
  exploreSessionId: identity.sessionId,
  scenarioId: 'prestudy',
  question: '海水为什么是蓝色？',
});
const second = await post(`/api/learning-sessions/${created.session.id}/turns`, {
  exploreSessionId: identity.sessionId,
  question: '我理解是不同颜色被吸收的程度不同，这样对吗？',
});
const third = await post(`/api/learning-sessions/${created.session.id}/turns`, {
  exploreSessionId: identity.sessionId,
  question: '如果水更深，颜色会怎样变化？',
});
const branched = await post(`/api/learning-sessions/${created.session.id}/branches`, {
  exploreSessionId: identity.sessionId,
  parentNodeId: created.currentNodeId,
  question: '如果换成天空，蓝色形成机制相同吗？',
});

assert.equal(third.nodes.length, 3);
assert.equal(branched.nodes.at(-1)?.isSideBranch, true);
assert.ok(third.nodes.every((node) => node.answer && node.followUpQuestion));
assert.ok(third.nodes.every((node) => node.answerSource === 'MODEL_PRIOR'));
assert.ok(new Set(third.nodes.map((node) => node.followUpQuestion)).size === 3);
```

请求头固定包含 `content-type: application/json`、`x-miniapp-client: uniprism-smoke` 和唯一 `idempotency-key`。脚本只连接显式 `API_BASE_URL` 或默认本地 3000，不接受生产地址作为默认值。

- [ ] **Step 3: 运行后端目标测试、类型检查和烟测**

Run:

```powershell
npx vitest run tests/unit/learningSessionAiPolicy.test.ts tests/unit/learningSessionTeachingEngine.test.ts tests/unit/learningSessionService.test.ts tests/unit/learningSessionRepository.test.ts tests/unit/learningSessionRoutes.test.ts
```

Run:

```powershell
npm run typecheck
```

Run（本地后端已使用新代码和真实模型配置启动时）：

```powershell
npx tsx scripts/run-learning-dialogue-smoke.ts
```

Expected: 单元测试和类型检查通过；烟测输出 3 个主线路径节点、1 个支线节点、实际模型名以及互不重复的三条追问。

- [ ] **Step 4: 运行 Flutter 全模块回归**

Run:

```powershell
flutter test --no-pub test/features/dialogue_exploration
```

Run:

```powershell
flutter analyze --no-pub lib/features/dialogue_exploration test/features/dialogue_exploration
```

Expected: 对话探索测试全部通过，静态分析无问题。

- [ ] **Step 5: 人工页面验收**

Run:

```powershell
flutter run -d chrome --web-hostname localhost --web-port 3001 --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=API_BASE_URL=http://localhost:3000
```

依次完成：

1. 开发者工具 → 1.2 对话探索实验室。
2. 直接提问一个 Mock 原子未收录的问题。
3. 确认回答卡显示“真实 AI · 模型知识”。
4. 连续回答 AI 追问三轮，确认追问引用当前表达且不重复。
5. 打开“查看探索过程”，确认节点增长。
6. 从首节点新开支线，确认新节点标记支线且主线保留。

- [ ] **Step 6: 汇总未提交差异与交付证据**

Run:

```powershell
git status --short
```

分别在 Flutter 与后端仓库记录：目标文件、测试结果、真实烟测模型名和仍需用户决定的提交范围。不得把两个仓库中原有的无关或预先存在改动包含进自动提交。

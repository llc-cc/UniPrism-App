# Knowledge Forest Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a development-only vertical slice that extracts structured knowledge from an Agent answer with DeepSeek, lets the user review it, and renders the confirmed in-memory topic tree in Flutter.

**Architecture:** The backend exposes a guarded development endpoint backed by the existing `callDeepSeekJson` wrapper and a strict Zod contract. Flutter keeps third-party mind-map types behind an adapter, stores confirmed trees only for the current process, and adds extraction preview plus forest/tree pages to the existing Agent flow.

**Tech Stack:** Flutter/Dart 3.12, `reactive_mind_map` 1.2.2, Next.js route handlers, TypeScript, Zod, DeepSeek JSON wrapper, Vitest, Flutter widget tests.

## Global Constraints

- Pin `reactive_mind_map` to exact version `1.2.2`; do not reimplement layout, pan, zoom, focus, or expand/collapse.
- Keep `MindMapData` inside the rendering adapter and knowledge-tree widget boundary.
- DeepSeek remains server-side; no key, prompt, or unrestricted URL enters Flutter.
- The prototype is development-only and stores confirmed trees in memory until App restart.
- Candidate nodes never become confirmed nodes without an explicit user confirmation.
- Limit a batch to 12 nodes, a tree suggestion to one target, and visible primary parent-child edges only.
- Preserve all unrelated dirty-worktree changes and stage only task-owned files or reviewed hunks.
- Follow `docs/DEVELOPMENT_CODE_STANDARD.md`; explain state transitions and safety boundaries with concise Chinese comments.

---

## File Structure

- `.backend_patch/lib/knowledge-extraction/extractKnowledge.ts`: request/response schemas, prompt construction, model call, normalization, and injectable dependency.
- `.backend_patch/app/api/dev/knowledge/extract/route.ts`: development guard, origin check, body validation, rate limit, and response envelope.
- `.backend_patch/tests/unit/knowledgeExtraction.test.ts`: deterministic extraction and safety tests using a fake DeepSeek caller.
- `lib/knowledge_models.dart`: third-party-independent forest, tree, confirmed-node, candidate, edge, source, and batch models.
- `lib/knowledge_service.dart`: development endpoint client, response parsing, extraction state, and in-memory forest store.
- `lib/knowledge_forest.dart`: candidate preview, forest list, mind-map adapter/view, and node detail UI.
- `lib/main.dart`: library parts, third-party import, and named routes.
- `lib/agent_experience.dart`: stable message identity, extraction entry, preview navigation, and forest navigation.
- `pubspec.yaml` / `pubspec.lock`: exact `reactive_mind_map` dependency.
- `test/knowledge_forest_test.dart`: model, store, adapter, preview, forest, and Agent integration tests.

---

### Task 1: Backend Knowledge Extraction Contract

**Files:**
- Create: `.backend_patch/lib/knowledge-extraction/extractKnowledge.ts`
- Create: `.backend_patch/tests/unit/knowledgeExtraction.test.ts`

**Interfaces:**
- Consumes: `callDeepSeekJson(options)` from `@/lib/ai/deepseek`.
- Produces: `extractKnowledgeBatch(input, caller?)`, `knowledgeExtractionInputSchema`, `KnowledgeExtractionBatch`, and `KnowledgeExtractionError`.

- [ ] **Step 1: Write the failing normalization tests**

```ts
import { describe, expect, it, vi } from 'vitest';
import { extractKnowledgeBatch } from '@/lib/knowledge-extraction/extractKnowledge';

const validInput = {
  conversationId: 'conv-1',
  messageId: 'msg-1',
  question: '人工智能专业学什么？',
  answer: '人工智能专业包括机器学习、智能系统和工程实践。',
  availableTrees: [{ id: 'tree-ai', title: '人工智能' }],
  clientTraceId: 'trace-1',
};

describe('knowledge extraction', () => {
  it('normalizes a valid DeepSeek batch and keeps only known parents', async () => {
    const caller = vi.fn().mockResolvedValue({
      content: JSON.stringify({
        suggestedTree: { mode: 'existing', treeId: 'tree-ai', title: '人工智能' },
        nodes: [
          { candidateId: 'root', parentCandidateId: null, type: 'topic', title: '人工智能', summary: '主题摘要', confidence: 0.91 },
          { candidateId: 'child', parentCandidateId: 'missing', type: 'concept', title: '机器学习', summary: '从数据学习规律', confidence: 0.83 },
        ],
        relatedEdges: [],
      }),
      model: 'deepseek-test',
      latencyMs: 12,
    });

    const result = await extractKnowledgeBatch({
      conversationId: 'conv-1',
      messageId: 'msg-1',
      question: '人工智能专业学什么？',
      answer: '人工智能专业包括机器学习等方向。',
      availableTrees: [{ id: 'tree-ai', title: '人工智能' }],
      clientTraceId: 'trace-1',
    }, caller);

    expect(result.nodes).toHaveLength(2);
    expect(result.nodes[1].parentCandidateId).toBeNull();
    expect(result.model).toBe('deepseek-test');
  });

  it('deduplicates titles and drops model-provided URLs', async () => {
    const caller = vi.fn().mockResolvedValue({
      content: JSON.stringify({
        suggestedTree: { mode: 'new', treeId: null, title: '数学' },
        nodes: [
          { candidateId: 'a', parentCandidateId: null, type: 'concept', title: '线性代数', summary: '研究向量空间', confidence: 0.8, sourceUrl: 'https://evil.example' },
          { candidateId: 'b', parentCandidateId: null, type: 'concept', title: '线性 代数', summary: '重复节点', confidence: 0.7 },
        ],
        relatedEdges: [],
      }),
      model: 'deepseek-test',
      latencyMs: 8,
    });
    const result = await extractKnowledgeBatch(validInput, caller);
    expect(result.nodes).toHaveLength(1);
    expect(result.nodes[0]).not.toHaveProperty('sourceUrl');
  });

  it('rejects empty model output instead of creating an empty tree', async () => {
    const caller = vi.fn().mockResolvedValue({
      content: JSON.stringify({
        suggestedTree: { mode: 'new', treeId: null, title: '空主题' },
        nodes: [],
        relatedEdges: [],
      }),
      model: 'deepseek-test',
      latencyMs: 5,
    });
    await expect(extractKnowledgeBatch(validInput, caller)).rejects.toMatchObject({
      code: 'NO_KNOWLEDGE_CANDIDATES',
    });
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts --run .backend_patch/tests/unit/knowledgeExtraction.test.ts
```

Expected: FAIL because `extractKnowledgeBatch` does not exist.

- [ ] **Step 3: Implement strict schemas and extraction**

```ts
const candidateSchema = z.object({
  candidateId: z.string().trim().min(1).max(80),
  parentCandidateId: z.string().trim().min(1).max(80).nullable(),
  type: z.enum(['topic', 'concept', 'insight', 'method', 'action', 'resource']),
  title: z.string().trim().min(1).max(80),
  summary: z.string().trim().min(1).max(240),
  confidence: z.number().min(0).max(1),
});

export async function extractKnowledgeBatch(
  input: KnowledgeExtractionInput,
  caller: typeof callDeepSeekJson = callDeepSeekJson,
): Promise<KnowledgeExtractionBatch> {
  const safeInput = knowledgeExtractionInputSchema.parse(input);
  const modelResult = await caller({
    modelEnvKey: 'DEEPSEEK_KNOWLEDGE_EXTRACTION_MODEL',
    fallbackModel: process.env.DEEPSEEK_DIALOGUE_MODEL || 'deepseek-v4-flash',
    messages: buildKnowledgeExtractionMessages(safeInput),
    temperature: 0.1,
    timeoutMs: 20_000,
    maxTokens: 1_600,
    thinking: 'disabled',
  });
  return normalizeKnowledgeBatch(modelResult, safeInput);
}
```

Normalization must cap nodes at 12, normalize titles for deduplication, clear missing/self parents, remove edges whose endpoints were dropped, mark all candidates selected by default, and generate `batchId` without trusting a model-supplied identifier.

- [ ] **Step 4: Run the backend test and verify it passes**

Run the Step 2 command. Expected: PASS for valid, duplicate, invalid-parent, and empty-output cases.

- [ ] **Step 5: Commit the backend contract when the scoped diff is clean**

```powershell
git add -- .backend_patch/lib/knowledge-extraction/extractKnowledge.ts .backend_patch/tests/unit/knowledgeExtraction.test.ts
git commit -m "feat: add knowledge extraction contract"
```

---

### Task 2: Development-Only Extraction Route

**Files:**
- Create: `.backend_patch/app/api/dev/knowledge/extract/route.ts`
- Modify: `.backend_patch/tests/unit/knowledgeExtraction.test.ts`

**Interfaces:**
- Consumes: `knowledgeExtractionInputSchema` and `extractKnowledgeBatch` from Task 1.
- Produces: `POST /api/dev/knowledge/extract` with the existing `{ ok, data }` response envelope.

- [ ] **Step 1: Add failing development-guard and limit tests**

```ts
import {
  assertKnowledgeExtractionEnvironment,
  knowledgeExtractionInputSchema,
} from '@/lib/knowledge-extraction/extractKnowledge';

it('rejects the extraction endpoint in production', () => {
  expect(() => assertKnowledgeExtractionEnvironment('production'))
    .toThrow(/仅用于开发联调/);
});

it('rejects oversized answers and more than 20 tree summaries', () => {
  expect(() => knowledgeExtractionInputSchema.parse({
    conversationId: 'conv-1',
    messageId: 'msg-1',
    question: '问题',
    answer: 'a'.repeat(6_001),
    availableTrees: [],
    clientTraceId: 'trace-1',
  })).toThrow();
});
```

- [ ] **Step 2: Run the focused backend test**

Expected: FAIL because `assertKnowledgeExtractionEnvironment` is not defined.

- [ ] **Step 3: Implement the guard and route**

```ts
export const POST = withApiHandler(async (request: NextRequest) => {
  assertKnowledgeExtractionEnvironment(process.env.NODE_ENV);
  assertSafeMutationRequest(request);
  const input = await validateJsonBody(request, knowledgeExtractionInputSchema);
  await assertRateLimit({
    namespace: 'dev.knowledge.extract.ip',
    key: getClientIp(request.headers),
    limit: 8,
    windowMs: 60_000,
  });
  return ok(await extractKnowledgeBatch(input));
});
```

`assertKnowledgeExtractionEnvironment` must throw `forbidden('知识提炼接口目前仅用于开发联调。')` when the environment is `production`.

- [ ] **Step 4: Run focused tests and backend type-oriented import check**

Run the focused Vitest command. Then run:

```powershell
npx vitest --config vitest.backend-patch.config.ts --run .backend_patch/tests/unit/knowledgeExtraction.test.ts .backend_patch/tests/unit/multiSourceRouting.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit the route when safe**

```powershell
git add -- .backend_patch/app/api/dev/knowledge/extract/route.ts .backend_patch/lib/knowledge-extraction/extractKnowledge.ts .backend_patch/tests/unit/knowledgeExtraction.test.ts
git commit -m "feat: expose development knowledge extraction"
```

---

### Task 3: Flutter Domain Models and In-Memory Store

**Files:**
- Create: `lib/knowledge_models.dart`
- Modify: `lib/main.dart`
- Create: `test/knowledge_forest_test.dart`

**Interfaces:**
- Produces: `KnowledgeNodeCandidate`, `KnowledgeExtractionBatch`, `KnowledgeNode`, `KnowledgeTreeSnapshot`, `KnowledgeForestStore.confirmBatch(...)`, and `KnowledgeForestStore.clearForTest()`.
- Does not consume `MindMapData`.

- [ ] **Step 1: Write failing parsing and confirmation tests**

```dart
const sampleBatchJson = <String, dynamic>{
  'batchId': 'batch-1',
  'conversationId': 'conv-1',
  'messageId': 'msg-1',
  'question': '人工智能专业学什么？',
  'answerExcerpt': '人工智能专业包括机器学习。',
  'suggestedTree': {'mode': 'new', 'title': '人工智能'},
  'nodes': [
    {
      'candidateId': 'node-1',
      'parentCandidateId': null,
      'type': 'topic',
      'title': '人工智能',
      'summary': '人工智能专业主题',
      'selected': true,
      'confidence': 0.9,
    },
    {
      'candidateId': 'node-2',
      'parentCandidateId': 'node-1',
      'type': 'concept',
      'title': '机器学习',
      'summary': '从数据中学习规律',
      'selected': true,
      'confidence': 0.8,
    },
  ],
};

KnowledgeExtractionBatch get sampleBatch =>
    KnowledgeExtractionBatch.fromJson(sampleBatchJson);

test('knowledge extraction batch parses candidates and tree suggestion', () {
  final batch = sampleBatch;
  expect(batch.nodes.last.title, '机器学习');
  expect(batch.suggestedTree.title, '人工智能');
});

test('confirmBatch promotes selected children whose parent was removed', () {
  final store = KnowledgeForestStore();
  final batchWithUnselectedParent = KnowledgeExtractionBatch.fromJson({
    ...sampleBatchJson,
    'batchId': 'batch-parent-test',
    'nodes': [
      {
        'candidateId': 'parent',
        'parentCandidateId': null,
        'type': 'topic',
        'title': '未选择父节点',
        'summary': '父节点摘要',
        'selected': false,
        'confidence': 0.7,
      },
      {
        'candidateId': 'child',
        'parentCandidateId': 'parent',
        'type': 'concept',
        'title': '保留的子节点',
        'summary': '子节点摘要',
        'selected': true,
        'confidence': 0.8,
      },
    ],
  });
  final tree = store.confirmBatch(
    batchWithUnselectedParent,
    targetTreeTitle: '人工智能',
  );
  expect(tree.nodes.single.parentNodeId, isNull);
});
```

- [ ] **Step 2: Run the focused Flutter test and verify failure**

```powershell
flutter test test/knowledge_forest_test.dart
```

Expected: FAIL because the knowledge models do not exist.

- [ ] **Step 3: Implement immutable models and store**

```dart
/// 当前进程内的个人知识森林；测试版重启后清空，不写设备持久化。
class KnowledgeForestStore extends ChangeNotifier {
  KnowledgeForestStore();

  final Map<String, KnowledgeTreeSnapshot> _trees = {};
  final Set<String> _confirmedBatchIds = {};
  final Map<String, String> _batchTreeIds = {};

  List<KnowledgeTreeSnapshot> get trees =>
      List.unmodifiable(_trees.values.toList()..sort(_newestFirst));

  KnowledgeTreeSnapshot confirmBatch(
    KnowledgeExtractionBatch batch, {
    required String targetTreeTitle,
    String? targetTreeId,
  }) {
    final confirmedTreeId = _batchTreeIds[batch.batchId];
    if (confirmedTreeId != null) return _trees[confirmedTreeId]!;

    final treeId = targetTreeId ?? 'tree-${batch.batchId}';
    final current = _trees[treeId] ?? KnowledgeTreeSnapshot.empty(
      id: treeId,
      title: targetTreeTitle.trim(),
    );
    final selectedIds = batch.nodes
        .where((candidate) => candidate.selected)
        .map((candidate) => candidate.candidateId)
        .toSet();
    final confirmedNodes = batch.nodes
        .where((candidate) => candidate.selected)
        .map((candidate) => candidate.toConfirmedNode(
              batch: batch,
              parentNodeId: selectedIds.contains(candidate.parentCandidateId)
                  ? 'node-${batch.batchId}-${candidate.parentCandidateId}'
                  : null,
            ))
        .toList(growable: false);
    final updated = current.merge(confirmedNodes, updatedAt: DateTime.now());
    _trees[treeId] = updated;
    _confirmedBatchIds.add(batch.batchId);
    _batchTreeIds[batch.batchId] = treeId;
    notifyListeners();
    return updated;
  }
}
```

Use stable client-generated IDs based on `batchId` and `candidateId`; never use titles as node IDs. Preserve `conversationId`, `messageId`, question, answer excerpt, optional source references, canonical reference fields, and personal overrides.

Define `KnowledgeTreeSnapshot.empty({required String id, required String title})`, `KnowledgeTreeSnapshot.merge(List<KnowledgeNode> nodes, {required DateTime updatedAt})`, and `KnowledgeNodeCandidate.toConfirmedNode({required KnowledgeExtractionBatch batch, required String? parentNodeId})` with the exact signatures used above.

- [ ] **Step 4: Run the model/store tests**

Expected: PASS for parsing, idempotency, target-tree selection, and parent promotion.

- [ ] **Step 5: Commit new model files only**

```powershell
git add -- lib/knowledge_models.dart lib/main.dart test/knowledge_forest_test.dart
git commit -m "feat: add in-memory knowledge forest models"
```

If `lib/main.dart` contains pre-existing unrelated edits, stage only the reviewed `part 'knowledge_models.dart';` hunk or defer the commit.

---

### Task 4: Flutter DeepSeek Extraction Client

**Files:**
- Create: `lib/knowledge_service.dart`
- Modify: `lib/main.dart`
- Modify: `test/knowledge_forest_test.dart`

**Interfaces:**
- Consumes: `KnowledgeExtractionBatch.fromJson` and `AppConfig.contentSourceTestApiBaseUrl`.
- Produces: `KnowledgeExtractionService.extract(...)` and injectable `KnowledgeExtractionGateway` for widget tests.

- [ ] **Step 1: Write failing response and error tests**

```dart
class FakeKnowledgeExtractionGateway implements KnowledgeExtractionGateway {
  FakeKnowledgeExtractionGateway.success(this._success)
      : _failures = const [];

  FakeKnowledgeExtractionGateway.failOnceThenSuccess(
    ApiRequestException failure,
    this._success,
  ) : _failures = [failure];

  final Map<String, dynamic> _success;
  final List<ApiRequestException> _failures;
  int _calls = 0;

  @override
  Future<KnowledgeExtractionBatch> extract({
    required String conversationId,
    required String messageId,
    required String question,
    required String answer,
    required List<KnowledgeTreeSummary> availableTrees,
    required List<KnowledgeSourceRef> sourceRefs,
  }) async {
    if (_calls < _failures.length) throw _failures[_calls++];
    _calls += 1;
    return KnowledgeExtractionBatch.fromJson(_success);
  }
}

test('knowledge extraction service parses the data envelope', () async {
  final gateway = FakeKnowledgeExtractionGateway.success(batchJson);
  final batch = await gateway.extract(
    conversationId: 'conv-1',
    messageId: 'msg-1',
    question: '人工智能学什么？',
    answer: '包括机器学习。',
    availableTrees: const [],
    sourceRefs: const [],
  );
  expect(batch.nodes, isNotEmpty);
});

test('knowledge extraction service exposes timeout as user-facing error', () async {
  expect(
    () => KnowledgeExtractionService.decodeFailureForTest(TimeoutException('x')),
    throwsA(isA<ApiRequestException>()),
  );
});
```

- [ ] **Step 2: Run focused tests and verify failure**

Expected: FAIL because the gateway and service do not exist.

- [ ] **Step 3: Implement a bounded HTTP client**

```dart
abstract interface class KnowledgeExtractionGateway {
  Future<KnowledgeExtractionBatch> extract({
    required String conversationId,
    required String messageId,
    required String question,
    required String answer,
    required List<KnowledgeTreeSummary> availableTrees,
    required List<KnowledgeSourceRef> sourceRefs,
  });
}
```

Post only the conversation/message identifiers, question, answer, and tree summaries to `${AppConfig.contentSourceTestApiBaseUrl}/api/dev/knowledge/extract`; do not send `sourceRefs` to DeepSeek. After parsing the response, attach the source references already present on the trusted Agent response with `batch.copyWith(sourceRefs: sourceRefs)`. Use a 30-second timeout, validate the existing `{ok,data}` envelope, convert socket/HTTP/format errors to concise Chinese `ApiRequestException` messages, and never log the full answer.

- [ ] **Step 4: Run the service tests**

Expected: PASS.

- [ ] **Step 5: Commit the service boundary**

```powershell
git add -- lib/knowledge_service.dart lib/main.dart test/knowledge_forest_test.dart
git commit -m "feat: connect knowledge extraction service"
```

---

### Task 5: Candidate Review and Confirmation UI

**Files:**
- Create: `lib/knowledge_forest.dart`
- Modify: `lib/main.dart`
- Modify: `test/knowledge_forest_test.dart`

**Interfaces:**
- Consumes: `KnowledgeExtractionBatch`, `KnowledgeForestStore`, and `KnowledgeExtractionGateway`.
- Produces: `KnowledgeExtractionPreviewPage` returning the confirmed `KnowledgeTreeSnapshot?` through Navigator.

- [ ] **Step 1: Write failing preview widget tests**

```dart
testWidgets('candidate preview edits and selectively confirms nodes', (tester) async {
  final store = KnowledgeForestStore();
  await tester.pumpWidget(MaterialApp(
    home: KnowledgeExtractionPreviewPage(batch: sampleBatch, store: store),
  ));
  await tester.tap(find.byKey(const ValueKey('knowledge-candidate-node-2')));
  await tester.enterText(
    find.byKey(const ValueKey('knowledge-candidate-title-node-1')),
    '机器学习基础',
  );
  await tester.tap(find.byKey(const ValueKey('confirm-knowledge-batch')));
  await tester.pumpAndSettle();
  expect(store.trees.single.nodes.single.title, '机器学习基础');
});
```

- [ ] **Step 2: Run the focused widget test**

Expected: FAIL because the preview page is missing.

- [ ] **Step 3: Implement the preview state machine**

```dart
enum KnowledgeExtractionUiState { idle, extracting, previewing, confirming, confirmed }
```

The preview owns editable copies of candidates, exposes one checkbox per node, validates a non-empty target tree title, supports selecting an existing tree or the suggested new tree, promotes selected children after unselected parents, and disables confirmation while committing. Cancel returns `null` and leaves the store unchanged.

- [ ] **Step 4: Run preview widget tests**

Expected: PASS for selection, editing, target override, cancel, and confirmation idempotency.

- [ ] **Step 5: Commit the preview UI**

```powershell
git add -- lib/knowledge_forest.dart lib/main.dart test/knowledge_forest_test.dart
git commit -m "feat: add knowledge candidate review"
```

---

### Task 6: Forest List and Reactive Mind Map View

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `lib/main.dart`
- Modify: `lib/knowledge_forest.dart`
- Modify: `test/knowledge_forest_test.dart`

**Interfaces:**
- Consumes: `KnowledgeTreeSnapshot`.
- Produces: `KnowledgeMindMapAdapter.toMindMapData(tree)`, `KnowledgeForestPage`, `KnowledgeTreePage`, and `KnowledgeNodeDetailSheet`.

- [ ] **Step 1: Add failing adapter and page tests**

```dart
import 'package:reactive_mind_map/reactive_mind_map.dart';

test('mind map adapter renders only primary parent-child edges', () {
  final store = KnowledgeForestStore();
  final sampleTree = store.confirmBatch(
    sampleBatch,
    targetTreeTitle: '人工智能',
  );
  final data = KnowledgeMindMapAdapter.toMindMapData(sampleTree);
  expect(data.id, sampleTree.rootNodeId);
  expect(data.children.single.id, 'node-batch-1-node-2');
});

testWidgets('forest opens a tree and node detail', (tester) async {
  final seededStore = KnowledgeForestStore()
    ..confirmBatch(sampleBatch, targetTreeTitle: '人工智能');
  await tester.pumpWidget(MaterialApp(home: KnowledgeForestPage(store: seededStore)));
  await tester.tap(find.text('人工智能'));
  await tester.pumpAndSettle();
  expect(find.byType(MindMapWidget), findsOneWidget);
});
```

- [ ] **Step 2: Add the exact dependency and run package resolution**

```yaml
dependencies:
  reactive_mind_map: 1.2.2
```

Run:

```powershell
flutter pub get
```

Expected: `pubspec.lock` resolves exactly `1.2.2`.

- [ ] **Step 3: Implement the adapter and pages**

```dart
abstract final class KnowledgeMindMapAdapter {
  static MindMapData toMindMapData(KnowledgeTreeSnapshot tree) {
    return _buildNode(tree.rootNodeId, tree.nodesById);
  }
}
```

Use `MindMapLayout.right`, `CameraFocus.rootNode`, type-specific colors through `MindMapStyle.nodeBuilder`, and `onNodeTap` for the detail sheet. Forest uses cards; it must never render all trees in one mind map. Show an explicit “内部测试数据，重启后清空” banner and an empty state.

- [ ] **Step 4: Run adapter and page tests**

Run `flutter test test/knowledge_forest_test.dart`. Expected: PASS without overflow at 390×844.

- [ ] **Step 5: Commit dependency and rendering files**

```powershell
git add -- pubspec.yaml pubspec.lock lib/main.dart lib/knowledge_forest.dart test/knowledge_forest_test.dart
git commit -m "feat: render knowledge trees in Flutter"
```

---

### Task 7: Agent Integration and End-to-End Prototype Flow

**Files:**
- Modify: `lib/agent_experience.dart`
- Modify: `lib/main.dart`
- Modify: `test/knowledge_forest_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `KnowledgeExtractionGateway`, `KnowledgeForestStore`, `KnowledgeExtractionPreviewPage`, and named routes.
- Produces: stable answer message IDs, “可提炼为知识” entry, “我的知识森林” navigation, and a complete prototype flow.

- [ ] **Step 1: Write failing Agent integration tests**

```dart
testWidgets('agent answer can be extracted and opened in the forest', (tester) async {
  final gateway = FakeKnowledgeExtractionGateway.success(sampleBatchJson);
  final store = KnowledgeForestStore();
  await tester.pumpWidget(MaterialApp(
    home: AgentExperiencePage(knowledgeGateway: gateway, knowledgeStore: store),
  ));
  await tester.enterText(
    find.byKey(const ValueKey('agent-message-input')),
    '人工智能专业主要学习什么？',
  );
  await tester.tap(find.byKey(const ValueKey('agent-send-button')));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.byKey(const ValueKey('knowledge-extract-button')));
  await tester.pumpAndSettle();
  expect(find.text('确认知识节点'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('confirm-knowledge-batch')));
  await tester.pumpAndSettle();
  expect(store.trees.single.title, '人工智能');
});

testWidgets('failed extraction keeps the answer and allows retry', (tester) async {
  final gateway = FakeKnowledgeExtractionGateway.failOnceThenSuccess(
    const ApiRequestException('知识提炼暂时不可用'),
    sampleBatchJson,
  );
  await tester.pumpWidget(MaterialApp(
    home: AgentExperiencePage(knowledgeGateway: gateway),
  ));
  await tester.enterText(
    find.byKey(const ValueKey('agent-message-input')),
    '数学专业需要哪些能力？',
  );
  await tester.tap(find.byKey(const ValueKey('agent-send-button')));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.byKey(const ValueKey('knowledge-extract-button')));
  await tester.pump();
  expect(find.textContaining('暂时不可用'), findsOneWidget);
  expect(find.textContaining('数学专业'), findsWidgets);
  await tester.tap(find.byKey(const ValueKey('knowledge-extract-button')));
  await tester.pumpAndSettle();
  expect(find.text('确认知识节点'), findsOneWidget);
});
```

- [ ] **Step 2: Run both Flutter test files and verify failure**

```powershell
flutter test test/knowledge_forest_test.dart test/widget_test.dart
```

Expected: FAIL because Agent has no knowledge controls.

- [ ] **Step 3: Integrate without mixing responsibilities**

Add `messageId`, `question`, and `knowledgeEligible` to `_AgentConversationEntry`. The page owns only extraction loading/error state; it delegates HTTP to the gateway, confirmation to the preview, and storage to `KnowledgeForestStore.instance`. Convert the entry's existing `AgentContentCardData` values to `KnowledgeSourceRef` and attach them locally through the gateway parameter; do not send those references to DeepSeek. Add `/knowledge-forest` to routes and an AppBar forest icon. Do not move subscription or acquisition logic into knowledge files.

Eligibility fallback for the development prototype must be deterministic:

```dart
bool get knowledgeEligible =>
    !fromUser && !isError && text.trim().length >= 40;
```

Do not claim that this fallback is an AI judgment; label it internal-test behavior. The extraction itself still uses DeepSeek.

- [ ] **Step 4: Run integration and regression tests**

Run the Step 2 command. Expected: existing Agent subscription tests and new knowledge flow tests both PASS.

- [ ] **Step 5: Commit only reviewed Agent hunks**

Because `lib/agent_experience.dart` already has unrelated working-tree changes, inspect `git diff -- lib/agent_experience.dart`, stage only knowledge-flow hunks when possible, and do not absorb unrelated edits into the feature commit.

```powershell
git commit -m "feat: connect agent answers to knowledge forest"
```

---

### Task 8: Verification and Handoff

**Files:**
- Modify only if verification exposes a feature-owned defect.

**Interfaces:**
- Validates every interface produced by Tasks 1–7.

- [ ] **Step 1: Run backend verification**

```powershell
npx vitest --config vitest.backend-patch.config.ts --run .backend_patch/tests/unit/knowledgeExtraction.test.ts .backend_patch/tests/unit/multiSourceRouting.test.ts
```

Expected: all selected tests PASS.

- [ ] **Step 2: Run Flutter analysis**

```powershell
dart analyze lib/main.dart lib/agent_experience.dart lib/knowledge_models.dart lib/knowledge_service.dart lib/knowledge_forest.dart test
```

Expected: no new analyzer errors.

- [ ] **Step 3: Run the complete Flutter test suite**

```powershell
flutter test
```

Expected: all tests PASS.

- [ ] **Step 4: Run manual development smoke test**

Start the existing backend with DeepSeek environment variables, then run Flutter with:

```powershell
flutter run -d emulator-5554 --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=AGENT_ENABLED=true --dart-define=CONTENT_SOURCE_TEST_API_BASE_URL=http://10.0.2.2:3000
```

Verify: answer → extraction prompt → DeepSeek preview → edit/select → confirm → forest → mind map → node details. Verify App restart clears the prototype forest.

- [ ] **Step 5: Review the final diff and report limitations**

Confirm no model secrets, database writes, public sharing, cross-branch rendering, or unrelated dirty-worktree changes entered the diff. Report backend/Flutter command output and the known in-memory-only limitation.

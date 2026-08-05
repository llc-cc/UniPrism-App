# 1.2 对话式发散提问 Mock Implementation Plan

> **已被替代：** 用户补充了练习端口、错误思路验证、诊断确认和回退要求。本计划保留为决策记录，执行以 `2026-08-05-dialogue-exploration-dual-port-mock.md` 为准。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在独立 Flutter 模块中实现可操作的 1.2 对话式发散提问闭环，使用二次函数与 business model Mock 数据，同时为知识库、正式对话、白板、事件和 M2 记忆项保留稳定接口。

**Architecture:** 模块位于 `lib/features/dialogue_exploration/`，不依赖 `main.dart` 的 part library。领域模型与接口在内层，确定性 Mock 在 adapters，`ChangeNotifier` 控制器编排异步和树状态，页面只负责展示与交互。所有外部能力经构造器注入；未来接 1.1、Skill、3.3 和 M2 时替换 adapter，不改页面协议。

**Tech Stack:** Flutter Material 3、Dart 3.12、`ChangeNotifier`、`CustomPainter`、`flutter_test`；本计划不新增第三方依赖。

## Global Constraints

- 仅实现 1.2，不新增闪卡、FSRS、复习组或 M3 能力计算。
- 功能代码必须独立存放于 `lib/features/dialogue_exploration/`。
- 正式知识库未交付前只用 Dart fixture；页面不得读取 Mock 常量。
- 单会话最多 40 个节点、主干最多 6 层、单节点最多 8 个直接分支、单回答最多 2 个素材。
- 输入边界固定为 `inScope / aboveStage / unrelated / inappropriate`；空、超长和不适宜输入不创建正式节点。
- 四类素材固定为 `figure / video / interactive / formula`；互动素材必须可操作，模拟视频必须显式标注。
- 所有新增公开类、异步状态转换、幂等、边界和失败分支写简洁中文注释。
- 严格 TDD：每个生产行为先写测试并确认按预期失败，再写最小实现。
- 不暂存或提交仓库中原有的其他修改；每次提交只列出本任务新增文件或精确修改文件。

---

## File Map

```text
lib/features/dialogue_exploration/
├─ dialogue_exploration.dart              # 模块公开出口
├─ domain/
│  ├─ dialogue_content.dart               # 原子、种子问题、素材
│  ├─ dialogue_models.dart                # 会话、节点、边界、候选、统计
│  └─ dialogue_ports.dart                 # 内容、对话、存储、白板、记忆项、事件接口
├─ adapters/
│  ├─ mock_dialogue_content_repository.dart
│  ├─ mock_dialogue_gateway.dart
│  ├─ in_memory_dialogue_session_repository.dart
│  ├─ in_memory_dialogue_sinks.dart
│  └─ mock_whiteboard_launcher.dart
├─ application/
│  ├─ dialogue_exploration_controller.dart
│  └─ dialogue_exporter.dart
└─ presentation/
   ├─ dialogue_lab_page.dart
   ├─ dialogue_exploration_page.dart
   └─ widgets/
      ├─ dialogue_material_card.dart
      ├─ dialogue_tree_panel.dart
      └─ parabola_painter.dart

test/features/dialogue_exploration/
├─ mock_dialogue_content_repository_test.dart
├─ mock_dialogue_gateway_test.dart
├─ dialogue_exploration_controller_test.dart
├─ dialogue_exporter_test.dart
├─ dialogue_material_card_test.dart
├─ dialogue_exploration_page_test.dart
└─ dialogue_lab_flow_test.dart
```

---

### Task 1: Domain contracts and auditable Mock content

**Files:**
- Create: `lib/features/dialogue_exploration/domain/dialogue_content.dart`
- Create: `lib/features/dialogue_exploration/domain/dialogue_models.dart`
- Create: `lib/features/dialogue_exploration/domain/dialogue_ports.dart`
- Create: `lib/features/dialogue_exploration/adapters/mock_dialogue_content_repository.dart`
- Create: `lib/features/dialogue_exploration/dialogue_exploration.dart`
- Test: `test/features/dialogue_exploration/mock_dialogue_content_repository_test.dart`

**Interfaces:**
- Consumes: Flutter foundation annotations only.
- Produces: `DialogueContentRepository`, `DialogueGateway`, `DialogueSessionRepository`, `DialogueWhiteboardLauncher`, `DialogueMemoryItemSink`, `DialogueEventSink`; immutable domain types used by every later task.

- [ ] **Step 1: Write the failing fixture contract tests**

```dart
test('Mock 内容覆盖三个入口和四类素材', () async {
  final repository = MockDialogueContentRepository();
  final topics = await repository.loadTopics();
  final seeds = await repository.loadSeedQuestions();
  final materials = await repository.loadMaterials(
    topics.expand((topic) => topic.materialIds).toSet(),
  );

  expect(topics.map((item) => item.id), contains('quadratic-graph'));
  expect(seeds.map((item) => item.id), contains('business-model-coffee'));
  expect(materials.map((item) => item.kind).toSet(), {
    DialogueMaterialKind.figure,
    DialogueMaterialKind.video,
    DialogueMaterialKind.interactive,
    DialogueMaterialKind.formula,
  });
});

test('Mock 内容的引用完整且素材不越出原子范围', () async {
  final repository = MockDialogueContentRepository();
  final issues = await repository.validateFixtures();
  expect(issues, isEmpty);
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/mock_dialogue_content_repository_test.dart`

Expected: FAIL because `MockDialogueContentRepository` and domain contracts do not exist.

- [ ] **Step 3: Implement immutable models and ports**

```dart
enum DialogueInputBoundary { inScope, aboveStage, unrelated, inappropriate }
enum DialogueMaterialKind { figure, video, interactive, formula }
enum DialogueNodeRole { student, tutor }

abstract interface class DialogueContentRepository {
  Future<List<DialogueTopic>> loadTopics();
  Future<List<DialogueSeedQuestion>> loadSeedQuestions();
  Future<List<DialogueMaterial>> loadMaterials(Set<String> ids);
  Future<Set<String>> allowedMaterialIds(String atomId);
}

abstract interface class DialogueGateway {
  Future<DialogueTurnResponse> reply(DialogueTurnRequest request);
}

abstract interface class DialogueMemoryItemSink {
  Future<List<String>> upsertCandidates(
    String sessionId,
    List<DialogueMemoryCandidate> candidates,
  );
}
```

Models must use unmodifiable collections, stable IDs and `copyWith` methods only where state transitions need them. `DialogueTurnResponse` must carry `answer`, `followUpQuestion`, `boundary`, `materialIds`, `memoryCandidates` and `strategyVersion`.

- [ ] **Step 4: Implement two deterministic fixture sets**

Create the quadratic topic with 6 seeds and all four material kinds. Create the coffee-shop business model seed with routes for revenue, cost, pricing, channel, moat and unit economics. `validateFixtures()` must reject duplicate IDs, missing references and material IDs outside a topic’s allowed set.

- [ ] **Step 5: Run tests and verify GREEN**

Run: `flutter test test/features/dialogue_exploration/mock_dialogue_content_repository_test.dart`

Expected: all tests PASS with no analyzer warnings.

- [ ] **Step 6: Commit the domain slice**

```powershell
git add -- lib/features/dialogue_exploration test/features/dialogue_exploration/mock_dialogue_content_repository_test.dart
git commit -m "feat(dialogue): add exploration domain and mock content"
```

---

### Task 2: Deterministic dialogue Gateway and input boundaries

**Files:**
- Create: `lib/features/dialogue_exploration/adapters/mock_dialogue_gateway.dart`
- Test: `test/features/dialogue_exploration/mock_dialogue_gateway_test.dart`

**Interfaces:**
- Consumes: `DialogueGateway.reply(DialogueTurnRequest)` and content repository material boundaries from Task 1.
- Produces: deterministic answers used by the controller; injectable `delay` and `failNextRequest()` for async tests.

- [ ] **Step 1: Write failing routing and safety tests**

```dart
test('回答包含原理反问且素材全部在允许集合内', () async {
  final gateway = MockDialogueGateway(delay: Duration.zero);
  final request = quadraticRequest('顶点为什么在这里');
  final response = await gateway.reply(request);

  expect(response.answer, isNotEmpty);
  expect(response.followUpQuestion, contains('条件'));
  expect(response.materialIds, hasLength(2));
  expect(response.materialIds.toSet().difference(request.allowedMaterialIds), isEmpty);
});

test('超纲、不相关和不适宜输入返回不同边界', () async {
  final gateway = MockDialogueGateway(delay: Duration.zero);
  expect((await gateway.reply(quadraticRequest('大学泛函分析'))).boundary,
      DialogueInputBoundary.aboveStage);
  expect((await gateway.reply(quadraticRequest('今天天气'))).boundary,
      DialogueInputBoundary.unrelated);
  expect(
    () => gateway.reply(quadraticRequest(MockDialogueGateway.inappropriateTestInput)),
    throwsA(isA<DialogueInputRejectedException>()),
  );
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/mock_dialogue_gateway_test.dart`

Expected: FAIL because the gateway is missing.

- [ ] **Step 3: Implement keyword routing and deterministic failures**

Use normalized lowercase/trimmed input. Every successful route returns a concrete explanation and a question about a condition, cause or calculation basis. Above-stage answers contain a visible boundary note and no out-of-range media; unrelated answers set `isSideBranchSuggested`; inappropriate input throws before a response node can be created.

```dart
final class MockDialogueGateway implements DialogueGateway {
  MockDialogueGateway({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;
  bool _shouldFailNext = false;

  void failNextRequest() => _shouldFailNext = true;

  @override
  Future<DialogueTurnResponse> reply(DialogueTurnRequest request) async {
    await Future<void>.delayed(delay);
    if (_shouldFailNext) {
      _shouldFailNext = false;
      throw const DialogueGatewayException('模拟回答失败，请重试。');
    }
    return _route(request);
  }
}
```

- [ ] **Step 4: Add business model contract tests**

Drive root → revenue → unit economics and root → cost branches. Assert the returned routes can form depth 3, at least 2 explicit branches and use at least 3 distinct material kinds without an empty “你觉得呢” follow-up.

- [ ] **Step 5: Run Gateway tests and commit**

Run: `flutter test test/features/dialogue_exploration/mock_dialogue_gateway_test.dart`

Expected: all tests PASS.

```powershell
git add -- lib/features/dialogue_exploration/adapters/mock_dialogue_gateway.dart test/features/dialogue_exploration/mock_dialogue_gateway_test.dart
git commit -m "feat(dialogue): add deterministic exploration gateway"
```

---

### Task 3: Tree state machine, persistence, conversion and export

**Files:**
- Create: `lib/features/dialogue_exploration/adapters/in_memory_dialogue_session_repository.dart`
- Create: `lib/features/dialogue_exploration/adapters/in_memory_dialogue_sinks.dart`
- Create: `lib/features/dialogue_exploration/application/dialogue_exploration_controller.dart`
- Create: `lib/features/dialogue_exploration/application/dialogue_exporter.dart`
- Test: `test/features/dialogue_exploration/dialogue_exploration_controller_test.dart`
- Test: `test/features/dialogue_exploration/dialogue_exporter_test.dart`

**Interfaces:**
- Consumes: Task 1 ports and Task 2 Gateway.
- Produces: `DialogueExplorationController`, `DialogueExplorationState`, `DialogueExporter.toVersionedJson()`, idempotent in-memory memory item IDs and events.

- [ ] **Step 1: Write failing controller tests for the happy path**

```dart
test('连续提问追加到活跃叶，只有显式 branchFromNodeId 才旁散', () async {
  final harness = DialogueControllerHarness();
  await harness.controller.startFromSeed(harness.quadraticSeed);
  final firstTutor = harness.controller.state.session!.activeLeafId;

  await harness.controller.submitQuestion('如果 a 变大会怎样');
  expect(harness.controller.state.session!.maxDepth, 2);

  await harness.controller.submitQuestion('零点又是什么', branchFromNodeId: firstTutor);
  expect(harness.controller.state.session!.sideBranchCount, 1);
});
```

- [ ] **Step 2: Write failing tests for retry, limits and idempotency**

Cover: empty/overlong/rejected input creates no node; Gateway failure retains one failed student node; retry replaces its state without duplicating it; 40-node/6-depth/8-child limits reject only new growth; repeated candidate conversion returns the same memory item IDs.

- [ ] **Step 3: Run controller tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/dialogue_exploration_controller_test.dart`

Expected: FAIL because controller and repositories are missing.

- [ ] **Step 4: Implement the explicit async state machine**

```dart
enum DialogueSubmissionStatus { idle, submitting, rendered, failed, reflecting, saved }

final class DialogueExplorationController extends ChangeNotifier {
  DialogueExplorationController({
    required DialogueGateway gateway,
    required DialogueSessionRepository sessionRepository,
    required DialogueMemoryItemSink memoryItemSink,
    required DialogueEventSink eventSink,
    required DateTime Function() nowUtc,
  });

  DialogueExplorationState get state => _state;
  Future<void> startFromSeed(DialogueSeedQuestion seed);
  Future<void> startFromFreeInput(DialogueTopic topic, String question);
  Future<void> submitQuestion(String question, {String? branchFromNodeId});
  Future<void> retryFailedNode(String nodeId);
  Future<void> saveReflection(String text);
  Future<List<String>> convertCandidates(Set<String> candidateIds);
  Future<void> saveSession();
}
```

Use a monotonically increasing local ID source and request key. Notify only after coherent state transitions. Override `dispose()` to set a private `_isDisposed` flag and check it before notifying from asynchronous callbacks. Saving and candidate conversion use stable IDs derived from session/node/candidate identifiers.

- [ ] **Step 5: Write exporter RED test, then implement versioned JSON**

```dart
test('导出包含父子关系、边界、素材、复述和策略版本', () {
  final json = DialogueExporter.toVersionedJson(completedSession);
  expect(json['schemaVersion'], 1);
  expect(json['nodes'][1]['parentId'], completedSession.rootNodeId);
  expect(json['reflection'], isNotEmpty);
  expect(json['strategyVersions'], contains('mock-exploration-v1'));
});
```

Run RED, implement `toVersionedJson`, then run both controller and exporter tests GREEN.

- [ ] **Step 6: Commit the application layer**

```powershell
git add -- lib/features/dialogue_exploration/application lib/features/dialogue_exploration/adapters/in_memory_dialogue_session_repository.dart lib/features/dialogue_exploration/adapters/in_memory_dialogue_sinks.dart test/features/dialogue_exploration/dialogue_exploration_controller_test.dart test/features/dialogue_exploration/dialogue_exporter_test.dart
git commit -m "feat(dialogue): add exploration tree state machine"
```

---

### Task 4: Four material widgets and Mock whiteboard

**Files:**
- Create: `lib/features/dialogue_exploration/adapters/mock_whiteboard_launcher.dart`
- Create: `lib/features/dialogue_exploration/presentation/widgets/parabola_painter.dart`
- Create: `lib/features/dialogue_exploration/presentation/widgets/dialogue_material_card.dart`
- Test: `test/features/dialogue_exploration/dialogue_material_card_test.dart`

**Interfaces:**
- Consumes: `DialogueMaterial` and `DialogueWhiteboardLauncher`.
- Produces: `DialogueMaterialCard` rendering each kind and an interactive whiteboard adapter returning `DialogueWhiteboardResult`.

- [ ] **Step 1: Write failing widget tests for all four materials**

```dart
testWidgets('互动素材拖动 a 后实时更新参数标签', (tester) async {
  await tester.pumpWidget(materialApp(interactiveMaterial));
  expect(find.text('a = 1.0'), findsOneWidget);
  await tester.drag(find.byKey(const ValueKey('parabola-a-slider')), const Offset(120, 0));
  await tester.pump();
  expect(find.textContaining('a = '), findsOneWidget);
  expect(find.text('a = 1.0'), findsNothing);
});

testWidgets('模拟视频明确标注且支持播放暂停', (tester) async {
  await tester.pumpWidget(materialApp(videoMaterial));
  expect(find.text('模拟视频'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('mock-video-toggle')));
  await tester.pump();
  expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
});
```

Also assert figure uses `CustomPaint`, formula renders derivation text, and no widget issues network requests.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/dialogue_material_card_test.dart`

Expected: FAIL because widgets do not exist.

- [ ] **Step 3: Implement focused material widgets**

`DialogueMaterialCard` dispatches to private widgets by enum. `ParabolaPainter` draws axes, curve and vertex from `a/h/k`. Interactive sliders own only temporary visual state. Mock video uses a slider and play/pause state, not timers that leak in tests.

- [ ] **Step 4: Implement the whiteboard port adapter**

```dart
final class MockDialogueWhiteboardLauncher implements DialogueWhiteboardLauncher {
  const MockDialogueWhiteboardLauncher();

  @override
  Future<DialogueWhiteboardResult> open(
    BuildContext context, {
    required String nodeId,
    required String atomId,
    required Map<String, Object?> initialState,
  }) async {
    final result = await showModalBottomSheet<DialogueWhiteboardResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MockDialogueWhiteboard(initialState: initialState),
    );
    return result ?? const DialogueWhiteboardResult.cancelled();
  }
}
```

Test moving one parameter and closing with a result. Cancellation must not mutate the dialogue node.

- [ ] **Step 5: Run tests and commit**

Run: `flutter test test/features/dialogue_exploration/dialogue_material_card_test.dart`

Expected: all tests PASS.

```powershell
git add -- lib/features/dialogue_exploration/adapters/mock_whiteboard_launcher.dart lib/features/dialogue_exploration/presentation/widgets test/features/dialogue_exploration/dialogue_material_card_test.dart
git commit -m "feat(dialogue): add interactive learning materials"
```

---

### Task 5: Dialogue tree and exploration page

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/widgets/dialogue_tree_panel.dart`
- Create: `lib/features/dialogue_exploration/presentation/dialogue_exploration_page.dart`
- Test: `test/features/dialogue_exploration/dialogue_exploration_page_test.dart`

**Interfaces:**
- Consumes: controller, content repository, exporter, material card and whiteboard port.
- Produces: mobile-safe exploration UI with question scaffolds, tree controls, reflection, save/export and candidate conversion.

- [ ] **Step 1: Write failing page tests for question and tree interactions**

```dart
testWidgets('脚手架只填入输入框，不会自动发送', (tester) async {
  await tester.pumpWidget(explorationPageHarness());
  await tester.tap(find.text('如果……会怎样'));
  await tester.pump();
  expect(find.byType(TextField), findsOneWidget);
  expect(find.text('如果……会怎样'), findsWidgets);
  expect(fakeGateway.requestCount, 0);
});

testWidgets('历史导师节点可以显式开支线并返回活跃叶', (tester) async {
  await tester.pumpWidget(explorationPageWithExistingTree());
  await tester.tap(find.byKey(const ValueKey('tree-node-tutor-1')));
  await tester.tap(find.text('从这里继续探索'));
  expect(find.text('正在创建支线'), findsOneWidget);
  await tester.tap(find.text('返回当前分支'));
  expect(find.byKey(const ValueKey('active-leaf')), findsOneWidget);
});
```

- [ ] **Step 2: Add failing tests for loading, failure, retry and boundaries**

Assert submitting disables duplicate send; failure keeps question and shows retry; above-stage and side-branch labels are visible; inappropriate input shows rejection without a message node; compact 360×640 viewport has no overflow.

- [ ] **Step 3: Run tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/dialogue_exploration_page_test.dart`

Expected: FAIL because page and tree panel do not exist.

- [ ] **Step 4: Implement the page without business logic in widgets**

Use `ListenableBuilder` on the controller. The conversation is a scrolling list; the tree opens in an end drawer on phones and a constrained side panel on wide screens. Tree nodes support focus, fold/unfold, branch, and return-to-leaf. Every tutor node renders at most two resolved material cards and a whiteboard action.

- [ ] **Step 5: Implement reflection, export and conversion UI**

Reflection must be non-empty before completion. Export opens a selectable JSON preview and copies via `Clipboard.setData`. Candidate selection opens an editable confirmation sheet; cancellation leaves the sink unchanged; success shows the count returned by the sink.

- [ ] **Step 6: Run page tests and commit**

Run: `flutter test test/features/dialogue_exploration/dialogue_exploration_page_test.dart`

Expected: all tests PASS without overflow or pending timers.

```powershell
git add -- lib/features/dialogue_exploration/presentation test/features/dialogue_exploration/dialogue_exploration_page_test.dart
git commit -m "feat(dialogue): build exploration tree experience"
```

---

### Task 6: Standalone lab entry and end-to-end acceptance

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/dialogue_lab_page.dart`
- Modify: `lib/features/dialogue_exploration/dialogue_exploration.dart`
- Modify: `lib/main.dart` (one import only)
- Modify: `lib/developer_tools.dart` (one `_DeveloperToolEntry` only; preserve all pre-existing content)
- Test: `test/features/dialogue_exploration/dialogue_lab_flow_test.dart`
- Modify: `test/widget_test.dart` only if its existing developer-tools assertion must include the new entry.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: `DialogueExplorationLabPage` as the module’s only app-facing constructor and a developer-tools navigation entry.

- [ ] **Step 1: Write failing standalone flow test**

```dart
testWidgets('二次函数可从问题进入、分支、复述并转记忆项', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: DialogueExplorationLabPage()));
  await tester.tap(find.text('二次函数的顶点为什么在这里'));
  await tester.pumpAndSettle();
  expect(find.textContaining('顶点式'), findsWidgets);

  await tester.tap(find.text('从这里继续探索').first);
  await tester.enterText(find.byKey(const ValueKey('dialogue-input')), '如果 a 变大会怎样');
  await tester.tap(find.byKey(const ValueKey('dialogue-send')));
  await tester.pumpAndSettle();
  expect(find.text('支线'), findsWidgets);
});
```

Add a second flow for business model that reaches depth 3, creates 2 branches, records 3 material kinds, and contains no empty follow-up. Add a lifecycle test that pops the lab and reconstructs it to prove process-local state resets.

- [ ] **Step 2: Run flow tests and verify RED**

Run: `flutter test test/features/dialogue_exploration/dialogue_lab_flow_test.dart`

Expected: FAIL because the standalone lab page is missing.

- [ ] **Step 3: Implement `DialogueExplorationLabPage` dependency composition**

The page constructs repository, gateway, session repository, sinks, controller, exporter and whiteboard launcher once in `initState`, disposes the controller, and shows “测试数据，退出实验室后清空”. It provides Mock atom, question library, free input, event viewer and reset action.

- [ ] **Step 4: Add the developer-tools entry with a focused test**

Import the barrel from `main.dart`:

```dart
import 'features/dialogue_exploration/dialogue_exploration.dart';
```

Add exactly one entry to `DeveloperToolsPage`:

```dart
_DeveloperToolEntry(
  key: const ValueKey('developer-tool-dialogue-exploration'),
  icon: Icons.account_tree_outlined,
  title: '教学助手：对话探索',
  description: '验证 1.2 思维树、素材与记忆项输出',
  onTap: () => _push(context, const DialogueExplorationLabPage()),
),
```

Because `developer_tools.dart` already has unrelated uncommitted work, do not stage it until its ownership is confirmed. The module and its tests remain independently runnable even if the app-shell hunk is left uncommitted.

- [ ] **Step 5: Run scoped and app-level verification**

```powershell
dart analyze lib/features/dialogue_exploration test/features/dialogue_exploration
flutter test test/features/dialogue_exploration
flutter test test/widget_test.dart
flutter test
```

Expected: zero analyzer errors and all tests PASS. If an unrelated baseline failure appears, record the exact test and demonstrate that all `test/features/dialogue_exploration` tests still pass.

- [ ] **Step 6: Review scope and commit only owned files**

Run `git diff --check`, inspect `git status --short`, and stage only `lib/features/dialogue_exploration/`, `test/features/dialogue_exploration/`, the single `main.dart` import hunk if cleanly separable, and the plan. Never use `git add .`.

```powershell
git commit -m "feat(dialogue): deliver mock exploration lab"
```

---

## Completion Checklist

- [ ] Mock 原子、问题库、自由输入三个入口可用。
- [ ] 五个提问脚手架不自动发送。
- [ ] 超纲、不相关、不适宜三类边界可区分。
- [ ] 每条成功回答都有指向原理或条件的反问。
- [ ] 图、模拟视频、互动、公式四类素材齐全且不越关系边。
- [ ] 树支持继续、分支、回溯、折叠、返回活跃叶。
- [ ] 白板通过接口打开，取消不修改节点。
- [ ] 复述、保存、版本化 JSON 导出可用。
- [ ] 候选经幂等 Sink 转为未来 M2 可消费的记忆项引用。
- [ ] business model Demo 达到 3 层、2 条支线、3 类素材。
- [ ] 40 节点、6 层、8 子分支和 2 素材限制有测试。
- [ ] 模块离开后进程内数据清空。
- [ ] 所有新增测试经历 RED → GREEN，分析与相关 Flutter 测试通过。

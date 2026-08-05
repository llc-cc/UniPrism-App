# 1.2 对话式发散提问双端口 Mock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 独立实现可复用的思维树引擎，并用二次函数教学、不等式证明练习和 business model 三个 Mock 场景展示 1.2 的大致效果。

**Architecture:** `dialogue_exploration` 模块以公共思维树和学生掌握快照为核心，教学与练习通过策略对象改变反问、素材和节点动作。练习中的候选诊断必须由学生确认或由步骤验证，错误分支保留并通过显式 backtrack 节点回退。

**Tech Stack:** Flutter Material 3、Dart 3.12、ChangeNotifier、CustomPainter、flutter_test；不新增第三方包。

## Global Constraints

- 只实现 1.2；不实现闪卡、FSRS 或能力分计算。
- 模块根目录固定为 `lib/features/dialogue_exploration/`。
- 首版使用确定性 Mock AI、三档 Mock 掌握快照和进程内存储。
- 单会话最多 40 节点、单路径最多 6 层、单节点最多 8 个直接分支、单回答最多 2 个素材。
- 错误路径不删除；候选诊断未确认前不能写入掌握证据。
- 生产代码先有按预期失败的测试，再写最小实现。
- 公开模型、控制器、页面、异步状态和证据边界写简洁中文注释。
- 不使用 `git add .`，不提交现有工作区中的无关改动。

## File Map

```text
lib/features/dialogue_exploration/
├─ dialogue_exploration.dart
├─ core/
│  ├─ exploration_models.dart
│  ├─ exploration_ports.dart
│  ├─ exploration_tree.dart
│  └─ exploration_controller.dart
├─ mastery/
│  ├─ student_mastery.dart
│  └─ mock_student_mastery_repository.dart
├─ teaching/
│  └─ teaching_exploration_strategy.dart
├─ practice/
│  ├─ practice_exploration_strategy.dart
│  └─ practice_diagnosis.dart
├─ materials/
│  ├─ exploration_material_card.dart
│  ├─ parabola_painter.dart
│  └─ mock_whiteboard_launcher.dart
├─ adapters/
│  ├─ mock_exploration_content_repository.dart
│  ├─ mock_exploration_gateway.dart
│  └─ in_memory_exploration_adapters.dart
└─ presentation/
   ├─ exploration_lab_page.dart
   ├─ exploration_session_page.dart
   └─ exploration_tree_panel.dart

test/features/dialogue_exploration/
├─ mock_content_and_mastery_test.dart
├─ exploration_tree_test.dart
├─ teaching_exploration_test.dart
├─ practice_exploration_test.dart
├─ exploration_material_test.dart
├─ exploration_page_test.dart
└─ exploration_flow_test.dart
```

---

### Task 1: Common models, ports and Mock inputs

**Files:**
- Create all `core/exploration_models.dart`, `core/exploration_ports.dart`, `mastery/student_mastery.dart`.
- Create `adapters/mock_exploration_content_repository.dart`, `mastery/mock_student_mastery_repository.dart`.
- Create `dialogue_exploration.dart` barrel.
- Test `test/features/dialogue_exploration/mock_content_and_mastery_test.dart`.

**Produces:** `ExplorationScenario`, `ExplorationNodeKind`, `ExplorationNodeStatus`, `DifficultyDiagnosisKind`, `StudentMasterySnapshot`, content/mastery/gateway/trace/evidence/memory/whiteboard ports.

- [ ] Write the fixture contract tests.

```dart
test('Mock 首版包含教学、练习和公开 Demo', () async {
  final repository = MockExplorationContentRepository();
  final scenarios = await repository.loadScenarios();
  expect(scenarios.map((item) => item.id), containsAll(<String>[
    'teaching-quadratic',
    'practice-inequality',
    'demo-coffee-business-model',
  ]));
  expect(await repository.validateFixtures(), isEmpty);
});

test('同一原子提供未知、薄弱、中等和较好掌握快照', () async {
  final repository = MockStudentMasteryRepository();
  final levels = await repository.availableProfiles('quadratic-vertex');
  expect(levels.map((item) => item.level).toSet(), {
    StudentMasteryLevel.unknown,
    StudentMasteryLevel.weak,
    StudentMasteryLevel.developing,
    StudentMasteryLevel.strong,
  });
});
```

- [ ] Run RED: `flutter test test/features/dialogue_exploration/mock_content_and_mastery_test.dart`.

Expected failure: imports/types are missing.

- [ ] Implement the exact enums and immutable contracts.

```dart
enum ExplorationScenarioKind { teaching, practice, publicDemo }
enum ExplorationNodeKind {
  studentQuestion,
  studentHypothesis,
  tutorResponse,
  reasoningStep,
  diagnosis,
  reflection,
  backtrack,
}
enum ExplorationNodeStatus {
  exploring,
  validated,
  contradicted,
  abandoned,
  backtracked,
  completed,
}
enum DifficultyDiagnosisKind {
  conceptGap,
  conditionGap,
  methodSelection,
  reasoningBreak,
  calculationGap,
  promptMisread,
  uncertain,
}
```

`ExplorationNode` includes stable ID, parent ID, kind, status, text, material IDs, optional diagnosis, optional `backtrackTargetNodeId`, creation time and strategy version. Collections are unmodifiable.

- [ ] Implement three scenario fixtures, four material kinds and four mastery profiles. Validate duplicate/missing IDs and out-of-bound material references.

- [ ] Run GREEN and commit only Task 1 files.

```powershell
flutter test test/features/dialogue_exploration/mock_content_and_mastery_test.dart
git add -- lib/features/dialogue_exploration/core/exploration_models.dart lib/features/dialogue_exploration/core/exploration_ports.dart lib/features/dialogue_exploration/mastery lib/features/dialogue_exploration/adapters/mock_exploration_content_repository.dart lib/features/dialogue_exploration/dialogue_exploration.dart test/features/dialogue_exploration/mock_content_and_mastery_test.dart
git commit -m "feat(dialogue): add dual-port exploration domain"
```

---

### Task 2: Tree invariants and explicit backtracking

**Files:**
- Create `core/exploration_tree.dart`.
- Test `test/features/dialogue_exploration/exploration_tree_test.dart`.

**Produces:** immutable `ExplorationTree` operations `append`, `branchFrom`, `updateStatus`, `backtrack`, `fold`, plus depth/width/branch metrics.

- [ ] Write RED tests proving ordinary append does not create a side branch and explicit branching does.

```dart
test('错误路径保留，回退节点指向最后有效节点', () {
  final tree = seededPracticeTree()
      .append(hypothesisNode('try-cauchy'))
      .append(stepNode('condition-fails'))
      .updateStatus('condition-fails', ExplorationNodeStatus.contradicted)
      .backtrack(fromNodeId: 'condition-fails', targetNodeId: 'problem-root');

  expect(tree.nodeById('condition-fails')!.status,
      ExplorationNodeStatus.contradicted);
  expect(tree.nodes.map((item) => item.id), contains('condition-fails'));
  expect(tree.activeLeaf!.kind, ExplorationNodeKind.backtrack);
  expect(tree.activeLeaf!.backtrackTargetNodeId, 'problem-root');
});
```

- [ ] Write RED limit tests for 40 nodes, depth 6 and 8 direct branches. A rejected mutation must return a typed `ExplorationLimitException` and leave the original tree unchanged.

- [ ] Run RED: `flutter test test/features/dialogue_exploration/exploration_tree_test.dart`.

- [ ] Implement immutable operations with parent/reference validation and Chinese comments explaining why contradicted nodes remain.

- [ ] Run GREEN and commit.

```powershell
flutter test test/features/dialogue_exploration/exploration_tree_test.dart
git add -- lib/features/dialogue_exploration/core/exploration_tree.dart test/features/dialogue_exploration/exploration_tree_test.dart
git commit -m "feat(dialogue): add reasoning tree and backtracking"
```

---

### Task 3: Teaching adaptation strategy

**Files:**
- Create `teaching/teaching_exploration_strategy.dart`.
- Create `adapters/mock_exploration_gateway.dart`.
- Test `test/features/dialogue_exploration/teaching_exploration_test.dart`.

**Produces:** `TeachingExplorationStrategy.buildRequest()` and deterministic Gateway routes with answer, principle question, material IDs and memory candidates.

- [ ] Write RED tests for mastery-driven behavior.

```dart
test('薄弱学生先补概念并使用图和互动', () async {
  final result = await harness.reply(
    profile: StudentMasteryLevel.weak,
    question: '二次函数的顶点为什么在这里',
  );
  expect(result.intent, ExplorationIntent.repairPrerequisite);
  expect(result.materialKinds, containsAll([
    ExplorationMaterialKind.figure,
    ExplorationMaterialKind.interactive,
  ]));
});

test('掌握较好学生进入推导而不重复基础定义', () async {
  final result = await harness.reply(
    profile: StudentMasteryLevel.strong,
    question: '二次函数的顶点为什么在这里',
  );
  expect(result.intent, ExplorationIntent.extendReasoning);
  expect(result.answer, isNot(contains('二次函数是')));
  expect(result.followUpQuestion, contains('成立条件'));
});
```

- [ ] Add RED tests for above-stage/unrelated/inappropriate input and five question scaffolds. Successful follow-up may not equal “你觉得呢”.

- [ ] Run RED, implement strategy and deterministic routes, then run GREEN.

- [ ] Commit Task 3 files.

```powershell
git add -- lib/features/dialogue_exploration/teaching lib/features/dialogue_exploration/adapters/mock_exploration_gateway.dart test/features/dialogue_exploration/teaching_exploration_test.dart
git commit -m "feat(dialogue): adapt teaching to student mastery"
```

---

### Task 4: Practice diagnosis confirmation and recovery

**Files:**
- Create `practice/practice_diagnosis.dart`, `practice/practice_exploration_strategy.dart`.
- Create `core/exploration_controller.dart`, `adapters/in_memory_exploration_adapters.dart`.
- Test `test/features/dialogue_exploration/practice_exploration_test.dart`.

**Produces:** controller actions `submit`, `validateStep`, `suggestDiagnosis`, `confirmDiagnosis`, `backtrack`, `saveReflection`, `save`, `export`, `convertCandidates`.

- [ ] Write RED evidence-boundary test.

```dart
test('系统候选诊断未确认时不写掌握证据', () async {
  final harness = practiceHarness();
  await harness.controller.start(harness.inequalityScenario);
  await harness.controller.submitHypothesis('直接使用柯西不等式');
  await harness.controller.validateActiveStep();

  expect(harness.controller.state.pendingDiagnosis, isNotNull);
  expect(harness.masteryEvidenceSink.items, isEmpty);

  await harness.controller.confirmDiagnosis(
    DifficultyDiagnosisKind.conditionGap,
  );
  expect(harness.masteryEvidenceSink.items.single.source,
      MasteryEvidenceSource.confirmedByStudent);
});
```

- [ ] Write RED full practice-flow test: wrong method → condition contradiction → student changes diagnosis → backtrack → new method branch → reflection. Assert the contradicted branch remains visible.

- [ ] Write RED idempotency/failure tests: duplicate submit, Gateway retry, repeated memory conversion and trace saving.

- [ ] Run RED, implement controller and in-memory ports. Async callbacks use a private disposed flag; coherent state transitions notify once.

- [ ] Run GREEN and commit.

```powershell
flutter test test/features/dialogue_exploration/practice_exploration_test.dart
git add -- lib/features/dialogue_exploration/practice lib/features/dialogue_exploration/core/exploration_controller.dart lib/features/dialogue_exploration/adapters/in_memory_exploration_adapters.dart test/features/dialogue_exploration/practice_exploration_test.dart
git commit -m "feat(dialogue): guide practice diagnosis and recovery"
```

---

### Task 5: Four materials and tree UI

**Files:**
- Create `materials/exploration_material_card.dart`, `materials/parabola_painter.dart`, `materials/mock_whiteboard_launcher.dart`.
- Create `presentation/exploration_tree_panel.dart`.
- Test `test/features/dialogue_exploration/exploration_material_test.dart`.

- [ ] Write RED Widget tests for `CustomPaint` figure, explicit “模拟视频” play/pause, live `a/h/k` slider, formula derivation and whiteboard result.

```dart
testWidgets('互动素材改变参数而不是静态截图', (tester) async {
  await tester.pumpWidget(materialHarness(interactiveParabola));
  expect(find.text('a = 1.0'), findsOneWidget);
  await tester.drag(find.byKey(const ValueKey('parabola-a-slider')),
      const Offset(120, 0));
  await tester.pump();
  expect(find.text('a = 1.0'), findsNothing);
});
```

- [ ] Write RED tree test for status labels, fold/unfold, focus, explicit branch and backtrack target display.

- [ ] Implement focused private widgets; no network requests or leaking timers. Mock whiteboard returns parameter changes only when confirmed.

- [ ] Run GREEN and commit.

---

### Task 6: Standalone lab and three acceptance flows

**Files:**
- Create `presentation/exploration_lab_page.dart`, `presentation/exploration_session_page.dart`.
- Modify barrel.
- Modify `lib/main.dart` with one import.
- Modify existing untracked `lib/developer_tools.dart` with one entry, without staging its pre-existing content until ownership is resolved.
- Test `test/features/dialogue_exploration/exploration_page_test.dart`, `exploration_flow_test.dart`.

- [ ] Write RED compact-page tests for scene/profile selection, three teaching entries, loading/failure/retry, diagnosis confirmation, error branch and return action.

- [ ] Write RED teaching flow showing different output for weak vs strong profiles.

- [ ] Write RED inequality flow showing wrong method, contradiction, diagnosis confirmation, backtrack and correct branch.

- [ ] Write RED business flow proving depth ≥3, side branches ≥2, material kinds ≥3 and no empty follow-up.

- [ ] Implement dependency composition once per lab visit and visible “测试数据，退出实验室后清空” copy. Use a drawer/bottom sheet for the tree on phones and a right panel on wide screens.

- [ ] Add the developer tool entry `developer-tool-dialogue-exploration`, title “教学助手：对话探索”.

- [ ] Run verification:

```powershell
dart analyze lib/features/dialogue_exploration test/features/dialogue_exploration
flutter test test/features/dialogue_exploration
flutter test test/widget_test.dart
flutter test
git diff --check
```

- [ ] Commit only owned module/test files and cleanly separable app-shell hunks.

## Prototype Limitations to Report

- 回答、诊断和素材调度为确定性 Mock，不代表正式 AI 教学质量。
- 学生掌握程度为四档 Mock，不写设备或服务端。
- 不等式题与 business model 路径为首版脚本数据。
- 视频、白板和树布局是功能替身，不是最终视觉与生产能力。
- 退出实验室后数据清空；正式 1.1、M2/M3、3.3 和 Skill 后续替换端口。

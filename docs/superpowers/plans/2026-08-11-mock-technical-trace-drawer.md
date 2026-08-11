# Mock Technical Trace Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在远程预习课堂顶栏提供始终可见的“技术轨迹 · Mock”入口，以右侧抽屉展示随当前 Session 变化的教学决策、证据与模拟 MCP 素材选择轨迹。

**Architecture:** 新增独立的不可变轨迹模型与 `MockTechnicalTraceProvider`，只读取 `RemoteLearningSessionSnapshot`，不修改课堂状态。新增独立抽屉 Widget 消费轨迹模型；`RemoteLearningSessionPage` 只负责构建最新轨迹并打开 `endDrawer`，未来真实后端轨迹只需替换 Provider。

**Tech Stack:** Flutter、Dart、Material 3、flutter_test

## Global Constraints

- Mock MCP 候选、版本、过滤与耗时必须显示“模拟数据”，不得冒充真实调用。
- Session 中已存在的阶段、atomId、目标、证据、教学意图、reasonCode 和当前素材必须读取真实快照。
- 抽屉不得展示链式思维、模型草稿或推测学生心理状态。
- 打开和关闭抽屉不得修改 Session、输入、滚动位置或当前树节点。
- 新增模型、Provider 和重要 Widget 使用简洁中文注释说明数据边界。
- 不新增依赖，不修改后端，不改动现有 API 合同。

---

### Task 1: Technical Trace Model and Deterministic Mock Provider

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/technical_trace.dart`
- Create: `test/features/dialogue_exploration/technical_trace_test.dart`

**Interfaces:**
- Consumes: `RemoteLearningSessionSnapshot`
- Produces: `TechnicalTraceSnapshot MockTechnicalTraceProvider.build(RemoteLearningSessionSnapshot snapshot)`
- Produces: `TechnicalTraceEvidence`, `TechnicalTraceMcpSelection`, `TechnicalTraceTiming`

- [ ] **Step 1: Write the failing provider tests**

Create test fixtures from `RemoteLearningSessionSnapshot.fromJson` and assert:

```dart
test('uses real guided-flow facts and clearly marks simulated MCP data', () {
  final trace = const MockTechnicalTraceProvider().build(_guidedSnapshot());

  expect(trace.isMock, isTrue);
  expect(trace.atomId, 'negative-times-negative');
  expect(trace.stageLabel, '动手验证');
  expect(trace.reasonCode, 'GUIDED_OPERATIONAL_EVIDENCE_REQUIRED');
  expect(trace.mcpSelection.isSimulated, isTrue);
  expect(trace.mcpSelection.selectedMaterialId, 'negative-sign-flip-widget');
});

test('returns an open-exploration trace without inventing agent decisions', () {
  final trace = const MockTechnicalTraceProvider().build(_openSnapshot());

  expect(trace.hasGuidedDecision, isFalse);
  expect(trace.reasonCode, isEmpty);
  expect(trace.mcpSelection.candidateCount, 0);
});
```

- [ ] **Step 2: Run provider tests and verify RED**

Run:

```text
flutter test test/features/dialogue_exploration/technical_trace_test.dart
```

Expected: FAIL because `technical_trace.dart` and provider types do not exist.

- [ ] **Step 3: Implement the minimal immutable model and Provider**

Implement these public shapes:

```dart
final class TechnicalTraceEvidence {
  const TechnicalTraceEvidence({
    required this.code,
    required this.strengthLabel,
    required this.sourceType,
    required this.recordedAt,
  });

  final String code;
  final String strengthLabel;
  final String sourceType;
  final String recordedAt;
}

final class TechnicalTraceMcpSelection {
  const TechnicalTraceMcpSelection({
    required this.isSimulated,
    required this.toolName,
    required this.requestSummary,
    required this.candidateCount,
    required this.filteredReasons,
    required this.selectedMaterialId,
    required this.selectedVersion,
  });

  final bool isSimulated;
  final String toolName;
  final String requestSummary;
  final int candidateCount;
  final List<String> filteredReasons;
  final String selectedMaterialId;
  final String selectedVersion;
}

final class TechnicalTraceTiming {
  const TechnicalTraceTiming({
    required this.agentMs,
    required this.mcpMs,
    required this.validationMs,
    required this.totalMs,
  });

  final int agentMs;
  final int mcpMs;
  final int validationMs;
  final int totalMs;
}

final class TechnicalTraceSnapshot {
  const TechnicalTraceSnapshot({
    required this.isMock,
    required this.hasGuidedDecision,
    required this.sessionId,
    required this.lessonPlanId,
    required this.atomId,
    required this.goal,
    required this.stageLabel,
    required this.latestEvidence,
    required this.missingEvidenceCodes,
    required this.teacherAction,
    required this.pedagogicalIntent,
    required this.reasonCode,
    required this.mcpSelection,
    required this.timing,
    required this.fallbackUsed,
    required this.fallbackReason,
  });

  final bool isMock;
  final bool hasGuidedDecision;
  final String sessionId;
  final String lessonPlanId;
  final String atomId;
  final String goal;
  final String stageLabel;
  final TechnicalTraceEvidence? latestEvidence;
  final List<String> missingEvidenceCodes;
  final String teacherAction;
  final String pedagogicalIntent;
  final String reasonCode;
  final TechnicalTraceMcpSelection mcpSelection;
  final TechnicalTraceTiming timing;
  final bool fallbackUsed;
  final String fallbackReason;
}

final class MockTechnicalTraceProvider {
  const MockTechnicalTraceProvider();

  TechnicalTraceSnapshot build(RemoteLearningSessionSnapshot snapshot) {
    final flow = snapshot.teachingFlow;
    final materialUsageId = flow?.currentAction.materialUsageId;
    RemoteLearningMaterial? selectedMaterial;
    for (final material in snapshot.materials) {
      if (material.id == materialUsageId) selectedMaterial = material;
    }
    selectedMaterial ??= snapshot.materials.isEmpty ? null : snapshot.materials.last;

    return TechnicalTraceSnapshot(
      isMock: true,
      hasGuidedDecision: flow != null,
      sessionId: snapshot.session.id,
      lessonPlanId: flow?.lessonPlanId ?? '',
      atomId: flow?.atomId ?? snapshot.session.atomId ?? '',
      goal: flow?.goal ?? '',
      stageLabel: _stageLabel(flow?.stage),
      latestEvidence: _latestEvidence(flow),
      missingEvidenceCodes: List.unmodifiable(flow?.evidence.missingCodes ?? const []),
      teacherAction: flow?.currentAction.type ?? '',
      pedagogicalIntent: flow?.currentAction.pedagogicalIntent ?? '',
      reasonCode: flow?.currentAction.reasonCode ?? '',
      mcpSelection: TechnicalTraceMcpSelection(
        isSimulated: true,
        toolName: selectedMaterial == null ? '' : 'search_teaching_assets',
        requestSummary: flow == null
            ? ''
            : 'atom=${flow.atomId}; intent=${flow.currentAction.pedagogicalIntent}',
        candidateCount: selectedMaterial == null ? 0 : 4,
        filteredReasons: selectedMaterial == null
            ? const []
            : const ['排除未审核版本（模拟）', '排除设备不兼容素材（模拟）'],
        selectedMaterialId: selectedMaterial?.materialId ?? '',
        selectedVersion: selectedMaterial == null
            ? ''
            : '${selectedMaterial.materialId}@mock-v1',
      ),
      timing: _timing(flow?.stage),
      fallbackUsed: false,
      fallbackReason: '',
    );
  }

  TechnicalTraceEvidence? _latestEvidence(RemoteTeachingFlow? flow) {
    if (flow == null || flow.evidence.items.isEmpty) return null;
    final item = flow.evidence.items.last;
    return TechnicalTraceEvidence(
      code: item.code,
      strengthLabel: item.strength.name.toUpperCase(),
      sourceType: item.sourceType,
      recordedAt: item.recordedAt,
    );
  }

  String _stageLabel(RemoteTeachingStage? stage) => switch (stage) {
    RemoteTeachingStage.dialogue => '说出猜想',
    RemoteTeachingStage.asset => '动手验证',
    RemoteTeachingStage.focus => '确认发现',
    RemoteTeachingStage.reflect => '整理收获',
    _ => '开放探索',
  };

  TechnicalTraceTiming _timing(RemoteTeachingStage? stage) => switch (stage) {
    RemoteTeachingStage.dialogue => const TechnicalTraceTiming(
      agentMs: 320,
      mcpMs: 0,
      validationMs: 24,
      totalMs: 344,
    ),
    RemoteTeachingStage.asset => const TechnicalTraceTiming(
      agentMs: 348,
      mcpMs: 176,
      validationMs: 31,
      totalMs: 555,
    ),
    RemoteTeachingStage.focus => const TechnicalTraceTiming(
      agentMs: 305,
      mcpMs: 0,
      validationMs: 28,
      totalMs: 333,
    ),
    RemoteTeachingStage.reflect => const TechnicalTraceTiming(
      agentMs: 286,
      mcpMs: 0,
      validationMs: 22,
      totalMs: 308,
    ),
    _ => const TechnicalTraceTiming(
      agentMs: 0,
      mcpMs: 0,
      validationMs: 0,
      totalMs: 0,
    ),
  };
}
```

Mapping rules:

- `flow == null`: `hasGuidedDecision=false`, empty decision fields, zero MCP candidates.
- `flow != null`: use `flow.lessonPlanId/atomId/goal/currentAction/evidence` directly.
- Resolve current material by `flow.currentAction.materialUsageId`; after the ASSET stage use the latest material so the previous selection remains auditable.
- Use stage-specific fixed candidate counts and timings; never call random or current clock APIs.
- Mark all MCP-derived details `isSimulated=true`.

- [ ] **Step 4: Run provider tests and verify GREEN**

Run the same targeted test; expected PASS.

- [ ] **Step 5: Commit Task 1**

```text
git add lib/features/dialogue_exploration/presentation/technical_trace.dart test/features/dialogue_exploration/technical_trace_test.dart
git commit -m "feat(exploration): model mock technical trace"
```

---

### Task 2: Technical Trace Drawer Widget

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/technical_trace_drawer.dart`
- Modify: `test/features/dialogue_exploration/technical_trace_test.dart`

**Interfaces:**
- Consumes: `TechnicalTraceSnapshot trace`
- Produces: `TechnicalTraceDrawer({required TechnicalTraceSnapshot trace})`

- [ ] **Step 1: Add failing Widget tests**

Add assertions for the real facts and Mock disclosure:

```dart
testWidgets('drawer exposes auditable facts and mock disclosure', (tester) async {
  final trace = const MockTechnicalTraceProvider().build(_guidedSnapshot());
  await tester.pumpWidget(MaterialApp(home: Scaffold(
    body: TechnicalTraceDrawer(trace: trace),
  )));

  expect(find.byKey(const ValueKey('technical-trace-drawer')), findsOneWidget);
  expect(find.text('Mock 演示数据'), findsOneWidget);
  expect(find.text('GUIDED_OPERATIONAL_EVIDENCE_REQUIRED'), findsOneWidget);
  expect(find.text('素材选择（模拟）'), findsOneWidget);
});
```

Add an open-exploration empty-state assertion for “当前为开放探索，暂无引导式技术轨迹”。

- [ ] **Step 2: Run Widget tests and verify RED**

Expected: FAIL because `TechnicalTraceDrawer` does not exist.

- [ ] **Step 3: Implement the scrollable right drawer**

Use a `SafeArea` + constrained `Material` + `ListView`. Render six isolated sections:

1. Mock disclosure.
2. 教学上下文.
3. 学习证据.
4. Teacher Agent 动作.
5. 素材选择（模拟）.
6. 耗时与 fallback（模拟）.

Use stable keys:

```text
technical-trace-drawer
technical-trace-mock-banner
technical-trace-context
technical-trace-evidence
technical-trace-action
technical-trace-mcp
technical-trace-timing
```

Unknown or empty fields render explicit empty-state copy and never throw.

- [ ] **Step 4: Run Widget tests and verify GREEN**

Run targeted test; expected PASS without overflow exceptions.

- [ ] **Step 5: Commit Task 2**

```text
git add lib/features/dialogue_exploration/presentation/technical_trace_drawer.dart test/features/dialogue_exploration/technical_trace_test.dart
git commit -m "feat(exploration): render mock technical trace drawer"
```

---

### Task 3: Remote Classroom Integration

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: `MockTechnicalTraceProvider.build(snapshot)`
- Produces: AppBar entry key `open-technical-trace`
- Produces: Scaffold `endDrawer` with the latest trace snapshot

- [ ] **Step 1: Add failing classroom integration test**

Use the existing guided fixture and assert:

```dart
expect(find.byKey(const ValueKey('open-technical-trace')), findsOneWidget);
await tester.tap(find.byKey(const ValueKey('open-technical-trace')));
await tester.pumpAndSettle();
expect(find.byKey(const ValueKey('technical-trace-drawer')), findsOneWidget);
expect(find.text('技术轨迹 · Mock'), findsWidgets);
```

Capture `controller.state.snapshot!.currentNodeId` before opening and assert it is unchanged after closing the drawer.

- [ ] **Step 2: Run integration test and verify RED**

Run:

```text
flutter test test/features/dialogue_exploration/live_tree_page_test.dart --plain-name "guided classroom opens mock technical trace without changing session state"
```

Expected: FAIL because the AppBar entry is absent.

- [ ] **Step 3: Integrate the entry and endDrawer**

In `RemoteLearningSessionPage.build`:

```dart
final trace = const MockTechnicalTraceProvider().build(snapshot);
return Scaffold(
  endDrawer: TechnicalTraceDrawer(trace: trace),
  appBar: AppBar(actions: [
    Builder(builder: (context) => TextButton.icon(
      key: const ValueKey('open-technical-trace'),
      onPressed: () => Scaffold.of(context).openEndDrawer(),
      icon: const Icon(Icons.account_tree_outlined),
      label: const Text('技术轨迹 · Mock'),
    )),
    // preserve existing actions
  ]),
  // preserve existing body
);
```

Keep the entry visible for guided and open exploration sessions. Do not call the controller when opening the drawer.

- [ ] **Step 4: Run integration and trace tests**

Expected: both targeted suites PASS.

- [ ] **Step 5: Commit Task 3**

```text
git add lib/features/dialogue_exploration/presentation/remote_exploration_page.dart test/features/dialogue_exploration/live_tree_page_test.dart
git commit -m "feat(exploration): expose mock technical trace"
```

---

### Task 4: Formatting and Verification

**Files:**
- Verify all files changed by Tasks 1–3

**Interfaces:**
- Consumes: completed implementation
- Produces: formatted, analyzed, regression-tested Flutter feature

- [ ] **Step 1: Format touched Dart files**

```text
dart format lib/features/dialogue_exploration/presentation/technical_trace.dart lib/features/dialogue_exploration/presentation/technical_trace_drawer.dart lib/features/dialogue_exploration/presentation/remote_exploration_page.dart test/features/dialogue_exploration/technical_trace_test.dart test/features/dialogue_exploration/live_tree_page_test.dart
```

- [ ] **Step 2: Run static analysis**

```text
dart analyze lib/main.dart test
```

Expected: no new errors or warnings.

- [ ] **Step 3: Run targeted tests**

```text
flutter test test/features/dialogue_exploration/technical_trace_test.dart
flutter test test/features/dialogue_exploration/live_tree_page_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run the full Flutter test suite**

```text
flutter test
```

Expected: PASS.

- [ ] **Step 5: Inspect the final diff**

Confirm only the new technical trace files, classroom integration, tests and this plan changed for the feature; preserve unrelated dirty worktree changes.

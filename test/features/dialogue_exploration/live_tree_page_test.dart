import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/core/remote_exploration_session_controller.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/remote_exploration_page.dart';

void main() {
  testWidgets(
    'chapter workspace shows learning, practice, review and the knowledge route',
    (tester) async {
      final api = _UiFakeApi();
      await tester.pumpWidget(
        MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
      );
      await tester.pumpAndSettle();

      expect(find.text('负数运算'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chapter-phase-learning')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-phase-practice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-phase-review')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-node-opposite-number')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('chapter-node-negative-times-negative-concept'),
        ),
        findsOneWidget,
      );
      expect(find.text('预计 10 分钟'), findsNWidgets(3));
      expect(find.text('进入这个知识点'), findsOneWidget);
    },
  );

  testWidgets(
    'desktop classroom keeps the mission, exploration map and learning assets visible',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('exploration-mission-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('exploration-session-timer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ai-exploration-classroom')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('personal-thinking-tree')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-sidebar-current-path')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('knowledge-overview-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chapter-knowledge-tree')),
        findsNothing,
      );
      expect(find.text('查看完整地图'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('learning-assets-preview')),
        findsOneWidget,
      );
      expect(find.text('导出探索地图'), findsOneWidget);
      expect(find.text('学习素材'), findsNothing);
      expect(find.text('知识结构图（章节地图）'), findsNothing);
    },
  );

  testWidgets(
    'session presents a guided exploration task instead of a chat log',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = RemoteExplorationSessionController(api: _UiFakeApi());
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('今日探索'), findsOneWidget);
      expect(find.text('探索阶段 1/3'), findsOneWidget);
      expect(find.text('AI 探索课堂'), findsOneWidget);
      expect(find.text('我的探索地图'), findsOneWidget);
      expect(find.text('当前探索路径'), findsNothing);
      expect(find.text('5/20 个问题节点'), findsNothing);
    },
  );

  testWidgets('long session sidebar only keeps the latest seven path nodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _UiFakeApi(sessionSnapshot: _longPathSnapshot());
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadChapter('negative-number-operations');
    await controller.startFromChapterNode('negative-times-negative-concept');

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('已折叠 5 个较早理解节点'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-tree-node-node-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('remote-tree-node-node-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-tree-node-node-11')),
      findsOneWidget,
    );
  });

  testWidgets(
    'opposite-number material lets the learner inspect a real number change',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = RemoteExplorationSessionController(
        api: _UiFakeApi(sessionSnapshot: _signFlipSnapshot()),
      );
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('选一个数，再亲手执行“取相反数”。'), findsOneWidget);
      expect(find.textContaining('当前方向'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sign-flip-apply')));
      await tester.pump();
      expect(find.text('-3  →  3'), findsOneWidget);
    },
  );

  testWidgets('full thinking tree remains readable for a long path on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _UiFakeApi(sessionSnapshot: _longPathSnapshot());
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadChapter('negative-number-operations');
    await controller.startFromChapterNode('negative-times-negative-concept');

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('探索地图'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('remote-tree-node-node-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-tree-node-node-11')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('remote-tree-node-node-11')))
          .width,
      greaterThanOrEqualTo(220),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop keeps the exploration classroom and live map visible together',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start(directionId: 'graph');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('exploration-classroom-stage')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('exploration-live-tree')),
        findsOneWidget,
      );
      expect(find.text('这一步成立需要什么条件？'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a tree node is read-only and reveals explicit actions',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start(directionId: 'graph');
      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('remote-tree-node-node-1')));
      await tester.pump();

      expect(api.branchCalls, 0);
      expect(api.turnCalls, 0);
      expect(api.backtrackCalls, 0);
      expect(find.text('从这里继续'), findsOneWidget);
      expect(find.text('新开支线'), findsOneWidget);
      expect(find.text('回溯到这里'), findsOneWidget);
      expect(find.text('转为记忆候选'), findsOneWidget);
    },
  );

  testWidgets(
    'mobile keeps the exploration map trigger visible and can expand the full map',
    (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start(directionId: 'graph');
      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mobile-current-path')), findsOneWidget);
      await tester.tap(find.text('探索地图'));
      await tester.pumpAndSettle();
      expect(find.text('我的探索地图'), findsOneWidget);
    },
  );
}

final class _UiFakeApi implements RemoteExplorationGateway {
  _UiFakeApi({this._sessionSnapshot});

  final RemoteLearningSessionSnapshot? _sessionSnapshot;
  int turnCalls = 0;
  int branchCalls = 0;
  int backtrackCalls = 0;

  final chapter = LearningChapterOverviewSnapshot(
    chapterId: 'negative-number-operations',
    title: '负数运算',
    description: '从负数意义出发理解运算规则。',
    estimatedMinutes: 30,
    progress: .2,
    recommendedNodeId: 'negative-times-negative-concept',
    phases: const [
      LearningChapterPhaseSnapshot(
        kind: 'LEARNING',
        title: '学习',
        summary: '理解概念',
        status: 'IN_PROGRESS',
        progress: .3,
        itemCount: 2,
      ),
      LearningChapterPhaseSnapshot(
        kind: 'PRACTICE',
        title: '练习',
        summary: '验证规则',
        status: 'AVAILABLE',
        progress: 0,
        itemCount: 1,
      ),
      LearningChapterPhaseSnapshot(
        kind: 'REVIEW',
        title: '复习',
        summary: '回顾易错点',
        status: 'LOCKED',
        progress: 0,
        itemCount: 1,
      ),
    ],
    nodes: const [
      LearningChapterNodeSnapshot(
        id: 'opposite-number',
        parentId: null,
        atomId: 'negative-times-negative',
        title: '相反数与方向翻转',
        description: '理解连续两次方向翻转。',
        phase: 'LEARNING',
        hookQuestion: '连续两次取相反数会怎样？',
        recommended: false,
      ),
      LearningChapterNodeSnapshot(
        id: 'negative-times-negative-concept',
        parentId: 'opposite-number',
        atomId: 'negative-times-negative',
        title: '为什么负负得正',
        description: '验证负数乘法规则。',
        phase: 'LEARNING',
        hookQuestion: '为什么两个负数相乘会得到正数？',
        recommended: true,
      ),
    ],
  );

  final entry = LearningEntrySnapshot(
    atomId: 'quadratic-function',
    title: '二次函数探索',
    coreQuestion: '为什么抛物线会出现？',
    estimatedMinutes: 10,
    recommendedDirectionId: 'graph',
    directions: const [
      LearningDirectionSnapshot(
        id: 'basic',
        title: '基础概念',
        description: '先看二次意味着什么',
        hookQuestion: '什么是二次函数？',
      ),
      LearningDirectionSnapshot(
        id: 'graph',
        title: '图像秘密',
        description: '观察顶点和开口方向',
        hookQuestion: '二次函数的顶点为什么在这里？',
      ),
      LearningDirectionSnapshot(
        id: 'application',
        title: '现实应用',
        description: '连接最值问题',
        hookQuestion: '二次函数能解决哪些现实问题？',
      ),
    ],
  );

  RemoteLearningSessionSnapshot get snapshot =>
      _sessionSnapshot ??
      RemoteLearningSessionSnapshot(
        session: const RemoteLearningSessionInfo(
          id: 'learning-1',
          exploreSessionId: 'explore-1',
          topic: '二次函数探索',
          scenarioId: 'teaching',
          atomId: 'quadratic-function',
          status: 'ACTIVE',
          revision: 1,
          nodeCount: 1,
          startedAt: '2026-08-06T01:00:00.000Z',
          expiresAt: '2026-08-06T01:10:00.000Z',
          completedAt: null,
        ),
        currentNodeId: 'node-1',
        activeStrategy: 'QUESTION_CHAIN',
        nodes: const [
          RemoteLearningNode(
            id: 'node-1',
            parentId: null,
            status: 'VALIDATED',
            question: '二次函数的顶点为什么在这里？',
            answer: '顶点来自完全平方结构。',
            followUpQuestion: '这一步成立需要什么条件？',
            strategy: 'QUESTION_CHAIN',
            depth: 0,
            isSideBranch: false,
            backtrackTargetId: null,
            confidence: .8,
            createdAt: '2026-08-06T01:00:00.000Z',
          ),
        ],
        materials: const [
          RemoteLearningMaterial(
            id: 'material-1',
            nodeId: 'node-1',
            materialId: 'quadratic-parabola-widget',
            type: 'INTERACTIVE',
            title: '拖动参数观察抛物线',
            componentKey: 'parabola_widget',
            payload: {},
          ),
        ],
        summary: null,
      );

  @override
  Future<LearningChapterOverviewSnapshot> getChapterOverview(
    String chapterId,
  ) async => chapter;

  @override
  Future<LearningEntrySnapshot> getEntry(String atomId) async => entry;

  @override
  Future<RemoteLearningSessionSnapshot> createSession({
    required String atomId,
    required String scenarioId,
    String? directionId,
    String? question,
    String? idempotencyKey,
  }) async => snapshot;

  @override
  Future<RemoteLearningSessionSnapshot?> restoreLatest() async => null;

  @override
  Future<RemoteLearningSessionSnapshot> submitTurn({
    required String sessionId,
    required String question,
    String? parentNodeId,
    String? idempotencyKey,
  }) async {
    turnCalls += 1;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot> createBranch({
    required String sessionId,
    required String parentNodeId,
    required String question,
    String? idempotencyKey,
  }) async {
    branchCalls += 1;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot> backtrack({
    required String sessionId,
    required String targetNodeId,
    String? idempotencyKey,
  }) async {
    backtrackCalls += 1;
    return snapshot;
  }

  @override
  Future<Map<String, Object?>> createMemoryCandidate({
    required String sessionId,
    required String nodeId,
    String? idempotencyKey,
  }) async => const {'id': 'memory-1', 'status': 'PENDING'};

  @override
  Future<RemoteLearningSessionSnapshot> complete({
    required String sessionId,
    required String reflection,
    String? idempotencyKey,
  }) async => snapshot;

  @override
  Future<String> exportTree(String sessionId) async => '{"schemaVersion":1}';
}

RemoteLearningSessionSnapshot _longPathSnapshot() {
  final nodes = List.generate(
    12,
    (index) => RemoteLearningNode(
      id: 'node-$index',
      parentId: index == 0 ? null : 'node-${index - 1}',
      status: 'VALIDATED',
      question: '第 ${index + 1} 个探索问题',
      answer: '第 ${index + 1} 个回答',
      followUpQuestion: '下一步可以追问：第 ${index + 2} 个问题是什么？',
      strategy: 'QUESTION_CHAIN',
      depth: index,
      isSideBranch: false,
      backtrackTargetId: null,
      confidence: .8,
      createdAt: '2026-08-06T01:${index.toString().padLeft(2, '0')}:00.000Z',
    ),
  );
  return RemoteLearningSessionSnapshot(
    session: const RemoteLearningSessionInfo(
      id: 'learning-long',
      exploreSessionId: 'explore-1',
      topic: '负数乘法探索',
      scenarioId: 'teaching',
      atomId: 'negative-times-negative',
      status: 'ACTIVE',
      revision: 12,
      nodeCount: 12,
      startedAt: '2026-08-06T01:00:00.000Z',
      expiresAt: '2026-08-06T01:10:00.000Z',
      completedAt: null,
    ),
    currentNodeId: 'node-11',
    activeStrategy: 'QUESTION_CHAIN',
    nodes: nodes,
    materials: const [],
    summary: null,
  );
}

RemoteLearningSessionSnapshot _signFlipSnapshot() {
  return RemoteLearningSessionSnapshot(
    session: RemoteLearningSessionInfo(
      id: 'learning-sign-flip',
      exploreSessionId: 'explore-1',
      topic: '负数乘法探索',
      scenarioId: 'teaching',
      atomId: 'negative-times-negative',
      status: 'ACTIVE',
      revision: 1,
      nodeCount: 1,
      startedAt: '2026-08-06T01:00:00.000Z',
      expiresAt: '2026-08-13T01:00:00.000Z',
      completedAt: null,
    ),
    currentNodeId: 'sign-node',
    activeStrategy: 'SOCRATIC',
    nodes: [
      RemoteLearningNode(
        id: 'sign-node',
        parentId: null,
        status: 'VALIDATED',
        question: '为什么乘以 -1 是取相反数？',
        answer: '先从 -3 开始，亲手对它取一次相反数。',
        followUpQuestion: '取完一次后，数值的哪一部分变了，哪一部分没有变？',
        strategy: 'SOCRATIC',
        depth: 0,
        isSideBranch: false,
        backtrackTargetId: null,
        confidence: .8,
        createdAt: '2026-08-06T01:00:00.000Z',
      ),
    ],
    materials: [
      RemoteLearningMaterial(
        id: 'sign-material',
        nodeId: 'sign-node',
        materialId: 'negative-sign-flip-widget',
        type: 'INTERACTIVE',
        title: '动手验证：取相反数',
        componentKey: 'sign_flip_widget',
        payload: {},
      ),
    ],
    summary: null,
  );
}

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
      expect(find.text('进入这个知识点'), findsOneWidget);
    },
  );

  testWidgets(
    'desktop workbench keeps session status, both trees and statistics visible',
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
        find.byKey(const ValueKey('exploration-session-progress')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('exploration-session-timer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('current-exploration-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('personal-thinking-tree')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-knowledge-tree')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('knowledge-overview-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('exploration-stats-card')),
        findsOneWidget,
      );
      expect(find.text('相反数与方向翻转'), findsOneWidget);
    },
  );

  testWidgets('desktop keeps the conversation and live tree visible together', (
    tester,
  ) async {
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
      find.byKey(const ValueKey('exploration-chat-stage')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('exploration-live-tree')), findsOneWidget);
    expect(find.text('这一步成立需要什么条件？'), findsOneWidget);
  });

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
    'mobile keeps the current path visible and can expand the full tree',
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
      await tester.tap(find.text('完整知识树'));
      await tester.pumpAndSettle();
      expect(find.text('我的思维树'), findsOneWidget);
    },
  );
}

final class _UiFakeApi implements RemoteExplorationGateway {
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

  RemoteLearningSessionSnapshot get snapshot => RemoteLearningSessionSnapshot(
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

import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/core/remote_exploration_session_controller.dart';

void main() {
  test('loads entry and creates the first server session', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteExplorationSessionController(api: api);

    await controller.loadEntry('quadratic-function');
    await controller.start(directionId: 'graph-secret');

    expect(controller.state.entry?.title, '二次函数探索');
    expect(controller.state.status, RemoteExplorationStatus.active);
    expect(controller.state.snapshot?.nodes.single.question, '二次函数的顶点为什么在这里？');
    expect(api.createCalls, 1);
  });

  test(
    'selecting an old node is read-only until an explicit action is chosen',
    () async {
      final api = _FakeRemoteApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start(directionId: 'graph-secret');

      controller.inspectNode('node-1');

      expect(controller.state.inspectedNodeId, 'node-1');
      expect(api.branchCalls, 0);
      expect(api.turnCalls, 0);
      expect(api.backtrackCalls, 0);
    },
  );

  test('explicit branch submits against the inspected parent', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start(directionId: 'graph-secret');
    controller.inspectNode('node-1');
    controller.prepareBranchFromInspected();

    await controller.submitQuestion('它和现实中的最值有什么关系？');

    expect(api.branchCalls, 1);
    expect(api.lastParentNodeId, 'node-1');
    expect(controller.state.composerMode, RemoteComposerMode.currentPath);
  });

  test('remote failure keeps the last tree and exposes a retry', () async {
    final api = _FakeRemoteApi()..failNextTurn = true;
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start(directionId: 'graph-secret');
    final previous = controller.state.snapshot;

    await controller.submitQuestion('继续追问');

    expect(controller.state.snapshot, same(previous));
    expect(controller.state.status, RemoteExplorationStatus.failed);
    expect(controller.state.canRetry, isTrue);
    await controller.retry();
    expect(api.turnCalls, 2);
    expect(controller.state.status, RemoteExplorationStatus.active);
  });

  test('backtrack, memory, complete and export use server endpoints', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start(directionId: 'graph-secret');
    controller.inspectNode('node-1');

    await controller.backtrackToInspected();
    controller.inspectNode('node-1');
    await controller.convertInspectedToMemory();
    await controller.complete('顶点是否最大或最小取决于开口方向。');
    final exported = await controller.exportTree();

    expect(api.backtrackCalls, 1);
    expect(api.memoryCalls, 1);
    expect(api.completeCalls, 1);
    expect(exported, contains('schemaVersion'));
    expect(controller.state.status, RemoteExplorationStatus.completed);
  });
}

final class _FakeRemoteApi implements RemoteExplorationGateway {
  int createCalls = 0;
  int turnCalls = 0;
  int branchCalls = 0;
  int backtrackCalls = 0;
  int memoryCalls = 0;
  int completeCalls = 0;
  String? lastParentNodeId;
  bool failNextTurn = false;

  final entry = LearningEntrySnapshot(
    atomId: 'quadratic-function',
    title: '二次函数探索',
    coreQuestion: '为什么抛物线会出现？',
    estimatedMinutes: 10,
    recommendedDirectionId: 'graph-secret',
    directions: const [
      LearningDirectionSnapshot(
        id: 'graph-secret',
        title: '图像秘密',
        description: '观察图像结构',
        hookQuestion: '二次函数的顶点为什么在这里？',
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
    materials: const [],
    summary: null,
  );

  @override
  Future<LearningEntrySnapshot> getEntry(String atomId) async => entry;

  @override
  Future<RemoteLearningSessionSnapshot> createSession({
    required String atomId,
    required String scenarioId,
    String? directionId,
    String? question,
    String? idempotencyKey,
  }) async {
    createCalls += 1;
    return snapshot;
  }

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
    if (failNextTurn) {
      failNextTurn = false;
      throw const RemoteExplorationException('网络暂时不可用');
    }
    lastParentNodeId = parentNodeId;
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
    lastParentNodeId = parentNodeId;
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
  }) async {
    memoryCalls += 1;
    return const {'id': 'memory-1', 'status': 'PENDING'};
  }

  @override
  Future<RemoteLearningSessionSnapshot> complete({
    required String sessionId,
    required String reflection,
    String? idempotencyKey,
  }) async {
    completeCalls += 1;
    return RemoteLearningSessionSnapshot(
      session: snapshot.session.copyWith(status: 'COMPLETED'),
      currentNodeId: snapshot.currentNodeId,
      activeStrategy: snapshot.activeStrategy,
      nodes: snapshot.nodes,
      materials: snapshot.materials,
      summary: const RemoteLearningSummary(
        studentRestatement: '顶点是否最大或最小取决于开口方向。',
        concept: 82,
        application: 70,
        boundary: 76,
        misconceptions: [],
        interestDirections: [],
        recommendedReview: [],
      ),
    );
  }

  @override
  Future<String> exportTree(String sessionId) async => '{"schemaVersion":1}';
}

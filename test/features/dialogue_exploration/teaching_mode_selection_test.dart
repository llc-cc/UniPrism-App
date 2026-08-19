import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/core/remote_exploration_session_controller.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/intro_chat_messages.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/teaching_mode_selection_stage.dart';

void main() {
  group('RemoteProcessSchedulerState.tryFromJson', () {
    test('parses full mode selection payload with menu options', () {
      final state = RemoteProcessSchedulerState.tryFromJson({
        'schemaVersion': 1,
        'lessonPlanId': 'plan-neg-times-neg',
        'currentGoalIndex': 0,
        'currentPhase': 'MODE_SELECTION',
        'goalStatuses': ['IN_PROGRESS', 'NOT_STARTED'],
        'modeMenuOptions': [
          {
            'skill': 'MORE_EXAMPLES',
            'label': '多看几个例子',
            'icon': '📚',
            'description': '通过更多例题加深理解',
          },
          {
            'skill': 'INTERACTIVE_EXPLORATION',
            'label': '玩一个小实验',
            'icon': '🎮',
            'description': '通过互动组件亲手探索规律',
          },
        ],
        'selectedSkill': null,
        'extraSupportCount': 0,
        'completedAt': null,
        'updatedAt': '2026-08-17T09:00:00.000Z',
      });
      expect(state, isNotNull);
      expect(state!.currentPhase, RemoteTeachingPhase.modeSelection);
      expect(state.lessonPlanId, 'plan-neg-times-neg');
      expect(state.currentGoalIndex, 0);
      expect(state.goalStatuses, [
        RemoteLessonGoalStatus.inProgress,
        RemoteLessonGoalStatus.notStarted,
      ]);
      expect(state.modeMenuOptions, hasLength(2));
      expect(state.modeMenuOptions!.first.skill, 'MORE_EXAMPLES');
      expect(state.modeMenuOptions!.first.icon, '📚');
      expect(state.selectedSkill, isNull);
      expect(state.isAwaitingModeSelection, isTrue);
    });

    test('unknown phase and status wire values do not throw', () {
      final state = RemoteProcessSchedulerState.tryFromJson({
        'lessonPlanId': 'plan',
        'currentGoalIndex': 0,
        'currentPhase': 'FUTURE_PHASE',
        'goalStatuses': ['MYSTERY'],
        'extraSupportCount': 0,
        'updatedAt': '2026-08-17T09:00:00.000Z',
      });
      expect(state, isNotNull);
      expect(state!.currentPhase, RemoteTeachingPhase.unknown);
      expect(state.goalStatuses.single, RemoteLessonGoalStatus.unknown);
      expect(state.isAwaitingModeSelection, isFalse);
    });

    test('returns null for empty or missing lessonPlanId payload', () {
      expect(RemoteProcessSchedulerState.tryFromJson(null), isNull);
      expect(RemoteProcessSchedulerState.tryFromJson(const {}), isNull);
      expect(
        RemoteProcessSchedulerState.tryFromJson({'lessonPlanId': ''}),
        isNull,
      );
    });

    test('filters malformed mode menu entries but keeps valid ones', () {
      final state = RemoteProcessSchedulerState.tryFromJson({
        'lessonPlanId': 'plan-1',
        'currentGoalIndex': 0,
        'currentPhase': 'MODE_SELECTION',
        'goalStatuses': ['IN_PROGRESS'],
        'modeMenuOptions': [
          {
            'skill': 'VIDEO',
            'label': '看一个视频',
            'icon': '🎬',
            'description': '通过视频直观理解概念',
          },
          {'skill': 'BROKEN'},
          'not-a-map',
        ],
        'extraSupportCount': 0,
        'updatedAt': '2026-08-17T09:00:00.000Z',
      });
      expect(state, isNotNull);
      expect(state!.modeMenuOptions, hasLength(1));
      expect(state.modeMenuOptions!.single.skill, 'VIDEO');
    });
  });

  group('RemoteLearningSessionSnapshot.processSchedulerState', () {
    test('exposes scheduler state when present on server snapshot', () {
      final snapshot = RemoteLearningSessionSnapshot.fromJson({
        'session': {
          'id': 'learning-1',
          'exploreSessionId': 'explore-1',
          'topic': '负数运算',
          'scenarioId': 'prestudy',
          'atomId': 'negative-times-negative',
          'status': 'ACTIVE',
          'revision': 3,
          'nodeCount': 1,
          'startedAt': '2026-08-17T09:00:00.000Z',
          'expiresAt': '2099-08-17T09:00:00.000Z',
          'completedAt': null,
        },
        'currentNodeId': 'node-1',
        'activeStrategy': 'QUESTION_CHAIN',
        'nodes': [
          {
            'id': 'node-1',
            'parentId': null,
            'status': 'VALIDATED',
            'question': '为什么负负得正？',
            'answer': '因为两次翻转方向',
            'followUpQuestion': '换一种情境还成立吗？',
            'strategy': 'QUESTION_CHAIN',
            'depth': 0,
            'isSideBranch': false,
            'backtrackTargetId': null,
            'confidence': 0.8,
            'createdAt': '2026-08-17T09:00:00.000Z',
          },
        ],
        'materials': const <Map<String, Object?>>[],
        'processSchedulerState': {
          'schemaVersion': 1,
          'lessonPlanId': 'plan-neg-times-neg',
          'currentGoalIndex': 0,
          'currentPhase': 'MODE_SELECTION',
          'goalStatuses': ['IN_PROGRESS'],
          'modeMenuOptions': [
            {
              'skill': 'MORE_EXAMPLES',
              'label': '多看几个例子',
              'icon': '📚',
              'description': '通过更多例题加深理解',
            },
          ],
          'extraSupportCount': 0,
          'updatedAt': '2026-08-17T09:00:00.000Z',
        },
      });
      expect(snapshot.processSchedulerState, isNotNull);
      expect(
        snapshot.processSchedulerState!.currentPhase,
        RemoteTeachingPhase.modeSelection,
      );
    });

    test('keeps processSchedulerState null when server omits the field', () {
      final snapshot = RemoteLearningSessionSnapshot.fromJson({
        'session': {
          'id': 'learning-2',
          'exploreSessionId': 'explore-2',
          'topic': '旧客户端兼容',
          'scenarioId': 'prestudy',
          'atomId': null,
          'status': 'ACTIVE',
          'revision': 1,
          'nodeCount': 0,
          'startedAt': '2026-08-17T09:00:00.000Z',
          'expiresAt': '2099-08-17T09:00:00.000Z',
          'completedAt': null,
        },
        'currentNodeId': null,
        'activeStrategy': null,
        'nodes': const <Map<String, Object?>>[],
        'materials': const <Map<String, Object?>>[],
      });
      expect(snapshot.processSchedulerState, isNull);
    });
  });

  group('RemoteExplorationSessionController.selectTeachingMode', () {
    test(
      'rejects skills that are not part of the current mode menu snapshot',
      () async {
        final gateway = _ModeSelectionFakeGateway();
        final controller = RemoteExplorationSessionController(api: gateway);
        gateway.snapshotToReturn = _modeSelectionSnapshot(
          options: [_option('MORE_EXAMPLES', '多看几个例子')],
        );
        await controller.selectChapter('chapter-1');
        await controller.startFromChapterNode(
          _ModeSelectionFakeGateway.chapterNodeId,
        );
        expect(
          controller.state.snapshot?.processSchedulerState?.currentPhase,
          RemoteTeachingPhase.modeSelection,
        );

        await expectLater(
          controller.selectTeachingMode('VIDEO'),
          throwsA(isA<ArgumentError>()),
        );
        expect(gateway.selectSkillCalls, isEmpty);
        expect(
          controller.state.snapshot?.processSchedulerState?.currentPhase,
          RemoteTeachingPhase.modeSelection,
        );
      },
    );

    test('rejects selection when phase is not MODE_SELECTION', () async {
      final gateway = _ModeSelectionFakeGateway();
      final controller = RemoteExplorationSessionController(api: gateway);
      gateway.snapshotToReturn = _modeSelectionSnapshot(
        options: [_option('MORE_EXAMPLES', '多看几个例子')],
        phase: RemoteTeachingPhase.example,
      );
      await controller.selectChapter('chapter-1');
      await controller.startFromChapterNode(
        _ModeSelectionFakeGateway.chapterNodeId,
      );
      await expectLater(
        controller.selectTeachingMode('MORE_EXAMPLES'),
        throwsA(isA<StateError>()),
      );
      expect(gateway.selectSkillCalls, isEmpty);
    });

    test(
      'forwards allowed skill and swaps snapshot with server response',
      () async {
        final gateway = _ModeSelectionFakeGateway();
        final controller = RemoteExplorationSessionController(api: gateway);
        gateway.snapshotToReturn = _modeSelectionSnapshot(
          options: [
            _option('MORE_EXAMPLES', '多看几个例子'),
            _option('VIDEO', '看一个视频'),
          ],
        );
        await controller.selectChapter('chapter-1');
        await controller.startFromChapterNode(
          _ModeSelectionFakeGateway.chapterNodeId,
        );

        gateway.snapshotToReturn = _exampleSnapshot(selectedSkill: 'VIDEO');
        await controller.selectTeachingMode('VIDEO');

        expect(gateway.selectSkillCalls, ['VIDEO']);
        expect(controller.state.status, RemoteExplorationStatus.active);
        expect(
          controller.state.snapshot?.processSchedulerState?.currentPhase,
          RemoteTeachingPhase.example,
        );
        expect(
          controller.state.snapshot?.processSchedulerState?.selectedSkill,
          'VIDEO',
        );
      },
    );

    test('exposes retry action when server refuses selection', () async {
      final gateway = _ModeSelectionFakeGateway();
      final controller = RemoteExplorationSessionController(api: gateway);
      gateway.snapshotToReturn = _modeSelectionSnapshot(
        options: [_option('MORE_EXAMPLES', '多看几个例子')],
      );
      await controller.selectChapter('chapter-1');
      await controller.startFromChapterNode(
        _ModeSelectionFakeGateway.chapterNodeId,
      );

      gateway.failNextSelectMode = true;
      await controller.selectTeachingMode('MORE_EXAMPLES');
      expect(controller.state.status, RemoteExplorationStatus.failed);
      expect(controller.state.canRetry, isTrue);
      expect(gateway.selectSkillCalls, ['MORE_EXAMPLES']);
    });
  });

  testWidgets('lesson map separates opening and expands only selected goal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const entries = [
      TeachingModeHistoryEntry(
        label: '寒暄 · 了解基础',
        kind: 'OPENING',
        isCompleted: true,
      ),
      TeachingModeHistoryEntry(
        label: '学习方式',
        kind: 'MODE_SELECTION',
        isCompleted: true,
      ),
      TeachingModeHistoryEntry(
        label: 'G1 · 集合定义与三大特性',
        kind: 'GOAL',
        isGoalHeader: true,
        goalStatus: 'completed',
      ),
      TeachingModeHistoryEntry(
        label: '概念：∈ / ∉ 与三大特性',
        boardId: 'g1-concept',
        kind: 'CONCEPT',
        depth: 1,
        isCompleted: true,
      ),
      TeachingModeHistoryEntry(
        label: '例子：集合与元素',
        boardId: 'g1-example',
        kind: 'EXAMPLE',
        depth: 2,
        isCompleted: true,
      ),
      TeachingModeHistoryEntry(
        label: '练习：无序性判断',
        boardId: 'g1-check',
        kind: 'CHECK',
        depth: 1,
        isCompleted: true,
      ),
      TeachingModeHistoryEntry(
        label: '老师帮助 #1',
        boardId: 'g1-help',
        kind: 'SUPPORT_BRANCH',
        depth: 2,
        isCompleted: true,
      ),
      TeachingModeHistoryEntry(
        label: 'G2 · 列举法与描述法',
        kind: 'GOAL',
        isGoalHeader: true,
        goalStatus: 'ongoing',
      ),
      TeachingModeHistoryEntry(
        label: '概念：两种表示法',
        boardId: 'g2-concept',
        kind: 'CONCEPT',
        depth: 1,
        isCompleted: true,
      ),
      TeachingModeHistoryEntry(
        label: '练习：列举法',
        boardId: 'g2-check',
        kind: 'CHECK',
        depth: 1,
        isActive: true,
      ),
      TeachingModeHistoryEntry(
        label: 'G3 · 集合之间的关系',
        kind: 'GOAL',
        isGoalHeader: true,
        goalStatus: 'pending',
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ModeSelectionSidebar(entries: entries, mobile: false),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(find.text('本节课'), findsOneWidget);
    expect(find.text('历史记录'), findsNothing);
    expect(find.text('开场'), findsOneWidget);
    expect(find.text('寒暄 · 了解基础'), findsOneWidget);
    expect(find.text('当前学习'), findsOneWidget);
    expect(find.text('练习：列举法'), findsOneWidget);
    expect(find.text('概念：∈ / ∉ 与三大特性'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('goal-header-G1 · 集合定义与三大特性')));
    await tester.pump();

    expect(find.text('概念：∈ / ∉ 与三大特性'), findsOneWidget);
    expect(find.text('例子：集合与元素'), findsOneWidget);
    expect(find.text('老师帮助 #1'), findsOneWidget);
    expect(find.text('练习：列举法'), findsNothing);
    expect(find.text('当前学习'), findsOneWidget);
  });

  testWidgets('switching historical boards resets conversation to the top', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var boardId = 'old-board';
    var messages = List<IntroChatMessage>.generate(
      18,
      (index) => IntroChatMessage.teacher('旧画板消息 ${index + 1}'),
    );
    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            refresh = setState;
            return TeachingModeSelectionStage(
              topicLabel: '集合',
              options: const [],
              submitting: false,
              onSelect: (_) {},
              mobile: false,
              messages: messages,
              selectedHistoryBoardId: boardId,
              boardPanelTitle: '历史画板',
              isReviewingHistory: true,
              showReplyBar: false,
            );
          },
        ),
      ),
    );

    final chatList = find.byType(ListView).last;
    await tester.drag(chatList, const Offset(0, -900));
    await tester.pump();

    refresh(() {
      boardId = 'new-board';
      messages = [
        IntroChatMessage.teacher('新画板第一句'),
        IntroChatMessage.student('新画板第二句'),
        IntroChatMessage.teacher('新画板第三句'),
      ];
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('新画板第一句'), findsOneWidget);
    expect(find.text('新画板第二句'), findsOneWidget);
  });
}

RemoteTeachingModeOption _option(String skill, String label) {
  return RemoteTeachingModeOption(
    skill: skill,
    label: label,
    icon: '⭐',
    description: '$label 的描述',
  );
}

RemoteLearningSessionSnapshot _modeSelectionSnapshot({
  required List<RemoteTeachingModeOption> options,
  RemoteTeachingPhase phase = RemoteTeachingPhase.modeSelection,
}) {
  return RemoteLearningSessionSnapshot(
    session: const RemoteLearningSessionInfo(
      id: 'learning-1',
      exploreSessionId: 'explore-1',
      topic: '负数乘法',
      scenarioId: 'prestudy',
      atomId: 'negative-times-negative',
      status: 'ACTIVE',
      revision: 2,
      nodeCount: 1,
      startedAt: '2026-08-17T09:00:00.000Z',
      expiresAt: '2099-08-17T09:00:00.000Z',
      completedAt: null,
    ),
    currentNodeId: 'node-1',
    activeStrategy: null,
    nodes: const [
      RemoteLearningNode(
        id: 'node-1',
        parentId: null,
        status: 'VALIDATED',
        question: '为什么负负得正？',
        answer: '因为两次翻转方向',
        followUpQuestion: '',
        strategy: null,
        depth: 0,
        isSideBranch: false,
        backtrackTargetId: null,
        confidence: 0.7,
        createdAt: '2026-08-17T09:00:00.000Z',
      ),
    ],
    materials: const [],
    summary: null,
    processSchedulerState: RemoteProcessSchedulerState(
      schemaVersion: 1,
      lessonPlanId: 'plan-neg-times-neg',
      currentGoalIndex: 0,
      currentPhase: phase,
      goalStatuses: const [RemoteLessonGoalStatus.inProgress],
      modeMenuOptions: options,
      selectedSkill: null,
      extraSupportCount: 0,
      completedAt: null,
      updatedAt: '2026-08-17T09:00:00.000Z',
    ),
  );
}

RemoteLearningSessionSnapshot _exampleSnapshot({
  required String selectedSkill,
}) {
  return RemoteLearningSessionSnapshot(
    session: const RemoteLearningSessionInfo(
      id: 'learning-1',
      exploreSessionId: 'explore-1',
      topic: '负数乘法',
      scenarioId: 'prestudy',
      atomId: 'negative-times-negative',
      status: 'ACTIVE',
      revision: 3,
      nodeCount: 1,
      startedAt: '2026-08-17T09:00:00.000Z',
      expiresAt: '2099-08-17T09:00:00.000Z',
      completedAt: null,
    ),
    currentNodeId: 'node-1',
    activeStrategy: null,
    nodes: const [
      RemoteLearningNode(
        id: 'node-1',
        parentId: null,
        status: 'VALIDATED',
        question: '为什么负负得正？',
        answer: '因为两次翻转方向',
        followUpQuestion: '',
        strategy: null,
        depth: 0,
        isSideBranch: false,
        backtrackTargetId: null,
        confidence: 0.7,
        createdAt: '2026-08-17T09:00:00.000Z',
      ),
    ],
    materials: const [],
    summary: null,
    processSchedulerState: RemoteProcessSchedulerState(
      schemaVersion: 1,
      lessonPlanId: 'plan-neg-times-neg',
      currentGoalIndex: 0,
      currentPhase: RemoteTeachingPhase.example,
      goalStatuses: const [RemoteLessonGoalStatus.inProgress],
      modeMenuOptions: null,
      selectedSkill: selectedSkill,
      extraSupportCount: 0,
      completedAt: null,
      updatedAt: '2026-08-17T09:05:00.000Z',
    ),
  );
}

final class _ModeSelectionFakeGateway implements RemoteExplorationGateway {
  static const chapterNodeId = 'concept-node';

  final List<String> selectSkillCalls = [];
  bool failNextSelectMode = false;
  RemoteLearningSessionSnapshot? snapshotToReturn;

  final _chapter = LearningChapterOverviewSnapshot(
    chapterId: 'chapter-1',
    title: '负数乘法',
    description: '理解为什么负负得正',
    estimatedMinutes: 10,
    progress: 0,
    recommendedNodeId: chapterNodeId,
    phases: const [],
    nodes: const [
      LearningChapterNodeSnapshot(
        id: chapterNodeId,
        parentId: null,
        atomId: 'negative-times-negative',
        title: '负负得正',
        description: '',
        phase: 'LEARNING',
        hookQuestion: '为什么两个负数相乘得到正数？',
        recommended: true,
      ),
    ],
  );

  final _entry = LearningEntrySnapshot(
    atomId: 'negative-times-negative',
    title: '负数乘法',
    coreQuestion: '为什么负负得正？',
    estimatedMinutes: 8,
    recommendedDirectionId: 'default',
    directions: const [
      LearningDirectionSnapshot(
        id: 'default',
        title: '默认',
        description: '',
        hookQuestion: '',
      ),
    ],
  );

  @override
  Future<List<LearningChapterCatalogItem>> listChapterCatalog() async =>
      const [];

  @override
  Future<LearningChapterOverviewSnapshot> getChapterOverview(
    String chapterId,
  ) async => _chapter;

  @override
  Future<LearningEntrySnapshot> getEntry(String atomId) async => _entry;

  @override
  Future<RemoteLearningSessionSnapshot> createSession({
    String? atomId,
    required String scenarioId,
    String? directionId,
    String? question,
    String? idempotencyKey,
    RemoteFlowMode flowMode = RemoteFlowMode.openExploration,
    RemoteSessionEntryMode? entryMode,
  }) async {
    return snapshotToReturn ?? (throw StateError('测试未设置 snapshotToReturn'));
  }

  @override
  Future<RemoteLearningSessionSnapshot?> restoreLatest() async => null;

  @override
  Future<List<RemoteLearningSessionSummary>> listSessions() async => const [];

  @override
  Future<RemoteLearningSessionSnapshot> restoreSession(
    RemoteLearningSessionSummary summary,
  ) async => snapshotToReturn!;

  @override
  Future<RemoteLearningSessionSnapshot> submitTurn({
    required String sessionId,
    required String question,
    String? parentNodeId,
    String? idempotencyKey,
  }) async => snapshotToReturn!;

  @override
  Future<RemoteLearningSessionSnapshot> createBranch({
    required String sessionId,
    required String parentNodeId,
    required String question,
    String? idempotencyKey,
  }) async => snapshotToReturn!;

  @override
  Future<RemoteLearningSessionSnapshot> backtrack({
    required String sessionId,
    required String targetNodeId,
    String? idempotencyKey,
  }) async => snapshotToReturn!;

  @override
  Future<Map<String, Object?>> createMemoryCandidate({
    required String sessionId,
    required String nodeId,
    String? idempotencyKey,
  }) async => const {'id': 'memory-1'};

  @override
  Future<RemoteLearningSessionSnapshot> complete({
    required String sessionId,
    required String reflection,
    String? idempotencyKey,
  }) async => snapshotToReturn!;

  @override
  Future<RemoteLearningSessionSnapshot> submitPracticeAttempt({
    required String sessionId,
    required String practiceId,
    required String reasoning,
    required String answer,
    String? idempotencyKey,
  }) async => snapshotToReturn!;

  @override
  Future<RemoteLearningSessionSnapshot> submitMaterialEvent({
    required String sessionId,
    required String materialUsageId,
    required RemoteAssetEvent event,
    String? idempotencyKey,
  }) async => snapshotToReturn!;

  @override
  Future<String> exportTree(String sessionId) async => '{}';

  @override
  Future<RemoteTeachingModeOptionsSnapshot> getTeachingModeOptions({
    required String sessionId,
  }) async {
    return RemoteTeachingModeOptionsSnapshot(
      phase: RemoteTeachingPhase.modeSelection,
      currentGoalIndex: 0,
      options: snapshotToReturn?.processSchedulerState?.modeMenuOptions,
    );
  }

  @override
  Future<RemoteLearningSessionSnapshot> selectTeachingMode({
    required String sessionId,
    required String skill,
    String? idempotencyKey,
  }) async {
    selectSkillCalls.add(skill);
    if (failNextSelectMode) {
      failNextSelectMode = false;
      throw const RemoteExplorationException('模式不在当前目标可选范围');
    }
    return snapshotToReturn!;
  }
}

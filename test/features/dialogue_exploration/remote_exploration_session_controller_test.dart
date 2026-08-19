import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/core/remote_exploration_session_controller.dart';

void main() {
  test(
    'catalog API unwraps one array envelope and filters malformed items',
    () async {
      var requestCount = 0;
      final api = RemoteExplorationApi(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          requestCount += 1;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/learning-chapters');
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': [
                {
                  'chapterId': 'integer-operations',
                  'title': '整数运算',
                  'description': '巩固整数运算规则',
                  'estimatedMinutes': 20,
                  'availableNodeCount': 4,
                },
                {'chapterId': ''},
                'malformed',
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final catalog = await api.listChapterCatalog();

      expect(requestCount, 1);
      expect(catalog, hasLength(1));
      expect(catalog.single.chapterId, 'integer-operations');
      expect(catalog.single.title, '整数运算');
      expect(catalog.single.description, '巩固整数运算规则');
      expect(catalog.single.estimatedMinutes, 20);
      expect(catalog.single.availableNodeCount, 4);
    },
  );

  test(
    'catalog API maps successful envelope data shape errors to stable remote errors',
    () async {
      var requestCount = 0;
      final api = RemoteExplorationApi(
        baseUrl: 'https://example.test',
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {'items': []},
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await expectLater(
        api.listChapterCatalog(),
        throwsA(
          isA<RemoteExplorationException>().having(
            (error) => error.message,
            'message',
            '服务端返回格式不正确。',
          ),
        ),
      );
      expect(requestCount, 1);
    },
  );

  test(
    'catalog API preserves envelope, HTTP and malformed JSON error contracts',
    () async {
      final responses = <http.Response>[
        http.Response(
          jsonEncode({
            'ok': false,
            'error': {'message': '拒绝访问'},
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
        http.Response(
          jsonEncode({'message': '服务故障'}),
          503,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
        http.Response('{', 200),
      ];
      final api = RemoteExplorationApi(
        baseUrl: 'https://example.test',
        client: MockClient((_) async => responses.removeAt(0)),
      );

      await expectLater(
        api.listChapterCatalog(),
        throwsA(
          isA<RemoteExplorationException>().having(
            (error) => error.message,
            'message',
            '拒绝访问',
          ),
        ),
      );
      await expectLater(
        api.listChapterCatalog(),
        throwsA(isA<RemoteExplorationException>()),
      );
      await expectLater(
        api.listChapterCatalog(),
        throwsA(
          isA<RemoteExplorationException>().having(
            (error) => error.message,
            'message',
            '服务端返回格式不正确。',
          ),
        ),
      );
    },
  );

  test(
    'V2 teaching flow exposes diagnostic, practice and next-learning data',
    () {
      final dynamic flow = RemoteTeachingFlow.fromJson({
        'schemaVersion': 2,
        'mode': 'GUIDED_LESSON',
        'stage': 'FOCUS',
        'lessonPlanId': 'negative-sign-guided-v2',
        'atomId': 'negative-times-negative',
        'goal': '解释为什么负负得正',
        'practiceId': 'legacy-practice',
        'currentAction': const {
          'schemaVersion': 2,
          'type': 'REQUEST_MICRO_CHECK',
          'prompt': '请作答',
          'pedagogicalIntent': 'VERIFY',
          'reasonCode': 'READY',
          'practiceId': 'legacy-practice',
        },
        'evidence': const {
          'schemaVersion': 2,
          'requiredCodes': [],
          'items': [],
          'missingCodes': [],
          'isReadyForMicroCheck': true,
        },
        'hintLevel': 1,
        'updatedAt': '2026-08-11T10:00:00.000Z',
        'diagnosticLevel': 'READY_FOR_CHECK',
        'diagnosticRound': 2,
        'learningLayer': 'TRANSFER',
        'explorationAct': 'SYNTHESIZE_DISCOVERY',
        'hypothesis': '连续两次取相反数会回到原数。',
        'attemptRound': 3,
        'supportLevel': 1,
        'activePractice': const {
          'id': 'sign-check',
          'title': '符号判断',
          'prompt': '负数乘负数是什么？',
          'reasoningLabel': '推理过程',
          'answerLabel': '答案',
        },
        'practiceVariants': const [
          {
            'id': 'sign-check-variant',
            'title': '变式',
            'prompt': '再判断一次',
            'reasoningLabel': '推理',
            'answerLabel': '答案',
          },
          'malformed',
        ],
        'feedback': '符号方向正确',
        'repairFocus': '解释两次反向',
        'nextLearningOptions': const [
          {
            'atomId': 'integer-division',
            'chapterId': 'integer-operations',
            'title': '整数除法',
            'relation': 'NEXT',
            'difficultyReason': '巩固符号规则',
            'estimatedMinutes': 8,
            'hookQuestion': '除法的符号怎样判断？',
            'prerequisitesSatisfied': true,
          },
          {'atomId': ''},
        ],
      });

      expect(flow.schemaVersion, 2);
      expect(flow.diagnosticLevel, RemoteDiagnosticLevel.readyForCheck);
      expect(flow.diagnosticRound, 2);
      expect(flow.learningLayer, RemoteGuidedLearningLayer.transfer);
      expect(
        flow.explorationAct,
        RemoteGuidedExplorationAct.synthesizeDiscovery,
      );
      expect(flow.hypothesis, '连续两次取相反数会回到原数。');
      expect(flow.attemptRound, 3);
      expect(flow.supportLevel, 1);
      expect(flow.activePractice.id, 'sign-check');
      expect(flow.activePractice.title, '符号判断');
      expect(flow.activePractice.prompt, '负数乘负数是什么？');
      expect(flow.activePractice.reasoningLabel, '推理过程');
      expect(flow.activePractice.answerLabel, '答案');
      expect(flow.practiceVariants, hasLength(1));
      expect(flow.feedback, '符号方向正确');
      expect(flow.repairFocus, '解释两次反向');
      final next = flow.nextLearningOptions.single;
      expect(next.atomId, 'integer-division');
      expect(next.chapterId, 'integer-operations');
      expect(next.title, '整数除法');
      expect(next.relation, 'NEXT');
      expect(next.difficultyReason, '巩固符号规则');
      expect(next.estimatedMinutes, 8);
      expect(next.hookQuestion, '除法的符号怎样判断？');
      expect(next.prerequisitesSatisfied, isTrue);
      expect(flow.currentAction.practiceId, 'legacy-practice');
    },
  );

  test(
    'V2 teaching flow parses a failed transfer as an exploration revisit',
    () {
      expect(
        RemoteGuidedExplorationAct.fromWire('TRANSFER_REVISIT'),
        RemoteGuidedExplorationAct.transferRevisit,
      );
    },
  );

  test('V1 teaching flow keeps legacy action while defaulting V2 fields', () {
    final dynamic flow = RemoteTeachingFlow.fromJson({
      'schemaVersion': 1,
      'stage': 'DIALOGUE',
      'lessonPlanId': 'legacy',
      'atomId': 'quadratic-function',
      'goal': '旧会话',
      'practiceId': 'legacy-practice',
      'currentAction': const {
        'schemaVersion': 1,
        'type': 'ASK_QUESTION',
        'prompt': '继续探索',
        'pedagogicalIntent': 'EXPLORE',
        'reasonCode': 'LEGACY',
        'practiceId': 'legacy-practice',
      },
      'evidence': const {
        'schemaVersion': 1,
        'requiredCodes': [],
        'items': [],
        'missingCodes': [],
        'isReadyForMicroCheck': false,
      },
      'hintLevel': 0,
      'updatedAt': '2026-08-11T10:00:00.000Z',
    });

    expect(flow.diagnosticLevel, RemoteDiagnosticLevel.unknown);
    expect(flow.diagnosticRound, 0);
    expect(flow.learningLayer, RemoteGuidedLearningLayer.unknown);
    expect(flow.attemptRound, 0);
    expect(flow.supportLevel, 0);
    expect(flow.activePractice, isNull);
    expect(flow.practiceVariants, isEmpty);
    expect(flow.nextLearningOptions, isEmpty);
    expect(flow.feedback, isNull);
    expect(flow.repairFocus, isNull);
    expect(flow.currentAction.practiceId, 'legacy-practice');
  });

  test('V2 teaching flow ignores an incomplete active practice', () {
    final flow = RemoteTeachingFlow.fromJson({
      'schemaVersion': 2,
      'stage': 'FOCUS',
      'lessonPlanId': 'v2',
      'atomId': 'integer-operations',
      'goal': '检查容错',
      'practiceId': 'legacy',
      'currentAction': const {
        'schemaVersion': 2,
        'type': 'REQUEST_MICRO_CHECK',
        'prompt': '作答',
        'pedagogicalIntent': 'VERIFY',
        'reasonCode': 'READY',
      },
      'evidence': const {
        'schemaVersion': 2,
        'requiredCodes': [],
        'items': [],
        'missingCodes': [],
        'isReadyForMicroCheck': false,
      },
      'hintLevel': 0,
      'updatedAt': '2026-08-11T10:00:00.000Z',
      'activePractice': const {'id': 'incomplete'},
    });

    expect(flow.activePractice, isNull);
  });

  test(
    'catalog loading is retryable and selecting a chapter delegates to load',
    () async {
      final api = _FakeRemoteApi()..failNextCatalogLoad = true;
      final controller = RemoteExplorationSessionController(api: api);

      await (controller as dynamic).loadChapterCatalog();

      expect(controller.state.status, RemoteExplorationStatus.failed);
      expect(controller.state.canRetry, isTrue);

      await controller.retry();

      expect(
        (controller.state as dynamic).chapterCatalog.single.chapterId,
        'integer-operations',
      );
      await (controller as dynamic).selectChapter('negative-number-operations');
      expect(controller.state.chapter?.chapterId, 'negative-number-operations');
    },
  );

  test('locked next-learning option does not create a session', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteExplorationSessionController(api: api);

    await (controller as dynamic).startNextLearningOption(
      _nextLearningOption(prerequisitesSatisfied: false),
    );

    expect(api.getEntryCalls, 0);
    expect(api.createCalls, 0);
  });

  test('next-learning retry reuses its create idempotency key', () async {
    final api = _FakeRemoteApi()..failNextCreate = true;
    final controller = RemoteExplorationSessionController(api: api);

    await (controller as dynamic).startNextLearningOption(
      _nextLearningOption(prerequisitesSatisfied: true),
    );
    await controller.retry();

    expect(api.createIdempotencyKeys, hasLength(2));
    expect(api.createIdempotencyKeys.toSet(), hasLength(1));
    expect(api.lastAtomId, 'integer-division');
    expect(api.lastScenarioId, 'prestudy');
    expect(api.lastQuestion, '除法的符号怎样判断？');
    expect(api.lastFlowMode, RemoteFlowMode.guidedLesson);
  });

  test(
    'loads a whole chapter and selects its recommended knowledge node',
    () async {
      final api = _FakeRemoteApi();
      final controller = RemoteExplorationSessionController(api: api);

      await controller.loadChapter('negative-number-operations');

      expect(controller.state.chapter?.title, '负数运算');
      expect(controller.state.chapter?.phases.map((phase) => phase.kind), [
        'LEARNING',
        'PRACTICE',
        'REVIEW',
      ]);
      expect(
        controller.state.selectedChapterNodeId,
        'negative-times-negative-concept',
      );
    },
  );

  test(
    'chapter node selection is read-only and can explicitly start its hook question',
    () async {
      final api = _FakeRemoteApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadChapter('negative-number-operations');

      controller.selectChapterNode('opposite-number');

      expect(api.createCalls, 0);
      expect(controller.state.selectedChapterNodeId, 'opposite-number');

      await controller.startFromChapterNode('opposite-number');

      expect(api.createCalls, 1);
      expect(api.lastAtomId, 'negative-times-negative');
      expect(api.lastScenarioId, 'prestudy');
      expect(api.lastFlowMode, RemoteFlowMode.guidedLesson);
      expect(api.lastQuestion, '连续两次取相反数，方向为什么会回到原处？');
    },
  );

  test(
    'free questions always create a pre-study exploration session',
    () async {
      final api = _FakeRemoteApi();
      final controller = RemoteExplorationSessionController(api: api);

      await controller.startFreeQuestion('为什么两个负数相乘会得到正数？');

      expect(api.createCalls, 1);
      expect(api.lastScenarioId, 'prestudy');
      expect(api.lastFlowMode, RemoteFlowMode.openExploration);
      expect(api.lastQuestion, '为什么两个负数相乘会得到正数？');
    },
  );

  test(
    'a free expression inside a chapter keeps the selected node guided flow',
    () async {
      final api = _FakeRemoteApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadChapter('negative-number-operations');
      controller.selectChapterNode('opposite-number');

      await controller.startFreeQuestion('我想弄懂为什么两个负数相乘会得到正数');

      expect(api.createCalls, 1);
      expect(api.lastAtomId, 'negative-times-negative');
      expect(api.lastFlowMode, RemoteFlowMode.guidedLesson);
      expect(api.lastQuestion, '我想弄懂为什么两个负数相乘会得到正数');
    },
  );

  test('loads entry and creates the first server session', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteExplorationSessionController(api: api);

    await controller.loadEntry('quadratic-function');
    await controller.start(directionId: 'graph-secret');

    expect(controller.state.entry?.title, '二次函数探索');
    expect(controller.state.status, RemoteExplorationStatus.active);
    expect(controller.state.snapshot?.nodes.single.question, '二次函数的顶点为什么在这里？');
    expect(api.createCalls, 1);
    expect(api.lastFlowMode, RemoteFlowMode.guidedLesson);
  });

  test('guided flow DTO tolerates optional fields and preserves evidence', () {
    final flow = RemoteTeachingFlow.fromJson({
      'schemaVersion': 1,
      'mode': 'GUIDED_LESSON',
      'stage': 'FOCUS',
      'lessonPlanId': 'negative-sign-guided-v1',
      'atomId': 'negative-times-negative',
      'goal': '解释为什么负负得正',
      'practiceId': 'negative-sign-prediction',
      'currentAction': {
        'schemaVersion': 1,
        'type': 'REQUEST_MICRO_CHECK',
        'prompt': '请独立解释',
        'pedagogicalIntent': 'VERIFY_INDEPENDENT_UNDERSTANDING',
        'reasonCode': 'GUIDED_MICRO_CHECK_READY',
        'practiceId': 'negative-sign-prediction',
      },
      'evidence': {
        'schemaVersion': 1,
        'requiredCodes': ['operation-observed'],
        'items': [
          {
            'code': 'operation-observed',
            'strength': 'OBSERVED',
            'sourceType': 'ASSET_EVENT',
            'sourceId': 'event-1',
            'recordedAt': '2026-08-10T10:00:00.000Z',
          },
        ],
        'missingCodes': [],
        'isReadyForMicroCheck': true,
      },
      'hintLevel': 0,
      'updatedAt': '2026-08-10T10:00:00.000Z',
    });

    expect(flow.stage, RemoteTeachingStage.focus);
    expect(flow.currentAction.practiceId, 'negative-sign-prediction');
    expect(
      flow.evidence.items.single.strength,
      RemoteEvidenceStrength.observed,
    );
  });

  test('material event retry reuses the same client event id', () async {
    final api = _FakeRemoteApi()..failNextMaterialEvent = true;
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start();

    await controller.submitMaterialEvent(
      materialUsageId: 'material-usage-1',
      eventType: 'completed',
      payload: const {'completed': true},
    );
    final firstEventId = api.materialEventIds.single;

    expect(controller.state.canRetry, isTrue);
    await controller.retry();

    expect(api.materialEventIds, [firstEventId, firstEventId]);
    expect(controller.state.status, RemoteExplorationStatus.active);
  });

  test(
    'guided practice uses the active server practice id instead of the action hint',
    () async {
      final api = _FakeRemoteApi()
        ..teachingFlow = _guidedFocusFlow(
          actionPracticeId: 'stale-action-practice',
          activePractice: const RemoteGuidedPractice(
            id: 'active-server-practice',
            title: '服务端题目',
            prompt: '请解释两次翻转后的方向。',
            reasoningLabel: '推理过程',
            answerLabel: '最终答案',
          ),
        );
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start();

      await controller.submitGuidedPractice(
        reasoning: '连续翻转两次会回到原方向',
        answer: '正数',
      );

      expect(api.practiceCalls, 1);
      expect(api.lastPracticeId, 'active-server-practice');
    },
  );

  test(
    'guided practice without an active server practice does not request',
    () async {
      final api = _FakeRemoteApi()..teachingFlow = _guidedFocusFlow();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start();

      await expectLater(
        controller.submitGuidedPractice(reasoning: '有推理', answer: '有答案'),
        throwsA(isA<StateError>()),
      );

      expect(api.practiceCalls, 0);
    },
  );

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

  test(
    'loads account history and opens a completed session read-only',
    () async {
      final api = _FakeRemoteApi();
      final controller = RemoteExplorationSessionController(api: api);

      await controller.loadHistory();

      expect(controller.state.history.map((item) => item.id), ['learning-old']);

      await controller.openHistorySession('learning-old');

      expect(controller.state.snapshot?.session.id, 'learning-1');
      expect(controller.state.status, RemoteExplorationStatus.completed);
      expect(controller.state.isReadOnly, isTrue);
    },
  );

  test(
    'restores the latest continuable account session during initialization',
    () async {
      final api = _FakeRemoteApi()
        ..history = const [
          RemoteLearningSessionSummary(
            id: 'learning-active',
            exploreSessionId: 'explore-1',
            topic: '继续预习',
            scenarioId: 'prestudy',
            atomId: 'quadratic-function',
            status: 'ACTIVE',
            nodeCount: 2,
            startedAt: '2026-08-09T01:00:00.000Z',
            expiresAt: '2099-08-09T01:10:00.000Z',
            completedAt: null,
            lastActiveAt: '2026-08-09T01:05:00.000Z',
          ),
        ];
      final controller = RemoteExplorationSessionController(api: api);

      await controller.loadHistory(restoreLatestActive: true);

      expect(controller.state.snapshot, isNotNull);
      expect(controller.state.status, RemoteExplorationStatus.active);
      expect(controller.state.isReadOnly, isFalse);
    },
  );

  test('opens an expired active history session read-only', () async {
    final api = _FakeRemoteApi()
      ..history = const [
        RemoteLearningSessionSummary(
          id: 'learning-expired',
          exploreSessionId: 'explore-1',
          topic: '已过期预习',
          scenarioId: 'prestudy',
          atomId: 'quadratic-function',
          status: 'ACTIVE',
          nodeCount: 2,
          startedAt: '2026-08-05T01:00:00.000Z',
          expiresAt: '2026-08-05T01:10:00.000Z',
          completedAt: null,
          lastActiveAt: '2026-08-05T01:05:00.000Z',
        ),
      ];
    final controller = RemoteExplorationSessionController(api: api);

    await controller.loadHistory();
    await controller.openHistorySession('learning-expired');

    expect(controller.state.isReadOnly, isTrue);
    await expectLater(
      controller.submitQuestion('不能继续写入'),
      throwsA(isA<StateError>()),
    );
    controller.inspectNode('node-1');
    expect(controller.prepareBranchFromInspected, throwsA(isA<StateError>()));
  });

  test('snapshot parses dynamic course state and capabilities', () {
    final snapshot = RemoteLearningSessionSnapshot.fromJson({
      'session': {
        'id': 'learning-1',
        'exploreSessionId': 'explore-1',
        'topic': '化学方程式配平',
        'scenarioId': 'prestudy',
        'status': 'ACTIVE',
        'revision': 2,
        'nodeCount': 1,
        'startedAt': '2026-08-18T01:00:00.000Z',
        'expiresAt': '2026-08-18T02:00:00.000Z',
      },
      'nodes': const [],
      'materials': const [],
      'courseState': {
        'currentStage': 'UNDERSTANDING_CHECK',
        'currentGoal': 'G1',
        'currentGoalIndex': 0,
        'supportCount': 1,
        'completionStatus': 'IN_PROGRESS',
        'timeBudget': {
          'totalMinutes': 35,
          'elapsedMinutes': 20,
          'remainingMinutes': 15,
          'policy': 'NORMAL',
        },
      },
      'teacherDecision': {
        'action': 'REPEAT',
        'reasonCode': 'PARTIAL_NEEDS_VARIANT',
        'reason': '部分掌握，提供变式',
        'decidedAt': '2026-08-18T01:20:00.000Z',
      },
      'allowedActions': ['SUBMIT_PRACTICE'],
      'capabilities': {
        'canSubmitText': false,
        'canSelectMode': false,
        'canSubmitMaterial': false,
        'canSkipMaterial': false,
        'canSwitchMaterial': false,
        'canSubmitPractice': true,
        'canComplete': false,
      },
    });

    expect(snapshot.courseState?.timeBudget?.remainingMinutes, 15);
    expect(snapshot.teacherDecision?.action, 'REPEAT');
    expect(snapshot.capabilities?.canSubmitPractice, isTrue);
    expect(snapshot.allows('SUBMIT_PRACTICE'), isTrue);
  });
}

final class _FakeRemoteApi implements RemoteExplorationGateway {
  int createCalls = 0;
  int getEntryCalls = 0;
  int turnCalls = 0;
  int branchCalls = 0;
  int backtrackCalls = 0;
  int memoryCalls = 0;
  int completeCalls = 0;
  int practiceCalls = 0;
  String? lastParentNodeId;
  String? lastAtomId;
  String? lastScenarioId;
  String? lastQuestion;
  String? lastPracticeId;
  RemoteFlowMode? lastFlowMode;
  bool failNextTurn = false;
  bool failNextMaterialEvent = false;
  bool failNextCatalogLoad = false;
  bool failNextCreate = false;
  final List<String> materialEventIds = [];
  final List<String?> createIdempotencyKeys = [];
  RemoteTeachingFlow? teachingFlow = _guidedAssetFlow();

  List<RemoteLearningSessionSummary> history = const [
    RemoteLearningSessionSummary(
      id: 'learning-old',
      exploreSessionId: 'explore-1',
      topic: '历史预习',
      scenarioId: 'prestudy',
      atomId: 'quadratic-function',
      status: 'COMPLETED',
      nodeCount: 3,
      startedAt: '2026-08-05T01:00:00.000Z',
      expiresAt: '2026-08-05T01:10:00.000Z',
      completedAt: '2026-08-05T01:08:00.000Z',
      lastActiveAt: '2026-08-05T01:08:00.000Z',
    ),
  ];

  final chapter = LearningChapterOverviewSnapshot(
    chapterId: 'negative-number-operations',
    title: '负数运算',
    description: '理解负数的意义和运算规则。',
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
        itemCount: 3,
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
        summary: '复习易错点',
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
        description: '理解两次方向翻转。',
        phase: 'LEARNING',
        hookQuestion: '连续两次取相反数，方向为什么会回到原处？',
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

  @override
  Future<List<LearningChapterCatalogItem>> listChapterCatalog() async {
    if (failNextCatalogLoad) {
      failNextCatalogLoad = false;
      throw const RemoteExplorationException('目录加载失败');
    }
    return const [
      LearningChapterCatalogItem(
        chapterId: 'integer-operations',
        title: '整数运算',
        description: '巩固整数运算规则',
        estimatedMinutes: 20,
        availableNodeCount: 4,
      ),
    ];
  }

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
      expiresAt: '2099-08-06T01:10:00.000Z',
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
    teachingFlow: teachingFlow,
  );

  @override
  Future<LearningEntrySnapshot> getEntry(String atomId) async {
    getEntryCalls += 1;
    return entry;
  }

  @override
  Future<LearningChapterOverviewSnapshot> getChapterOverview(
    String chapterId,
  ) async => chapter;

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
    createCalls += 1;
    createIdempotencyKeys.add(idempotencyKey);
    if (failNextCreate) {
      failNextCreate = false;
      throw const RemoteExplorationException('创建会话失败');
    }
    lastAtomId = atomId;
    lastScenarioId = scenarioId;
    lastQuestion = question;
    lastFlowMode = flowMode;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot?> restoreLatest() async => null;

  @override
  Future<List<RemoteLearningSessionSummary>> listSessions() async => history;

  @override
  Future<RemoteLearningSessionSnapshot> restoreSession(
    RemoteLearningSessionSummary summary,
  ) async {
    return RemoteLearningSessionSnapshot(
      session: snapshot.session.copyWith(
        status: summary.status,
        expiresAt: summary.expiresAt,
      ),
      currentNodeId: snapshot.currentNodeId,
      activeStrategy: snapshot.activeStrategy,
      nodes: snapshot.nodes,
      materials: snapshot.materials,
      summary: snapshot.summary,
    );
  }

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
  Future<RemoteLearningSessionSnapshot> submitPracticeAttempt({
    required String sessionId,
    required String practiceId,
    required String reasoning,
    required String answer,
    String? idempotencyKey,
  }) async {
    practiceCalls += 1;
    lastPracticeId = practiceId;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot> submitMaterialEvent({
    required String sessionId,
    required String materialUsageId,
    required RemoteAssetEvent event,
    String? idempotencyKey,
  }) async {
    materialEventIds.add(event.eventId);
    if (failNextMaterialEvent) {
      failNextMaterialEvent = false;
      throw const RemoteExplorationException('素材事件提交失败');
    }
    return snapshot;
  }

  @override
  Future<String> exportTree(String sessionId) async => '{"schemaVersion":1}';

  @override
  Future<RemoteTeachingModeOptionsSnapshot> getTeachingModeOptions({
    required String sessionId,
  }) async {
    return RemoteTeachingModeOptionsSnapshot(
      phase: RemoteTeachingPhase.unknown,
      currentGoalIndex: 0,
      options: null,
    );
  }

  @override
  Future<RemoteLearningSessionSnapshot> selectTeachingMode({
    required String sessionId,
    required String skill,
    String? idempotencyKey,
  }) async {
    return snapshot;
  }
}

RemoteNextLearningOption _nextLearningOption({
  required bool prerequisitesSatisfied,
}) => RemoteNextLearningOption(
  atomId: 'integer-division',
  chapterId: 'integer-operations',
  title: '整数除法',
  relation: 'NEXT',
  difficultyReason: '巩固符号规则',
  estimatedMinutes: 8,
  hookQuestion: '除法的符号怎样判断？',
  prerequisitesSatisfied: prerequisitesSatisfied,
);

RemoteTeachingFlow _guidedAssetFlow() => _guidedFlow(
  stage: RemoteTeachingStage.asset,
  actionType: 'SHOW_ASSET',
  materialUsageId: 'material-usage-1',
);

RemoteTeachingFlow _guidedFocusFlow({
  String? actionPracticeId,
  RemoteGuidedPractice? activePractice,
}) => _guidedFlow(
  stage: RemoteTeachingStage.focus,
  actionType: 'REQUEST_MICRO_CHECK',
  practiceId: actionPracticeId ?? 'negative-sign-prediction',
  activePractice: activePractice,
);

RemoteTeachingFlow _guidedFlow({
  required RemoteTeachingStage stage,
  required String actionType,
  String? materialUsageId,
  String? practiceId,
  RemoteGuidedPractice? activePractice,
}) {
  return RemoteTeachingFlow(
    schemaVersion: 1,
    stage: stage,
    lessonPlanId: 'negative-sign-guided-v1',
    atomId: 'negative-times-negative',
    goal: '解释为什么负负得正',
    practiceId: 'negative-sign-prediction',
    currentAction: RemoteTeacherAction(
      schemaVersion: 1,
      type: actionType,
      prompt: '完成当前步骤',
      pedagogicalIntent: 'VERIFY_INDEPENDENT_UNDERSTANDING',
      reasonCode: 'GUIDED_MICRO_CHECK_READY',
      materialUsageId: materialUsageId,
      practiceId: practiceId,
    ),
    evidence: const RemoteEvidenceState(
      schemaVersion: 1,
      requiredCodes: ['operation-observed'],
      items: [],
      missingCodes: ['operation-observed'],
      isReadyForMicroCheck: false,
    ),
    hintLevel: 0,
    updatedAt: '2026-08-10T10:00:00.000Z',
    activePractice: activePractice,
  );
}

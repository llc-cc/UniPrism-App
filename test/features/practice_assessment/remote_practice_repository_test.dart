import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/practice_assessment.dart';

void main() {
  test('映射不含答案和 rubric 的远程试卷并保存匿名令牌', () async {
    final tokenStore = MemoryPracticeParticipantTokenStore();
    final repository = RemotePracticeRepository(
      api: PracticeApiClient(
        baseUrl: 'http://localhost:3000',
        participantTokenStore: tokenStore,
        client: MockClient((request) async {
          expect(request.url.path, '/api/practice/sessions');
          return http.Response(
            jsonEncode(_sessionEnvelope(participantToken: 'participant-token')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final snapshot = await repository.loadOrCreateSession();

    expect(snapshot.paper.questions, hasLength(1));
    expect(snapshot.paper.contentVersion, 'demo-v1');
    expect(snapshot.paper.questions.single.rubric, isNull);
    expect(await tokenStore.read(), 'participant-token');
  });

  test('远程失败返回 request id 且不会切换到 mock', () async {
    final repository = RemotePracticeRepository(
      api: PracticeApiClient(
        baseUrl: 'http://localhost:3000',
        participantTokenStore: MemoryPracticeParticipantTokenStore(),
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'ok': false,
              'error': {
                'code': 'SERVICE_UNAVAILABLE',
                'message': '服务暂不可用',
                'requestId': 'req_test',
              },
            }),
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await expectLater(
      repository.loadOrCreateSession(),
      throwsA(
        isA<PracticeApiException>().having(
          (error) => error.requestId,
          'requestId',
          'req_test',
        ),
      ),
    );
  });

  test('原生绑定同时发送登录 Bearer 与匿名令牌并在成功后清除令牌', () async {
    final tokenStore = MemoryPracticeParticipantTokenStore('participant-token');
    final repository = RemotePracticeRepository(
      api: PracticeApiClient(
        baseUrl: 'http://localhost:3000',
        participantTokenStore: tokenStore,
        bearerTokenProvider: () async => 'user-token',
        client: MockClient((request) async {
          expect(request.url.path, '/api/practice/sessions/session-1/bind');
          expect(request.headers['authorization'], 'Bearer user-token');
          expect(
            request.headers['x-practice-participant-token'],
            'participant-token',
          );
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {'bound': true, 'sessionId': 'session-1'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await repository.bindCurrentSession('session-1');

    expect(await tokenStore.read(), isNull);
  });

  test('读取跨设备能力画像时只映射学生可见字段', () async {
    final repository = RemotePracticeRepository(
      api: PracticeApiClient(
        baseUrl: 'http://localhost:3000',
        participantTokenStore: MemoryPracticeParticipantTokenStore(),
        bearerTokenProvider: () async => 'user-token',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'profiles': [
                  {
                    'dimension': 'READING',
                    'displayBand': 3,
                    'maturity': 'PROVISIONAL',
                    'evidenceCount': 4,
                    'uncertainty': 0.42,
                  },
                  {
                    'dimension': 'TECHNIQUE',
                    'displayBand': null,
                    'maturity': 'INSUFFICIENT',
                    'evidenceCount': 0,
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final profiles = await repository.loadAbilityProfile();

    expect(profiles.first.dimension, AbilityDimension.reading);
    expect(profiles.first.displayBand, 3);
    expect(profiles.first.evidenceCount, 4);
    expect(profiles.last.dimension, AbilityDimension.technique);
    expect(profiles.last.displayBand, isNull);
    expect(profiles.last.maturity, 'INSUFFICIENT');
  });

  test('学生作答映射忽略服务端误带的内部置信度和标签', () {
    final assessment = mapStudentAttempt({
      'questionId': 'q1',
      'outcome': 'CORRECT',
      'assessorVersion': 'rules-v1',
      'rubricVersion': 'rubric-v1',
      'observations': [
        {
          'dimension': 'READING',
          'status': 'OBSERVED',
          'band': 3,
          'confidence': 0.123,
          'evidenceStepIds': ['internal-step'],
          'factCodes': ['INTERNAL_FACT'],
          'errorTags': ['INTERNAL_ERROR'],
        },
      ],
      'nextRecommendation': {
        'questionId': 'q2',
        'questionNumber': 2,
        'prompt': '下一道练习题',
        'knowledgePoints': ['函数'],
        'publicReason': '根据近期学习表现，为你选择了一道针对性练习。',
        'ruleVersion': 'adaptive-rule-v1',
        // 学生端模型不得接收管理端评分和能力快照。
        'totalScore': 99,
        'abilities': {'CALC': 1},
      },
    });

    final observation = assessment.observationFor(AbilityDimension.reading);
    expect(observation.confidence, 1);
    expect(observation.evidenceStepIds, isEmpty);
    expect(observation.factCodes, isEmpty);
    expect(observation.errorTags, isEmpty);
    expect(assessment.nextRecommendation?.questionId, 'q2');
    expect(assessment.nextRecommendation?.questionNumber, 2);
    expect(assessment.nextRecommendation?.knowledgePoints, ['函数']);
    expect(assessment.nextRecommendation?.ruleVersion, 'adaptive-rule-v1');
  });
}

Map<String, Object?> _sessionEnvelope({String? participantToken}) => {
  'ok': true,
  'data': {
    'participantToken': participantToken,
    'session': {
      'id': 'practice-session-1',
      'status': 'ACTIVE',
      'revision': 0,
      'currentQuestionNumber': 1,
      'expiresAt': '2026-09-12T00:00:00.000Z',
      'paper': {
        'id': 'paper-1',
        'paperCode': 'cn-gaokao-2026-new-i-math-v1',
        'contentVersion': 'demo-v1',
        'title': '2026 新高考 I 卷数学结构演示',
        'subtitle': '自造演示题，不是官方试题。',
        'source': 'DEMONSTRATION',
        'difficultyAlgorithmVersion': 'difficulty-rule-v1',
        'questionCount': 1,
        'questions': [
          {
            'id': 'q1',
            'questionCode': 'q1',
            'number': 1,
            'type': 'SINGLE_CHOICE',
            'prompt': '1+1=?',
            'options': {'A': '1', 'B': '2'},
            'knowledgePoints': ['集合'],
            'difficulty': {
              'knowledgeLoad': 1,
              'readingLoad': 1,
              'reasoningLoad': 1,
              'calculationLoad': 1,
              'techniqueDependency': 0,
              'stepDepth': 1,
              'overallBand': 1,
              'algorithmVersion': 'difficulty-rule-v1',
            },
          },
        ],
      },
      'progresses': [],
      'attempts': [],
    },
  },
};

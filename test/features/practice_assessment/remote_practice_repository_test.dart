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
        client: MockClient((request) async => http.Response(
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
        )),
      ),
    );

    await expectLater(
      repository.loadOrCreateSession(),
      throwsA(
        isA<PracticeApiException>()
            .having((error) => error.requestId, 'requestId', 'req_test'),
      ),
    );
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/demo_spoken_formula_repository.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/practice_api_client.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/practice_participant_token_store.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/remote_spoken_formula_repository.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';

void main() {
  test('远程解析只发送文字和区域，并使用调用方提供的超时', () async {
    final observedTimeouts = <Duration>[];
    final repository = _remoteRepository((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/practice/formulas/resolve-spoken-text');
      expect(jsonDecode(request.body), <String, Object?>{
        'text': 'x 的平方',
        'locale': 'zh-CN',
      });
      return _okResponse(_resolvedFixture());
    });

    final resolution = await runZoned(
      () => repository.resolve(
        text: 'x 的平方',
        timeout: const Duration(seconds: 4),
      ),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(seconds: 4) ||
              duration == const Duration(seconds: 70)) {
            observedTimeouts.add(duration);
          }
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );

    expect(observedTimeouts, <Duration>[const Duration(seconds: 4)]);
    expect(resolution.resolutionId, 'resolution-1');
    expect(resolution.recognizedText, 'x 的平方');
    expect(resolution.normalizedText, 'x的平方');
    expect(resolution.outcome, SpokenFormulaOutcome.resolved);
    expect(resolution.candidates.single.id, 'candidate-1');
    expect(resolution.candidates.single.latex, r'x^2');
    expect(resolution.candidates.single.spokenBack, 'x 的平方');
    expect(resolution.clarification, isNull);
    expect(resolution.warnings, isEmpty);
  });

  test('远程解析映射二至三个候选及反向朗读', () async {
    final data = _resolvedFixture()
      ..['outcome'] = 'candidates'
      ..['candidates'] = <Map<String, Object?>>[
        {
          'id': 'candidate-1',
          'latex': r'\frac{1}{x^2+1}',
          'spokenBack': '一除以括号 x 平方加一括号',
        },
        {
          'id': 'candidate-2',
          'latex': r'\frac{1}{x^2}+1',
          'spokenBack': '一除以 x 平方，再加一',
        },
      ]
      ..['warnings'] = <String>['请确认分母范围'];
    final repository = _remoteRepository((_) async => _okResponse(data));

    final resolution = await repository.resolve(
      text: '一除以 x 平方加一',
      timeout: const Duration(seconds: 5),
    );

    expect(resolution.outcome, SpokenFormulaOutcome.candidates);
    expect(resolution.candidates.map((candidate) => candidate.id), <String>[
      'candidate-1',
      'candidate-2',
    ]);
    expect(resolution.candidates.last.latex, r'\frac{1}{x^2}+1');
    expect(resolution.candidates.last.spokenBack, '一除以 x 平方，再加一');
    expect(resolution.warnings, <String>['请确认分母范围']);
  });

  test('远程解析映射澄清问题及全部可交互动作', () async {
    final data = _resolvedFixture()
      ..['outcome'] = 'clarification'
      ..['candidates'] = <Map<String, Object?>>[
        {'id': 'candidate-1', 'latex': r'(-2)^2', 'spokenBack': '负二整体的平方'},
      ]
      ..['clarification'] = <String, Object?>{
        'question': '“负二的平方”是否包含负号？',
        'focusText': '负二的平方',
        'options': <Map<String, Object?>>[
          {
            'id': 'select-negative-square',
            'label': '选择负二整体的平方',
            'action': 'selectCandidate',
            'candidateId': 'candidate-1',
          },
          {
            'id': 'retry-recording',
            'label': '重新录音',
            'action': 'retryRecording',
          },
          {'id': 'use-keyboard', 'label': '使用公式键盘', 'action': 'useKeyboard'},
        ],
      };
    final repository = _remoteRepository((_) async => _okResponse(data));

    final resolution = await repository.resolve(
      text: '负二的平方',
      timeout: const Duration(seconds: 5),
    );

    expect(resolution.outcome, SpokenFormulaOutcome.clarification);
    expect(resolution.clarification?.question, '“负二的平方”是否包含负号？');
    expect(resolution.clarification?.focusText, '负二的平方');
    expect(
      resolution.clarification?.options.map((option) => option.action),
      <SpokenFormulaClarificationAction>[
        SpokenFormulaClarificationAction.selectCandidate,
        SpokenFormulaClarificationAction.retryRecording,
        SpokenFormulaClarificationAction.useKeyboard,
      ],
    );
    expect(resolution.clarification?.options.first.candidateId, 'candidate-1');
    expect(resolution.clarification?.options.last.candidateId, isNull);
  });

  for (final fixture in <({String name, Map<String, Object?> data})>[
    (
      name: 'resolved 缺少候选',
      data: _resolvedFixture()..['candidates'] = <Object?>[],
    ),
    (
      name: 'resolved 带有两个候选',
      data: _resolvedFixture()
        ..['candidates'] = <Object?>[
          _candidateFixture('candidate-1'),
          _candidateFixture('candidate-2'),
        ],
    ),
    (
      name: 'candidates 只有一个候选',
      data: _resolvedFixture()..['outcome'] = 'candidates',
    ),
    (
      name: 'clarification 缺少澄清内容',
      data: _resolvedFixture()
        ..['outcome'] = 'clarification'
        ..['candidates'] = <Object?>[],
    ),
  ]) {
    test('拒绝不符合结果基数的响应：${fixture.name}', () async {
      await _expectSafeResolutionFailure(fixture.data);
    });
  }

  test('拒绝未知结果枚举和未知澄清动作', () async {
    await _expectSafeResolutionFailure(
      _resolvedFixture()..['outcome'] = 'maybe',
    );
    await _expectSafeResolutionFailure(
      _clarificationFixture()
        ..['clarification'] = <String, Object?>{
          'question': '请选择下一步。',
          'focusText': '未知片段',
          'options': <Map<String, Object?>>[
            {'id': 'retry-recording', 'label': '重新录音', 'action': 'tryAgain'},
            {'id': 'use-keyboard', 'label': '使用公式键盘', 'action': 'useKeyboard'},
          ],
        },
    );
  });

  test('拒绝澄清动作引用响应外候选或携带多余候选 ID', () async {
    final unknownCandidate = _clarificationFixture();
    final clarification =
        unknownCandidate['clarification']! as Map<String, Object?>;
    clarification['options'] = <Map<String, Object?>>[
      {
        'id': 'select-candidate',
        'label': '选择候选',
        'action': 'selectCandidate',
        'candidateId': 'candidate-outside-response',
      },
      {'id': 'use-keyboard', 'label': '使用公式键盘', 'action': 'useKeyboard'},
    ];
    await _expectSafeResolutionFailure(unknownCandidate);

    final redundantCandidateId = _clarificationFixture();
    final redundantClarification =
        redundantCandidateId['clarification']! as Map<String, Object?>;
    redundantClarification['options'] = <Map<String, Object?>>[
      {
        'id': 'retry-recording',
        'label': '重新录音',
        'action': 'retryRecording',
        'candidateId': 'candidate-1',
      },
      {'id': 'use-keyboard', 'label': '使用公式键盘', 'action': 'useKeyboard'},
    ];
    await _expectSafeResolutionFailure(redundantCandidateId);
  });

  test('拒绝重复候选 ID、重复选项 ID 和不足两个澄清选项', () async {
    final duplicateCandidates = _resolvedFixture()
      ..['outcome'] = 'candidates'
      ..['candidates'] = <Object?>[
        _candidateFixture('candidate-1'),
        _candidateFixture('candidate-1'),
      ];
    await _expectSafeResolutionFailure(duplicateCandidates);

    final duplicateOptions = _clarificationFixture();
    final duplicateClarification =
        duplicateOptions['clarification']! as Map<String, Object?>;
    duplicateClarification['options'] = <Map<String, Object?>>[
      {'id': 'retry-recording', 'label': '重新录音', 'action': 'retryRecording'},
      {'id': 'retry-recording', 'label': '使用公式键盘', 'action': 'useKeyboard'},
    ];
    await _expectSafeResolutionFailure(duplicateOptions);

    final oneOption = _clarificationFixture();
    final oneOptionClarification =
        oneOption['clarification']! as Map<String, Object?>;
    oneOptionClarification['options'] = <Map<String, Object?>>[
      {'id': 'retry-recording', 'label': '重新录音', 'action': 'retryRecording'},
    ];
    await _expectSafeResolutionFailure(oneOption);
  });

  test('演示解析对未覆盖表达返回可交互澄清而不是抛错', () async {
    const repository = DemoSpokenFormulaRepository();

    final resolution = await repository.resolve(
      text: '一个未覆盖的数学表达',
      timeout: const Duration(seconds: 5),
    );

    expect(resolution.outcome, SpokenFormulaOutcome.clarification);
    expect(resolution.candidates, isEmpty);
    expect(resolution.clarification?.focusText, '一个未覆盖的数学表达');
    expect(
      resolution.clarification?.options.map((option) => option.action),
      <SpokenFormulaClarificationAction>[
        SpokenFormulaClarificationAction.retryRecording,
        SpokenFormulaClarificationAction.useKeyboard,
      ],
    );
  });
}

RemoteSpokenFormulaRepository _remoteRepository(
  Future<http.Response> Function(http.Request request) handler,
) => RemoteSpokenFormulaRepository(
  PracticeApiClient(
    baseUrl: 'http://localhost:3000',
    participantTokenStore: MemoryPracticeParticipantTokenStore(),
    client: MockClient(handler),
  ),
);

http.Response _okResponse(Map<String, Object?> data) => http.Response(
  jsonEncode(<String, Object?>{'ok': true, 'data': data}),
  200,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

Map<String, Object?> _resolvedFixture() => <String, Object?>{
  'resolutionId': 'resolution-1',
  'recognizedText': 'x 的平方',
  'normalizedText': 'x的平方',
  'outcome': 'resolved',
  'candidates': <Map<String, Object?>>[_candidateFixture('candidate-1')],
  'clarification': null,
  'warnings': <String>[],
};

Map<String, Object?> _clarificationFixture() => <String, Object?>{
  'resolutionId': 'resolution-1',
  'recognizedText': '负二的平方',
  'normalizedText': '负二的平方',
  'outcome': 'clarification',
  'candidates': <Map<String, Object?>>[
    {'id': 'candidate-1', 'latex': r'(-2)^2', 'spokenBack': '负二整体的平方'},
  ],
  'clarification': <String, Object?>{
    'question': '请选择下一步。',
    'focusText': '负二的平方',
    'options': <Map<String, Object?>>[
      {'id': 'retry-recording', 'label': '重新录音', 'action': 'retryRecording'},
      {'id': 'use-keyboard', 'label': '使用公式键盘', 'action': 'useKeyboard'},
    ],
  },
  'warnings': <String>[],
};

Map<String, Object?> _candidateFixture(String id) => <String, Object?>{
  'id': id,
  'latex': r'x^2',
  'spokenBack': 'x 的平方',
};

Future<void> _expectSafeResolutionFailure(Map<String, Object?> data) async {
  final repository = _remoteRepository((_) async => _okResponse(data));

  await expectLater(
    repository.resolve(text: 'x', timeout: const Duration(seconds: 5)),
    throwsA(
      isA<SpokenFormulaResolutionException>().having(
        (error) => error.message,
        'message',
        '公式服务返回的数据不完整，请重新说一次。',
      ),
    ),
  );
}

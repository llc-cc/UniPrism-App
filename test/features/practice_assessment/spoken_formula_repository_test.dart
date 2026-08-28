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
  test('远程解析发送剩余预算，并使用同一调用方超时', () async {
    final observedTimeouts = <Duration>[];
    final repository = _remoteRepository((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/practice/formulas/resolve-spoken-text');
      expect(jsonDecode(request.body), <String, Object?>{
        'text': 'x 的平方',
        'locale': 'zh-CN',
        'budgetMs': 4000,
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

  test('V2 budgetMs 收敛到 1..5000 且不抬高已有的较小毫秒预算', () async {
    final budgets = <int>[];
    final repository = _remoteRepository((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      budgets.add(body['budgetMs']! as int);
      return _okResponse(_resolvedFixture());
    });

    await repository.resolve(text: '上限测试', timeout: const Duration(seconds: 6));
    await repository.resolve(
      text: '较小预算',
      timeout: const Duration(milliseconds: 200),
    );
    expect(budgets, <int>[5000, 200]);
  });

  test('不足一整毫秒的剩余时间在 HTTP 前失败', () async {
    var requestCount = 0;
    final repository = _remoteRepository((_) async {
      requestCount += 1;
      return _okResponse(_resolvedFixture());
    });

    for (final timeout in <Duration>[
      const Duration(microseconds: 500),
      Duration.zero,
      const Duration(milliseconds: -1),
    ]) {
      await expectLater(
        repository.resolve(text: '不应上传', timeout: timeout),
        throwsA(
          isA<SpokenFormulaResolutionException>().having(
            (error) => error.message,
            'message',
            contains('时间'),
          ),
        ),
      );
    }

    expect(requestCount, 0);
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
            'id': 'continue-recording',
            'label': '继续补充语音',
            'action': 'continueRecording',
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
        SpokenFormulaClarificationAction.continueRecording,
        SpokenFormulaClarificationAction.useKeyboard,
      ],
    );
    expect(resolution.clarification?.options.first.candidateId, 'candidate-1');
    expect(resolution.clarification?.options.last.candidateId, isNull);
  });

  test('远程解析接受三个公式片段及其选择、续录和键盘共五个澄清动作', () async {
    final data = _clarificationFixture();
    data['candidates'] = <Map<String, Object?>>[
      _candidateFixture('candidate-1'),
      _candidateFixture('candidate-2'),
      _candidateFixture('candidate-3'),
    ];
    final clarification = data['clarification']! as Map<String, Object?>;
    clarification['options'] = <Map<String, Object?>>[
      {
        'id': 'select-candidate-1',
        'label': '选择片段一',
        'action': 'selectCandidate',
        'candidateId': 'candidate-1',
      },
      {
        'id': 'select-candidate-2',
        'label': '选择片段二',
        'action': 'selectCandidate',
        'candidateId': 'candidate-2',
      },
      {
        'id': 'select-candidate-3',
        'label': '选择片段三',
        'action': 'selectCandidate',
        'candidateId': 'candidate-3',
      },
      {
        'id': 'continue-recording',
        'label': '继续补充语音',
        'action': 'continueRecording',
      },
      {'id': 'use-keyboard', 'label': '使用公式键盘', 'action': 'useKeyboard'},
    ];
    final repository = _remoteRepository((_) async => _okResponse(data));

    final resolution = await repository.resolve(
      text: '已知 x 大于零，求最小值',
      timeout: const Duration(seconds: 5),
    );

    expect(resolution.outcome, SpokenFormulaOutcome.clarification);
    expect(resolution.candidates, hasLength(3));
    expect(resolution.clarification?.options, hasLength(5));
    expect(
      resolution.clarification?.options
          .where(
            (option) =>
                option.action ==
                SpokenFormulaClarificationAction.selectCandidate,
          )
          .map((option) => option.candidateId),
      <String>['candidate-1', 'candidate-2', 'candidate-3'],
    );
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

  test('拒绝同一候选被重复选择以及重复的非选择澄清动作', () async {
    final duplicateCandidateSelection = _clarificationFixture();
    final duplicateSelectionClarification =
        duplicateCandidateSelection['clarification']! as Map<String, Object?>;
    duplicateSelectionClarification['options'] = <Map<String, Object?>>[
      {
        'id': 'select-candidate-first',
        'label': '选择候选一',
        'action': 'selectCandidate',
        'candidateId': 'candidate-1',
      },
      {
        'id': 'select-candidate-again',
        'label': '再次选择候选一',
        'action': 'selectCandidate',
        'candidateId': 'candidate-1',
      },
      {'id': 'use-keyboard', 'label': '使用公式键盘', 'action': 'useKeyboard'},
    ];
    await _expectSafeResolutionFailure(duplicateCandidateSelection);

    for (final duplicateAction in <String>[
      'continueRecording',
      'retryRecording',
      'useKeyboard',
    ]) {
      final data = _clarificationFixture();
      final clarification = data['clarification']! as Map<String, Object?>;
      clarification['options'] = <Map<String, Object?>>[
        {
          'id': '$duplicateAction-first',
          'label': '第一个恢复动作',
          'action': duplicateAction,
        },
        {
          'id': '$duplicateAction-second',
          'label': '重复的恢复动作',
          'action': duplicateAction,
        },
        {
          'id':
              'fallback-${duplicateAction == 'useKeyboard' ? 'retry' : 'keyboard'}',
          'label': '另一恢复动作',
          'action': duplicateAction == 'useKeyboard'
              ? 'retryRecording'
              : 'useKeyboard',
        },
      ];
      await _expectSafeResolutionFailure(data);
    }
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

  final textLengthCases =
      <
        ({
          String field,
          int maximum,
          Map<String, Object?> Function(String value) fixture,
        })
      >[
        (
          field: 'recognizedText',
          maximum: 300,
          fixture: (value) => _resolvedFixture()..['recognizedText'] = value,
        ),
        (
          field: 'normalizedText',
          maximum: 300,
          fixture: (value) => _resolvedFixture()..['normalizedText'] = value,
        ),
        (
          field: 'candidate.spokenBack',
          maximum: 240,
          fixture: (value) => _candidateFieldFixture('spokenBack', value),
        ),
        (
          field: 'candidate.latex',
          maximum: 512,
          fixture: (value) => _candidateFieldFixture('latex', value),
        ),
        (
          field: 'clarification.question',
          maximum: 240,
          fixture: (value) => _clarificationFieldFixture('question', value),
        ),
        (
          field: 'clarification.focusText',
          maximum: 120,
          fixture: (value) => _clarificationFieldFixture('focusText', value),
        ),
        (
          field: 'clarification.options.label',
          maximum: 120,
          fixture: (value) => _optionFieldFixture('label', value),
        ),
        (
          field: 'warnings',
          maximum: 160,
          fixture: (value) =>
              _resolvedFixture()..['warnings'] = <String>[value],
        ),
      ];

  for (final item in textLengthCases) {
    test('${item.field} 接受后端契约最大长度 ${item.maximum}', () async {
      final repository = _remoteRepository(
        (_) async => _okResponse(item.fixture(_repeatedText(item.maximum))),
      );

      final result = await repository.resolve(
        text: 'x',
        timeout: const Duration(seconds: 5),
      );

      expect(result, isA<SpokenFormulaResolution>());
    });

    test('${item.field} 拒绝超过后端契约最大长度', () async {
      await _expectSafeResolutionFailure(
        item.fixture(_repeatedText(item.maximum + 1)),
      );
    });
  }

  test('用户原文和规范化文本允许契约内的 URL 与反斜线纯文本', () async {
    final data = _resolvedFixture()
      ..['recognizedText'] = '输入 https://example.com'
      ..['normalizedText'] = r'集合 \{x\}';
    final repository = _remoteRepository((_) async => _okResponse(data));

    final resolution = await repository.resolve(
      text: 'x',
      timeout: const Duration(seconds: 5),
    );

    expect(resolution.recognizedText, '输入 https://example.com');
    expect(resolution.normalizedText, r'集合 \{x\}');
  });

  for (final unsafeText in <String>[
    r'\frac{x}{y}',
    r'$x$',
    '<img\nsrc=example.com/image>',
    '`x`',
    '[说明](https://example.com)',
    '# 标题',
    '**粗体答案**',
    '__粗体答案__',
    '~~删除答案~~',
    '请确认 *答案*。',
    '请确认_答案_。',
    'ftp://example.com/formula',
    'mailto:test@example.com',
    'data:text/plain,x',
    'javascript:alert(1)',
    'file:///tmp/formula',
    'www.example.com/formula',
    '//example.com/formula',
    '请查看example.com/formula',
  ]) {
    test('服务端展示文本拒绝标记或链接：$unsafeText', () async {
      await _expectSafeResolutionFailure(
        _candidateFieldFixture('spokenBack', unsafeText),
      );
    });
  }

  test('展示文本拒绝 U+3007 位于 Markdown 强调前的 Han 邻接绕过', () async {
    await _expectSafeResolutionFailure(
      _candidateFieldFixture('spokenBack', '〇_答案_。'),
    );
  });

  test('展示文本拒绝 U+3007 位于 Markdown 强调后的 Han 邻接绕过', () async {
    await _expectSafeResolutionFailure(
      _candidateFieldFixture('spokenBack', '请_答案_〇'),
    );
  });

  for (final item in <({String codePoint, int rune})>[
    (codePoint: 'U+3021', rune: 0x3021),
    (codePoint: 'U+3038', rune: 0x3038),
    (codePoint: 'U+16FE2', rune: 0x16FE2),
  ]) {
    test('展示文本拒绝 ${item.codePoint} Han 邻接绕过', () async {
      final hanCharacter = String.fromCharCode(item.rune);
      await _expectSafeResolutionFailure(
        _candidateFieldFixture('spokenBack', '${hanCharacter}_答案_。'),
      );
    });
  }

  test('展示文本不把后端 Script=Common 的 U+31C0 扩大为 Han', () async {
    final data = _candidateFieldFixture('spokenBack', '㇀_答案_。');
    final repository = _remoteRepository((_) async => _okResponse(data));

    final resolution = await repository.resolve(
      text: 'x',
      timeout: const Duration(seconds: 5),
    );

    expect(resolution.candidates.single.spokenBack, '㇀_答案_。');
  });

  test('展示文本过滤允许普通高中数学下标描述', () async {
    final data = _resolvedFixture()
      ..['warnings'] = <String>['请确认 x_2 的取值范围（可以等于 2）。'];
    final repository = _remoteRepository((_) async => _okResponse(data));

    final resolution = await repository.resolve(
      text: 'x',
      timeout: const Duration(seconds: 5),
    );

    expect(resolution.warnings, <String>['请确认 x_2 的取值范围（可以等于 2）。']);
  });

  for (final item
      in <
        ({String field, Map<String, Object?> Function(String value) fixture})
      >[
        (
          field: 'candidate.spokenBack',
          fixture: (value) => _candidateFieldFixture('spokenBack', value),
        ),
        (
          field: 'clarification.question',
          fixture: (value) => _clarificationFieldFixture('question', value),
        ),
        (
          field: 'clarification.focusText',
          fixture: (value) => _clarificationFieldFixture('focusText', value),
        ),
        (
          field: 'clarification.options.label',
          fixture: (value) => _optionFieldFixture('label', value),
        ),
        (
          field: 'warnings',
          fixture: (value) =>
              _resolvedFixture()..['warnings'] = <String>[value],
        ),
      ]) {
    test('${item.field} 使用服务端展示文本过滤规则', () async {
      await _expectSafeResolutionFailure(
        item.fixture('访问 https://example.com'),
      );
    });
  }

  for (final item
      in <({String level, Map<String, Object?> Function() fixture})>[
        (level: '顶层', fixture: () => _resolvedFixture()..['confidence'] = 0.99),
        (
          level: 'candidate',
          fixture: () => _candidateFieldFixture('ast', <String, Object?>{}),
        ),
        (
          level: 'clarification',
          fixture: () => _clarificationFieldFixture('confidence', 0.5),
        ),
        (
          level: 'option',
          fixture: () => _optionFieldFixture('confidence', 0.5),
        ),
      ]) {
    test('${item.level}对象拒绝后端契约外字段', () async {
      await _expectSafeResolutionFailure(item.fixture());
    });
  }

  test('领域集合防御复制源列表且 getter 不可修改', () {
    final sourceOptions = <SpokenFormulaClarificationOption>[
      const SpokenFormulaClarificationOption(
        id: 'retry-recording',
        label: '重新录音',
        action: SpokenFormulaClarificationAction.retryRecording,
      ),
      const SpokenFormulaClarificationOption(
        id: 'use-keyboard',
        label: '使用公式键盘',
        action: SpokenFormulaClarificationAction.useKeyboard,
      ),
    ];
    final clarification = SpokenFormulaClarification(
      question: '请选择下一步。',
      focusText: '作用范围',
      options: sourceOptions,
    );
    final sourceCandidates = <SpokenFormulaCandidate>[
      const SpokenFormulaCandidate(
        id: 'candidate-1',
        latex: 'x^2',
        spokenBack: 'x 的平方',
      ),
    ];
    final sourceWarnings = <String>['请确认作用范围。'];
    final resolution = SpokenFormulaResolution(
      resolutionId: 'resolution-1',
      recognizedText: 'x 的平方',
      normalizedText: 'x的平方',
      outcome: SpokenFormulaOutcome.clarification,
      candidates: sourceCandidates,
      clarification: clarification,
      warnings: sourceWarnings,
    );

    sourceCandidates.clear();
    sourceWarnings.clear();
    sourceOptions.clear();

    expect(resolution.candidates, hasLength(1));
    expect(resolution.warnings, hasLength(1));
    expect(resolution.clarification?.options, hasLength(2));
    expect(
      () => resolution.candidates.clear(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(() => resolution.warnings.clear(), throwsA(isA<UnsupportedError>()));
    expect(
      () => resolution.clarification?.options.clear(),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('演示解析的候选、警告和澄清选项均不可修改', () async {
    const repository = DemoSpokenFormulaRepository();

    final resolved = await repository.resolve(
      text: 'x 的平方',
      timeout: const Duration(seconds: 5),
    );
    final candidates = await repository.resolve(
      text: '负二的平方',
      timeout: const Duration(seconds: 5),
    );
    final clarification = await repository.resolve(
      text: '未覆盖表达',
      timeout: const Duration(seconds: 5),
    );

    expect(
      () => resolved.candidates.add(
        const SpokenFormulaCandidate(
          id: 'candidate-2',
          latex: 'x',
          spokenBack: 'x',
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(() => candidates.warnings.clear(), throwsA(isA<UnsupportedError>()));
    expect(
      () => clarification.clarification?.options.clear(),
      throwsA(isA<UnsupportedError>()),
    );
  });

  for (final text in <String>['', '   ', '，。！？']) {
    test('演示解析拒绝空白或归一化为空的输入：${text.isEmpty ? '空字符串' : text}', () async {
      const repository = DemoSpokenFormulaRepository();

      await expectLater(
        repository.resolve(text: text, timeout: const Duration(seconds: 5)),
        throwsA(
          isA<SpokenFormulaResolutionException>().having(
            (error) => error.message,
            'message',
            '没有识别到有效的公式内容，请重新说一次。',
          ),
        ),
      );
    });
  }

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

Map<String, Object?> _candidateFieldFixture(String key, Object? value) {
  final data = _resolvedFixture();
  final candidates = data['candidates']! as List<Map<String, Object?>>;
  candidates.single[key] = value;
  return data;
}

Map<String, Object?> _clarificationFieldFixture(String key, Object? value) {
  final data = _clarificationFixture();
  final clarification = data['clarification']! as Map<String, Object?>;
  clarification[key] = value;
  return data;
}

Map<String, Object?> _optionFieldFixture(String key, Object? value) {
  final data = _clarificationFixture();
  final clarification = data['clarification']! as Map<String, Object?>;
  final options = clarification['options']! as List<Map<String, Object?>>;
  options.first[key] = value;
  return data;
}

String _repeatedText(int length) => List<String>.filled(length, '甲').join();

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

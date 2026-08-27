import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/practice_api_client.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/practice_participant_token_store.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/remote_spoken_formula_repository.dart';
import 'package:uniprism_app/features/practice_assessment/application/speech_formula_controller.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_voice_panel.dart';

void main() {
  testWidgets('真实远程组件链路依次处理 resolved 与 candidates，并只插入一次', (tester) async {
    final requests = <http.Request>[];
    var responseIndex = 0;
    final client = MockClient((request) async {
      requests.add(request);
      final response = responseIndex++ == 0
          ? _resolvedResponse
          : _candidatesResponse;
      return http.Response(
        jsonEncode(<String, Object?>{'ok': true, 'data': response}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    addTearDown(client.close);
    final api = PracticeApiClient(
      baseUrl: 'https://practice.example.test/',
      participantTokenStore: MemoryPracticeParticipantTokenStore(),
      client: client,
    );
    final repository = RemoteSpokenFormulaRepository(api);
    final recognizer = _ControlledRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    final inserted = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeFormulaVoicePanel(
            controller: controller,
            onInsert: inserted.add,
          ),
        ),
      ),
    );

    await _startAndResolve(tester, recognizer, 'x 的平方加一');

    expect(
      find.byKey(const ValueKey('practice-formula-voice-resolved')),
      findsOneWidget,
    );
    expect(find.text('反向朗读：x 的平方加一'), findsOneWidget);
    expect(inserted, isEmpty);
    await _tapInsertTwiceBeforeRebuild(tester);
    expect(inserted, <String>[r'x^2+1']);

    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-start')),
    );
    await _pumpAsync(tester);
    recognizer.emit('负二的平方', isFinal: true);
    await _pumpAsync(tester);

    expect(
      find.byKey(const ValueKey('practice-formula-voice-candidates')),
      findsOneWidget,
    );
    expect(find.text('反向朗读：负二整体的平方'), findsOneWidget);
    expect(find.text('反向朗读：二的平方再取负'), findsOneWidget);
    final insertButton = find.byKey(
      const ValueKey('practice-formula-voice-insert'),
    );
    expect(tester.widget<FilledButton>(insertButton).onPressed, isNull);

    await tester.tap(
      find.byKey(
        const ValueKey('practice-formula-voice-candidate-negative-outside'),
      ),
    );
    await tester.pump();
    expect(controller.state.selectedCandidate?.id, 'negative-outside');
    expect(tester.widget<FilledButton>(insertButton).onPressed, isNotNull);
    await _tapInsertTwiceBeforeRebuild(tester);

    expect(inserted, <String>[r'x^2+1', r'-2^2']);
    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://practice.example.test/api/practice/formulas/resolve-spoken-text',
      );
    }
    expect(jsonDecode(requests[0].body), <String, Object?>{
      'text': 'x 的平方加一',
      'locale': 'zh-CN',
    });
    expect(jsonDecode(requests[1].body), <String, Object?>{
      'text': '负二的平方',
      'locale': 'zh-CN',
    });
  });
}

Future<void> _startAndResolve(
  WidgetTester tester,
  _ControlledRecognizer recognizer,
  String transcript,
) async {
  await tester.tap(find.byKey(const ValueKey('practice-formula-voice-start')));
  await _pumpAsync(tester);
  recognizer.emit(transcript, isFinal: true);
  await _pumpAsync(tester);
}

Future<void> _tapInsertTwiceBeforeRebuild(WidgetTester tester) async {
  final insert = find.byKey(const ValueKey('practice-formula-voice-insert'));
  await tester.tap(insert);
  await tester.tap(insert);
  await tester.pump();
}

Future<void> _pumpAsync(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump();
  }
}

final class _ControlledRecognizer implements SpeechFormulaRecognizer {
  final List<SpeechFormulaResultCallback> _results =
      <SpeechFormulaResultCallback>[];

  @override
  SpokenFormulaRecognitionException? get initializationError => null;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
    SpeechFormulaFinalizationStartedCallback? onFinalizationStarted,
  }) async {
    _results.add(onResult);
  }

  void emit(String words, {required bool isFinal}) {
    _results.last(words, isFinal: isFinal);
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stop() async {}
}

const _resolvedResponse = <String, Object?>{
  'resolutionId': 'resolution-resolved',
  'recognizedText': 'x 的平方加一',
  'normalizedText': 'x的平方加一',
  'outcome': 'resolved',
  'candidates': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'resolved-candidate',
      'latex': r'x^2+1',
      'spokenBack': 'x 的平方加一',
    },
  ],
  'clarification': null,
  'warnings': <String>[],
};

const _candidatesResponse = <String, Object?>{
  'resolutionId': 'resolution-candidates',
  'recognizedText': '负二的平方',
  'normalizedText': '负二的平方',
  'outcome': 'candidates',
  'candidates': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'negative-inside',
      'latex': r'(-2)^2',
      'spokenBack': '负二整体的平方',
    },
    <String, Object?>{
      'id': 'negative-outside',
      'latex': r'-2^2',
      'spokenBack': '二的平方再取负',
    },
  ],
  'clarification': null,
  'warnings': <String>['请确认负号是否在平方范围内'],
};

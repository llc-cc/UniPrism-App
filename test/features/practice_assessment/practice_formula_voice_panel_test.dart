import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/application/speech_formula_controller.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_voice_panel.dart';

void main() {
  testWidgets('空闲状态显示语音入口并进入监听状态', (tester) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: _Repository(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));
    expect(find.text('识别方式：浏览器语音'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-start')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-formula-voice-stop')),
      findsOneWidget,
    );
    expect(find.textContaining('识别方式：'), findsNothing);
  });

  testWidgets('375 窄屏空闲状态显示本机 SenseVoice 来源且不溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SpeechFormulaController(
      recognizer: _FakeRecognizer(),
      repository: _Repository(),
      sourceLabel: '本机 SenseVoice',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));

    expect(find.text('识别方式：本机 SenseVoice'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-start')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('预览确认前不插入且确认后只回调选中候选', (tester) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: _Repository(withAlternative: true),
    );
    final inserted = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, inserted.add));
    await controller.startListening();
    recognizer.emit('负二的平方', isFinal: true);
    await _pumpAsync(tester);

    expect(controller.state.status, SpeechFormulaStatus.preview);
    expect(inserted, isEmpty);
    expect(find.textContaining('负二的平方'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-alternative-1')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-insert')),
    );
    await tester.pump();

    expect(inserted, <String>[r'-2^2']);
  });

  testWidgets('375 窄屏预览操作不溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: _Repository(withAlternative: true),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));
    await controller.startListening();
    recognizer.emit('负二的平方', isFinal: true);
    await _pumpAsync(tester);

    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  SpeechFormulaController controller,
  ValueChanged<String> onInsert,
) => MaterialApp(
  home: Scaffold(
    body: PracticeFormulaVoicePanel(controller: controller, onInsert: onInsert),
  ),
);

Future<void> _pumpAsync(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump();
  }
}

final class _FakeRecognizer implements SpeechFormulaRecognizer {
  SpeechFormulaResultCallback? _onResult;

  @override
  SpokenFormulaRecognitionException? get initializationError => null;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
  }) async {
    _onResult = onResult;
  }

  void emit(String words, {required bool isFinal}) =>
      _onResult?.call(words, isFinal: isFinal);

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stop() async {}
}

final class _Repository implements SpokenFormulaRepository {
  const _Repository({this.withAlternative = false});

  final bool withAlternative;

  @override
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  }) async => SpokenFormulaConversion(
    recognizedText: text,
    normalizedText: text,
    latex: withAlternative ? r'(-2)^2' : r'x^2',
    alternatives: withAlternative ? const <String>[r'-2^2'] : const [],
    warnings: withAlternative ? const <String>['括号作用范围存在歧义'] : const [],
  );
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/application/speech_formula_controller.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';

void main() {
  test('最终语音文本转换为可确认公式', () async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: _ImmediateRepository(),
    );
    addTearDown(controller.dispose);

    await controller.startListening();
    recognizer.emit('x 的平方', isFinal: true);
    await _flushAsyncWork();

    expect(controller.state.status, SpeechFormulaStatus.preview);
    expect(controller.state.transcript, 'x 的平方');
    expect(controller.state.selectedLatex, 'x^2');
  });

  test('浏览器不支持语音时保留可恢复错误状态', () async {
    final controller = SpeechFormulaController(
      recognizer: _FakeRecognizer(isAvailable: false),
      repository: _ImmediateRepository(),
    );
    addTearDown(controller.dispose);

    await controller.startListening();

    expect(controller.state.status, SpeechFormulaStatus.error);
    expect(controller.state.isSupported, isFalse);
    expect(controller.state.errorMessage, contains('Chrome'));
  });

  test('取消后迟到的转换结果不能进入预览', () async {
    final recognizer = _FakeRecognizer();
    final repository = _DeferredRepository();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);

    await controller.startListening();
    recognizer.emit('x 的平方', isFinal: true);
    await _flushAsyncWork();
    expect(controller.state.status, SpeechFormulaStatus.converting);

    await controller.reset();
    repository.complete(_conversion());
    await _flushAsyncWork();

    expect(controller.state.status, SpeechFormulaStatus.idle);
    expect(controller.state.conversion, isNull);
  });
}

SpokenFormulaConversion _conversion() => const SpokenFormulaConversion(
  recognizedText: 'x 的平方',
  normalizedText: 'x 的平方',
  latex: 'x^2',
  alternatives: <String>[],
  warnings: <String>[],
);

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _FakeRecognizer implements SpeechFormulaRecognizer {
  _FakeRecognizer({this.isAvailable = true});

  final bool isAvailable;
  SpeechFormulaResultCallback? _onResult;

  @override
  Future<bool> initialize() async => isAvailable;

  @override
  Future<void> listen({required SpeechFormulaResultCallback onResult}) async {
    _onResult = onResult;
  }

  void emit(String words, {required bool isFinal}) {
    _onResult?.call(words, isFinal: isFinal);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

final class _ImmediateRepository implements SpokenFormulaRepository {
  @override
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  }) async => _conversion();
}

final class _DeferredRepository implements SpokenFormulaRepository {
  final Completer<SpokenFormulaConversion> _completer = Completer();

  @override
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  }) => _completer.future;

  void complete(SpokenFormulaConversion value) => _completer.complete(value);
}

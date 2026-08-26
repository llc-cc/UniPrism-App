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
    expect(recognizer.stopCount, 0);
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

  test('重复的最终识别结果只触发一次公式转换', () async {
    final recognizer = _FakeRecognizer();
    final repository = _CountingRepository();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);

    await controller.startListening();
    recognizer.emit('x 的平方', isFinal: true);
    recognizer.emit('x 的平方', isFinal: true);
    await _flushAsyncWork();

    expect(repository.callCount, 1);
  });

  test('旧 operation 的 typed error 不能覆盖新一轮监听状态', () async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: _ImmediateRepository(),
    );
    addTearDown(controller.dispose);

    await controller.startListening();
    await controller.reset();
    await controller.startListening();
    recognizer.emitError(
      const SpokenFormulaRecognitionException('旧错误'),
      listenIndex: 0,
    );

    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(controller.state.errorMessage, isNull);
  });

  test('manual stop 没有 final 时不转换 partial 并报告无识别结果', () async {
    final recognizer = _FakeRecognizer();
    final repository = _CountingRepository();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('partial', isFinal: false);

    await controller.stopListening();

    expect(controller.state.status, SpeechFormulaStatus.error);
    expect(controller.state.errorMessage, contains('没有识别到语音'));
    expect(repository.callCount, 0);
  });

  test('manual stop 内同步发出的 final 只转换一次', () async {
    final recognizer = _FakeRecognizer(finalWordsOnStop: 'x 的平方');
    final repository = _CountingRepository();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();

    await controller.stopListening();
    await _flushAsyncWork();

    expect(controller.state.status, SpeechFormulaStatus.preview);
    expect(repository.callCount, 1);
    expect(recognizer.stopCount, 1);
  });

  test(
    '当前 operation 的 typed recognition error 保留 partial transcript',
    () async {
      final recognizer = _FakeRecognizer();
      final controller = SpeechFormulaController(
        recognizer: recognizer,
        repository: _ImmediateRepository(),
      );
      addTearDown(controller.dispose);
      await controller.startListening();
      recognizer.emit('x partial', isFinal: false);

      recognizer.emitError(const SpokenFormulaRecognitionException('安全错误'));

      expect(controller.state.status, SpeechFormulaStatus.error);
      expect(controller.state.transcript, 'x partial');
      expect(controller.state.errorMessage, '安全错误');
    },
  );
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
  _FakeRecognizer({this.isAvailable = true, this.finalWordsOnStop});

  final bool isAvailable;
  final String? finalWordsOnStop;
  final List<SpeechFormulaResultCallback> _resultCallbacks = [];
  final List<SpeechFormulaErrorCallback?> _errorCallbacks = [];
  int stopCount = 0;

  @override
  Future<bool> initialize() async => isAvailable;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
  }) async {
    _resultCallbacks.add(onResult);
    _errorCallbacks.add(onError);
  }

  void emit(String words, {required bool isFinal, int? listenIndex}) {
    _resultCallbacks[listenIndex ?? _resultCallbacks.length - 1](
      words,
      isFinal: isFinal,
    );
  }

  void emitError(SpokenFormulaRecognitionException error, {int? listenIndex}) {
    _errorCallbacks[listenIndex ?? _errorCallbacks.length - 1]?.call(error);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    if (finalWordsOnStop case final words?) {
      emit(words, isFinal: true);
    }
  }

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

final class _CountingRepository implements SpokenFormulaRepository {
  int callCount = 0;

  @override
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  }) async {
    callCount += 1;
    return _conversion();
  }
}

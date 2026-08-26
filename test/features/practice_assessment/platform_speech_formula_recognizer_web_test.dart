import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';

void main() {
  test('stop 无 final 时最多一次把最后非空 partial 提升为 final', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final results = <({String words, bool isFinal})>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (words, {required isFinal}) =>
          results.add((words: words, isFinal: isFinal)),
    );
    driver.emit('first partial', isFinal: false);
    driver.emit('last partial', isFinal: false);

    await recognizer.stop();
    await recognizer.stop();

    expect(results, <({String words, bool isFinal})>[
      (words: 'first partial', isFinal: false),
      (words: 'last partial', isFinal: false),
      (words: 'last partial', isFinal: true),
    ]);
  });

  test('cancel 不会把 partial 发为 final 并忽略迟到回调', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final results = <({String words, bool isFinal})>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (words, {required isFinal}) =>
          results.add((words: words, isFinal: isFinal)),
    );
    driver.emit('partial', isFinal: false);

    await recognizer.cancel();
    driver.emit('late final', isFinal: true);

    expect(results, <({String words, bool isFinal})>[
      (words: 'partial', isFinal: false),
    ]);
    expect(driver.cancelCount, 1);
  });

  test('relisten 清空旧 partial 和 final guard 并隔离旧 generation', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final results = <({String words, bool isFinal})>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (words, {required isFinal}) =>
          results.add((words: words, isFinal: isFinal)),
    );
    driver.emit('old partial', isFinal: false, listenIndex: 0);
    driver.emit('old final', isFinal: true, listenIndex: 0);

    await recognizer.listen(
      onResult: (words, {required isFinal}) =>
          results.add((words: words, isFinal: isFinal)),
    );
    driver.emit('late old mutation', isFinal: false, listenIndex: 0);
    driver.emit('new partial', isFinal: false, listenIndex: 1);
    await recognizer.stop();

    expect(results, <({String words, bool isFinal})>[
      (words: 'old partial', isFinal: false),
      (words: 'old final', isFinal: true),
      (words: 'new partial', isFinal: false),
      (words: 'new partial', isFinal: true),
    ]);
  });

  test('browser driver error 通过 typed onError 安全转发且只发一次', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final errors = <SpokenFormulaRecognitionException>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (_, {required isFinal}) => fail('不应发出结果'),
      onError: errors.add,
    );

    driver.emitError(StateError('browser internals'));
    driver.emitError(StateError('duplicate'));

    expect(errors, hasLength(1));
    expect(errors.single.message, isNot(contains('browser internals')));
  });
}

final class _FakeWebSpeechDriver implements WebSpeechRecognitionDriver {
  final List<WebSpeechResultCallback> _callbacks = [];
  WebSpeechDriverErrorCallback? _onError;
  int stopCount = 0;
  int cancelCount = 0;

  @override
  Future<bool> initialize({
    required WebSpeechDriverErrorCallback onError,
  }) async {
    _onError = onError;
    return true;
  }

  @override
  Future<void> listen({required WebSpeechResultCallback onResult}) async {
    _callbacks.add(onResult);
  }

  void emit(String words, {required bool isFinal, int? listenIndex}) {
    _callbacks[listenIndex ?? _callbacks.length - 1](words, isFinal: isFinal);
  }

  void emitError(Object error) => _onError?.call(error);

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }
}

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

  test('relisten 后旧 session error 不能进入新 session onError', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final oldErrors = <SpokenFormulaRecognitionException>[];
    final newErrors = <SpokenFormulaRecognitionException>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (_, {required isFinal}) {},
      onError: oldErrors.add,
    );
    await recognizer.listen(
      onResult: (_, {required isFinal}) {},
      onError: newErrors.add,
    );

    driver.emitError(StateError('late old error'), listenIndex: 0);
    expect(oldErrors, isEmpty);
    expect(newErrors, isEmpty);

    driver.emitError(StateError('current error'), listenIndex: 1);
    expect(oldErrors, isEmpty);
    expect(newErrors, hasLength(1));
  });

  test('browser final onResult 抛错不逃逸且不会再发 terminal error', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    var resultCalls = 0;
    var errorCalls = 0;
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (_, {required isFinal}) {
        resultCalls += 1;
        throw StateError('consumer result failure');
      },
      onError: (_) => errorCalls += 1,
    );

    driver.emit('final', isFinal: true);
    driver.emitError(StateError('late error'));
    await recognizer.stop();

    expect(resultCalls, 1);
    expect(errorCalls, 0);
    expect(driver.stopCount, 1);
  });

  test('browser onError 抛错不逃逸且仍只调用一次', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    var errorCalls = 0;
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (_, {required isFinal}) => fail('不应发出结果'),
      onError: (_) {
        errorCalls += 1;
        throw StateError('consumer error failure');
      },
    );

    driver.emitError(StateError('first'));
    driver.emitError(StateError('second'));

    expect(errorCalls, 1);
  });
}

final class _FakeWebSpeechDriver implements WebSpeechRecognitionDriver {
  final List<WebSpeechResultCallback> _callbacks = [];
  final List<WebSpeechDriverErrorCallback> _errorCallbacks = [];
  int stopCount = 0;
  int cancelCount = 0;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> listen({
    required WebSpeechResultCallback onResult,
    required WebSpeechDriverErrorCallback onError,
  }) async {
    _callbacks.add(onResult);
    _errorCallbacks.add(onError);
  }

  void emit(String words, {required bool isFinal, int? listenIndex}) {
    _callbacks[listenIndex ?? _callbacks.length - 1](words, isFinal: isFinal);
  }

  void emitError(Object error, {int? listenIndex}) {
    _errorCallbacks[listenIndex ?? _errorCallbacks.length - 1](error);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }
}

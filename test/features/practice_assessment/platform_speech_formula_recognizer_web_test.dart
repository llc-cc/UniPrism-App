import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
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

    final stopping = recognizer.stop();
    driver.emitStatus(SpeechToText.doneStatus);
    await stopping;
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

    final cancelling = recognizer.cancel();
    driver.emitStatus(SpeechToText.doneStatus);
    await cancelling;
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
    final firstStopping = recognizer.stop();
    driver.emitStatus(SpeechToText.doneStatus);
    await firstStopping;

    await recognizer.listen(
      onResult: (words, {required isFinal}) =>
          results.add((words: words, isFinal: isFinal)),
    );
    driver.emit('late old mutation', isFinal: false, listenIndex: 0);
    driver.emit('new partial', isFinal: false, listenIndex: 1);
    final secondStopping = recognizer.stop();
    driver.emitStatus(SpeechToText.doneStatus);
    await secondStopping;

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

  test('current error 在 done 排空前拒绝 relisten，排空后新 error 只归新会话', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final oldErrors = <SpokenFormulaRecognitionException>[];
    final newErrors = <SpokenFormulaRecognitionException>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (_, {required isFinal}) {},
      onError: oldErrors.add,
    );

    driver.emitError(StateError('current old error'));
    expect(oldErrors, hasLength(1));
    await expectLater(
      recognizer.listen(
        onResult: (_, {required isFinal}) {},
        onError: newErrors.add,
      ),
      throwsStateError,
    );

    driver.emitStatus(SpeechToText.doneStatus);
    await expectLater(
      recognizer.listen(
        onResult: (_, {required isFinal}) {},
        onError: newErrors.add,
      ),
      throwsStateError,
    );
    await pumpEventQueue(times: 2);
    await recognizer.listen(
      onResult: (_, {required isFinal}) {},
      onError: newErrors.add,
    );

    driver.emitError(StateError('current new error'));
    expect(oldErrors, hasLength(1));
    expect(newErrors, hasLength(1));
    driver.emitStatus(SpeechToText.doneStatus);
    await pumpEventQueue(times: 2);
  });

  test('error 与同步 manual stop/cancel 复用同一 finishing 且不重复终止 driver', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    late Future<void> stopping;
    late Future<void> cancelling;
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (_, {required isFinal}) {},
      onError: (_) {
        stopping = recognizer.stop();
        cancelling = recognizer.cancel();
      },
    );

    driver.emitError(StateError('current error'));
    expect(identical(stopping, cancelling), isTrue);
    expect(driver.stopCount, 0);
    expect(driver.cancelCount, 0);

    driver.emitStatus(SpeechToText.doneStatus);
    await Future.wait(<Future<void>>[stopping, cancelling]);
    await recognizer.listen(onResult: (_, {required isFinal}) {});
  });

  test('pending manual stop 中到达 error 不覆盖已有 finishing', () async {
    final driver = _FakeWebSpeechDriver()..stopGate = Completer<void>();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final errors = <SpokenFormulaRecognitionException>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (_, {required isFinal}) {},
      onError: errors.add,
    );

    final stopping = recognizer.stop();
    driver.emitError(StateError('error during stop'));
    final repeatedStop = recognizer.stop();
    final cancelling = recognizer.cancel();
    expect(identical(stopping, repeatedStop), isTrue);
    expect(identical(stopping, cancelling), isTrue);
    expect(errors, hasLength(1));
    expect(driver.stopCount, 1);
    expect(driver.cancelCount, 0);

    driver.emitStatus(SpeechToText.doneStatus);
    driver.stopGate!.complete();
    await Future.wait(<Future<void>>[stopping, repeatedStop, cancelling]);
  });

  test('driver.listen throw 只发一次 typed error，排空后可 relisten', () async {
    final driver = _FakeWebSpeechDriver()
      ..listenError = StateError('browser start failure');
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final oldErrors = <SpokenFormulaRecognitionException>[];
    final newResults = <String>[];
    await recognizer.initialize();

    await recognizer.listen(
      onResult: (_, {required isFinal}) => fail('失败会话不应发出结果'),
      onError: oldErrors.add,
    );
    expect(oldErrors, hasLength(1));
    expect(oldErrors.single.message, isNot(contains('browser start failure')));

    await recognizer.listen(
      onResult: (words, {required isFinal}) => newResults.add(words),
    );
    driver.emit('late failed result', isFinal: true, listenIndex: 0);
    driver.emit('new result', isFinal: false, listenIndex: 1);
    expect(newResults, <String>['new result']);
  });

  test('旧 session 排空前 relisten 被拒绝且全局 error 仍归旧 session', () async {
    final driver = _FakeWebSpeechDriver();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final oldErrors = <SpokenFormulaRecognitionException>[];
    final newErrors = <SpokenFormulaRecognitionException>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (_, {required isFinal}) {},
      onError: oldErrors.add,
    );
    var stopCompleted = false;
    final stopping = recognizer.stop().then((_) => stopCompleted = true);
    driver.emitStatus(SpeechToText.notListeningStatus);
    await Future<void>.delayed(Duration.zero);
    expect(stopCompleted, isFalse);

    await expectLater(
      recognizer.listen(
        onResult: (_, {required isFinal}) {},
        onError: newErrors.add,
      ),
      throwsStateError,
    );
    driver.emitError(StateError('late old error'));
    expect(oldErrors, hasLength(1));
    expect(newErrors, isEmpty);

    driver.emitStatus(SpeechToText.doneStatus);
    await stopping;

    await recognizer.listen(
      onResult: (_, {required isFinal}) {},
      onError: newErrors.add,
    );

    driver.emitError(StateError('current error'));
    expect(oldErrors, hasLength(1));
    expect(newErrors, hasLength(1));
  });

  test('gated stop 期间到达 final 只转发一次且不再 fallback', () async {
    final driver = _FakeWebSpeechDriver()..stopGate = Completer<void>();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final results = <({String words, bool isFinal})>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (words, {required isFinal}) =>
          results.add((words: words, isFinal: isFinal)),
    );
    driver.emit('partial', isFinal: false);

    var stopCompleted = false;
    final stopping = recognizer.stop().then((_) => stopCompleted = true);
    driver.emit('native final', isFinal: true);
    driver.emitStatus(SpeechToText.doneStatus);
    await Future<void>.delayed(Duration.zero);
    expect(stopCompleted, isFalse);

    driver.stopGate!.complete();
    await stopping;
    expect(results, <({String words, bool isFinal})>[
      (words: 'partial', isFinal: false),
      (words: 'native final', isFinal: true),
    ]);
  });

  test('gated cancel 期间到达的 partial/final 都不会转成 final', () async {
    final driver = _FakeWebSpeechDriver()..cancelGate = Completer<void>();
    final recognizer = WebSpeechFormulaRecognizer(driver: driver);
    final results = <({String words, bool isFinal})>[];
    await recognizer.initialize();
    await recognizer.listen(
      onResult: (words, {required isFinal}) =>
          results.add((words: words, isFinal: isFinal)),
    );
    driver.emit('partial', isFinal: false);

    var cancelCompleted = false;
    final cancelling = recognizer.cancel().then((_) => cancelCompleted = true);
    driver.emit('late partial', isFinal: false);
    driver.emit('late final', isFinal: true);
    driver.emitStatus(SpeechToText.doneStatus);
    await Future<void>.delayed(Duration.zero);
    expect(cancelCompleted, isFalse);

    driver.cancelGate!.complete();
    await cancelling;
    expect(results, <({String words, bool isFinal})>[
      (words: 'partial', isFinal: false),
    ]);
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
    final stopping = recognizer.stop();
    driver.emitStatus(SpeechToText.doneStatus);
    await stopping;

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
  WebSpeechDriverErrorCallback? _errorListener;
  WebSpeechDriverStatusCallback? _statusListener;
  Completer<void>? stopGate;
  Completer<void>? cancelGate;
  Object? listenError;
  int stopCount = 0;
  int cancelCount = 0;

  @override
  Future<bool> initialize({
    required WebSpeechDriverErrorCallback onError,
    required WebSpeechDriverStatusCallback onStatus,
  }) async {
    _errorListener = onError;
    _statusListener = onStatus;
    return true;
  }

  @override
  Future<void> listen({required WebSpeechResultCallback onResult}) async {
    _callbacks.add(onResult);
    final error = listenError;
    listenError = null;
    if (error != null) throw error;
  }

  void emit(String words, {required bool isFinal, int? listenIndex}) {
    _callbacks[listenIndex ?? _callbacks.length - 1](words, isFinal: isFinal);
  }

  void emitError(Object error) => _errorListener!(error);

  void emitStatus(String status) => _statusListener!(status);

  @override
  Future<void> stop() async {
    stopCount += 1;
    await stopGate?.future;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    await cancelGate?.future;
  }
}

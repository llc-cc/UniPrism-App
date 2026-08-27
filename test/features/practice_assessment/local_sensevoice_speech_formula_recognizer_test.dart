import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/sensevoice_asr_client.dart';
import 'package:uniprism_app/features/practice_assessment/application/speech_formula_controller.dart';
import 'package:uniprism_app/features/practice_assessment/core/speech_audio_capture.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';

void main() {
  test('initialize 先检查服务健康状态再请求麦克风权限', () async {
    final events = <String>[];
    final capture = _FakeCapture(events: events);
    final client = _FakeAsrClient(events: events);
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);

    expect(await recognizer.initialize(), isTrue);
    expect(events, <String>['health', 'permission']);
  });

  test('initialize 健康检查失败时提供启动本机服务的安全原因', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient()..isHealthyResult = false;
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);

    expect(await recognizer.initialize(), isFalse);
    expect(
      recognizer.initializationError?.message,
      contains('启动本机 SenseVoice 服务'),
    );
    expect(
      recognizer.initializationError?.message,
      isNot(contains('127.0.0.1')),
    );
    expect(recognizer.initializationError?.message, isNot(contains('Chrome')));
    expect(capture.permissionCalls, 0);
  });

  test('initialize 健康检查异常也收敛为启动本机服务的安全原因', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient()..healthError = StateError('endpoint down');
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);

    expect(await recognizer.initialize(), isFalse);
    expect(
      recognizer.initializationError?.message,
      contains('启动本机 SenseVoice 服务'),
    );
    expect(
      recognizer.initializationError?.message,
      isNot(contains('endpoint')),
    );
    expect(capture.permissionCalls, 0);
  });

  test('initialize 麦克风权限失败时提供权限恢复原因', () async {
    final capture = _FakeCapture()..permissionResult = false;
    final client = _FakeAsrClient();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);

    expect(await recognizer.initialize(), isFalse);
    expect(recognizer.initializationError?.message, contains('麦克风权限'));
    expect(recognizer.initializationError?.message, isNot(contains('Chrome')));
    expect(recognizer.initializationError?.message, isNot(contains('Edge')));
  });

  test('initialize 重试成功后清除上一轮失败原因', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient()..isHealthyResult = false;
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    expect(await recognizer.initialize(), isFalse);
    expect(recognizer.initializationError, isNotNull);

    client.isHealthyResult = true;

    expect(await recognizer.initialize(), isTrue);
    expect(recognizer.initializationError, isNull);
  });

  test('listen 为每次录音建立新的 PCM 缓冲区', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient(transcripts: <String>['first', 'second']);
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);

    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) {},
    );
    capture.add(<int>[1, 2]);
    await recognizer.stop();
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) {},
    );
    capture.add(<int>[3, 4]);
    await recognizer.stop();

    expect(client.requests, hasLength(2));
    expect(client.requests[0].sublist(44), <int>[1, 2]);
    expect(client.requests[1].sublist(44), <int>[3, 4]);
  });

  test('listen 不丢失订阅时同步送达的首个 PCM chunk', () async {
    final capture = _FakeCapture(
      chunksOnListen: <List<int>>[
        <int>[1, 2],
      ],
    );
    final client = _FakeAsrClient(transcripts: <String>['sync chunk']);
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);

    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) {},
    );
    await recognizer.stop();

    expect(client.lastBytes!.sublist(44), <int>[1, 2]);
  });

  test('pending capture.start 取消收尾完成前新 listen 不得启动新 capture', () async {
    final startGate = Completer<void>();
    final capture = _FakeCapture(startGate: startGate);
    final client = _FakeAsrClient();
    final timerFactory = _ManualTimerFactory();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
      capture,
      client,
      timerFactory: timerFactory.call,
    );
    final firstListening = recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) => fail('不应发出结果'),
    );
    await _flushAsyncWork();

    var isCancelComplete = false;
    final cancelling = recognizer.cancel().then((_) => isCancelComplete = true);
    final secondListening = recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) {},
    );
    await _flushAsyncWork();
    final startsBeforeOldCleanup = capture.startCount;
    final cancelCompletedBeforeOldStart = isCancelComplete;

    startGate.complete();
    await Future.wait<void>(<Future<void>>[
      firstListening,
      cancelling,
      secondListening,
    ]);

    expect(startsBeforeOldCleanup, 1);
    expect(cancelCompletedBeforeOldStart, isFalse);
    expect(capture.startCount, 2);
    expect(capture.cancelCount, 1);
    expect(timerFactory.timers, hasLength(1));
    await recognizer.cancel();
  });

  test('stop 拼接安全副本并仅上传一次 WAV 后发出一个 final', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient(transcripts: <String>['x 的平方']);
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final results = <String>[];
    final finalFlags = <bool>[];
    final firstChunk = Uint8List.fromList(<int>[1, 2]);

    await recognizer.listen(
      onResult: (words, {required isFinal, processingElapsed}) {
        results.add(words);
        finalFlags.add(isFinal);
      },
    );
    capture.addBytes(firstChunk);
    firstChunk[0] = 99;
    capture.add(<int>[3, 4]);
    await recognizer.stop();

    expect(results, <String>['x 的平方']);
    expect(finalFlags, <bool>[true]);
    expect(client.callCount, 1);
    expect(client.lastBytes!.sublist(0, 4), 'RIFF'.codeUnits);
    expect(client.lastBytes!.sublist(44), <int>[1, 2, 3, 4]);
    expect(capture.stopCount, 1);
    expect(capture.subscriptionCancelCount, 1);
  });

  test('final processingElapsed 覆盖 capture stop、WAV 编码与 ASR', () async {
    var elapsed = Duration.zero;
    final stopGate = Completer<void>();
    final capture = _FakeCapture(stopGate: stopGate);
    final client = _FakeAsrClient()..transcribeGate = Completer<String>();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
      capture,
      client,
      processingClock: () => elapsed,
    );
    final observed = <Duration?>[];
    await recognizer.listen(
      onResult: (words, {required isFinal, processingElapsed}) =>
          observed.add(processingElapsed),
    );
    capture.add(<int>[1, 2]);

    final stopping = recognizer.stop();
    elapsed = const Duration(milliseconds: 300);
    stopGate.complete();
    await _flushAsyncWork();
    expect(client.callCount, 1);
    elapsed = const Duration(milliseconds: 750);
    client.transcribeGate!.complete('x 的平方');
    await stopping;

    expect(observed, <Duration?>[const Duration(milliseconds: 750)]);
  });

  test('stop 在 pending capture.start 时也从 finalization 发起点计时', () async {
    var elapsed = Duration.zero;
    final startGate = Completer<void>();
    final capture = _FakeCapture(
      startGate: startGate,
      chunksOnListen: <List<int>>[
        <int>[1, 2],
      ],
    );
    final client = _FakeAsrClient()..transcribeGate = Completer<String>();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
      capture,
      client,
      processingClock: () => elapsed,
    );
    final observed = <Duration?>[];
    final listening = recognizer.listen(
      onResult: (words, {required isFinal, processingElapsed}) =>
          observed.add(processingElapsed),
    );

    final stopping = recognizer.stop();
    elapsed = const Duration(milliseconds: 400);
    startGate.complete();
    await listening;
    await _flushAsyncWork();
    expect(client.callCount, 1);
    elapsed = const Duration(milliseconds: 900);
    client.transcribeGate!.complete('x 的平方');
    await stopping;

    expect(observed, <Duration?>[const Duration(milliseconds: 900)]);
  });

  test(
    'controller watchdog 覆盖 pending capture.start 且迟到 start 不改写错误',
    () async {
      final startGate = Completer<void>();
      final capture = _FakeCapture(startGate: startGate);
      final client = _FakeAsrClient();
      final repository = _RecordingResolutionRepository();
      final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
        capture,
        client,
      );
      final controller = SpeechFormulaController(
        recognizer: recognizer,
        repository: repository,
        totalDeadline: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);

      final starting = controller.startListening();
      await _flushAsyncWork();
      final stopping = controller.stopListening();
      await Future<void>.delayed(const Duration(milliseconds: 45));
      final statusAtDeadline = controller.state.status;
      final messageAtDeadline = controller.state.errorMessage;

      startGate.complete();
      await Future.wait<void>(<Future<void>>[starting, stopping]);
      await _flushAsyncWork();

      expect(statusAtDeadline, SpeechFormulaStatus.infrastructureError);
      expect(messageAtDeadline, contains('5 秒'));
      expect(capture.cancelCount, 1);
      expect(repository.callCount, 0);
      expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    },
  );

  test('controller watchdog 覆盖 gated capture.stop 且迟到收尾不能解析', () async {
    final stopGate = Completer<void>();
    final capture = _FakeCapture(stopGate: stopGate);
    final client = _FakeAsrClient(transcripts: <String>['迟到结果']);
    final repository = _RecordingResolutionRepository();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
      totalDeadline: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    capture.add(<int>[1, 2]);

    final stopping = controller.stopListening();
    await Future<void>.delayed(const Duration(milliseconds: 45));
    final statusAtDeadline = controller.state.status;
    stopGate.complete();
    await stopping;
    await _flushAsyncWork();

    expect(statusAtDeadline, SpeechFormulaStatus.infrastructureError);
    expect(capture.cancelCount, 1);
    expect(client.callCount, 0);
    expect(repository.callCount, 0);
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
  });

  test('controller watchdog 覆盖 gated ASR 且 late final 不能覆盖错误', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient()..transcribeGate = Completer<String>();
    final repository = _RecordingResolutionRepository();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
      totalDeadline: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    capture.add(<int>[1, 2]);

    final stopping = controller.stopListening();
    await _flushAsyncWork();
    expect(client.callCount, 1);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    final statusAtDeadline = controller.state.status;
    client.transcribeGate!.complete('迟到公式');
    await stopping;
    await _flushAsyncWork();

    expect(statusAtDeadline, SpeechFormulaStatus.infrastructureError);
    expect(capture.cancelCount, 1);
    expect(repository.callCount, 0);
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
  });

  test('并发 duplicate stop 共享同一个 in-flight Future 且不重复上传', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient()..transcribeGate = Completer<String>();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final results = <String>[];
    await recognizer.listen(
      onResult: (words, {required isFinal, processingElapsed}) =>
          results.add(words),
    );
    capture.add(<int>[1, 2]);

    final first = recognizer.stop();
    await _flushAsyncWork();
    final second = recognizer.stop();

    expect(identical(first, second), isTrue);
    expect(client.callCount, 1);
    client.transcribeGate!.complete('x 的平方');
    await Future.wait<void>(<Future<void>>[first, second]);
    expect(results, <String>['x 的平方']);
    expect(capture.stopCount, 1);
  });

  test('pending capture.start 期间 stop 仍共享单一 Future 并只 stop 一次', () async {
    final startGate = Completer<void>();
    final capture = _FakeCapture(startGate: startGate);
    final client = _FakeAsrClient();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final errors = <SpokenFormulaRecognitionException>[];
    final listening = recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) => fail('不应发出结果'),
      onError: errors.add,
    );

    final first = recognizer.stop();
    final second = recognizer.stop();
    expect(identical(first, second), isTrue);
    startGate.complete();
    await listening;
    await first;

    expect(capture.stopCount, 1);
    expect(capture.cancelCount, 0);
    expect(errors, hasLength(1));
  });

  test('auto stop 与 manual stop 同时发生仍只共享一次终止和上传', () async {
    final stopGate = Completer<void>();
    final capture = _FakeCapture(stopGate: stopGate);
    final client = _FakeAsrClient(transcripts: <String>['auto-manual']);
    final timerFactory = _ManualTimerFactory();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
      capture,
      client,
      timerFactory: timerFactory.call,
    );
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) {},
    );
    capture.add(<int>[1, 2]);

    timerFactory.timers.single.fire();
    await _flushAsyncWork();
    final firstManual = recognizer.stop();
    final secondManual = recognizer.stop();
    expect(identical(firstManual, secondManual), isTrue);
    expect(capture.stopCount, 1);
    stopGate.complete();
    await firstManual;

    expect(client.callCount, 1);
    expect(capture.stopCount, 1);
  });

  test('cancel 先失效 generation 并阻止迟到 HTTP 结果回调', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient()..transcribeGate = Completer<String>();
    final timerFactory = _ManualTimerFactory();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
      capture,
      client,
      timerFactory: timerFactory.call,
    );
    final results = <String>[];
    await recognizer.listen(
      onResult: (words, {required isFinal, processingElapsed}) =>
          results.add(words),
    );
    capture.add(<int>[1, 2]);
    final stopping = recognizer.stop();
    await _flushAsyncWork();

    final cancelling = recognizer.cancel();
    client.transcribeGate!.complete('late');
    await Future.wait<void>(<Future<void>>[stopping, cancelling]);

    expect(results, isEmpty);
    expect(capture.cancelCount, 1);
    expect(capture.subscriptionCancelCount, 1);
    expect(timerFactory.timers.single.isActive, isFalse);
  });

  test('默认 15 秒自动停止并发出 final transcript', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient(transcripts: <String>['auto result']);
    final timerFactory = _ManualTimerFactory();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
      capture,
      client,
      timerFactory: timerFactory.call,
    );
    final results = <String>[];
    await recognizer.listen(
      onResult: (words, {required isFinal, processingElapsed}) =>
          results.add(words),
    );
    capture.add(<int>[1, 2]);

    expect(timerFactory.delays, <Duration>[const Duration(seconds: 15)]);
    timerFactory.timers.single.fire();
    await _flushAsyncWork();

    expect(results, <String>['auto result']);
    expect(client.callCount, 1);
    expect(capture.stopCount, 1);
  });

  test('空 PCM 只通过 typed onError 发出精确安全错误', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final errors = <SpokenFormulaRecognitionException>[];
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) => fail('不应发出识别结果'),
      onError: errors.add,
    );

    await recognizer.stop();

    expect(errors, hasLength(1));
    expect(errors.single.message, '没有录到有效语音，请重新说一次。');
    expect(client.callCount, 0);
  });

  test('ASR failure 映射为安全 typed error 且不发 final', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient(
      transcribeError: const SenseVoiceAsrException('本地语音识别暂时不可用，请稍后重试。'),
    );
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final results = <String>[];
    final errors = <SpokenFormulaRecognitionException>[];
    await recognizer.listen(
      onResult: (words, {required isFinal, processingElapsed}) =>
          results.add(words),
      onError: errors.add,
    );
    capture.add(<int>[1, 2]);

    await recognizer.stop();

    expect(results, isEmpty);
    expect(errors.map((error) => error.message), <String>[
      '本地语音识别暂时不可用，请稍后重试。',
    ]);
  });

  test('PCM stream error 结束会话、释放资源且只发一次 typed error', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient();
    final timerFactory = _ManualTimerFactory();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
      capture,
      client,
      timerFactory: timerFactory.call,
    );
    final errors = <SpokenFormulaRecognitionException>[];
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) => fail('不应发出识别结果'),
      onError: errors.add,
    );

    capture.addError(StateError('driver detail'));
    await _flushAsyncWork();
    await recognizer.stop();

    expect(errors, hasLength(1));
    expect(errors.single.message, isNot(contains('driver detail')));
    expect(capture.cancelCount, 1);
    expect(capture.subscriptionCancelCount, 1);
    expect(timerFactory.timers.single.isActive, isFalse);
    expect(client.callCount, 0);
  });

  test('stream error cleanup 完成前拒绝 relisten，完成后允许新会话', () async {
    final subscriptionCancelGate = Completer<void>();
    final cancelGate = Completer<void>();
    final capture = _FakeCapture(
      subscriptionCancelGate: subscriptionCancelGate,
      cancelGate: cancelGate,
    );
    final client = _FakeAsrClient();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    Future<void>? immediateRelisten;
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) => fail('不应发出结果'),
      onError: (_) {
        immediateRelisten = recognizer.listen(
          onResult: (_, {required isFinal, processingElapsed}) {},
        );
      },
    );

    capture.addError(StateError('stream failed'));
    await expectLater(immediateRelisten, throwsStateError);
    final terminal = recognizer.stop();
    final duplicateTerminal = recognizer.stop();
    expect(identical(terminal, duplicateTerminal), isTrue);
    var isTerminalComplete = false;
    terminal.then((_) => isTerminalComplete = true);
    await _flushAsyncWork();
    expect(isTerminalComplete, isFalse);
    expect(capture.cancelCount, 0);

    subscriptionCancelGate.complete();
    await _flushAsyncWork();
    expect(capture.cancelCount, 1);
    expect(isTerminalComplete, isFalse);
    cancelGate.complete();
    await terminal;
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) {},
    );
    expect(capture.startCount, 2);
    await recognizer.cancel();
  });

  test('manual stop 中的 stream error 复用原 Future 且不重复终止 capture', () async {
    final stopGate = Completer<void>();
    final capture = _FakeCapture(stopGate: stopGate);
    final client = _FakeAsrClient();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final errors = <SpokenFormulaRecognitionException>[];
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) => fail('不应发出结果'),
      onError: errors.add,
    );
    capture.add(<int>[1, 2]);

    final manual = recognizer.stop();
    await _flushAsyncWork();
    capture.addError(StateError('stream failed during stop'));
    final afterError = recognizer.stop();

    expect(identical(manual, afterError), isTrue);
    expect(capture.stopCount, 1);
    expect(capture.cancelCount, 0);
    expect(errors, hasLength(1));
    stopGate.complete();
    await manual;
    expect(client.callCount, 0);
    expect(capture.subscriptionCancelCount, 1);
  });

  test('capture stop 与 WAV 编码错误均不会重复或泄露内部异常', () async {
    for (final fixture in <_FailureFixture>[
      _FailureFixture(stopError: StateError('plugin stop detail')),
      const _FailureFixture(bytes: <int>[1]),
    ]) {
      final capture = _FakeCapture()..stopError = fixture.stopError;
      final client = _FakeAsrClient();
      final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
        capture,
        client,
      );
      final errors = <SpokenFormulaRecognitionException>[];
      await recognizer.listen(
        onResult: (_, {required isFinal, processingElapsed}) =>
            fail('不应发出识别结果'),
        onError: errors.add,
      );
      if (fixture.bytes case final bytes?) capture.add(bytes);

      await recognizer.stop();
      await recognizer.stop();

      expect(errors, hasLength(1));
      expect(errors.single.message, isNot(contains('detail')));
      expect(client.callCount, 0);
    }
  });

  test('stop/transcribe 竞态中 cancel 后迟到成功和失败都不能回调', () async {
    for (final completesWithError in <bool>[false, true]) {
      final capture = _FakeCapture();
      final gate = Completer<String>();
      final client = _FakeAsrClient()..transcribeGate = gate;
      final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
        capture,
        client,
      );
      final results = <String>[];
      final errors = <SpokenFormulaRecognitionException>[];
      await recognizer.listen(
        onResult: (words, {required isFinal, processingElapsed}) =>
            results.add(words),
        onError: errors.add,
      );
      capture.add(<int>[1, 2]);
      final stopping = recognizer.stop();
      await _flushAsyncWork();

      final cancelling = recognizer.cancel();
      if (completesWithError) {
        gate.completeError(StateError('late failure'));
      } else {
        gate.complete('late success');
      }
      await Future.wait<void>(<Future<void>>[stopping, cancelling]);

      expect(results, isEmpty);
      expect(errors, isEmpty);
    }
  });

  test('onResult 抛错仍只产生一个 terminal 并完成资源释放', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient(transcripts: <String>['result']);
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    var resultCalls = 0;
    var errorCalls = 0;
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) {
        resultCalls += 1;
        throw StateError('consumer result failure');
      },
      onError: (_) => errorCalls += 1,
    );
    capture.add(<int>[1, 2]);

    await recognizer.stop();

    expect(resultCalls, 1);
    expect(errorCalls, 0);
    expect(capture.stopCount, 1);
    expect(capture.subscriptionCancelCount, 1);
  });

  test('stop error 的 onError 抛错不会逃逸或跳过资源释放', () async {
    final subscriptionCancelGate = Completer<void>();
    final capture = _FakeCapture(subscriptionCancelGate: subscriptionCancelGate)
      ..stopError = StateError('capture failure');
    final client = _FakeAsrClient();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    var errorCalls = 0;
    await recognizer.listen(
      onResult: (_, {required isFinal, processingElapsed}) => fail('不应发出结果'),
      onError: (_) {
        errorCalls += 1;
        throw StateError('consumer error failure');
      },
    );

    final stopping = recognizer.stop();
    var isStoppingComplete = false;
    stopping.then((_) => isStoppingComplete = true);
    await _flushAsyncWork();

    expect(errorCalls, 1);
    expect(capture.stopCount, 1);
    expect(capture.subscriptionCancelCount, 1);
    expect(isStoppingComplete, isFalse);
    subscriptionCancelGate.complete();
    await stopping;
  });

  test('stream error 的 onError 抛错不会成为 unhandled async error', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      final capture = _FakeCapture();
      final client = _FakeAsrClient();
      final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
        capture,
        client,
      );
      await recognizer.listen(
        onResult: (_, {required isFinal, processingElapsed}) => fail('不应发出结果'),
        onError: (_) => throw StateError('consumer stream error failure'),
      );

      capture.addError(StateError('stream failed'));
      await recognizer.stop();
      expect(capture.cancelCount, 1);
      expect(capture.subscriptionCancelCount, 1);
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });

  test('重复 dispose 活跃会话只释放资源一次且迟到转写不再回调', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient()..transcribeGate = Completer<String>();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final results = <String>[];
    final errors = <SpokenFormulaRecognitionException>[];
    await recognizer.listen(
      onResult: (words, {required isFinal, processingElapsed}) =>
          results.add(words),
      onError: errors.add,
    );
    capture.add(<int>[1, 2]);
    final stopping = recognizer.stop();
    await _flushAsyncWork();
    expect(client.callCount, 1);

    final firstDispose = recognizer.dispose();
    final secondDispose = recognizer.dispose();
    var isDisposeComplete = false;
    firstDispose.then((_) => isDisposeComplete = true);
    await _flushAsyncWork();
    final disposeCompletedBeforeOldStop = isDisposeComplete;

    client.transcribeGate!.complete('late result');
    await Future.wait<void>(<Future<void>>[
      stopping,
      firstDispose,
      secondDispose,
    ]);

    expect(disposeCompletedBeforeOldStop, isFalse);
    expect(capture.cancelCount, 1);
    expect(capture.disposeCount, 1);
    expect(client.disposeCount, 1);
    expect(capture.subscriptionCancelCount, 1);
    expect(results, isEmpty);
    expect(errors, isEmpty);
  });
}

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 5; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FailureFixture {
  const _FailureFixture({this.stopError, this.bytes});

  final Object? stopError;
  final List<int>? bytes;
}

final class _FakeCapture implements SpeechAudioCapture {
  _FakeCapture({
    this.events,
    this.startGate,
    this.stopGate,
    this.cancelGate,
    this.subscriptionCancelGate,
    this.chunksOnListen,
  });

  final List<String>? events;
  final Completer<void>? startGate;
  final Completer<void>? stopGate;
  final Completer<void>? cancelGate;
  final Completer<void>? subscriptionCancelGate;
  final List<List<int>>? chunksOnListen;
  final List<StreamController<Uint8List>> _controllers = [];
  Object? stopError;
  bool permissionResult = true;
  int permissionCalls = 0;
  int stopCount = 0;
  int cancelCount = 0;
  int subscriptionCancelCount = 0;
  int startCount = 0;
  int disposeCount = 0;

  StreamController<Uint8List> get _current => _controllers.last;

  @override
  Future<bool> requestPermission() async {
    permissionCalls += 1;
    events?.add('permission');
    return permissionResult;
  }

  @override
  Future<Stream<Uint8List>> start() async {
    startCount += 1;
    await startGate?.future;
    late final StreamController<Uint8List> controller;
    controller = StreamController<Uint8List>(
      sync: true,
      onListen: () {
        for (final chunk in chunksOnListen ?? const <List<int>>[]) {
          controller.add(Uint8List.fromList(chunk));
        }
      },
      onCancel: () {
        subscriptionCancelCount += 1;
        return subscriptionCancelGate?.future;
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }

  void add(List<int> bytes) => addBytes(Uint8List.fromList(bytes));

  void addBytes(Uint8List bytes) => _current.add(bytes);

  void addError(Object error) => _current.addError(error);

  @override
  Future<void> stop() async {
    stopCount += 1;
    await stopGate?.future;
    if (stopError case final error?) throw error;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    await cancelGate?.future;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class _FakeAsrClient implements SenseVoiceAsrApi {
  _FakeAsrClient({this.events, List<String>? transcripts, this.transcribeError})
    : _transcripts = transcripts ?? <String>[];

  final List<String>? events;
  final List<String> _transcripts;
  final Object? transcribeError;
  final List<Uint8List> requests = <Uint8List>[];
  Completer<String>? transcribeGate;
  bool isHealthyResult = true;
  Object? healthError;
  int disposeCount = 0;

  int get callCount => requests.length;
  Uint8List? get lastBytes => requests.lastOrNull;

  @override
  Future<bool> isHealthy() async {
    events?.add('health');
    if (healthError case final error?) throw error;
    return isHealthyResult;
  }

  @override
  Future<String> transcribe(Uint8List wavBytes) async {
    requests.add(Uint8List.fromList(wavBytes));
    if (transcribeError case final error?) throw error;
    if (transcribeGate case final gate?) return gate.future;
    return _transcripts.removeAt(0);
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class _RecordingResolutionRepository
    implements SpokenFormulaResolutionRepository {
  int callCount = 0;

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async {
    callCount += 1;
    return SpokenFormulaResolution(
      resolutionId: 'late-resolution',
      recognizedText: text,
      normalizedText: text,
      outcome: SpokenFormulaOutcome.resolved,
      candidates: const <SpokenFormulaCandidate>[
        SpokenFormulaCandidate(
          id: 'late-candidate',
          latex: 'x^2',
          spokenBack: 'x 的平方',
        ),
      ],
      clarification: null,
      warnings: const <String>[],
    );
  }
}

final class _ManualTimerFactory {
  final List<Duration> delays = <Duration>[];
  final List<_ManualTimer> timers = <_ManualTimer>[];

  Timer call(Duration delay, void Function() callback) {
    delays.add(delay);
    final timer = _ManualTimer(callback);
    timers.add(timer);
    return timer;
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _isActive = true;

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _callback();
  }

  @override
  void cancel() => _isActive = false;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _isActive ? 0 : 1;
}

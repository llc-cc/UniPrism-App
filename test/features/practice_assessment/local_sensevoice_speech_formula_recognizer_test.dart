import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/sensevoice_asr_client.dart';
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

  test('listen 为每次录音建立新的 PCM 缓冲区', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient(transcripts: <String>['first', 'second']);
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);

    await recognizer.listen(onResult: (_, {required isFinal}) {});
    capture.add(<int>[1, 2]);
    await recognizer.stop();
    await recognizer.listen(onResult: (_, {required isFinal}) {});
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

    await recognizer.listen(onResult: (_, {required isFinal}) {});
    await recognizer.stop();

    expect(client.lastBytes!.sublist(44), <int>[1, 2]);
  });

  test('cancel 与 pending capture.start 竞态只取消一次且不启动 timer', () async {
    final startGate = Completer<void>();
    final capture = _FakeCapture(startGate: startGate);
    final client = _FakeAsrClient();
    final timerFactory = _ManualTimerFactory();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(
      capture,
      client,
      timerFactory: timerFactory.call,
    );
    final listening = recognizer.listen(
      onResult: (_, {required isFinal}) => fail('不应发出结果'),
    );

    await recognizer.cancel();
    startGate.complete();
    await listening;

    expect(capture.cancelCount, 1);
    expect(timerFactory.timers, isEmpty);
  });

  test('stop 拼接安全副本并仅上传一次 WAV 后发出一个 final', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient(transcripts: <String>['x 的平方']);
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final results = <String>[];
    final finalFlags = <bool>[];
    final firstChunk = Uint8List.fromList(<int>[1, 2]);

    await recognizer.listen(
      onResult: (words, {required isFinal}) {
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

  test('并发 duplicate stop 共享同一个 in-flight Future 且不重复上传', () async {
    final capture = _FakeCapture();
    final client = _FakeAsrClient()..transcribeGate = Completer<String>();
    final recognizer = LocalSenseVoiceSpeechFormulaRecognizer(capture, client);
    final results = <String>[];
    await recognizer.listen(
      onResult: (words, {required isFinal}) => results.add(words),
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
      onResult: (words, {required isFinal}) => results.add(words),
    );
    capture.add(<int>[1, 2]);
    final stopping = recognizer.stop();
    await _flushAsyncWork();

    await recognizer.cancel();
    client.transcribeGate!.complete('late');
    await stopping;

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
      onResult: (words, {required isFinal}) => results.add(words),
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
      onResult: (_, {required isFinal}) => fail('不应发出识别结果'),
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
      onResult: (words, {required isFinal}) => results.add(words),
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
      onResult: (_, {required isFinal}) => fail('不应发出识别结果'),
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
        onResult: (_, {required isFinal}) => fail('不应发出识别结果'),
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
        onResult: (words, {required isFinal}) => results.add(words),
        onError: errors.add,
      );
      capture.add(<int>[1, 2]);
      final stopping = recognizer.stop();
      await _flushAsyncWork();

      await recognizer.cancel();
      if (completesWithError) {
        gate.completeError(StateError('late failure'));
      } else {
        gate.complete('late success');
      }
      await stopping;

      expect(results, isEmpty);
      expect(errors, isEmpty);
    }
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
  _FakeCapture({this.events, this.startGate, this.chunksOnListen});

  final List<String>? events;
  final Completer<void>? startGate;
  final List<List<int>>? chunksOnListen;
  final List<StreamController<Uint8List>> _controllers = [];
  Object? stopError;
  int stopCount = 0;
  int cancelCount = 0;
  int subscriptionCancelCount = 0;

  StreamController<Uint8List> get _current => _controllers.last;

  @override
  Future<bool> requestPermission() async {
    events?.add('permission');
    return true;
  }

  @override
  Future<Stream<Uint8List>> start() async {
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
        return null;
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
    if (stopError case final error?) throw error;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
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

  int get callCount => requests.length;
  Uint8List? get lastBytes => requests.lastOrNull;

  @override
  Future<bool> isHealthy() async {
    events?.add('health');
    return true;
  }

  @override
  Future<String> transcribe(Uint8List wavBytes) async {
    requests.add(Uint8List.fromList(wavBytes));
    if (transcribeError case final error?) throw error;
    if (transcribeGate case final gate?) return gate.future;
    return _transcripts.removeAt(0);
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

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/record_speech_audio_capture.dart';

void main() {
  test('授予录音权限时只向插件请求一次权限', () async {
    final driver = _FakeSpeechRecordDriver(hasPermissionResult: true);
    final capture = RecordSpeechAudioCapture(driver: driver);

    expect(await capture.requestPermission(), isTrue);
    expect(driver.hasPermissionCalls, 1);
    expect(driver.startStreamCalls, 0);
  });

  test('拒绝录音权限时返回 false 且不开始录音', () async {
    final driver = _FakeSpeechRecordDriver(hasPermissionResult: false);
    final capture = RecordSpeechAudioCapture(driver: driver);

    expect(await capture.requestPermission(), isFalse);
    expect(driver.hasPermissionCalls, 1);
    expect(driver.startStreamCalls, 0);
  });

  test('不支持 PCM16 时在开始录音前抛出 StateError', () async {
    final driver = _FakeSpeechRecordDriver(isPcm16Supported: false);
    final capture = RecordSpeechAudioCapture(driver: driver);

    await expectLater(capture.start(), throwsA(isA<StateError>()));
    expect(driver.checkedEncoder, AudioEncoder.pcm16bits);
    expect(driver.startStreamCalls, 0);
  });

  test('开始录音时请求并确认单声道 16kHz PCM16 流', () async {
    final driver = _FakeSpeechRecordDriver(
      effectiveConfigOnStart: _pcm16Config(),
    );
    final capture = RecordSpeechAudioCapture(driver: driver);

    final stream = await capture.start();

    expect(stream, same(driver.audioStream));
    expect(driver.setConfigHandlerCalls, 1);
    expect(driver.requestedConfig?.encoder, AudioEncoder.pcm16bits);
    expect(driver.requestedConfig?.sampleRate, 16000);
    expect(driver.requestedConfig?.numChannels, 1);
    expect(driver.requestedConfig?.autoGain, isTrue);
    expect(driver.requestedConfig?.echoCancel, isTrue);
    expect(driver.requestedConfig?.noiseSuppress, isTrue);
  });

  test('浏览器返回 48kHz 单声道 PCM16 时降采样为 16kHz', () async {
    final driver = _FakeSpeechRecordDriver(
      effectiveConfigOnStart: const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 48000,
        numChannels: 1,
      ),
      audioStream: Stream<Uint8List>.value(
        _pcm16(<int>[3000, 6000, 9000, -3000, -6000, -9000]),
      ),
    );
    final capture = RecordSpeechAudioCapture(driver: driver);

    final stream = await capture.start();

    expect(
      await stream.expand((chunk) => chunk).toList(),
      _pcm16(<int>[6000, -6000]),
    );
    expect(driver.cancelCalls, 0);
  });

  test('浏览器返回 16kHz 双声道 PCM16 时混合为单声道', () async {
    final driver = _FakeSpeechRecordDriver(
      effectiveConfigOnStart: const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 2,
      ),
      audioStream: Stream<Uint8List>.fromIterable(<Uint8List>[
        _pcm16(<int>[1000, 3000, -3000]),
        _pcm16(<int>[-1000]),
      ]),
    );
    final capture = RecordSpeechAudioCapture(driver: driver);

    final stream = await capture.start();

    expect(
      await stream.expand((chunk) => chunk).toList(),
      _pcm16(<int>[2000, -2000]),
    );
    expect(driver.cancelCalls, 0);
  });

  test('有效配置为非 PCM16 的 16kHz 单声道时取消且不交付流', () async {
    final driver = _FakeSpeechRecordDriver(
      effectiveConfigOnStart: const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    final capture = RecordSpeechAudioCapture(driver: driver);

    await expectLater(capture.start(), throwsA(isA<StateError>()));
    expect(driver.cancelCalls, 1);
    expect(driver.stopCalls, 0);
  });

  test('停止会使尚未完成的启动失效，并在启动后调用插件停止', () async {
    final driver = _FakeSpeechRecordDriver.withPendingStart();
    final capture = RecordSpeechAudioCapture(driver: driver);

    final start = capture.start();
    await driver.startRequested.future;
    final stop = capture.stop();
    var stopCompleted = false;
    unawaited(stop.whenComplete(() => stopCompleted = true));
    await _flushAsyncWork();
    expect(stopCompleted, isFalse);

    driver.completePendingStart();
    await stop;

    await expectLater(start, throwsA(isA<StateError>()));
    expect(driver.stopCalls, 1);
    expect(driver.cancelCalls, 0);
  });

  test('取消会使尚未完成的启动失效，并在启动后调用插件取消', () async {
    final driver = _FakeSpeechRecordDriver.withPendingStart();
    final capture = RecordSpeechAudioCapture(driver: driver);

    final start = capture.start();
    await driver.startRequested.future;
    final cancel = capture.cancel();
    await _flushAsyncWork();
    expect(driver.cancelCalls, 0);

    driver.completePendingStart();
    await cancel;

    await expectLater(start, throwsA(isA<StateError>()));
    expect(driver.cancelCalls, 1);
    expect(driver.stopCalls, 0);
  });

  test('重复启动不会替换正在启动的录音流', () async {
    final driver = _FakeSpeechRecordDriver.withPendingStart();
    final capture = RecordSpeechAudioCapture(driver: driver);

    final firstStart = capture.start();
    final secondStart = capture.start();
    expect(identical(firstStart, secondStart), isTrue);
    await driver.startRequested.future;

    driver.completePendingStart();
    expect(await firstStart, same(driver.audioStream));
    expect(driver.startStreamCalls, 1);
  });

  test('重复启动不会替换已交付的录音流', () async {
    final driver = _FakeSpeechRecordDriver(
      effectiveConfigOnStart: _pcm16Config(),
    );
    final capture = RecordSpeechAudioCapture(driver: driver);

    final activeStream = await capture.start();

    await expectLater(capture.start(), throwsA(isA<StateError>()));
    expect(activeStream, same(driver.audioStream));
    expect(driver.startStreamCalls, 1);
  });

  test('启动插件异常原样传递，之后可以重新启动', () async {
    final error = StateError('plugin start failed');
    final driver = _FakeSpeechRecordDriver(
      startError: error,
      effectiveConfigOnStart: _pcm16Config(),
    );
    final capture = RecordSpeechAudioCapture(driver: driver);

    await expectLater(capture.start(), throwsA(same(error)));
    driver.startError = null;

    expect(await capture.start(), same(driver.audioStream));
    expect(driver.startStreamCalls, 2);
  });

  test('权限插件异常原样传递', () async {
    final error = StateError('permission failed');
    final driver = _FakeSpeechRecordDriver(hasPermissionError: error);
    final capture = RecordSpeechAudioCapture(driver: driver);

    await expectLater(capture.requestPermission(), throwsA(same(error)));
  });

  test('停止插件异常原样传递', () async {
    final error = StateError('stop failed');
    final driver = _FakeSpeechRecordDriver(stopError: error);
    final capture = RecordSpeechAudioCapture(driver: driver);

    await expectLater(capture.stop(), throwsA(same(error)));
  });

  test('停止插件异常后仍可重新启动', () async {
    final driver = _FakeSpeechRecordDriver(
      effectiveConfigOnStart: _pcm16Config(),
    );
    final capture = RecordSpeechAudioCapture(driver: driver);
    await capture.start();
    driver.stopError = StateError('stop failed');

    await expectLater(capture.stop(), throwsA(isA<StateError>()));
    driver.stopError = null;

    expect(await capture.start(), same(driver.audioStream));
  });

  test('取消插件异常原样传递', () async {
    final error = StateError('cancel failed');
    final driver = _FakeSpeechRecordDriver(cancelError: error);
    final capture = RecordSpeechAudioCapture(driver: driver);

    await expectLater(capture.cancel(), throwsA(same(error)));
  });

  test('重复 dispose 活跃采集只取消一次、转发 driver dispose 并拒绝新启动', () async {
    final driver = _FakeSpeechRecordDriver(
      effectiveConfigOnStart: _pcm16Config(),
    );
    final capture = RecordSpeechAudioCapture(driver: driver);
    await capture.start();

    await Future.wait<void>(<Future<void>>[
      capture.dispose(),
      capture.dispose(),
    ]);

    expect(driver.cancelCalls, 1);
    expect(driver.disposeCalls, 1);
    await expectLater(capture.start(), throwsStateError);
  });
}

RecordConfig _pcm16Config() => const RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  autoGain: true,
  echoCancel: true,
  noiseSuppress: true,
);

Uint8List _pcm16(List<int> samples) {
  final bytes = Uint8List(samples.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < samples.length; index += 1) {
    data.setInt16(index * 2, samples[index], Endian.little);
  }
  return bytes;
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _FakeSpeechRecordDriver implements SpeechRecordDriver {
  _FakeSpeechRecordDriver({
    this.hasPermissionResult = true,
    this.isPcm16Supported = true,
    this.effectiveConfigOnStart,
    this.startError,
    this.hasPermissionError,
    this.stopError,
    this.cancelError,
    Stream<Uint8List>? audioStream,
  }) : audioStream = audioStream ?? Stream<Uint8List>.empty(),
       _pendingStart = null;

  _FakeSpeechRecordDriver.withPendingStart()
    : hasPermissionResult = true,
      isPcm16Supported = true,
      effectiveConfigOnStart = null,
      hasPermissionError = null,
      stopError = null,
      cancelError = null,
      audioStream = const Stream<Uint8List>.empty(),
      _pendingStart = Completer<Stream<Uint8List>>();

  final bool hasPermissionResult;
  final bool isPcm16Supported;
  final RecordConfig? effectiveConfigOnStart;
  final Object? hasPermissionError;
  Object? stopError;
  final Object? cancelError;
  final Stream<Uint8List> audioStream;
  final Completer<void> startRequested = Completer<void>();
  final Completer<Stream<Uint8List>>? _pendingStart;

  Object? startError;
  void Function(RecordConfig)? _onConfigChanged;
  AudioEncoder? checkedEncoder;
  RecordConfig? requestedConfig;
  int hasPermissionCalls = 0;
  int setConfigHandlerCalls = 0;
  int startStreamCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;

  @override
  Future<bool> hasPermission() async {
    hasPermissionCalls += 1;
    final error = hasPermissionError;
    if (error != null) throw error;
    return hasPermissionResult;
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    checkedEncoder = encoder;
    return isPcm16Supported;
  }

  @override
  Future<void> setOnConfigChanged(void Function(RecordConfig)? handler) async {
    setConfigHandlerCalls += 1;
    _onConfigChanged = handler;
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startStreamCalls += 1;
    requestedConfig = config;
    if (!startRequested.isCompleted) startRequested.complete();
    final effectiveConfig = effectiveConfigOnStart;
    if (effectiveConfig != null) _onConfigChanged?.call(effectiveConfig);
    final error = startError;
    if (error != null) throw error;
    return _pendingStart?.future ?? audioStream;
  }

  void completePendingStart() => _pendingStart!.complete(audioStream);

  @override
  Future<void> stop() async {
    stopCalls += 1;
    final error = stopError;
    if (error != null) throw error;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    final error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

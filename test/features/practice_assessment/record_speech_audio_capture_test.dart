import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/record_speech_audio_capture.dart';

void main() {
  test('权限被拒绝时返回 false 而不开始录音', () async {
    final driver = _FakeSpeechRecordDriver(hasPermissionResult: false);
    final capture = RecordSpeechAudioCapture(driver: driver);

    expect(await capture.requestPermission(), isFalse);
    expect(driver.startStreamCalls, 0);
  });

  test('不支持 PCM16 时在开始录音前抛出 StateError', () async {
    final driver = _FakeSpeechRecordDriver(isPcm16Supported: false);
    final capture = RecordSpeechAudioCapture(driver: driver);

    await expectLater(capture.start(), throwsA(isA<StateError>()));
    expect(driver.checkedEncoder, AudioEncoder.pcm16bits);
    expect(driver.startStreamCalls, 0);
  });

  test('开始录音时请求单声道 16kHz PCM16 流', () async {
    final driver = _FakeSpeechRecordDriver();
    final capture = RecordSpeechAudioCapture(driver: driver);

    final stream = await capture.start();

    expect(stream, same(driver.audioStream));
    expect(driver.requestedConfig?.encoder, AudioEncoder.pcm16bits);
    expect(driver.requestedConfig?.sampleRate, 16000);
    expect(driver.requestedConfig?.numChannels, 1);
    expect(driver.requestedConfig?.autoGain, isTrue);
    expect(driver.requestedConfig?.echoCancel, isTrue);
    expect(driver.requestedConfig?.noiseSuppress, isTrue);
  });

  test('停止录音会转发给插件驱动', () async {
    final driver = _FakeSpeechRecordDriver();
    final capture = RecordSpeechAudioCapture(driver: driver);

    await capture.stop();

    expect(driver.stopCalls, 1);
  });

  test('取消录音只转发取消而不停止', () async {
    final driver = _FakeSpeechRecordDriver();
    final capture = RecordSpeechAudioCapture(driver: driver);

    await capture.cancel();

    expect(driver.cancelCalls, 1);
    expect(driver.stopCalls, 0);
  });

  test('插件启动异常会原样传递给调用方', () async {
    final error = StateError('plugin start failed');
    final driver = _FakeSpeechRecordDriver(startError: error);
    final capture = RecordSpeechAudioCapture(driver: driver);

    await expectLater(capture.start(), throwsA(same(error)));
  });
}

final class _FakeSpeechRecordDriver implements SpeechRecordDriver {
  _FakeSpeechRecordDriver({
    this.hasPermissionResult = true,
    this.isPcm16Supported = true,
    this.startError,
  });

  final bool hasPermissionResult;
  final bool isPcm16Supported;
  final Object? startError;
  final Stream<Uint8List> audioStream = Stream<Uint8List>.empty();

  AudioEncoder? checkedEncoder;
  RecordConfig? requestedConfig;
  int startStreamCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<bool> hasPermission() async => hasPermissionResult;

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    checkedEncoder = encoder;
    return isPcm16Supported;
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startStreamCalls += 1;
    requestedConfig = config;
    final error = startError;
    if (error != null) throw error;
    return audioStream;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }
}

import 'dart:typed_data';

import 'package:record/record.dart';

import '../core/speech_audio_capture.dart';

/// 隔离 record 插件的生产边界；替换实现时不会让采集端口或上层业务耦合插件 API。
abstract interface class SpeechRecordDriver {
  Future<bool> hasPermission();

  Future<bool> isEncoderSupported(AudioEncoder encoder);

  Future<Stream<Uint8List>> startStream(RecordConfig config);

  Future<void> stop();

  Future<void> cancel();
}

/// 使用 record 插件捕获 SenseVoice 所需的单声道 PCM16 数据流。
final class RecordSpeechAudioCapture implements SpeechAudioCapture {
  RecordSpeechAudioCapture({SpeechRecordDriver? driver})
    : _driver = driver ?? _PluginRecordDriver();

  final SpeechRecordDriver _driver;

  @override
  Future<bool> requestPermission() => _driver.hasPermission();

  @override
  Future<Stream<Uint8List>> start() async {
    final isPcm16Supported = await _driver.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    if (!isPcm16Supported) {
      throw StateError('当前平台不支持 PCM16 音频流录制');
    }
    return _driver.startStream(_config);
  }

  @override
  Future<void> stop() => _driver.stop();

  @override
  Future<void> cancel() {
    // 取消与停止语义不同：调用方会丢弃这次采集，不能将残留音频当作完成录音。
    return _driver.cancel();
  }

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
  );
}

/// 仅在适配器内部持有插件实例，避免插件异常被包装或吞掉，供上层决定提示与重试策略。
final class _PluginRecordDriver implements SpeechRecordDriver {
  _PluginRecordDriver() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) =>
      _recorder.isEncoderSupported(encoder);

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      _recorder.startStream(config);

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();
}

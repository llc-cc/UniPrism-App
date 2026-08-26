import 'dart:typed_data';

/// 语音采集边界：上层只接收 PCM16 数据流，不依赖具体浏览器或原生录音插件。
abstract interface class SpeechAudioCapture {
  Future<bool> requestPermission();

  Future<Stream<Uint8List>> start();

  Future<void> stop();

  Future<void> cancel();
}

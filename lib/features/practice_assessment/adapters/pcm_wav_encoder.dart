import 'dart:typed_data';

/// 将单声道 PCM16 字节流封装为确定性的 RIFF/WAV；PCM 必须保持完整 16 位采样，
/// 以免最后半个采样被错误地解释为音频数据。
Uint8List encodePcm16MonoWav(Uint8List pcm, {int sampleRate = 16000}) {
  if (pcm.length.isOdd) {
    throw ArgumentError.value(pcm.length, 'pcm.length', '必须是完整的 PCM16 采样');
  }
  // RIFF 头的 byteRate 是无符号 32 位字段，单声道 PCM16 每秒固定两个字节。
  if (sampleRate <= 0 || sampleRate > 0x7fffffff) {
    throw ArgumentError.value(sampleRate, 'sampleRate', '无法写入 WAV 字节率字段');
  }

  const channels = 1;
  const bitsPerSample = 16;
  final output = Uint8List(44 + pcm.length);
  final data = ByteData.sublistView(output);

  void writeAscii(int offset, String value) {
    output.setRange(offset, offset + value.length, value.codeUnits);
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
  data.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, pcm.length, Endian.little);
  output.setRange(44, output.length, pcm);
  return output;
}

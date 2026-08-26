import 'dart:typed_data';

/// 在 RIFF 的 32 位 chunkSize 中可写入的最大偶数 PCM16 负载字节数。
const maxPcm16MonoWavLength = 0xffffffda;

/// 校验 PCM16 负载既能构成完整采样，也能在不分配大数组时安全写入 RIFF 头。
void validatePcm16MonoWavLength(int pcmLength) {
  if (pcmLength < 0 || pcmLength.isOdd || pcmLength > maxPcm16MonoWavLength) {
    throw ArgumentError.value(pcmLength, 'pcm.length', '无法写入 PCM16 WAV');
  }
}

/// 将单声道 PCM16 字节流封装为确定性的 RIFF/WAV；PCM 必须保持完整 16 位采样，
/// 以免最后半个采样被错误地解释为音频数据。
Uint8List encodePcm16MonoWav(Uint8List pcm, {int sampleRate = 16000}) {
  validatePcm16MonoWavLength(pcm.length);
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

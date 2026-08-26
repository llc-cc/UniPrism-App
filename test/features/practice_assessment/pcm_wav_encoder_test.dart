import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/pcm_wav_encoder.dart';

void main() {
  test('PCM16 单声道被编码为 16kHz WAV', () {
    final wav = encodePcm16MonoWav(Uint8List.fromList(<int>[0, 0, 1, 0]));
    final data = ByteData.sublistView(wav);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(data.getUint32(4, Endian.little), 40);
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
    expect(data.getUint32(16, Endian.little), 16);
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint32(28, Endian.little), 32000);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint16(32, Endian.little), 2);
    expect(data.getUint16(34, Endian.little), 16);
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    expect(data.getUint32(40, Endian.little), 4);
    expect(wav.sublist(44), <int>[0, 0, 1, 0]);
  });

  test('奇数个字节的 PCM 被拒绝', () {
    expect(
      () => encodePcm16MonoWav(Uint8List.fromList(<int>[0])),
      throwsArgumentError,
    );
  });

  test('非正采样率被拒绝', () {
    expect(
      () => encodePcm16MonoWav(Uint8List(0), sampleRate: 0),
      throwsArgumentError,
    );
  });

  test('会使 WAV 字节率溢出的采样率被拒绝', () {
    expect(
      () => encodePcm16MonoWav(Uint8List(0), sampleRate: 0x80000000),
      throwsArgumentError,
    );
  });

  test('RIFF 可表示的最大偶数 PCM 长度合法', () {
    expect(() => validatePcm16MonoWavLength(0xffffffda), returnsNormally);
  });

  test('超过 RIFF 可表示范围的 PCM 长度被拒绝', () {
    expect(() => validatePcm16MonoWavLength(0xffffffdc), throwsArgumentError);
  });
}

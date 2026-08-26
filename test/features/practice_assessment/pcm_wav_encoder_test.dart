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
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint16(34, Endian.little), 16);
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
}

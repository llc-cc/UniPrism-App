import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/sensevoice_asr_client.dart';

void main() {
  test('健康检查只接受 2xx', () async {
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient(
        (request) async => http.Response('{"status":"ok"}', 200),
      ),
    );

    expect(await client.isHealthy(), isTrue);
  });

  test('健康检查将非 2xx 和网络失败视为不健康', () async {
    final non2xxClient = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async => http.Response('unavailable', 503)),
    );
    final failedClient = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async => throw StateError('network failed')),
    );

    expect(await non2xxClient.isHealthy(), isFalse);
    expect(await failedClient.isHealthy(), isFalse);
  });

  test('转写上传 canonical WAV 并返回清洗后的 text', () async {
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000/',
      client: MockClient.streaming((request, bodyStream) async {
        expect(request.url.path, '/v1/audio/transcriptions');
        expect(request.method, 'POST');
        final body = await bodyStream.transform(latin1.decoder).join();
        expect(body, contains('name="model"'));
        expect(body, contains('sensevoice'));
        expect(body, contains('name="response_format"'));
        expect(body, contains('json'));
        expect(body, contains('filename="formula.wav"'));
        expect(body, contains('content-type: audio/wav'));
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('{"text":"  x 的平方  "}')),
          200,
        );
      }),
    );

    expect(await client.transcribe(_canonicalWav()), 'x 的平方');
  });

  test('超过 5MB 的载荷在发送前被拒绝', () async {
    var wasSent = false;
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async {
        wasSent = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.transcribe(Uint8List(5 * 1024 * 1024 + 1)),
      throwsA(isA<SenseVoiceAsrException>()),
    );
    expect(wasSent, isFalse);
  });

  test('超过 15 秒的 canonical WAV 在发送前被拒绝', () async {
    var wasSent = false;
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async {
        wasSent = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.transcribe(_canonicalWav(pcmLength: 480002)),
      throwsA(isA<SenseVoiceAsrException>()),
    );
    expect(wasSent, isFalse);
  });

  test('恰好 15 秒的 canonical WAV 会发送', () async {
    var wasSent = false;
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async {
        wasSent = true;
        return http.Response('{"text":"ok"}', 200);
      }),
    );

    expect(await client.transcribe(_canonicalWav(pcmLength: 480000)), 'ok');
    expect(wasSent, isTrue);
  });

  test('畸形 WAV 在发送前被拒绝', () async {
    var wasSent = false;
    final malformedWav = _canonicalWav();
    ByteData.sublistView(malformedWav).setUint32(40, 4, Endian.little);
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async {
        wasSent = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.transcribe(malformedWav),
      throwsA(isA<SenseVoiceAsrException>()),
    );
    expect(wasSent, isFalse);
  });

  test('非 2xx 响应不会泄露服务端 body', () async {
    const serverBody = 'internal trace: secret-model-path';
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async => http.Response(serverBody, 500)),
    );

    try {
      await client.transcribe(_canonicalWav());
      fail('应拒绝非 2xx 响应');
    } on SenseVoiceAsrException catch (error) {
      expect(error.message, isNot(contains(serverBody)));
      expect(error.message, isNot(contains('127.0.0.1')));
    }
  });

  test('坏 JSON 响应被拒绝', () async {
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async => http.Response('{not-json', 200)),
    );

    await expectLater(
      client.transcribe(_canonicalWav()),
      throwsA(isA<SenseVoiceAsrException>()),
    );
  });

  test('空白 text 响应被拒绝', () async {
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async => http.Response('{"text":"  "}', 200)),
    );

    await expectLater(
      client.transcribe(_canonicalWav()),
      throwsA(isA<SenseVoiceAsrException>()),
    );
  });

  test('超过 64KB 的响应会在读取上限处被拒绝', () async {
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(<List<int>>[
            List<int>.filled(64 * 1024, 97),
            <int>[98],
          ]),
          200,
        );
      }),
    );

    await expectLater(
      client.transcribe(_canonicalWav()),
      throwsA(isA<SenseVoiceAsrException>()),
    );
  });

  test('发送超时映射为安全的超时提示', () async {
    final pendingResponse = Completer<http.Response>();
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((request) => pendingResponse.future),
    );

    await _expectTimeout(client.transcribe(_canonicalWav()));
  });

  test('响应流超时映射为安全的超时提示', () async {
    final responseController = StreamController<List<int>>();
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      timeout: const Duration(milliseconds: 10),
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(responseController.stream, 200);
      }),
    );

    await _expectTimeout(client.transcribe(_canonicalWav()));
    await responseController.close();
  });
}

Future<void> _expectTimeout(Future<String> transcription) async {
  try {
    await transcription;
    fail('应抛出超时异常');
  } on SenseVoiceAsrException catch (error) {
    expect(error.message, '本地语音识别超时，请重新说一次。');
  }
}

Uint8List _canonicalWav({int pcmLength = 2}) {
  final wav = Uint8List(44 + pcmLength);
  final data = ByteData.sublistView(wav);

  void writeAscii(int offset, String value) {
    wav.setRange(offset, offset + value.length, value.codeUnits);
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + pcmLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, pcmLength, Endian.little);
  return wav;
}

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
      client: MockClient((request) async {
        expect(request.url, Uri.parse('http://127.0.0.1:8000/health'));
        return http.Response('{"status":"ok"}', 200);
      }),
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
      client: MockClient(
        (request) async => http.Response('{"text":"  "}', 200),
      ),
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
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      timeout: const Duration(milliseconds: 10),
      client: _AbortObservingClient.pendingSend(),
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

  test('multipart 精确传递三个协议部分和原始 WAV 字节', () async {
    final wav = _canonicalWav();
    final client = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000/',
      client: MockClient.streaming((request, bodyStream) async {
        expect(
          request.url,
          Uri.parse('http://127.0.0.1:8000/v1/audio/transcriptions'),
        );
        final parts = _parseMultipart(
          await bodyStream.toBytes(),
          request.headers['content-type']!,
        );
        expect(parts, hasLength(3));
        expect(parts[0].name, 'model');
        expect(utf8.decode(parts[0].body), 'sensevoice');
        expect(parts[1].name, 'response_format');
        expect(utf8.decode(parts[1].body), 'json');
        expect(parts[2].name, 'file');
        expect(parts[2].filename, 'formula.wav');
        expect(parts[2].contentType, 'audio/wav');
        expect(parts[2].body, wav);
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"text":"ok"}')),
          200,
        );
      }),
    );

    expect(await client.transcribe(wav), 'ok');
  });

  test(
    '5MB size guard emits its dedicated safe message before WAV validation',
    () async {
      final client = SenseVoiceAsrClient(
        baseUrl: 'http://127.0.0.1:8000',
        client: _FailIfSentClient(),
      );

      await _expectMessage(
        client.transcribe(Uint8List(5 * 1024 * 1024 + 1)),
        '录音文件过大，请重新录制。',
      );
    },
  );

  test(
    'deadline aborts an in-flight send without closing injected client',
    () async {
      final client = _AbortObservingClient.pendingSend();
      final asr = SenseVoiceAsrClient(
        baseUrl: 'http://127.0.0.1:8000',
        timeout: const Duration(milliseconds: 10),
        client: client,
      );

      await _expectTimeout(asr.transcribe(_canonicalWav()));
      expect(await client.abortObserved.future, isTrue);
      expect(client.closed, isFalse);
    },
  );

  test(
    'deadline cancels the response subscription without closing injected client',
    () async {
      final onCancel = Completer<void>();
      final controller = StreamController<List<int>>(
        onCancel: onCancel.complete,
      );
      final client = _AbortObservingClient(
        (request) async => http.StreamedResponse(controller.stream, 200),
      );
      final asr = SenseVoiceAsrClient(
        baseUrl: 'http://127.0.0.1:8000',
        timeout: const Duration(milliseconds: 10),
        client: client,
      );

      await _expectTimeout(asr.transcribe(_canonicalWav()));
      await onCancel.future;
      expect(await client.abortObserved.future, isTrue);
      expect(client.closed, isFalse);
    },
  );

  test('64KB 加一个字节时立即取消响应订阅', () async {
    final onCancel = Completer<void>();
    final controller = StreamController<List<int>>(onCancel: onCancel.complete);
    final client = _AbortObservingClient(
      (request) async => http.StreamedResponse(controller.stream, 200),
    );
    final asr = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: client,
    );
    final transcription = asr.transcribe(_canonicalWav());
    controller
      ..add(List<int>.filled(64 * 1024, 1))
      ..add(<int>[2]);

    await expectLater(transcription, throwsA(isA<SenseVoiceAsrException>()));
    await onCancel.future;
    expect(client.closed, isFalse);
  });

  for (final mutation in <String, void Function(Uint8List)>{
    'RIFF': (wav) => wav[0] = 0,
    'WAVE': (wav) => wav[8] = 0,
    'fmt': (wav) => wav[12] = 0,
    'PCM': (wav) => ByteData.sublistView(wav).setUint16(20, 3, Endian.little),
    'mono': (wav) => ByteData.sublistView(wav).setUint16(22, 2, Endian.little),
    '16k': (wav) =>
        ByteData.sublistView(wav).setUint32(24, 8000, Endian.little),
    'byteRate': (wav) =>
        ByteData.sublistView(wav).setUint32(28, 16000, Endian.little),
    'blockAlign': (wav) =>
        ByteData.sublistView(wav).setUint16(32, 4, Endian.little),
    'dataLength': (wav) =>
        ByteData.sublistView(wav).setUint32(40, 4, Endian.little),
    'sampleCompleteness': (wav) =>
        ByteData.sublistView(wav).setUint32(40, 1, Endian.little),
  }.entries) {
    test('${mutation.key} mutation is rejected before transport', () async {
      final client = _FailIfSentClient();
      final wav = _canonicalWav();
      mutation.value(wav);

      await expectLater(
        clientAsr(client).transcribe(wav),
        throwsA(isA<SenseVoiceAsrException>()),
      );
      expect(client.sent, isFalse);
    });
  }

  test(
    'invalid UTF-8, non-object JSON, non-string text and sync failures stay safe',
    () async {
      for (final client in <http.Client>[
        MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(Stream.value(<int>[0xff]), 200),
        ),
        MockClient((request) async => http.Response('[]', 200)),
        MockClient((request) async => http.Response('{"text":1}', 200)),
        _ThrowingClient(),
      ]) {
        await _expectSafe(clientAsr(client).transcribe(_canonicalWav()));
      }
    },
  );

  test('injected client remains reusable for a second request', () async {
    final client = _CountingClient();
    final asr = clientAsr(client);
    expect(await asr.transcribe(_canonicalWav()), 'ok');
    expect(await asr.transcribe(_canonicalWav()), 'ok');
    expect(client.sent, 2);
    expect(client.closed, isFalse);
  });

  test(
    'ignoring abortTrigger still returns timeout without closing client',
    () async {
      final client = _IgnoringAbortClient();
      final asr = SenseVoiceAsrClient(
        baseUrl: 'http://127.0.0.1:8000',
        client: client,
        deadlineScheduler: _ImmediateDeadlineScheduler(),
      );

      await _expectTimeout(asr.transcribe(_canonicalWav()));
      expect(client.closed, isFalse);
    },
  );

  test(
    'pending cancel does not delay deadline result and cancel is initiated',
    () async {
      final cancelStarted = Completer<void>();
      final controller = StreamController<List<int>>(
        onCancel: () {
          cancelStarted.complete();
          return Completer<void>().future;
        },
      );
      final asr = SenseVoiceAsrClient(
        baseUrl: 'http://127.0.0.1:8000',
        deadlineScheduler: _ImmediateDeadlineScheduler(),
        client: _AbortObservingClient(
          (request) async => http.StreamedResponse(controller.stream, 200),
        ),
      );

      await _expectTimeout(asr.transcribe(_canonicalWav()));
      await cancelStarted.future;
    },
  );

  test('dispose 幂等关闭自行创建的 HTTP client', () async {
    final transport = _CountingClient();
    final asr = http.runWithClient(
      () => SenseVoiceAsrClient(baseUrl: 'http://127.0.0.1:8000'),
      () => transport,
    );

    await asr.dispose();
    await asr.dispose();

    expect(transport.closeCount, 1);
  });

  test('dispose 不关闭注入 client 且拒绝后续健康检查与转写', () async {
    final transport = _CountingClient();
    final asr = SenseVoiceAsrClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: transport,
    );

    await asr.dispose();

    expect(transport.closeCount, 0);
    await expectLater(asr.isHealthy(), throwsStateError);
    await expectLater(asr.transcribe(_canonicalWav()), throwsStateError);
  });

  test('dispose 关闭 owned client 并使进行中的请求安全结束', () async {
    final transport = _CloseCompletingClient();
    final asr = http.runWithClient(
      () => SenseVoiceAsrClient(baseUrl: 'http://127.0.0.1:8000'),
      () => transport,
    );
    final transcription = asr.transcribe(_canonicalWav());
    // 先订阅错误 Future，避免 close 同步中止传输时被测试 Zone 判为未处理异常。
    final transcriptionExpectation = expectLater(
      transcription,
      throwsA(isA<SenseVoiceAsrException>()),
    );
    await transport.sendStarted.future;

    await asr.dispose();

    await transcriptionExpectation;
    expect(transport.closeCount, 1);
  });

  test(
    'default transcription and fixed health deadlines are scheduled by behavior',
    () async {
      final scheduler = _RecordingDeadlineScheduler();
      final asr = SenseVoiceAsrClient(
        baseUrl: 'http://127.0.0.1:8000',
        deadlineScheduler: scheduler,
        client: _IgnoringAbortClient(),
      );

      await _expectTimeout(asr.transcribe(_canonicalWav()));
      expect(scheduler.delays.first, const Duration(seconds: 15));
      expect(await asr.isHealthy(), isFalse);
      expect(scheduler.delays.last, const Duration(seconds: 2));
    },
  );

  for (final mutation in <String, void Function(Uint8List)>{
    'riffSize': (wav) =>
        ByteData.sublistView(wav).setUint32(4, 0, Endian.little),
    'fmtSize': (wav) =>
        ByteData.sublistView(wav).setUint32(16, 18, Endian.little),
    'bits': (wav) => ByteData.sublistView(wav).setUint16(34, 8, Endian.little),
    'dataMarker': (wav) => wav[36] = 0,
    'oddDataLength': (wav) {},
  }.entries) {
    test('${mutation.key} mutation is rejected before transport', () async {
      final client = _FailIfSentClient();
      final wav = mutation.key == 'oddDataLength'
          ? _canonicalWav(pcmLength: 1)
          : _canonicalWav();
      mutation.value(wav);
      await expectLater(
        clientAsr(client).transcribe(wav),
        throwsA(isA<SenseVoiceAsrException>()),
      );
      expect(client.sent, isFalse);
    });
  }
}

Future<void> _expectTimeout(Future<String> transcription) async {
  try {
    await transcription;
    fail('应抛出超时异常');
  } on SenseVoiceAsrException catch (error) {
    expect(error.message, '本机语音识别超时，请重新说一次。');
  }
}

SenseVoiceAsrClient clientAsr(http.Client client) =>
    SenseVoiceAsrClient(baseUrl: 'http://127.0.0.1:8000', client: client);

Future<void> _expectMessage(Future<String> future, String message) async {
  try {
    await future;
    fail('expected SenseVoiceAsrException');
  } on SenseVoiceAsrException catch (error) {
    expect(error.message, message);
  }
}

Future<void> _expectSafe(Future<String> future) async {
  try {
    await future;
    fail('expected SenseVoiceAsrException');
  } on SenseVoiceAsrException catch (error) {
    expect(error.message, isNot(contains('127.0.0.1')));
    expect(error.message, isNot(contains('private endpoint error')));
    expect(error.message, isNot(contains('Exception')));
  }
}

final class _IgnoringAbortClient extends http.BaseClient {
  var closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
  @override
  void close() {
    closed = true;
  }
}

final class _ImmediateDeadlineScheduler implements SenseVoiceDeadlineScheduler {
  @override
  Timer schedule(Duration delay, void Function() callback) {
    callback();
    return _FakeTimer();
  }
}

final class _RecordingDeadlineScheduler implements SenseVoiceDeadlineScheduler {
  final delays = <Duration>[];
  @override
  Timer schedule(Duration delay, void Function() callback) {
    delays.add(delay);
    callback();
    return _FakeTimer();
  }
}

final class _FakeTimer implements Timer {
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
  @override
  void cancel() {}
}

final class _FailIfSentClient extends http.BaseClient {
  var sent = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent = true;
    throw StateError('transport must not run');
  }
}

final class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('private endpoint error');
}

final class _CountingClient extends http.BaseClient {
  var sent = 0;
  var closeCount = 0;
  bool get closed => closeCount > 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent += 1;
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"text":"ok"}')),
      200,
    );
  }

  @override
  void close() {
    closeCount += 1;
  }
}

final class _CloseCompletingClient extends http.BaseClient {
  final sendStarted = Completer<void>();
  final _response = Completer<http.StreamedResponse>();
  var closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sendStarted.complete();
    return _response.future;
  }

  @override
  void close() {
    closeCount += 1;
    if (!_response.isCompleted) {
      _response.completeError(StateError('transport closed'));
    }
  }
}

final class _AbortObservingClient extends http.BaseClient {
  _AbortObservingClient(this._handler);
  _AbortObservingClient.pendingSend() : _handler = null;
  final Future<http.StreamedResponse> Function(http.BaseRequest)? _handler;
  final abortObserved = Completer<bool>();
  var closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    expect(request, isA<http.Abortable>());
    final abortable = request as http.Abortable;
    abortable.abortTrigger!.then((_) {
      if (!abortObserved.isCompleted) abortObserved.complete(true);
    });
    if (_handler != null) return _handler(request);
    final pending = Completer<http.StreamedResponse>();
    abortable.abortTrigger!.then(
      (_) => pending.completeError(http.RequestAbortedException()),
    );
    return pending.future;
  }

  @override
  void close() {
    closed = true;
  }
}

final class _MultipartPart {
  _MultipartPart(this.name, this.body, {this.filename, this.contentType});
  final String name;
  final List<int> body;
  final String? filename;
  final String? contentType;
}

List<_MultipartPart> _parseMultipart(List<int> bytes, String contentType) {
  final boundary = RegExp(
    'boundary=([^;]+)',
  ).firstMatch(contentType)!.group(1)!;
  final parts = <_MultipartPart>[];
  for (final rawPart in latin1.decode(bytes).split('--$boundary')) {
    if (rawPart.isEmpty || rawPart == '--\r\n') {
      continue;
    }
    final part = rawPart.substring(2, rawPart.length - 2);
    final headerEnd = part.indexOf('\r\n\r\n');
    final headers = part.substring(0, headerEnd);
    final disposition = RegExp(
      'name="([^"]+)"(?:; filename="([^"]+)")?',
    ).firstMatch(headers)!;
    final mime = RegExp(
      'content-type: ([^\r\n]+)',
    ).firstMatch(headers)?.group(1);
    parts.add(
      _MultipartPart(
        disposition.group(1)!,
        latin1.encode(part.substring(headerEnd + 4)),
        filename: disposition.group(2),
        contentType: mime,
      ),
    );
  }
  return parts;
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';

void main() {
  group('decodeRemoteTurnSse', () {
    test('decodes split UTF-8 frames into typed turn events in order', () async {
      final bytes = utf8.encode(
        'event: metadata\n'
        'data: {"traceId":"trace-1","model":"teacher-mini"}\n\n'
        'event: answer_delta\n'
        'data: {"text":"你好"}\n\n'
        'event: answer_delta\n'
        'data: {"text":"，同学"}\n\n'
        'event: committed\n'
        'data: {"ok":true,"data":${jsonEncode(_snapshot())}}\n\n'
        'event: done\n'
        'data: {"timings":{"headersMs":12,"totalMs":45},"usage":{"inputTokens":8}}\n\n',
      );
      final split = bytes.indexOf(utf8.encode('你').first) + 1;

      final events = await decodeRemoteTurnSse(
        Stream<List<int>>.fromIterable([bytes.sublist(0, split), bytes.sublist(split)]),
      ).toList();

      expect(events, hasLength(5));
      expect(events[0], isA<RemoteTurnMetadata>());
      expect((events[0] as RemoteTurnMetadata).traceId, 'trace-1');
      expect((events[1] as RemoteTurnAnswerDelta).text, '你好');
      expect((events[2] as RemoteTurnAnswerDelta).text, '，同学');
      expect((events[3] as RemoteTurnCommitted).snapshot.session.id, 'learning-1');
      expect((events[4] as RemoteTurnDone).timings['totalMs'], 45);
      expect((events[4] as RemoteTurnDone).usage['inputTokens'], 8);
    });

    test('accepts CRLF frames and joins multiple non-empty data lines', () async {
      final events = await decodeRemoteTurnSse(
        Stream<List<int>>.value(
          utf8.encode('event: answer_delta\r\ndata: {"text":"第一行"}\r\ndata:  \r\n\r\n'),
        ),
      ).toList();

      expect(events.single, isA<RemoteTurnAnswerDelta>());
      expect((events.single as RemoteTurnAnswerDelta).text, '第一行');
    });

    test('accepts an event line and blank separator split across chunks', () async {
      final bytes = utf8.encode('event: answer_delta\ndata: {"text":"边界"}\n\n');

      final events = await decodeRemoteTurnSse(
        Stream<List<int>>.fromIterable([
          bytes.sublist(0, 4),
          bytes.sublist(4, bytes.length - 1),
          bytes.sublist(bytes.length - 1),
        ]),
      ).toList();

      expect(events.single, isA<RemoteTurnAnswerDelta>());
      expect((events.single as RemoteTurnAnswerDelta).text, '边界');
    });

    test('maps error frames and ignores unknown events', () async {
      final events = await decodeRemoteTurnSse(
        Stream<List<int>>.value(
          utf8.encode(
            'event: heartbeat\n'
            'data: {"ignored":true}\n\n'
            'event: error\n'
            'data: {"message":"服务繁忙","canFallback":true}\n\n',
          ),
        ),
      ).toList();

      expect(events, hasLength(1));
      expect(events.single, isA<RemoteTurnFailed>());
      final failed = events.single as RemoteTurnFailed;
      expect(failed.message, '服务繁忙');
      expect(failed.canFallback, isTrue);
    });

    test('throws a stable exception for malformed known event JSON', () async {
      final stream = decodeRemoteTurnSse(
        Stream<List<int>>.value(
          utf8.encode('event: answer_delta\ndata: {not-json}\n\n'),
        ),
      );

      await expectLater(
        stream.toList(),
        throwsA(
          isA<RemoteExplorationException>().having(
            (error) => error.message,
            'message',
            '服务端返回格式不正确。',
          ),
        ),
      );
    });

    test('throws when the stream ends with an incomplete SSE frame', () async {
      final stream = decodeRemoteTurnSse(
        Stream<List<int>>.value(
          utf8.encode('event: committed\ndata: {"ok":true}\n'),
        ),
      );

      await expectLater(stream.toList(), throwsA(isA<RemoteExplorationException>()));
    });

    test('rejects done frames without numeric timings and usage maps', () async {
      const invalidPayloads = [
        '{"timings":{"totalMs":1}}',
        '{"timings":{"totalMs":1},"usage":"invalid"}',
        '{"timings":{"totalMs":"slow"},"usage":{"inputTokens":1}}',
      ];

      for (final payload in invalidPayloads) {
        await expectLater(
          decodeRemoteTurnSse(
            Stream<List<int>>.value(utf8.encode('event: done\ndata: $payload\n\n')),
          ).toList(),
          throwsA(isA<RemoteExplorationException>()),
        );
      }
    });
  });

  test('submitTurnStream exposes a delta before the response stream closes', () async {
    final responseController = StreamController<List<int>>();
    late http.BaseRequest captured;
    final client = _StreamClient((request) async {
      captured = request;
      return http.StreamedResponse(responseController.stream, 200);
    });
    final api = RemoteExplorationApi(
      client: client,
      baseUrl: 'https://teacher.example',
      identityProvider: () async => const RemoteExplorationIdentity(
        exploreSessionId: 'explore-a',
        bearerToken: 'token-a',
      ),
    );
    final iterator = StreamIterator(
      api.submitTurnStream(sessionId: 'learning-1', question: '继续追问', idempotencyKey: 'key-a'),
    );

    final next = iterator.moveNext();
    responseController.add(
      utf8.encode('event: answer_delta\ndata: {"text":"先看定义"}\n\n'),
    );

    expect(await next, isTrue);
    expect(iterator.current, isA<RemoteTurnAnswerDelta>());
    expect((iterator.current as RemoteTurnAnswerDelta).text, '先看定义');
    expect(captured.url.path, '/api/learning-sessions/learning-1/turns/stream');
    expect(captured.headers['authorization'], 'Bearer token-a');
    expect(captured.headers['content-type'], 'application/json');
    expect(captured.headers['x-miniapp-client'], 'uniprism-weapp');
    expect(captured.headers['idempotency-key'], 'key-a');
    expect(jsonDecode((captured as http.Request).body), {
      'exploreSessionId': 'explore-a',
      'question': '继续追问',
    });

    await responseController.close();
    await iterator.cancel();
  });

  test('submitTurnStream aborts a request cancelled before response headers', () async {
    final headersPending = Completer<http.StreamedResponse>();
    final requestSent = Completer<http.AbortableRequest>();
    final aborted = Completer<void>();
    var requestCount = 0;
    final client = _StreamClient((request) async {
      requestCount += 1;
      if (requestCount == 1) {
        final abortable = request as http.AbortableRequest;
        requestSent.complete(abortable);
        abortable.abortTrigger!.then((_) => aborted.complete());
        return headersPending.future;
      }
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode('event: answer_delta\ndata: {"text":"恢复"}\n\n'),
        ),
        200,
      );
    });
    final api = _streamingApi(client);
    final subscription = api
        .submitTurnStream(sessionId: 'learning-1', question: '取消')
        .listen((_) {});

    await requestSent.future.timeout(const Duration(seconds: 1));
    await subscription.cancel();
    await aborted.future;
    headersPending.completeError(http.RequestAbortedException());

    final next = await api
        .submitTurnStream(sessionId: 'learning-1', question: '重试')
        .first;
    expect(next, isA<RemoteTurnAnswerDelta>());
    expect(requestCount, 2);
  });

  test('submitTurnStream aborts an active body subscription without closing client', () async {
    final bodyCancelled = Completer<void>();
    final deltaReceived = Completer<void>();
    final abortObserved = Completer<void>();
    final requestSent = Completer<http.AbortableRequest>();
    final body = StreamController<List<int>>(
      onCancel: () => bodyCancelled.complete(),
    );
    final client = _StreamClient((request) async {
      final abortable = request as http.AbortableRequest;
      requestSent.complete(abortable);
      abortable.abortTrigger!.then((_) => abortObserved.complete());
      return http.StreamedResponse(body.stream, 200);
    });
    final api = _streamingApi(client);
    final subscription = api
        .submitTurnStream(sessionId: 'learning-1', question: '停止')
        .listen((event) {
          if (event is RemoteTurnAnswerDelta) deltaReceived.complete();
        });

    await requestSent.future.timeout(const Duration(seconds: 1));
    body.add(utf8.encode('event: answer_delta\ndata: {"text":"已开始"}\n\n'));
    await deltaReceived.future;
    await subscription.cancel();

    await abortObserved.future.timeout(const Duration(seconds: 1));
    await bodyCancelled.future.timeout(const Duration(seconds: 1));
    await body.close();
  });

  test('submitTurnStream aborts a header request when the timeout elapses', () async {
    final headersPending = Completer<http.StreamedResponse>();
    final requestSent = Completer<http.AbortableRequest>();
    final aborted = Completer<void>();
    final client = _StreamClient((request) async {
      final abortable = request as http.AbortableRequest;
      requestSent.complete(abortable);
      abortable.abortTrigger!.then((_) => aborted.complete());
      return headersPending.future;
    });
    final api = _streamingApi(client, timeout: const Duration(milliseconds: 5));
    final result = api
        .submitTurnStream(sessionId: 'learning-1', question: '超时')
        .toList();

    await requestSent.future.timeout(const Duration(seconds: 1));
    await expectLater(
      result,
      throwsA(isA<RemoteExplorationException>()),
    );
    await aborted.future;
    headersPending.completeError(http.RequestAbortedException());
  });

  test('submitTurnStream maps empty and malformed non-2xx responses stably', () async {
    final bodies = ['', '{'];
    for (final body in bodies) {
      final api = _streamingApi(
        _StreamClient(
          (_) async => http.StreamedResponse(Stream.value(utf8.encode(body)), 503),
        ),
      );

      await expectLater(
        api.submitTurnStream(sessionId: 'learning-1', question: '失败').toList(),
        throwsA(
          isA<RemoteExplorationException>()
              .having((error) => error.message, 'message', '请求失败，请重试。')
              .having((error) => error.statusCode, 'statusCode', 503),
        ),
      );
    }
  });
}

final class _StreamClient extends http.BaseClient {
  _StreamClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _send(request);
}

RemoteExplorationApi _streamingApi(
  http.Client client, {
  Duration timeout = const Duration(seconds: 35),
}) => RemoteExplorationApi(
  client: client,
  baseUrl: 'https://teacher.example',
  timeout: timeout,
  identityProvider: () async => const RemoteExplorationIdentity(
    exploreSessionId: 'explore-a',
  ),
);

Map<String, Object?> _snapshot() => {
  'session': {
    'id': 'learning-1',
    'exploreSessionId': 'explore-a',
    'topic': '测试预习',
    'scenarioId': 'prestudy',
    'atomId': null,
    'status': 'ACTIVE',
    'revision': 1,
    'nodeCount': 0,
    'startedAt': '2026-08-09T01:00:00.000Z',
    'expiresAt': '2099-08-09T01:15:00.000Z',
    'completedAt': null,
  },
  'currentNodeId': null,
  'activeStrategy': null,
  'nodes': <Object?>[],
  'conceptNodes': <Object?>[],
  'materials': <Object?>[],
  'summary': null,
};

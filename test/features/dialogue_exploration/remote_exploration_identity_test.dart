import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';

void main() {
  test('account history requests carry the current Bearer token', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {'items': [], 'nextCursor': null},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = RemoteExplorationApi(
      client: client,
      identityProvider: () async => const RemoteExplorationIdentity(
        exploreSessionId: 'explore-user-a',
        bearerToken: 'token-a',
      ),
    );

    await api.listSessions();

    expect(captured.headers['authorization'], 'Bearer token-a');
    expect(captured.headers['x-miniapp-client'], 'uniprism-weapp');
    expect(captured.url.queryParameters['exploreSessionId'], 'explore-user-a');
  });

  test(
    'anonymous history requests carry only the anonymous identity',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {'items': [], 'nextCursor': null},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = RemoteExplorationApi(
        client: client,
        identityProvider: () async => const RemoteExplorationIdentity(
          exploreSessionId: 'explore-anon-a',
          anonymousId: 'anon-a',
        ),
      );

      await api.listSessions();

      expect(captured.headers['authorization'], isNull);
      expect(captured.headers['x-anonymous-id'], 'anon-a');
    },
  );

  test(
    'mutations and exports refresh identity after an account switch',
    () async {
      final captured = <http.Request>[];
      final client = MockClient((request) async {
        captured.add(request);
        final data = request.url.path.endsWith('/export')
            ? <String, Object?>{'schemaVersion': 1}
            : _emptySnapshot('explore-current');
        return http.Response(
          jsonEncode({'ok': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      var identityCall = 0;
      final api = RemoteExplorationApi(
        client: client,
        identityProvider: () async {
          identityCall += 1;
          return RemoteExplorationIdentity(
            exploreSessionId: 'explore-$identityCall',
            bearerToken: 'token-$identityCall',
          );
        },
      );

      await api.submitTurn(sessionId: 'learning-1', question: '继续追问');
      await api.exportTree('learning-1');

      expect(captured[0].headers['authorization'], 'Bearer token-1');
      expect(jsonDecode(captured[0].body)['exploreSessionId'], 'explore-1');
      expect(captured[1].headers['authorization'], 'Bearer token-2');
      expect(captured[1].url.queryParameters['exploreSessionId'], 'explore-2');
    },
  );
}

Map<String, Object?> _emptySnapshot(String exploreSessionId) => {
  'session': {
    'id': 'learning-1',
    'exploreSessionId': exploreSessionId,
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

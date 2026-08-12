import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';

void main() {
  test('Web 学习入口绕过仅支持原生端的身份提供器', () {
    final provider = remoteIdentityProviderForPlatform(
      isWeb: true,
      nativeProvider: () async => throw UnsupportedError('dart:io unavailable'),
    );

    expect(provider, isNull);
  });

  test('原生端学习入口保留应用账号身份提供器', () async {
    const identity = RemoteExplorationIdentity(
      exploreSessionId: 'explore-native',
      bearerToken: 'token-native',
    );
    final provider = remoteIdentityProviderForPlatform(
      isWeb: false,
      nativeProvider: () async => identity,
    );

    expect(await provider!(), same(identity));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/knowledge_map/high_school_math_knowledge_map_page.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/remote_exploration_page.dart';
import 'package:uniprism_app/main.dart' as app;

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

  testWidgets('开发构建可通过稳定路由直接打开 AI 课堂', (tester) async {
    await tester.pumpWidget(const app.UniPrismApp());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final routeBuilder = materialApp.routes!['/dialogue-exploration-lab'];

    expect(routeBuilder, isNotNull);
    expect(
      routeBuilder!(tester.element(find.byType(MaterialApp))),
      isA<RemoteExplorationLabPage>(),
    );
  });

  testWidgets('开发构建可通过稳定路由直接打开知识图谱', (tester) async {
    await tester.pumpWidget(const app.UniPrismApp());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final routeBuilder = materialApp.routes!['/knowledge-map-lab'];

    expect(routeBuilder, isNotNull);
    expect(
      routeBuilder!(tester.element(find.byType(MaterialApp))),
      isA<HighSchoolMathKnowledgeMapPage>(),
    );
  });
}

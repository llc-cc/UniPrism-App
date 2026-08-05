import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  testWidgets('figure material renders a custom parabola painter', (tester) async {
    await tester.pumpWidget(
      _materialHarness(
        _material(
          id: 'figure',
          kind: ExplorationMaterialKind.figure,
          payload: const {'a': 1.0, 'h': 0.0, 'k': 0.0},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('exploration-figure')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('interactive parabola changes a instead of showing a screenshot', (
    tester,
  ) async {
    await tester.pumpWidget(
      _materialHarness(
        _material(
          id: 'interactive',
          kind: ExplorationMaterialKind.interactive,
          payload: const {'a': 1.0, 'h': 0.0, 'k': 0.0},
        ),
      ),
    );

    expect(find.text('a = 1.0'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('parabola-a-slider')),
      const Offset(120, 0),
    );
    await tester.pump();

    expect(find.text('a = 1.0'), findsNothing);
    expect(find.textContaining('a = '), findsOneWidget);
  });

  testWidgets('business interaction updates the daily revenue', (tester) async {
    await tester.pumpWidget(
      _materialHarness(
        _material(
          id: 'business',
          kind: ExplorationMaterialKind.interactive,
          payload: const {'price': 28.0, 'dailyOrders': 120.0},
        ),
      ),
    );

    expect(find.text('日收入：¥3360'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('business-price-slider')),
      const Offset(100, 0),
    );
    await tester.pump();
    expect(find.text('日收入：¥3360'), findsNothing);
  });

  testWidgets('mock video is labelled and supports play and pause', (tester) async {
    await tester.pumpWidget(
      _materialHarness(
        _material(
          id: 'video',
          kind: ExplorationMaterialKind.video,
          payload: const {'durationSeconds': 18},
        ),
      ),
    );

    expect(find.text('模拟视频'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mock-video-toggle')));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mock-video-toggle')));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('formula material renders the formal expression', (tester) async {
    await tester.pumpWidget(
      _materialHarness(
        _material(
          id: 'formula',
          kind: ExplorationMaterialKind.formula,
          payload: const {'formula': 'y = a(x-h)² + k'},
        ),
      ),
    );

    expect(find.text('y = a(x-h)² + k'), findsOneWidget);
  });

  testWidgets('whiteboard returns changes only after confirmation', (tester) async {
    ExplorationWhiteboardResult? result;
    const launcher = MockExplorationWhiteboardLauncher();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await launcher.open(
                  context,
                  nodeId: 'node-1',
                  atomId: 'quadratic-vertex',
                  initialState: const {'a': 1.0, 'h': 0.0, 'k': 0.0},
                );
              },
              child: const Text('打开白板'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开白板'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('whiteboard-h-slider')),
      const Offset(100, 0),
    );
    await tester.tap(find.byKey(const ValueKey('whiteboard-confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.confirmed, isTrue);
    expect(result!.state['h'], isNot(0.0));
  });
}

Widget _materialHarness(ExplorationMaterial material) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 390,
        child: ExplorationMaterialCard(material: material),
      ),
    ),
  );
}

ExplorationMaterial _material({
  required String id,
  required ExplorationMaterialKind kind,
  required Map<String, Object?> payload,
}) {
  return ExplorationMaterial(
    id: id,
    atomId: 'test-atom',
    kind: kind,
    title: '测试素材',
    payload: payload,
  );
}

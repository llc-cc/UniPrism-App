import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  testWidgets('lab shows three scenarios, mastery profiles, and mock warning', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();

    expect(find.text('1.2 对话探索实验室'), findsOneWidget);
    expect(find.textContaining('测试数据'), findsWidgets);
    expect(find.text('二次函数：顶点为什么在这里'), findsOneWidget);
    expect(find.text('证明不等式：验证、诊断与回退'), findsOneWidget);
    expect(find.text('Business model：咖啡店怎么赚钱'), findsOneWidget);
    expect(find.text('基础薄弱'), findsOneWidget);
    expect(find.text('正在形成'), findsOneWidget);
    expect(find.text('掌握较好'), findsOneWidget);
  });

  testWidgets('teaching scenario renders adapted answer and live material', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scenario-teaching-quadratic')),
    );
    await tester.pumpAndSettle();

    expect(find.text('二次函数：顶点为什么在这里'), findsOneWidget);
    expect(find.textContaining('顶点式'), findsWidgets);
    expect(find.byKey(const ValueKey('parabola-a-slider')), findsOneWidget);
    expect(find.text('查看思维树'), findsOneWidget);
  });

  testWidgets('question scaffold only fills input and does not auto-send', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scenario-teaching-quadratic')),
    );
    await tester.pumpAndSettle();
    final tutorCount = find.byKey(const ValueKey('tutor-message')).evaluate().length;

    await tester.tap(find.text('如果……会怎样'));
    await tester.pump();

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('exploration-question-input')),
    );
    expect(input.controller!.text, '如果……会怎样');
    expect(
      find.byKey(const ValueKey('tutor-message')).evaluate().length,
      tutorCount,
    );
  });

  testWidgets('question library fills a seed and tutor message opens whiteboard', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scenario-teaching-quadratic')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('一般式怎么变成顶点式？'));
    await tester.pump();
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('exploration-question-input')),
    );
    expect(input.controller!.text, '一般式怎么变成顶点式？');

    final whiteboardButton = find.text('在白板上演示').first;
    await tester.ensureVisible(whiteboardButton);
    await tester.tap(whiteboardButton);
    await tester.pumpAndSettle();
    expect(find.text('Mock 白板'), findsOneWidget);
  });

  testWidgets('practice page keeps wrong path and reaches a valid branch', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scenario-practice-inequality')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('practice-try-wrong')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-validate')));
    await tester.pumpAndSettle();
    expect(find.textContaining('候选诊断'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-confirm-diagnosis')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('practice-backtrack')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-try-correct')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-validate')));
    await tester.pumpAndSettle();

    expect(find.textContaining('满足基本不等式'), findsOneWidget);
    expect(find.text('不成立'), findsWidgets);
    expect(find.text('回退'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('practice-reflection')),
      '先检查正数条件，再选择基本不等式。',
    );
    await tester.tap(find.byKey(const ValueKey('practice-complete')));
    await tester.pump();
    expect(find.text('已完成'), findsWidgets);
  });

  testWidgets('compact teaching page has no layout overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scenario-teaching-quadratic')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

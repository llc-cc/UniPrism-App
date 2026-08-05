import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  testWidgets('lab opens as a conversation instead of a scenario menu', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();

    expect(find.text('1.2 对话探索实验室'), findsOneWidget);
    expect(find.text('今天想弄懂什么？'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('exploration-topic-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('exploration-start-session')),
      findsOneWidget,
    );
    expect(find.text('为什么两个负数相乘会得到正数？'), findsOneWidget);
    expect(find.text('选择学生掌握程度'), findsNothing);
    expect(find.text('选择复用场景'), findsNothing);
    expect(
      find.byKey(const ValueKey('scenario-teaching-quadratic')),
      findsNothing,
    );
  });

  testWidgets('a free question starts an automatically planned micro lesson', (
    tester,
  ) async {
    await _startQuestion(tester, '二次函数的顶点为什么在这里？');

    expect(find.text('二次函数：顶点为什么在这里'), findsOneWidget);
    expect(find.textContaining('正在梳理问题链'), findsOneWidget);
    expect(find.textContaining('顶点'), findsWidgets);
    expect(find.byKey(const ValueKey('parabola-a-slider')), findsOneWidget);
    expect(find.text('查看思维树'), findsOneWidget);
  });

  testWidgets('negative multiplication seed receives a relevant response', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('为什么两个负数相乘会得到正数？'));
    await tester.tap(find.byKey(const ValueKey('exploration-start-session')));
    await tester.pumpAndSettle();

    expect(find.textContaining('负数'), findsWidgets);
    expect(find.textContaining('成立条件'), findsWidgets);
  });

  testWidgets('question scaffold only fills input and does not auto-send', (
    tester,
  ) async {
    await _startQuestion(tester, '二次函数的顶点为什么在这里？');
    final tutorCount = find
        .byKey(const ValueKey('tutor-message'))
        .evaluate()
        .length;

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

  testWidgets(
    'question library fills a seed and tutor message opens whiteboard',
    (tester) async {
      await _startQuestion(tester, '二次函数的顶点为什么在这里？');

      await tester.tap(find.text('一般式怎么变成顶点式？'));
      await tester.pump();
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('exploration-question-input')),
      );
      expect(input.controller!.text, '一般式怎么变成顶点式？');

      final whiteboardButton = find.text('在白板上演示').first;
      final button = tester.widget<TextButton>(
        find.ancestor(of: whiteboardButton, matching: find.byType(TextButton)),
      );
      button.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Mock 白板'), findsOneWidget);
    },
  );

  testWidgets('practice question keeps wrong path and reaches a valid branch', (
    tester,
  ) async {
    await _startQuestion(tester, '怎样证明 x + 1/x ≥ 2？');

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

  testWidgets('self explanation completes the session and shows five outputs', (
    tester,
  ) async {
    await _startQuestion(tester, '为什么两个负数相乘会得到正数？');
    await _sendTurn(tester, '负号表示相反方向');
    await _sendTurn(tester, '还是太抽象了');
    await _sendTurn(tester, '所以负负还是负数');
    await _sendTurn(tester, '我来总结');

    expect(find.textContaining('正在验证你的解释'), findsOneWidget);
    await _sendTurn(tester, '乘以负数表示取相反数，两次取相反数回到原方向。');

    expect(find.text('本次学习产出'), findsOneWidget);
    expect(find.text('思维树'), findsOneWidget);
    expect(find.text('理解深度'), findsOneWidget);
    expect(find.text('错误模型'), findsOneWidget);
    expect(find.text('兴趣方向'), findsOneWidget);
    expect(find.text('复习卡片'), findsOneWidget);
  });

  testWidgets('compact conversation entry has no layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
    await tester.pumpAndSettle();

    expect(find.text('今天想弄懂什么？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _startQuestion(WidgetTester tester, String question) async {
  await tester.pumpWidget(const MaterialApp(home: ExplorationLabPage()));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('exploration-topic-input')),
    question,
  );
  await tester.tap(find.byKey(const ValueKey('exploration-start-session')));
  await tester.pumpAndSettle();
}

Future<void> _sendTurn(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('exploration-question-input')),
    text,
  );
  await tester.tap(find.byKey(const ValueKey('exploration-send')));
  await tester.pumpAndSettle();
}

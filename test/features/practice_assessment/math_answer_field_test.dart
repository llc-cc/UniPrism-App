import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/math_answer_field.dart';

void main() {
  testWidgets('填空题把公式输入框嵌入题干占位符而不保留下划线', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          prompt: '双曲线的离心率为______。',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('practice-fill-blank-prompt-before')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-math-answer-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-fill-blank-prompt-after')),
      findsOneWidget,
    );
    expect(find.textContaining('______'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-fraction')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-3')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-2')));
    await tester.pump();

    expect(changes.last, r'\frac{3}{2}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('公式草稿初始化为排版值且不回传伪造的编辑事件', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          value: r'\frac{3}{2}',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    expect(
      controller.currentEditingValue(placeholderWhenEmpty: false),
      r'(\frac{3}{2})',
    );
    expect(changes, isEmpty);
    expect(
      find.byKey(const ValueKey('practice-math-answer-field')),
      findsOneWidget,
    );
  });

  testWidgets('服务端恢复的新草稿同步到公式框但不会触发保存回环', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    Widget field(String value) => _app(
      MathAnswerField(
        questionId: 'q12',
        value: value,
        enabled: true,
        controller: controller,
        onChanged: changes.add,
      ),
    );

    await tester.pumpWidget(field('1'));
    await tester.pumpWidget(field(r'\sqrt{2}'));

    expect(
      controller.currentEditingValue(placeholderWhenEmpty: false),
      r'\sqrt{2}',
    );
    expect(changes, isEmpty);
  });

  testWidgets('学生编辑公式时只上报一次不带定界符的 LaTeX', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    controller.addLeaf('2');
    await tester.pump();

    expect(changes, ['2']);
  });

  testWidgets('点击公式框打开 UniPrism 浅色键盘并可输入分式', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-formula-keyboard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-formula-key-fraction')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-fraction')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-3')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-2')));
    await tester.pump();

    expect(changes.last, r'\frac{3}{2}');
  });

  testWidgets('关系符号页覆盖高中数学填空题常用符号且窄屏不溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          value: '',
          enabled: true,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-category-symbols')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-formula-key-less-equal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-formula-key-infinity')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MathKeyboardViewInsets(child: Scaffold(body: child)),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/math_answer_field.dart';

void main() {
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
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MathKeyboardViewInsets(child: Scaffold(body: child)),
  );
}

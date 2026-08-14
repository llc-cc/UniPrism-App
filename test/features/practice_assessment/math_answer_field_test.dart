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
      find.byKey(const ValueKey('practice-formula-section-commonTemplates')),
    );
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
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-section-commonTemplates')),
    );
    await tester.pump();
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

  testWidgets('科学记数法模板通过真实公式框输出可编辑槽位', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-scientific',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-section-commonTemplates')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-scientific-notation')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-3')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-8')));
    await tester.pump();

    expect(changes.last, r'3\times10^{8}');
  });

  testWidgets('条件概率模板通过真实公式框按条件两侧填写', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-conditional-probability',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-primary-mathematics')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-section-mathTemplates')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-conditional-prob')),
    );
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-more-shortcut')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-uppercase')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-letter-a')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-letter-b')),
    );
    await tester.pump();

    expect(changes.last, r'P\left({A}\mid{B}\right)');
  });

  testWidgets('核素模板通过真实公式框按质量数原子序数元素填写', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-nucleus',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-primary-physics')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-nucleus')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-1')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-4')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-6')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-more-shortcut')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-uppercase')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-letter-c')),
    );
    await tester.pump();

    expect(changes.last, r'{}_{6}^{14}C');
  });

  testWidgets('复合单位通过真实公式框保留数值间距和直立体', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-compound-unit',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-5')));
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-primary-physics')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-section-physicsUnits')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-page-next')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-page-next')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-unit-m-per-s2')),
    );
    await tester.pump();

    expect(changes.last, r'5\,\mathrm{m}/\mathrm{s}^{2}');
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
      find.byKey(const ValueKey('practice-formula-section-commonSymbols')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-formula-key-less-equal')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-primary-mathematics')),
    );
    await tester.pump();
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

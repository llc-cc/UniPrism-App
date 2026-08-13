import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_keyboard.dart';

void main() {
  testWidgets('窄屏数字区固定为四行四列且切换标签后仍然保留', (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    expect(
      find.byKey(const ValueKey('practice-formula-numeric-pad')),
      findsOneWidget,
    );
    _expectSameRow(tester, const ['7', '8', '9', 'divide']);
    _expectSameRow(tester, const ['4', '5', '6', 'multiply']);
    _expectSameRow(tester, const ['1', '2', '3', 'minus']);
    _expectSameRow(tester, const ['0', 'decimal', 'equals', 'plus']);
    expect(_center(tester, '4').dy, greaterThan(_center(tester, '7').dy));
    expect(_center(tester, '1').dy, greaterThan(_center(tester, '4').dy));
    expect(_center(tester, '0').dy, greaterThan(_center(tester, '1').dy));

    await tester.tap(
      find.byKey(const ValueKey('practice-formula-tab-functions')),
    );
    await tester.pump();

    expect(find.byKey(_key('7')), findsOneWidget);
    expect(find.byKey(_key('plus')), findsOneWidget);
    expect(find.byKey(_key('x')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面宽度仍保持数字区顺序而不与辅助键混排', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    _expectSameRow(tester, const ['7', '8', '9', 'divide']);
    _expectSameRow(tester, const ['4', '5', '6', 'multiply']);
    expect(_center(tester, 'divide').dx, greaterThan(_center(tester, '9').dx));
    expect(_center(tester, '4').dy, greaterThan(_center(tester, '7').dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('分式根式和上下限键帽使用真正的数学公式排版', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    expect(
      find.descendant(
        of: find.byKey(_key('fraction')),
        matching: find.byType(Math),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_key('sqrt')),
        matching: find.byType(Math),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-tab-functions')),
    );
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(_key('sum')), matching: find.byType(Math)),
      findsOneWidget,
    );
  });

  testWidgets('数字与四则运算键写入受控 LaTeX', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    for (final id in <String>[
      '7',
      'divide',
      '8',
      'multiply',
      '9',
      'minus',
      '1',
      'equals',
      '6',
      'plus',
      '2',
    ]) {
      await tester.tap(find.byKey(_key(id)));
    }

    expect(_latex(controller), r'7\div8\times9-1=6+2');
  });

  testWidgets('平方幂下标根式与函数键创建可继续填写的结构', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    controller.addLeaf('x');
    await tester.tap(find.byKey(_key('square')));
    expect(_latex(controller), r'x^{2}');

    controller.clear();
    controller.addLeaf('x');
    await tester.tap(find.byKey(_key('power')));
    controller.addLeaf('3');
    expect(_latex(controller), r'x^{3}');

    controller.clear();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-tab-functions')),
    );
    await tester.pump();
    controller.addLeaf('x');
    await tester.tap(find.byKey(_key('subscript')));
    controller.addLeaf('1');
    expect(_latex(controller), r'x_{1}');

    controller.clear();
    await tester.tap(find.byKey(_key('sin')));
    await tester.tap(find.byKey(_key('x')));
    expect(_latex(controller), r'\sin(x)');

    controller.clear();
    await tester.tap(find.byKey(_key('exp')));
    await tester.tap(find.byKey(_key('2')));
    expect(_latex(controller), r'e^{2}');
  });

  testWidgets('符号页补齐比较集合与几何符号并写入标准命令', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await tester.tap(
      find.byKey(const ValueKey('practice-formula-tab-relations')),
    );
    await tester.pump();
    for (final id in <String>[
      'less-equal',
      'approx',
      'subset-equal',
      'perpendicular',
      'degree',
      'arrow',
    ]) {
      await tester.tap(find.byKey(_key(id)));
    }

    expect(_latex(controller), r'\le\approx\subseteq\perp^{\circ}\to');
    expect(find.byKey(_key('not-in')), findsOneWidget);
    expect(find.byKey(_key('empty-set')), findsOneWidget);
  });

  testWidgets('极限求和与积分键提供可按顺序填写的上下限槽位', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-tab-functions')),
    );
    await tester.pump();

    await tester.tap(find.byKey(_key('limit')));
    await tester.tap(find.byKey(_key('n')));
    expect(_latex(controller), r'\lim_{n}');

    controller.clear();
    await tester.tap(find.byKey(_key('sum')));
    await tester.tap(find.byKey(_key('1')));
    await tester.tap(find.byKey(_key('next')));
    await tester.tap(find.byKey(_key('n')));
    expect(_latex(controller), r'\sum_{1}^{n}');

    controller.clear();
    await tester.tap(find.byKey(_key('integral')));
    await tester.tap(find.byKey(_key('0')));
    await tester.tap(find.byKey(_key('next')));
    await tester.tap(find.byKey(_key('1')));
    expect(_latex(controller), r'\int_{0}^{1}');
  });
}

Widget _app(MathFieldEditingController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PracticeFormulaKeyboard(controller: controller, onDone: () {}),
      ),
    ),
  );
}

ValueKey<String> _key(String id) =>
    ValueKey<String>('practice-formula-key-$id');

Offset _center(WidgetTester tester, String id) =>
    tester.getCenter(find.byKey(_key(id)));

void _expectSameRow(WidgetTester tester, List<String> ids) {
  final positions = ids.map((id) => _center(tester, id)).toList();
  for (var index = 1; index < positions.length; index++) {
    expect(positions[index].dy, closeTo(positions.first.dy, 0.5));
    expect(positions[index].dx, greaterThan(positions[index - 1].dx));
  }
}

String _latex(MathFieldEditingController controller) => controller
    .currentEditingValue(placeholderWhenEmpty: false)
    .replaceAll(' ', '');

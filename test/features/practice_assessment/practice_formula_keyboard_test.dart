import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_key_catalog.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_keyboard.dart';

void main() {
  testWidgets('桌面端显示两级导航并保持右侧五行数字区', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    for (final primary in PracticeFormulaPrimaryCategory.values) {
      expect(find.byKey(_primaryKey(primary)), findsOneWidget);
    }
    for (final section
        in practiceFormulaSectionsByPrimary[PracticeFormulaPrimaryCategory
            .common]!) {
      expect(find.byKey(_sectionKey(section)), findsOneWidget);
    }
    expect(
      find.byKey(
        const ValueKey('practice-formula-section-grid-lettersAndNumbers'),
      ),
      findsOneWidget,
    );

    final navigation = tester.getRect(
      find.byKey(const ValueKey('practice-formula-navigation-rail')),
    );
    final content = tester.getRect(
      find.byKey(
        const ValueKey('practice-formula-section-grid-lettersAndNumbers'),
      ),
    );
    final numeric = tester.getRect(
      find.byKey(const ValueKey('practice-formula-numeric-pad')),
    );
    expect(navigation.right, lessThan(content.left));
    expect(content.right, lessThan(numeric.left));

    _expectSameRow(tester, const [
      'more-shortcut',
      'previous',
      'next',
      'delete',
    ]);
    _expectSameRow(tester, const ['7', '8', '9', 'divide']);
    _expectSameRow(tester, const ['4', '5', '6', 'multiply']);
    _expectSameRow(tester, const ['1', '2', '3', 'minus']);
    _expectSameRow(tester, const ['0', 'decimal', 'plus', 'done']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换一级分类只显示所属二级标签并自动选择首项', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await _selectPrimary(tester, PracticeFormulaPrimaryCategory.mathematics);
    expect(
      find.byKey(_sectionKey(PracticeFormulaSection.mathSymbols)),
      findsOneWidget,
    );
    expect(
      find.byKey(_sectionKey(PracticeFormulaSection.mathTemplates)),
      findsOneWidget,
    );
    expect(
      find.byKey(_sectionKey(PracticeFormulaSection.commonSymbols)),
      findsNothing,
    );
    expect(find.byKey(_key('infinity')), findsOneWidget);

    await _selectSection(tester, PracticeFormulaSection.mathTemplates);
    expect(find.byKey(_key('conditional-prob')), findsOneWidget);

    await _selectPrimary(tester, PracticeFormulaPrimaryCategory.physics);
    expect(
      find.byKey(_sectionKey(PracticeFormulaSection.physicsSymbols)),
      findsOneWidget,
    );
    expect(
      find.byKey(_sectionKey(PracticeFormulaSection.physicsUnits)),
      findsOneWidget,
    );
    expect(
      find.byKey(_sectionKey(PracticeFormulaSection.physicsConstants)),
      findsOneWidget,
    );
    expect(
      find.byKey(_sectionKey(PracticeFormulaSection.mathSymbols)),
      findsNothing,
    );
    expect(find.byKey(_key('nucleus')), findsOneWidget);
  });

  testWidgets('物理单位每页二十项且切换标签重置页码', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await _selectPrimary(tester, PracticeFormulaPrimaryCategory.physics);
    await _selectSection(tester, PracticeFormulaSection.physicsUnits);
    expect(find.byKey(_key('unit-mm')), findsOneWidget);
    expect(find.byKey(_key('unit-kW-hour')), findsNothing);
    expect(
      find.byKey(const ValueKey('practice-formula-page-indicator')),
      findsOneWidget,
    );
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-formula-page-next')));
    await tester.pump();
    expect(find.text('2/3'), findsOneWidget);
    expect(find.byKey(_key('unit-mm')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('practice-formula-page-next')));
    await tester.pump();
    expect(find.text('3/3'), findsOneWidget);
    expect(find.byKey(_key('unit-kW-hour')), findsOneWidget);

    await _selectSection(tester, PracticeFormulaSection.physicsSymbols);
    expect(find.byKey(_key('nucleus')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-formula-page-controls')),
      findsNothing,
    );

    await _selectSection(tester, PracticeFormulaSection.physicsUnits);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byKey(_key('unit-mm')), findsOneWidget);
  });

  testWidgets('375 窄屏使用两行横向导航并逐标签无溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));
    expect(
      find.byKey(const ValueKey('practice-formula-primary-scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-formula-section-scroll')),
      findsOneWidget,
    );

    for (final primary in PracticeFormulaPrimaryCategory.values) {
      await _selectPrimary(tester, primary);
      for (final section in practiceFormulaSectionsByPrimary[primary]!) {
        await _selectSection(tester, section);
        expect(
          find.byKey(ValueKey('practice-formula-section-grid-${section.name}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    }
    _expectSameRow(tester, const ['7', '8', '9', 'divide']);
    _expectSameRow(tester, const ['0', 'decimal', 'plus', 'done']);
  });

  testWidgets('720 和 1100 宽屏逐分类保持稳定布局', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in <double>[720, 1100]) {
      tester.view.physicalSize = Size(width, 900);
      final controller = MathFieldEditingController();
      await tester.pumpWidget(_app(controller));
      expect(
        find.byKey(const ValueKey('practice-formula-wide-layout')),
        findsOneWidget,
      );
      for (final primary in PracticeFormulaPrimaryCategory.values) {
        await _selectPrimary(tester, primary);
        for (final section in practiceFormulaSectionsByPrimary[primary]!) {
          await _selectSection(tester, section);
          expect(tester.takeException(), isNull);
        }
      }
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('abc 跳回字母页且大小写状态保持独立', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    for (final letter in 'abcdefghijklmnopqrstuvwxyz'.split('')) {
      expect(find.byKey(_key('letter-$letter')), findsOneWidget);
    }
    expect(find.byKey(_key('pi')), findsOneWidget);
    expect(find.byKey(_key('uppercase')), findsOneWidget);
    expect(_isSelected(tester, 'uppercase'), isFalse);

    await tester.tap(find.byKey(_key('uppercase')));
    await tester.pump();
    expect(_isSelected(tester, 'uppercase'), isTrue);
    await tester.tap(find.byKey(_key('letter-a')));

    await _selectPrimary(tester, PracticeFormulaPrimaryCategory.physics);
    await tester.tap(find.byKey(_key('more-shortcut')));
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey('practice-formula-section-grid-lettersAndNumbers'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_key('letter-z')),
        matching: find.text('Z'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_key('letter-z')));
    expect(_latex(controller), 'AZ');
  });

  testWidgets('中文入口使用系统文本框并安全插入公式', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(_key('chinese-input')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('practice-formula-chinese-field')),
    );
    expect(field.autofocus, isTrue);
    expect(field.keyboardType, TextInputType.text);
    await tester.enterText(
      find.byKey(const ValueKey('practice-formula-chinese-field')),
      '最大值',
    );
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-chinese-insert')),
    );
    await tester.pumpAndSettle();
    expect(_latex(controller), r'\text{最大值}');
  });

  testWidgets('公式模板使用数学排版并可继续填写槽位', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await _selectSection(tester, PracticeFormulaSection.commonTemplates);

    for (final id in <String>['fraction', 'sqrt', 'scientific-notation']) {
      expect(
        find.descendant(of: find.byKey(_key(id)), matching: find.byType(Math)),
        findsOneWidget,
      );
    }

    await tester.tap(find.byKey(_key('fraction')));
    await tester.tap(find.byKey(_key('3')));
    await tester.tap(find.byKey(_key('next')));
    await tester.tap(find.byKey(_key('2')));
    expect(_latex(controller), r'\frac{3}{2}');

    controller.clear();
    for (final id in <String>[
      '7',
      'divide',
      '8',
      'multiply',
      '9',
      'minus',
      '1',
      'plus',
      '2',
    ]) {
      await tester.tap(find.byKey(_key(id)));
    }
    expect(_latex(controller), r'7\div8\times9-1+2');
  });
}

Widget _app(MathFieldEditingController controller, {VoidCallback? onDone}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PracticeFormulaKeyboard(
          controller: controller,
          onDone: onDone ?? () {},
        ),
      ),
    ),
  );
}

Future<void> _selectPrimary(
  WidgetTester tester,
  PracticeFormulaPrimaryCategory primary,
) async {
  final finder = find.byKey(_primaryKey(primary));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _selectSection(
  WidgetTester tester,
  PracticeFormulaSection section,
) async {
  final finder = find.byKey(_sectionKey(section));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

ValueKey<String> _primaryKey(PracticeFormulaPrimaryCategory primary) =>
    ValueKey<String>('practice-formula-primary-${primary.name}');

ValueKey<String> _sectionKey(PracticeFormulaSection section) =>
    ValueKey<String>('practice-formula-section-${section.name}');

ValueKey<String> _key(String id) =>
    ValueKey<String>('practice-formula-key-$id');

Offset _center(WidgetTester tester, String id) =>
    tester.getCenter(find.byKey(_key(id)));

bool _isSelected(WidgetTester tester, String id) {
  final semantics = tester.widget<Semantics>(
    find
        .ancestor(of: find.byKey(_key(id)), matching: find.byType(Semantics))
        .first,
  );
  return semantics.properties.selected ?? false;
}

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

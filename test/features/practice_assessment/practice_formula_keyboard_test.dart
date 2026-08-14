import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_key_catalog.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_keyboard.dart';

void main() {
  testWidgets('桌面端按左分类中公式右数字三栏排版并固定右侧五行', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    final rail = tester.getRect(
      find.byKey(const ValueKey('practice-formula-category-rail')),
    );
    final auxiliary = tester.getRect(
      find.byKey(const ValueKey('practice-formula-auxiliary-pad-common')),
    );
    final numeric = tester.getRect(
      find.byKey(const ValueKey('practice-formula-numeric-pad')),
    );
    expect(rail.right, lessThan(auxiliary.left));
    expect(auxiliary.right, lessThan(numeric.left));

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
    expect(
      _center(tester, '7').dy,
      greaterThan(_center(tester, 'previous').dy),
    );
    expect(_center(tester, '4').dy, greaterThan(_center(tester, '7').dy));
    expect(_center(tester, '1').dy, greaterThan(_center(tester, '4').dy));
    expect(_center(tester, '0').dy, greaterThan(_center(tester, '1').dy));
    expect(find.byKey(_key('equals')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('希腊和符号分类优先展示高中高频键位', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await _selectCategory(tester, PracticeFormulaKeyboardCategory.greek);
    for (final id in <String>['alpha', 'beta', 'gamma', 'theta', 'pi']) {
      expect(find.byKey(_key(id)), findsOneWidget);
    }

    await _selectCategory(tester, PracticeFormulaKeyboardCategory.symbols);
    for (final id in <String>[
      'less-equal',
      'greater-equal',
      'not-equal',
      'in',
      'union',
      'intersection',
    ]) {
      expect(find.byKey(_key(id)), findsOneWidget);
    }
    expect(
      _center(tester, 'less-equal').dy,
      lessThan(_center(tester, 'parallel').dy),
    );
    expect(
      _center(tester, 'intersection').dy,
      lessThan(_center(tester, 'degree').dy),
    );
  });

  testWidgets('窄屏分类横向滚动且逐类切换不产生布局溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    expect(
      find.byKey(const ValueKey('practice-formula-category-scroll')),
      findsOneWidget,
    );
    for (final category in PracticeFormulaKeyboardCategory.values) {
      await _selectCategory(tester, category);
      expect(
        find.byKey(ValueKey('practice-formula-auxiliary-pad-${category.name}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    _expectSameRow(tester, const ['7', '8', '9', 'divide']);
    _expectSameRow(tester, const ['0', 'decimal', 'plus', 'done']);
  });

  testWidgets('字母页通过手机式大写键切换并保持 abc 仅作为入口', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(_key('more-shortcut')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('practice-formula-auxiliary-pad-letters')),
      findsOneWidget,
    );
    for (final letter in 'abcdefghijklmnopqrstuvwxyz'.split('')) {
      expect(find.byKey(_key('letter-$letter')), findsOneWidget);
    }
    expect(find.byKey(_key('uppercase')), findsOneWidget);
    expect(find.text('⇧ 大写'), findsOneWidget);
    expect(find.text('小写'), findsNothing);
    expect(_isSelected(tester, 'uppercase'), isFalse);

    await tester.tap(find.byKey(_key('more-shortcut')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(_key('letter-a')),
        matching: find.text('a'),
      ),
      findsOneWidget,
    );
    expect(_isSelected(tester, 'uppercase'), isFalse);

    await tester.tap(find.byKey(_key('uppercase')));
    await tester.pump();
    expect(_isSelected(tester, 'uppercase'), isTrue);
    expect(
      find.descendant(
        of: find.byKey(_key('letter-a')),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_key('letter-a')));
    await tester.tap(find.byKey(_key('letter-z')));

    await tester.tap(find.byKey(_key('uppercase')));
    await tester.pump();
    expect(_isSelected(tester, 'uppercase'), isFalse);
    expect(find.text('小写'), findsNothing);
    await tester.tap(find.byKey(_key('letter-b')));
    expect(_latex(controller), 'AZb');
  });

  testWidgets('中文入口使用系统文本框并把确认内容插入公式', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(_key('more-shortcut')));
    await tester.pump();
    await tester.tap(find.byKey(_key('chinese-input')));
    await tester.pumpAndSettle();

    expect(find.text('输入中文'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('practice-formula-chinese-field')),
    );
    expect(field.autofocus, isTrue);
    expect(field.keyboardType, TextInputType.text);
    expect(field.enableSuggestions, isTrue);
    expect(field.autocorrect, isTrue);
    expect(field.textCapitalization, TextCapitalization.none);
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

  testWidgets('中文输入取消不改变公式且确认回调仍只调用一次', (tester) async {
    final controller = MathFieldEditingController();
    var doneCount = 0;
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, onDone: () => doneCount += 1));

    await tester.tap(find.byKey(_key('more-shortcut')));
    await tester.pump();
    await tester.tap(find.byKey(_key('chinese-input')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('practice-formula-chinese-field')),
      '不应插入',
    );
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-chinese-cancel')),
    );
    await tester.pumpAndSettle();
    expect(_latex(controller), isEmpty);

    await tester.tap(find.byKey(_key('done')));
    expect(doneCount, 1);
  });

  testWidgets('结构键帽使用真正数学排版并可继续填写槽位', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await _selectCategory(tester, PracticeFormulaKeyboardCategory.structures);
    for (final id in <String>['fraction', 'sqrt', 'sum']) {
      expect(
        find.descendant(of: find.byKey(_key(id)), matching: find.byType(Math)),
        findsOneWidget,
      );
    }

    controller.addLeaf('x');
    await tester.tap(find.byKey(_key('square')));
    expect(_latex(controller), r'x^{2}');

    controller.clear();
    await tester.tap(find.byKey(_key('fraction')));
    await tester.tap(find.byKey(_key('3')));
    await tester.tap(find.byKey(_key('next')));
    await tester.tap(find.byKey(_key('2')));
    expect(_latex(controller), r'\frac{3}{2}');
  });

  testWidgets('数字函数关系键写入受控 LaTeX', (tester) async {
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
      'plus',
      '2',
    ]) {
      await tester.tap(find.byKey(_key(id)));
    }
    expect(_latex(controller), r'7\div8\times9-1+2');

    controller.clear();
    await _selectCategory(tester, PracticeFormulaKeyboardCategory.functions);
    await tester.tap(find.byKey(_key('sin')));
    await _selectCategory(tester, PracticeFormulaKeyboardCategory.common);
    await tester.tap(find.byKey(_key('equals')));
    expect(_latex(controller), r'\sin(=)');

    controller.clear();
    await _selectCategory(tester, PracticeFormulaKeyboardCategory.symbols);
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
  });

  testWidgets('极限求和与积分键提供可按顺序填写的上下限槽位', (tester) async {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await _selectCategory(tester, PracticeFormulaKeyboardCategory.functions);

    await tester.tap(find.byKey(_key('limit')));
    await _selectCategory(tester, PracticeFormulaKeyboardCategory.common);
    await tester.tap(find.byKey(_key('equals')));
    expect(_latex(controller), r'\lim_{=}');

    controller.clear();
    await _selectCategory(tester, PracticeFormulaKeyboardCategory.functions);
    await tester.tap(find.byKey(_key('sum')));
    await tester.tap(find.byKey(_key('1')));
    await tester.tap(find.byKey(_key('next')));
    await _selectCategory(tester, PracticeFormulaKeyboardCategory.more);
    await tester.tap(find.byKey(_key('m')));
    expect(_latex(controller), r'\sum_{1}^{m}');

    controller.clear();
    await _selectCategory(tester, PracticeFormulaKeyboardCategory.functions);
    await tester.tap(find.byKey(_key('integral')));
    await tester.tap(find.byKey(_key('0')));
    await tester.tap(find.byKey(_key('next')));
    await tester.tap(find.byKey(_key('1')));
    expect(_latex(controller), r'\int_{0}^{1}');
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

Future<void> _selectCategory(
  WidgetTester tester,
  PracticeFormulaKeyboardCategory category,
) async {
  final finder = find.byKey(
    ValueKey('practice-formula-category-${category.name}'),
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

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

import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_key_catalog.dart';

void main() {
  test('目录按九类组织并把高频关系符号放在符号页最前', () {
    expect(
      PracticeFormulaKeyboardCategory.values.map((item) => item.name),
      <String>[
        'common',
        'structures',
        'symbols',
        'functions',
        'greek',
        'physics',
        'units',
        'letters',
        'more',
      ],
    );

    expect(
      practiceFormulaCategoryKeys[PracticeFormulaKeyboardCategory.symbols]!
          .take(6)
          .map((item) => item.id),
      <String>[
        'less-equal',
        'greater-equal',
        'not-equal',
        'in',
        'union',
        'intersection',
      ],
    );

    final allKeys = <PracticeFormulaKeySpec>[
      ...practiceFormulaCategoryKeys.values.expand((items) => items),
      ...practiceFormulaNumericKeys,
    ];
    expect(allKeys.where((item) => item.id == 'equals'), hasLength(1));
    expect(
      practiceFormulaCategoryKeys[PracticeFormulaKeyboardCategory.greek]!.map(
        (item) => item.id,
      ),
      containsAll(<String>['alpha', 'beta', 'gamma', 'theta', 'pi']),
    );
  });

  test('字母目录完整产生二十六个小写或大写键', () {
    final lowercase = practiceFormulaAlphabetKeys(uppercase: false);
    final uppercase = practiceFormulaAlphabetKeys(uppercase: true);

    expect(lowercase, hasLength(26));
    expect(
      lowercase.map((item) => item.label).join(),
      'abcdefghijklmnopqrstuvwxyz',
    );
    expect(uppercase, hasLength(26));
    expect(
      uppercase.map((item) => item.label).join(),
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    );

    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    lowercase.first.action(controller);
    uppercase.last.action(controller);
    expect(_latex(controller), 'aZ');
  });

  test('中文文本以受控 text 节点插入并转义 TeX 特殊字符', () {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    insertPracticeFormulaText(controller, '最大值{a}_%');

    expect(_latex(controller), r'\text{最大值\{a\}\_\%}');
  });

  test('希腊字母物理矢量和单位键写入受控 LaTeX', () {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    _key(PracticeFormulaKeyboardCategory.greek, 'alpha').action(controller);
    expect(_latex(controller), r'\alpha');

    controller.clear();
    _key(
      PracticeFormulaKeyboardCategory.physics,
      'vector-force',
    ).action(controller);
    expect(_latex(controller), r'\vec{F}');

    controller.clear();
    controller.addLeaf('5');
    _key(
      PracticeFormulaKeyboardCategory.units,
      'unit-metre',
    ).action(controller);
    expect(_latex(controller), r'5\,\mathrm{m}');
  });
}

PracticeFormulaKeySpec _key(
  PracticeFormulaKeyboardCategory category,
  String id,
) =>
    practiceFormulaCategoryKeys[category]!.singleWhere((item) => item.id == id);

String _latex(MathFieldEditingController controller) => controller
    .currentEditingValue(placeholderWhenEmpty: false)
    .replaceAll(' ', '');

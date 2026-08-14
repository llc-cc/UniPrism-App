import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_key_catalog.dart';

void main() {
  test('目录固定为三个一级分类和八个二级标签', () {
    expect(
      PracticeFormulaPrimaryCategory.values.map((item) => item.name),
      <String>['common', 'mathematics', 'physics'],
    );
    expect(PracticeFormulaSection.values.map((item) => item.name), <String>[
      'lettersAndNumbers',
      'commonSymbols',
      'commonTemplates',
      'mathSymbols',
      'mathTemplates',
      'physicsSymbols',
      'physicsUnits',
      'physicsConstants',
    ]);
    expect(
      practiceFormulaSectionsByPrimary,
      <PracticeFormulaPrimaryCategory, List<PracticeFormulaSection>>{
        PracticeFormulaPrimaryCategory.common: <PracticeFormulaSection>[
          PracticeFormulaSection.lettersAndNumbers,
          PracticeFormulaSection.commonSymbols,
          PracticeFormulaSection.commonTemplates,
        ],
        PracticeFormulaPrimaryCategory.mathematics: <PracticeFormulaSection>[
          PracticeFormulaSection.mathSymbols,
          PracticeFormulaSection.mathTemplates,
        ],
        PracticeFormulaPrimaryCategory.physics: <PracticeFormulaSection>[
          PracticeFormulaSection.physicsSymbols,
          PracticeFormulaSection.physicsUnits,
          PracticeFormulaSection.physicsConstants,
        ],
      },
    );
  });

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

  test('常用目录覆盖唯一主位置', () {
    expect(
      practiceFormulaCommonSectionKeys[PracticeFormulaSection.commonSymbols]!
          .map((item) => item.id)
          .toSet(),
      <String>{
        'plus-minus',
        'dot-multiply',
        'slash',
        'equals',
        'not-equal',
        'approx',
        'less',
        'greater',
        'less-equal',
        'greater-equal',
        'percent',
        'degree',
        'comma',
        'semicolon',
        'factorial',
        'ellipsis',
      },
    );
    expect(
      practiceFormulaCommonSectionKeys[PracticeFormulaSection.commonTemplates]!
          .map((item) => item.id)
          .toSet(),
      <String>{
        'fraction',
        'power',
        'square',
        'cube',
        'subscript',
        'sub-superscript',
        'sqrt',
        'nth-root',
        'parentheses',
        'brackets',
        'braces',
        'absolute',
        'overline',
        'vector',
        'scientific-notation',
      },
    );

    final fixedIds = practiceFormulaNumericKeys.map((item) => item.id).toSet();
    expect(
      fixedIds,
      containsAll(<String>{
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        'decimal',
        'plus',
        'minus',
        'multiply',
        'divide',
      }),
    );
    final gridIds = practiceFormulaCommonSectionKeys.values
        .expand((items) => items)
        .map((item) => item.id)
        .toSet();
    expect(
      gridIds.intersection(<String>{
        'decimal',
        'plus',
        'minus',
        'multiply',
        'divide',
      }),
      isEmpty,
    );
    expect(practiceFormulaLetterAndNumberKeys(uppercase: false), hasLength(30));
    expect(
      practiceFormulaLetterAndNumberKeys(
        uppercase: true,
      ).take(26).map((item) => item.label).join(),
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    );
  });

  test('数学符号目录精确覆盖三十三个教材符号', () {
    final symbols =
        practiceFormulaMathSectionKeys[PracticeFormulaSection.mathSymbols]!;
    final latexById = <String, String>{
      for (final key in symbols) key.id: key.expectedLatex,
    };

    expect(latexById, hasLength(33));
    expect(latexById, <String, String>{
      'infinity': r'\infty',
      'equivalent': r'\equiv',
      'arrow': r'\to',
      'prime': "'",
      'empty-set': r'\varnothing',
      'in': r'\in',
      'not-in': r'\notin',
      'subset': r'\subset',
      'subset-equal': r'\subseteq',
      'union': r'\cup',
      'intersection': r'\cap',
      'set-minus': r'\setminus',
      'complement': r'\complement',
      'divides': r'\mid',
      'natural-set': r'\mathbb{N}',
      'integer-set': r'\mathbb{Z}',
      'rational-set': r'\mathbb{Q}',
      'real-set': r'\mathbb{R}',
      'complex-set': r'\mathbb{C}',
      'forall': r'\forall',
      'exists': r'\exists',
      'not': r'\neg',
      'logical-and': r'\land',
      'logical-or': r'\lor',
      'implies': r'\Rightarrow',
      'iff': r'\Leftrightarrow',
      'angle': r'\angle',
      'triangle': r'\triangle',
      'perpendicular': r'\perp',
      'parallel': r'\parallel',
      'congruent': r'\cong',
      'similar': r'\sim',
      'sigma': r'\sigma',
    });
    expect(latexById['empty-set'], isNot(r'\emptyset'));
  });

  test('数学模板覆盖十五项并按语义顺序填写复合槽位', () {
    final templates =
        practiceFormulaMathSectionKeys[PracticeFormulaSection.mathTemplates]!;
    expect(
      <String, String>{for (final key in templates) key.id: key.expectedLatex},
      <String, String>{
        'log-base': r'\log_{}\left(\right)',
        'common-log': r'\lg\left(\right)',
        'natural-log': r'\ln\left(\right)',
        'sin': r'\sin\left(\right)',
        'cos': r'\cos\left(\right)',
        'tan': r'\tan\left(\right)',
        'derivative': r"f'\left(\right)",
        'permutation': r'A_{}^{}',
        'combination': r'C_{}^{}',
        'probability': r'P\left(\right)',
        'conditional-prob': r'P\left({}\mid{}\right)',
        'set-builder': r'\left\{x\mid{}\right\}',
        'open-interval': r'\left({},{}\right)',
        'closed-interval': r'\left[{},{}\right]',
        'cases': r'\begin{cases}{}\\{}\end{cases}',
      },
    );

    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    templates
        .singleWhere((key) => key.id == 'conditional-prob')
        .insert(controller);
    controller
      ..addLeaf('A')
      ..goNext()
      ..addLeaf('B');
    expect(_latex(controller), r'P\left({A}\mid{B}\right)');

    controller.clear();
    templates
        .singleWhere((key) => key.id == 'open-interval')
        .insert(controller);
    controller
      ..addLeaf('1')
      ..goNext()
      ..addLeaf('2');
    expect(_latex(controller), r'\left({1},{2}\right)');

    controller.clear();
    templates.singleWhere((key) => key.id == 'cases').insert(controller);
    controller
      ..addLeaf('x')
      ..goNext()
      ..addLeaf('-x');
    expect(_latex(controller), r'\begin{cases}{x}\\{-x}\end{cases}');

    final officialIds = practiceFormulaMathSectionKeys.values
        .expand((items) => items)
        .map((key) => key.id)
        .toSet();
    expect(
      officialIds.intersection(
        practiceFormulaExtendedKeys.map((key) => key.id).toSet(),
      ),
      isEmpty,
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

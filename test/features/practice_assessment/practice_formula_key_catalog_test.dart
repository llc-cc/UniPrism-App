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

  test('正式目录键位 ID 唯一且展示位置合法', () {
    expect(validatePracticeFormulaCatalog, returnsNormally);
    expect(
      <PracticeFormulaSection, int>{
        for (final entry in practiceFormulaSectionKeys.entries)
          entry.key: entry.value.length,
      },
      <PracticeFormulaSection, int>{
        PracticeFormulaSection.lettersAndNumbers: 30,
        PracticeFormulaSection.commonSymbols: 16,
        PracticeFormulaSection.commonTemplates: 15,
        PracticeFormulaSection.mathSymbols: 33,
        PracticeFormulaSection.mathTemplates: 15,
        PracticeFormulaSection.physicsSymbols: 11,
        PracticeFormulaSection.physicsUnits: 51,
        PracticeFormulaSection.physicsConstants: 10,
      },
    );

    final official = practiceFormulaSectionKeys.values
        .expand((items) => items)
        .toList(growable: false);
    expect(official, hasLength(181));
    expect(official.map((item) => item.id).toSet(), hasLength(official.length));
    expect(
      official.where(
        (item) => item.placement == PracticeFormulaKeyPlacement.fixedPad,
      ),
      isEmpty,
    );
    for (final entry in practiceFormulaSectionKeys.entries) {
      expect(entry.value.every((item) => item.section == entry.key), isTrue);
    }
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

  test('物理符号覆盖十一项且核素按质量数原子序数元素填写', () {
    final symbols =
        practiceFormulaPhysicsSectionKeys[PracticeFormulaSection
            .physicsSymbols]!;
    expect(symbols, hasLength(11));
    expect(
      <String, String>{for (final key in symbols) key.id: key.expectedLatex},
      <String, String>{
        'physics-delta': r'\Delta',
        'physics-rho': r'\rho',
        'physics-eta': r'\eta',
        'physics-mu': r'\mu',
        'physics-lambda': r'\lambda',
        'physics-nu': r'\nu',
        'physics-omega': r'\omega',
        'physics-varphi': r'\varphi',
        'physics-capital-phi': r'\Phi',
        'physics-gamma': r'\gamma',
        'nucleus': r'{}_{Z}^{A}X',
      },
    );

    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    symbols.singleWhere((key) => key.id == 'nucleus').insert(controller);
    controller
      ..addLeaf('14')
      ..goNext()
      ..addLeaf('6')
      ..goNext()
      ..addLeaf('C');
    expect(_latex(controller), r'{}_{6}^{14}C');
  });

  test('物理单位精确覆盖五十一项并按上下文补单位间距', () {
    final units =
        practiceFormulaPhysicsSectionKeys[PracticeFormulaSection.physicsUnits]!;
    expect(
      <String, String>{for (final key in units) key.id: key.expectedLatex},
      <String, String>{
        'unit-mm': r'\mathrm{mm}',
        'unit-nm': r'\mathrm{nm}',
        'unit-cm': r'\mathrm{cm}',
        'unit-m': r'\mathrm{m}',
        'unit-km': r'\mathrm{km}',
        'unit-mL': r'\mathrm{mL}',
        'unit-L': r'\mathrm{L}',
        'unit-mg': r'\mathrm{mg}',
        'unit-g': r'\mathrm{g}',
        'unit-kg': r'\mathrm{kg}',
        'unit-t': r'\mathrm{t}',
        'unit-s': r'\mathrm{s}',
        'unit-ms': r'\mathrm{ms}',
        'unit-min': r'\mathrm{min}',
        'unit-h': r'\mathrm{h}',
        'unit-celsius': r'^{\circ}\mathrm{C}',
        'unit-K': r'\mathrm{K}',
        'unit-rad': r'\mathrm{rad}',
        'unit-Hz': r'\mathrm{Hz}',
        'unit-kHz': r'\mathrm{kHz}',
        'unit-MHz': r'\mathrm{MHz}',
        'unit-dB': r'\mathrm{dB}',
        'unit-N': r'\mathrm{N}',
        'unit-Pa': r'\mathrm{Pa}',
        'unit-kPa': r'\mathrm{kPa}',
        'unit-J': r'\mathrm{J}',
        'unit-W': r'\mathrm{W}',
        'unit-kW': r'\mathrm{kW}',
        'unit-C': r'\mathrm{C}',
        'unit-A': r'\mathrm{A}',
        'unit-mA': r'\mathrm{mA}',
        'unit-microA': r'\mu\mathrm{A}',
        'unit-V': r'\mathrm{V}',
        'unit-ohm': r'\Omega',
        'unit-kilohm': r'\mathrm{k}\Omega',
        'unit-megaohm': r'\mathrm{M}\Omega',
        'unit-F': r'\mathrm{F}',
        'unit-microF': r'\mu\mathrm{F}',
        'unit-Wb': r'\mathrm{Wb}',
        'unit-T': r'\mathrm{T}',
        'unit-mol': r'\mathrm{mol}',
        'unit-eV': r'\mathrm{eV}',
        'unit-u': r'\mathrm{u}',
        'unit-m-per-s': r'\mathrm{m}/\mathrm{s}',
        'unit-km-per-h': r'\mathrm{km}/\mathrm{h}',
        'unit-m-per-s2': r'\mathrm{m}/\mathrm{s}^{2}',
        'unit-kg-per-m3': r'\mathrm{kg}/\mathrm{m}^{3}',
        'unit-g-per-cm3': r'\mathrm{g}/\mathrm{cm}^{3}',
        'unit-N-per-C': r'\mathrm{N}/\mathrm{C}',
        'unit-rad-per-s': r'\mathrm{rad}/\mathrm{s}',
        'unit-kW-hour': r'\mathrm{kW}\cdot\mathrm{h}',
      },
    );
    expect(units, hasLength(51));

    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    final metre = units.singleWhere((key) => key.id == 'unit-m');
    metre.insert(controller);
    expect(_latex(controller), r'\mathrm{m}');
    controller
      ..clear()
      ..addLeaf('5');
    metre.insert(controller);
    expect(_latex(controller), r'5\,\mathrm{m}');
  });

  test('物理常数保留十项教材说明并受控插入组合下标', () {
    final constants =
        practiceFormulaPhysicsSectionKeys[PracticeFormulaSection
            .physicsConstants]!;
    expect(
      <String, String>{for (final key in constants) key.id: key.usage},
      <String, String>{
        'constant-g':
            r'常取 9.8\,\mathrm{m}/\mathrm{s}^{2}，题目有时取 10\,\mathrm{m}/\mathrm{s}^{2}',
        'constant-G':
            r'6.67\times10^{-11}\,\mathrm{N}\cdot\mathrm{m}^{2}/\mathrm{kg}^{2}',
        'constant-c': r'3.0\times10^{8}\,\mathrm{m}/\mathrm{s}',
        'constant-k':
            r'9.0\times10^{9}\,\mathrm{N}\cdot\mathrm{m}^{2}/\mathrm{C}^{2}',
        'constant-e': r'1.60\times10^{-19}\,\mathrm{C}',
        'constant-h': r'6.63\times10^{-34}\,\mathrm{J}\cdot\mathrm{s}',
        'constant-NA': r'6.02\times10^{23}\,\mathrm{mol}^{-1}',
        'constant-kB': r'1.38\times10^{-23}\,\mathrm{J}/\mathrm{K}',
        'constant-R': r'8.31\,\mathrm{J}/(\mathrm{mol}\cdot\mathrm{K})',
        'constant-p0': r'常取 1.01\times10^{5}\,\mathrm{Pa}',
      },
    );
    expect(constants, hasLength(10));

    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);
    for (final entry in <String, String>{
      'constant-NA': r'N_{A}',
      'constant-kB': r'k_{B}',
      'constant-p0': r'p_{0}',
    }.entries) {
      controller.clear();
      constants.singleWhere((key) => key.id == entry.key).insert(controller);
      expect(_latex(controller), entry.value);
    }
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

  test('正式目录普通符号和单位键写入受控 LaTeX', () {
    final controller = MathFieldEditingController();
    addTearDown(controller.dispose);

    practiceFormulaKeysForSection(
      PracticeFormulaSection.lettersAndNumbers,
    ).singleWhere((item) => item.id == 'alpha').insert(controller);
    expect(_latex(controller), r'\alpha');

    controller.clear();
    controller.addLeaf('5');
    practiceFormulaKeysForSection(
      PracticeFormulaSection.physicsUnits,
    ).singleWhere((item) => item.id == 'unit-m').insert(controller);
    expect(_latex(controller), r'5\,\mathrm{m}');
  });
}

String _latex(MathFieldEditingController controller) => controller
    .currentEditingValue(placeholderWhenEmpty: false)
    .replaceAll(' ', '');

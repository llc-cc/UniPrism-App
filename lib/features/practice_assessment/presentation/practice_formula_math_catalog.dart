import 'practice_formula_insertions.dart';
import 'practice_formula_key_models.dart';

/// 数学符号按教材目录顺序声明，显示字符与规范 LaTeX 分开保存。
final List<PracticeFormulaKeySpec> _mathSymbolKeys = <PracticeFormulaKeySpec>[
  _mathSymbol('infinity', '∞', '无穷', r'\infty'),
  _mathSymbol('equivalent', '≡', '恒等于', r'\equiv'),
  _mathSymbol('arrow', '→', '趋向箭头', r'\to'),
  _mathSymbol('prime', '′', '撇号', "'"),
  _mathSymbol('empty-set', '∅', '空集', r'\varnothing'),
  _mathSymbol('in', '∈', '属于', r'\in'),
  _mathSymbol('not-in', '∉', '不属于', r'\notin'),
  _mathSymbol('subset', '⊂', '真子集', r'\subset'),
  _mathSymbol('subset-equal', '⊆', '子集或相等', r'\subseteq'),
  _mathSymbol('union', '∪', '并集', r'\cup'),
  _mathSymbol('intersection', '∩', '交集', r'\cap'),
  _mathSymbol('set-minus', '∖', '集合差', r'\setminus'),
  _mathSymbol('complement', '∁', '补集', r'\complement'),
  _mathSymbol('divides', '|', '整除或条件分隔', r'\mid'),
  _mathSymbol('natural-set', 'ℕ', '自然数集', r'\mathbb{N}'),
  _mathSymbol('integer-set', 'ℤ', '整数集', r'\mathbb{Z}'),
  _mathSymbol('rational-set', 'ℚ', '有理数集', r'\mathbb{Q}'),
  _mathSymbol('real-set', 'ℝ', '实数集', r'\mathbb{R}'),
  _mathSymbol('complex-set', 'ℂ', '复数集', r'\mathbb{C}'),
  _mathSymbol('forall', '∀', '任意', r'\forall'),
  _mathSymbol('exists', '∃', '存在', r'\exists'),
  _mathSymbol('not', '¬', '逻辑非', r'\neg'),
  _mathSymbol('logical-and', '∧', '逻辑与', r'\land'),
  _mathSymbol('logical-or', '∨', '逻辑或', r'\lor'),
  _mathSymbol('implies', '⇒', '推出', r'\Rightarrow'),
  _mathSymbol('iff', '⇔', '等价', r'\Leftrightarrow'),
  _mathSymbol('angle', '∠', '角', r'\angle'),
  _mathSymbol('triangle', '△', '三角形', r'\triangle'),
  _mathSymbol('perpendicular', '⊥', '垂直', r'\perp'),
  _mathSymbol('parallel', '∥', '平行', r'\parallel'),
  _mathSymbol('congruent', '≅', '全等', r'\cong'),
  _mathSymbol('similar', '∼', '相似', r'\sim'),
  _mathSymbol('sigma', 'σ', '希腊字母 sigma', r'\sigma'),
];

final PracticeFormulaKeySpec practiceFormulaConditionalProbabilityKey =
    _mathTemplate(
      'conditional-prob',
      r'P\left(\Box\mid\Box\right)',
      '条件概率',
      r'P\left({}\mid{}\right)',
      '依次填写事件和条件事件',
      const CompositeFormulaInsertion(<String>[
        r'P\left({',
        r'}\mid{',
        r'}\right)',
      ]),
    );

final List<PracticeFormulaKeySpec> _mathTemplateKeys = <PracticeFormulaKeySpec>[
  _mathTemplate(
    'log-base',
    r'\log_{\Box}\left(\Box\right)',
    '带底对数',
    r'\log_{}\left(\right)',
    '依次填写底数和真数',
    const CompositeFormulaInsertion(<String>[
      r'\log_{',
      r'}\left(',
      r'\right)',
    ]),
  ),
  _mathTemplate(
    'common-log',
    r'\lg\left(\Box\right)',
    '常用对数',
    r'\lg\left(\right)',
    '填写常用对数的真数',
    const CompositeFormulaInsertion(<String>[r'\lg\left(', r'\right)']),
  ),
  _mathTemplate(
    'natural-log',
    r'\ln\left(\Box\right)',
    '自然对数',
    r'\ln\left(\right)',
    '填写自然对数的真数',
    const CompositeFormulaInsertion(<String>[r'\ln\left(', r'\right)']),
  ),
  _mathTemplate(
    'sin',
    r'\sin\left(\Box\right)',
    '正弦',
    r'\sin\left(\right)',
    '填写正弦函数的自变量',
    const CompositeFormulaInsertion(<String>[r'\sin\left(', r'\right)']),
  ),
  _mathTemplate(
    'cos',
    r'\cos\left(\Box\right)',
    '余弦',
    r'\cos\left(\right)',
    '填写余弦函数的自变量',
    const CompositeFormulaInsertion(<String>[r'\cos\left(', r'\right)']),
  ),
  _mathTemplate(
    'tan',
    r'\tan\left(\Box\right)',
    '正切',
    r'\tan\left(\right)',
    '填写正切函数的自变量',
    const CompositeFormulaInsertion(<String>[r'\tan\left(', r'\right)']),
  ),
  _mathTemplate(
    'derivative',
    r"f'\left(\Box\right)",
    '导函数',
    r"f'\left(\right)",
    '填写导函数的自变量',
    const CompositeFormulaInsertion(<String>[r"f'\left(", r'\right)']),
  ),
  _mathTemplate(
    'permutation',
    r'A_{\Box}^{\Box}',
    '排列数',
    r'A_{}^{}',
    '依次填写下标和上标',
    const CompositeFormulaInsertion(<String>[r'A_{', r'}^{', '}']),
  ),
  _mathTemplate(
    'combination',
    r'C_{\Box}^{\Box}',
    '组合数',
    r'C_{}^{}',
    '依次填写下标和上标',
    const CompositeFormulaInsertion(<String>[r'C_{', r'}^{', '}']),
  ),
  _mathTemplate(
    'probability',
    r'P\left(\Box\right)',
    '概率',
    r'P\left(\right)',
    '填写事件',
    const CompositeFormulaInsertion(<String>[r'P\left(', r'\right)']),
  ),
  practiceFormulaConditionalProbabilityKey,
  _mathTemplate(
    'set-builder',
    r'\left\{x\mid\Box\right\}',
    '描述法集合',
    r'\left\{x\mid{}\right\}',
    '填写集合中元素满足的条件',
    const CompositeFormulaInsertion(<String>[r'\left\{x\mid{', r'}\right\}']),
  ),
  _mathTemplate(
    'open-interval',
    r'\left(\Box,\Box\right)',
    '开区间',
    r'\left({},{}\right)',
    '依次填写左端点和右端点',
    const CompositeFormulaInsertion(<String>[r'\left({', r'},{', r'}\right)']),
  ),
  _mathTemplate(
    'closed-interval',
    r'\left[\Box,\Box\right]',
    '闭区间',
    r'\left[{},{}\right]',
    '依次填写左端点和右端点',
    const CompositeFormulaInsertion(<String>[r'\left[{', r'},{', r'}\right]']),
  ),
  _mathTemplate(
    'cases',
    r'\begin{cases}\Box\\\Box\end{cases}',
    '方程组或分段结构',
    r'\begin{cases}{}\\{}\end{cases}',
    '依次填写两行表达式',
    const CompositeFormulaInsertion(<String>[
      r'\begin{cases}{',
      r'}\\{',
      r'}\end{cases}',
    ]),
  ),
];

/// 正式数学目录仅包含附件定义的 33 个符号和 15 个模板。
final Map<PracticeFormulaSection, List<PracticeFormulaKeySpec>>
practiceFormulaMathSectionKeys =
    <PracticeFormulaSection, List<PracticeFormulaKeySpec>>{
      PracticeFormulaSection.mathSymbols: _mathSymbolKeys,
      PracticeFormulaSection.mathTemplates: _mathTemplateKeys,
    };

/// 既有高级能力留作未来扩展，不参与八个正式标签的唯一位置校验。
final List<PracticeFormulaKeySpec> practiceFormulaExtendedKeys =
    <PracticeFormulaKeySpec>[
      _extendedTemplate(
        'norm',
        r'\left\lVert\Box\right\rVert',
        '范数',
        r'\left\lVert\right\rVert',
        const PairFormulaInsertion(r'\left\lVert', r'\right\rVert'),
      ),
      _extendedTemplate(
        'overrightarrow',
        r'\overrightarrow{\Box}',
        '有向线段',
        r'\overrightarrow{}',
        const FunctionFormulaInsertion(
          r'\overrightarrow',
          <PracticeFormulaArgument>[PracticeFormulaArgument.braces],
        ),
      ),
      _extendedTemplate(
        'limit',
        r'\lim_{\Box}',
        '极限',
        r'\lim_{}',
        const CompositeFormulaInsertion(<String>[r'\lim_{', '}']),
      ),
      _extendedTemplate(
        'sum',
        r'\sum_{\Box}^{\Box}',
        '求和',
        r'\sum_{}^{}',
        const CompositeFormulaInsertion(<String>[r'\sum_{', r'}^{', '}']),
      ),
      _extendedTemplate(
        'integral',
        r'\int_{\Box}^{\Box}',
        '积分',
        r'\int_{}^{}',
        const CompositeFormulaInsertion(<String>[r'\int_{', r'}^{', '}']),
      ),
      _extendedTemplate(
        'product',
        r'\prod_{\Box}^{\Box}',
        '连乘',
        r'\prod_{}^{}',
        const CompositeFormulaInsertion(<String>[r'\prod_{', r'}^{', '}']),
      ),
      _extendedTemplate(
        'cot',
        r'\cot\left(\Box\right)',
        '余切',
        r'\cot\left(\right)',
        const CompositeFormulaInsertion(<String>[r'\cot\left(', r'\right)']),
      ),
      _extendedTemplate(
        'exp',
        r'e^{\Box}',
        '指数函数',
        r'e^{}',
        const CompositeFormulaInsertion(<String>[r'e^{', '}']),
      ),
      _extendedTemplate(
        'max',
        r'\max\left(\Box\right)',
        '最大值',
        r'\max\left(\right)',
        const CompositeFormulaInsertion(<String>[r'\max\left(', r'\right)']),
      ),
      _extendedTemplate(
        'min',
        r'\min\left(\Box\right)',
        '最小值',
        r'\min\left(\right)',
        const CompositeFormulaInsertion(<String>[r'\min\left(', r'\right)']),
      ),
    ];

PracticeFormulaKeySpec _mathSymbol(
  String id,
  String label,
  String name,
  String latex,
) => PracticeFormulaKeySpec.catalog(
  id: id,
  label: label,
  name: name,
  semanticLabel: name,
  expectedLatex: latex,
  kind: PracticeFormulaKeyKind.symbol,
  section: PracticeFormulaSection.mathSymbols,
  placement: PracticeFormulaKeyPlacement.sectionGrid,
  usage: '输入$name',
  insertion: LeafFormulaInsertion(latex.startsWith(r'\') ? '$latex ' : latex),
);

PracticeFormulaKeySpec _mathTemplate(
  String id,
  String label,
  String name,
  String expectedLatex,
  String usage,
  PracticeFormulaInsertion insertion,
) => PracticeFormulaKeySpec.catalog(
  id: id,
  label: label,
  name: name,
  semanticLabel: '插入$name模板',
  expectedLatex: expectedLatex,
  kind: PracticeFormulaKeyKind.template,
  section: PracticeFormulaSection.mathTemplates,
  placement: PracticeFormulaKeyPlacement.sectionGrid,
  usage: usage,
  insertion: insertion,
  isTexLabel: true,
);

PracticeFormulaKeySpec _extendedTemplate(
  String id,
  String label,
  String name,
  String expectedLatex,
  PracticeFormulaInsertion insertion,
) => PracticeFormulaKeySpec.catalog(
  id: 'extended-$id',
  label: label,
  name: name,
  semanticLabel: '插入$name',
  expectedLatex: expectedLatex,
  kind: PracticeFormulaKeyKind.template,
  section: PracticeFormulaSection.mathTemplates,
  placement: PracticeFormulaKeyPlacement.semanticShortcut,
  usage: '目录外扩展能力',
  insertion: insertion,
  isTexLabel: true,
);

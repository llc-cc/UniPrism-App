import 'practice_formula_insertions.dart';
import 'practice_formula_key_models.dart';

/// 数学符号按教材目录顺序声明，显示字符与规范 LaTeX 分开保存。
final List<PracticeFormulaKeySpec> _mathSymbolKeys = <PracticeFormulaKeySpec>[
  _mathSymbol('infinity', '∞', '无穷', r'\infty', usage: '表示无界大的量，用于极限、区间等'),
  _mathSymbol('equivalent', '≡', '恒等于', r'\equiv', usage: '两端表达式对所有变量值都相等，常用于恒等变形'),
  _mathSymbol('arrow', '→', '趋向箭头', r'\to', usage: '变量趋向某值，也用于函数映射方向'),
  _mathSymbol('prime', '′', '撇号', "'", usage: '表示导数或角分，如 f′(x)'),
  _mathSymbol('empty-set', '∅', '空集', r'\varnothing', usage: '不含任何元素的集合'),
  _mathSymbol('in', '∈', '属于', r'\in', usage: '元素属于某集合，如 x ∈ ℝ'),
  _mathSymbol('not-in', '∉', '不属于', r'\notin', usage: '元素不在某集合中'),
  _mathSymbol('subset', '⊂', '真子集', r'\subset', usage: 'A ⊂ B 表示 A 是 B 的真子集'),
  _mathSymbol('subset-equal', '⊆', '子集', r'\subseteq', usage: 'A ⊆ B 表示 A 是 B 的子集（含相等）'),
  _mathSymbol('union', '∪', '并集', r'\cup', usage: '两个集合的所有元素合并'),
  _mathSymbol('intersection', '∩', '交集', r'\cap', usage: '两个集合共同包含的元素'),
  _mathSymbol('set-minus', '∖', '差集', r'\setminus', usage: 'A ∖ B 表示属于 A 但不属于 B 的元素'),
  _mathSymbol('complement', '∁', '补集', r'\complement', usage: '全集中不属于某集合的所有元素'),
  _mathSymbol('divides', '|', '整除 / 使得', r'\mid', usage: '集合描述法中的"使得"，或整除关系'),
  _mathSymbol('natural-set', 'ℕ', '自然数集', r'\mathbb{N}', usage: '包含 0 和全体正整数的集合'),
  _mathSymbol('integer-set', 'ℤ', '整数集', r'\mathbb{Z}', usage: '全体整数（含负整数）的集合'),
  _mathSymbol('rational-set', 'ℚ', '有理数集', r'\mathbb{Q}', usage: '可表示为分数的数的集合'),
  _mathSymbol('real-set', 'ℝ', '实数集', r'\mathbb{R}', usage: '有理数与无理数的全体'),
  _mathSymbol('complex-set', 'ℂ', '复数集', r'\mathbb{C}', usage: '包含实部和虚部的数的全体'),
  _mathSymbol('forall', '∀', '任意', r'\forall', usage: '对所有满足条件的对象都成立'),
  _mathSymbol('exists', '∃', '存在', r'\exists', usage: '至少存在一个满足条件的对象'),
  _mathSymbol('not', '¬', '逻辑非', r'\neg', usage: '对命题取反，¬P 表示"非 P"'),
  _mathSymbol('logical-and', '∧', '逻辑与', r'\land', usage: 'P ∧ Q 表示 P 且 Q 同时成立'),
  _mathSymbol('logical-or', '∨', '逻辑或', r'\lor', usage: 'P ∨ Q 表示 P 或 Q 至少一个成立'),
  _mathSymbol('implies', '⇒', '推出', r'\Rightarrow', usage: 'P ⇒ Q 表示由 P 可以推出 Q'),
  _mathSymbol('iff', '⇔', '等价', r'\Leftrightarrow', usage: 'P ⇔ Q 表示 P 与 Q 互相推出（充要条件）'),
  _mathSymbol('angle', '∠', '角', r'\angle', usage: '表示几何中的角，如 ∠ABC'),
  _mathSymbol('triangle', '△', '三角形', r'\triangle', usage: '表示三角形，如 △ABC'),
  _mathSymbol('perpendicular', '⊥', '垂直', r'\perp', usage: '两直线或向量垂直，如 AB ⊥ CD'),
  _mathSymbol('parallel', '∥', '平行', r'\parallel', usage: '两直线平行，如 AB ∥ CD'),
  _mathSymbol('congruent', '≅', '全等', r'\cong', usage: '两个几何图形完全相同（形状与大小）'),
  _mathSymbol('similar', '∼', '相似', r'\sim', usage: '两个几何图形形状相同但大小可不同'),
  _mathSymbol('sigma', 'σ', '标准差 σ', r'\sigma', usage: '统计中表示标准差，衡量数据分散程度'),
];

final PracticeFormulaKeySpec practiceFormulaConditionalProbabilityKey =
    _mathTemplate(
      'conditional-prob',
      r'P\left(\Box\mid\Box\right)',
      '条件概率',
      r'P\left({}\mid{}\right)',
      '依次填写事件和条件事件',
      const CompositeFormulaInsertion(<String>[
        r'P\left(',
        r'\mid ',
        r'\right)',
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
  String latex, {
  String? usage,
}) => PracticeFormulaKeySpec.catalog(
  id: id,
  label: label,
  name: name,
  semanticLabel: name,
  expectedLatex: latex,
  kind: PracticeFormulaKeyKind.symbol,
  section: PracticeFormulaSection.mathSymbols,
  placement: PracticeFormulaKeyPlacement.sectionGrid,
  usage: usage ?? name,
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

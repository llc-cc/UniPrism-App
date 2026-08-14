import 'package:math_keyboard/math_keyboard.dart';
// math_keyboard 的公开 controller 方法暴露了 TeXArg，但主入口没有转出该类型。
// ignore: implementation_imports
import 'package:math_keyboard/src/foundation/node.dart';

import 'practice_formula_common_catalog.dart';
import 'practice_formula_insertions.dart';
import 'practice_formula_key_models.dart';
import 'practice_formula_math_catalog.dart';

export 'practice_formula_common_catalog.dart';
export 'practice_formula_insertions.dart';
export 'practice_formula_key_models.dart';
export 'practice_formula_math_catalog.dart';

/// 公式键盘的一级分类；顺序同时决定桌面左栏和窄屏分类栏顺序。
enum PracticeFormulaKeyboardCategory {
  common,
  structures,
  symbols,
  functions,
  greek,
  physics,
  units,
  letters,
  more,
}

const Map<PracticeFormulaKeyboardCategory, String>
practiceFormulaCategoryLabels = <PracticeFormulaKeyboardCategory, String>{
  PracticeFormulaKeyboardCategory.common: '常用',
  PracticeFormulaKeyboardCategory.structures: '结构',
  PracticeFormulaKeyboardCategory.symbols: '符号',
  PracticeFormulaKeyboardCategory.functions: '函数',
  PracticeFormulaKeyboardCategory.greek: '希腊',
  PracticeFormulaKeyboardCategory.physics: '物理',
  PracticeFormulaKeyboardCategory.units: '单位',
  PracticeFormulaKeyboardCategory.letters: '字母',
  PracticeFormulaKeyboardCategory.more: '更多',
};

PracticeFormulaKeyAction _leaf(String value) =>
    (controller) => controller.addLeaf(value);

PracticeFormulaKeyAction _function(String command) =>
    (controller) => controller.addFunction(command, const [TeXArg.parentheses]);

PracticeFormulaKeyAction _paired(String left, String right) => (controller) {
  controller.addLeaf(left);
  controller.addLeaf(right);
  controller.goBack();
};

void _insertAbsoluteValue(MathFieldEditingController controller) {
  controller.addLeaf(r'\left|');
  controller.addLeaf(r'\right|');
  controller.goBack();
}

void _insertNorm(MathFieldEditingController controller) {
  controller.addLeaf(r'\left\lVert ');
  controller.addLeaf(r'\right\rVert ');
  controller.goBack();
}

void _insertExponential(MathFieldEditingController controller) {
  controller.addLeaf('e');
  controller.addFunction('^', const [TeXArg.braces]);
}

void _insertBoundedOperator(
  MathFieldEditingController controller,
  String command,
) {
  controller.addFunction('${command}_', const [TeXArg.braces]);
  controller.goNext();
  controller.addFunction('^', const [TeXArg.braces]);
  // 上下限是两个相邻节点，默认回到下限以匹配学生从下到上的填写顺序。
  controller.goBack();
  controller.goBack();
}

PracticeFormulaKeyAction _fixedFunction(String command, String value) =>
    (controller) {
      controller.addFunction(command, const [TeXArg.braces]);
      controller.addLeaf(value);
    };

PracticeFormulaKeyAction _delta(String variable) => (controller) {
  controller.addLeaf(r'\Delta ');
  controller.addLeaf(variable);
};

void _insertInitialVelocity(MathFieldEditingController controller) {
  controller.addLeaf('v');
  controller.addFunction('_', const [TeXArg.braces]);
  controller.addLeaf('0');
}

PracticeFormulaKeyAction _unit(String latex) => (controller) {
  final current = controller
      .currentEditingValue(placeholderWhenEmpty: false)
      .replaceAll(' ', '');
  // 单位跟在数值或结构右括号后才补薄空格，空输入时不制造前导间距。
  if (RegExp(r'(?:\d|\})$').hasMatch(current)) controller.addLeaf(r'\,');
  controller.addLeaf(latex);
};

/// 按当前大小写状态生成完整的 26 个受控字母键。
List<PracticeFormulaKeySpec> practiceFormulaAlphabetKeys({
  required bool uppercase,
}) => practiceFormulaLetterAndNumberKeys(
  uppercase: uppercase,
).take(26).toList(growable: false);

final PracticeFormulaKeySpec _fraction = PracticeFormulaKeySpec(
  'fraction',
  r'\frac{\Box}{\Box}',
  '插入分式',
  (controller) =>
      controller.addFunction(r'\frac', const [TeXArg.braces, TeXArg.braces]),
  isTexLabel: true,
);

final PracticeFormulaKeySpec _square = PracticeFormulaKeySpec(
  'square',
  r'\Box^2',
  '插入平方',
  (controller) => controller.addFunction('^2', const [TeXArg.braces]),
  isTexLabel: true,
);

final PracticeFormulaKeySpec _power = PracticeFormulaKeySpec(
  'power',
  r'\Box^{\Box}',
  '插入任意次幂',
  (controller) => controller.addFunction('^', const [TeXArg.braces]),
  isTexLabel: true,
);

final PracticeFormulaKeySpec _subscript = PracticeFormulaKeySpec(
  'subscript',
  r'\Box_{\Box}',
  '插入下标',
  (controller) => controller.addFunction('_', const [TeXArg.braces]),
  isTexLabel: true,
);

final PracticeFormulaKeySpec _sqrt = PracticeFormulaKeySpec(
  'sqrt',
  r'\sqrt{\Box}',
  '插入平方根',
  (controller) => controller.addFunction(r'\sqrt', const [TeXArg.braces]),
  isTexLabel: true,
);

final PracticeFormulaKeySpec _nthRoot = PracticeFormulaKeySpec(
  'nth-root',
  r'\sqrt[\Box]{\Box}',
  '插入 n 次根',
  (controller) =>
      controller.addFunction(r'\sqrt', const [TeXArg.brackets, TeXArg.braces]),
  isTexLabel: true,
);

final PracticeFormulaKeySpec _absolute = PracticeFormulaKeySpec(
  'absolute',
  r'\left|x\right|',
  '插入绝对值',
  _insertAbsoluteValue,
  isTexLabel: true,
);

final PracticeFormulaKeySpec _infinity = PracticeFormulaKeySpec(
  'infinity',
  '∞',
  '无穷',
  _leaf(r'\infty '),
);

final PracticeFormulaKeySpec _limit = PracticeFormulaKeySpec(
  'limit',
  r'\lim_{\Box}',
  '插入极限下标',
  (controller) => controller.addFunction(r'\lim_', const [TeXArg.braces]),
  isTexLabel: true,
);

final PracticeFormulaKeySpec _sum = PracticeFormulaKeySpec(
  'sum',
  r'\sum_{\Box}^{\Box}',
  '插入求和上下限',
  (controller) => _insertBoundedOperator(controller, r'\sum'),
  isTexLabel: true,
);

final PracticeFormulaKeySpec _integral = PracticeFormulaKeySpec(
  'integral',
  r'\int_{\Box}^{\Box}',
  '插入积分上下限',
  (controller) => _insertBoundedOperator(controller, r'\int'),
  isTexLabel: true,
);

/// 八类公式键目录；列表顺序就是面板中的阅读与键位优先级。
final Map<PracticeFormulaKeyboardCategory, List<PracticeFormulaKeySpec>>
practiceFormulaCategoryKeys =
    <PracticeFormulaKeyboardCategory, List<PracticeFormulaKeySpec>>{
      PracticeFormulaKeyboardCategory.common: <PracticeFormulaKeySpec>[
        PracticeFormulaKeySpec('left-paren', '(', '左括号', _paired('(', ')')),
        PracticeFormulaKeySpec('right-paren', ')', '右括号', _leaf(')')),
        PracticeFormulaKeySpec('left-bracket', '[', '左方括号', _paired('[', ']')),
        PracticeFormulaKeySpec('right-bracket', ']', '右方括号', _leaf(']')),
        PracticeFormulaKeySpec('equals', '=', '等号', _leaf('=')),
        _fraction,
        _square,
        _power,
        _subscript,
        _sqrt,
        _nthRoot,
        _absolute,
        PracticeFormulaKeySpec('pi', 'π', '圆周率', _leaf(r'\pi ')),
        PracticeFormulaKeySpec('e', 'e', '自然常数 e', _leaf('e')),
        _infinity,
        PracticeFormulaKeySpec('plus-minus', '±', '正负号', _leaf(r'\pm ')),
        practiceFormulaScientificNotationKey,
      ],
      PracticeFormulaKeyboardCategory.structures: <PracticeFormulaKeySpec>[
        _fraction,
        _square,
        _power,
        _subscript,
        _sqrt,
        _nthRoot,
        _absolute,
        PracticeFormulaKeySpec(
          'norm',
          r'\left\lVert x\right\rVert',
          '插入范数',
          _insertNorm,
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'vector',
          r'\vec{\Box}',
          '插入向量',
          (controller) =>
              controller.addFunction(r'\vec', const [TeXArg.braces]),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'overline',
          r'\overline{\Box}',
          '插入上划线',
          (controller) =>
              controller.addFunction(r'\overline', const [TeXArg.braces]),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'overrightarrow',
          r'\overrightarrow{\Box}',
          '插入有向线段',
          (controller) =>
              controller.addFunction(r'\overrightarrow', const [TeXArg.braces]),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'binomial',
          r'\binom{\Box}{\Box}',
          '插入组合数',
          (controller) => controller.addFunction(r'\binom', const [
            TeXArg.braces,
            TeXArg.braces,
          ]),
          isTexLabel: true,
        ),
        _sum,
        _integral,
        _limit,
      ],
      PracticeFormulaKeyboardCategory.symbols: <PracticeFormulaKeySpec>[
        PracticeFormulaKeySpec('less-equal', '≤', '小于等于', _leaf(r'\le ')),
        PracticeFormulaKeySpec('greater-equal', '≥', '大于等于', _leaf(r'\ge ')),
        PracticeFormulaKeySpec('not-equal', '≠', '不等于', _leaf(r'\ne ')),
        PracticeFormulaKeySpec('in', '∈', '属于', _leaf(r'\in ')),
        PracticeFormulaKeySpec('union', '∪', '并集', _leaf(r'\cup ')),
        PracticeFormulaKeySpec('intersection', '∩', '交集', _leaf(r'\cap ')),
        _infinity,
        PracticeFormulaKeySpec('less', '<', '小于', _leaf('<')),
        PracticeFormulaKeySpec('greater', '>', '大于', _leaf('>')),
        PracticeFormulaKeySpec('approx', '≈', '约等于', _leaf(r'\approx ')),
        PracticeFormulaKeySpec('not-in', '∉', '不属于', _leaf(r'\notin ')),
        PracticeFormulaKeySpec('subset', '⊂', '真子集', _leaf(r'\subset ')),
        PracticeFormulaKeySpec(
          'subset-equal',
          '⊆',
          '子集或相等',
          _leaf(r'\subseteq '),
        ),
        PracticeFormulaKeySpec('empty-set', '∅', '空集', _leaf(r'\emptyset ')),
        PracticeFormulaKeySpec('arrow', '→', '趋向', _leaf(r'\to ')),
        PracticeFormulaKeySpec('parallel', '∥', '平行', _leaf(r'\parallel ')),
        PracticeFormulaKeySpec('perpendicular', '⊥', '垂直', _leaf(r'\perp ')),
        PracticeFormulaKeySpec('degree', '°', '角度', _leaf(r'^{\circ}')),
      ],
      PracticeFormulaKeyboardCategory.functions: <PracticeFormulaKeySpec>[
        practiceFormulaConditionalProbabilityKey,
        PracticeFormulaKeySpec('sin', 'sin', '正弦函数', _function(r'\sin')),
        PracticeFormulaKeySpec('cos', 'cos', '余弦函数', _function(r'\cos')),
        PracticeFormulaKeySpec('tan', 'tan', '正切函数', _function(r'\tan')),
        PracticeFormulaKeySpec('cot', 'cot', '余切函数', _function(r'\cot')),
        PracticeFormulaKeySpec('log', 'log', '对数函数', _function(r'\log')),
        PracticeFormulaKeySpec('ln', 'ln', '自然对数函数', _function(r'\ln')),
        PracticeFormulaKeySpec(
          'exp',
          r'e^{\Box}',
          '指数函数',
          _insertExponential,
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec('max', 'max', '最大值', _function(r'\max')),
        PracticeFormulaKeySpec('min', 'min', '最小值', _function(r'\min')),
        _limit,
        _sum,
        PracticeFormulaKeySpec(
          'product',
          r'\prod_{\Box}^{\Box}',
          '插入连乘上下限',
          (controller) => _insertBoundedOperator(controller, r'\prod'),
          isTexLabel: true,
        ),
        _integral,
      ],
      PracticeFormulaKeyboardCategory.greek: <PracticeFormulaKeySpec>[
        PracticeFormulaKeySpec('alpha', 'α', '希腊字母 alpha', _leaf(r'\alpha ')),
        PracticeFormulaKeySpec('beta', 'β', '希腊字母 beta', _leaf(r'\beta ')),
        PracticeFormulaKeySpec('gamma', 'γ', '希腊字母 gamma', _leaf(r'\gamma ')),
        PracticeFormulaKeySpec('delta', 'δ', '希腊字母 delta', _leaf(r'\delta ')),
        PracticeFormulaKeySpec(
          'epsilon',
          'ε',
          '希腊字母 epsilon',
          _leaf(r'\epsilon '),
        ),
        PracticeFormulaKeySpec('eta', 'η', '希腊字母 eta', _leaf(r'\eta ')),
        PracticeFormulaKeySpec('theta', 'θ', '希腊字母 theta', _leaf(r'\theta ')),
        PracticeFormulaKeySpec(
          'lambda',
          'λ',
          '希腊字母 lambda',
          _leaf(r'\lambda '),
        ),
        PracticeFormulaKeySpec('mu', 'μ', '希腊字母 mu', _leaf(r'\mu ')),
        PracticeFormulaKeySpec('rho', 'ρ', '希腊字母 rho', _leaf(r'\rho ')),
        PracticeFormulaKeySpec('sigma', 'σ', '希腊字母 sigma', _leaf(r'\sigma ')),
        PracticeFormulaKeySpec('phi', 'φ', '希腊字母 phi', _leaf(r'\phi ')),
        PracticeFormulaKeySpec('omega', 'ω', '希腊字母 omega', _leaf(r'\omega ')),
        PracticeFormulaKeySpec('pi', 'π', '圆周率 pi', _leaf(r'\pi ')),
        PracticeFormulaKeySpec('Delta', 'Δ', '大写 Delta', _leaf(r'\Delta ')),
        PracticeFormulaKeySpec('Omega', 'Ω', '大写 Omega', _leaf(r'\Omega ')),
      ],
      PracticeFormulaKeyboardCategory.physics: <PracticeFormulaKeySpec>[
        PracticeFormulaKeySpec(
          'vector-force',
          r'\vec{F}',
          '力矢量',
          _fixedFunction(r'\vec', 'F'),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'vector-velocity',
          r'\vec{v}',
          '速度矢量',
          _fixedFunction(r'\vec', 'v'),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'vector-acceleration',
          r'\vec{a}',
          '加速度矢量',
          _fixedFunction(r'\vec', 'a'),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'vector-magnetic',
          r'\vec{B}',
          '磁感应强度矢量',
          _fixedFunction(r'\vec', 'B'),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'vector-electric',
          r'\vec{E}',
          '电场强度矢量',
          _fixedFunction(r'\vec', 'E'),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'delta-time',
          r'\Delta t',
          '时间变化量',
          _delta('t'),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'delta-position',
          r'\Delta x',
          '位置变化量',
          _delta('x'),
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec(
          'initial-velocity',
          r'v_0',
          '初速度',
          _insertInitialVelocity,
          isTexLabel: true,
        ),
        PracticeFormulaKeySpec('gravity', 'g', '重力加速度', _leaf('g')),
        PracticeFormulaKeySpec('force', 'F', '力', _leaf('F')),
        PracticeFormulaKeySpec('work', 'W', '功', _leaf('W')),
        PracticeFormulaKeySpec('power-physics', 'P', '功率', _leaf('P')),
        PracticeFormulaKeySpec('voltage', 'U', '电压', _leaf('U')),
        PracticeFormulaKeySpec('current', 'I', '电流', _leaf('I')),
        PracticeFormulaKeySpec('resistance', 'R', '电阻', _leaf('R')),
        PracticeFormulaKeySpec('charge', 'Q', '电荷量', _leaf('Q')),
      ],
      PracticeFormulaKeyboardCategory.units: <PracticeFormulaKeySpec>[
        PracticeFormulaKeySpec('unit-metre', 'm', '米', _unit(r'\mathrm{m}')),
        PracticeFormulaKeySpec('unit-second', 's', '秒', _unit(r'\mathrm{s}')),
        PracticeFormulaKeySpec(
          'unit-kilogram',
          'kg',
          '千克',
          _unit(r'\mathrm{kg}'),
        ),
        PracticeFormulaKeySpec('unit-newton', 'N', '牛顿', _unit(r'\mathrm{N}')),
        PracticeFormulaKeySpec('unit-joule', 'J', '焦耳', _unit(r'\mathrm{J}')),
        PracticeFormulaKeySpec('unit-watt', 'W', '瓦特', _unit(r'\mathrm{W}')),
        PracticeFormulaKeySpec(
          'unit-pascal',
          'Pa',
          '帕斯卡',
          _unit(r'\mathrm{Pa}'),
        ),
        PracticeFormulaKeySpec('unit-hertz', 'Hz', '赫兹', _unit(r'\mathrm{Hz}')),
        PracticeFormulaKeySpec('unit-coulomb', 'C', '库仑', _unit(r'\mathrm{C}')),
        PracticeFormulaKeySpec('unit-volt', 'V', '伏特', _unit(r'\mathrm{V}')),
        PracticeFormulaKeySpec('unit-ampere', 'A', '安培', _unit(r'\mathrm{A}')),
        PracticeFormulaKeySpec('unit-ohm', 'Ω', '欧姆', _unit(r'\Omega')),
        PracticeFormulaKeySpec('unit-tesla', 'T', '特斯拉', _unit(r'\mathrm{T}')),
        PracticeFormulaKeySpec('unit-kelvin', 'K', '开尔文', _unit(r'\mathrm{K}')),
        PracticeFormulaKeySpec(
          'unit-mole',
          'mol',
          '摩尔',
          _unit(r'\mathrm{mol}'),
        ),
        PracticeFormulaKeySpec(
          'unit-celsius',
          '℃',
          '摄氏度',
          _unit(r'^{\circ}\mathrm{C}'),
        ),
      ],
      PracticeFormulaKeyboardCategory.letters: <PracticeFormulaKeySpec>[],
      PracticeFormulaKeyboardCategory.more: <PracticeFormulaKeySpec>[
        PracticeFormulaKeySpec('z', 'z', '变量 z', _leaf('z')),
        PracticeFormulaKeySpec('a', 'a', '变量 a', _leaf('a')),
        PracticeFormulaKeySpec('b', 'b', '变量 b', _leaf('b')),
        PracticeFormulaKeySpec('c', 'c', '变量 c', _leaf('c')),
        PracticeFormulaKeySpec('k', 'k', '变量 k', _leaf('k')),
        PracticeFormulaKeySpec('t', 't', '变量 t', _leaf('t')),
        PracticeFormulaKeySpec('m', 'm', '变量 m', _leaf('m')),
        PracticeFormulaKeySpec('p', 'p', '变量 p', _leaf('p')),
        PracticeFormulaKeySpec('forall', '∀', '任意', _leaf(r'\forall ')),
        PracticeFormulaKeySpec('exists', '∃', '存在', _leaf(r'\exists ')),
        PracticeFormulaKeySpec('implies', '⇒', '推出', _leaf(r'\Rightarrow ')),
        PracticeFormulaKeySpec('iff', '⇔', '等价', _leaf(r'\Leftrightarrow ')),
        PracticeFormulaKeySpec(
          'natural-set',
          'ℕ',
          '自然数集',
          _leaf(r'\mathbb{N}'),
        ),
        PracticeFormulaKeySpec('integer-set', 'ℤ', '整数集', _leaf(r'\mathbb{Z}')),
        PracticeFormulaKeySpec(
          'rational-set',
          'ℚ',
          '有理数集',
          _leaf(r'\mathbb{Q}'),
        ),
        PracticeFormulaKeySpec('real-set', 'ℝ', '实数集', _leaf(r'\mathbb{R}')),
      ],
    };

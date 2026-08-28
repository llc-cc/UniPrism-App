import 'practice_formula_insertions.dart';
import 'practice_formula_key_models.dart';

final PracticeFormulaKeySpec practiceFormulaNucleusKey =
    PracticeFormulaKeySpec.catalog(
      id: 'nucleus',
      label: r'{}_{Z}^{A}X',
      name: '核素',
      semanticLabel: '插入核素模板，依次填写质量数、原子序数和元素符号',
      expectedLatex: r'{}_{Z}^{A}X',
      kind: PracticeFormulaKeyKind.template,
      section: PracticeFormulaSection.physicsSymbols,
      placement: PracticeFormulaKeyPlacement.sectionGrid,
      usage: '依次填写质量数 A、原子序数 Z 和元素符号 X',
      insertion: const NucleusFormulaInsertion(),
      isTexLabel: true,
    );

final List<PracticeFormulaKeySpec> _physicsSymbolKeys =
    <PracticeFormulaKeySpec>[
      _physicsSymbol('physics-delta', 'Δ', '变化量 Delta', r'\Delta'),
      _physicsSymbol('physics-rho', 'ρ', '密度 rho', r'\rho'),
      _physicsSymbol('physics-eta', 'η', '效率 eta', r'\eta'),
      _physicsSymbol('physics-mu', 'μ', '摩擦因数 mu', r'\mu'),
      _physicsSymbol('physics-lambda', 'λ', '波长 lambda', r'\lambda'),
      _physicsSymbol('physics-nu', 'ν', '频率 nu', r'\nu'),
      _physicsSymbol('physics-omega', 'ω', '角速度 omega', r'\omega'),
      _physicsSymbol('physics-varphi', 'φ', '相位角 varphi', r'\varphi'),
      _physicsSymbol('physics-capital-phi', 'Φ', '通量 Phi', r'\Phi'),
      _physicsSymbol('physics-gamma', 'γ', '伽马 gamma', r'\gamma'),
      practiceFormulaNucleusKey,
    ];

final PracticeFormulaKeySpec practiceFormulaMetrePerSecondSquaredKey = _unit(
  'unit-m-per-s2',
  'm/s²',
  '米每二次方秒',
  r'\mathrm{m}/\mathrm{s}^{2}',
);

/// 物理单位逐项声明，避免动态前缀组合产生教材目录之外的单位。
final List<PracticeFormulaKeySpec> _physicsUnitKeys = <PracticeFormulaKeySpec>[
  _unit('unit-mm', 'mm', '毫米', r'\mathrm{mm}'),
  _unit('unit-nm', 'nm', '纳米', r'\mathrm{nm}'),
  _unit('unit-cm', 'cm', '厘米', r'\mathrm{cm}'),
  _unit('unit-m', 'm', '米', r'\mathrm{m}'),
  _unit('unit-km', 'km', '千米', r'\mathrm{km}'),
  _unit('unit-mL', 'mL', '毫升', r'\mathrm{mL}'),
  _unit('unit-L', 'L', '升', r'\mathrm{L}'),
  _unit('unit-mg', 'mg', '毫克', r'\mathrm{mg}'),
  _unit('unit-g', 'g', '克', r'\mathrm{g}'),
  _unit('unit-kg', 'kg', '千克', r'\mathrm{kg}'),
  _unit('unit-t', 't', '吨', r'\mathrm{t}'),
  _unit('unit-s', 's', '秒', r'\mathrm{s}'),
  _unit('unit-ms', 'ms', '毫秒', r'\mathrm{ms}'),
  _unit('unit-min', 'min', '分钟', r'\mathrm{min}'),
  _unit('unit-h', 'h', '小时', r'\mathrm{h}'),
  _unit('unit-celsius', '℃', '摄氏度', r'^{\circ}\mathrm{C}'),
  _unit('unit-K', 'K', '开尔文', r'\mathrm{K}'),
  _unit('unit-rad', 'rad', '弧度', r'\mathrm{rad}'),
  _unit('unit-Hz', 'Hz', '赫兹', r'\mathrm{Hz}'),
  _unit('unit-kHz', 'kHz', '千赫兹', r'\mathrm{kHz}'),
  _unit('unit-MHz', 'MHz', '兆赫兹', r'\mathrm{MHz}'),
  _unit('unit-dB', 'dB', '分贝', r'\mathrm{dB}'),
  _unit('unit-N', 'N', '牛顿', r'\mathrm{N}'),
  _unit('unit-Pa', 'Pa', '帕斯卡', r'\mathrm{Pa}'),
  _unit('unit-kPa', 'kPa', '千帕', r'\mathrm{kPa}'),
  _unit('unit-J', 'J', '焦耳', r'\mathrm{J}'),
  _unit('unit-W', 'W', '瓦特', r'\mathrm{W}'),
  _unit('unit-kW', 'kW', '千瓦', r'\mathrm{kW}'),
  _unit('unit-C', 'C', '库仑', r'\mathrm{C}'),
  _unit('unit-A', 'A', '安培', r'\mathrm{A}'),
  _unit('unit-mA', 'mA', '毫安', r'\mathrm{mA}'),
  _unit('unit-microA', 'μA', '微安', r'\mu\mathrm{A}'),
  _unit('unit-V', 'V', '伏特', r'\mathrm{V}'),
  _unit('unit-ohm', 'Ω', '欧姆', r'\Omega'),
  _unit('unit-kilohm', 'kΩ', '千欧', r'\mathrm{k}\Omega'),
  _unit('unit-megaohm', 'MΩ', '兆欧', r'\mathrm{M}\Omega'),
  _unit('unit-F', 'F', '法拉', r'\mathrm{F}'),
  _unit('unit-microF', 'μF', '微法', r'\mu\mathrm{F}'),
  _unit('unit-Wb', 'Wb', '韦伯', r'\mathrm{Wb}'),
  _unit('unit-T', 'T', '特斯拉', r'\mathrm{T}'),
  _unit('unit-mol', 'mol', '摩尔', r'\mathrm{mol}'),
  _unit('unit-eV', 'eV', '电子伏特', r'\mathrm{eV}'),
  _unit('unit-u', 'u', '原子质量单位', r'\mathrm{u}'),
  _unit('unit-m-per-s', 'm/s', '米每秒', r'\mathrm{m}/\mathrm{s}'),
  _unit('unit-km-per-h', 'km/h', '千米每小时', r'\mathrm{km}/\mathrm{h}'),
  practiceFormulaMetrePerSecondSquaredKey,
  _unit('unit-kg-per-m3', 'kg/m³', '千克每立方米', r'\mathrm{kg}/\mathrm{m}^{3}'),
  _unit('unit-g-per-cm3', 'g/cm³', '克每立方厘米', r'\mathrm{g}/\mathrm{cm}^{3}'),
  _unit('unit-N-per-C', 'N/C', '牛顿每库仑', r'\mathrm{N}/\mathrm{C}'),
  _unit('unit-rad-per-s', 'rad/s', '弧度每秒', r'\mathrm{rad}/\mathrm{s}'),
  _unit('unit-kW-hour', 'kW·h', '千瓦时', r'\mathrm{kW}\cdot\mathrm{h}'),
];

final List<PracticeFormulaKeySpec>
_physicsConstantKeys = <PracticeFormulaKeySpec>[
  _constant(
    'constant-g',
    'g',
    '重力加速度',
    'g',
    r'常取 9.8\,\mathrm{m}/\mathrm{s}^{2}，题目有时取 10\,\mathrm{m}/\mathrm{s}^{2}',
    const LeafFormulaInsertion('g'),
  ),
  _constant(
    'constant-G',
    'G',
    '万有引力常量',
    'G',
    r'6.67\times10^{-11}\,\mathrm{N}\cdot\mathrm{m}^{2}/\mathrm{kg}^{2}',
    const LeafFormulaInsertion('G'),
  ),
  _constant(
    'constant-c',
    'c',
    '真空光速',
    'c',
    r'3.0\times10^{8}\,\mathrm{m}/\mathrm{s}',
    const LeafFormulaInsertion('c'),
  ),
  _constant(
    'constant-k',
    'k',
    '静电力常量',
    'k',
    r'9.0\times10^{9}\,\mathrm{N}\cdot\mathrm{m}^{2}/\mathrm{C}^{2}',
    const LeafFormulaInsertion('k'),
  ),
  _constant(
    'constant-e',
    'e',
    '元电荷',
    'e',
    r'1.60\times10^{-19}\,\mathrm{C}',
    const LeafFormulaInsertion('e'),
  ),
  _constant(
    'constant-h',
    'h',
    '普朗克常量',
    'h',
    r'6.63\times10^{-34}\,\mathrm{J}\cdot\mathrm{s}',
    const LeafFormulaInsertion('h'),
  ),
  _constant(
    'constant-NA',
    r'N_A',
    '阿伏伽德罗常数',
    r'N_{A}',
    r'6.02\times10^{23}\,\mathrm{mol}^{-1}',
    const SubscriptedSymbolFormulaInsertion('N', 'A'),
    isTexLabel: true,
  ),
  _constant(
    'constant-kB',
    r'k_B',
    '玻尔兹曼常数',
    r'k_{B}',
    r'1.38\times10^{-23}\,\mathrm{J}/\mathrm{K}',
    const SubscriptedSymbolFormulaInsertion('k', 'B'),
    isTexLabel: true,
  ),
  _constant(
    'constant-R',
    'R',
    '理想气体常数',
    'R',
    r'8.31\,\mathrm{J}/(\mathrm{mol}\cdot\mathrm{K})',
    const LeafFormulaInsertion('R'),
  ),
  _constant(
    'constant-p0',
    r'p_0',
    '标准大气压',
    r'p_{0}',
    r'常取 1.01\times10^{5}\,\mathrm{Pa}',
    const SubscriptedSymbolFormulaInsertion('p', '0'),
    isTexLabel: true,
  ),
];

final Map<PracticeFormulaSection, List<PracticeFormulaKeySpec>>
practiceFormulaPhysicsSectionKeys =
    <PracticeFormulaSection, List<PracticeFormulaKeySpec>>{
      PracticeFormulaSection.physicsSymbols: _physicsSymbolKeys,
      PracticeFormulaSection.physicsUnits: _physicsUnitKeys,
      PracticeFormulaSection.physicsConstants: _physicsConstantKeys,
    };

PracticeFormulaKeySpec _physicsSymbol(
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
  section: PracticeFormulaSection.physicsSymbols,
  placement: PracticeFormulaKeyPlacement.sectionGrid,
  usage: '输入物理量符号 $label',
  insertion: LeafFormulaInsertion('$latex '),
);

PracticeFormulaKeySpec _unit(
  String id,
  String label,
  String name,
  String latex,
) => PracticeFormulaKeySpec.catalog(
  id: id,
  label: label,
  name: name,
  semanticLabel: '物理单位$name',
  expectedLatex: latex,
  kind: PracticeFormulaKeyKind.unit,
  section: PracticeFormulaSection.physicsUnits,
  placement: PracticeFormulaKeyPlacement.sectionGrid,
  usage: '输入物理单位 $label',
  insertion: UnitFormulaInsertion(latex),
);

PracticeFormulaKeySpec _constant(
  String id,
  String label,
  String name,
  String expectedLatex,
  String usage,
  PracticeFormulaInsertion insertion, {
  bool isTexLabel = false,
}) => PracticeFormulaKeySpec.catalog(
  id: id,
  label: label,
  name: name,
  semanticLabel: '$name，$usage',
  expectedLatex: expectedLatex,
  kind: PracticeFormulaKeyKind.constant,
  section: PracticeFormulaSection.physicsConstants,
  placement: PracticeFormulaKeyPlacement.semanticShortcut,
  usage: usage,
  insertion: insertion,
  isTexLabel: isTexLabel,
);

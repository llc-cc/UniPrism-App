import 'package:math_keyboard/math_keyboard.dart';

/// 公式键盘的一级学科分类。
enum PracticeFormulaPrimaryCategory { common, mathematics, physics }

/// 一级分类下的正式二级标签；顺序同时决定键盘中的阅读顺序。
enum PracticeFormulaSection {
  lettersAndNumbers,
  commonSymbols,
  commonTemplates,
  mathSymbols,
  mathTemplates,
  mathUniversity,
  physicsSymbols,
  physicsUnits,
  physicsConstants,
}

/// 键位内容类型，用于区分字符、结构模板和物理语义内容。
enum PracticeFormulaKeyKind { character, symbol, template, unit, constant }

/// 键位主展示位置；固定区与正式目录不能重复渲染同一个基础键。
enum PracticeFormulaKeyPlacement { fixedPad, sectionGrid, semanticShortcut }

/// 一级分类的用户可见名称。
const Map<PracticeFormulaPrimaryCategory, String> practiceFormulaPrimaryLabels =
    <PracticeFormulaPrimaryCategory, String>{
      PracticeFormulaPrimaryCategory.common: '常用类',
      PracticeFormulaPrimaryCategory.mathematics: '数学类',
      PracticeFormulaPrimaryCategory.physics: '物理类',
    };

/// 二级标签的用户可见名称。
const Map<PracticeFormulaSection, String> practiceFormulaSectionLabels =
    <PracticeFormulaSection, String>{
      PracticeFormulaSection.lettersAndNumbers: '字母与数字',
      PracticeFormulaSection.commonSymbols: '常用符号',
      PracticeFormulaSection.commonTemplates: '常用公式模板',
      PracticeFormulaSection.mathSymbols: '数学符号',
      PracticeFormulaSection.mathTemplates: '数学公式模板',
      PracticeFormulaSection.mathUniversity: '大学数学',
      PracticeFormulaSection.physicsSymbols: '物理符号',
      PracticeFormulaSection.physicsUnits: '物理单位',
      PracticeFormulaSection.physicsConstants: '物理常数',
    };

/// 一级分类与二级标签的固定映射，避免 UI 自行判断学科归属。
const Map<PracticeFormulaPrimaryCategory, List<PracticeFormulaSection>>
practiceFormulaSectionsByPrimary =
    <PracticeFormulaPrimaryCategory, List<PracticeFormulaSection>>{
      PracticeFormulaPrimaryCategory.common: <PracticeFormulaSection>[
        PracticeFormulaSection.lettersAndNumbers,
        PracticeFormulaSection.commonSymbols,
        PracticeFormulaSection.commonTemplates,
      ],
      PracticeFormulaPrimaryCategory.mathematics: <PracticeFormulaSection>[
        PracticeFormulaSection.mathSymbols,
        PracticeFormulaSection.mathTemplates,
        PracticeFormulaSection.mathUniversity,
      ],
      PracticeFormulaPrimaryCategory.physics: <PracticeFormulaSection>[
        PracticeFormulaSection.physicsSymbols,
        PracticeFormulaSection.physicsUnits,
        PracticeFormulaSection.physicsConstants,
      ],
    };

typedef PracticeFormulaKeyAction =
    void Function(MathFieldEditingController controller);

/// 公式插入策略；目录只声明策略，不接触编辑器内部节点。
abstract interface class PracticeFormulaInsertion {
  void apply(MathFieldEditingController controller);
}

/// 兼容现有闭包动作的插入策略，迁移期间保持旧键位行为不变。
final class CallbackFormulaInsertion implements PracticeFormulaInsertion {
  const CallbackFormulaInsertion(this.callback);

  final PracticeFormulaKeyAction callback;

  @override
  void apply(MathFieldEditingController controller) => callback(controller);
}

/// 单个受控公式键；显示元数据与编辑动作分离。
final class PracticeFormulaKeySpec {
  PracticeFormulaKeySpec(
    this.id,
    this.label,
    this.semanticLabel,
    PracticeFormulaKeyAction action, {
    this.isTexLabel = false,
  }) : name = semanticLabel,
       expectedLatex = '',
       kind = PracticeFormulaKeyKind.symbol,
       section = PracticeFormulaSection.commonSymbols,
       placement = PracticeFormulaKeyPlacement.sectionGrid,
       usage = '',
       insertion = CallbackFormulaInsertion(action);

  const PracticeFormulaKeySpec.catalog({
    required this.id,
    required this.label,
    required this.name,
    required this.semanticLabel,
    required this.expectedLatex,
    required this.kind,
    required this.section,
    required this.placement,
    required this.usage,
    required this.insertion,
    this.isTexLabel = false,
  });

  final String id;
  final String label;
  final String name;
  final String semanticLabel;
  final String expectedLatex;
  final PracticeFormulaKeyKind kind;
  final PracticeFormulaSection section;
  final PracticeFormulaKeyPlacement placement;
  final String usage;
  final PracticeFormulaInsertion insertion;
  final bool isTexLabel;

  /// 旧 Widget 与测试仍通过 action 调用；目录迁移完成后统一改用 insert。
  PracticeFormulaKeyAction get action => insertion.apply;

  void insert(MathFieldEditingController controller) =>
      insertion.apply(controller);
}

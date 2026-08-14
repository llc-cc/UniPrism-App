import 'practice_formula_common_catalog.dart';
import 'practice_formula_key_models.dart';
import 'practice_formula_math_catalog.dart';
import 'practice_formula_physics_catalog.dart';

export 'practice_formula_common_catalog.dart';
export 'practice_formula_insertions.dart';
export 'practice_formula_key_models.dart';
export 'practice_formula_math_catalog.dart';
export 'practice_formula_physics_catalog.dart';

/// 八个正式标签的单一索引；字母默认使用小写，界面可按状态动态生成大写版本。
final Map<PracticeFormulaSection, List<PracticeFormulaKeySpec>>
practiceFormulaSectionKeys =
    <PracticeFormulaSection, List<PracticeFormulaKeySpec>>{
      PracticeFormulaSection.lettersAndNumbers:
          practiceFormulaLetterAndNumberKeys(uppercase: false),
      ...practiceFormulaCommonSectionKeys,
      ...practiceFormulaMathSectionKeys,
      ...practiceFormulaPhysicsSectionKeys,
    };

/// 读取标签内容；只有字母页受大小写状态影响，其他目录始终返回稳定顺序。
List<PracticeFormulaKeySpec> practiceFormulaKeysForSection(
  PracticeFormulaSection section, {
  bool uppercaseLetters = false,
}) {
  if (section == PracticeFormulaSection.lettersAndNumbers) {
    return practiceFormulaLetterAndNumberKeys(uppercase: uppercaseLetters);
  }
  return practiceFormulaSectionKeys[section]!;
}

/// 验证正式目录的唯一 ID、标签归属和展示位置边界。
void validatePracticeFormulaCatalog() {
  final seenOwners = <String, String>{};

  for (final section in PracticeFormulaSection.values) {
    final keys = practiceFormulaSectionKeys[section];
    if (keys == null) {
      throw StateError('公式目录缺少标签 ${section.name}');
    }
    for (final key in keys) {
      if (key.section != section) {
        throw StateError(
          '键位 ${key.id} 声明属于 ${key.section.name}，却出现在 ${section.name}',
        );
      }
      if (key.placement == PracticeFormulaKeyPlacement.fixedPad) {
        throw StateError('正式标签 ${section.name} 不能包含固定区键位 ${key.id}');
      }
      // 语义快捷入口只允许出现在常数页，其他正式内容必须拥有唯一网格位置。
      if (key.placement == PracticeFormulaKeyPlacement.semanticShortcut &&
          section != PracticeFormulaSection.physicsConstants) {
        throw StateError('键位 ${key.id} 在 ${section.name} 使用了非法快捷位置');
      }
      _registerUniqueKey(seenOwners, key, section.name);
    }
  }

  for (final key in practiceFormulaNumericKeys) {
    if (key.placement != PracticeFormulaKeyPlacement.fixedPad) {
      throw StateError('固定数字区键位 ${key.id} 的展示位置不合法');
    }
    _registerUniqueKey(seenOwners, key, 'fixedPad');
  }
}

void _registerUniqueKey(
  Map<String, String> seenOwners,
  PracticeFormulaKeySpec key,
  String owner,
) {
  final previousOwner = seenOwners[key.id];
  if (previousOwner != null) {
    throw StateError('公式键位 ID ${key.id} 同时出现在 $previousOwner 和 $owner');
  }
  seenOwners[key.id] = owner;
}

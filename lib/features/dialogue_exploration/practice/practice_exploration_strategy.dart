import 'practice_diagnosis.dart';

/// 练习端口首版的可替换验证策略；后续可由正式 Skill/解法图实现。
final class PracticeExplorationStrategy {
  const PracticeExplorationStrategy();

  PracticeValidationResult validateHypothesis(String hypothesis) {
    final normalized = hypothesis.trim();
    if (normalized.contains('柯西')) {
      return const PracticeValidationResult.invalid(
        explanation: '当前直接写法没有先建立柯西不等式所需的对应结构，推导在适用条件处中断。',
        diagnosis: PracticeDiagnosisSuggestion(
          suggestedKind: DifficultyDiagnosisKind.conditionGap,
          rationale: '学生提出了工具名称，但没有检查工具的适用条件和变量对应关系。',
        ),
      );
    }
    if (normalized.contains('基本不等式') || normalized.contains('均值')) {
      return const PracticeValidationResult.valid(
        explanation: '因为 x>0，所以 x 与 1/x 都为正，满足基本不等式的非负条件，且乘积为 1。',
      );
    }
    return const PracticeValidationResult.invalid(
      explanation: '当前思路还没有形成可以验证的等价变形或不等式依据。',
      diagnosis: PracticeDiagnosisSuggestion(
        suggestedKind: DifficultyDiagnosisKind.methodSelection,
        rationale: '目前缺少能连接题目条件与目标结论的明确工具。',
      ),
    );
  }
}

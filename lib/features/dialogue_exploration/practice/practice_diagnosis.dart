/// 练习端口首版可确认的卡点类型，避免用一个模糊“不会”覆盖不同补救动作。
enum DifficultyDiagnosisKind {
  conceptGap,
  conditionGap,
  methodSelection,
  reasoningBreak,
  calculationGap,
  promptMisread,
  uncertain,
}

/// 只有学生确认或客观步骤验证的证据可以流入正式掌握记录。
enum MasteryEvidenceSource { confirmedByStudent, verifiedByStep }

/// 系统对卡点的候选判断；此对象本身不是掌握证据。
final class PracticeDiagnosisSuggestion {
  const PracticeDiagnosisSuggestion({
    required this.suggestedKind,
    required this.rationale,
  });

  final DifficultyDiagnosisKind suggestedKind;
  final String rationale;
}

/// 经允许来源确认后的掌握证据，可由 M2/M3 的正式实现继续消费。
final class MasteryEvidence {
  const MasteryEvidence({
    required this.id,
    required this.atomId,
    required this.nodeId,
    required this.diagnosisKind,
    required this.source,
    required this.summary,
    required this.occurredAt,
  });

  final String id;
  final String atomId;
  final String nodeId;
  final DifficultyDiagnosisKind? diagnosisKind;
  final MasteryEvidenceSource source;
  final String summary;
  final DateTime occurredAt;
}

/// 一次解题思路验证的确定性结果。
final class PracticeValidationResult {
  const PracticeValidationResult.valid({required this.explanation})
    : isValid = true,
      diagnosis = null;

  const PracticeValidationResult.invalid({
    required this.explanation,
    required PracticeDiagnosisSuggestion this.diagnosis,
  }) : isValid = false;

  final bool isValid;
  final String explanation;
  final PracticeDiagnosisSuggestion? diagnosis;
}

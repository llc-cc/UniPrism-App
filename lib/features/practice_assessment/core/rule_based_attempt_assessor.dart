import 'practice_models.dart';
import 'practice_ports.dart';

/// V1 保守规则评分器，只依据确定答案、rubric 关键词和交互事实生成证据。
final class RuleBasedAttemptAssessor implements AttemptAssessor {
  const RuleBasedAttemptAssessor();

  @override
  AttemptAssessment assess({
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  }) {
    final normalizedAnswer = _normalizeAnswer(question.type, draft.answer);
    final expectedAnswers = question.rubric.expectedAnswers
        .map((item) => _normalizeAnswer(question.type, item))
        .toSet();
    final isAnswerCorrect = expectedAnswers.contains(normalizedAnswer);
    final matchedSteps = _matchedSteps(question, draft.reasoning);
    final outcome = _outcome(
      question: question,
      normalizedAnswer: normalizedAnswer,
      expectedAnswers: expectedAnswers,
      isAnswerCorrect: isAnswerCorrect,
      matchedSteps: matchedSteps,
    );
    final factCodes = <String>[
      switch (outcome) {
        AttemptOutcome.correct => 'answer-correct',
        AttemptOutcome.partiallyCorrect => 'answer-partial',
        AttemptOutcome.incorrect => 'answer-incorrect',
      },
      if (facts.hintCount > 0) 'assisted',
      if (draft.revisionCount > 0) 'revised',
    ];

    final observations = <AbilityDimension, AbilityObservation>{};
    for (final dimension in AbilityDimension.values) {
      observations[dimension] = _observation(
        question: question,
        draft: draft,
        facts: facts,
        outcome: outcome,
        dimension: dimension,
        matchedSteps: matchedSteps,
        factCodes: factCodes,
      );
    }

    return AttemptAssessment(
      questionId: question.id,
      outcome: outcome,
      feedback: _feedback(outcome, matchedSteps.length),
      matchedStepIds: matchedSteps.map((item) => item.id).toList(),
      observations: observations,
      assessorVersion: 'rule-v1',
      rubricVersion: question.rubric.version,
    );
  }

  /// 把已校验的评分结果投影为去标识化训练样本。
  TrainingExampleV1 projectTrainingExample({
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
    required AttemptAssessment assessment,
  }) {
    return TrainingExampleV1(
      questionId: question.id,
      questionType: question.type,
      answer: draft.answer.trim(),
      reasoning: draft.reasoning.trim(),
      facts: <String, Object?>{
        'hintCount': facts.hintCount,
        'submissionCount': facts.submissionCount,
        'durationSeconds': facts.durationSeconds,
        'revisionCount': draft.revisionCount,
        'outcome': assessment.outcome.name,
      },
      labels: <String, Object?>{
        for (final entry in assessment.observations.entries)
          entry.key.name: <String, Object?>{
            'status': entry.value.status.name,
            'band': entry.value.band,
            'evidenceStepIds': entry.value.evidenceStepIds,
            'factCodes': entry.value.factCodes,
            'errorTags': entry.value.errorTags,
          },
      },
      assessorVersion: assessment.assessorVersion,
      rubricVersion: assessment.rubricVersion,
    );
  }

  AbilityObservation _observation({
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
    required AttemptOutcome outcome,
    required AbilityDimension dimension,
    required List<RubricStep> matchedSteps,
    required List<String> factCodes,
  }) {
    if (dimension == AbilityDimension.selfCorrection) {
      final hasCorrectionEvidence =
          draft.revisionCount > 0 && outcome != AttemptOutcome.incorrect;
      if (!hasCorrectionEvidence) {
        return _missing(dimension, AbilityEvidenceStatus.insufficientEvidence);
      }
      return AbilityObservation(
        dimension: dimension,
        status: AbilityEvidenceStatus.observed,
        band: facts.hintCount > 0 ? 2 : 3,
        confidence: 0.82,
        evidenceStepIds: matchedSteps.map((item) => item.id).toList(),
        factCodes: factCodes,
        errorTags: const [],
      );
    }

    if (!question.rubric.observableDimensions.contains(dimension)) {
      return _missing(dimension, AbilityEvidenceStatus.notApplicable);
    }

    if (dimension == AbilityDimension.calculation) {
      if (draft.answer.trim().isEmpty) {
        return _missing(dimension, AbilityEvidenceStatus.insufficientEvidence);
      }
      return AbilityObservation(
        dimension: dimension,
        status: AbilityEvidenceStatus.observed,
        band: _capAssisted(switch (outcome) {
          AttemptOutcome.correct => 4,
          AttemptOutcome.partiallyCorrect => 2,
          AttemptOutcome.incorrect => 1,
        }, facts),
        confidence: 0.9,
        evidenceStepIds: matchedSteps.map((item) => item.id).toList(),
        factCodes: factCodes,
        errorTags: outcome == AttemptOutcome.incorrect
            ? _firstErrorTag(question)
            : const [],
      );
    }

    if (dimension == AbilityDimension.expression &&
        draft.reasoning.trim().isNotEmpty) {
      final band = draft.reasoning.trim().length >= 24 ? 3 : 2;
      return AbilityObservation(
        dimension: dimension,
        status: AbilityEvidenceStatus.observed,
        band: _capAssisted(band, facts),
        confidence: 0.65,
        evidenceStepIds: matchedSteps.map((item) => item.id).toList(),
        factCodes: factCodes,
        errorTags: const [],
      );
    }

    final dimensionSteps = matchedSteps
        .where((item) => item.dimensions.contains(dimension))
        .toList(growable: false);
    if (dimensionSteps.isEmpty) {
      // 最终答案无法替代过程证据，留空比把“未知”误判成低能力更安全。
      return _missing(dimension, AbilityEvidenceStatus.insufficientEvidence);
    }

    return AbilityObservation(
      dimension: dimension,
      status: AbilityEvidenceStatus.observed,
      band: _capAssisted((dimensionSteps.length + 1).clamp(1, 4), facts),
      confidence: (0.62 + dimensionSteps.length * 0.1).clamp(0, 0.92),
      evidenceStepIds: dimensionSteps.map((item) => item.id).toList(),
      factCodes: factCodes,
      errorTags: outcome == AttemptOutcome.incorrect
          ? _firstErrorTag(question)
          : const [],
    );
  }

  AbilityObservation _missing(
    AbilityDimension dimension,
    AbilityEvidenceStatus status,
  ) {
    return AbilityObservation(
      dimension: dimension,
      status: status,
      confidence: status == AbilityEvidenceStatus.notApplicable ? 1 : 0,
      evidenceStepIds: const [],
      factCodes: const [],
      errorTags: const [],
    );
  }

  int _capAssisted(int band, PracticeAttemptFacts facts) {
    // 提示后完成仍是有效证据，但不能与独立完成获得相同的最高档位。
    return facts.hintCount > 0 ? band.clamp(0, 3) : band;
  }

  List<String> _firstErrorTag(PracticeQuestion question) =>
      question.rubric.errorTags.isEmpty
      ? const []
      : <String>[question.rubric.errorTags.first];

  List<RubricStep> _matchedSteps(PracticeQuestion question, String reasoning) {
    final normalized = _normalizeFreeText(reasoning);
    if (normalized.isEmpty) return const [];
    return question.rubric.steps
        .where((step) {
          return step.keywords.any(
            (keyword) => normalized.contains(_normalizeFreeText(keyword)),
          );
        })
        .toList(growable: false);
  }

  AttemptOutcome _outcome({
    required PracticeQuestion question,
    required String normalizedAnswer,
    required Set<String> expectedAnswers,
    required bool isAnswerCorrect,
    required List<RubricStep> matchedSteps,
  }) {
    if (isAnswerCorrect) return AttemptOutcome.correct;
    if (question.type == PracticeQuestionType.multipleChoice &&
        normalizedAnswer.isNotEmpty) {
      final selected = normalizedAnswer.split('').toSet();
      final expected = expectedAnswers.first.split('').toSet();
      if (selected.isNotEmpty &&
          selected.difference(expected).isEmpty &&
          expected.difference(selected).isNotEmpty) {
        return AttemptOutcome.partiallyCorrect;
      }
    }
    if (matchedSteps.isNotEmpty) return AttemptOutcome.partiallyCorrect;
    return AttemptOutcome.incorrect;
  }

  String _feedback(AttemptOutcome outcome, int matchedStepCount) {
    return switch (outcome) {
      AttemptOutcome.correct =>
        matchedStepCount == 0 ? '答案正确；补充解题依据后才能形成理解与推理证据。' : '答案与关键步骤匹配。',
      AttemptOutcome.partiallyCorrect => '已识别部分关键步骤，请继续完成推导。',
      AttemptOutcome.incorrect => '当前答案未通过规则判定，请检查条件和运算。',
    };
  }

  String _normalizeAnswer(PracticeQuestionType type, String value) {
    if (type == PracticeQuestionType.singleChoice ||
        type == PracticeQuestionType.multipleChoice) {
      final selections =
          value
              .toUpperCase()
              .split('')
              .where(
                (item) => const <String>{'A', 'B', 'C', 'D'}.contains(item),
              )
              .toSet()
              .toList()
            ..sort();
      return selections.join();
    }
    return _normalizeFreeText(value);
  }

  String _normalizeFreeText(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('，', ',')
        .replaceAll('：', ':')
        .replaceAll('（', '(')
        .replaceAll('）', ')');
  }
}

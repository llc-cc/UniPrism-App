import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/practice_assessment.dart';

void main() {
  test('2026 新高考 I 卷结构演示包含 19 题并保持题型分布', () async {
    final paper = await MockGaokaoMathRepository().loadPaper();

    expect(paper.id, 'cn-gaokao-2026-new-i-math-v1');
    expect(
      paper.questions.map((item) => item.number),
      orderedEquals(List<int>.generate(19, (index) => index + 1)),
    );
    expect(
      paper.questions.where(
        (item) => item.type == PracticeQuestionType.singleChoice,
      ),
      hasLength(8),
    );
    expect(
      paper.questions.where(
        (item) => item.type == PracticeQuestionType.multipleChoice,
      ),
      hasLength(3),
    );
    expect(
      paper.questions.where(
        (item) => item.type == PracticeQuestionType.fillBlank,
      ),
      hasLength(3),
    );
    expect(
      paper.questions.where(
        (item) => item.type == PracticeQuestionType.solution,
      ),
      hasLength(5),
    );
    expect(paper.isAuthorizedOfficialContent, isFalse);
    expect(
      paper.questions.every(
        (item) =>
            item.rubric!.steps.isNotEmpty && item.options.isNotEmpty ||
            item.type == PracticeQuestionType.fillBlank ||
            item.type == PracticeQuestionType.solution,
      ),
      isTrue,
    );
  });

  test('能力证据不足时不能携带分数', () {
    expect(
      () => AbilityObservation(
        dimension: AbilityDimension.understanding,
        status: AbilityEvidenceStatus.insufficientEvidence,
        band: 2,
        confidence: 0,
        evidenceStepIds: const [],
        factCodes: const [],
        errorTags: const [],
      ),
      throwsArgumentError,
    );
  });

  test('已观察能力必须携带 0 到 4 的等级', () {
    expect(
      () => AbilityObservation(
        dimension: AbilityDimension.calculation,
        status: AbilityEvidenceStatus.observed,
        confidence: 0.8,
        evidenceStepIds: const ['step-1'],
        factCodes: const ['answer-correct'],
        errorTags: const [],
      ),
      throwsArgumentError,
    );
    expect(
      () => AbilityObservation(
        dimension: AbilityDimension.calculation,
        status: AbilityEvidenceStatus.observed,
        band: 5,
        confidence: 0.8,
        evidenceStepIds: const ['step-1'],
        factCodes: const ['answer-correct'],
        errorTags: const [],
      ),
      throwsArgumentError,
    );
  });
}

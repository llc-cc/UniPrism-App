import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/practice_assessment.dart';

void main() {
  late PracticePaper paper;
  late RuleBasedAttemptAssessor assessor;

  setUp(() async {
    paper = await MockGaokaoMathRepository().loadPaper();
    assessor = const RuleBasedAttemptAssessor();
  });

  test('正确客观答案但没有过程时只形成确定结果', () {
    final assessment = assessor.assess(
      question: paper.questions[0],
      draft: const PracticeDraft(answer: 'B'),
      facts: const PracticeAttemptFacts(
        hintCount: 0,
        submissionCount: 1,
        durationSeconds: 30,
      ),
    );

    expect(assessment.outcome, AttemptOutcome.correct);
    expect(
      assessment.observationFor(AbilityDimension.understanding).status,
      AbilityEvidenceStatus.insufficientEvidence,
    );
    expect(
      assessment.observationFor(AbilityDimension.reasoning).status,
      AbilityEvidenceStatus.insufficientEvidence,
    );
  });

  test('命中 rubric 关键步骤时形成可追溯的理解和推理证据', () {
    final assessment = assessor.assess(
      question: paper.questions[6],
      draft: const PracticeDraft(
        answer: 'B',
        reasoning: '先利用总和约束，再用奇偶性排除，最后构造验证。',
      ),
      facts: const PracticeAttemptFacts(
        hintCount: 0,
        submissionCount: 1,
        durationSeconds: 95,
      ),
    );

    final observation = assessment.observationFor(AbilityDimension.reasoning);
    expect(observation.status, AbilityEvidenceStatus.observed);
    expect(observation.evidenceStepIds, hasLength(3));
    expect(observation.band, 4);
  });

  test('多选答案忽略顺序和大小写', () {
    final assessment = assessor.assess(
      question: paper.questions[8],
      draft: const PracticeDraft(answer: 'c, a'),
      facts: const PracticeAttemptFacts(
        hintCount: 0,
        submissionCount: 1,
        durationSeconds: 20,
      ),
    );

    expect(assessment.outcome, AttemptOutcome.correct);
  });

  test('填空答案忽略空白但不做符号代数猜测', () {
    final assessment = assessor.assess(
      question: paper.questions[11],
      draft: const PracticeDraft(answer: ' 3 / 2 '),
      facts: const PracticeAttemptFacts(
        hintCount: 0,
        submissionCount: 1,
        durationSeconds: 20,
      ),
    );

    expect(assessment.outcome, AttemptOutcome.correct);
  });

  test('解答题只命中部分步骤时返回部分正确', () {
    final assessment = assessor.assess(
      question: paper.questions[18],
      draft: const PracticeDraft(answer: '尚未完成', reasoning: '先理解定义，然后分类讨论。'),
      facts: const PracticeAttemptFacts(
        hintCount: 0,
        submissionCount: 1,
        durationSeconds: 180,
      ),
    );

    expect(assessment.outcome, AttemptOutcome.partiallyCorrect);
    expect(assessment.matchedStepIds, hasLength(2));
  });

  test('提示后的能力证据标为辅助且最高三档', () {
    final assessment = assessor.assess(
      question: paper.questions[6],
      draft: const PracticeDraft(answer: 'B', reasoning: '总和约束、奇偶性、构造验证。'),
      facts: const PracticeAttemptFacts(
        hintCount: 1,
        submissionCount: 1,
        durationSeconds: 60,
      ),
    );

    final observation = assessment.observationFor(AbilityDimension.reasoning);
    expect(observation.factCodes, contains('assisted'));
    expect(observation.band, 3);
  });

  test('修改后答对形成自我纠错证据', () {
    final assessment = assessor.assess(
      question: paper.questions[0],
      draft: const PracticeDraft(
        answer: 'B',
        reasoning: '排序后取中间位置。',
        revisionCount: 1,
      ),
      facts: const PracticeAttemptFacts(
        hintCount: 0,
        submissionCount: 2,
        durationSeconds: 50,
      ),
    );

    expect(
      assessment.observationFor(AbilityDimension.selfCorrection).status,
      AbilityEvidenceStatus.observed,
    );
  });

  test('训练投影不包含身份和设备字段', () {
    final question = paper.questions[6];
    const draft = PracticeDraft(answer: 'B', reasoning: '使用奇偶性排除。');
    const facts = PracticeAttemptFacts(
      hintCount: 0,
      submissionCount: 1,
      durationSeconds: 45,
    );
    final assessment = assessor.assess(
      question: question,
      draft: draft,
      facts: facts,
    );
    final example = assessor.projectTrainingExample(
      question: question,
      draft: draft,
      facts: facts,
      assessment: assessment,
    );

    final json = example.toJson();
    expect(json, isNot(contains('userId')));
    expect(json, isNot(contains('sessionId')));
    expect(json, isNot(contains('deviceId')));
    expect(json['questionId'], question.id);
  });
}

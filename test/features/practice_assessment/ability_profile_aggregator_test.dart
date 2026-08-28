import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/practice_assessment.dart';

void main() {
  test('聚合器仅加权已观察证据并忽略证据不足项', () {
    final assessments = <AttemptAssessment>[
      _assessment(
        reasoning: AbilityObservation(
          dimension: AbilityDimension.reasoning,
          status: AbilityEvidenceStatus.observed,
          band: 4,
          confidence: 0.8,
          evidenceStepIds: const ['q1-s1'],
          factCodes: const [],
          errorTags: const [],
        ),
      ),
      _assessment(
        reasoning: AbilityObservation(
          dimension: AbilityDimension.reasoning,
          status: AbilityEvidenceStatus.observed,
          band: 2,
          confidence: 0.4,
          evidenceStepIds: const ['q2-s1'],
          factCodes: const [],
          errorTags: const [],
        ),
      ),
      _assessment(
        reasoning: AbilityObservation(
          dimension: AbilityDimension.reasoning,
          status: AbilityEvidenceStatus.insufficientEvidence,
          confidence: 0,
          evidenceStepIds: const [],
          factCodes: const [],
          errorTags: const [],
        ),
      ),
    ];

    final profile = const AbilityProfileAggregator().aggregate(assessments);

    expect(profile[AbilityDimension.reasoning]!.score.round(), 83);
    expect(profile[AbilityDimension.reasoning]!.sampleCount, 2);
    expect(profile, isNot(contains(AbilityDimension.reading)));
  });
}

AttemptAssessment _assessment({required AbilityObservation reasoning}) {
  return AttemptAssessment(
    questionId: 'question',
    outcome: AttemptOutcome.partiallyCorrect,
    feedback: '测试',
    matchedStepIds: reasoning.evidenceStepIds,
    observations: <AbilityDimension, AbilityObservation>{
      AbilityDimension.reasoning: reasoning,
    },
    assessorVersion: 'test-v1',
    rubricVersion: 'rubric-v1',
  );
}

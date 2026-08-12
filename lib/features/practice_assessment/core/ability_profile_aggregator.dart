import 'practice_models.dart';

/// 某一能力维度的本地聚合摘要，只由实际观察证据计算。
final class AbilityProfileEntry {
  const AbilityProfileEntry({
    required this.dimension,
    required this.score,
    required this.confidence,
    required this.sampleCount,
  });

  final AbilityDimension dimension;
  final double score;
  final double confidence;
  final int sampleCount;
}

/// 将多次作答证据聚合为展示摘要；V1 不承担长期掌握度诊断。
final class AbilityProfileAggregator {
  const AbilityProfileAggregator();

  Map<AbilityDimension, AbilityProfileEntry> aggregate(
    Iterable<AttemptAssessment> assessments,
  ) {
    final weightedBands = <AbilityDimension, double>{};
    final confidenceSums = <AbilityDimension, double>{};
    final counts = <AbilityDimension, int>{};

    for (final assessment in assessments) {
      for (final observation in assessment.observations.values) {
        if (observation.status != AbilityEvidenceStatus.observed ||
            observation.band == null ||
            observation.confidence <= 0) {
          continue;
        }
        weightedBands.update(
          observation.dimension,
          (value) => value + observation.band! * observation.confidence,
          ifAbsent: () => observation.band! * observation.confidence,
        );
        confidenceSums.update(
          observation.dimension,
          (value) => value + observation.confidence,
          ifAbsent: () => observation.confidence,
        );
        counts.update(
          observation.dimension,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return Map<AbilityDimension, AbilityProfileEntry>.unmodifiable({
      for (final dimension in weightedBands.keys)
        dimension: AbilityProfileEntry(
          dimension: dimension,
          score: weightedBands[dimension]! / confidenceSums[dimension]! * 25,
          confidence: (confidenceSums[dimension]! / counts[dimension]!).clamp(
            0,
            1,
          ),
          sampleCount: counts[dimension]!,
        ),
    });
  }
}

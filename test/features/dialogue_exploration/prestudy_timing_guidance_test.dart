import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/core/prestudy_timing_guidance.dart';

void main() {
  test('keeps pre-study open before the five-minute reflection cue', () {
    final guidance = preStudyTimingGuidanceFor(const Duration(minutes: 4));

    expect(guidance, isNull);
  });

  test(
    'offers non-blocking reflection and summary cues at five, eight and ten minutes',
    () {
      expect(
        preStudyTimingGuidanceFor(const Duration(minutes: 5)),
        const PreStudyTimingGuidance(
          milestone: PreStudyTimingMilestone.reflect,
          message: '你已经探索约 5 分钟，可以用自己的话整理一个刚发现的规律。',
        ),
      );
      expect(
        preStudyTimingGuidanceFor(const Duration(minutes: 8)),
        const PreStudyTimingGuidance(
          milestone: PreStudyTimingMilestone.consolidate,
          message: '已接近本段预习建议时长：可以收束当前问题，也可以继续深挖。',
        ),
      );
      expect(
        preStudyTimingGuidanceFor(const Duration(minutes: 10)),
        const PreStudyTimingGuidance(
          milestone: PreStudyTimingMilestone.summarize,
          message: '本段预习已达到建议 10 分钟：建议结束并总结；你也可以继续探索。',
        ),
      );
    },
  );
}

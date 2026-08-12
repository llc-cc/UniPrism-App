/// 预习时长只用于帮助学生收束，不得作为强制退出课堂或判定掌握度的依据。
enum PreStudyTimingMilestone { reflect, consolidate, summarize }

final class PreStudyTimingGuidance {
  const PreStudyTimingGuidance({
    required this.milestone,
    required this.message,
  });

  final PreStudyTimingMilestone milestone;
  final String message;

  @override
  bool operator ==(Object other) {
    return other is PreStudyTimingGuidance &&
        other.milestone == milestone &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(milestone, message);
}

/// 按已探索时长返回单一、非阻断的课堂提示。
///
/// 10 分钟后仍返回总结建议，而不是“超时”状态，避免打断学生正在形成的问题链。
PreStudyTimingGuidance? preStudyTimingGuidanceFor(Duration elapsed) {
  if (elapsed < const Duration(minutes: 5)) return null;
  if (elapsed < const Duration(minutes: 8)) {
    return const PreStudyTimingGuidance(
      milestone: PreStudyTimingMilestone.reflect,
      message: '你已经探索约 5 分钟，可以用自己的话整理一个刚发现的规律。',
    );
  }
  if (elapsed < const Duration(minutes: 10)) {
    return const PreStudyTimingGuidance(
      milestone: PreStudyTimingMilestone.consolidate,
      message: '已接近本段预习建议时长：可以收束当前问题，也可以继续深挖。',
    );
  }
  return const PreStudyTimingGuidance(
    milestone: PreStudyTimingMilestone.summarize,
    message: '本段预习已达到建议 10 分钟：建议结束并总结；你也可以继续探索。',
  );
}

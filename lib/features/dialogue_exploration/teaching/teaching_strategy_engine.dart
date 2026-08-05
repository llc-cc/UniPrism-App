import '../mastery/student_mastery.dart';

/// 首版可自动组合的五种教学动作；它们由引擎选择，不暴露给学生手动切换。
enum TeachingDialogueMode {
  problemChain,
  socratic,
  errorTracing,
  analogyTransfer,
  selfExplanation,
}

/// 当前教学动作要解决的问题，用于评测策略切换是否真的服务学习目标。
enum TeachingStrategyGoal {
  mapQuestion,
  conceptUnderstanding,
  repairMisconception,
  transferUnderstanding,
  verifyUnderstanding,
}

/// Teaching Engine 对单轮对话的可回放决策。
final class TeachingStrategyDecision {
  const TeachingStrategyDecision({
    required this.mode,
    required this.goal,
    required this.reason,
    required this.depth,
    required this.allowMaterial,
  });

  final TeachingDialogueMode mode;
  final TeachingStrategyGoal goal;
  final String reason;
  final int depth;
  final bool allowMaterial;
}

/// 根据对话证据选择教学动作；只决定“怎么教”，不产生知识事实。
final class TeachingStrategyEngine {
  const TeachingStrategyEngine();

  TeachingStrategyDecision decide({
    required int turnIndex,
    required String studentText,
    required int consecutiveErrors,
    required bool isClosing,
    required StudentMasterySnapshot mastery,
  }) {
    // 已验证的错误优先处理，避免按固定课程进度跳过学生真实卡点。
    if (consecutiveErrors > 0) {
      return TeachingStrategyDecision(
        mode: TeachingDialogueMode.errorTracing,
        goal: TeachingStrategyGoal.repairMisconception,
        reason: '检测到错误证据，保留当前思路并用反例定位卡点',
        depth: _depthFor(mastery),
        allowMaterial: true,
      );
    }
    if (isClosing || _containsAny(studentText, const ['总结', '结束', '学会了'])) {
      return TeachingStrategyDecision(
        mode: TeachingDialogueMode.selfExplanation,
        goal: TeachingStrategyGoal.verifyUnderstanding,
        reason: 'Session 进入收口阶段，需要用学生自己的解释验证理解',
        depth: 1,
        allowMaterial: false,
      );
    }
    if (_containsAny(studentText, const ['抽象', '不懂', '不会', '不知道', '有什么用'])) {
      return TeachingStrategyDecision(
        mode: TeachingDialogueMode.analogyTransfer,
        goal: TeachingStrategyGoal.transferUnderstanding,
        reason: '学生表达抽象或卡住，切换到熟悉场景建立结构类比',
        depth: _depthFor(mastery),
        allowMaterial: true,
      );
    }
    if (turnIndex == 0) {
      return TeachingStrategyDecision(
        mode: TeachingDialogueMode.problemChain,
        goal: TeachingStrategyGoal.mapQuestion,
        reason: '新问题先拆出主干、前置概念和可继续探索的支线',
        depth: _depthFor(mastery),
        allowMaterial: true,
      );
    }
    return TeachingStrategyDecision(
      mode: TeachingDialogueMode.socratic,
      goal: TeachingStrategyGoal.conceptUnderstanding,
      reason: '继续追问当前结论使用的原理和成立条件',
      depth: _depthFor(mastery),
      allowMaterial: true,
    );
  }

  static int _depthFor(StudentMasterySnapshot mastery) {
    return switch (mastery.level) {
      StudentMasteryLevel.strong => 4,
      StudentMasteryLevel.developing => 3,
      StudentMasteryLevel.weak || StudentMasteryLevel.unknown => 2,
    };
  }

  static bool _containsAny(String value, List<String> signals) {
    return signals.any(value.contains);
  }
}

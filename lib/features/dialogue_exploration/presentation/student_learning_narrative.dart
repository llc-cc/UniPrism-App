import '../adapters/guided_teaching_flow_dto.dart';

/// 将服务端教学状态翻译成学生能直接理解的学习叙事。
///
/// 这里只转换文案，不根据客户端行为判断掌握度，也不改变阶段或证据。
abstract final class StudentLearningNarrative {
  static const explorationJourney = [
    '明确问题',
    '说出理由',
    '换种情况',
    '动手验证',
    '观察深挖',
    '形成发现',
    '迁移应用',
  ];

  static String explorationTitle(RemoteGuidedExplorationAct act) =>
      switch (act) {
        RemoteGuidedExplorationAct.clarifyScope => '先明确你真正想弄懂的问题',
        RemoteGuidedExplorationAct.probeReason => '说说为什么会这样想',
        RemoteGuidedExplorationAct.counterfactual => '换一种情况再想想',
        RemoteGuidedExplorationAct.formHypothesis => '用现象验证你的猜想',
        RemoteGuidedExplorationAct.postAssetObservation => '从现象里找证据',
        RemoteGuidedExplorationAct.deepenReasoning => '用反例继续深挖',
        RemoteGuidedExplorationAct.synthesizeDiscovery => '形成你自己的发现',
        RemoteGuidedExplorationAct.readyForCheck => '换个情况试试',
        RemoteGuidedExplorationAct.transferRevisit => '回到发现，修正薄弱点',
        RemoteGuidedExplorationAct.practiceRepair => '回到薄弱点重新理解',
        RemoteGuidedExplorationAct.unknown => '继续探索',
      };

  static int explorationJourneyIndex(
    RemoteTeachingStage stage,
    RemoteGuidedExplorationAct act,
  ) {
    if (stage == RemoteTeachingStage.asset) return 3;
    if (stage == RemoteTeachingStage.focus) return 6;
    if (stage == RemoteTeachingStage.reflect) return 5;
    return switch (act) {
      RemoteGuidedExplorationAct.clarifyScope => 0,
      RemoteGuidedExplorationAct.probeReason => 1,
      RemoteGuidedExplorationAct.counterfactual ||
      RemoteGuidedExplorationAct.formHypothesis => 2,
      RemoteGuidedExplorationAct.postAssetObservation ||
      RemoteGuidedExplorationAct.deepenReasoning => 4,
      RemoteGuidedExplorationAct.synthesizeDiscovery => 5,
      RemoteGuidedExplorationAct.readyForCheck => 6,
      RemoteGuidedExplorationAct.transferRevisit => 4,
      RemoteGuidedExplorationAct.practiceRepair => 6,
      RemoteGuidedExplorationAct.unknown => 0,
    };
  }

  static String stageTitle(RemoteTeachingStage stage) => switch (stage) {
    RemoteTeachingStage.dialogue => '先说说你的猜想',
    RemoteTeachingStage.asset => '我们验证一下',
    RemoteTeachingStage.focus => '把刚才的发现用一下',
    RemoteTeachingStage.reflect => '把今天的发现说出来',
    RemoteTeachingStage.unknown => '继续探索',
  };

  static String stageLabel(RemoteTeachingStage stage) => switch (stage) {
    RemoteTeachingStage.dialogue => '说出猜想',
    RemoteTeachingStage.asset => '动手验证',
    RemoteTeachingStage.focus => '迁移应用',
    RemoteTeachingStage.reflect => '整理收获',
    RemoteTeachingStage.unknown => '继续探索',
  };

  static String verificationMessage(RemoteEvidenceState evidence) {
    final missingCount = evidence.missingCodes.length;
    if (missingCount == 0 || evidence.isReadyForMicroCheck) {
      return '这个发现已经得到验证';
    }
    if (missingCount == 1) {
      return '还需要一次验证，确认你的想法';
    }
    return '还需要 $missingCount 次验证，确认你的想法';
  }

  /// 迁移失败时要明确告诉学生正在回到探索，避免连续出题造成“刷题补救”的感受。
  static String progressMessage(RemoteTeachingFlow flow) {
    if (flow.stage == RemoteTeachingStage.focus) {
      return '探索已经形成，现在换一个新情境，独立使用刚才的发现。';
    }
    if (flow.explorationAct == RemoteGuidedExplorationAct.transferRevisit) {
      return '新情境暴露了一个薄弱点：先回到探索，修正理解后再重新尝试。';
    }
    return verificationMessage(flow.evidence);
  }

  /// 第三轮后仍需新的独立作答，完整示范只能帮助修复思路，不能替代掌握证据。
  static String? supportMessage(int supportLevel) =>
      supportLevel >= 3 ? '我们先完整走一遍例子，再换一道新题由你独立完成。' : null;

  /// 模型与知识库来源留在后端审计信息中；学生只需区分普通回答和保守提示。
  static String? answerContextLabel(String? answerSource) =>
      answerSource == 'SAFE_FALLBACK' ? '当前提示' : null;

  static String chapterPhaseTitle(String kind) => switch (kind) {
    'LEARNING' => '先发现规律',
    'PRACTICE' => '动手试一试',
    'REVIEW' => '回看我的发现',
    _ => '继续学习',
  };

  static String chapterPhaseStatus(String status) => switch (status) {
    'LOCKED' => '完成前面后开启',
    'IN_PROGRESS' => '正在这里',
    'COMPLETED' => '已经完成',
    _ => '准备好了',
  };
}

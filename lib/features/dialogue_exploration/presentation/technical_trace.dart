import '../adapters/guided_teaching_flow_dto.dart';
import '../adapters/remote_exploration_dto.dart';

/// 技术轨迹只展示服务端已经给出的教学事实，不推导或暴露模型内部思维过程。
final class TechnicalTraceSnapshot {
  TechnicalTraceSnapshot({
    required this.isMock,
    required this.hasGuidedDecision,
    required this.sessionId,
    required this.currentNodeId,
    required this.lessonPlanId,
    required this.atomId,
    required this.goal,
    required this.stageLabel,
    required this.latestEvidence,
    required List<String> missingEvidenceCodes,
    required this.teacherAction,
    required this.pedagogicalIntent,
    required this.reasonCode,
    required this.mcpSelection,
    required this.timing,
    required this.fallbackUsed,
    required this.fallbackReason,
  }) : missingEvidenceCodes = List.unmodifiable(missingEvidenceCodes);

  final bool isMock;
  final bool hasGuidedDecision;
  final String sessionId;
  final String currentNodeId;
  final String lessonPlanId;
  final String atomId;
  final String goal;
  final String stageLabel;
  final TechnicalTraceEvidence? latestEvidence;
  final List<String> missingEvidenceCodes;
  final String teacherAction;
  final String pedagogicalIntent;
  final String reasonCode;
  final TechnicalTraceMcpSelection mcpSelection;
  final TechnicalTraceTiming timing;
  final bool fallbackUsed;
  final String fallbackReason;
}

final class TechnicalTraceEvidence {
  const TechnicalTraceEvidence({
    required this.code,
    required this.strengthLabel,
    required this.sourceType,
    required this.recordedAt,
  });

  final String code;
  final String strengthLabel;
  final String sourceType;
  final String recordedAt;
}

/// MCP 候选、过滤原因、版本和耗时目前没有真实遥测，因此必须整体标记为模拟数据。
final class TechnicalTraceMcpSelection {
  TechnicalTraceMcpSelection({
    required this.isSimulated,
    required this.toolName,
    required this.requestSummary,
    required this.candidateCount,
    required List<String> filteredReasons,
    required this.selectedMaterialId,
    required this.selectedVersion,
  }) : filteredReasons = List.unmodifiable(filteredReasons);

  final bool isSimulated;
  final String toolName;
  final String requestSummary;
  final int candidateCount;
  final List<String> filteredReasons;
  final String selectedMaterialId;
  final String selectedVersion;
}

final class TechnicalTraceTiming {
  const TechnicalTraceTiming({
    required this.agentMs,
    required this.mcpMs,
    required this.validationMs,
    required this.totalMs,
  });

  final int agentMs;
  final int mcpMs;
  final int validationMs;
  final int totalMs;
}

/// 在真实遥测接口接入前，稳定地把当前会话快照投影成可演示的技术轨迹。
///
/// 教学动作与证据来自真实快照；只有 MCP 检索细节和耗时使用固定 Mock，避免
/// 让刷新页面产生看似真实但互相矛盾的随机数据。
final class MockTechnicalTraceProvider {
  const MockTechnicalTraceProvider();

  TechnicalTraceSnapshot build(RemoteLearningSessionSnapshot snapshot) {
    final flow = snapshot.teachingFlow;
    final hasGuidedDecision =
        flow != null && flow.mode == RemoteFlowMode.guidedLesson;
    if (!hasGuidedDecision) {
      return TechnicalTraceSnapshot(
        isMock: true,
        hasGuidedDecision: false,
        sessionId: snapshot.session.id,
        currentNodeId: snapshot.currentNodeId ?? '',
        lessonPlanId: '',
        atomId: snapshot.session.atomId ?? '',
        goal: '',
        stageLabel: '开放探索',
        latestEvidence: null,
        missingEvidenceCodes: const [],
        teacherAction: '',
        pedagogicalIntent: '',
        reasonCode: '',
        mcpSelection: _emptyMcpSelection,
        timing: _emptyTiming,
        fallbackUsed: false,
        fallbackReason: '',
      );
    }

    final guidedFlow = flow;
    final material = _selectedMaterial(snapshot, guidedFlow);
    final latestEvidence = guidedFlow.evidence.items.isEmpty
        ? null
        : _mapEvidence(guidedFlow.evidence.items.last);
    final timing = _timingFor(guidedFlow.stage);

    return TechnicalTraceSnapshot(
      isMock: true,
      hasGuidedDecision: true,
      sessionId: snapshot.session.id,
      currentNodeId: snapshot.currentNodeId ?? '',
      lessonPlanId: guidedFlow.lessonPlanId,
      atomId: guidedFlow.atomId,
      goal: guidedFlow.goal,
      stageLabel: _stageLabel(guidedFlow.stage),
      latestEvidence: latestEvidence,
      missingEvidenceCodes: guidedFlow.evidence.missingCodes,
      teacherAction: guidedFlow.currentAction.prompt,
      pedagogicalIntent: guidedFlow.currentAction.pedagogicalIntent,
      reasonCode: guidedFlow.currentAction.reasonCode,
      mcpSelection: _mockMcpSelection(guidedFlow, material),
      timing: timing,
      fallbackUsed: false,
      fallbackReason: '',
    );
  }

  static const _emptyTiming = TechnicalTraceTiming(
    agentMs: 0,
    mcpMs: 0,
    validationMs: 0,
    totalMs: 0,
  );

  static final _emptyMcpSelection = TechnicalTraceMcpSelection(
    isSimulated: true,
    toolName: '',
    requestSummary: '',
    candidateCount: 0,
    filteredReasons: const [],
    selectedMaterialId: '',
    selectedVersion: '',
  );

  RemoteLearningMaterial? _selectedMaterial(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingFlow flow,
  ) {
    final usageId = flow.currentAction.materialUsageId;
    if (usageId != null) {
      for (final material in snapshot.materials) {
        if (material.id == usageId) return material;
      }
    }

    // 素材阶段结束后 action 可能已切换，保留最近一次素材便于回看完整教学轨迹。
    if (flow.stage == RemoteTeachingStage.focus ||
        flow.stage == RemoteTeachingStage.reflect) {
      return snapshot.materials.isEmpty ? null : snapshot.materials.last;
    }
    return null;
  }

  TechnicalTraceEvidence _mapEvidence(RemoteEvidenceItem evidence) {
    return TechnicalTraceEvidence(
      code: evidence.code,
      strengthLabel: switch (evidence.strength) {
        RemoteEvidenceStrength.observed => 'OBSERVED',
        RemoteEvidenceStrength.assisted => 'ASSISTED',
        RemoteEvidenceStrength.independent => 'INDEPENDENT',
        RemoteEvidenceStrength.unknown => 'UNKNOWN',
      },
      sourceType: evidence.sourceType,
      recordedAt: evidence.recordedAt,
    );
  }

  TechnicalTraceMcpSelection _mockMcpSelection(
    RemoteTeachingFlow flow,
    RemoteLearningMaterial? material,
  ) {
    if (material == null) return _emptyMcpSelection;
    return TechnicalTraceMcpSelection(
      isSimulated: true,
      toolName: 'search_teaching_assets',
      requestSummary:
          'atom=${flow.atomId}; intent=${flow.currentAction.pedagogicalIntent}',
      candidateCount: 4,
      filteredReasons: const ['排除未审核版本（模拟）', '排除设备不兼容素材（模拟）'],
      selectedMaterialId: material.materialId,
      selectedVersion: '${material.materialId}@mock-v1',
    );
  }

  String _stageLabel(RemoteTeachingStage stage) {
    return switch (stage) {
      RemoteTeachingStage.dialogue => '说出猜想',
      RemoteTeachingStage.asset => '动手验证',
      RemoteTeachingStage.focus => '确认发现',
      RemoteTeachingStage.reflect => '整理收获',
      RemoteTeachingStage.unknown => '开放探索',
    };
  }

  TechnicalTraceTiming _timingFor(RemoteTeachingStage stage) {
    return switch (stage) {
      RemoteTeachingStage.dialogue => const TechnicalTraceTiming(
        agentMs: 320,
        mcpMs: 0,
        validationMs: 24,
        totalMs: 344,
      ),
      RemoteTeachingStage.asset => const TechnicalTraceTiming(
        agentMs: 348,
        mcpMs: 176,
        validationMs: 31,
        totalMs: 555,
      ),
      RemoteTeachingStage.focus => const TechnicalTraceTiming(
        agentMs: 305,
        mcpMs: 0,
        validationMs: 28,
        totalMs: 333,
      ),
      RemoteTeachingStage.reflect => const TechnicalTraceTiming(
        agentMs: 286,
        mcpMs: 0,
        validationMs: 22,
        totalMs: 308,
      ),
      RemoteTeachingStage.unknown => _emptyTiming,
    };
  }
}

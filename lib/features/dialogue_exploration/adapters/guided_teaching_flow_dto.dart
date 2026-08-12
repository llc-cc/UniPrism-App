/// 会话创建模式由入口明确选择，客户端不根据返回内容猜测课堂类型。
enum RemoteFlowMode {
  openExploration('OPEN_EXPLORATION'),
  guidedLesson('GUIDED_LESSON');

  const RemoteFlowMode(this.wireValue);

  final String wireValue;

  static RemoteFlowMode fromWire(Object? value) {
    return value == guidedLesson.wireValue ? guidedLesson : openExploration;
  }
}

/// 引导课堂阶段只用于展示和约束交互；阶段推进始终由服务端快照决定。
enum RemoteTeachingStage {
  dialogue,
  asset,
  focus,
  reflect,
  unknown;

  static RemoteTeachingStage fromWire(Object? value) {
    return switch (value?.toString()) {
      'DIALOGUE' => dialogue,
      'ASSET' => asset,
      'FOCUS' => focus,
      'REFLECT' => reflect,
      _ => unknown,
    };
  }
}

enum RemoteEvidenceStrength {
  observed,
  assisted,
  independent,
  unknown;

  static RemoteEvidenceStrength fromWire(Object? value) {
    return switch (value?.toString()) {
      'OBSERVED' => observed,
      'ASSISTED' => assisted,
      'INDEPENDENT' => independent,
      _ => unknown,
    };
  }
}

/// V2 诊断结论由服务端计算；客户端仅用于呈现与决定允许的交互入口。
enum RemoteDiagnosticLevel {
  unknown,
  readyForCheck,
  needsClarification,
  needsTeaching;

  static RemoteDiagnosticLevel fromWire(Object? value) {
    return switch (value?.toString()) {
      'READY_FOR_CHECK' => readyForCheck,
      'NEEDS_CLARIFICATION' => needsClarification,
      'NEEDS_TEACHING' => needsTeaching,
      _ => unknown,
    };
  }
}

/// 服务端明确区分“形成发现”和“把发现用于新情境”，客户端不得用题目出现与否自行猜测。
enum RemoteGuidedLearningLayer {
  exploration,
  transfer,
  unknown;

  static RemoteGuidedLearningLayer fromWire(Object? value) {
    return switch (value?.toString()) {
      'EXPLORATION' => exploration,
      'TRANSFER' => transfer,
      _ => unknown,
    };
  }
}

/// 对话大阶段内的认知动作由服务端编排，客户端只负责呈现当前探索位置。
enum RemoteGuidedExplorationAct {
  clarifyScope,
  probeReason,
  counterfactual,
  formHypothesis,
  postAssetObservation,
  deepenReasoning,
  synthesizeDiscovery,
  readyForCheck,
  transferRevisit,
  practiceRepair,
  unknown;

  static RemoteGuidedExplorationAct fromWire(Object? value) {
    return switch (value?.toString()) {
      'CLARIFY_SCOPE' => clarifyScope,
      'PROBE_REASON' => probeReason,
      'COUNTERFACTUAL' => counterfactual,
      'FORM_HYPOTHESIS' => formHypothesis,
      'POST_ASSET_OBSERVATION' => postAssetObservation,
      'DEEPEN_REASONING' => deepenReasoning,
      'SYNTHESIZE_DISCOVERY' => synthesizeDiscovery,
      'READY_FOR_CHECK' => readyForCheck,
      'TRANSFER_REVISIT' => transferRevisit,
      'PRACTICE_REPAIR' => practiceRepair,
      _ => unknown,
    };
  }
}

/// 服务端指定的引导练习，标签与题干均不得由客户端推导或补全。
final class RemoteGuidedPractice {
  const RemoteGuidedPractice({
    required this.id,
    required this.title,
    required this.prompt,
    required this.reasoningLabel,
    required this.answerLabel,
  });

  static RemoteGuidedPractice? tryFromJson(Object? value) {
    final json = _map(value);
    final id = _nullableString(json['id']);
    final title = _nullableString(json['title']);
    final prompt = _nullableString(json['prompt']);
    final reasoningLabel = _nullableString(json['reasoningLabel']);
    final answerLabel = _nullableString(json['answerLabel']);
    if (id == null ||
        title == null ||
        prompt == null ||
        reasoningLabel == null ||
        answerLabel == null) {
      return null;
    }
    return RemoteGuidedPractice(
      id: id,
      title: title,
      prompt: prompt,
      reasoningLabel: reasoningLabel,
      answerLabel: answerLabel,
    );
  }

  final String id;
  final String title;
  final String prompt;
  final String reasoningLabel;
  final String answerLabel;
}

/// 后续学习建议携带服务端前置条件，避免客户端猜测学习路径是否可进入。
final class RemoteNextLearningOption {
  const RemoteNextLearningOption({
    required this.atomId,
    required this.chapterId,
    required this.title,
    required this.relation,
    required this.difficultyReason,
    required this.estimatedMinutes,
    required this.hookQuestion,
    required this.prerequisitesSatisfied,
  });

  static RemoteNextLearningOption? tryFromJson(Object? value) {
    final json = _map(value);
    final atomId = _nullableString(json['atomId']);
    final chapterId = _nullableString(json['chapterId']);
    final title = _nullableString(json['title']);
    final relation = _nullableString(json['relation']);
    final difficultyReason = _nullableString(json['difficultyReason']);
    final hookQuestion = _nullableString(json['hookQuestion']);
    if (atomId == null ||
        chapterId == null ||
        title == null ||
        relation == null ||
        difficultyReason == null ||
        hookQuestion == null) {
      return null;
    }
    return RemoteNextLearningOption(
      atomId: atomId,
      chapterId: chapterId,
      title: title,
      relation: relation,
      difficultyReason: difficultyReason,
      estimatedMinutes: _int(json['estimatedMinutes']),
      hookQuestion: hookQuestion,
      prerequisitesSatisfied: json['prerequisitesSatisfied'] == true,
    );
  }

  final String atomId;
  final String chapterId;
  final String title;
  final String relation;
  final String difficultyReason;
  final int estimatedMinutes;
  final String hookQuestion;
  final bool prerequisitesSatisfied;
}

/// 服务端给出的下一步教师动作；可选 ID 只在相应动作类型下出现。
final class RemoteTeacherAction {
  const RemoteTeacherAction({
    required this.schemaVersion,
    required this.type,
    required this.prompt,
    required this.pedagogicalIntent,
    required this.reasonCode,
    this.materialUsageId,
    this.practiceId,
  });

  factory RemoteTeacherAction.fromJson(Map<String, dynamic> json) {
    return RemoteTeacherAction(
      schemaVersion: _int(json['schemaVersion'], fallback: 1),
      type: _string(json['type']),
      prompt: _string(json['prompt']),
      pedagogicalIntent: _string(json['pedagogicalIntent']),
      reasonCode: _string(json['reasonCode']),
      materialUsageId: _nullableString(json['materialUsageId']),
      practiceId: _nullableString(json['practiceId']),
    );
  }

  final int schemaVersion;
  final String type;
  final String prompt;
  final String pedagogicalIntent;
  final String reasonCode;
  final String? materialUsageId;
  final String? practiceId;
}

final class RemoteEvidenceItem {
  const RemoteEvidenceItem({
    required this.code,
    required this.strength,
    required this.sourceType,
    required this.sourceId,
    required this.recordedAt,
  });

  factory RemoteEvidenceItem.fromJson(Map<String, dynamic> json) {
    return RemoteEvidenceItem(
      code: _string(json['code']),
      strength: RemoteEvidenceStrength.fromWire(json['strength']),
      sourceType: _string(json['sourceType']),
      sourceId: _string(json['sourceId']),
      recordedAt: _string(json['recordedAt']),
    );
  }

  final String code;
  final RemoteEvidenceStrength strength;
  final String sourceType;
  final String sourceId;
  final String recordedAt;
}

/// 证据状态直接投影服务端结果，避免客户端自行提升证据强度或判定掌握。
final class RemoteEvidenceState {
  const RemoteEvidenceState({
    required this.schemaVersion,
    required this.requiredCodes,
    required this.items,
    required this.missingCodes,
    required this.isReadyForMicroCheck,
  });

  factory RemoteEvidenceState.fromJson(Map<String, dynamic> json) {
    return RemoteEvidenceState(
      schemaVersion: _int(json['schemaVersion'], fallback: 1),
      requiredCodes: _strings(json['requiredCodes']),
      items: _list(json['items'])
          .map((item) => RemoteEvidenceItem.fromJson(_map(item)))
          .toList(growable: false),
      missingCodes: _strings(json['missingCodes']),
      isReadyForMicroCheck: json['isReadyForMicroCheck'] == true,
    );
  }

  final int schemaVersion;
  final List<String> requiredCodes;
  final List<RemoteEvidenceItem> items;
  final List<String> missingCodes;
  final bool isReadyForMicroCheck;
}

/// 服务端持久化的引导教学状态；旧快照没有该对象时仍按开放探索渲染。
final class RemoteTeachingFlow {
  RemoteTeachingFlow({
    required this.schemaVersion,
    this.mode = RemoteFlowMode.guidedLesson,
    required this.stage,
    required this.lessonPlanId,
    required this.atomId,
    required this.goal,
    this.assetEvidenceCode,
    this.independentEvidenceCode,
    required this.practiceId,
    required this.currentAction,
    required this.evidence,
    required this.hintLevel,
    required this.updatedAt,
    this.diagnosticLevel = RemoteDiagnosticLevel.unknown,
    this.diagnosticRound = 0,
    this.learningLayer = RemoteGuidedLearningLayer.unknown,
    this.explorationAct = RemoteGuidedExplorationAct.unknown,
    this.hypothesis,
    this.attemptRound = 0,
    this.supportLevel = 0,
    this.activePractice,
    List<RemoteGuidedPractice> practiceVariants = const [],
    this.feedback,
    this.repairFocus,
    List<RemoteNextLearningOption> nextLearningOptions = const [],
  }) : practiceVariants = List.unmodifiable(practiceVariants),
       nextLearningOptions = List.unmodifiable(nextLearningOptions);

  factory RemoteTeachingFlow.fromJson(Map<String, dynamic> json) {
    return RemoteTeachingFlow(
      schemaVersion: _int(json['schemaVersion'], fallback: 1),
      mode: RemoteFlowMode.fromWire(json['mode']),
      stage: RemoteTeachingStage.fromWire(json['stage']),
      lessonPlanId: _string(json['lessonPlanId']),
      atomId: _string(json['atomId']),
      goal: _string(json['goal']),
      assetEvidenceCode: _nullableString(json['assetEvidenceCode']),
      independentEvidenceCode: _nullableString(json['independentEvidenceCode']),
      practiceId: _string(json['practiceId']),
      currentAction: RemoteTeacherAction.fromJson(_map(json['currentAction'])),
      evidence: RemoteEvidenceState.fromJson(_map(json['evidence'])),
      hintLevel: _int(json['hintLevel']),
      updatedAt: _string(json['updatedAt']),
      diagnosticLevel: RemoteDiagnosticLevel.fromWire(json['diagnosticLevel']),
      diagnosticRound: _int(json['diagnosticRound']),
      learningLayer: RemoteGuidedLearningLayer.fromWire(json['learningLayer']),
      explorationAct: RemoteGuidedExplorationAct.fromWire(
        json['explorationAct'],
      ),
      hypothesis: _nullableString(json['hypothesis']),
      attemptRound: _int(json['attemptRound']),
      supportLevel: _int(json['supportLevel']),
      activePractice: RemoteGuidedPractice.tryFromJson(json['activePractice']),
      practiceVariants: _list(json['practiceVariants'])
          .map(RemoteGuidedPractice.tryFromJson)
          .whereType<RemoteGuidedPractice>()
          .toList(growable: false),
      feedback: _nullableString(json['feedback']),
      repairFocus: _nullableString(json['repairFocus']),
      nextLearningOptions: _list(json['nextLearningOptions'])
          .map(RemoteNextLearningOption.tryFromJson)
          .whereType<RemoteNextLearningOption>()
          .toList(growable: false),
    );
  }

  final int schemaVersion;
  final RemoteFlowMode mode;
  final RemoteTeachingStage stage;
  final String lessonPlanId;
  final String atomId;
  final String goal;
  final String? assetEvidenceCode;
  final String? independentEvidenceCode;
  final String practiceId;
  final RemoteTeacherAction currentAction;
  final RemoteEvidenceState evidence;
  final int hintLevel;
  final String updatedAt;
  final RemoteDiagnosticLevel diagnosticLevel;
  final int diagnosticRound;
  final RemoteGuidedLearningLayer learningLayer;
  final RemoteGuidedExplorationAct explorationAct;
  final String? hypothesis;
  final int attemptRound;
  final int supportLevel;
  final RemoteGuidedPractice? activePractice;
  final List<RemoteGuidedPractice> practiceVariants;
  final String? feedback;
  final String? repairFocus;
  final List<RemoteNextLearningOption> nextLearningOptions;
}

/// 素材组件只上报事实事件；事件 ID 在重试时保持不变，由服务端幂等去重。
final class RemoteAssetEvent {
  const RemoteAssetEvent({
    required this.schemaVersion,
    required this.eventId,
    required this.eventType,
    required this.occurredAt,
    required this.payload,
  });

  final int schemaVersion;
  final String eventId;
  final String eventType;
  final String occurredAt;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'eventId': eventId,
    'eventType': eventType,
    'occurredAt': occurredAt,
    'payload': payload,
  };
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return const {};
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

String _string(Object? value) => value?.toString() ?? '';

String? _nullableString(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int _int(Object? value, {int fallback = 0}) {
  return value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}

List<String> _strings(Object? value) {
  return _list(value).map((item) => item.toString()).toList(growable: false);
}

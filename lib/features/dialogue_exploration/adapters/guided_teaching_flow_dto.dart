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

/// 章节入口创建模式；`chapterGreeting` 表示 AI 老师先开口寒暄。
enum RemoteSessionEntryMode {
  chapterGreeting('CHAPTER_GREETING');

  const RemoteSessionEntryMode(this.wireValue);

  final String wireValue;
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

/// 课程目标级教学阶段；由服务端持久化，客户端只据此决定当前允许的交互入口。
enum RemoteTeachingPhase {
  conceptIntroduction('CONCEPT_INTRODUCTION'),
  example('EXAMPLE'),
  understandingCheck('UNDERSTANDING_CHECK'),
  modeSelection('MODE_SELECTION'),
  extraSupport('EXTRA_SUPPORT'),
  goalComplete('GOAL_COMPLETE'),
  unknown('UNKNOWN');

  const RemoteTeachingPhase(this.wireValue);

  final String wireValue;

  static RemoteTeachingPhase fromWire(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    for (final phase in RemoteTeachingPhase.values) {
      if (phase.wireValue == normalized) return phase;
    }
    return RemoteTeachingPhase.unknown;
  }
}

/// 单个学习目标的掌握状态；由服务端在 UNDERSTANDING_CHECK 判定后写入。
enum RemoteLessonGoalStatus {
  notStarted('NOT_STARTED'),
  inProgress('IN_PROGRESS'),
  mastered('MASTERED'),
  needsReview('NEEDS_REVIEW'),
  unknown('UNKNOWN');

  const RemoteLessonGoalStatus(this.wireValue);

  final String wireValue;

  static RemoteLessonGoalStatus fromWire(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    for (final status in RemoteLessonGoalStatus.values) {
      if (status.wireValue == normalized) return status;
    }
    return RemoteLessonGoalStatus.unknown;
  }
}

/// 教学模式菜单里的单个技能选项；label/icon/description 由服务端提供，客户端不改写。
final class RemoteTeachingModeOption {
  const RemoteTeachingModeOption({
    required this.skill,
    required this.label,
    required this.icon,
    required this.description,
  });

  static RemoteTeachingModeOption? tryFromJson(Object? value) {
    final json = _map(value);
    final skill = _nullableString(json['skill']);
    final label = _nullableString(json['label']);
    final icon = _nullableString(json['icon']);
    final description = _nullableString(json['description']);
    if (skill == null || label == null || icon == null || description == null) {
      return null;
    }
    return RemoteTeachingModeOption(
      skill: skill,
      label: label,
      icon: icon,
      description: description,
    );
  }

  /// 教学技能 wire code（例如 MORE_EXAMPLES、VIDEO），提交选择时原样回传服务端。
  final String skill;
  final String label;
  final String icon;
  final String description;
}

/// 课程目标级进程调度快照；每次会话状态刷新会覆盖旧值，客户端不能自行推进阶段。
final class RemoteProcessSchedulerState {
  RemoteProcessSchedulerState({
    required this.schemaVersion,
    required this.lessonPlanId,
    required this.currentGoalIndex,
    required this.currentPhase,
    required List<RemoteLessonGoalStatus> goalStatuses,
    List<RemoteTeachingModeOption>? modeMenuOptions,
    this.selectedSkill,
    required this.extraSupportCount,
    this.completedAt,
    required this.updatedAt,
  }) : goalStatuses = List.unmodifiable(goalStatuses),
       modeMenuOptions = modeMenuOptions == null
           ? null
           : List.unmodifiable(modeMenuOptions);

  static RemoteProcessSchedulerState? tryFromJson(Object? value) {
    if (value == null) return null;
    final json = _map(value);
    if (json.isEmpty) return null;
    final lessonPlanId = _nullableString(json['lessonPlanId']);
    if (lessonPlanId == null) return null;

    final modeMenuRaw = json['modeMenuOptions'];
    final modeMenuOptions = modeMenuRaw == null
        ? null
        : _list(modeMenuRaw)
              .map(RemoteTeachingModeOption.tryFromJson)
              .whereType<RemoteTeachingModeOption>()
              .toList(growable: false);

    return RemoteProcessSchedulerState(
      schemaVersion: _int(json['schemaVersion'], fallback: 1),
      lessonPlanId: lessonPlanId,
      currentGoalIndex: _int(json['currentGoalIndex']),
      currentPhase: RemoteTeachingPhase.fromWire(json['currentPhase']),
      goalStatuses: _list(json['goalStatuses'])
          .map(RemoteLessonGoalStatus.fromWire)
          .toList(growable: false),
      modeMenuOptions: modeMenuOptions,
      selectedSkill: _nullableString(json['selectedSkill']),
      extraSupportCount: _int(json['extraSupportCount']),
      completedAt: _nullableString(json['completedAt']),
      updatedAt: _nullableString(json['updatedAt']) ?? '',
    );
  }

  final int schemaVersion;
  final String lessonPlanId;
  final int currentGoalIndex;
  final RemoteTeachingPhase currentPhase;
  final List<RemoteLessonGoalStatus> goalStatuses;
  final List<RemoteTeachingModeOption>? modeMenuOptions;
  final String? selectedSkill;
  final int extraSupportCount;
  final String? completedAt;
  final String updatedAt;

  bool get isAwaitingModeSelection =>
      currentPhase == RemoteTeachingPhase.modeSelection &&
      (modeMenuOptions?.isNotEmpty ?? false);
}

/// GET /teaching-mode 返回的轻量快照；仅供 UI 独立拉取当前可选模式时使用。
final class RemoteTeachingModeOptionsSnapshot {
  RemoteTeachingModeOptionsSnapshot({
    required this.phase,
    required this.currentGoalIndex,
    List<RemoteTeachingModeOption>? options,
  }) : options = options == null ? null : List.unmodifiable(options);

  factory RemoteTeachingModeOptionsSnapshot.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return RemoteTeachingModeOptionsSnapshot(
      phase: RemoteTeachingPhase.fromWire(json['phase']),
      currentGoalIndex: _int(json['currentGoalIndex']),
      options: rawOptions == null
          ? null
          : _list(rawOptions)
                .map(RemoteTeachingModeOption.tryFromJson)
                .whereType<RemoteTeachingModeOption>()
                .toList(growable: false),
    );
  }

  final RemoteTeachingPhase phase;
  final int currentGoalIndex;
  final List<RemoteTeachingModeOption>? options;
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

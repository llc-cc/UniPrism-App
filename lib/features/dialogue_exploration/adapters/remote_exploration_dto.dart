import 'guided_teaching_flow_dto.dart';
import 'teaching_architecture_dto.dart';

/// Learning Entry 中单个可探索方向，内容由 1.1 Provider 提供而非页面硬编码。
final class LearningDirectionSnapshot {
  const LearningDirectionSnapshot({
    required this.id,
    required this.title,
    required this.description,
    required this.hookQuestion,
  });

  factory LearningDirectionSnapshot.fromJson(Map<String, dynamic> json) {
    return LearningDirectionSnapshot(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      description: _requiredString(json, 'description'),
      hookQuestion: _requiredString(json, 'hookQuestion'),
    );
  }

  final String id;
  final String title;
  final String description;
  final String hookQuestion;
}

/// 进入互动微课前的认知导航，不承载正式教学内容。
final class LearningEntrySnapshot {
  LearningEntrySnapshot({
    required this.atomId,
    required this.title,
    required this.coreQuestion,
    required this.estimatedMinutes,
    required this.recommendedDirectionId,
    required List<LearningDirectionSnapshot> directions,
  }) : directions = List.unmodifiable(directions);

  factory LearningEntrySnapshot.fromJson(Map<String, dynamic> json) {
    return LearningEntrySnapshot(
      atomId: _requiredString(json, 'atomId'),
      title: _requiredString(json, 'title'),
      coreQuestion: _requiredString(json, 'coreQuestion'),
      estimatedMinutes: _int(json['estimatedMinutes']),
      recommendedDirectionId: _requiredString(json, 'recommendedDirectionId'),
      directions: _list(json['directions'])
          .map((item) => LearningDirectionSnapshot.fromJson(_map(item)))
          .toList(growable: false),
    );
  }

  final String atomId;
  final String title;
  final String coreQuestion;
  final int estimatedMinutes;
  final String recommendedDirectionId;
  final List<LearningDirectionSnapshot> directions;
}

/// 章节入口寒暄与 DesignArena 选项，由知识库或服务端 entryGuidance 提供。
final class ChapterEntryGuidanceSnapshot {
  ChapterEntryGuidanceSnapshot({
    required List<String> welcomeMessages,
    required this.designArenaPromptTemplate,
    required List<RemoteTeachingModeOption> designArenaOptions,
  }) : welcomeMessages = List.unmodifiable(welcomeMessages),
       designArenaOptions = List.unmodifiable(designArenaOptions);

  factory ChapterEntryGuidanceSnapshot.fromJson(Map<String, dynamic> json) {
    return ChapterEntryGuidanceSnapshot(
      welcomeMessages: _strings(json['welcomeMessages']),
      designArenaPromptTemplate:
          _requiredString(json, 'designArenaPromptTemplate'),
      designArenaOptions: _list(json['designArenaOptions'])
          .map(RemoteTeachingModeOption.tryFromJson)
          .whereType<RemoteTeachingModeOption>()
          .toList(growable: false),
    );
  }

  static ChapterEntryGuidanceSnapshot? tryFromJson(Object? value) {
    if (value is! Map) return null;
    try {
      return ChapterEntryGuidanceSnapshot.fromJson(
        value.map((key, item) => MapEntry('$key', item)),
      );
    } catch (_) {
      return null;
    }
  }

  final List<String> welcomeMessages;
  final String designArenaPromptTemplate;
  final List<RemoteTeachingModeOption> designArenaOptions;

  String modePromptFor(String topic) {
    final label = topic.trim().isEmpty ? '本节课内容' : topic.trim();
    return designArenaPromptTemplate.replaceAll('{topic}', label);
  }
}

final class LearningChapterPhaseSnapshot {
  const LearningChapterPhaseSnapshot({
    required this.kind,
    required this.title,
    required this.summary,
    required this.status,
    required this.progress,
    required this.itemCount,
  });

  factory LearningChapterPhaseSnapshot.fromJson(Map<String, dynamic> json) {
    return LearningChapterPhaseSnapshot(
      kind: _requiredString(json, 'kind'),
      title: _requiredString(json, 'title'),
      summary: _requiredString(json, 'summary'),
      status: _requiredString(json, 'status'),
      progress: _doubleOrNull(json['progress']) ?? 0,
      itemCount: _int(json['itemCount']),
    );
  }

  final String kind;
  final String title;
  final String summary;
  final String status;
  final double progress;
  final int itemCount;
}

/// 章节知识节点来自知识库编排，不与学生在会话中生成的个人思维节点混存。
final class LearningChapterNodeSnapshot {
  const LearningChapterNodeSnapshot({
    required this.id,
    required this.parentId,
    required this.atomId,
    required this.title,
    required this.description,
    required this.phase,
    required this.hookQuestion,
    required this.recommended,
  });

  factory LearningChapterNodeSnapshot.fromJson(Map<String, dynamic> json) {
    return LearningChapterNodeSnapshot(
      id: _requiredString(json, 'id'),
      parentId: _nullableString(json['parentId']),
      atomId: _requiredString(json, 'atomId'),
      title: _requiredString(json, 'title'),
      description: _requiredString(json, 'description'),
      phase: _requiredString(json, 'phase'),
      hookQuestion: _requiredString(json, 'hookQuestion'),
      recommended: json['recommended'] == true,
    );
  }

  final String id;
  final String? parentId;
  final String atomId;
  final String title;
  final String description;
  final String phase;
  final String hookQuestion;
  final bool recommended;
}

/// 章节工作台的稳定只读快照；正式 1.1 知识库接入后保持该客户端契约不变。
final class LearningChapterOverviewSnapshot {
  LearningChapterOverviewSnapshot({
    required this.chapterId,
    required this.title,
    required this.description,
    required this.estimatedMinutes,
    required this.progress,
    required this.recommendedNodeId,
    required List<LearningChapterPhaseSnapshot> phases,
    required List<LearningChapterNodeSnapshot> nodes,
    this.entryGuidance,
  }) : phases = List.unmodifiable(phases),
       nodes = List.unmodifiable(nodes);

  factory LearningChapterOverviewSnapshot.fromJson(Map<String, dynamic> json) {
    return LearningChapterOverviewSnapshot(
      chapterId: _requiredString(json, 'chapterId'),
      title: _requiredString(json, 'title'),
      description: _requiredString(json, 'description'),
      estimatedMinutes: _int(json['estimatedMinutes']),
      progress: _doubleOrNull(json['progress']) ?? 0,
      recommendedNodeId: _requiredString(json, 'recommendedNodeId'),
      phases: _list(json['phases'])
          .map((item) => LearningChapterPhaseSnapshot.fromJson(_map(item)))
          .toList(growable: false),
      nodes: _list(json['nodes'])
          .map((item) => LearningChapterNodeSnapshot.fromJson(_map(item)))
          .toList(growable: false),
      entryGuidance: ChapterEntryGuidanceSnapshot.tryFromJson(
        json['entryGuidance'],
      ),
    );
  }

  final String chapterId;
  final String title;
  final String description;
  final int estimatedMinutes;
  final double progress;
  final String recommendedNodeId;
  final List<LearningChapterPhaseSnapshot> phases;
  final List<LearningChapterNodeSnapshot> nodes;
  final ChapterEntryGuidanceSnapshot? entryGuidance;

  LearningChapterNodeSnapshot? nodeById(String? id) {
    if (id == null) return null;
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }
}

/// 章节目录仅用于入口编排；详情仍须通过章节概览接口读取，避免目录数据被误当作完整学习状态。
final class LearningChapterCatalogItem {
  const LearningChapterCatalogItem({
    required this.chapterId,
    required this.title,
    required this.description,
    required this.estimatedMinutes,
    required this.availableNodeCount,
  });

  static LearningChapterCatalogItem? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, item) => MapEntry('$key', item));
    final chapterId = _nullableString(json['chapterId']);
    final title = _nullableString(json['title']);
    final description = _nullableString(json['description']);
    if (chapterId == null || title == null || description == null) return null;
    return LearningChapterCatalogItem(
      chapterId: chapterId,
      title: title,
      description: description,
      estimatedMinutes: _int(json['estimatedMinutes']),
      availableNodeCount: _int(json['availableNodeCount']),
    );
  }

  final String chapterId;
  final String title;
  final String description;
  final int estimatedMinutes;
  final int availableNodeCount;
}

/// 服务端学习会话的元信息；节点数和 revision 用于显示实时进度与并发版本。
final class RemoteLearningSessionSummary {
  const RemoteLearningSessionSummary({
    required this.id,
    required this.exploreSessionId,
    required this.topic,
    required this.scenarioId,
    required this.atomId,
    required this.status,
    required this.nodeCount,
    required this.startedAt,
    required this.expiresAt,
    required this.completedAt,
    required this.lastActiveAt,
  });

  factory RemoteLearningSessionSummary.fromJson(Map<String, dynamic> json) {
    return RemoteLearningSessionSummary(
      id: _requiredString(json, 'id'),
      exploreSessionId: _requiredString(json, 'exploreSessionId'),
      topic: _requiredString(json, 'topic'),
      scenarioId: _requiredString(json, 'scenarioId'),
      atomId: _nullableString(json['atomId']),
      status: _requiredString(json, 'status'),
      nodeCount: _int(json['nodeCount']),
      startedAt: _requiredString(json, 'startedAt'),
      expiresAt: _requiredString(json, 'expiresAt'),
      completedAt: _nullableString(json['completedAt']),
      lastActiveAt: _requiredString(json, 'lastActiveAt'),
    );
  }

  final String id;
  final String exploreSessionId;
  final String topic;
  final String scenarioId;
  final String? atomId;
  final String status;
  final int nodeCount;
  final String startedAt;
  final String expiresAt;
  final String? completedAt;
  final String lastActiveAt;

  bool get canContinue {
    final expiry = DateTime.tryParse(expiresAt);
    return status == 'ACTIVE' &&
        (expiry == null || expiry.isAfter(DateTime.now().toUtc()));
  }
}

/// 服务端学习会话的元信息；节点数和 revision 用于显示实时进度与并发版本。
final class RemoteLearningSessionInfo {
  const RemoteLearningSessionInfo({
    required this.id,
    required this.exploreSessionId,
    required this.topic,
    required this.scenarioId,
    required this.atomId,
    required this.status,
    required this.revision,
    required this.nodeCount,
    required this.startedAt,
    required this.expiresAt,
    required this.completedAt,
  });

  factory RemoteLearningSessionInfo.fromJson(Map<String, dynamic> json) {
    return RemoteLearningSessionInfo(
      id: _requiredString(json, 'id'),
      exploreSessionId: _requiredString(json, 'exploreSessionId'),
      topic: _requiredString(json, 'topic'),
      scenarioId: _requiredString(json, 'scenarioId'),
      atomId: _nullableString(json['atomId']),
      status: _requiredString(json, 'status'),
      revision: _int(json['revision']),
      nodeCount: _int(json['nodeCount']),
      startedAt: _requiredString(json, 'startedAt'),
      expiresAt: _requiredString(json, 'expiresAt'),
      completedAt: _nullableString(json['completedAt']),
    );
  }

  final String id;
  final String exploreSessionId;
  final String topic;
  final String scenarioId;
  final String? atomId;
  final String status;
  final int revision;
  final int nodeCount;
  final String startedAt;
  final String expiresAt;
  final String? completedAt;

  RemoteLearningSessionInfo copyWith({String? status, String? expiresAt}) {
    return RemoteLearningSessionInfo(
      id: id,
      exploreSessionId: exploreSessionId,
      topic: topic,
      scenarioId: scenarioId,
      atomId: atomId,
      status: status ?? this.status,
      revision: revision,
      nodeCount: nodeCount,
      startedAt: startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      completedAt: completedAt,
    );
  }
}

/// 树节点以学生真实问题为标题，同时保留 AI 回答、反问、策略和错误路径状态。
final class RemoteLearningNode {
  const RemoteLearningNode({
    required this.id,
    required this.parentId,
    required this.status,
    required this.question,
    required this.answer,
    required this.followUpQuestion,
    this.mapLabel,
    this.answerSource,
    this.turnIntent,
    required this.strategy,
    required this.depth,
    required this.isSideBranch,
    required this.backtrackTargetId,
    required this.confidence,
    required this.createdAt,
  });

  factory RemoteLearningNode.fromJson(Map<String, dynamic> json) {
    return RemoteLearningNode(
      id: _requiredString(json, 'id'),
      parentId: _nullableString(json['parentId']),
      status: _requiredString(json, 'status'),
      question: _nullableString(json['question']) ?? '',
      answer: _nullableString(json['answer']) ?? '',
      followUpQuestion: _nullableString(json['followUpQuestion']) ?? '',
      mapLabel: _nullableString(json['mapLabel']),
      answerSource: _nullableString(json['answerSource']),
      turnIntent: _nullableString(json['turnIntent']),
      strategy: _nullableString(json['strategy']),
      depth: _int(json['depth']),
      isSideBranch: json['isSideBranch'] == true,
      backtrackTargetId: _nullableString(json['backtrackTargetId']),
      confidence: _doubleOrNull(json['confidence']),
      createdAt: _requiredString(json, 'createdAt'),
    );
  }

  final String id;
  final String? parentId;
  final String status;
  final String question;
  final String answer;
  final String followUpQuestion;
  final String? mapLabel;
  final String? answerSource;
  final String? turnIntent;
  final String? strategy;
  final int depth;
  final bool isSideBranch;
  final String? backtrackTargetId;
  final double? confidence;
  final String createdAt;
}

/// 服务端从完整对话轮次提炼出的认知节点；evidenceNodeId 可定位回形成该理解的原始对话。
final class RemoteLearningConceptNode {
  const RemoteLearningConceptNode({
    required this.id,
    required this.parentId,
    required this.label,
    required this.kind,
    required this.status,
    required this.relation,
    required this.evidenceNodeId,
    required this.confidence,
  });

  factory RemoteLearningConceptNode.fromJson(Map<String, dynamic> json) {
    return RemoteLearningConceptNode(
      id: _requiredString(json, 'id'),
      parentId: _nullableString(json['parentId']),
      label: _requiredString(json, 'label'),
      kind: _requiredString(json, 'kind'),
      status: _requiredString(json, 'status'),
      relation: _requiredString(json, 'relation'),
      evidenceNodeId: _requiredString(json, 'evidenceNodeId'),
      confidence: _doubleOrNull(json['confidence']),
    );
  }

  final String id;
  final String? parentId;
  final String label;
  final String kind;
  final String status;
  final String relation;
  final String evidenceNodeId;
  final double? confidence;
}

/// 一轮对话实际调用的素材记录；payload 只在对应素材组件内解释。
final class RemoteLearningMaterial {
  const RemoteLearningMaterial({
    required this.id,
    required this.nodeId,
    required this.materialId,
    required this.type,
    required this.title,
    required this.componentKey,
    required this.payload,
    this.hasRecordedInteraction = false,
  });

  factory RemoteLearningMaterial.fromJson(Map<String, dynamic> json) {
    return RemoteLearningMaterial(
      id: _nullableString(json['id']) ?? _requiredString(json, 'materialId'),
      nodeId: _requiredString(json, 'nodeId'),
      materialId: _requiredString(json, 'materialId'),
      type: _requiredString(json, 'type'),
      title: _requiredString(json, 'title'),
      componentKey: _nullableString(json['componentKey']),
      payload: _mapOrEmpty(json['payload']),
      hasRecordedInteraction:
          json['interactionEvents'] is List &&
          (json['interactionEvents'] as List).isNotEmpty,
    );
  }

  final String id;
  final String nodeId;
  final String materialId;
  final String type;
  final String title;
  final String? componentKey;
  final Map<String, dynamic> payload;

  /// 历史素材只有产生过完成、跳过或操作事件，才能证明学生真实到达过该节点。
  final bool hasRecordedInteraction;
}

/// 学生主动复述后生成的本次学习产出摘要。
final class RemoteLearningSummary {
  const RemoteLearningSummary({
    required this.studentRestatement,
    required this.concept,
    required this.application,
    required this.boundary,
    required this.misconceptions,
    required this.interestDirections,
    required this.recommendedReview,
  });

  factory RemoteLearningSummary.fromJson(Map<String, dynamic> json) {
    final understanding = _mapOrEmpty(json['understanding']);
    return RemoteLearningSummary(
      studentRestatement: _nullableString(json['studentRestatement']) ?? '',
      concept: _int(understanding['concept']),
      application: _int(understanding['application']),
      boundary: _int(understanding['boundary']),
      misconceptions: _strings(json['misconceptions']),
      interestDirections: _strings(json['interestDirections']),
      recommendedReview: _strings(json['recommendedReview']),
    );
  }

  final String studentRestatement;
  final int concept;
  final int application;
  final int boundary;
  final List<String> misconceptions;
  final List<String> interestDirections;
  final List<String> recommendedReview;
}

/// 练习节点由练习服务生成；当前阶段保留 Mock 标识，避免把测试样本误当成学生已完成的练习。
final class RemoteLearningPracticeNode {
  const RemoteLearningPracticeNode({
    required this.id,
    required this.title,
    required this.prompt,
    required this.purpose,
    required this.status,
    required this.latestReasoning,
    required this.latestAnswer,
    required this.feedback,
  });

  factory RemoteLearningPracticeNode.fromJson(Map<String, dynamic> json) {
    return RemoteLearningPracticeNode(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      prompt: _requiredString(json, 'prompt'),
      purpose: _requiredString(json, 'purpose'),
      status: _requiredString(json, 'status'),
      latestReasoning: _nullableString(json['latestReasoning']),
      latestAnswer: _nullableString(json['latestAnswer']),
      feedback: _nullableString(json['feedback']),
    );
  }

  final String id;
  final String title;
  final String prompt;
  final String purpose;
  final String status;
  final String? latestReasoning;
  final String? latestAnswer;
  final String? feedback;
}

/// 一道练习的步骤证据；真实解题记录接入后会按学生提交实时替换。
final class RemoteLearningSolutionPathNode {
  const RemoteLearningSolutionPathNode({
    required this.practiceId,
    required this.steps,
  });

  factory RemoteLearningSolutionPathNode.fromJson(Map<String, dynamic> json) {
    return RemoteLearningSolutionPathNode(
      practiceId: _requiredString(json, 'practiceId'),
      steps: _strings(json['steps']),
    );
  }

  final String practiceId;
  final List<String> steps;
}

/// 掌握度只引用会话和练习证据，不在客户端自行推断学生表现。
final class RemoteLearningMasteryNode {
  const RemoteLearningMasteryNode({
    required this.dimension,
    required this.score,
    required this.evidence,
  });

  factory RemoteLearningMasteryNode.fromJson(Map<String, dynamic> json) {
    return RemoteLearningMasteryNode(
      dimension: _requiredString(json, 'dimension'),
      score: _int(json['score']),
      evidence: _strings(json['evidence']),
    );
  }

  final String dimension;
  final int score;
  final List<String> evidence;
}

/// 服务端基于学生真实问题与练习过程生成的诊断；待验证不等于薄弱，
/// 客户端只负责忠实展示证据，不能自行给学生贴“不会”的标签。
final class RemoteLearningDiagnostic {
  const RemoteLearningDiagnostic({
    required this.id,
    required this.dimension,
    required this.status,
    required this.title,
    required this.observation,
    required this.evidence,
    required this.nextAction,
  });

  factory RemoteLearningDiagnostic.fromJson(Map<String, dynamic> json) {
    return RemoteLearningDiagnostic(
      id: _requiredString(json, 'id'),
      dimension: _requiredString(json, 'dimension'),
      status: _requiredString(json, 'status'),
      title: _requiredString(json, 'title'),
      observation: _requiredString(json, 'observation'),
      evidence: _strings(json['evidence']),
      nextAction: _requiredString(json, 'nextAction'),
    );
  }

  final String id;
  final String dimension;
  final String status;
  final String title;
  final String observation;
  final List<String> evidence;
  final String nextAction;
}

/// 后端统一派生的学习图；知识库和练习服务完成后保持该客户端读取契约不变。
final class RemoteLearningGraph {
  RemoteLearningGraph({
    required this.conceptTitle,
    required this.explorationQuestion,
    required List<RemoteLearningPracticeNode> practice,
    required List<RemoteLearningSolutionPathNode> solutionPaths,
    required List<RemoteLearningMasteryNode> mastery,
    List<RemoteLearningDiagnostic> diagnostics = const [],
    required List<RemoteLearningNextChallenge> nextChallenges,
  }) : practice = List.unmodifiable(practice),
       solutionPaths = List.unmodifiable(solutionPaths),
       mastery = List.unmodifiable(mastery),
       diagnostics = List.unmodifiable(diagnostics),
       nextChallenges = List.unmodifiable(nextChallenges);

  factory RemoteLearningGraph.fromJson(Map<String, dynamic> json) {
    final concept = _mapOrEmpty(json['concept']);
    final exploration = _mapOrEmpty(json['exploration']);
    return RemoteLearningGraph(
      conceptTitle: _nullableString(concept['title']) ?? '当前概念',
      explorationQuestion:
          _nullableString(exploration['question']) ?? '正在形成探索问题',
      practice: _list(json['practice'])
          .map((item) => RemoteLearningPracticeNode.fromJson(_map(item)))
          .toList(growable: false),
      solutionPaths: _list(json['solutionPaths'])
          .map((item) => RemoteLearningSolutionPathNode.fromJson(_map(item)))
          .toList(growable: false),
      mastery: _list(json['mastery'])
          .map((item) => RemoteLearningMasteryNode.fromJson(_map(item)))
          .toList(growable: false),
      diagnostics: _list(json['diagnostics'])
          .map((item) => RemoteLearningDiagnostic.fromJson(_map(item)))
          .toList(growable: false),
      nextChallenges: _list(json['nextChallenges'])
          .map((item) => RemoteLearningNextChallenge.fromJson(_map(item)))
          .toList(growable: false),
    );
  }

  final String conceptTitle;
  final String explorationQuestion;
  final List<RemoteLearningPracticeNode> practice;
  final List<RemoteLearningSolutionPathNode> solutionPaths;
  final List<RemoteLearningMasteryNode> mastery;
  final List<RemoteLearningDiagnostic> diagnostics;
  final List<RemoteLearningNextChallenge> nextChallenges;

  RemoteLearningSolutionPathNode? solutionPathFor(String practiceId) {
    for (final path in solutionPaths) {
      if (path.practiceId == practiceId) return path;
    }
    return null;
  }
}

/// 章节掌握后由后端解锁的相邻挑战，不在客户端硬编码难度路线。
final class RemoteLearningNextChallenge {
  const RemoteLearningNextChallenge({
    required this.id,
    required this.title,
    required this.question,
  });

  factory RemoteLearningNextChallenge.fromJson(Map<String, dynamic> json) {
    return RemoteLearningNextChallenge(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      question: _requiredString(json, 'question'),
    );
  }

  final String id;
  final String title;
  final String question;
}

/// 服务端面向学生视角的精简引导，避免前端解析 teachingFlow 内部状态。
final class RemoteStudentGuidance {
  const RemoteStudentGuidance({
    required this.stageLabel,
    required this.actionHint,
    required this.materialReady,
    required this.materialInteractable,
    required this.canSubmitText,
    required this.showMaterialArea,
    required this.showPracticeArea,
    this.showModeSelection,
    this.teacherIntroMessages,
    this.modeSelectionPrompt,
  });

  factory RemoteStudentGuidance.fromJson(Map<String, dynamic> json) {
    final intro = json['teacherIntroMessages'];
    return RemoteStudentGuidance(
      stageLabel: _nullableString(json['stageLabel']) ?? '继续学习',
      actionHint: _nullableString(json['actionHint']) ?? '',
      materialReady: json['materialReady'] == true,
      materialInteractable: json['materialInteractable'] == true,
      canSubmitText: json['canSubmitText'] == true,
      showMaterialArea: json['showMaterialArea'] == true,
      showPracticeArea: json['showPracticeArea'] == true,
      showModeSelection: json['showModeSelection'] as bool?,
      teacherIntroMessages: intro is List
          ? _strings(intro)
          : null,
      modeSelectionPrompt: _nullableString(json['modeSelectionPrompt']),
    );
  }

  static RemoteStudentGuidance? tryFromJson(Object? value) {
    if (value is! Map) return null;
    return RemoteStudentGuidance.fromJson(
      value.map((k, v) => MapEntry('$k', v)),
    );
  }

  final String stageLabel;
  final String actionHint;
  final bool materialReady;
  final bool materialInteractable;
  final bool canSubmitText;
  final bool showMaterialArea;
  final bool showPracticeArea;
  final bool? showModeSelection;
  final List<String>? teacherIntroMessages;
  final String? modeSelectionPrompt;
}

final class RemoteCourseTimeBudget {
  const RemoteCourseTimeBudget({
    required this.totalMinutes,
    required this.elapsedMinutes,
    required this.remainingMinutes,
    required this.policy,
  });

  static RemoteCourseTimeBudget? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, item) => MapEntry('$key', item));
    return RemoteCourseTimeBudget(
      totalMinutes: _int(json['totalMinutes']),
      elapsedMinutes: _int(json['elapsedMinutes']),
      remainingMinutes: _int(json['remainingMinutes']),
      policy: _nullableString(json['policy']) ?? 'NORMAL',
    );
  }

  final int totalMinutes;
  final int elapsedMinutes;
  final int remainingMinutes;
  final String policy;
}

final class RemoteTeacherDecision {
  const RemoteTeacherDecision({
    required this.action,
    required this.reasonCode,
    required this.reason,
    this.skill,
    required this.decidedAt,
  });

  static RemoteTeacherDecision? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, item) => MapEntry('$key', item));
    final action = _nullableString(json['action']);
    if (action == null) return null;
    return RemoteTeacherDecision(
      action: action,
      reasonCode: _nullableString(json['reasonCode']) ?? '',
      reason: _nullableString(json['reason']) ?? '',
      skill: _nullableString(json['skill']),
      decidedAt: _nullableString(json['decidedAt']) ?? '',
    );
  }

  final String action;
  final String reasonCode;
  final String reason;
  final String? skill;
  final String decidedAt;
}

final class RemoteCourseCapabilities {
  const RemoteCourseCapabilities({
    required this.canSubmitText,
    required this.canSelectMode,
    required this.canSubmitMaterial,
    required this.canSkipMaterial,
    required this.canSwitchMaterial,
    required this.canSubmitPractice,
    required this.canComplete,
  });

  static RemoteCourseCapabilities? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, item) => MapEntry('$key', item));
    return RemoteCourseCapabilities(
      canSubmitText: json['canSubmitText'] == true,
      canSelectMode: json['canSelectMode'] == true,
      canSubmitMaterial: json['canSubmitMaterial'] == true,
      canSkipMaterial: json['canSkipMaterial'] == true,
      canSwitchMaterial: json['canSwitchMaterial'] == true,
      canSubmitPractice: json['canSubmitPractice'] == true,
      canComplete: json['canComplete'] == true,
    );
  }

  final bool canSubmitText;
  final bool canSelectMode;
  final bool canSubmitMaterial;
  final bool canSkipMaterial;
  final bool canSwitchMaterial;
  final bool canSubmitPractice;
  final bool canComplete;
}

final class RemoteCourseState {
  const RemoteCourseState({
    required this.currentStage,
    required this.currentGoal,
    required this.currentGoalIndex,
    required this.supportCount,
    required this.completionStatus,
    this.selectedMode,
    this.currentMaterial,
    this.practiceResult,
    this.timeBudget,
  });

  static RemoteCourseState? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, item) => MapEntry('$key', item));
    final currentStage =
        _nullableString(json['currentStage']) ??
        _nullableString(json['currentPhase']);
    if (currentStage == null) return null;
    return RemoteCourseState(
      currentStage: currentStage,
      currentGoal:
          _nullableString(json['currentGoal']) ??
          'G${_int(json['currentGoalIndex']) + 1}',
      currentGoalIndex: _int(json['currentGoalIndex']),
      supportCount: json.containsKey('supportCount')
          ? _int(json['supportCount'])
          : _int(json['extraSupportCount']),
      completionStatus:
          _nullableString(json['completionStatus']) ?? 'IN_PROGRESS',
      selectedMode:
          _nullableString(json['selectedMode']) ??
          _nullableString(json['selectedSkill']),
      currentMaterial: _nullableString(json['currentMaterial']),
      practiceResult: _nullableString(json['practiceResult']),
      timeBudget: RemoteCourseTimeBudget.tryFromJson(json['timeBudget']),
    );
  }

  final String currentStage;
  final String currentGoal;
  final int currentGoalIndex;
  final int supportCount;
  final String completionStatus;
  final String? selectedMode;
  final String? currentMaterial;
  final String? practiceResult;
  final RemoteCourseTimeBudget? timeBudget;
}

/// 客户端每次原子替换的完整服务端快照，避免本地猜测树合并结果。
final class RemoteLearningSessionSnapshot {
  RemoteLearningSessionSnapshot({
    required this.session,
    required this.currentNodeId,
    required this.activeStrategy,
    required List<RemoteLearningNode> nodes,
    List<RemoteLearningConceptNode> conceptNodes = const [],
    required List<RemoteLearningMaterial> materials,
    required this.summary,
    this.learningGraph,
    this.teachingFlow,
    this.processSchedulerState,
    this.studentGuidance,
    this.courseState,
    this.teacherDecision,
    this.capabilities,
    List<String> allowedActions = const [],
    this.teachingArchitecture,
  }) : nodes = List.unmodifiable(nodes),
       conceptNodes = List.unmodifiable(conceptNodes),
       materials = List.unmodifiable(materials),
       allowedActions = List.unmodifiable(allowedActions);

  factory RemoteLearningSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final summaryJson = json['summary'];
    final learningGraphJson = json['learningGraph'];
    final teachingFlowJson = json['teachingFlow'];
    return RemoteLearningSessionSnapshot(
      session: RemoteLearningSessionInfo.fromJson(_map(json['session'])),
      currentNodeId: _nullableString(json['currentNodeId']),
      activeStrategy: _nullableString(json['activeStrategy']),
      nodes: _list(json['nodes'])
          .map((item) => RemoteLearningNode.fromJson(_map(item)))
          .toList(growable: false),
      conceptNodes: _list(json['conceptNodes'])
          .map((item) => RemoteLearningConceptNode.fromJson(_map(item)))
          .toList(growable: false),
      materials: _list(json['materials'])
          .map((item) => RemoteLearningMaterial.fromJson(_map(item)))
          .toList(growable: false),
      summary: summaryJson == null
          ? null
          : RemoteLearningSummary.fromJson(_map(summaryJson)),
      learningGraph: learningGraphJson == null
          ? null
          : RemoteLearningGraph.fromJson(_map(learningGraphJson)),
      teachingFlow: teachingFlowJson == null
          ? null
          : RemoteTeachingFlow.fromJson(_map(teachingFlowJson)),
      // 旧后端快照没有该字段；tryFromJson 返回 null，让 UI 继续按 TeachingFlow 渲染。
      processSchedulerState: RemoteProcessSchedulerState.tryFromJson(
        json['processSchedulerState'],
      ),
      studentGuidance: RemoteStudentGuidance.tryFromJson(
        json['studentGuidance'],
      ),
      courseState: RemoteCourseState.tryFromJson(json['courseState']),
      teacherDecision: RemoteTeacherDecision.tryFromJson(
        json['teacherDecision'],
      ),
      capabilities: RemoteCourseCapabilities.tryFromJson(json['capabilities']),
      allowedActions: _strings(json['allowedActions']),
      teachingArchitecture: RemoteTeachingArchitectureSnapshot.tryFromJson(
        json['teachingArchitecture'],
      ),
    );
  }

  final RemoteLearningSessionInfo session;
  final String? currentNodeId;
  final String? activeStrategy;
  final List<RemoteLearningNode> nodes;
  final List<RemoteLearningConceptNode> conceptNodes;
  final List<RemoteLearningMaterial> materials;
  final RemoteLearningSummary? summary;
  final RemoteLearningGraph? learningGraph;
  final RemoteTeachingFlow? teachingFlow;
  final RemoteProcessSchedulerState? processSchedulerState;
  final RemoteStudentGuidance? studentGuidance;
  final RemoteCourseState? courseState;
  final RemoteTeacherDecision? teacherDecision;
  final RemoteCourseCapabilities? capabilities;
  final List<String> allowedActions;
  final RemoteTeachingArchitectureSnapshot? teachingArchitecture;

  bool allows(String action) => allowedActions.contains(action);

  RemoteLearningNode? nodeById(String? id) {
    if (id == null) return null;
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<RemoteLearningNode> pathTo(String? nodeId) {
    final result = <RemoteLearningNode>[];
    var current = nodeById(nodeId);
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      result.insert(0, current);
      current = nodeById(current.parentId);
    }
    return List.unmodifiable(result);
  }

  /// 兼容尚未重启的旧后端：缺少 conceptNodes 时只在客户端临时投影，不写回数据库。
  List<RemoteLearningConceptNode> get displayConceptNodes {
    if (conceptNodes.isNotEmpty) return conceptNodes;
    final result = <RemoteLearningConceptNode>[];
    final conceptIdByLabel = <String, String>{};
    final conceptIdByTurn = <String, String>{};
    for (final node in nodes) {
      final label = (node.mapLabel?.trim().isNotEmpty ?? false)
          ? node.mapLabel!.trim()
          : node.question.trim();
      if (label.isEmpty) continue;
      final normalized = label.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      final existing = conceptIdByLabel[normalized];
      if (existing != null) {
        conceptIdByTurn[node.id] = existing;
        continue;
      }
      final id = 'concept-${node.id}';
      final parentId = node.parentId == null
          ? null
          : conceptIdByTurn[node.parentId!];
      result.add(
        RemoteLearningConceptNode(
          id: id,
          parentId: parentId,
          label: label,
          kind: node.status == 'CONTRADICTED' ? 'MISCONCEPTION' : 'CONCEPT',
          status: node.status == 'CONTRADICTED' ? 'CONFLICTED' : 'VALIDATED',
          relation: node.status == 'CONTRADICTED'
              ? 'CONTRADICTS'
              : node.isSideBranch
              ? 'BRANCH'
              : parentId == null
              ? 'ROOT'
              : 'DEEPENS',
          evidenceNodeId: node.id,
          confidence: node.confidence,
        ),
      );
      conceptIdByLabel[normalized] = id;
      conceptIdByTurn[node.id] = id;
    }
    return List.unmodifiable(result);
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw const FormatException('服务端返回对象格式不正确');
}

Map<String, dynamic> _mapOrEmpty(Object? value) {
  if (value == null) return const {};
  return _map(value);
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _nullableString(json[key]);
  if (value == null) throw FormatException('服务端缺少字段：$key');
  return value;
}

String? _nullableString(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double? _doubleOrNull(Object? value) {
  if (value == null) return null;
  return value is num ? value.toDouble() : double.tryParse('$value');
}

List<String> _strings(Object? value) {
  return _list(value).map((item) => item.toString()).toList(growable: false);
}

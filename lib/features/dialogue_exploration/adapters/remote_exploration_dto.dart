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

/// 章节阶段只描述学习路径状态；练习和复习的具体流程由各自模块继续承载。
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

  LearningChapterNodeSnapshot? nodeById(String? id) {
    if (id == null) return null;
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
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

  RemoteLearningSessionInfo copyWith({String? status}) {
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
      expiresAt: expiresAt,
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
  final String? strategy;
  final int depth;
  final bool isSideBranch;
  final String? backtrackTargetId;
  final double? confidence;
  final String createdAt;
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
    );
  }

  final String id;
  final String nodeId;
  final String materialId;
  final String type;
  final String title;
  final String? componentKey;
  final Map<String, dynamic> payload;
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

/// 客户端每次原子替换的完整服务端快照，避免本地猜测树合并结果。
final class RemoteLearningSessionSnapshot {
  RemoteLearningSessionSnapshot({
    required this.session,
    required this.currentNodeId,
    required this.activeStrategy,
    required List<RemoteLearningNode> nodes,
    required List<RemoteLearningMaterial> materials,
    required this.summary,
  }) : nodes = List.unmodifiable(nodes),
       materials = List.unmodifiable(materials);

  factory RemoteLearningSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final summaryJson = json['summary'];
    return RemoteLearningSessionSnapshot(
      session: RemoteLearningSessionInfo.fromJson(_map(json['session'])),
      currentNodeId: _nullableString(json['currentNodeId']),
      activeStrategy: _nullableString(json['activeStrategy']),
      nodes: _list(json['nodes'])
          .map((item) => RemoteLearningNode.fromJson(_map(item)))
          .toList(growable: false),
      materials: _list(json['materials'])
          .map((item) => RemoteLearningMaterial.fromJson(_map(item)))
          .toList(growable: false),
      summary: summaryJson == null
          ? null
          : RemoteLearningSummary.fromJson(_map(summaryJson)),
    );
  }

  final RemoteLearningSessionInfo session;
  final String? currentNodeId;
  final String? activeStrategy;
  final List<RemoteLearningNode> nodes;
  final List<RemoteLearningMaterial> materials;
  final RemoteLearningSummary? summary;

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

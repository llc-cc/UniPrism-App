part of 'main.dart';

@immutable
class KnowledgeTreeSummary {
  const KnowledgeTreeSummary({required this.id, required this.title});

  final String id;
  final String title;

  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}

@immutable
class KnowledgeSourceRef {
  const KnowledgeSourceRef({
    required this.id,
    required this.title,
    required this.url,
    required this.sourceName,
  });

  factory KnowledgeSourceRef.fromJson(dynamic value) {
    final json = _knowledgeMap(value);
    return KnowledgeSourceRef(
      id: _knowledgeString(json, 'id'),
      title: _knowledgeString(json, 'title'),
      url: _knowledgeString(json, 'url'),
      sourceName: _knowledgeString(json, 'sourceName'),
    );
  }

  final String id;
  final String title;
  final String url;
  final String sourceName;
}

@immutable
class KnowledgeCanonicalSnapshot {
  const KnowledgeCanonicalSnapshot({
    required this.nodeId,
    required this.version,
    required this.title,
    required this.summary,
  });

  factory KnowledgeCanonicalSnapshot.fromJson(dynamic value) {
    final json = _knowledgeMap(value);
    return KnowledgeCanonicalSnapshot(
      nodeId: _knowledgeString(json, 'nodeId'),
      version: _knowledgeString(json, 'version'),
      title: _knowledgeString(json, 'title'),
      summary: _knowledgeString(json, 'summary'),
    );
  }

  final String nodeId;
  final String version;
  final String title;
  final String summary;
}

@immutable
class KnowledgePersonalOverride {
  const KnowledgePersonalOverride({this.title, this.summary, this.note});

  final String? title;
  final String? summary;
  final String? note;
}

@immutable
class KnowledgeTreeSuggestion {
  const KnowledgeTreeSuggestion({
    required this.mode,
    required this.title,
    this.treeId,
  });

  factory KnowledgeTreeSuggestion.fromJson(dynamic value) {
    final json = _knowledgeMap(value);
    return KnowledgeTreeSuggestion(
      mode: _knowledgeString(json, 'mode', fallback: 'new'),
      treeId: _knowledgeNullableString(json['treeId']),
      title: _knowledgeString(json, 'title'),
    );
  }

  final String mode;
  final String? treeId;
  final String title;
}

@immutable
class KnowledgeRelatedEdge {
  const KnowledgeRelatedEdge({
    required this.fromCandidateId,
    required this.toCandidateId,
    required this.relation,
  });

  factory KnowledgeRelatedEdge.fromJson(dynamic value) {
    final json = _knowledgeMap(value);
    return KnowledgeRelatedEdge(
      fromCandidateId: _knowledgeString(json, 'fromCandidateId'),
      toCandidateId: _knowledgeString(json, 'toCandidateId'),
      relation: _knowledgeString(json, 'relation'),
    );
  }

  final String fromCandidateId;
  final String toCandidateId;
  final String relation;
}

@immutable
class KnowledgeNodeCandidate {
  const KnowledgeNodeCandidate({
    required this.candidateId,
    required this.parentCandidateId,
    required this.type,
    required this.title,
    required this.summary,
    required this.selected,
    required this.confidence,
  });

  factory KnowledgeNodeCandidate.fromJson(dynamic value) {
    final json = _knowledgeMap(value);
    return KnowledgeNodeCandidate(
      candidateId: _knowledgeString(json, 'candidateId'),
      parentCandidateId: _knowledgeNullableString(json['parentCandidateId']),
      type: _knowledgeString(json, 'type', fallback: 'concept'),
      title: _knowledgeString(json, 'title'),
      summary: _knowledgeString(json, 'summary'),
      selected: json['selected'] != false,
      confidence: _knowledgeDouble(json['confidence']),
    );
  }

  final String candidateId;
  final String? parentCandidateId;
  final String type;
  final String title;
  final String summary;
  final bool selected;
  final double confidence;

  KnowledgeNodeCandidate copyWith({
    String? title,
    String? summary,
    bool? selected,
  }) {
    return KnowledgeNodeCandidate(
      candidateId: candidateId,
      parentCandidateId: parentCandidateId,
      type: type,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      selected: selected ?? this.selected,
      confidence: confidence,
    );
  }

  KnowledgeNode toConfirmedNode({
    required KnowledgeExtractionBatch batch,
    required String? parentNodeId,
  }) {
    return KnowledgeNode(
      id: 'node-${batch.batchId}-$candidateId',
      parentNodeId: parentNodeId,
      type: type,
      title: title.trim(),
      summary: summary.trim(),
      confidence: confidence,
      confirmedAt: DateTime.now(),
      sourceConversationId: batch.conversationId,
      sourceMessageId: batch.messageId,
      sourceQuestion: batch.question,
      sourceAnswerExcerpt: batch.answerExcerpt,
      sourceRefs: batch.sourceRefs,
      canonical: null,
      personalOverride: const KnowledgePersonalOverride(),
    );
  }
}

@immutable
class KnowledgeExtractionBatch {
  KnowledgeExtractionBatch({
    required this.batchId,
    required this.conversationId,
    required this.messageId,
    required this.question,
    required this.answerExcerpt,
    required this.suggestedTree,
    required List<KnowledgeNodeCandidate> nodes,
    required List<KnowledgeRelatedEdge> relatedEdges,
    required this.traceId,
    required this.model,
    required this.latencyMs,
    List<KnowledgeSourceRef> sourceRefs = const [],
  }) : nodes = List.unmodifiable(nodes),
       relatedEdges = List.unmodifiable(relatedEdges),
       sourceRefs = List.unmodifiable(sourceRefs);

  factory KnowledgeExtractionBatch.fromJson(dynamic value) {
    final json = _knowledgeMap(value);
    return KnowledgeExtractionBatch(
      batchId: _knowledgeString(json, 'batchId'),
      conversationId: _knowledgeString(json, 'conversationId'),
      messageId: _knowledgeString(json, 'messageId'),
      question: _knowledgeString(json, 'question'),
      answerExcerpt: _knowledgeString(json, 'answerExcerpt'),
      suggestedTree: KnowledgeTreeSuggestion.fromJson(json['suggestedTree']),
      nodes: _knowledgeList(
        json['nodes'],
      ).map(KnowledgeNodeCandidate.fromJson).toList(growable: false),
      relatedEdges: _knowledgeList(
        json['relatedEdges'],
      ).map(KnowledgeRelatedEdge.fromJson).toList(growable: false),
      traceId: _knowledgeString(json, 'traceId'),
      model: _knowledgeString(json, 'model'),
      latencyMs: _knowledgeInt(json['latencyMs']),
      sourceRefs: _knowledgeList(
        json['sourceRefs'],
      ).map(KnowledgeSourceRef.fromJson).toList(growable: false),
    );
  }

  final String batchId;
  final String conversationId;
  final String messageId;
  final String question;
  final String answerExcerpt;
  final KnowledgeTreeSuggestion suggestedTree;
  final List<KnowledgeNodeCandidate> nodes;
  final List<KnowledgeRelatedEdge> relatedEdges;
  final String traceId;
  final String model;
  final int latencyMs;
  final List<KnowledgeSourceRef> sourceRefs;

  KnowledgeExtractionBatch copyWith({
    List<KnowledgeNodeCandidate>? nodes,
    List<KnowledgeSourceRef>? sourceRefs,
  }) {
    return KnowledgeExtractionBatch(
      batchId: batchId,
      conversationId: conversationId,
      messageId: messageId,
      question: question,
      answerExcerpt: answerExcerpt,
      suggestedTree: suggestedTree,
      nodes: nodes ?? this.nodes,
      relatedEdges: relatedEdges,
      traceId: traceId,
      model: model,
      latencyMs: latencyMs,
      sourceRefs: sourceRefs ?? this.sourceRefs,
    );
  }
}

@immutable
class KnowledgeNode {
  KnowledgeNode({
    required this.id,
    required this.parentNodeId,
    required this.type,
    required this.title,
    required this.summary,
    required this.confidence,
    required this.confirmedAt,
    required this.sourceConversationId,
    required this.sourceMessageId,
    required this.sourceQuestion,
    required this.sourceAnswerExcerpt,
    required List<KnowledgeSourceRef> sourceRefs,
    required this.canonical,
    required this.personalOverride,
  }) : sourceRefs = List.unmodifiable(sourceRefs);

  final String id;
  final String? parentNodeId;
  final String type;
  final String title;
  final String summary;
  final double confidence;
  final DateTime confirmedAt;
  final String sourceConversationId;
  final String sourceMessageId;
  final String sourceQuestion;
  final String sourceAnswerExcerpt;
  final List<KnowledgeSourceRef> sourceRefs;
  final KnowledgeCanonicalSnapshot? canonical;
  final KnowledgePersonalOverride personalOverride;
}

@immutable
class KnowledgeTreeSnapshot {
  KnowledgeTreeSnapshot({
    required this.id,
    required this.title,
    required List<KnowledgeNode> nodes,
    required this.updatedAt,
  }) : nodes = List.unmodifiable(nodes);

  factory KnowledgeTreeSnapshot.empty({
    required String id,
    required String title,
  }) {
    return KnowledgeTreeSnapshot(
      id: id,
      title: title,
      nodes: const [],
      updatedAt: DateTime.now(),
    );
  }

  final String id;
  final String title;
  final List<KnowledgeNode> nodes;
  final DateTime updatedAt;

  List<KnowledgeNode> get rootNodes =>
      List.unmodifiable(nodes.where((node) => node.parentNodeId == null));

  KnowledgeTreeSnapshot merge(
    List<KnowledgeNode> additions, {
    required DateTime updatedAt,
  }) {
    final merged = <String, KnowledgeNode>{
      for (final node in nodes) node.id: node,
      for (final node in additions) node.id: node,
    };
    return KnowledgeTreeSnapshot(
      id: id,
      title: title,
      nodes: merged.values.toList(growable: false),
      updatedAt: updatedAt,
    );
  }
}

@immutable
class KnowledgeForestSnapshot {
  KnowledgeForestSnapshot(List<KnowledgeTreeSnapshot> trees)
    : trees = List.unmodifiable(trees);

  final List<KnowledgeTreeSnapshot> trees;
}

/// 当前进程内的个人知识森林；测试版重启后清空，不写设备持久化。
class KnowledgeForestStore extends ChangeNotifier {
  KnowledgeForestStore();

  final Map<String, KnowledgeTreeSnapshot> _trees = {};
  final Set<String> _confirmedBatchIds = {};
  final Map<String, String> _batchTreeIds = {};

  List<KnowledgeTreeSnapshot> get trees {
    final sorted = _trees.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List.unmodifiable(sorted);
  }

  KnowledgeTreeSnapshot? treeById(String id) => _trees[id];

  KnowledgeTreeSnapshot confirmBatch(
    KnowledgeExtractionBatch batch, {
    required String targetTreeTitle,
    String? targetTreeId,
  }) {
    final confirmedTreeId = _batchTreeIds[batch.batchId];
    if (_confirmedBatchIds.contains(batch.batchId) && confirmedTreeId != null) {
      return _trees[confirmedTreeId]!;
    }

    final treeId = targetTreeId ?? 'tree-${batch.batchId}';
    final normalizedTitle = targetTreeTitle.trim().isNotEmpty
        ? targetTreeTitle.trim()
        : batch.suggestedTree.title.trim();
    final current =
        _trees[treeId] ??
        KnowledgeTreeSnapshot.empty(id: treeId, title: normalizedTitle);
    final selectedIds = batch.nodes
        .where((candidate) => candidate.selected)
        .map((candidate) => candidate.candidateId)
        .toSet();

    // 候选父节点被取消时，子节点提升为根，避免产生悬空引用。
    final confirmedNodes = batch.nodes
        .where((candidate) => candidate.selected)
        .map(
          (candidate) => candidate.toConfirmedNode(
            batch: batch,
            parentNodeId: selectedIds.contains(candidate.parentCandidateId)
                ? 'node-${batch.batchId}-${candidate.parentCandidateId}'
                : null,
          ),
        )
        .toList(growable: false);
    final updated = current.merge(confirmedNodes, updatedAt: DateTime.now());
    _trees[treeId] = updated;
    _confirmedBatchIds.add(batch.batchId);
    _batchTreeIds[batch.batchId] = treeId;
    notifyListeners();
    return updated;
  }

  void clearForTest() {
    _trees.clear();
    _confirmedBatchIds.clear();
    _batchTreeIds.clear();
    notifyListeners();
  }
}

Map<String, dynamic> _knowledgeMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return const <String, dynamic>{};
}

List<dynamic> _knowledgeList(dynamic value) => value is List ? value : const [];

String _knowledgeString(
  Map<String, dynamic> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key]?.toString().trim() ?? '';
  return value.isEmpty ? fallback : value;
}

String? _knowledgeNullableString(dynamic value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

double _knowledgeDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _knowledgeInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

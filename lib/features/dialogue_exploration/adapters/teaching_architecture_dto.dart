final class RemoteTeachingArchitectureSnapshot {
  RemoteTeachingArchitectureSnapshot({
    required this.chapterId,
    required this.atomId,
    required this.activeBoardId,
    required List<RemoteTeachingBoardSnapshot> boards,
    required List<RemoteTeachingBranchRecord> branches,
  }) : boards = List.unmodifiable(boards),
       branches = List.unmodifiable(branches);

  static RemoteTeachingArchitectureSnapshot? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final boardsJson = json['boards'];
    if (boardsJson is! List) return null;
    return RemoteTeachingArchitectureSnapshot(
      chapterId: _nullableString(json['chapterId']),
      atomId: _nullableString(json['atomId']),
      activeBoardId: _nullableString(json['activeBoardId']),
      boards: boardsJson
          .map((item) => RemoteTeachingBoardSnapshot.fromJson(_map(item)))
          .toList(growable: false),
      branches: _list(json['branches'])
          .map((item) => RemoteTeachingBranchRecord.fromJson(_map(item)))
          .toList(growable: false),
    );
  }

  final String? chapterId;
  final String? atomId;
  final String? activeBoardId;
  final List<RemoteTeachingBoardSnapshot> boards;
  final List<RemoteTeachingBranchRecord> branches;

  RemoteTeachingBoardSnapshot? boardById(String? id) {
    if (id == null) return null;
    for (final board in boards) {
      if (board.id == id) return board;
    }
    return null;
  }
}

final class RemoteTeachingBoardSnapshot {
  RemoteTeachingBoardSnapshot({
    required this.id,
    required this.kind,
    required this.label,
    required this.goalId,
    required this.goalIndex,
    required this.beatKind,
    required List<String> knowledgeNodeIds,
    required List<String> knowledgeNodeNames,
    required List<String> nodeIds,
    required List<String> materialUsageIds,
    required List<String> practiceAttemptIds,
    required this.practiceId,
    required this.branchId,
    required this.parentBoardId,
    required this.isActive,
    required this.openedAt,
  }) : knowledgeNodeIds = List.unmodifiable(knowledgeNodeIds),
       knowledgeNodeNames = List.unmodifiable(knowledgeNodeNames),
       nodeIds = List.unmodifiable(nodeIds),
       materialUsageIds = List.unmodifiable(materialUsageIds),
       practiceAttemptIds = List.unmodifiable(practiceAttemptIds);

  factory RemoteTeachingBoardSnapshot.fromJson(Map<String, dynamic> json) {
    return RemoteTeachingBoardSnapshot(
      id: _string(json['id']),
      kind: _string(json['kind']),
      label: _string(json['label']),
      goalId: _nullableString(json['goalId']),
      goalIndex: _nullableInt(json['goalIndex']),
      beatKind: _nullableString(json['beatKind']),
      knowledgeNodeIds: _strings(json['knowledgeNodeIds']),
      knowledgeNodeNames: _strings(json['knowledgeNodeNames']),
      nodeIds: _strings(json['nodeIds']),
      materialUsageIds: _strings(json['materialUsageIds']),
      practiceAttemptIds: _strings(json['practiceAttemptIds']),
      practiceId: _nullableString(json['practiceId']),
      branchId: _nullableString(json['branchId']),
      parentBoardId: _nullableString(json['parentBoardId']),
      isActive: json['isActive'] == true,
      openedAt: _string(json['openedAt']),
    );
  }

  final String id;
  final String kind;
  final String label;
  final String? goalId;
  final int? goalIndex;
  final String? beatKind;
  final List<String> knowledgeNodeIds;
  final List<String> knowledgeNodeNames;
  final List<String> nodeIds;
  final List<String> materialUsageIds;
  final List<String> practiceAttemptIds;
  final String? practiceId;
  final String? branchId;
  final String? parentBoardId;
  final bool isActive;
  final String openedAt;
}

final class RemoteTeachingBranchRecord {
  RemoteTeachingBranchRecord({
    required this.id,
    required this.goalId,
    required this.goalIndex,
    required this.branchKind,
    required List<String> targetKnowledgeNodeIds,
    required this.triggerPracticeAttemptId,
    required this.triggerStudentText,
    required this.feedback,
    required this.repairFocus,
    required this.practiceVerdict,
    required this.openedAt,
    required this.closedAt,
    required this.result,
    required this.boardId,
  }) : targetKnowledgeNodeIds = List.unmodifiable(targetKnowledgeNodeIds);

  factory RemoteTeachingBranchRecord.fromJson(Map<String, dynamic> json) {
    return RemoteTeachingBranchRecord(
      id: _string(json['id']),
      goalId: _string(json['goalId']),
      goalIndex: _int(json['goalIndex']),
      branchKind: _string(json['branchKind']),
      targetKnowledgeNodeIds: _strings(json['targetKnowledgeNodeIds']),
      triggerPracticeAttemptId: _nullableString(json['triggerPracticeAttemptId']),
      triggerStudentText: _nullableString(json['triggerStudentText']),
      feedback: _string(json['feedback']),
      repairFocus: _nullableString(json['repairFocus']),
      practiceVerdict: _string(json['practiceVerdict']),
      openedAt: _string(json['openedAt']),
      closedAt: _nullableString(json['closedAt']),
      result: _nullableString(json['result']),
      boardId: _string(json['boardId']),
    );
  }

  final String id;
  final String goalId;
  final int goalIndex;
  final String branchKind;
  final List<String> targetKnowledgeNodeIds;
  final String? triggerPracticeAttemptId;
  final String? triggerStudentText;
  final String feedback;
  final String? repairFocus;
  final String practiceVerdict;
  final String openedAt;
  final String? closedAt;
  final String? result;
  final String boardId;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : Map<String, dynamic>.from(value as Map);

List<dynamic> _list(Object? value) =>
    value is List ? value : const [];

String _string(Object? value) => value?.toString() ?? '';

String? _nullableString(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return text;
}

int _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

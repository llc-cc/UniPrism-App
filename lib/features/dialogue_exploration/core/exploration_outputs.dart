import 'exploration_tree.dart';

/// 保存的思维过程图；首版进程内存储，正式版可直接映射到事件后端。
final class ExplorationTraceRecord {
  const ExplorationTraceRecord({
    required this.id,
    required this.scenarioId,
    required this.tree,
    required this.reflection,
    required this.savedAt,
  });

  final String id;
  final String scenarioId;
  final ExplorationTree tree;
  final String reflection;
  final DateTime savedAt;
}

/// 由思维树节点派生、供未来 M2 消费的稳定记忆候选引用。
final class ExplorationMemoryCandidate {
  const ExplorationMemoryCandidate({
    required this.id,
    required this.scenarioId,
    required this.nodeId,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String scenarioId;
  final String nodeId;
  final String text;
  final DateTime createdAt;
}

/// 将思维过程图转换为版本化、可复制的 JSON 数据。
abstract final class ExplorationTraceExporter {
  static Map<String, Object?> toVersionedJson(ExplorationTraceRecord record) {
    return <String, Object?>{
      'schemaVersion': 1,
      'traceId': record.id,
      'scenarioId': record.scenarioId,
      'reflection': record.reflection,
      'savedAt': record.savedAt.toUtc().toIso8601String(),
      'activeLeafId': record.tree.activeLeafId,
      'nodes': record.tree.nodes
          .map(
            (node) => <String, Object?>{
              'id': node.id,
              'parentId': node.parentId,
              'kind': node.kind.name,
              'status': node.status.name,
              'text': node.text,
              'materialIds': node.materialIds,
              'isSideBranch': node.isSideBranch,
              'backtrackTargetNodeId': node.backtrackTargetNodeId,
              'createdAt': node.createdAt.toUtc().toIso8601String(),
              'strategyVersion': node.strategyVersion,
            },
          )
          .toList(growable: false),
    };
  }
}

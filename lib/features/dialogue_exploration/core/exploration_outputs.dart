import 'exploration_tree.dart';
import '../teaching/teaching_strategy_engine.dart';

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

/// 从已发生的对话证据生成学习产出；没有支线或错误时明确说明证据不足。
final class ExplorationSessionSummary {
  const ExplorationSessionSummary({
    required this.thinkingTree,
    required this.understandingDepth,
    required this.errorModel,
    required this.interestDirection,
    required this.reviewCard,
  });

  factory ExplorationSessionSummary.fromEvidence({
    required ExplorationTree tree,
    required List<TeachingStrategyDecision> strategyHistory,
    required String reflection,
  }) {
    final errorTurns = strategyHistory
        .where((item) => item.mode == TeachingDialogueMode.errorTracing)
        .length;
    final hasSelfExplanation = strategyHistory.any(
      (item) => item.mode == TeachingDialogueMode.selfExplanation,
    );
    final sideBranches = tree.nodes
        .where((node) => node.isSideBranch)
        .map((node) => node.text)
        .take(2)
        .toList(growable: false);
    return ExplorationSessionSummary(
      thinkingTree: '${tree.nodes.length} 个节点 · ${tree.sideBranchCount} 条支线',
      understandingDepth: hasSelfExplanation && reflection.trim().isNotEmpty
          ? '已完成自我解释，并留下可复查的理解证据'
          : '尚未完成自我解释，理解深度证据不足',
      errorModel: errorTurns == 0
          ? '本次没有确认的错误证据'
          : '追踪了 $errorTurns 次错误思路，并保留原路径',
      interestDirection: sideBranches.isEmpty
          ? '本次没有足够支线证据，暂不推断兴趣方向'
          : '主动探索支线：${sideBranches.join('；')}',
      reviewCard: reflection.trim(),
    );
  }

  final String thinkingTree;
  final String understandingDepth;
  final String errorModel;
  final String interestDirection;
  final String reviewCard;
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
              'strategyMode': node.strategyMode,
              'strategyGoal': node.strategyGoal,
              'strategyReason': node.strategyReason,
            },
          )
          .toList(growable: false),
    };
  }
}

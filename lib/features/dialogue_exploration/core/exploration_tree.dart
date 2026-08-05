import 'exploration_models.dart';

/// 思维树增长限制的稳定分类，页面可据此给出不同收口提示。
enum ExplorationLimitKind { nodeCount, pathDepth, directBranches }

/// 达到树增长上限时抛出的领域异常；原树保持不变。
final class ExplorationLimitException implements Exception {
  const ExplorationLimitException(this.kind, this.message);

  final ExplorationLimitKind kind;
  final String message;

  @override
  String toString() => message;
}

/// 对话与练习共用的不可变思维树，集中维护父子引用和回退约束。
final class ExplorationTree {
  ExplorationTree._({
    required this.id,
    required List<ExplorationNode> nodes,
    required this.activeLeafId,
    required Set<String> collapsedNodeIds,
  }) : nodes = List.unmodifiable(nodes),
       collapsedNodeIds = Set.unmodifiable(collapsedNodeIds);

  static const int maxNodes = 40;
  // 五个教学策略来回至少产生十层节点，保留两层用于收口或错误回退。
  static const int maxDepth = 12;
  static const int maxDirectBranches = 8;

  factory ExplorationTree.seed({
    required String id,
    required ExplorationNode root,
  }) {
    if (root.parentId != null) {
      throw ArgumentError.value(root.parentId, 'root.parentId', '根节点不能有父节点');
    }
    return ExplorationTree._(
      id: id,
      nodes: [root],
      activeLeafId: root.id,
      collapsedNodeIds: const {},
    );
  }

  final String id;
  final List<ExplorationNode> nodes;
  final String activeLeafId;
  final Set<String> collapsedNodeIds;

  ExplorationNode? nodeById(String nodeId) {
    for (final node in nodes) {
      if (node.id == nodeId) return node;
    }
    return null;
  }

  ExplorationNode? get activeLeaf => nodeById(activeLeafId);

  List<ExplorationNode> childrenOf(String nodeId) {
    return List.unmodifiable(nodes.where((node) => node.parentId == nodeId));
  }

  int get sideBranchCount => nodes.where((node) => node.isSideBranch).length;

  int get maxPathDepth {
    var result = 0;
    for (final node in nodes) {
      final depth = _depthOf(node.id);
      if (depth > result) result = depth;
    }
    return result;
  }

  ExplorationTree append(
    ExplorationNode node, {
    bool enforceDepthLimit = true,
  }) {
    if (node.parentId != activeLeafId) {
      throw ArgumentError.value(
        node.parentId,
        'node.parentId',
        '普通继续必须追加到当前活跃叶节点',
      );
    }
    return _insert(
      node,
      isSideBranch: false,
      enforceDepthLimit: enforceDepthLimit,
    );
  }

  ExplorationTree branchFrom({
    required String parentNodeId,
    required ExplorationNode node,
  }) {
    if (node.parentId != parentNodeId) {
      throw ArgumentError.value(
        node.parentId,
        'node.parentId',
        '分支节点的 parentId 必须与指定历史节点一致',
      );
    }
    return _insert(node, isSideBranch: true, enforceDepthLimit: true);
  }

  ExplorationTree updateStatus(String nodeId, ExplorationNodeStatus status) {
    final current = nodeById(nodeId);
    if (current == null) {
      throw ArgumentError.value(nodeId, 'nodeId', '节点不存在');
    }
    final updated = nodes
        .map((node) => node.id == nodeId ? node.withStatus(status) : node)
        .toList(growable: false);
    return _copy(nodes: updated);
  }

  ExplorationTree backtrack({
    required String fromNodeId,
    required String targetNodeId,
    required String backtrackNodeId,
    required String reason,
    required DateTime createdAt,
  }) {
    final from = nodeById(fromNodeId);
    final target = nodeById(targetNodeId);
    if (from == null || target == null) {
      throw ArgumentError('回退起点和目标都必须存在');
    }
    if (fromNodeId != activeLeafId) {
      throw ArgumentError.value(fromNodeId, 'fromNodeId', '只能从当前活跃叶回退');
    }
    if (!_isAncestor(ancestorId: targetNodeId, nodeId: fromNodeId)) {
      throw ArgumentError.value(targetNodeId, 'targetNodeId', '回退目标必须是当前路径的祖先');
    }
    // 回退是新增的思维证据，不能覆盖导致矛盾的节点，否则会丢失学生如何发现错误。
    final backtrackNode = ExplorationNode(
      id: backtrackNodeId,
      parentId: fromNodeId,
      kind: ExplorationNodeKind.backtrack,
      status: ExplorationNodeStatus.backtracked,
      text: reason,
      materialIds: const [],
      isSideBranch: false,
      backtrackTargetNodeId: targetNodeId,
      createdAt: createdAt,
      strategyVersion: from.strategyVersion,
    );
    return _insert(backtrackNode, isSideBranch: false, enforceDepthLimit: true);
  }

  ExplorationTree toggleCollapsed(String nodeId) {
    if (nodeById(nodeId) == null) {
      throw ArgumentError.value(nodeId, 'nodeId', '节点不存在');
    }
    final next = Set<String>.of(collapsedNodeIds);
    if (!next.remove(nodeId)) next.add(nodeId);
    return _copy(collapsedNodeIds: next);
  }

  ExplorationTree _insert(
    ExplorationNode node, {
    required bool isSideBranch,
    required bool enforceDepthLimit,
  }) {
    if (nodeById(node.id) != null) {
      throw ArgumentError.value(node.id, 'node.id', '节点 ID 必须唯一');
    }
    final parentId = node.parentId;
    if (parentId == null || nodeById(parentId) == null) {
      throw ArgumentError.value(parentId, 'node.parentId', '父节点不存在');
    }
    if (nodes.length >= maxNodes) {
      throw const ExplorationLimitException(
        ExplorationLimitKind.nodeCount,
        '思维树已达到 40 个节点，请先收口或导出。',
      );
    }
    if (childrenOf(parentId).length >= maxDirectBranches) {
      throw const ExplorationLimitException(
        ExplorationLimitKind.directBranches,
        '当前节点已达到 8 个直接分支。',
      );
    }
    final nextDepth = _depthOf(parentId) + 1;
    if (enforceDepthLimit && nextDepth > maxDepth) {
      throw ExplorationLimitException(
        ExplorationLimitKind.pathDepth,
        '当前路径已达到 $maxDepth 层，请回到已有节点继续。',
      );
    }
    final storedNode = isSideBranch ? node.asSideBranch() : node;
    return _copy(nodes: [...nodes, storedNode], activeLeafId: storedNode.id);
  }

  int _depthOf(String nodeId) {
    var depth = 0;
    ExplorationNode? current = nodeById(nodeId);
    final visited = <String>{};
    while (current != null) {
      if (!visited.add(current.id)) {
        throw StateError('思维树出现父子环：${current.id}');
      }
      depth += 1;
      current = current.parentId == null ? null : nodeById(current.parentId!);
    }
    return depth;
  }

  bool _isAncestor({required String ancestorId, required String nodeId}) {
    ExplorationNode? current = nodeById(nodeId);
    while (current != null) {
      if (current.id == ancestorId) return true;
      current = current.parentId == null ? null : nodeById(current.parentId!);
    }
    return false;
  }

  ExplorationTree _copy({
    List<ExplorationNode>? nodes,
    String? activeLeafId,
    Set<String>? collapsedNodeIds,
  }) {
    return ExplorationTree._(
      id: id,
      nodes: nodes ?? this.nodes,
      activeLeafId: activeLeafId ?? this.activeLeafId,
      collapsedNodeIds: collapsedNodeIds ?? this.collapsedNodeIds,
    );
  }
}

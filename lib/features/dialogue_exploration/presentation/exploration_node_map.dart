import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../adapters/remote_exploration_dto.dart';

const _mapBrand = Color(0xFF6B23FF);
const _mapInk = Color(0xFF27222D);
const _mapMuted = Color(0xFF6F6977);

/// 1.2 的探索地图：把已保存的概念节点还原为可点击的空间关系，
/// 而不是按时间堆叠聊天记录。画布只消费会话快照，不写入或推断掌握度。
final class ExplorationNodeMap extends StatelessWidget {
  const ExplorationNodeMap({
    super.key,
    required this.snapshot,
    required this.readOnly,
    required this.inspectedNodeId,
    required this.onNodeTap,
    required this.onContinue,
    required this.onBranch,
    required this.onClose,
  });

  final RemoteLearningSessionSnapshot snapshot;
  final bool readOnly;
  final String? inspectedNodeId;
  final ValueChanged<String> onNodeTap;
  final VoidCallback onContinue;
  final VoidCallback onBranch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final focusedId = inspectedNodeId ?? snapshot.currentNodeId;
    final focusedNode =
        snapshot.nodeById(focusedId) ??
        (snapshot.nodes.isEmpty ? null : snapshot.nodes.last);
    final concepts = snapshot.displayConceptNodes;
    final focusedConcept = _conceptForEvidence(concepts, focusedNode?.id);
    return Material(
      color: const Color(0xFFF9F7FC),
      child: SafeArea(
        child: Column(
          children: [
            _MapHeader(onClose: onClose),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 760;
                  final detail = _FocusedNodeCard(
                    node: focusedNode,
                    concept: focusedConcept,
                    readOnly: readOnly,
                    onContinue: onContinue,
                    onBranch: onBranch,
                  );
                  final canvas = KeyedSubtree(
                    key: const ValueKey('personal-thinking-tree'),
                    child: _ExplorationNodeCanvas(
                      concepts: concepts,
                      selectedEvidenceNodeId: focusedNode?.id,
                      onNodeTap: onNodeTap,
                    ),
                  );
                  if (isCompact) {
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                          child: detail,
                        ),
                        Expanded(child: canvas),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(
                        width: math.min(470, constraints.maxWidth * .42),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: detail,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: canvas),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  RemoteLearningConceptNode? _conceptForEvidence(
    List<RemoteLearningConceptNode> concepts,
    String? evidenceNodeId,
  ) {
    for (final concept in concepts) {
      if (concept.evidenceNodeId == evidenceNodeId) return concept;
    }
    return null;
  }
}

final class _MapHeader extends StatelessWidget {
  const _MapHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 12, 14),
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, color: _mapBrand),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的探索地图',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 2),
                Text(
                  '拖动画布查看关系；点击节点即可切换当前探索位置。',
                  style: TextStyle(fontSize: 12, color: _mapMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭探索地图',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

final class _FocusedNodeCard extends StatelessWidget {
  const _FocusedNodeCard({
    required this.node,
    required this.concept,
    required this.readOnly,
    required this.onContinue,
    required this.onBranch,
  });

  final RemoteLearningNode? node;
  final RemoteLearningConceptNode? concept;
  final bool readOnly;
  final VoidCallback onContinue;
  final VoidCallback onBranch;

  @override
  Widget build(BuildContext context) {
    final focusedNode = node;
    if (focusedNode == null) {
      return const _EmptyMapState();
    }
    return Container(
      key: const ValueKey('exploration-node-focus-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF25222A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF4A4456)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x23000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '当前探索节点',
            style: TextStyle(
              color: Color(0xFFDCD5E8),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            concept?.label ?? focusedNode.mapLabel ?? focusedNode.question,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1.22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            focusedNode.question,
            style: const TextStyle(color: Color(0xFFF1EDF5), height: 1.5),
          ),
          if (focusedNode.answer.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'AI 给出的线索',
              style: TextStyle(
                color: Color(0xFFBEB3CF),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              focusedNode.answer,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, height: 1.5),
            ),
          ],
          if (focusedNode.followUpQuestion.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF342D40),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                focusedNode.followUpQuestion,
                style: const TextStyle(
                  color: Color(0xFFDCD0FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (!readOnly)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 18,
                  ),
                  label: const Text('从这里继续问'),
                ),
                OutlinedButton.icon(
                  onPressed: onBranch,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.call_split_rounded, size: 18),
                  label: const Text('从这里开分支'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

final class _EmptyMapState extends StatelessWidget {
  const _EmptyMapState();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('先提出第一个问题，探索地图会从这里长出来。'));
}

/// 画布按父子关系布局而非按消息时间排列。节点数量增加时可缩放、平移，
/// 以避免把预习中的长对话压缩成无法阅读的侧栏列表。
final class _ExplorationNodeCanvas extends StatelessWidget {
  const _ExplorationNodeCanvas({
    required this.concepts,
    required this.selectedEvidenceNodeId,
    required this.onNodeTap,
  });

  final List<RemoteLearningConceptNode> concepts;
  final String? selectedEvidenceNodeId;
  final ValueChanged<String> onNodeTap;

  @override
  Widget build(BuildContext context) {
    final layout = _NodeGraphLayout.build(concepts);
    if (concepts.isEmpty) return const _EmptyMapState();
    return Container(
      color: const Color(0xFFF5F1FA),
      child: InteractiveViewer(
        key: const ValueKey('exploration-node-canvas'),
        constrained: false,
        minScale: .55,
        maxScale: 1.8,
        boundaryMargin: const EdgeInsets.all(120),
        child: SizedBox(
          width: layout.width,
          height: layout.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _NodeLinkPainter(
                    concepts: concepts,
                    positions: layout.positions,
                    selectedEvidenceNodeId: selectedEvidenceNodeId,
                  ),
                ),
              ),
              for (final concept in concepts)
                _ConceptGraphNode(
                  concept: concept,
                  position: layout.positions[concept.id]!,
                  selected: concept.evidenceNodeId == selectedEvidenceNodeId,
                  current: concept.evidenceNodeId == selectedEvidenceNodeId,
                  onTap: () => onNodeTap(concept.evidenceNodeId),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ConceptGraphNode extends StatelessWidget {
  const _ConceptGraphNode({
    required this.concept,
    required this.position,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final RemoteLearningConceptNode concept;
  final Offset position;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = concept.status == 'CONFLICTED'
        ? const Color(0xFFFFEEEE)
        : selected
        ? const Color(0xFFF0E8FF)
        : Colors.white;
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: _NodeGraphLayout.nodeWidth,
      child: Semantics(
        button: true,
        selected: selected,
        label: '探索节点：${concept.label}',
        child: InkWell(
          key: ValueKey('exploration-node-${concept.evidenceNodeId}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? _mapBrand : const Color(0xFFD8D1E0),
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x336B23FF),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      concept.relation == 'BRANCH'
                          ? Icons.call_split_rounded
                          : Icons.circle,
                      color: selected ? _mapBrand : const Color(0xFFB1A8BD),
                      size: concept.relation == 'BRANCH' ? 16 : 10,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _nodeStatus(concept.status, current),
                        style: const TextStyle(fontSize: 11, color: _mapMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  concept.label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _mapInk,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _nodeStatus(String status, bool current) {
    if (current) return '正在查看';
    return switch (status) {
      'CONFLICTED' => '待继续探索',
      'CORRECTED' => '已修正',
      'FORMING' => '形成中',
      _ => '已探索',
    };
  }
}

final class _NodeGraphLayout {
  const _NodeGraphLayout({
    required this.positions,
    required this.width,
    required this.height,
  });

  static const nodeWidth = 190.0;
  static const nodeHeight = 94.0;
  static const columnGap = 104.0;
  static const rowGap = 34.0;

  final Map<String, Offset> positions;
  final double width;
  final double height;

  static _NodeGraphLayout build(List<RemoteLearningConceptNode> concepts) {
    final byId = {for (final item in concepts) item.id: item};
    final childrenByParent = <String?, List<RemoteLearningConceptNode>>{};
    for (final item in concepts) {
      final parent = byId.containsKey(item.parentId) ? item.parentId : null;
      (childrenByParent[parent] ??= []).add(item);
    }
    final depthById = <String, int>{};
    final visited = <String>{};
    void assignDepth(RemoteLearningConceptNode item, int depth) {
      if (!visited.add(item.id)) return;
      depthById[item.id] = depth;
      for (final child in childrenByParent[item.id] ?? const []) {
        assignDepth(child, depth + 1);
      }
    }

    for (final root in childrenByParent[null] ?? const []) {
      assignDepth(root, 0);
    }
    for (final item in concepts) {
      assignDepth(item, depthById[item.id] ?? 0);
    }

    final columns = <int, List<RemoteLearningConceptNode>>{};
    for (final item in concepts) {
      (columns[depthById[item.id] ?? 0] ??= []).add(item);
    }
    final maxDepth = columns.keys.fold(0, math.max);
    final maxRows = columns.values.fold(
      1,
      (value, items) => math.max(value, items.length),
    );
    final positions = <String, Offset>{};
    for (final entry in columns.entries) {
      final topOffset =
          (maxRows - entry.value.length) * (nodeHeight + rowGap) / 2;
      for (var index = 0; index < entry.value.length; index++) {
        positions[entry.value[index].id] = Offset(
          52 + entry.key * (nodeWidth + columnGap),
          54 + topOffset + index * (nodeHeight + rowGap),
        );
      }
    }
    return _NodeGraphLayout(
      positions: positions,
      width: math.max(760, 104 + (maxDepth + 1) * (nodeWidth + columnGap)),
      height: math.max(440, 108 + maxRows * (nodeHeight + rowGap)),
    );
  }
}

final class _NodeLinkPainter extends CustomPainter {
  const _NodeLinkPainter({
    required this.concepts,
    required this.positions,
    required this.selectedEvidenceNodeId,
  });

  final List<RemoteLearningConceptNode> concepts;
  final Map<String, Offset> positions;
  final String? selectedEvidenceNodeId;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final item in concepts) item.id: item};
    for (final child in concepts) {
      final parentId = child.parentId;
      final parent = parentId == null ? null : byId[parentId];
      if (parent == null) continue;
      final startPosition = positions[parent.id];
      final endPosition = positions[child.id];
      if (startPosition == null || endPosition == null) continue;
      final highlighted =
          child.evidenceNodeId == selectedEvidenceNodeId ||
          parent.evidenceNodeId == selectedEvidenceNodeId;
      final paint = Paint()
        ..color = highlighted ? _mapBrand : const Color(0xFFCFC6DB)
        ..strokeWidth = highlighted ? 2.4 : 1.5
        ..style = PaintingStyle.stroke;
      final start = Offset(
        startPosition.dx + _NodeGraphLayout.nodeWidth,
        startPosition.dy + _NodeGraphLayout.nodeHeight / 2,
      );
      final end = Offset(
        endPosition.dx,
        endPosition.dy + _NodeGraphLayout.nodeHeight / 2,
      );
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx + 48, start.dy, end.dx - 48, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NodeLinkPainter oldDelegate) =>
      oldDelegate.concepts != concepts ||
      oldDelegate.positions != positions ||
      oldDelegate.selectedEvidenceNodeId != selectedEvidenceNodeId;
}

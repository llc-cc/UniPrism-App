import 'package:flutter/material.dart';

import '../core/exploration_models.dart';
import '../core/exploration_tree.dart';

/// 首版思维树面板，优先清楚展示分支、矛盾和回退，后续可替换图布局。
final class ExplorationTreePanel extends StatefulWidget {
  const ExplorationTreePanel({super.key, required this.tree});

  final ExplorationTree tree;

  @override
  State<ExplorationTreePanel> createState() => _ExplorationTreePanelState();
}

final class _ExplorationTreePanelState extends State<ExplorationTreePanel> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final roots = widget.tree.nodes.where((node) => node.parentId == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: roots.map((node) => _buildNode(node, 0)).toList(growable: false),
    );
  }

  Widget _buildNode(ExplorationNode node, int depth) {
    final children = widget.tree.childrenOf(node.id);
    final isCollapsed = _collapsed.contains(node.id);
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: ValueKey('tree-node-${node.id}'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _nodeColor(node.status),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2DDE8)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (children.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      if (!_collapsed.remove(node.id)) _collapsed.add(node.id);
                    }),
                    icon: Icon(
                      isCollapsed
                          ? Icons.chevron_right_rounded
                          : Icons.expand_more_rounded,
                    ),
                  )
                else
                  const SizedBox(width: 40),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _StatusPill(label: _statusLabel(node.status)),
                          if (node.isSideBranch)
                            const _StatusPill(label: '支线'),
                          if (node.backtrackTargetNodeId != null)
                            const _StatusPill(label: '回退'),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(node.text, maxLines: 5, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isCollapsed)
            ...children.map((child) => _buildNode(child, depth + 1)),
        ],
      ),
    );
  }

  static String _statusLabel(ExplorationNodeStatus status) {
    return switch (status) {
      ExplorationNodeStatus.exploring => '探索中',
      ExplorationNodeStatus.validated => '已验证',
      ExplorationNodeStatus.contradicted => '不成立',
      ExplorationNodeStatus.abandoned => '已放弃',
      ExplorationNodeStatus.backtracked => '回退',
      ExplorationNodeStatus.completed => '已完成',
    };
  }

  static Color _nodeColor(ExplorationNodeStatus status) {
    return switch (status) {
      ExplorationNodeStatus.contradicted => const Color(0xFFFFF0F0),
      ExplorationNodeStatus.backtracked => const Color(0xFFFFF7E8),
      ExplorationNodeStatus.completed => const Color(0xFFEDF9F2),
      _ => Colors.white,
    };
  }
}

final class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFEAF7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

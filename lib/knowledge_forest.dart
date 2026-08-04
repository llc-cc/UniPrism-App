part of 'main.dart';

enum KnowledgeExtractionUiState {
  idle,
  extracting,
  previewing,
  confirming,
  confirmed,
}

class KnowledgeExtractionPreviewPage extends StatefulWidget {
  const KnowledgeExtractionPreviewPage({
    super.key,
    required this.batch,
    required this.store,
  });

  final KnowledgeExtractionBatch batch;
  final KnowledgeForestStore store;

  @override
  State<KnowledgeExtractionPreviewPage> createState() =>
      _KnowledgeExtractionPreviewPageState();
}

class _KnowledgeExtractionPreviewPageState
    extends State<KnowledgeExtractionPreviewPage> {
  late List<KnowledgeNodeCandidate> _candidates;
  late final TextEditingController _treeTitleController;
  late String _targetChoice;
  KnowledgeExtractionUiState _state = KnowledgeExtractionUiState.previewing;

  bool get _isConfirming => _state == KnowledgeExtractionUiState.confirming;

  @override
  void initState() {
    super.initState();
    _candidates = widget.batch.nodes.toList(growable: false);
    final suggestedTreeId = widget.batch.suggestedTree.treeId;
    final canUseSuggestion =
        suggestedTreeId != null &&
        widget.store.treeById(suggestedTreeId) != null;
    _targetChoice = canUseSuggestion ? suggestedTreeId : _newTreeChoice;
    _treeTitleController = TextEditingController(
      text: canUseSuggestion
          ? widget.store.treeById(suggestedTreeId)!.title
          : widget.batch.suggestedTree.title,
    );
  }

  @override
  void dispose() {
    _treeTitleController.dispose();
    super.dispose();
  }

  void _replaceCandidate(
    int index, {
    String? title,
    String? summary,
    bool? selected,
  }) {
    final updated = _candidates[index].copyWith(
      title: title,
      summary: summary,
      selected: selected,
    );
    setState(() {
      _candidates = [..._candidates]..[index] = updated;
    });
  }

  Future<void> _confirm() async {
    if (_isConfirming) return;
    final title = _treeTitleController.text.trim();
    if (title.isEmpty) {
      _showMessage('请输入目标知识树名称。');
      return;
    }
    if (!_candidates.any((candidate) => candidate.selected)) {
      _showMessage('至少选择一个知识节点。');
      return;
    }

    setState(() => _state = KnowledgeExtractionUiState.confirming);
    final confirmed = widget.store.confirmBatch(
      widget.batch.copyWith(nodes: _candidates),
      targetTreeId: _targetChoice == _newTreeChoice ? null : _targetChoice,
      targetTreeTitle: title,
    );
    if (!mounted) return;
    setState(() => _state = KnowledgeExtractionUiState.confirmed);
    await Navigator.of(context).maybePop(confirmed);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('审核知识节点'),
        leading: IconButton(
          tooltip: '取消',
          onPressed: _isConfirming
              ? null
              : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _buildReviewNotice(theme),
                  const SizedBox(height: 16),
                  _buildTreeTarget(theme),
                  const SizedBox(height: 20),
                  Text(
                    '候选节点（${_candidates.where((item) => item.selected).length}/${_candidates.length}）',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var index = 0; index < _candidates.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildCandidate(index, theme),
                    ),
                ],
              ),
            ),
            _buildBottomAction(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewNotice(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF3EEFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6B23FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'AI 只生成候选内容。请勾选、修改并确认后再加入你的知识树。',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreeTarget(ThemeData theme) {
    final existingTrees = widget.store.trees;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '加入哪棵知识树',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const ValueKey('knowledge-target-tree-choice'),
          initialValue: _targetChoice,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '目标树',
          ),
          items: [
            const DropdownMenuItem(value: _newTreeChoice, child: Text('新建主题树')),
            for (final tree in existingTrees)
              DropdownMenuItem(value: tree.id, child: Text(tree.title)),
          ],
          onChanged: _isConfirming
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _targetChoice = value);
                  if (value != _newTreeChoice) {
                    _treeTitleController.text =
                        widget.store.treeById(value)?.title ?? '';
                  }
                },
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('knowledge-target-tree-title'),
          controller: _treeTitleController,
          enabled: !_isConfirming && _targetChoice == _newTreeChoice,
          maxLength: 80,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '知识树名称',
            counterText: '',
          ),
        ),
      ],
    );
  }

  Widget _buildCandidate(int index, ThemeData theme) {
    final candidate = _candidates[index];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: candidate.selected ? Colors.white : const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: candidate.selected
              ? const Color(0xFFCFB9FF)
              : const Color(0xFFE5E5E8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  key: ValueKey('knowledge-candidate-${candidate.candidateId}'),
                  value: candidate.selected,
                  onChanged: _isConfirming
                      ? null
                      : (value) =>
                            _replaceCandidate(index, selected: value ?? false),
                ),
                Expanded(
                  child: Text(
                    _typeLabel(candidate.type),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF6B23FF),
                    ),
                  ),
                ),
                Text(
                  '${(candidate.confidence * 100).round()}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextFormField(
              key: ValueKey(
                'knowledge-candidate-title-${candidate.candidateId}',
              ),
              initialValue: candidate.title,
              enabled: candidate.selected && !_isConfirming,
              maxLength: 80,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '标题',
                counterText: '',
              ),
              onChanged: (value) => _replaceCandidate(index, title: value),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey(
                'knowledge-candidate-summary-${candidate.candidateId}',
              ),
              initialValue: candidate.summary,
              enabled: candidate.selected && !_isConfirming,
              minLines: 2,
              maxLines: 4,
              maxLength: 240,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '摘要',
                counterText: '',
              ),
              onChanged: (value) => _replaceCandidate(index, summary: value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction(ThemeData theme) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            key: const ValueKey('confirm-knowledge-batch'),
            onPressed: _isConfirming ? null : _confirm,
            icon: _isConfirming
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_tree_rounded),
            label: Text(_isConfirming ? '正在加入…' : '确认加入知识树'),
          ),
        ),
      ),
    );
  }

  static String _typeLabel(String type) {
    return switch (type) {
      'topic' => '主题',
      'concept' => '概念',
      'insight' => '洞察',
      'method' => '方法',
      'action' => '行动',
      'resource' => '资源',
      _ => '知识',
    };
  }
}

const _newTreeChoice = '__new_knowledge_tree__';

abstract final class KnowledgeMindMapAdapter {
  static MindMapData toMindMapData(KnowledgeTreeSnapshot tree) {
    final nodesById = {for (final node in tree.nodes) node.id: node};
    final roots = tree.nodes
        .where(
          (node) =>
              node.parentNodeId == null ||
              !nodesById.containsKey(node.parentNodeId),
        )
        .toList(growable: false);
    if (roots.length == 1) {
      return _buildNode(roots.single, tree.nodes, const <String>{});
    }

    // 第三方组件只接受单根数据；多根树使用不入库的渲染根。
    return MindMapData(
      id: 'render-root-${tree.id}',
      title: tree.title,
      description: '知识树根节点',
      color: const Color(0xFF6B23FF),
      customData: const {'type': 'topic', 'synthetic': true},
      children: roots
          .map((node) => _buildNode(node, tree.nodes, const <String>{}))
          .toList(growable: false),
    );
  }

  static MindMapData _buildNode(
    KnowledgeNode node,
    List<KnowledgeNode> allNodes,
    Set<String> ancestors,
  ) {
    if (ancestors.contains(node.id)) {
      return MindMapData(
        id: node.id,
        title: node.title,
        description: node.summary,
        color: _nodeColor(node.type),
        customData: {'type': node.type, 'cycleTruncated': true},
      );
    }
    final nextAncestors = {...ancestors, node.id};
    final children = allNodes
        .where((candidate) => candidate.parentNodeId == node.id)
        .map((child) => _buildNode(child, allNodes, nextAncestors))
        .toList(growable: false);
    return MindMapData(
      id: node.id,
      title: node.title,
      description: node.summary,
      color: _nodeColor(node.type),
      customData: {'type': node.type, 'knowledgeNodeId': node.id},
      children: children,
    );
  }

  static Color _nodeColor(String type) {
    return switch (type) {
      'topic' => const Color(0xFF6B23FF),
      'concept' => const Color(0xFF2563EB),
      'insight' => const Color(0xFF0F8A78),
      'method' => const Color(0xFFB45309),
      'action' => const Color(0xFFDC4C64),
      'resource' => const Color(0xFF64748B),
      _ => const Color(0xFF475569),
    };
  }
}

class KnowledgeForestPage extends StatelessWidget {
  const KnowledgeForestPage({super.key, required this.store});

  final KnowledgeForestStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的知识森林')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final trees = store.trees;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                const _KnowledgePrototypeBanner(),
                const SizedBox(height: 18),
                if (trees.isEmpty)
                  const _KnowledgeForestEmptyState()
                else
                  for (final tree in trees)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _KnowledgeTreeCard(
                        tree: tree,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => KnowledgeTreePage(tree: tree),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _KnowledgePrototypeBanner extends StatelessWidget {
  const _KnowledgePrototypeBanner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD98B)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(13),
        child: Row(
          children: [
            Icon(Icons.science_outlined, color: Color(0xFF9A6700)),
            SizedBox(width: 10),
            Expanded(child: Text('内部测试数据，App 重启后清空。')),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeForestEmptyState extends StatelessWidget {
  const _KnowledgeForestEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 18),
          Text(
            '还没有知识树',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '从 Agent 回答中选择“提炼为知识”，确认后将在这里形成主题树。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _KnowledgeTreeCard extends StatelessWidget {
  const _KnowledgeTreeCard({required this.tree, required this.onTap});

  final KnowledgeTreeSnapshot tree;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE6E0F1)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EAFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    Icons.account_tree_rounded,
                    color: Color(0xFF6B23FF),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tree.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text('${tree.nodes.length} 个知识节点'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class KnowledgeTreePage extends StatelessWidget {
  const KnowledgeTreePage({super.key, required this.tree});

  final KnowledgeTreeSnapshot tree;

  @override
  Widget build(BuildContext context) {
    final data = KnowledgeMindMapAdapter.toMindMapData(tree);
    final nodesById = {for (final node in tree.nodes) node.id: node};
    return Scaffold(
      appBar: AppBar(title: Text(tree.title)),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _KnowledgePrototypeBanner(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: MindMapWidget(
                    data: data,
                    cameraFocus: CameraFocus.rootNode,
                    minCanvasSize: const Size(900, 600),
                    canvasPadding: const EdgeInsets.all(180),
                    style: MindMapStyle(
                      layout: MindMapLayout.right,
                      backgroundColor: const Color(0xFFF8F7FC),
                      connectionColor: const Color(0xFFB8A7D9),
                      levelSpacing: 140,
                      nodeMargin: 24,
                      minNodeWidth: 96,
                      maxNodeWidth: 190,
                      nodeBuilder:
                          (node, isSelected, onTap, onLongPress, onDoubleTap) {
                            final type =
                                node.customData?['type']?.toString() ?? '';
                            final color = KnowledgeMindMapAdapter._nodeColor(
                              type,
                            );
                            return Material(
                              color: color,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: isSelected
                                      ? Colors.white
                                      : color.withValues(alpha: 0.75),
                                  width: isSelected ? 3 : 1,
                                ),
                              ),
                              child: InkWell(
                                onTap: onTap,
                                onLongPress: onLongPress,
                                onDoubleTap: onDoubleTap,
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Center(
                                    child: Text(
                                      node.title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                    ),
                    onNodeTap: (data) {
                      final node = nodesById[data.id];
                      if (node != null) {
                        KnowledgeNodeDetailSheet.show(context, node);
                      }
                    },
                    onNodeLongPress: (data) {
                      final node = nodesById[data.id];
                      if (node != null) {
                        KnowledgeNodeDetailSheet.show(context, node);
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KnowledgeNodeDetailSheet extends StatelessWidget {
  const KnowledgeNodeDetailSheet({super.key, required this.node});

  final KnowledgeNode node;

  static Future<void> show(BuildContext context, KnowledgeNode node) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => KnowledgeNodeDetailSheet(node: node),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(node.summary, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 20),
            Text('来源问题', style: theme.textTheme.labelLarge),
            const SizedBox(height: 5),
            Text(node.sourceQuestion),
            const SizedBox(height: 14),
            Text('原始回答摘要', style: theme.textTheme.labelLarge),
            const SizedBox(height: 5),
            Text(node.sourceAnswerExcerpt),
            if (node.sourceRefs.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('可追溯来源', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final source in node.sourceRefs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link_rounded),
                  title: Text(source.title),
                  subtitle: Text(source.sourceName),
                  trailing: IconButton(
                    tooltip: '复制链接',
                    onPressed: source.url.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: source.url),
                          ),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

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

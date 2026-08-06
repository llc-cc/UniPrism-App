import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adapters/remote_exploration_api.dart';
import '../adapters/remote_exploration_dto.dart';
import '../core/remote_exploration_session_controller.dart';
import '../materials/parabola_painter.dart';
import 'chapter_workspace_components.dart';

const _brand = Color(0xFF6B23FF);
const _ink = Color(0xFF27222D);
const _muted = Color(0xFF6F6977);
const _surface = Color(0xFFF7F5FA);

/// 1.2 正式纵向切片入口：先给学习地图，再进入由学生问题驱动的远程 AI Session。
final class RemoteExplorationLabPage extends StatefulWidget {
  const RemoteExplorationLabPage({super.key, this.gateway});

  final RemoteExplorationGateway? gateway;

  @override
  State<RemoteExplorationLabPage> createState() =>
      _RemoteExplorationLabPageState();
}

final class _RemoteExplorationLabPageState
    extends State<RemoteExplorationLabPage> {
  static const _atoms = <(String, String)>[
    ('quadratic-function', '二次函数'),
    ('negative-times-negative', '负负得正'),
    ('inequality-proof', '不等式证明'),
    ('coffee-business-model', '咖啡店商业模型'),
  ];

  late final RemoteExplorationSessionController _controller;
  final _questionController = TextEditingController();
  String _atomId = _atoms.first.$1;
  String? _directionId;

  @override
  void initState() {
    super.initState();
    _controller = RemoteExplorationSessionController(
      api: widget.gateway ?? RemoteExplorationApi(),
    )..addListener(_refresh);
    _controller.loadChapter('negative-number-operations');
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    if (state.snapshot != null) {
      return RemoteLearningSessionPage(controller: _controller);
    }
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('1.2 AI 探索课堂'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: state.chapter == null
                ? _loadingOrError(state)
                : ChapterOverviewPanel(
                    chapter: state.chapter!,
                    selectedNodeId: state.selectedChapterNodeId,
                    questionController: _questionController,
                    busy: state.status == RemoteExplorationStatus.submitting,
                    onSelectNode: _controller.selectChapterNode,
                    onStartNode: _startChapterNode,
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _startChapterNode(String nodeId) async {
    await _controller.startFromChapterNode(
      nodeId,
      question: _questionController.text,
    );
  }

  Widget _loadingOrError(RemoteExplorationState state) {
    if (state.status == RemoteExplorationStatus.failed) {
      return _ErrorPanel(
        message: state.errorMessage ?? '知识地图加载失败',
        onRetry: _controller.retry,
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  /// 保留原子自由入口的渲染能力，后续问题库入口可复用；章节入口不再调用它。
  // ignore: unused_element
  Widget _entryContent(
    LearningEntrySnapshot entry,
    RemoteExplorationState state,
  ) {
    final selected = _directionId ?? entry.recommendedDirectionId;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _KnowledgeMockNotice(),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: _atoms
                  .map(
                    (item) =>
                        ButtonSegment(value: item.$1, label: Text(item.$2)),
                  )
                  .toList(growable: false),
              selected: {_atomId},
              onSelectionChanged:
                  state.status == RemoteExplorationStatus.submitting
                  ? null
                  : (selection) => _selectAtom(selection.single),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            entry.title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 18, color: _muted),
              const SizedBox(width: 6),
              Text(
                '预计探索 ${entry.estimatedMinutes} 分钟 · 教学策略由 AI 自动选择',
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF0E8FF), Color(0xFFFFF0DE)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本节核心问题',
                  style: TextStyle(color: _brand, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.coreQuestion,
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '先看看可以往哪里探索',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...entry.directions.indexed.map((indexed) {
            final (index, direction) = indexed;
            return _DirectionCard(
              key: ValueKey('learning-direction-${direction.id}'),
              index: index + 1,
              direction: direction,
              selected: direction.id == selected,
              recommended: direction.id == entry.recommendedDirectionId,
              showConnector: index < entry.directions.length - 1,
              onTap: () => setState(() => _directionId = direction.id),
            );
          }),
          const SizedBox(height: 18),
          const Text(
            '或者，直接写下你真正想弄懂的问题',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('remote-free-question'),
            controller: _questionController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '例如：如果 a=0，还算二次函数吗？',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          if (state.status == RemoteExplorationStatus.failed) ...[
            const SizedBox(height: 12),
            _ErrorPanel(
              message: state.errorMessage ?? '创建失败',
              onRetry: _controller.retry,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('remote-start-exploration'),
            onPressed: state.status == RemoteExplorationStatus.submitting
                ? null
                : () => _start(entry, selected),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 17),
            ),
            icon: state.status == RemoteExplorationStatus.submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: const Text(
              '开始探索',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAtom(String atomId) async {
    setState(() {
      _atomId = atomId;
      _directionId = null;
      _questionController.clear();
    });
    await _controller.loadEntry(atomId);
  }

  Future<void> _start(LearningEntrySnapshot entry, String directionId) async {
    await _controller.start(
      directionId: directionId,
      question: _questionController.text.trim().isEmpty
          ? null
          : _questionController.text.trim(),
    );
    if (!mounted || _controller.state.snapshot == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RemoteLearningSessionPage(controller: _controller),
      ),
    );
  }
}

final class _DirectionCard extends StatelessWidget {
  const _DirectionCard({
    super.key,
    required this.index,
    required this.direction,
    required this.selected,
    required this.recommended,
    required this.showConnector,
    required this.onTap,
  });

  final int index;
  final LearningDirectionSnapshot direction;
  final bool selected;
  final bool recommended;
  final bool showConnector;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (showConnector)
          Positioned(
            left: 21,
            top: 54,
            bottom: 0,
            child: Container(width: 2, color: const Color(0xFFD9D1E6)),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFF2ECFF) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? _brand : const Color(0xFFE2DDE8),
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: selected
                        ? _brand
                        : const Color(0xFFEFEAF7),
                    foregroundColor: selected ? Colors.white : _ink,
                    child: Text(
                      '$index',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              direction.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (recommended)
                              const Chip(
                                label: Text('推荐'),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          direction.description,
                          style: const TextStyle(color: _muted),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          direction.hookQuestion,
                          style: const TextStyle(
                            color: _brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: selected ? _brand : _muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A+C 探索课堂：桌面常驻双栏，手机常驻当前路径并可展开完整知识树。
final class RemoteLearningSessionPage extends StatefulWidget {
  const RemoteLearningSessionPage({super.key, required this.controller});

  final RemoteExplorationSessionController controller;

  @override
  State<RemoteLearningSessionPage> createState() =>
      _RemoteLearningSessionPageState();
}

final class _RemoteLearningSessionPageState
    extends State<RemoteLearningSessionPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _sessionClock;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    // 剩余时间是会话级状态，只刷新展示，不触发后端写入或改变学习路径。
    _sessionClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _sessionClock?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final snapshot = state.snapshot!;
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 20,
        title: _SessionHeaderTitle(
          snapshot: snapshot,
          remainingLabel: _remainingLabel(snapshot.session.expiresAt),
        ),
        actions: [
          TextButton.icon(
            onPressed: _exportTree,
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('学习素材'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: state.status == RemoteExplorationStatus.completed
                ? _showSummary
                : _complete,
            icon: const Icon(Icons.auto_awesome_rounded, size: 17),
            label: Text(
              state.status == RemoteExplorationStatus.completed
                  ? '学习产出'
                  : '结束并总结',
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 900) {
              return Row(
                children: [
                  Expanded(flex: 6, child: _chatStage(snapshot, mobile: false)),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    key: const ValueKey('exploration-live-tree'),
                    width: (constraints.maxWidth * .3)
                        .clamp(360.0, 560.0)
                        .toDouble(),
                    child: _treeStage(snapshot),
                  ),
                ],
              );
            }
            return Column(
              children: [
                _mobilePath(snapshot),
                Expanded(child: _chatStage(snapshot, mobile: true)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chatStage(
    RemoteLearningSessionSnapshot snapshot, {
    required bool mobile,
  }) {
    final state = widget.controller.state;
    final visibleNodes = snapshot.pathTo(
      state.inspectedNodeId ?? snapshot.currentNodeId,
    );
    return Column(
      key: const ValueKey('exploration-chat-stage'),
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              mobile ? 14 : 28,
              18,
              mobile ? 14 : 28,
              20,
            ),
            itemCount: visibleNodes.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: _CurrentExplorationCard(
                    topic: snapshot.session.topic,
                    strategy: _strategyLabel(snapshot.activeStrategy),
                    chapter: state.chapter,
                    selectedChapterNodeId: state.selectedChapterNodeId,
                  ),
                );
              }
              final node = visibleNodes[index - 1];
              return _ConversationTurn(
                node: node,
                materials: snapshot.materials
                    .where((item) => item.nodeId == node.id)
                    .toList(growable: false),
              );
            },
          ),
        ),
        if (state.inspectedNodeId != null) _selectedNodeActions(snapshot),
        if (state.status == RemoteExplorationStatus.failed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _ErrorPanel(
              message: state.errorMessage ?? '发送失败',
              onRetry: widget.controller.retry,
            ),
          ),
        if (state.status != RemoteExplorationStatus.completed) _composer(),
      ],
    );
  }

  Widget _mobilePath(RemoteLearningSessionSnapshot snapshot) {
    final path = snapshot.pathTo(snapshot.currentNodeId);
    return Material(
      key: const ValueKey('mobile-current-path'),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.account_tree_rounded, size: 18, color: _brand),
            const SizedBox(width: 7),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: path.indexed
                      .map((entry) {
                        final (index, node) = entry;
                        return Row(
                          children: [
                            if (index > 0)
                              const Icon(Icons.chevron_right_rounded, size: 16),
                            Text(
                              node.question,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            ),
            TextButton(
              onPressed: () => _showTree(snapshot),
              child: const Text('完整知识树'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _treeStage(RemoteLearningSessionSnapshot snapshot) {
    final chapter = widget.controller.state.chapter;
    return ColoredBox(
      color: const Color(0xFFFBFAFD),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkbenchPanel(
              title: '我的思维树（探索路径）',
              icon: Icons.account_tree_rounded,
              trailing: TextButton.icon(
                onPressed: _exportTree,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('导出'),
              ),
              subtitle: '点击节点查看，并从任一节点继续、分支或回溯',
              child: KeyedSubtree(
                key: const ValueKey('personal-thinking-tree'),
                child: RemoteLearningTree(
                  snapshot: snapshot,
                  inspectedNodeId: widget.controller.state.inspectedNodeId,
                  onNodeTap: widget.controller.inspectNode,
                ),
              ),
            ),
            if (chapter != null) ...[
              const SizedBox(height: 12),
              _WorkbenchPanel(
                key: const ValueKey('knowledge-overview-card'),
                title: '知识结构图（章节地图）',
                icon: Icons.hub_outlined,
                subtitle: '稳定的章节路线，不会改写你的个人探索路径',
                child: ChapterKnowledgeTree(
                  chapter: chapter,
                  selectedNodeId: widget.controller.state.selectedChapterNodeId,
                  onNodeTap: widget.controller.selectChapterNode,
                  compact: true,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _ExplorationStatsCard(snapshot: snapshot),
          ],
        ),
      ),
    );
  }

  String _remainingLabel(String expiresAt) {
    final expires = DateTime.tryParse(expiresAt)?.toLocal();
    if (expires == null) return '--:--';
    final remaining = expires.difference(DateTime.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    final minutesPart = (seconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (seconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  Widget _selectedNodeActions(RemoteLearningSessionSnapshot snapshot) {
    final state = widget.controller.state;
    final node = snapshot.nodeById(state.inspectedNodeId)!;
    final remembered = state.memoryCandidateNodeIds.contains(node.id);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      color: const Color(0xFFF1ECFA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '正在查看：${node.question}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: widget.controller.prepareContinueFromInspected,
                icon: const Icon(Icons.subdirectory_arrow_right_rounded),
                label: const Text('从这里继续'),
              ),
              TextButton.icon(
                onPressed: widget.controller.prepareBranchFromInspected,
                icon: const Icon(Icons.call_split_rounded),
                label: const Text('新开支线'),
              ),
              TextButton.icon(
                onPressed: widget.controller.backtrackToInspected,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('回溯到这里'),
              ),
              TextButton.icon(
                onPressed: remembered
                    ? null
                    : widget.controller.convertInspectedToMemory,
                icon: Icon(
                  remembered
                      ? Icons.check_circle_rounded
                      : Icons.bookmark_add_outlined,
                ),
                label: Text(remembered ? '已加入候选' : '转为记忆候选'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final state = widget.controller.state;
    final busy = state.status == RemoteExplorationStatus.submitting;
    final modeText = switch (state.composerMode) {
      RemoteComposerMode.currentPath => null,
      RemoteComposerMode.continueFromNode => '下一问将从所选节点继续',
      RemoteComposerMode.branchFromNode => '下一问将从所选节点新开支线',
    };
    return Material(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (modeText != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      modeText,
                      style: const TextStyle(
                        color: _brand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.controller.cancelPreparedAction,
                    child: const Text('取消'),
                  ),
                ],
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['是什么', '为什么会这样', '如果……会怎样', '这和 X 有什么关系', '这有什么用']
                    .map(
                      (text) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(text),
                          onPressed: () => _inputController.text = text,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('remote-question-input'),
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: busy ? null : (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: '继续提出你的问题…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('remote-send-question'),
                  onPressed: busy ? null : _send,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    await widget.controller.submitQuestion(text);
    if (!mounted ||
        widget.controller.state.status == RemoteExplorationStatus.failed) {
      return;
    }
    _inputController.clear();
  }

  void _showTree(RemoteLearningSessionSnapshot snapshot) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .86,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  '我的思维树',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: RemoteLearningTree(
                    snapshot: snapshot,
                    inspectedNodeId: widget.controller.state.inspectedNodeId,
                    onNodeTap: (id) {
                      widget.controller.inspectNode(id);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _complete() async {
    final controller = TextEditingController();
    final reflection = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用自己的话收口'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '说出核心结论、成立条件和一个边界…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续探索'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('完成本次学习'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reflection == null || reflection.trim().isEmpty) return;
    await widget.controller.complete(reflection);
    if (mounted &&
        widget.controller.state.status == RemoteExplorationStatus.completed) {
      _showSummary();
    }
  }

  Future<void> _exportTree() async {
    try {
      final json = await widget.controller.exportTree();
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('思维树 JSON 已复制'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(child: SelectableText(json)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _showSummary() {
    final summary = widget.controller.state.snapshot?.summary;
    if (summary == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '本次学习产出',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              Text('你的复述：${summary.studentRestatement}'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [
                  Chip(label: Text('概念 ${summary.concept}%')),
                  Chip(label: Text('应用 ${summary.application}%')),
                  Chip(label: Text('边界 ${summary.boundary}%')),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '需要复习：${summary.recommendedReview.isEmpty ? '暂无' : summary.recommendedReview.join('、')}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SessionHeaderTitle extends StatelessWidget {
  const _SessionHeaderTitle({
    required this.snapshot,
    required this.remainingLabel,
  });

  final RemoteLearningSessionSnapshot snapshot;
  final String remainingLabel;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final topic = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          snapshot.session.topic,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        Text(
          '${snapshot.session.nodeCount}/20 个问题节点',
          style: const TextStyle(fontSize: 11, color: _muted),
        ),
      ],
    );
    if (!isDesktop) return topic;
    final progress = (snapshot.session.nodeCount / 20).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(width: 230, child: topic),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            key: const ValueKey('exploration-session-progress'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '探索进度',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                  Text(
                    '${snapshot.session.nodeCount}/20',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _brand,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: const Color(0xFFE9E3F1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Text(
          remainingLabel,
          key: const ValueKey('exploration-session-timer'),
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        const Text('/10:00', style: TextStyle(fontSize: 11, color: _muted)),
      ],
    );
  }
}

final class _CurrentExplorationCard extends StatelessWidget {
  const _CurrentExplorationCard({
    required this.topic,
    required this.strategy,
    required this.chapter,
    required this.selectedChapterNodeId,
  });

  final String topic;
  final String strategy;
  final LearningChapterOverviewSnapshot? chapter;
  final String? selectedChapterNodeId;

  @override
  Widget build(BuildContext context) {
    final node = chapter?.nodeById(selectedChapterNodeId);
    return Container(
      key: const ValueKey('current-exploration-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DFEA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A2A123D),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0E8FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.school_rounded, color: _brand, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前探索方向',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(height: 4),
                Text(
                  node?.hookQuestion ?? topic,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '当前策略：$strategy',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          const Chip(label: Text('问题驱动'), visualDensity: VisualDensity.compact),
        ],
      ),
    );
  }
}

final class _WorkbenchPanel extends StatelessWidget {
  const _WorkbenchPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE5DFEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _brand, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: _muted)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

final class _ExplorationStatsCard extends StatelessWidget {
  const _ExplorationStatsCard({required this.snapshot});

  final RemoteLearningSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final started = DateTime.tryParse(snapshot.session.startedAt);
    final elapsed = started == null
        ? 0
        : DateTime.now()
              .toUtc()
              .difference(started.toUtc())
              .inMinutes
              .clamp(0, 99);
    final depth = snapshot.nodes.fold<int>(
      0,
      (value, node) => node.depth > value ? node.depth : value,
    );
    final branches = snapshot.nodes.where((node) => node.isSideBranch).length;
    return Container(
      key: const ValueKey('exploration-stats-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE5DFEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('探索概览', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(label: '探索时长', value: '${elapsed}m'),
              _StatItem(
                label: '节点数',
                value: '${snapshot.session.nodeCount}/20',
              ),
              _StatItem(label: '探索深度', value: '${depth + 1}/5'),
              _StatItem(label: '分支数', value: '$branches'),
            ],
          ),
        ],
      ),
    );
  }
}

final class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

/// 远程思维树只发出节点选择事件，所有写操作由页面上的显式按钮完成。
final class RemoteLearningTree extends StatelessWidget {
  const RemoteLearningTree({
    super.key,
    required this.snapshot,
    required this.inspectedNodeId,
    required this.onNodeTap,
  });

  final RemoteLearningSessionSnapshot snapshot;
  final String? inspectedNodeId;
  final ValueChanged<String> onNodeTap;

  @override
  Widget build(BuildContext context) {
    final roots = snapshot.nodes.where((node) => node.parentId == null);
    return Column(
      children: roots.map((node) => _node(node, 0)).toList(growable: false),
    );
  }

  Widget _node(RemoteLearningNode node, int depth) {
    final children = snapshot.nodes
        .where((candidate) => candidate.parentId == node.id)
        .toList(growable: false);
    final selected = inspectedNodeId == node.id;
    final current = snapshot.currentNodeId == node.id;
    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('remote-tree-node-${node.id}'),
            borderRadius: BorderRadius.circular(13),
            onTap: () => onNodeTap(node.id),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _treeColor(node.status, selected),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: selected || current ? _brand : const Color(0xFFDDD7E6),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      _TreePill(_statusLabel(node.status)),
                      if (current) const _TreePill('当前'),
                      if (node.isSideBranch) const _TreePill('支线'),
                      if (node.backtrackTargetId != null)
                        const _TreePill('已回溯'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    node.question,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          if (children.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 10, top: 7),
              padding: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFFD8D0E5), width: 2),
                ),
              ),
              child: Column(
                children: children
                    .map((child) => _node(child, depth + 1))
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  static Color _treeColor(String status, bool selected) {
    if (selected) return const Color(0xFFF1E9FF);
    if (status == 'CONTRADICTED') return const Color(0xFFFFEEEE);
    if (status == 'BACKTRACKED') return const Color(0xFFFFF5E4);
    return Colors.white;
  }

  static String _statusLabel(String status) => switch (status) {
    'CONTRADICTED' => '不成立',
    'BACKTRACKED' => '已回退',
    'COMPLETED' => '已完成',
    _ => '已探索',
  };
}

final class _ConversationTurn extends StatelessWidget {
  const _ConversationTurn({required this.node, required this.materials});

  final RemoteLearningNode node;
  final List<RemoteLearningMaterial> materials;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE4FF),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                node.question,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 17,
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                child: Icon(Icons.auto_awesome_rounded, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.answer,
                      style: const TextStyle(height: 1.55, fontSize: 15),
                    ),
                    if (materials.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...materials.map(
                        (material) => _RemoteMaterialCard(material: material),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F7F4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.psychology_alt_rounded,
                            size: 18,
                            color: Color(0xFF167A5A),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              node.followUpQuestion,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF175B47),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _RemoteMaterialCard extends StatelessWidget {
  const _RemoteMaterialCard({required this.material});

  final RemoteLearningMaterial material;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF9F8FC),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE0DBE8)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_materialIcon(material.type), size: 18, color: _brand),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    material.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            if (material.type == 'INTERACTIVE')
              _InteractiveLearningMaterial(material: material)
            else if (material.type == 'VIDEO')
              _PlayableProcessMaterial(material: material)
            else if (material.type == 'FIGURE')
              _ConceptFigure(material: material)
            else
              _FormulaBlock(material: material),
          ],
        ),
      ),
    );
  }

  static IconData _materialIcon(String type) => switch (type) {
    'INTERACTIVE' => Icons.tune_rounded,
    'VIDEO' => Icons.play_circle_outline_rounded,
    'FIGURE' => Icons.schema_rounded,
    _ => Icons.functions_rounded,
  };
}

final class _InteractiveLearningMaterial extends StatefulWidget {
  const _InteractiveLearningMaterial({required this.material});

  final RemoteLearningMaterial material;

  @override
  State<_InteractiveLearningMaterial> createState() =>
      _InteractiveLearningMaterialState();
}

final class _InteractiveLearningMaterialState
    extends State<_InteractiveLearningMaterial> {
  double _a = 1;
  double _h = 0;
  double _k = 0;
  double _price = 24;
  double _orders = 120;
  double _cost = 9;
  int _flipCount = 0;

  @override
  Widget build(BuildContext context) {
    final key = widget.material.componentKey ?? '';
    if (key == 'parabola_widget') {
      return Column(
        children: [
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: ParabolaPainter(a: _a, h: _h, k: _k),
              child: const SizedBox.expand(),
            ),
          ),
          _slider(
            'a',
            _a,
            -2,
            2,
            (value) => setState(() => _a = value == 0 ? .1 : value),
          ),
          _slider('h', _h, -3, 3, (value) => setState(() => _h = value)),
          _slider('k', _k, -3, 3, (value) => setState(() => _k = value)),
        ],
      );
    }
    if (key == 'sign_flip_widget') {
      return Row(
        children: [
          Expanded(
            child: Text(_flipCount.isEven ? '当前方向：向右（正）' : '当前方向：向左（负）'),
          ),
          FilledButton.tonal(
            onPressed: () => setState(() => _flipCount += 1),
            child: Text('乘以 -1（$_flipCount 次）'),
          ),
        ],
      );
    }
    if (key.contains('unit') ||
        widget.material.materialId.contains('business')) {
      final profit = (_price - _cost) * _orders;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '每日贡献毛利：¥${profit.toStringAsFixed(0)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF167A5A),
            ),
          ),
          _slider(
            '单价',
            _price,
            10,
            50,
            (value) => setState(() => _price = value),
          ),
          _slider(
            '订单',
            _orders,
            20,
            300,
            (value) => setState(() => _orders = value),
          ),
          _slider(
            '单杯变动成本',
            _cost,
            3,
            25,
            (value) => setState(() => _cost = value),
          ),
        ],
      );
    }
    return _slider('验证参数', _a, -2, 2, (value) => setState(() => _a = value));
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            '$label ${value.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

final class _PlayableProcessMaterial extends StatefulWidget {
  const _PlayableProcessMaterial({required this.material});
  final RemoteLearningMaterial material;

  @override
  State<_PlayableProcessMaterial> createState() =>
      _PlayableProcessMaterialState();
}

final class _PlayableProcessMaterialState
    extends State<_PlayableProcessMaterial> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => setState(
            () =>
                _progress = _progress >= 1 ? 0 : (_progress + .25).clamp(0, 1),
          ),
          icon: Icon(
            _progress >= 1 ? Icons.replay_rounded : Icons.play_arrow_rounded,
          ),
        ),
        Expanded(
          child: Slider(
            value: _progress,
            onChanged: (value) => setState(() => _progress = value),
          ),
        ),
        Text('${(_progress * 100).round()}%'),
      ],
    );
  }
}

final class _ConceptFigure extends StatelessWidget {
  const _ConceptFigure({required this.material});
  final RemoteLearningMaterial material;

  @override
  Widget build(BuildContext context) {
    final description =
        material.payload['description']?.toString() ?? '观察结构之间的连接关系';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Expanded(child: _FigureBlock(label: '现象')),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded),
          ),
          Expanded(child: _FigureBlock(label: description, emphasized: true)),
        ],
      ),
    );
  }
}

final class _FigureBlock extends StatelessWidget {
  const _FigureBlock({required this.label, this.emphasized = false});
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFFD8F1EC) : Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

final class _FormulaBlock extends StatelessWidget {
  const _FormulaBlock({required this.material});
  final RemoteLearningMaterial material;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEE9F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        material.payload['description']?.toString() ?? material.title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

final class _TreePill extends StatelessWidget {
  const _TreePill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEDE8F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

final class _KnowledgeMockNotice extends StatelessWidget {
  const _KnowledgeMockNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text('知识内容与首批素材暂用 Mock；AI 调度、会话、思维树和学习产出均走后端。')),
        ],
      ),
    );
  }
}

final class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

String _strategyLabel(String? strategy) => switch (strategy) {
  'QUESTION_CHAIN' => '问题链探索',
  'SOCRATIC' => '苏格拉底追问',
  'ERROR_TRACKING' => '错误思维追踪',
  'ANALOGY_TRANSFER' => '类比迁移',
  'SELF_EXPLANATION' => '自我解释',
  _ => '自动教学策略',
};

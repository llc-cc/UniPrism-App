import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adapters/guided_teaching_flow_dto.dart';
import '../adapters/remote_exploration_api.dart';
import '../adapters/remote_exploration_dto.dart';
import '../core/prestudy_timing_guidance.dart';
import '../core/remote_exploration_session_controller.dart';
import '../materials/mock_whiteboard_launcher.dart';
import '../materials/parabola_painter.dart';
import 'chapter_catalog_picker.dart';
import 'chapter_workspace_components.dart';
import 'exploration_node_map.dart';
import 'guided_practice_dialog.dart';
import 'next_learning_options_sheet.dart';
import 'student_learning_narrative.dart';
import 'technical_trace.dart';
import 'technical_trace_drawer.dart';

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
  late final RemoteExplorationSessionController _controller;
  final _questionController = TextEditingController();
  final _directTeacherQuestionController = TextEditingController();
  var _catalogRequested = false;
  var _initializing = true;

  @override
  void initState() {
    super.initState();
    _controller = RemoteExplorationSessionController(
      api: widget.gateway ?? RemoteExplorationApi(),
    )..addListener(_refresh);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _controller.loadHistory(restoreLatestActive: true);
    if (!mounted) return;
    // 账号历史是恢复会话的事实来源；加载失败时必须停留在错误态，不能继续创建空白入口。
    if (_controller.state.status == RemoteExplorationStatus.failed) {
      setState(() => _initializing = false);
      return;
    }
    if (_controller.state.snapshot == null) {
      // 只有确认不存在可恢复会话时才请求目录，避免目录短暂覆盖恢复结果。
      _catalogRequested = true;
      await _controller.loadChapterCatalog();
    }
    if (!mounted) return;
    setState(() => _initializing = false);
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
    _directTeacherQuestionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    if (state.snapshot != null) {
      return RemoteLearningSessionPage(
        controller: _controller,
        onBackToOverview: _backToOverview,
      );
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
            child: Column(
              children: [
                if (state.history.isNotEmpty)
                  _PrestudyHistorySection(
                    history: state.history,
                    onOpen: (sessionId) =>
                        unawaited(_controller.openHistorySession(sessionId)),
                  ),
                Expanded(
                  child: state.chapter == null
                      ? _catalogOrError(state)
                      : ChapterOverviewPanel(
                          chapter: state.chapter!,
                          selectedNodeId: state.selectedChapterNodeId,
                          questionController: _questionController,
                          directTeacherQuestionController:
                              _directTeacherQuestionController,
                          busy:
                              state.status ==
                              RemoteExplorationStatus.submitting,
                          errorMessage:
                              state.status == RemoteExplorationStatus.failed
                              ? state.errorMessage
                              : null,
                          onRetry: _controller.retry,
                          onSelectNode: _controller.selectChapterNode,
                          onStartNode: _startChapterNode,
                          onStartDirectQuestion: _startDirectQuestion,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startChapterNode(String nodeId, String? question) async {
    await _controller.startFromChapterNode(nodeId, question: question);
  }

  Future<void> _startDirectQuestion(String question) async {
    await _controller.startFreeQuestion(question);
  }

  Widget _catalogOrError(RemoteExplorationState state) {
    if (state.status == RemoteExplorationStatus.failed) {
      return _ErrorPanel(
        message: state.errorMessage ?? '知识地图加载失败',
        onRetry: _retryInitialLoad,
      );
    }
    return ChapterCatalogPicker(
      chapters: state.chapterCatalog,
      busy:
          _initializing || state.status == RemoteExplorationStatus.loadingEntry,
      onSelect: (chapterId) => unawaited(_controller.selectChapter(chapterId)),
    );
  }

  Future<void> _retryInitialLoad() async {
    if (_catalogRequested) {
      await _controller.retry();
      if (mounted) setState(() => _initializing = false);
      return;
    }
    await _initialize();
  }

  Future<void> _backToOverview() async {
    _controller.leaveSession();
    if (_controller.state.chapter != null) return;
    // 从历史会话返回没有章节概览时，只重放目录加载，不能再次抢占恢复流程。
    _catalogRequested = true;
    await _controller.loadChapterCatalog();
  }
}

/// 学科卡只负责切换编排好的章节；不会把学科选择写进会话节点，避免污染学生的探索路径。
/// 历史区只展示服务端返回的账号范围记录，不在设备端复制或拼接会话树。
final class _PrestudyHistorySection extends StatelessWidget {
  const _PrestudyHistorySection({required this.history, required this.onOpen});

  final List<RemoteLearningSessionSummary> history;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('prestudy-history-section'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4DDEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_rounded, color: _brand),
              SizedBox(width: 8),
              Text(
                '我的预习记录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = history[index];
                final completed = item.status == 'COMPLETED';
                final progressLabel = item.canContinue
                    ? '可继续'
                    : completed
                    ? '已完成'
                    : '已结束';
                return SizedBox(
                  width: 260,
                  child: InkWell(
                    key: ValueKey('prestudy-history-${item.id}'),
                    onTap: () => onOpen(item.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F3FC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            completed
                                ? Icons.check_circle_outline_rounded
                                : Icons.play_circle_outline_rounded,
                            color: _brand,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.topic,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$progressLabel · ${item.nodeCount} 个节点',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 探索课堂桌面常驻对话与当前路径，手机可展开完整思维树。
final class RemoteLearningSessionPage extends StatefulWidget {
  const RemoteLearningSessionPage({
    super.key,
    required this.controller,
    this.onBackToOverview,
  });

  final RemoteExplorationSessionController controller;
  final Future<void> Function()? onBackToOverview;

  @override
  State<RemoteLearningSessionPage> createState() =>
      _RemoteLearningSessionPageState();
}

final class _RemoteLearningSessionPageState
    extends State<RemoteLearningSessionPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _whiteboardLauncher = const MockExplorationWhiteboardLauncher();
  Timer? _timingTicker;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    // 只为切换软引导文案刷新页面；不提交请求，也不改变会话状态。
    _timingTicker = Timer.periodic(const Duration(seconds: 30), (_) {
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
  void didUpdateWidget(covariant RemoteLearningSessionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    // 页面复用时迁移监听，避免旧会话的更新误刷新当前课堂。
    oldWidget.controller.removeListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    _timingTicker?.cancel();
    widget.controller.removeListener(_refresh);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final snapshot = state.snapshot!;
    final teachingFlow = snapshot.teachingFlow;
    final technicalTrace = const MockTechnicalTraceProvider().build(snapshot);
    final canCompleteGuidedLesson =
        teachingFlow == null ||
        teachingFlow.stage == RemoteTeachingStage.reflect;
    return Scaffold(
      backgroundColor: _surface,
      endDrawer: TechnicalTraceDrawer(trace: technicalTrace),
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 20,
        leading: state.history.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('prestudy-back-to-overview'),
                tooltip: '返回预习总览',
                onPressed: () => unawaited(_backToOverview()),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(
          snapshot.session.topic,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        actions: [
          Builder(
            builder: (scaffoldContext) {
              final compact = MediaQuery.sizeOf(context).width < 900;
              void openTrace() => Scaffold.of(scaffoldContext).openEndDrawer();
              if (compact) {
                return IconButton(
                  key: const ValueKey('open-technical-trace'),
                  tooltip: '查看技术轨迹 · Mock',
                  onPressed: openTrace,
                  icon: const Icon(Icons.schema_outlined),
                );
              }
              return TextButton.icon(
                key: const ValueKey('open-technical-trace'),
                onPressed: openTrace,
                icon: const Icon(Icons.schema_outlined, size: 18),
                label: const Text('技术轨迹 · Mock'),
              );
            },
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: _exportTree,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('导出探索地图'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: state.isReadOnly
                ? (snapshot.summary == null ? null : _showSummary)
                : canCompleteGuidedLesson
                ? _complete
                : null,
            icon: const Icon(Icons.auto_awesome_rounded, size: 17),
            label: Text(state.isReadOnly ? '学习产出' : '结束并总结'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                if (state.isReadOnly)
                  Container(
                    key: const ValueKey('prestudy-read-only-banner'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    color: const Color(0xFFFFF2D8),
                    child: const Text(
                      '这是已结束的预习记录，可查看完整对话树，但不能继续修改。',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                _ConceptPathStrip(
                  snapshot: snapshot,
                  onOpenMap: () => _showTree(snapshot),
                ),
                Expanded(
                  child: _classroomStage(
                    snapshot,
                    mobile: constraints.maxWidth < 700,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _backToOverview() async {
    final onBackToOverview = widget.onBackToOverview;
    if (onBackToOverview != null) {
      await onBackToOverview();
      return;
    }
    widget.controller.leaveSession();
  }

  Widget _classroomStage(
    RemoteLearningSessionSnapshot snapshot, {
    required bool mobile,
  }) {
    final state = widget.controller.state;
    final node = snapshot.nodeById(
      state.inspectedNodeId ?? snapshot.currentNodeId,
    )!;
    final path = snapshot.pathTo(node.id);
    final guidance = _timingGuidance(snapshot);
    final teachingFlow = snapshot.teachingFlow;
    final guidedMaterial = teachingFlow == null
        ? null
        : _materialByUsageId(
            snapshot.materials,
            teachingFlow.currentAction.materialUsageId,
          );
    final guidedEventType = _completionEventType(guidedMaterial?.componentKey);
    final activeGuidedMaterialId =
        teachingFlow?.stage == RemoteTeachingStage.asset
        ? guidedMaterial?.id
        : null;
    return Column(
      key: const ValueKey('exploration-classroom-stage'),
      children: [
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              mobile ? 14 : 28,
              18,
              mobile ? 14 : 28,
              20,
            ),
            children: [
              _ClassroomGuideHeader(
                topic: snapshot.session.topic,
                currentQuestion: node.question,
              ),
              const SizedBox(height: 14),
              if (guidance != null) ...[
                _PreStudyTimingCue(guidance: guidance),
                const SizedBox(height: 14),
              ],
              _StudentLearningTimeline(
                turns: [
                  ...path.indexed.map(
                    (entry) => _ExplorationTurnCard(
                      node: entry.$2,
                      isCurrent: entry.$2.id == node.id,
                      materials: snapshot.materials
                          .where(
                            (item) =>
                                item.nodeId == entry.$2.id &&
                                item.id != activeGuidedMaterialId,
                          )
                          .toList(growable: false),
                      onOpenWhiteboard: () => _openWhiteboard(entry.$2),
                    ),
                  ),
                  if (teachingFlow != null)
                    _GuidedTeachingActionPanel(
                      flow: teachingFlow,
                      material: guidedMaterial,
                      assetEventType: guidedEventType,
                      onAssetComplete:
                          guidedMaterial == null || guidedEventType == null
                          ? null
                          : (interactionPayload) =>
                                widget.controller.submitMaterialEvent(
                                  materialUsageId: guidedMaterial.id,
                                  eventType: guidedEventType,
                                  payload: {
                                    'componentKey': guidedMaterial.componentKey,
                                    'completionConfirmed': true,
                                    ...interactionPayload,
                                  },
                                ),
                      onStartMicroCheck: _showGuidedPractice,
                      onStartReflection: _complete,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (state.inspectedNodeId != null && !state.isReadOnly)
          _selectedNodeActions(snapshot),
        if (state.status == RemoteExplorationStatus.failed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _ErrorPanel(
              message: state.errorMessage ?? '发送失败',
              onRetry: widget.controller.retry,
            ),
          ),
        if (!state.isReadOnly) _composer(),
      ],
    );
  }

  /// 迁移判断在对话框关闭后才提交，避免网络失败导致未确认草稿进入证据链。
  /// 必做题只能由当前服务端快照打开；缺少快照时不能回退到空白本地表单。
  Future<void> _showGuidedPractice() async {
    final flow = widget.controller.state.snapshot?.teachingFlow;
    final practice = flow?.activePractice;
    if (flow?.stage != RemoteTeachingStage.focus || practice == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('暂时无法打开新情境'),
          content: const Text('题目快照尚未准备好，请稍后重试。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GuidedPracticeDialog(
        practice: practice,
        onSubmit: _submitGuidedPractice,
        onRetry: _retryGuidedPractice,
      ),
    );
  }

  Future<bool> _submitGuidedPractice(GuidedPracticeDraft draft) async {
    await widget.controller.submitGuidedPractice(
      reasoning: draft.reasoning,
      answer: draft.answer,
    );
    return widget.controller.state.status != RemoteExplorationStatus.failed;
  }

  Future<bool> _retryGuidedPractice() async {
    await widget.controller.retry();
    return widget.controller.state.status != RemoteExplorationStatus.failed;
  }

  PreStudyTimingGuidance? _timingGuidance(
    RemoteLearningSessionSnapshot snapshot,
  ) {
    final startedAt = DateTime.tryParse(snapshot.session.startedAt);
    if (startedAt == null) return null;
    final elapsed = DateTime.now().difference(startedAt);
    return preStudyTimingGuidanceFor(
      elapsed.isNegative ? Duration.zero : elapsed,
    );
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
            '正在查看：${_explorationConceptLabel(node)}',
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
    final busy =
        state.status == RemoteExplorationStatus.submitting ||
        state.snapshot?.teachingFlow?.stage == RemoteTeachingStage.focus;
    final modeText = switch (state.composerMode) {
      RemoteComposerMode.currentPath => null,
      RemoteComposerMode.continueFromNode => '下一问将从所选节点继续',
      RemoteComposerMode.branchFromNode => '下一问将从所选节点新开支线',
    };
    return Material(
      key: const ValueKey('prestudy-question-composer'),
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
                      hintText: '写下你的发现、疑问或一个反例…',
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

  Future<void> _openWhiteboard(RemoteLearningNode node) async {
    final result = await _whiteboardLauncher.open(
      context,
      nodeId: node.id,
      atomId: widget.controller.state.snapshot!.session.atomId ?? '',
      initialState: const {'a': 1.0, 'h': 0.0, 'k': 0.0},
    );
    if (!mounted || !result.confirmed) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('白板状态已带回当前探索节点（Mock）')));
  }

  void _showTree(RemoteLearningSessionSnapshot snapshot) {
    var visualFocusNodeId =
        widget.controller.state.inspectedNodeId ?? snapshot.currentNodeId;
    final readOnly = widget.controller.state.isReadOnly;
    if (MediaQuery.sizeOf(context).width >= 900) {
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => StatefulBuilder(
          builder: (_, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.all(28),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 1280,
              height: 760,
              child: KeyedSubtree(
                key: const ValueKey('concept-map-sheet'),
                child: _ConceptMapSheet(
                  snapshot: snapshot,
                  readOnly: readOnly,
                  inspectedNodeId: visualFocusNodeId,
                  onNodeTap: (id) {
                    widget.controller.inspectNode(id);
                    setDialogState(() => visualFocusNodeId = id);
                  },
                  onContinue: () {
                    widget.controller.inspectNode(visualFocusNodeId!);
                    widget.controller.prepareContinueFromInspected();
                    Navigator.pop(dialogContext);
                  },
                  onBranch: () {
                    widget.controller.inspectNode(visualFocusNodeId!);
                    widget.controller.prepareBranchFromInspected();
                    Navigator.pop(dialogContext);
                  },
                  onClose: () => Navigator.pop(dialogContext),
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: .92,
            child: KeyedSubtree(
              key: const ValueKey('concept-map-sheet'),
              child: _ConceptMapSheet(
                snapshot: snapshot,
                readOnly: readOnly,
                inspectedNodeId: visualFocusNodeId,
                onNodeTap: (id) {
                  widget.controller.inspectNode(id);
                  setSheetState(() => visualFocusNodeId = id);
                },
                onContinue: () {
                  widget.controller.inspectNode(visualFocusNodeId!);
                  widget.controller.prepareContinueFromInspected();
                  Navigator.pop(sheetContext);
                },
                onBranch: () {
                  widget.controller.inspectNode(visualFocusNodeId!);
                  widget.controller.prepareBranchFromInspected();
                  Navigator.pop(sheetContext);
                },
                onClose: () => Navigator.pop(sheetContext),
              ),
            ),
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
        title: const Text('整理这次探索'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '写下你现在的猜想、还没想明白的问题，或最想继续探索的方向',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续探索'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('结束预习并生成探索结果'),
          ),
        ],
      ),
    );
    // Dialog 的退出动画仍会读取输入控制器；下一帧释放可避免快速提交后的悬空监听。
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
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
    final snapshot = widget.controller.state.snapshot;
    final summary = snapshot?.summary;
    if (summary == null) return;
    final exploredLabels = snapshot == null
        ? const <String>[]
        : _currentConceptPath(
            snapshot,
          ).map((item) => item.label).toSet().take(4).toList(growable: false);
    final nextQuestion = snapshot
        ?.nodeById(snapshot.currentNodeId)
        ?.followUpQuestion;
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
                '本次探索结果',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              Text('你写下的想法：${summary.studentRestatement}'),
              const SizedBox(height: 14),
              const Text(
                '已探索的方向',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: exploredLabels.isEmpty
                    ? const [Chip(label: Text('你已提出第一个探索问题'))]
                    : exploredLabels
                          .map((item) => Chip(label: Text(item)))
                          .toList(),
              ),
              if (nextQuestion != null && nextQuestion.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  '带去正式学习的问题',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(nextQuestion),
              ],
              const SizedBox(height: 16),
              const Text(
                '这不是掌握度判断。正式学习会从你的探索问题出发，系统化展开概念与证明。',
                style: TextStyle(color: _muted),
              ),
              if (snapshot?.teachingFlow != null) ...[
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final state = widget.controller.state;
                    return NextLearningOptionsSheet(
                      options: snapshot!.teachingFlow!.nextLearningOptions,
                      busy: state.status == RemoteExplorationStatus.submitting,
                      errorMessage:
                          state.status == RemoteExplorationStatus.failed
                          ? state.errorMessage
                          : null,
                      onContinue: (option) =>
                          unawaited(_startNextLearning(option)),
                      onRetry: () => unawaited(_retryNextLearning()),
                      onFinish: () => Navigator.pop(context),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startNextLearning(RemoteNextLearningOption option) async {
    await widget.controller.startNextLearningOption(option);
    if (!mounted ||
        widget.controller.state.status == RemoteExplorationStatus.failed) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _retryNextLearning() async {
    await widget.controller.retry();
    if (!mounted ||
        widget.controller.state.status == RemoteExplorationStatus.failed) {
      return;
    }
    Navigator.of(context).pop();
  }
}

/// 地图只呈现已经形成的概念，不把“是什么”“不懂”等对话动作伪装成知识节点。
String _explorationConceptLabel(RemoteLearningNode node) {
  final persistedLabel = node.mapLabel?.trim();
  if (persistedLabel != null && persistedLabel.isNotEmpty) {
    return persistedLabel;
  }
  final text = '${node.question} ${node.answer} ${node.followUpQuestion}';
  if (text.contains('分配律') || text.contains('0=(-1)')) return '分配律证明';
  if (text.contains('同号') || text.contains('异号') || text.contains('结果符号')) {
    return '符号判断规则';
  }
  if (text.contains('相反数')) return '取相反数';
  if (text.contains('方向') || text.contains('数轴')) return '数轴上的方向变化';
  if (text.contains('顶点') || text.contains('完全平方')) return '顶点与完全平方';
  if (text.contains('反例') || text.contains('矛盾')) return '反例检验';
  return node.question.length > 16
      ? '${node.question.substring(0, 16)}…'
      : node.question;
}

/// 回答来源由后端判定；未知值保持静默，以兼容滚动发布期间的新旧协议。
String? _answerSourceLabel(RemoteLearningNode node) =>
    StudentLearningNarrative.answerContextLabel(node.answerSource);

/// 课堂顶部只呈现最近的有效认知路径，完整结构按需展开，不持续挤压教学空间。
final class _ConceptPathStrip extends StatelessWidget {
  const _ConceptPathStrip({required this.snapshot, required this.onOpenMap});

  final RemoteLearningSessionSnapshot snapshot;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final path = _currentConceptPath(snapshot);
    final visible = path.length > 3 ? path.sublist(path.length - 3) : path;
    return Material(
      key: const ValueKey('concept-path-strip'),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 9, 12, 9),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE8E2ED))),
        ),
        child: Row(
          children: [
            const Icon(Icons.route_rounded, size: 18, color: _brand),
            const SizedBox(width: 8),
            const Text(
              '你的探索足迹',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: visible.isEmpty
                      ? const [
                          Text(
                            '第一个发现正在形成',
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                        ]
                      : visible.indexed
                            .expand(
                              (entry) => [
                                if (entry.$1 > 0)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: _muted,
                                    ),
                                  ),
                                Chip(
                                  label: Text(entry.$2.label),
                                  visualDensity: VisualDensity.compact,
                                  side: BorderSide.none,
                                  backgroundColor:
                                      entry.$1 == visible.length - 1
                                      ? const Color(0xFFF0E8FF)
                                      : const Color(0xFFF5F2F8),
                                ),
                              ],
                            )
                            .toList(growable: false),
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('open-concept-map'),
              onPressed: onOpenMap,
              icon: const Icon(Icons.account_tree_outlined, size: 17),
              label: const Text('回看我的探索'),
            ),
          ],
        ),
      ),
    );
  }

  static List<RemoteLearningConceptNode> _currentConceptPath(
    RemoteLearningSessionSnapshot snapshot,
  ) {
    final concepts = snapshot.displayConceptNodes;
    if (concepts.isEmpty) return const [];
    final turnPathIds = snapshot
        .pathTo(snapshot.currentNodeId)
        .map((node) => node.id)
        .toSet();
    final current = concepts.lastWhere(
      (concept) => turnPathIds.contains(concept.evidenceNodeId),
      orElse: () => concepts.last,
    );
    final byId = {for (final concept in concepts) concept.id: concept};
    final path = <RemoteLearningConceptNode>[];
    final visited = <String>{};
    RemoteLearningConceptNode? cursor = current;
    while (cursor != null && visited.add(cursor.id)) {
      path.insert(0, cursor);
      cursor = cursor.parentId == null ? null : byId[cursor.parentId!];
    }
    return path;
  }
}

/// 预习收束与顶部路径条复用同一条概念路径，避免两个区域展示不同的探索结果。
List<RemoteLearningConceptNode> _currentConceptPath(
  RemoteLearningSessionSnapshot snapshot,
) => _ConceptPathStrip._currentConceptPath(snapshot);

/// 探索过程使用覆盖式容器承载，关闭后课堂立即恢复全宽。
final class _ConceptMapSheet extends StatelessWidget {
  const _ConceptMapSheet({
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
    return ExplorationNodeMap(
      snapshot: snapshot,
      readOnly: readOnly,
      inspectedNodeId: inspectedNodeId,
      onNodeTap: onNodeTap,
      onContinue: onContinue,
      onBranch: onBranch,
      onClose: onClose,
    );
  }
}

/// 认知树只发出证据对话节点选择事件，所有写操作由页面上的显式按钮完成。
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: snapshot.displayConceptNodes
          .map(_fullOutlineNode)
          .toList(growable: false),
    );
  }

  Widget _fullOutlineNode(RemoteLearningConceptNode node) {
    final selected = inspectedNodeId == node.evidenceNodeId;
    final current = snapshot.currentNodeId == node.evidenceNodeId;
    final visualDepth = _conceptDepth(node).clamp(0, 4);
    return Padding(
      padding: EdgeInsets.only(left: visualDepth * 4.0, bottom: 8),
      child: InkWell(
        key: ValueKey('remote-tree-node-${node.evidenceNodeId}'),
        borderRadius: BorderRadius.circular(13),
        onTap: () => onNodeTap(node.evidenceNodeId),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: _conceptColor(node.status, selected),
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
                  _TreePill(_kindLabel(node.kind)),
                  _TreePill(_conceptStatusLabel(node.status)),
                  if (current) const _TreePill('当前'),
                  if (node.relation == 'BRANCH') const _TreePill('支线'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                node.label,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _conceptDepth(RemoteLearningConceptNode node) {
    final byId = {
      for (final concept in snapshot.displayConceptNodes) concept.id: concept,
    };
    var depth = 0;
    var cursor = node.parentId == null ? null : byId[node.parentId!];
    final visited = <String>{node.id};
    while (cursor != null && visited.add(cursor.id)) {
      depth += 1;
      cursor = cursor.parentId == null ? null : byId[cursor.parentId!];
    }
    return depth;
  }

  static String _kindLabel(String kind) => switch (kind) {
    'METHOD' => '方法',
    'MISCONCEPTION' => '误区',
    'VERIFICATION' => '验证',
    _ => '概念',
  };

  static Color _conceptColor(String status, bool selected) {
    if (selected) return const Color(0xFFF1E9FF);
    if (status == 'CONFLICTED') return const Color(0xFFFFEEEE);
    if (status == 'CORRECTED') return const Color(0xFFFFF5E4);
    return Colors.white;
  }

  static String _conceptStatusLabel(String status) => switch (status) {
    'CONFLICTED' => '待纠正',
    'CORRECTED' => '已修正',
    'FORMING' => '形成中',
    _ => '已验证',
  };
}

/// 预习时长提示只建议收束，不替代学生主动结束会话的决定。
final class _PreStudyTimingCue extends StatelessWidget {
  const _PreStudyTimingCue({required this.guidance});

  final PreStudyTimingGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final icon = switch (guidance.milestone) {
      PreStudyTimingMilestone.reflect => Icons.lightbulb_outline_rounded,
      PreStudyTimingMilestone.consolidate => Icons.bookmark_outline_rounded,
      PreStudyTimingMilestone.summarize => Icons.auto_awesome_rounded,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('prestudy-timing-cue'),
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF1ECFA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _brand),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                guidance.message,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一次课堂只把当前认知关口放在台前；历史过程收进探索地图，避免退化为聊天记录。
/// 对话区保留学生自己提出的问题和 AI 的反问，让每一轮都能回看并继续分支。
final class _ClassroomGuideHeader extends StatelessWidget {
  const _ClassroomGuideHeader({
    required this.topic,
    required this.currentQuestion,
  });

  final String topic;
  final String currentQuestion;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('ai-exploration-classroom'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0E8FF), Color(0xFFFFF7EC)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            child: Icon(Icons.auto_awesome_rounded, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今天，我们一起发现一个秘密',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  currentQuestion,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.35,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '围绕「$topic」，先不用急着记规则，从你的想法开始。',
                  style: const TextStyle(color: _muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 引导条只渲染服务端当前动作；素材操作仅决定按钮是否可提交，阶段与证据仍由服务端推进。
final class _GuidedTeachingActionPanel extends StatefulWidget {
  const _GuidedTeachingActionPanel({
    required this.flow,
    required this.material,
    required this.assetEventType,
    required this.onAssetComplete,
    required this.onStartMicroCheck,
    required this.onStartReflection,
  });

  final RemoteTeachingFlow flow;
  final RemoteLearningMaterial? material;
  final String? assetEventType;
  final Future<void> Function(Map<String, Object?> payload)? onAssetComplete;
  final Future<void> Function() onStartMicroCheck;
  final Future<void> Function() onStartReflection;

  @override
  State<_GuidedTeachingActionPanel> createState() =>
      _GuidedTeachingActionPanelState();
}

final class _GuidedTeachingActionPanelState
    extends State<_GuidedTeachingActionPanel> {
  bool _isAssetReady = false;
  Map<String, Object?> _assetPayload = const {};

  @override
  void didUpdateWidget(covariant _GuidedTeachingActionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flow.stage != widget.flow.stage ||
        oldWidget.material?.id != widget.material?.id) {
      _isAssetReady = false;
      _assetPayload = const {};
    }
  }

  void _setAssetReadiness(bool isReady, Map<String, Object?> payload) {
    setState(() {
      _isAssetReady = isReady;
      _assetPayload = Map<String, Object?>.unmodifiable(payload);
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final canSubmitAsset =
        _isAssetReady &&
        widget.material != null &&
        widget.assetEventType != null &&
        widget.onAssetComplete != null;
    return Container(
      key: const ValueKey('guided-teaching-action-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF2ECFF), Color(0xFFF9F7FD)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9C9FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, color: _brand, size: 20),
              const SizedBox(width: 8),
              Text(
                flow.explorationAct == RemoteGuidedExplorationAct.unknown
                    ? StudentLearningNarrative.stageTitle(flow.stage)
                    : StudentLearningNarrative.explorationTitle(
                        flow.explorationAct,
                      ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Builder(
            key: const ValueKey('student-learning-journey'),
            builder: (context) {
              final currentIndex =
                  StudentLearningNarrative.explorationJourneyIndex(
                    flow.stage,
                    flow.explorationAct,
                  );
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: StudentLearningNarrative.explorationJourney.indexed
                    .map(
                      (entry) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: entry.$1 == currentIndex
                              ? _brand
                              : const Color(0xFFEAE5F0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          entry.$2,
                          style: TextStyle(
                            color: entry.$1 == currentIndex
                                ? Colors.white
                                : _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            '今天要发现：${flow.goal}',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 5),
          Text(
            flow.currentAction.prompt,
            style: const TextStyle(fontWeight: FontWeight.w800, height: 1.45),
          ),
          if (flow.feedback?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(flow.feedback!, style: const TextStyle(height: 1.4)),
          ],
          if (flow.repairFocus?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('guided-repair-focus'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5E5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(flow.repairFocus!),
            ),
          ],
          if (StudentLearningNarrative.supportMessage(flow.supportLevel)
              case final supportMessage?) ...[
            const SizedBox(height: 8),
            Text(
              supportMessage,
              style: const TextStyle(color: _muted, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          if (flow.stage != RemoteTeachingStage.dialogue ||
              const {
                RemoteGuidedExplorationAct.postAssetObservation,
                RemoteGuidedExplorationAct.deepenReasoning,
                RemoteGuidedExplorationAct.synthesizeDiscovery,
                RemoteGuidedExplorationAct.transferRevisit,
                RemoteGuidedExplorationAct.practiceRepair,
              }.contains(flow.explorationAct)) ...[
            Container(
              key: const ValueKey('student-verification-message'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                StudentLearningNarrative.progressMessage(flow),
                style: const TextStyle(
                  color: Color(0xFF5C437D),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (flow.stage == RemoteTeachingStage.dialogue)
            const Text(
              '请在下方输入框继续表达，AI 老师会根据你的想法追问或安排验证。',
              style: TextStyle(color: Color(0xFF5C437D), fontSize: 12),
            )
          else if (flow.stage == RemoteTeachingStage.asset) ...[
            if (widget.material != null) ...[
              _RemoteMaterialCard(
                material: widget.material!,
                onCompletionChanged: _setAssetReadiness,
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              key: const ValueKey('guided-asset-complete-button'),
              onPressed: canSubmitAsset
                  ? () => unawaited(widget.onAssetComplete!(_assetPayload))
                  : null,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                widget.material == null || widget.assetEventType == null
                    ? '当前素材暂不支持事件上报'
                    : _isAssetReady
                    ? '提交观察并继续'
                    : '请先完成上方操作',
              ),
            ),
          ] else if (flow.stage == RemoteTeachingStage.focus)
            FilledButton.icon(
              key: const ValueKey('guided-start-micro-check-button'),
              onPressed: () => unawaited(widget.onStartMicroCheck()),
              icon: const Icon(Icons.task_alt_rounded, size: 18),
              label: const Text('换个情况试试'),
            )
          else if (flow.stage == RemoteTeachingStage.reflect)
            FilledButton.icon(
              key: const ValueKey('guided-start-reflection-button'),
              onPressed: () => unawaited(widget.onStartReflection()),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('写下反思并完成'),
            ),
        ],
      ),
    );
  }
}

RemoteLearningMaterial? _materialByUsageId(
  List<RemoteLearningMaterial> materials,
  String? usageId,
) {
  if (usageId == null) return null;
  for (final material in materials) {
    if (material.id == usageId) return material;
  }
  return null;
}

/// 组件事件名是前后端约定的传输协议，不携带证据代码；证据含义仍由服务端映射。
String? _completionEventType(String? componentKey) => switch (componentKey) {
  'sign_flip_widget' => 'SIGN_FLIPPED',
  'parabola_widget' => 'PARABOLA_PARAMETERS_COMMITTED',
  'reaction_balance_widget' => 'REACTION_BALANCED',
  'force_motion_widget' => 'FORCE_PARAMETERS_COMMITTED',
  'step_order_widget' => 'STEP_ORDER_VERIFIED',
  'unit_economics_widget' => 'UNIT_ECONOMICS_COMMITTED',
  _ => null,
};

/// 用一条连续轨迹串起每轮问题与发现；轨迹只表达阅读顺序，不推断学习状态。
final class _StudentLearningTimeline extends StatelessWidget {
  const _StudentLearningTimeline({required this.turns});

  final List<Widget> turns;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('student-learning-timeline'),
      children: turns.indexed
          .map(
            (entry) => IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 30,
                    child: Column(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: entry.$1 == turns.length - 1
                                ? _brand
                                : const Color(0xFF49B984),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x226B23FF),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        if (entry.$1 < turns.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: const Color(0xFFDCCBFF),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: entry.$2),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _ExplorationTurnCard extends StatelessWidget {
  const _ExplorationTurnCard({
    required this.node,
    required this.materials,
    required this.isCurrent,
    required this.onOpenWhiteboard,
  });

  final RemoteLearningNode node;
  final List<RemoteLearningMaterial> materials;
  final bool isCurrent;
  final VoidCallback onOpenWhiteboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            key: ValueKey('student-question-${node.id}'),
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.only(left: 56, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0E9FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _studentContributionLabel(node),
                  style: TextStyle(
                    color: _brand,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  node.question,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        _ExplorationClassroom(
          node: node,
          materials: materials,
          isCurrent: isCurrent,
          onOpenWhiteboard: onOpenWhiteboard,
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

final class _ExplorationClassroom extends StatelessWidget {
  const _ExplorationClassroom({
    required this.node,
    required this.materials,
    required this.isCurrent,
    required this.onOpenWhiteboard,
  });

  final RemoteLearningNode node;
  final List<RemoteLearningMaterial> materials;
  final bool isCurrent;
  final VoidCallback onOpenWhiteboard;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = _answerSourceLabel(node);
    return Container(
      constraints: const BoxConstraints(maxWidth: 860),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.white : const Color(0xFFFCFBFE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent ? _brand : const Color(0xFFE5DFEA),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isCurrent ? 'AI 老师回应' : 'AI 老师的引导',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onOpenWhiteboard,
                icon: const Icon(Icons.draw_outlined, size: 16),
                label: const Text('在白板上演示'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '这一轮我们在发现：${_explorationConceptLabel(node)}',
            style: const TextStyle(color: _brand, fontWeight: FontWeight.w800),
          ),
          if (sourceLabel != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EFF8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                sourceLabel,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(node.answer, style: const TextStyle(height: 1.65, fontSize: 16)),
          if (materials.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...materials.map(
              (material) => _RemoteMaterialCard(material: material),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '下一步',
                  style: TextStyle(
                    color: Color(0xFF167A5A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  node.followUpQuestion.replaceFirst('下一步可以追问：', ''),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF175B47),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _studentContributionLabel(RemoteLearningNode node) =>
    switch (node.turnIntent) {
      'ANSWER_TO_TUTOR' => '你的回答',
      'HELP_REQUEST' => '你的困惑',
      'TOPIC_SWITCH' => '你的新问题',
      _ => '你的问题',
    };

final class _RemoteMaterialCard extends StatelessWidget {
  const _RemoteMaterialCard({required this.material, this.onCompletionChanged});

  final RemoteLearningMaterial material;
  final void Function(bool isReady, Map<String, Object?> payload)?
  onCompletionChanged;

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
              _InteractiveLearningMaterial(
                material: material,
                onCompletionChanged: onCompletionChanged,
              )
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
  const _InteractiveLearningMaterial({
    required this.material,
    this.onCompletionChanged,
  });

  final RemoteLearningMaterial material;
  final void Function(bool isReady, Map<String, Object?> payload)?
  onCompletionChanged;

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
  int _hydrogenCoefficient = 2;
  int _oxygenCoefficient = 1;
  int _waterCoefficient = 2;
  double _force = 6;
  double _mass = 2;
  int _oppositeNumber = -3;
  final List<int> _oppositeHistory = [-3];

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
          _slider('a', _a, -2, 2, (value) {
            setState(() => _a = value == 0 ? .1 : value);
            _reportCompletion(true, {'a': _a, 'h': _h, 'k': _k});
          }),
          _slider('h', _h, -3, 3, (value) {
            setState(() => _h = value);
            _reportCompletion(true, {'a': _a, 'h': _h, 'k': _k});
          }),
          _slider('k', _k, -3, 3, (value) {
            setState(() => _k = value);
            _reportCompletion(true, {'a': _a, 'h': _h, 'k': _k});
          }),
        ],
      );
    }
    if (key == 'sign_flip_widget') {
      final completedTwoFlips = _oppositeHistory.length >= 3;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选一个数，再亲手执行“取相反数”。'),
          const SizedBox(height: 4),
          const Text(
            '请连续操作两次，再比较起点和终点。',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [-3, -1, 1, 3]
                .map(
                  (value) => ChoiceChip(
                    label: Text('$value'),
                    selected:
                        _oppositeHistory.length == 1 &&
                        _oppositeNumber == value,
                    onSelected: (_) {
                      setState(() {
                        _oppositeNumber = value;
                        _oppositeHistory
                          ..clear()
                          ..add(value);
                      });
                      _reportCompletion(false, {
                        'startValue': value,
                        'history': List<int>.of(_oppositeHistory),
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          Text(
            _oppositeHistory.join('  →  '),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: _brand,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const ValueKey('sign-flip-apply'),
            onPressed: () {
              setState(() {
                _oppositeNumber = -_oppositeNumber;
                _oppositeHistory.add(_oppositeNumber);
              });
              _reportCompletion(_oppositeHistory.length >= 3, {
                'startValue': _oppositeHistory.first,
                'endValue': _oppositeHistory.last,
                'flipCount': _oppositeHistory.length - 1,
                'history': List<int>.of(_oppositeHistory),
              });
            },
            child: Text('对 $_oppositeNumber 取相反数'),
          ),
          const SizedBox(height: 7),
          Text(
            completedTwoFlips
                ? '观察：终点回到起点。两个负号对应两次方向翻转，符号抵消；绝对值仍照常相乘。'
                : '先完成两次操作：留意每次是否只改变符号，以及第二次后是否回到起点。',
            style: TextStyle(
              fontSize: 12,
              color: completedTwoFlips ? const Color(0xFF167A5A) : _muted,
              fontWeight: completedTwoFlips
                  ? FontWeight.w700
                  : FontWeight.normal,
            ),
          ),
        ],
      );
    }
    if (key == 'reaction_balance_widget') {
      final hydrogenBalanced =
          _hydrogenCoefficient * 2 == _waterCoefficient * 2;
      final oxygenBalanced = _oxygenCoefficient * 2 == _waterCoefficient;
      final balanced = hydrogenBalanced && oxygenBalanced;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('只改系数，不改 H₂、O₂、H₂O 里的右下角数字。'),
          const SizedBox(height: 10),
          Text(
            '${_hydrogenCoefficient}H₂ + ${_oxygenCoefficient}O₂ → ${_waterCoefficient}H₂O',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _brand,
            ),
          ),
          const SizedBox(height: 10),
          _coefficientPicker('H₂', _hydrogenCoefficient, (value) {
            setState(() => _hydrogenCoefficient = value);
            _reportReactionReadiness();
          }),
          _coefficientPicker('O₂', _oxygenCoefficient, (value) {
            setState(() => _oxygenCoefficient = value);
            _reportReactionReadiness();
          }),
          _coefficientPicker('H₂O', _waterCoefficient, (value) {
            setState(() => _waterCoefficient = value);
            _reportReactionReadiness();
          }),
          const SizedBox(height: 8),
          Text(
            '左侧 H ${_hydrogenCoefficient * 2} / O ${_oxygenCoefficient * 2}；右侧 H ${_waterCoefficient * 2} / O $_waterCoefficient',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 6),
          Text(
            balanced ? '已配平：两种元素的原子数都守恒。' : '还未配平：先找出哪一种元素的原子数不相等。',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: balanced
                  ? const Color(0xFF167A5A)
                  : const Color(0xFF9A5B00),
            ),
          ),
        ],
      );
    }
    if (key == 'force_motion_widget') {
      final acceleration = _force / _mass;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前加速度 a = F ÷ m = ${acceleration.toStringAsFixed(1)} m/s²',
            style: const TextStyle(fontWeight: FontWeight.w900, color: _brand),
          ),
          const SizedBox(height: 8),
          _slider('合力 F', _force, 1, 16, (value) {
            setState(() => _force = value);
            _reportCompletion(true, {
              'force': _force,
              'mass': _mass,
              'acceleration': _force / _mass,
            });
          }),
          _slider('质量 m', _mass, 1, 8, (value) {
            setState(() => _mass = value);
            _reportCompletion(true, {
              'force': _force,
              'mass': _mass,
              'acceleration': _force / _mass,
            });
          }),
          const SizedBox(height: 5),
          const Text(
            '保持一个量不变，只改另一个量：你能预测加速度会怎样变吗？',
            style: TextStyle(fontSize: 12, color: _muted),
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
          _slider('单价', _price, 10, 50, (value) {
            setState(() => _price = value);
            _reportBusinessReadiness();
          }),
          _slider('订单', _orders, 20, 300, (value) {
            setState(() => _orders = value);
            _reportBusinessReadiness();
          }),
          _slider('单杯变动成本', _cost, 3, 25, (value) {
            setState(() => _cost = value);
            _reportBusinessReadiness();
          }),
        ],
      );
    }
    return _slider('验证参数', _a, -2, 2, (value) {
      setState(() => _a = value);
      _reportCompletion(true, {'value': _a});
    });
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

  Widget _coefficientPicker(
    String label,
    int selected,
    ValueChanged<int> onSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text('$label 系数', style: const TextStyle(fontSize: 12)),
          ...[1, 2, 3, 4].map(
            (value) => ChoiceChip(
              label: Text('$value'),
              selected: value == selected,
              onSelected: (_) => onSelected(value),
            ),
          ),
        ],
      ),
    );
  }

  void _reportCompletion(bool isReady, Map<String, Object?> payload) {
    widget.onCompletionChanged?.call(isReady, payload);
  }

  void _reportReactionReadiness() {
    final isBalanced =
        _hydrogenCoefficient * 2 == _waterCoefficient * 2 &&
        _oxygenCoefficient * 2 == _waterCoefficient;
    _reportCompletion(isBalanced, {
      'hydrogenCoefficient': _hydrogenCoefficient,
      'oxygenCoefficient': _oxygenCoefficient,
      'waterCoefficient': _waterCoefficient,
      'isBalanced': isBalanced,
    });
  }

  void _reportBusinessReadiness() {
    _reportCompletion(true, {
      'price': _price,
      'orders': _orders,
      'variableCost': _cost,
      'contributionMargin': (_price - _cost) * _orders,
    });
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

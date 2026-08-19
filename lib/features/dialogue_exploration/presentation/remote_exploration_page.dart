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
import '../core/teacher_agent_test_seed.dart';
import 'exploration_node_map.dart';
import 'guided_practice_dialog.dart';
import 'next_learning_options_sheet.dart';
import 'student_learning_narrative.dart';
import 'technical_trace.dart';
import 'technical_trace_drawer.dart';
import 'classroom_board_catalog.dart';
import 'classroom_remediation_panel.dart';
import 'inline_practice_panel.dart';
import '../adapters/teaching_architecture_dto.dart';
import 'intro_chat_messages.dart';
import 'teaching_mode_selection_stage.dart';

const _brand = Color(0xFF6B23FF);
const _ink = Color(0xFF27222D);
const _muted = Color(0xFF6F6977);
const _surface = Color(0xFFF7F5FA);
const _studentBubbleFill = Color(0xFFDBEAFE);
const _studentBubbleBorder = Color(0xFF2563EB);
const _studentBubbleInk = Color(0xFF1E3A8A);
const _teacherBubbleFill = Color(0xFFFFFBF5);
const _teacherBubbleBorder = Color(0xFFE8DFD0);

String _studentFriendlyRepairFocus(String value) {
  if (value.contains('系数') ||
      value.contains('下标') ||
      value.contains('原子') ||
      value.contains('守恒')) {
    return '右下角的小数字决定它是什么物质，不能修改；前面的数字表示有几份，可以调整。';
  }
  return value;
}

String _studentMaterialCaption(RemoteLearningMaterial material) {
  final raw =
      material.payload['description']?.toString().trim() ?? material.title;
  if (raw.contains('Mock') || raw.contains('教研素材')) {
    return _defaultMaterialCaption(material);
  }
  return raw;
}

String _defaultMaterialCaption(RemoteLearningMaterial material) {
  return switch (material.materialId) {
    'chemistry-particle-figure' => '反应前 H、O 原子分开存在；反应后重新组合成 H₂O，原子种类和数量不变。',
    'chemistry-conservation-formula' => '对每种元素分别统计：反应前原子总数 = 反应后原子总数。',
    'chemistry-reaction-video' => '比较密闭与敞口容器中，反应前后称量结果有何不同。',
    _ => material.title,
  };
}

List<RemoteLearningMaterial> _dialogueTimelineMaterials(
  List<RemoteLearningMaterial> materials,
  RemoteTeachingFlow? teachingFlow,
  bool isCurrent,
) {
  if (teachingFlow == null) return const [];
  if (teachingFlow.stage == RemoteTeachingStage.asset && isCurrent) {
    return materials;
  }
  return materials
      .where((material) => material.type == 'INTERACTIVE')
      .toList(growable: false);
}

String _studentFriendlyFollowUp(String value) {
  if (value.contains('系数') && (value.contains('原子') || value.contains('配平'))) {
    return '看看箭头两边：哪一种原子的数量不同？先从它开始调整。';
  }
  return value;
}

typedef _LessonProgressInfo = ({
  String title,
  int currentStep,
  int totalSteps,
  String stepLabel,
});

_LessonProgressInfo _lessonProgressInfo(
  RemoteLearningSessionSnapshot snapshot,
) {
  final flow = snapshot.teachingFlow;
  final proc = snapshot.processSchedulerState?.currentPhase;
  final guidanceLabel = snapshot.studentGuidance?.stageLabel.trim();
  final practiceTitle = flow?.activePractice?.title.trim();
  final title = (practiceTitle != null && practiceTitle.isNotEmpty)
      ? practiceTitle
      : (flow != null && flow.goal.trim().isNotEmpty
            ? flow.goal
            : snapshot.session.topic);
  const totalSteps = 4;
  var step = 1;
  var stepLabel = '说说你的理解';
  switch (proc) {
    case RemoteTeachingPhase.modeSelection:
    case RemoteTeachingPhase.conceptIntroduction:
      step = 1;
      stepLabel = '说说你的理解';
    case RemoteTeachingPhase.example:
      step = 2;
      stepLabel = '动手试一试';
    case RemoteTeachingPhase.extraSupport:
      step = flow?.stage == RemoteTeachingStage.focus ? 3 : 2;
      stepLabel = step == 3 ? '独立验证' : '换个方法理解';
    case RemoteTeachingPhase.understandingCheck:
      step = 3;
      stepLabel = '独立验证';
    case RemoteTeachingPhase.goalComplete:
      step = 4;
      stepLabel = '本章完成';
    default:
      step = switch (flow?.stage) {
        RemoteTeachingStage.asset => 2,
        RemoteTeachingStage.focus => 3,
        RemoteTeachingStage.reflect => 4,
        _ => 1,
      };
      stepLabel = switch (flow?.stage) {
        RemoteTeachingStage.asset => '动手试一试',
        RemoteTeachingStage.focus => '独立验证',
        RemoteTeachingStage.reflect => '总结发现',
        _ => '说说你的理解',
      };
  }
  if (guidanceLabel != null && guidanceLabel.isNotEmpty) {
    stepLabel = guidanceLabel;
  }
  return (
    title: title,
    currentStep: step,
    totalSteps: totalSteps,
    stepLabel: stepLabel,
  );
}

String _classroomTaskTitle(
  RemoteLearningMaterial? material,
  RemoteTeachingFlow flow,
) {
  if (material?.componentKey == 'reaction_balance_widget') {
    return '配平 H₂ + O₂ → H₂O';
  }
  if (material?.componentKey == 'set_membership_widget') {
    return '判断元素 ∈ / ∉ 集合';
  }
  final materialTitle = material?.title.trim();
  if (materialTitle != null && materialTitle.isNotEmpty) {
    return materialTitle;
  }
  return flow.goal.trim().isNotEmpty ? flow.goal : '课堂任务';
}

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
    await _controller.loadHistory(restoreLatestActive: false);
    if (!mounted) return;
    // 账号历史是恢复会话的事实来源；加载失败时必须停留在错误态，不能继续创建空白入口。
    if (_controller.state.status == RemoteExplorationStatus.failed) {
      setState(() => _initializing = false);
      return;
    }
    if (_controller.state.snapshot == null) {
      _catalogRequested = true;
      await _controller.loadChapterCatalog();
      if (TeacherAgentTestSeed.shouldAutoLoadChapter) {
        await _controller.loadChapter(TeacherAgentTestSeed.chapterId);
        await _controller.startChapterGreetingSession();
      }
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
        title: Text(state.chapter?.title ?? '1.2 AI 探索课堂'),
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
                          busy:
                              state.status ==
                                  RemoteExplorationStatus.submitting ||
                              state.status ==
                                  RemoteExplorationStatus.loadingEntry,
                          errorMessage:
                              state.status == RemoteExplorationStatus.failed
                              ? state.errorMessage
                              : null,
                          onRetry: _controller.retry,
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
  final _guidedActionPanelKey = GlobalKey<_GuidedTeachingActionPanelState>();
  Timer? _timingTicker;
  Timer? _extraSupportAutoAdvanceTimer;
  String? _extraSupportAutoAdvanceKey;
  String? _inspectedBoardId;
  String? _lastActiveBoardId;

  bool _needsExtraSupportRepairAck(RemoteLearningSessionSnapshot? snapshot) {
    final flow = snapshot?.teachingFlow;
    if (flow?.explorationAct != RemoteGuidedExplorationAct.practiceRepair) {
      return false;
    }
    return flow?.stage == RemoteTeachingStage.dialogue ||
        flow?.stage == RemoteTeachingStage.focus;
  }

  void _maybeScheduleExtraSupportAutoAdvance() {
    final snapshot = widget.controller.state.snapshot;
    if (!_needsExtraSupportRepairAck(snapshot)) {
      _extraSupportAutoAdvanceKey = null;
      return;
    }
    final flow = snapshot?.teachingFlow;
    final key =
        '${snapshot?.session.id}:${flow?.updatedAt}:${flow?.stage.name}';
    if (_extraSupportAutoAdvanceKey == key) return;
    _extraSupportAutoAdvanceKey = key;
    _scheduleExtraSupportAutoAdvance();
  }

  void _scheduleExtraSupportAutoAdvance() {
    _extraSupportAutoAdvanceTimer?.cancel();
    _extraSupportAutoAdvanceTimer = Timer(
      const Duration(milliseconds: 2800),
      () {
        if (!mounted) return;
        if (!_needsExtraSupportRepairAck(widget.controller.state.snapshot)) {
          return;
        }
        unawaited(_acknowledgeExtraSupportRepair(autoOpenPractice: false));
      },
    );
  }

  Future<void> _acknowledgeExtraSupportRepair({
    bool autoOpenPractice = false,
  }) async {
    _extraSupportAutoAdvanceTimer?.cancel();
    _extraSupportAutoAdvanceKey = null;
    await widget.controller.submitQuestion('继续', force: true);
    if (!mounted || !autoOpenPractice) return;
    if (widget.controller.state.status == RemoteExplorationStatus.failed) {
      return;
    }
    final snapshot = widget.controller.state.snapshot;
    if (snapshot?.capabilities?.canSubmitPractice == true) {
      await _showGuidedPractice();
    }
  }

  @override
  void initState() {
    super.initState();
    _lastActiveBoardId =
        widget.controller.state.snapshot?.teachingArchitecture?.activeBoardId;
    widget.controller.addListener(_refresh);
    _timingTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.syncModeSelectionIfNeeded());
    });
  }

  void _refresh() {
    if (!mounted) return;
    final nextActiveBoardId =
        widget.controller.state.snapshot?.teachingArchitecture?.activeBoardId;
    final wasFollowingPreviousActiveBoard =
        _inspectedBoardId != null && _inspectedBoardId == _lastActiveBoardId;
    // 服务端会重新投影画板 ID；原本跟随当前进度时必须切到新的活动画板，避免误落入同 ID 的历史板。
    if (nextActiveBoardId != _lastActiveBoardId &&
        wasFollowingPreviousActiveBoard) {
      _inspectedBoardId = null;
    }
    _lastActiveBoardId = nextActiveBoardId;
    setState(() {});
    _maybeScheduleExtraSupportAutoAdvance();
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
    _inspectedBoardId = null;
    _lastActiveBoardId =
        widget.controller.state.snapshot?.teachingArchitecture?.activeBoardId;
  }

  @override
  void dispose() {
    _timingTicker?.cancel();
    _extraSupportAutoAdvanceTimer?.cancel();
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
        leading: IconButton(
          key: const ValueKey('prestudy-back-to-overview'),
          tooltip: '返回章节目录',
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
              return PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (value) {
                  if (value == 'trace') {
                    Scaffold.of(scaffoldContext).openEndDrawer();
                  } else if (value == 'export') {
                    unawaited(_exportTree());
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'trace', child: Text('查看课堂记录')),
                  PopupMenuItem(value: 'export', child: Text('导出学习记录')),
                ],
              );
            },
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
                if (snapshot.teachingFlow == null)
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
    if (widget.controller.shouldUseSidebarClassroom(snapshot)) {
      return _sidebarClassroomStage(snapshot, mobile: mobile);
    }
    return _legacyClassroomStage(snapshot, mobile: mobile);
  }

  Widget _sidebarClassroomStage(
    RemoteLearningSessionSnapshot snapshot, {
    required bool mobile,
  }) {
    final state = widget.controller.state;
    final focusBoardId = ClassroomBoardCatalog.resolveFocusBoardId(
      snapshot,
      _inspectedBoardId,
    );
    final focusBoard = focusBoardId == null
        ? null
        : snapshot.teachingArchitecture?.boardById(focusBoardId);
    final focusParentBoard = focusBoard?.parentBoardId == null
        ? null
        : snapshot.teachingArchitecture?.boardById(focusBoard!.parentBoardId);
    final focusNodeId = state.inspectedNodeId ?? snapshot.currentNodeId!;
    final isCurrentBoard =
        focusBoard?.isActive ??
        (focusBoardId == null && focusNodeId == snapshot.currentNodeId);
    final isReviewingHistory = focusBoard != null && !isCurrentBoard;
    final guidance = snapshot.studentGuidance;
    final teachingFlow = snapshot.teachingFlow;
    final guidedMaterial = teachingFlow == null
        ? null
        : _materialByUsageId(
            snapshot.materials,
            teachingFlow.currentAction.materialUsageId,
          );
    final guidedEventType = _completionEventType(guidedMaterial?.componentKey);
    final awaitingModeSelection = widget.controller.shouldShowModeSelection(
      snapshot,
    );
    final showModeOptions =
        isCurrentBoard && (guidance?.showModeSelection ?? false);
    final inIntro = widget.controller.isModeSelectionIntro(snapshot);
    final modeOptions = widget.controller.resolvedModeMenuOptions(snapshot);
    if (modeOptions.isEmpty &&
        !inIntro &&
        awaitingModeSelection &&
        isCurrentBoard) {
      return _StaleSessionRestartPanel(
        onRestart: () => unawaited(_backToOverview()),
      );
    }
    final topic = snapshot.session.topic.trim();
    final topicLabel = topic.isEmpty ? '本节课内容' : topic;
    final resolvedOptions = modeOptions.isNotEmpty
        ? modeOptions
        : TeachingModeOptionCatalog.forTopic(topicLabel);
    final flow = teachingFlow;
    final introPrompt = inIntro ? flow?.currentAction.prompt.trim() : null;
    final actionHint = guidance?.actionHint.trim();
    final trailingPrompt = (introPrompt != null && introPrompt.isNotEmpty)
        ? introPrompt
        : (actionHint != null && actionHint.isNotEmpty ? actionHint : null);
    final messages = focusBoardId != null
        ? ClassroomBoardCatalog.messagesForBoard(
            snapshot,
            focusBoardId,
            trailingTeacherPrompt: isCurrentBoard ? trailingPrompt : null,
            modeSelectionPrompt: guidance?.modeSelectionPrompt,
            appendModePrompt: showModeOptions,
            liveTeachingFlow: isCurrentBoard ? teachingFlow : null,
          )
        : ClassroomBoardCatalog.messagesForNode(
            snapshot,
            focusNodeId,
            trailingTeacherPrompt: isCurrentBoard ? trailingPrompt : null,
            modeSelectionPrompt: guidance?.modeSelectionPrompt,
            appendModePrompt: showModeOptions,
            liveTeachingFlow: isCurrentBoard ? teachingFlow : null,
          );
    final submitting = state.status == RemoteExplorationStatus.submitting;
    final needsRepairAck = _needsExtraSupportRepairAck(snapshot);
    final showClassroomBottom =
        isCurrentBoard &&
        !state.isReadOnly &&
        !showModeOptions &&
        !(guidance?.showPracticeArea == true &&
            teachingFlow?.stage == RemoteTeachingStage.focus) &&
        (needsRepairAck ||
            guidance?.showMaterialArea == true ||
            snapshot.capabilities?.canSubmitMaterial == true ||
            snapshot.capabilities?.canComplete == true);
    final isSupportDialogue =
        isCurrentBoard &&
        focusBoard?.kind == 'SUPPORT_BRANCH' &&
        teachingFlow?.stage == RemoteTeachingStage.dialogue;
    final showReplyBar =
        isCurrentBoard &&
        !state.isReadOnly &&
        !showModeOptions &&
        !showClassroomBottom &&
        !isSupportDialogue &&
        widget.controller.canSubmitEntryDialogue(snapshot);

    void inspectBoard(String boardId) {
      final board = snapshot.teachingArchitecture?.boardById(boardId);
      final shouldFollowCurrent = board?.isActive == true;
      setState(() {
        _inspectedBoardId = shouldFollowCurrent ? null : boardId;
      });
      if (shouldFollowCurrent && snapshot.currentNodeId != null) {
        widget.controller.inspectNode(snapshot.currentNodeId!);
      }
    }

    return TeachingModeSelectionStage(
      topicLabel: topicLabel,
      historyEntries: ClassroomBoardCatalog.historyEntries(snapshot),
      selectedHistoryNodeId: focusNodeId,
      selectedHistoryBoardId: focusBoardId,
      boardPanelTitle: focusBoard == null
          ? null
          : ClassroomBoardCatalog.boardPanelTitle(
              focusBoard,
              isModeSelectionIntro: inIntro && isCurrentBoard,
              parentBoard: focusParentBoard,
            ),
      emptyConversationLabel: isReviewingHistory && messages.isEmpty
          ? '这个阶段没有单独保存聊天内容，请查看下方的阶段说明。'
          : null,
      onBoardTap: inspectBoard,
      isReviewingHistory: isReviewingHistory,
      onReturnToCurrent: isReviewingHistory
          ? () {
              setState(() => _inspectedBoardId = null);
              final currentNodeId = snapshot.currentNodeId;
              if (currentNodeId != null) {
                widget.controller.inspectNode(currentNodeId);
              }
            }
          : null,
      options: resolvedOptions,
      messages: messages,
      showOptions: showModeOptions,
      submitting: submitting,
      teacherTyping: submitting,
      showReplyBar: showReplyBar,
      onSendMessage: (text) => widget.controller.submitQuestion(text),
      onSelect: (skill) =>
          unawaited(widget.controller.selectTeachingMode(skill)),
      onHistoryTap: (nodeId) {
        final boardId = ClassroomBoardCatalog.boardIdForNode(snapshot, nodeId);
        if (boardId != null) {
          inspectBoard(boardId);
        } else {
          setState(() => _inspectedBoardId = null);
          widget.controller.inspectNode(nodeId);
        }
      },
      mobile: mobile,
      guidedPanel: isReviewingHistory
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                mobile ? 12 : 20,
                0,
                mobile ? 12 : 20,
                8,
              ),
              child: _HistoricalBoardSnapshotPanel(
                snapshot: snapshot,
                board: focusBoard,
              ),
            )
          : teachingFlow != null
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                mobile ? 12 : 20,
                0,
                mobile ? 12 : 20,
                8,
              ),
              child: _GuidedTeachingActionPanel(
                key: _guidedActionPanelKey,
                snapshot: snapshot,
                focusBoard: focusBoard,
                isCurrentBoard: isCurrentBoard,
                flow: teachingFlow,
                guidance: guidance,
                capabilities: snapshot.capabilities,
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
                onSkipMaterial:
                    guidedMaterial == null ||
                        snapshot.capabilities?.canSkipMaterial != true
                    ? null
                    : () => widget.controller.submitMaterialEvent(
                        materialUsageId: guidedMaterial.id,
                        eventType: 'MATERIAL_SKIPPED',
                        payload: const {'reason': 'student_requested'},
                      ),
                onSubmitPractice: _submitGuidedPractice,
                onSendMessage: (text) => widget.controller.submitQuestion(text),
                onStartReflection: _complete,
              ),
            )
          : null,
      classroomBottomBar: showClassroomBottom
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.status == RemoteExplorationStatus.failed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: _ErrorPanel(
                      message: state.errorMessage ?? '发送失败',
                      onRetry: widget.controller.retry,
                    ),
                  ),
                _ClassroomBottomBar(
                  snapshot: snapshot,
                  controller: widget.controller,
                  inputController: _inputController,
                  onSend: _send,
                  onAskHelp: _askTeacherForHelp,
                  onComplete: _completeCurrentStep,
                ),
              ],
            )
          : null,
    );
  }

  Widget _legacyClassroomStage(
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
    final awaitingModeSelection = widget.controller.shouldShowModeSelection(
      snapshot,
    );
    final showEntryDialogue = widget.controller.shouldShowEntryDialogue(
      snapshot,
    );
    final modeOptions = widget.controller.resolvedModeMenuOptions(snapshot);
    if (showEntryDialogue) {
      final guidance = snapshot.studentGuidance;
      final inIntro = widget.controller.isModeSelectionIntro(snapshot);
      if (modeOptions.isEmpty && !inIntro && awaitingModeSelection) {
        return _StaleSessionRestartPanel(
          onRestart: () => unawaited(_backToOverview()),
        );
      }
      final topic = snapshot.session.topic.trim();
      final topicLabel = topic.isEmpty ? '本节课内容' : topic;
      final resolvedOptions = modeOptions.isNotEmpty
          ? modeOptions
          : TeachingModeOptionCatalog.forTopic(topicLabel);
      final actionHint = guidance?.actionHint.trim();
      final flow = snapshot.teachingFlow;
      final introPrompt = inIntro ? flow?.currentAction.prompt.trim() : null;
      final trailingPrompt = (introPrompt != null && introPrompt.isNotEmpty)
          ? introPrompt
          : (actionHint != null && actionHint.isNotEmpty ? actionHint : null);
      final messages = IntroChatMessage.fromSessionPath(
        path,
        trailingTeacherPrompt: trailingPrompt,
        modeSelectionPrompt: guidance?.modeSelectionPrompt,
        appendModePrompt: guidance?.showModeSelection ?? false,
      );
      final submitting = state.status == RemoteExplorationStatus.submitting;
      return TeachingModeSelectionStage(
        topicLabel: topicLabel,
        historyEntries: TeachingModeOptionCatalog.fromSessionPath(path),
        options: resolvedOptions,
        messages: messages,
        showOptions: guidance?.showModeSelection ?? false,
        submitting: submitting,
        teacherTyping: submitting,
        showReplyBar: widget.controller.canSubmitEntryDialogue(snapshot),
        onSendMessage: (text) => widget.controller.submitQuestion(text),
        onSelect: (skill) =>
            unawaited(widget.controller.selectTeachingMode(skill)),
        onHistoryTap: widget.controller.inspectNode,
        mobile: mobile,
      );
    }
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
              if (teachingFlow != null)
                _LessonProgressHeader(snapshot: snapshot)
              else
                _ClassroomGuideHeader(
                  topic: snapshot.session.topic,
                  hookQuestion: path.isNotEmpty
                      ? path.first.question
                      : node.question,
                ),
              const SizedBox(height: 14),
              if (teachingFlow == null && guidance != null) ...[
                _PreStudyTimingCue(guidance: guidance),
                const SizedBox(height: 14),
              ],
              if (widget.controller.isLegacyBrokenSession(snapshot)) ...[
                _StaleSessionRestartPanel(
                  onRestart: () => unawaited(_backToOverview()),
                ),
                const SizedBox(height: 14),
              ],
              _StudentLearningTimeline(
                turns: [
                  ...path.indexed.map(
                    (entry) => _ExplorationTurnCard(
                      node: entry.$2,
                      isCurrent: entry.$2.id == node.id,
                      teachingFlow: teachingFlow,
                      materials: snapshot.materials
                          .where((item) {
                            if (item.nodeId != entry.$2.id) return false;
                            if (item.id == activeGuidedMaterialId) {
                              return false;
                            }
                            // 当前节点离开 ASSET 后，素材改由下方引导面板展示，避免与对话提示叠在一起。
                            if (entry.$2.id == snapshot.currentNodeId &&
                                teachingFlow != null &&
                                teachingFlow.stage !=
                                    RemoteTeachingStage.asset) {
                              return false;
                            }
                            return true;
                          })
                          .toList(growable: false),
                      onOpenWhiteboard: () => _openWhiteboard(entry.$2),
                    ),
                  ),
                  if (teachingFlow != null)
                    _GuidedTeachingActionPanel(
                      key: _guidedActionPanelKey,
                      flow: teachingFlow,
                      guidance: snapshot.studentGuidance,
                      capabilities: snapshot.capabilities,
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
                      onSkipMaterial:
                          guidedMaterial == null ||
                              snapshot.capabilities?.canSkipMaterial != true
                          ? null
                          : () => widget.controller.submitMaterialEvent(
                              materialUsageId: guidedMaterial.id,
                              eventType: 'MATERIAL_SKIPPED',
                              payload: const {'reason': 'student_requested'},
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
        if (!state.isReadOnly &&
            !awaitingModeSelection &&
            !(snapshot.studentGuidance?.showModeSelection ?? false))
          _ClassroomBottomBar(
            snapshot: snapshot,
            controller: widget.controller,
            inputController: _inputController,
            onSend: _send,
            onAskHelp: _askTeacherForHelp,
            onComplete: _completeCurrentStep,
          ),
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
    if (widget.controller.state.status == RemoteExplorationStatus.failed) {
      return false;
    }
    final snapshot = widget.controller.state.snapshot;
    final proc = snapshot?.processSchedulerState;
    final flow = snapshot?.teachingFlow;
    final course = snapshot?.courseState;
    final mastered =
        course?.practiceResult == 'MASTERED' ||
        proc?.currentPhase == RemoteTeachingPhase.conceptIntroduction ||
        proc?.currentPhase == RemoteTeachingPhase.goalComplete;
    if (!mastered && _needsExtraSupportRepairAck(snapshot)) {
      _scheduleExtraSupportAutoAdvance();
    } else if (!mastered &&
        flow?.feedback?.trim().isNotEmpty == true &&
        mounted) {
      final feedback = flow!.feedback!.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI 老师：$feedback'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    return true;
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

  Future<void> _askTeacherForHelp() async {
    final snapshot = widget.controller.state.snapshot;
    final caps = snapshot?.capabilities;
    if (caps?.canSkipMaterial == true) {
      _guidedActionPanelKey.currentState?.requestHelp();
      return;
    }
    _inputController.text = '我有疑问，请再解释一下';
    await _send();
  }

  Future<void> _completeCurrentStep() async {
    final snapshot = widget.controller.state.snapshot;
    final caps = snapshot?.capabilities;
    if (_needsExtraSupportRepairAck(snapshot)) {
      await _acknowledgeExtraSupportRepair(autoOpenPractice: false);
      return;
    }
    if (caps?.canSubmitMaterial == true) {
      await _guidedActionPanelKey.currentState?.submitAssetIfReady();
      return;
    }
    if (caps?.canSubmitPractice == true) {
      await _showGuidedPractice();
      return;
    }
    if (caps?.canComplete == true) {
      await _complete();
      return;
    }
    if (caps?.canSubmitText == true) {
      _inputController.text = '我完成了，可以继续';
      await _send();
    }
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

String _teacherMessageForNode(
  RemoteLearningNode node, {
  RemoteTeachingFlow? flow,
  required bool isCurrent,
}) {
  final answer = node.answer.trim();
  if (answer.isNotEmpty) {
    return answer;
  }
  if (!isCurrent || flow == null) return '';
  final feedback = flow.feedback?.trim();
  if (feedback != null && feedback.isNotEmpty) return feedback;
  return flow.currentAction.prompt.trim();
}

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

/// 顶部进度条：课程标题 + 当前步骤 / 总步骤。
final class _LessonProgressHeader extends StatelessWidget {
  const _LessonProgressHeader({required this.snapshot});

  final RemoteLearningSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final info = _lessonProgressInfo(snapshot);
    final progress = info.currentStep / info.totalSteps;
    return Container(
      key: const ValueKey('lesson-progress-header'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DFEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  info.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                '进度 ${info.currentStep}/${info.totalSteps} 步',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFEDE8F5),
              color: _brand,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '当前：${info.stepLabel}',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
    );
  }
}

/// AI 老师左对齐气泡，与任务卡片分离。
final class _TeacherChatBubble extends StatelessWidget {
  const _TeacherChatBubble({required this.message, this.compact = false});

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: _brand,
            child: Icon(Icons.school_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 16,
                compact ? 10 : 14,
                compact ? 12 : 16,
                compact ? 10 : 14,
              ),
              decoration: BoxDecoration(
                color: _teacherBubbleFill,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: _teacherBubbleBorder),
                boxShadow: const [
                  BoxShadow(color: _brand, offset: Offset(-3, 0)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI 老师',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: _brand,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message.trim(),
                    style: TextStyle(
                      height: 1.55,
                      fontSize: compact ? 14 : 16,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _classroomInputHint(
  RemoteLearningSessionSnapshot snapshot, {
  required bool canType,
}) {
  if (canType) return '写下你的想法或疑问…';
  final stage = snapshot.teachingFlow?.stage;
  if (stage == RemoteTeachingStage.asset) {
    return '请先完成上方课堂任务，再回来继续对话';
  }
  if (stage == RemoteTeachingStage.focus) {
    return '请先点击「开始验证」完成独立练习';
  }
  return '当前阶段请使用页面上方的操作按钮继续';
}

String _classroomInputBlockedReason(RemoteLearningSessionSnapshot snapshot) {
  final stage = snapshot.teachingFlow?.stage;
  if (stage == RemoteTeachingStage.asset) {
    return '互动探索阶段：先完成上方 ∈/∉ 判断任务，再提交并继续。';
  }
  if (stage == RemoteTeachingStage.focus) {
    return '独立验证阶段：请点击上方「开始作答」或底部「开始验证」。';
  }
  return '当前请先完成页面上方的课堂任务。';
}

/// 底部固定输入区：文本 + 「我有疑问」「我完成了」快捷按钮。
final class _ClassroomBottomBar extends StatelessWidget {
  const _ClassroomBottomBar({
    required this.snapshot,
    required this.controller,
    required this.inputController,
    required this.onSend,
    required this.onAskHelp,
    required this.onComplete,
  });

  final RemoteLearningSessionSnapshot snapshot;
  final RemoteExplorationSessionController controller;
  final TextEditingController inputController;
  final Future<void> Function() onSend;
  final Future<void> Function() onAskHelp;
  final Future<void> Function() onComplete;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final busy = state.status == RemoteExplorationStatus.submitting;
    final caps = snapshot.capabilities;
    final canType = caps?.canSubmitText ?? true;
    final inputHint = _classroomInputHint(snapshot, canType: canType);
    final canComplete =
        caps?.canSubmitMaterial == true ||
        caps?.canSubmitPractice == true ||
        caps?.canComplete == true ||
        canType ||
        _needsExtraSupportRepairAck(snapshot);
    return Material(
      key: const ValueKey('classroom-bottom-bar'),
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('remote-question-input'),
                      controller: inputController,
                      minLines: 1,
                      maxLines: 3,
                      enabled: canType && !busy,
                      onSubmitted: canType && !busy ? (_) => onSend() : null,
                      decoration: InputDecoration(
                        hintText: inputHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        filled: !canType,
                        fillColor: canType ? null : const Color(0xFFF7F5FA),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey('remote-send-question'),
                    onPressed: canType && !busy ? onSend : null,
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
              if (!canType) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _classroomInputBlockedReason(snapshot),
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
              ],
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('classroom-ask-help-button'),
                    onPressed: busy ? null : () => unawaited(onAskHelp()),
                    icon: const Icon(Icons.help_outline_rounded, size: 18),
                    label: const Text('我有疑问'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('classroom-complete-step-button'),
                    onPressed: busy || !canComplete
                        ? null
                        : () => unawaited(onComplete()),
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: Text(_completeButtonLabel(caps)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _completeButtonLabel(RemoteCourseCapabilities? caps) {
    if (caps?.canSubmitMaterial == true) return '提交并继续';
    if (caps?.canSubmitPractice == true) return '开始验证';
    if (caps?.canComplete == true) return '完成总结';
    final snapshot = controller.state.snapshot;
    if (_needsExtraSupportRepairAck(snapshot)) return '听懂了，继续巩固';
    return '我完成了';
  }

  bool _needsExtraSupportRepairAck(RemoteLearningSessionSnapshot? snapshot) {
    final flow = snapshot?.teachingFlow;
    if (flow?.explorationAct != RemoteGuidedExplorationAct.practiceRepair) {
      return false;
    }
    return flow?.stage == RemoteTeachingStage.dialogue ||
        flow?.stage == RemoteTeachingStage.focus;
  }
}

/// 一次课堂只把当前认知关口放在台前；历史过程收进探索地图，避免退化为聊天记录。
/// 对话区保留学生自己提出的问题和 AI 的反问，让每一轮都能回看并继续分支。
final class _ClassroomGuideHeader extends StatelessWidget {
  const _ClassroomGuideHeader({
    required this.topic,
    required this.hookQuestion,
  });

  final String topic;
  final String hookQuestion;

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
                  hookQuestion,
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

/// 历史画板使用所属素材和练习快照完整回放，不复用当前教学动作，避免回看时内容串台或只剩标题。
final class _HistoricalBoardSnapshotPanel extends StatelessWidget {
  const _HistoricalBoardSnapshotPanel({
    required this.snapshot,
    required this.board,
  });

  final RemoteLearningSessionSnapshot snapshot;
  final RemoteTeachingBoardSnapshot board;

  @override
  Widget build(BuildContext context) {
    final architecture = snapshot.teachingArchitecture;
    final parentBoard = board.parentBoardId == null
        ? null
        : architecture?.boardById(board.parentBoardId);
    final replayBoards =
        board.kind == 'SUPPORT_BRANCH' && parentBoard?.kind == 'CHECK'
        ? [parentBoard!, board]
        : [board];
    final materialsById = <String, RemoteLearningMaterial>{};
    final practicesById = <String, RemoteLearningPracticeNode>{};
    for (final replayBoard in replayBoards) {
      for (final material in ClassroomBoardCatalog.materialsForBoard(
        snapshot,
        replayBoard,
      )) {
        materialsById[material.id] = material;
      }
      final practice = ClassroomBoardCatalog.practiceForBoard(
        snapshot,
        replayBoard,
      );
      if (practice != null) practicesById[practice.id] = practice;
    }
    final materials = materialsById.values.toList(growable: false);
    final practices = practicesById.values.toList(growable: false);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: SingleChildScrollView(
        key: const ValueKey('historical-board-snapshot-panel'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (materials.isEmpty && practices.isEmpty)
              _HistoricalBoardOverviewCard(board: board),
            for (final material in materials)
              _HistoricalMaterialCard(material: material),
            for (final practice in practices)
              _HistoricalPracticeCard(practice: practice),
          ],
        ),
      ),
    );
  }
}

/// 没有独立对话或素材的历史阶段仍展示真实课程信息，避免误回退成“请和老师打招呼”的空白开场。
final class _HistoricalBoardOverviewCard extends StatelessWidget {
  const _HistoricalBoardOverviewCard({required this.board});

  final RemoteTeachingBoardSnapshot board;

  @override
  Widget build(BuildContext context) {
    final topics = board.knowledgeNodeNames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join('、');
    final topicText = topics.isEmpty ? '本阶段知识点' : topics;
    return Container(
      key: const ValueKey('historical-board-overview-card'),
      margin: const EdgeInsets.only(left: 44, right: 8, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本阶段学习内容',
            style: TextStyle(fontWeight: FontWeight.w900, color: _ink),
          ),
          const SizedBox(height: 8),
          Text(topicText, style: const TextStyle(height: 1.5, color: _ink)),
          const SizedBox(height: 6),
          const Text(
            '这一步没有单独保存聊天或素材；相关讲解已融入后续互动和练习。回看不会改变当前学习进度。',
            style: TextStyle(height: 1.45, color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

final class _HistoricalMaterialCard extends StatelessWidget {
  const _HistoricalMaterialCard({required this.material});

  final RemoteLearningMaterial material;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('historical-material-${material.id}'),
      margin: const EdgeInsets.only(left: 44, right: 8, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8C9A0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history_edu_rounded, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  material.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Chip(
                label: Text('历史素材'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 历史素材保留当时的完整视觉，但禁止再次提交或制造新的学习证据。
          IgnorePointer(
            child: _RemoteMaterialCard(
              material: material,
              embedded: true,
              onCompletionChanged: (_, _) {},
            ),
          ),
        ],
      ),
    );
  }
}

final class _HistoricalPracticeCard extends StatelessWidget {
  const _HistoricalPracticeCard({required this.practice});

  final RemoteLearningPracticeNode practice;

  @override
  Widget build(BuildContext context) {
    final reasoning = practice.latestReasoning?.trim();
    final answer = practice.latestAnswer?.trim();
    final feedback = practice.feedback?.trim();
    return Container(
      key: ValueKey('historical-practice-${practice.id}'),
      margin: const EdgeInsets.only(left: 44, right: 8, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8CBFF), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: _brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  practice.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              _HistoricalPracticeStatus(status: practice.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(practice.prompt, style: const TextStyle(height: 1.5)),
          if (reasoning != null && reasoning.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('当时的思路', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(reasoning, style: const TextStyle(height: 1.45)),
          ],
          if (answer != null && answer.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('当时的结论', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(answer, style: const TextStyle(height: 1.45)),
          ],
          if (feedback != null && feedback.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '老师反馈：$feedback',
                style: const TextStyle(height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _HistoricalPracticeStatus extends StatelessWidget {
  const _HistoricalPracticeStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toUpperCase();
    final (label, color, background) = switch (normalized) {
      'MASTERED' ||
      'CORRECT' ||
      'PASSED' => ('已通过', const Color(0xFF15803D), const Color(0xFFDCFCE7)),
      'PARTIAL' ||
      'NEEDS_REVIEW' ||
      'INCORRECT' => ('需巩固', const Color(0xFFB45309), const Color(0xFFFFEDD5)),
      _ => ('已作答', const Color(0xFF475569), const Color(0xFFF1F5F9)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// 引导条只渲染服务端当前动作；素材操作仅决定按钮是否可提交，阶段与证据仍由服务端推进。
final class _GuidedTeachingActionPanel extends StatefulWidget {
  const _GuidedTeachingActionPanel({
    super.key,
    this.snapshot,
    this.focusBoard,
    this.isCurrentBoard = true,
    required this.flow,
    required this.guidance,
    required this.capabilities,
    required this.material,
    required this.assetEventType,
    required this.onAssetComplete,
    required this.onSkipMaterial,
    this.onSubmitPractice,
    this.onSendMessage,
    this.onStartMicroCheck,
    required this.onStartReflection,
  });

  final RemoteLearningSessionSnapshot? snapshot;
  final RemoteTeachingBoardSnapshot? focusBoard;
  final bool isCurrentBoard;
  final RemoteTeachingFlow flow;
  final RemoteStudentGuidance? guidance;
  final RemoteCourseCapabilities? capabilities;
  final RemoteLearningMaterial? material;
  final String? assetEventType;
  final Future<void> Function(Map<String, Object?> payload)? onAssetComplete;
  final Future<void> Function()? onSkipMaterial;
  final Future<bool> Function(GuidedPracticeDraft draft)? onSubmitPractice;
  final Future<void> Function(String text)? onSendMessage;
  final Future<void> Function()? onStartMicroCheck;
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

  bool get canSubmitAssetNow =>
      _isAssetReady &&
      widget.material != null &&
      widget.assetEventType != null &&
      widget.onAssetComplete != null;

  Future<void> submitAssetIfReady() async {
    if (!canSubmitAssetNow) return;
    await widget.onAssetComplete!(_assetPayload);
  }

  Future<void> requestHelp() async {
    if (widget.onSkipMaterial != null) {
      await widget.onSkipMaterial!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final guidance = widget.guidance;
    final focusBoard = widget.focusBoard;
    final isCurrentBoard = widget.isCurrentBoard;

    if (focusBoard?.kind == 'SUPPORT_BRANCH') {
      RemoteTeachingBranchRecord? branch;
      for (final item
          in widget.snapshot?.teachingArchitecture?.branches ??
              const <RemoteTeachingBranchRecord>[]) {
        if (item.id == focusBoard!.branchId) {
          branch = item;
          break;
        }
      }
      final isSupportDialogue =
          isCurrentBoard && flow.stage == RemoteTeachingStage.dialogue;
      // 补救分支的所有对话步骤都收在练习页内，并给出唯一继续入口；进入 FOCUS 后再交还正式作答面板。
      if (branch != null && (!isCurrentBoard || isSupportDialogue)) {
        return ClassroomRemediationPanel.fromBranch(
          branch: branch,
          knowledgeNodeNames: focusBoard!.knowledgeNodeNames,
          readOnly: !isCurrentBoard,
          nextAction: isSupportDialogue ? flow.currentAction.prompt : null,
          onContinue: isSupportDialogue && widget.onSendMessage != null
              ? () => widget.onSendMessage!('继续')
              : null,
        );
      }
    }

    if (!isCurrentBoard) {
      if (focusBoard?.kind == 'CHECK') {
        final practice = _practiceForBoard(focusBoard!, flow);
        if (practice != null) {
          return InlinePracticeAnswerPanel(
            practice: practice,
            readOnly: true,
            onSubmit: (_) async => false,
          );
        }
      }
      return const SizedBox.shrink();
    }

    final actionHint = guidance != null && guidance.actionHint.trim().isNotEmpty
        ? guidance.actionHint.trim()
        : flow.currentAction.prompt.trim();
    final showMaterial =
        widget.capabilities?.canSubmitMaterial ??
        guidance?.showMaterialArea ??
        (flow.stage == RemoteTeachingStage.asset &&
            widget.material?.componentKey != null);
    final showPractice =
        widget.capabilities?.canSubmitPractice ??
        guidance?.showPracticeArea ??
        flow.stage == RemoteTeachingStage.focus;
    final isConsolidation =
        flow.currentAction.reasonCode == 'GUIDED_CONSOLIDATION_CHECK_READY' ||
        guidance?.stageLabel == '巩固练习';
    final practice = flow.activePractice;
    final showRepairDialogue =
        flow.stage == RemoteTeachingStage.dialogue &&
        flow.explorationAct == RemoteGuidedExplorationAct.practiceRepair;

    return Column(
      key: const ValueKey('guided-teaching-action-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showRepairDialogue && widget.onSendMessage != null)
          ClassroomRemediationPanel(
            topic: focusBoard?.knowledgeNodeNames.isNotEmpty == true
                ? focusBoard!.knowledgeNodeNames.first
                : '薄弱知识点',
            feedback: flow.feedback?.trim() ?? '',
            repairFocus: flow.repairFocus,
            onContinue: () => widget.onSendMessage!('继续'),
          ),
        if (showMaterial && widget.material == null)
          _GuidedMaterialPlaceholder(goal: flow.goal, stage: flow.stage),
        if (showMaterial && widget.material != null)
          _ClassroomTaskCard(
            title: _classroomTaskTitle(widget.material, flow),
            material: widget.material!,
            onCompletionChanged: _setAssetReadiness,
            canSubmit: canSubmitAssetNow,
            onSubmit: () => unawaited(submitAssetIfReady()),
          )
        else if (showPractice &&
            widget.onSubmitPractice != null &&
            practice != null)
          InlinePracticeAnswerPanel(
            practice: practice,
            isConsolidation: isConsolidation,
            onSubmit: widget.onSubmitPractice!,
          )
        else if (showPractice && widget.onStartMicroCheck != null)
          _PracticeReadyCard(
            practice: practice,
            actionHint: actionHint,
            isConsolidation: isConsolidation,
            onStart: () => unawaited(widget.onStartMicroCheck!()),
          )
        else if (widget.capabilities?.canComplete ??
            flow.stage == RemoteTeachingStage.reflect)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: FilledButton.icon(
              key: const ValueKey('guided-start-reflection-button'),
              onPressed: () => unawaited(widget.onStartReflection()),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('写下反思并完成'),
            ),
          ),
      ],
    );
  }

  RemoteGuidedPractice? _practiceForBoard(
    RemoteTeachingBoardSnapshot board,
    RemoteTeachingFlow flow,
  ) {
    if (board.practiceId != null &&
        flow.activePractice?.id == board.practiceId) {
      return flow.activePractice;
    }
    final graphNode = widget.snapshot?.learningGraph?.practice
        .where((item) => item.id == board.practiceId)
        .toList(growable: false);
    if (graphNode == null || graphNode.isEmpty) return null;
    final node = graphNode.first;
    return RemoteGuidedPractice(
      id: node.id,
      title: node.title,
      prompt: node.prompt,
      reasoningLabel: '理由',
      answerLabel: '结论',
    );
  }
}

/// 独立验证阶段：把练习题干和操作入口放在同一卡片里，避免只有一句提示。
final class _PracticeReadyCard extends StatelessWidget {
  const _PracticeReadyCard({
    required this.practice,
    required this.actionHint,
    required this.isConsolidation,
    required this.onStart,
  });

  final RemoteGuidedPractice? practice;
  final String actionHint;
  final bool isConsolidation;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final title = practice?.title.trim();
    final prompt = practice?.prompt.trim();
    final cardTitle = isConsolidation
        ? (title?.isNotEmpty == true ? '巩固练习：$title' : '巩固练习')
        : (title?.isNotEmpty == true ? '独立验证：$title' : '独立验证');
    final defaultHint = isConsolidation
        ? '换一道稍不同的巩固题，用刚才补到的原理独立试一次。'
        : '打开一道新题，用刚才发现的方法独立试一次。';
    final buttonLabel = isConsolidation ? '开始巩固' : '开始作答';
    return Container(
      key: const ValueKey('practice-ready-card'),
      margin: const EdgeInsets.only(left: 44, right: 8, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8CBFF), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✅', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cardTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (prompt != null && prompt.isNotEmpty)
            Text(prompt, style: const TextStyle(height: 1.55, color: _ink))
          else if (actionHint.isNotEmpty)
            Text(actionHint, style: const TextStyle(height: 1.55, color: _ink))
          else
            Text(
              defaultHint,
              style: const TextStyle(height: 1.55, color: _ink),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('guided-start-practice-button'),
              onPressed: onStart,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// 独立课堂任务卡片：与聊天气泡分离，承载互动/练习操作。
final class _ClassroomTaskCard extends StatelessWidget {
  const _ClassroomTaskCard({
    required this.title,
    required this.material,
    required this.onCompletionChanged,
    required this.canSubmit,
    required this.onSubmit,
  });

  final String title;
  final RemoteLearningMaterial material;
  final void Function(bool isReady, Map<String, Object?> payload)
  onCompletionChanged;
  final bool canSubmit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('classroom-task-card'),
      margin: const EdgeInsets.only(left: 44, right: 8, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8C9A0), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📝', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '课堂任务：$title',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _RemoteMaterialCard(
            material: material,
            embedded: true,
            onCompletionChanged: onCompletionChanged,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('guided-asset-complete-button'),
              onPressed: canSubmit ? onSubmit : null,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(canSubmit ? '提交并继续' : '请先完成全部判断'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 联调期间真实素材尚未返回时提供可读的课堂内容，真实素材到达后自动被替换。
final class _GuidedMaterialPlaceholder extends StatelessWidget {
  const _GuidedMaterialPlaceholder({required this.goal, required this.stage});

  final String goal;
  final RemoteTeachingStage stage;

  @override
  Widget build(BuildContext context) {
    final isChemistry =
        goal.contains('原子') || goal.contains('化学') || goal.contains('配平');
    final title = isChemistry ? '原子守恒示例' : '本节课堂示例';
    final principle = isChemistry
        ? '化学反应前后，每种元素的原子总数保持不变。下标表示物质组成，不能修改；系数表示微粒个数，可以调整。'
        : '先观察例子中的不变量，再用自己的话说明变化前后什么保持不变。';

    return Container(
      key: const ValueKey('guided-material-placeholder'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8F4FF), Color(0xFFF2F8FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9C9FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: _brand, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Chip(
                label: Text('课堂示例'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(principle, style: const TextStyle(height: 1.55, color: _ink)),
          if (isChemistry) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '2H₂ + O₂ → 2H₂O',
                    style: TextStyle(
                      color: _brand,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text('反应前：H 4 个、O 2 个　｜　反应后：H 4 个、O 2 个'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            stage == RemoteTeachingStage.dialogue
                ? '想一想：为什么这里调整的是前面的系数，而不是右下角的数字？'
                : '请结合上面的例子完成当前学习操作。',
            style: const TextStyle(
              color: Color(0xFF5C437D),
              fontWeight: FontWeight.w700,
            ),
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
  'set_membership_widget' => 'SET_MEMBERSHIP_VERIFIED',
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, turn) in turns.indexed)
          Padding(
            padding: EdgeInsets.only(bottom: index < turns.length - 1 ? 4 : 0),
            child: turn,
          ),
      ],
    );
  }
}

final class _ExplorationTurnCard extends StatelessWidget {
  const _ExplorationTurnCard({
    required this.node,
    required this.materials,
    required this.isCurrent,
    required this.onOpenWhiteboard,
    this.teachingFlow,
  });

  final RemoteLearningNode node;
  final List<RemoteLearningMaterial> materials;
  final bool isCurrent;
  final VoidCallback onOpenWhiteboard;
  final RemoteTeachingFlow? teachingFlow;

  @override
  Widget build(BuildContext context) {
    final question = node.question.trim();
    final showTeacher = node.answer.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (question.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Container(
                  key: ValueKey('student-question-${node.id}'),
                  constraints: const BoxConstraints(maxWidth: 560),
                  margin: const EdgeInsets.only(bottom: 12, left: 48),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: BoxDecoration(
                    color: _studentBubbleFill,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(6),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: const Border(
                      right: BorderSide(color: _studentBubbleBorder, width: 3),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A2563EB),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 14,
                            color: _studentBubbleBorder,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '学生',
                            style: const TextStyle(
                              color: _studentBubbleBorder,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        question,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _studentBubbleInk,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const CircleAvatar(
                radius: 18,
                backgroundColor: _studentBubbleBorder,
                child: Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        if (showTeacher)
          _ExplorationClassroom(
            node: node,
            materials: materials,
            isCurrent: isCurrent,
            teachingFlow: teachingFlow,
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
    this.teachingFlow,
  });

  final RemoteLearningNode node;
  final List<RemoteLearningMaterial> materials;
  final bool isCurrent;
  final VoidCallback onOpenWhiteboard;
  final RemoteTeachingFlow? teachingFlow;

  @override
  Widget build(BuildContext context) {
    final teacherMessage = _teacherMessageForNode(
      node,
      flow: teachingFlow,
      isCurrent: isCurrent,
    );
    if (teacherMessage.isEmpty) return const SizedBox.shrink();
    return _TeacherChatBubble(message: teacherMessage);
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
  const _RemoteMaterialCard({
    required this.material,
    this.onCompletionChanged,
    this.embedded = false,
  });

  final RemoteLearningMaterial material;
  final void Function(bool isReady, Map<String, Object?> payload)?
  onCompletionChanged;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded) ...[
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
        ],
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
    );
    if (embedded) return content;
    return Card(
      elevation: 0,
      color: const Color(0xFFF9F8FC),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE0DBE8)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: content),
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
  final Map<String, bool> _setMembershipChoices = {};

  static const _setMembershipItems =
      <({String id, String element, String setLabel, bool belongs})>[
        (
          id: 'three-in-a',
          element: '3',
          setLabel: 'A = {1, 2, 3, 4, 5}',
          belongs: true,
        ),
        (
          id: 'six-not-in-a',
          element: '6',
          setLabel: 'A = {1, 2, 3, 4, 5}',
          belongs: false,
        ),
        (
          id: 'half-not-in-z',
          element: '0.5',
          setLabel: 'Z（整数集）',
          belongs: false,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final key = widget.material.componentKey ?? '';
    if (key == 'set_membership_widget') {
      final allAnswered = _setMembershipItems.every(
        (item) => _setMembershipChoices.containsKey(item.id),
      );
      final allCorrect = _setMembershipItems.every(
        (item) => _setMembershipChoices[item.id] == item.belongs,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '你的任务',
            style: TextStyle(fontWeight: FontWeight.w900, color: _brand),
          ),
          const SizedBox(height: 4),
          const Text('判断每个对象与集合之间是 ∈（属于）还是 ∉（不属于）。'),
          const SizedBox(height: 10),
          for (final item in _setMembershipItems) ...[
            Text(
              '${item.element} 与 ${item.setLabel}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('∈ 属于'),
                  selected: _setMembershipChoices[item.id] == true,
                  onSelected: (_) => _updateSetMembership(item.id, true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('∉ 不属于'),
                  selected: _setMembershipChoices[item.id] == false,
                  onSelected: (_) => _updateSetMembership(item.id, false),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            !allAnswered
                ? '请完成全部判断。'
                : allCorrect
                ? '很好！你已经能区分元素与集合的两种关系。'
                : '再想想：集合元素具有确定性，每个对象要么属于，要么不属于。',
            style: TextStyle(
              fontSize: 12,
              color: allCorrect && allAnswered
                  ? const Color(0xFF167A5A)
                  : const Color(0xFF9A5B00),
              fontWeight: allCorrect && allAnswered
                  ? FontWeight.w700
                  : FontWeight.normal,
            ),
          ),
        ],
      );
    }
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
          const Text(
            '你的任务',
            style: TextStyle(fontWeight: FontWeight.w900, color: _brand),
          ),
          const SizedBox(height: 4),
          const Text('点击下面的数字，让箭头左右两边 H 和 O 的数量分别相同。'),
          const SizedBox(height: 4),
          const Text(
            '提示：只能改化学式前面的数字；右下角的小数字决定它是什么物质。',
            style: TextStyle(color: _muted, height: 1.4),
          ),
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
            '反应前：H ${_hydrogenCoefficient * 2} 个、O ${_oxygenCoefficient * 2} 个'
            '　｜　反应后：H ${_waterCoefficient * 2} 个、O $_waterCoefficient 个',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 6),
          Text(
            balanced ? '完成！反应前后的 H、O 数量都相同。' : '还差一点：看看 H 或 O 哪一种数量还不一样。',
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

  void _updateSetMembership(String itemId, bool belongs) {
    setState(() => _setMembershipChoices[itemId] = belongs);
    final answers = {
      for (final item in _setMembershipItems)
        item.id: _setMembershipChoices[item.id],
    };
    final allAnswered = _setMembershipItems.every(
      (item) => answers.containsKey(item.id),
    );
    final allCorrect = _setMembershipItems.every(
      (item) => answers[item.id] == item.belongs,
    );
    _reportCompletion(allAnswered, {
      'answers': answers,
      'allCorrect': allCorrect,
    });
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
    final description = _studentMaterialCaption(material);
    final leftLabel = material.materialId == 'chemistry-particle-figure'
        ? '反应前'
        : '现象';
    final rightLabel = material.materialId == 'chemistry-particle-figure'
        ? '反应后'
        : description;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _FigureBlock(label: leftLabel)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded),
              ),
              Expanded(
                child: _FigureBlock(
                  label: rightLabel,
                  emphasized:
                      material.materialId != 'chemistry-particle-figure',
                ),
              ),
            ],
          ),
          if (material.materialId == 'chemistry-particle-figure') ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(fontSize: 13, height: 1.5, color: _ink),
            ),
          ],
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
        _studentMaterialCaption(material),
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

final class _StaleSessionRestartPanel extends StatelessWidget {
  const _StaleSessionRestartPanel({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('stale-session-restart-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5D08A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFFB45309)),
              SizedBox(width: 8),
              Text(
                '这是旧测试会话，流程已失效',
                style: TextStyle(fontWeight: FontWeight.w900, color: _ink),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '刷新页面无法修复。请返回章节目录，点「开始验收测试」重新开一场。',
            style: TextStyle(height: 1.5, color: _ink),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('返回章节目录，重新开始'),
          ),
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

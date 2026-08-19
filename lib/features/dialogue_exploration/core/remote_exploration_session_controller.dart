import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../adapters/guided_teaching_flow_dto.dart';
import '../adapters/remote_exploration_api.dart';
import '../adapters/remote_exploration_dto.dart';

enum RemoteExplorationStatus {
  idle,
  loadingEntry,
  ready,
  submitting,
  active,
  failed,
  completed,
}

enum RemoteComposerMode { currentPath, continueFromNode, branchFromNode }

/// 远程会话页面只读状态；思维树永远来自服务端完整快照。
final class RemoteExplorationState {
  const RemoteExplorationState({
    required this.status,
    required this.chapter,
    required this.selectedChapterNodeId,
    required this.entry,
    required this.snapshot,
    required this.inspectedNodeId,
    required this.composerMode,
    required this.errorMessage,
    required this.memoryCandidateNodeIds,
    required this.canRetry,
    required this.history,
    required this.chapterCatalog,
  });

  const RemoteExplorationState.idle()
    : status = RemoteExplorationStatus.idle,
      chapter = null,
      selectedChapterNodeId = null,
      entry = null,
      snapshot = null,
      inspectedNodeId = null,
      composerMode = RemoteComposerMode.currentPath,
      errorMessage = null,
      memoryCandidateNodeIds = const {},
      canRetry = false,
      history = const [],
      chapterCatalog = const [];

  final RemoteExplorationStatus status;
  final LearningChapterOverviewSnapshot? chapter;
  final String? selectedChapterNodeId;
  final LearningEntrySnapshot? entry;
  final RemoteLearningSessionSnapshot? snapshot;
  final String? inspectedNodeId;
  final RemoteComposerMode composerMode;
  final String? errorMessage;
  final Set<String> memoryCandidateNodeIds;
  final bool canRetry;
  final List<RemoteLearningSessionSummary> history;
  final List<LearningChapterCatalogItem> chapterCatalog;

  /// 已结束或由服务端标记为不可继续的历史会话只能浏览，避免修改既有学习证据。
  bool get isReadOnly {
    final session = snapshot?.session;
    if (session == null) return false;
    if (session.status != 'ACTIVE') return true;
    final expiresAt = DateTime.tryParse(session.expiresAt);
    return expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc());
  }

  RemoteExplorationState copyWith({
    RemoteExplorationStatus? status,
    LearningChapterOverviewSnapshot? chapter,
    String? selectedChapterNodeId,
    bool clearSelectedChapterNode = false,
    LearningEntrySnapshot? entry,
    RemoteLearningSessionSnapshot? snapshot,
    bool clearSnapshot = false,
    String? inspectedNodeId,
    bool clearInspectedNode = false,
    RemoteComposerMode? composerMode,
    String? errorMessage,
    bool clearError = false,
    Set<String>? memoryCandidateNodeIds,
    bool? canRetry,
    List<RemoteLearningSessionSummary>? history,
    List<LearningChapterCatalogItem>? chapterCatalog,
  }) {
    return RemoteExplorationState(
      status: status ?? this.status,
      chapter: chapter ?? this.chapter,
      selectedChapterNodeId: clearSelectedChapterNode
          ? null
          : selectedChapterNodeId ?? this.selectedChapterNodeId,
      entry: entry ?? this.entry,
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      inspectedNodeId: clearInspectedNode
          ? null
          : inspectedNodeId ?? this.inspectedNodeId,
      composerMode: composerMode ?? this.composerMode,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      memoryCandidateNodeIds:
          memoryCandidateNodeIds ?? this.memoryCandidateNodeIds,
      canRetry: canRetry ?? this.canRetry,
      history: history ?? this.history,
      chapterCatalog: chapterCatalog ?? this.chapterCatalog,
    );
  }
}

/// 管理远程 Session 的异步状态、显式节点动作和幂等重试，不在本地合并树。
final class RemoteExplorationSessionController extends ChangeNotifier {
  RemoteExplorationSessionController({required this.api});

  final RemoteExplorationGateway api;
  RemoteExplorationState _state = const RemoteExplorationState.idle();
  Future<void> Function()? _retryOperation;
  Timer? _submitWatchdog;
  String? _pendingTeachingModeSkill;
  List<RemoteTeachingModeOption>? _modeMenuOptionsOverride;
  var _isDisposed = false;

  RemoteExplorationState get state => _state;

  bool shouldShowModeSelection(RemoteLearningSessionSnapshot snapshot) {
    final guidance = snapshot.studentGuidance;
    return snapshot.capabilities?.canSelectMode == true ||
        snapshot.processSchedulerState?.isAwaitingModeSelection == true ||
        guidance?.stageLabel == '选择学习方式' ||
        guidance?.stageLabel == 'AI 老师开场' ||
        (guidance?.showModeSelection == false &&
            snapshot.courseState?.currentStage == 'MODE_SELECTION') ||
        snapshot.allows('SELECT_MODE') ||
        snapshot.courseState?.currentStage == 'MODE_SELECTION' ||
        (_modeMenuOptionsOverride?.isNotEmpty ?? false);
  }

  bool isModeSelectionIntro(RemoteLearningSessionSnapshot snapshot) {
    final guidance = snapshot.studentGuidance;
    return guidance?.stageLabel == 'AI 老师开场' ||
        (guidance?.showModeSelection == false &&
            snapshot.courseState?.currentStage == 'MODE_SELECTION');
  }

  /// 引导式课堂全程使用带历史记录的侧边栏布局（图二），不再切换到全宽聊天（图一）。
  bool shouldUseSidebarClassroom(RemoteLearningSessionSnapshot snapshot) {
    return snapshot.teachingFlow?.mode == RemoteFlowMode.guidedLesson;
  }

  /// 概念诊断前的真实寒暄，以及选路前的引导对话，都走同一聊天面板。
  bool shouldShowEntryDialogue(RemoteLearningSessionSnapshot snapshot) {
    if (shouldUseSidebarClassroom(snapshot)) return true;
    if (snapshot.processSchedulerState?.currentPhase ==
        RemoteTeachingPhase.conceptIntroduction) {
      return true;
    }
    return shouldShowModeSelection(snapshot);
  }

  bool canSubmitEntryDialogue(RemoteLearningSessionSnapshot snapshot) {
    final capabilities = snapshot.capabilities;
    if (capabilities != null) {
      return capabilities.canSubmitText;
    }
    return snapshot.studentGuidance?.canSubmitText ?? true;
  }

  List<RemoteTeachingModeOption> resolvedModeMenuOptions(
    RemoteLearningSessionSnapshot snapshot,
  ) {
    final fromSnapshot = snapshot.processSchedulerState?.modeMenuOptions;
    if (fromSnapshot != null && fromSnapshot.isNotEmpty) return fromSnapshot;
    return _modeMenuOptionsOverride ?? const [];
  }

  /// 旧版内存会话缺少 processSchedulerState，诊断后会误进入自由对话。
  bool isLegacyBrokenSession(RemoteLearningSessionSnapshot snapshot) {
    return snapshot.processSchedulerState == null &&
        snapshot.teachingFlow?.mode == RemoteFlowMode.guidedLesson &&
        snapshot.nodes.length >= 2 &&
        snapshot.studentGuidance?.stageLabel == '确定方向';
  }

  /// 旧会话或字段缺失时，通过 teaching-mode 接口补拉模式菜单。
  Future<void> syncModeSelectionIfNeeded() => _syncTeachingModeIfNeeded();

  Future<void> _syncTeachingModeIfNeeded() async {
    final snapshot = _state.snapshot;
    if (snapshot == null) {
      _modeMenuOptionsOverride = null;
      return;
    }
    if (!shouldShowModeSelection(snapshot)) {
      _modeMenuOptionsOverride = null;
      return;
    }
    if (snapshot.processSchedulerState?.modeMenuOptions?.isNotEmpty == true) {
      _modeMenuOptionsOverride = null;
      return;
    }
    try {
      final mode = await api.getTeachingModeOptions(
        sessionId: snapshot.session.id,
      );
      if (mode.phase == RemoteTeachingPhase.modeSelection &&
          (mode.options?.isNotEmpty ?? false)) {
        _modeMenuOptionsOverride = mode.options;
        if (!_isDisposed) notifyListeners();
      }
    } catch (_) {
      // 拉取失败时保留当前快照，由页面提示用户重新开始。
    }
  }

  /// 目录加载与详情加载分离，目录失败可重试且不清除用户已打开的会话快照。
  Future<void> loadChapterCatalog() async {
    _replace(
      _state.copyWith(
        status: RemoteExplorationStatus.loadingEntry,
        clearError: true,
      ),
    );
    try {
      final catalog = await api.listChapterCatalog();
      _retryOperation = null;
      _replace(
        _state.copyWith(
          status: RemoteExplorationStatus.ready,
          chapterCatalog: List<LearningChapterCatalogItem>.unmodifiable(
            catalog,
          ),
          clearError: true,
          canRetry: false,
        ),
      );
    } catch (error) {
      _fail(error, loadChapterCatalog);
    }
  }

  /// 章节选择后加载概览，并由 AI 老师先发起寒暄会话。
  Future<void> selectChapter(String chapterId) async {
    await loadChapter(chapterId);
    await startChapterGreetingSession();
  }

  /// 进入章节时创建「老师先开口」的寒暄会话，不预填 hook 问题。
  Future<void> startChapterGreetingSession() async {
    if (_state.snapshot != null) return;
    final chapter = _state.chapter;
    if (chapter == null) return;
    final nodeId = _state.selectedChapterNodeId ?? chapter.recommendedNodeId;
    final node = chapter.nodeById(nodeId);
    if (node == null) return;

    selectChapterNode(nodeId);
    final key = _traceId('create-greeting');
    Future<void> operation() async {
      _submitting();
      try {
        final entry = _state.entry?.atomId == node.atomId
            ? _state.entry!
            : await api.getEntry(node.atomId);
        final snapshot = await api.createSession(
          atomId: node.atomId,
          scenarioId: _preStudyScenarioId,
          idempotencyKey: key,
          flowMode: RemoteFlowMode.guidedLesson,
          entryMode: RemoteSessionEntryMode.chapterGreeting,
        );
        _replace(_state.copyWith(entry: entry));
        await _acceptSnapshot(snapshot);
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> loadChapter(String chapterId) async {
    _replace(
      _state.copyWith(
        status: RemoteExplorationStatus.loadingEntry,
        clearError: true,
      ),
    );
    try {
      final chapter = await api.getChapterOverview(chapterId);
      _replace(
        _state.copyWith(
          status: RemoteExplorationStatus.ready,
          chapter: chapter,
          selectedChapterNodeId: chapter.recommendedNodeId,
          clearError: true,
        ),
      );
    } catch (error) {
      _fail(error, () => loadChapter(chapterId));
    }
  }

  /// 选择章节节点只改变本地浏览焦点，不提前创建会话或写入学生行为。
  void selectChapterNode(String nodeId) {
    if (_state.chapter?.nodeById(nodeId) == null) return;
    _replace(_state.copyWith(selectedChapterNodeId: nodeId, clearError: true));
  }

  Future<void> startFromChapterNode(String nodeId, {String? question}) async {
    final node = _state.chapter?.nodeById(nodeId);
    if (node == null) throw StateError('章节知识节点不存在');
    final normalizedQuestion = (question ?? '').trim();
    if (normalizedQuestion.isEmpty) {
      _replace(
        _state.copyWith(
          status: RemoteExplorationStatus.ready,
          errorMessage: '先写下你想和 AI 老师讨论的内容',
        ),
      );
      return;
    }
    selectChapterNode(nodeId);
    final key = _traceId('create');
    Future<void> operation() async {
      _submitting();
      try {
        final entry = _state.entry?.atomId == node.atomId
            ? _state.entry!
            : await api.getEntry(node.atomId);
        final snapshot = await api.createSession(
          atomId: node.atomId,
          // 章节的学习/练习/复习只是全章导航；1.2 创建的始终是预习探索会话。
          scenarioId: _preStudyScenarioId,
          question: normalizedQuestion,
          idempotencyKey: key,
          flowMode: RemoteFlowMode.guidedLesson,
        );
        _replace(_state.copyWith(entry: entry));
        await _acceptSnapshot(snapshot);
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  /// 章节入口只记录学生选择并创建会话；诊断答案必须由学生自己提交。
  ///
  /// 后端进入 MODE_SELECTION 后，才应用学生在入口已经选过的模式。
  Future<void> startFromChapterNodeWithTeachingMode(
    String nodeId,
    String skill, {
    String? question,
  }) async {
    final node = _state.chapter?.nodeById(nodeId);
    if (node == null) throw StateError('章节知识节点不存在');
    final normalizedSkill = skill.trim();
    if (normalizedSkill.isEmpty) {
      throw ArgumentError('教学模式技能不能为空');
    }

    _pendingTeachingModeSkill = normalizedSkill;
    await startFromChapterNode(nodeId, question: question);
  }

  /// 前置条件未满足时只在本地阻断，避免为不可进入的知识点创建无效会话。
  Future<void> startNextLearningOption(RemoteNextLearningOption option) async {
    if (!option.prerequisitesSatisfied) return;
    final key = _traceId('create-next-learning');
    Future<void> operation() async {
      _submitting();
      try {
        final entry = await api.getEntry(option.atomId);
        final snapshot = await api.createSession(
          atomId: option.atomId,
          scenarioId: _preStudyScenarioId,
          question: option.hookQuestion,
          idempotencyKey: key,
          flowMode: RemoteFlowMode.guidedLesson,
        );
        _replace(_state.copyWith(entry: entry));
        await _acceptSnapshot(snapshot);
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  /// 章节内的自由表达仍挂载当前知识节点，保证服务端可以沿引导状态机插入实验；
  /// 只有未进入章节时才创建开放探索，交给服务端按问题识别知识范围。
  Future<void> startFreeQuestion(String question) async {
    final normalizedQuestion = question.trim();
    if (normalizedQuestion.isEmpty) {
      _replace(
        _state.copyWith(
          status: RemoteExplorationStatus.ready,
          errorMessage: '先写下你想和 AI 老师讨论的问题',
        ),
      );
      return;
    }

    final chapter = _state.chapter;
    final contextualNodeId =
        _state.selectedChapterNodeId ?? chapter?.recommendedNodeId;
    if (contextualNodeId != null &&
        chapter?.nodeById(contextualNodeId) != null) {
      await startFromChapterNode(
        contextualNodeId,
        question: normalizedQuestion,
      );
      return;
    }

    final key = _traceId('create-free-question');
    Future<void> operation() async {
      _submitting();
      try {
        final snapshot = await api.createSession(
          scenarioId: _preStudyScenarioId,
          question: normalizedQuestion,
          idempotencyKey: key,
          flowMode: RemoteFlowMode.openExploration,
        );
        await _acceptSnapshot(snapshot);
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> loadEntry(String atomId) async {
    _replace(
      _state.copyWith(
        status: RemoteExplorationStatus.loadingEntry,
        clearError: true,
      ),
    );
    try {
      final entry = await api.getEntry(atomId);
      _replace(
        _state.copyWith(status: RemoteExplorationStatus.ready, entry: entry),
      );
    } catch (error) {
      _fail(error, () => loadEntry(atomId));
    }
  }

  Future<void> start({String? directionId, String? question}) async {
    final entry = _state.entry;
    if (entry == null) throw StateError('Learning Entry 尚未加载');
    final key = _traceId('create');
    Future<void> operation() async {
      _submitting();
      try {
        final snapshot = await api.createSession(
          atomId: entry.atomId,
          scenarioId: _preStudyScenarioId,
          directionId: directionId,
          question: question,
          idempotencyKey: key,
          flowMode: RemoteFlowMode.guidedLesson,
        );
        await _acceptSnapshot(snapshot);
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> restoreLatest() async {
    try {
      final snapshot = await api.restoreLatest();
      if (snapshot != null) await _acceptSnapshot(snapshot);
    } catch (error) {
      _fail(error, restoreLatest);
    }
  }

  /// 历史列表由服务端按当前账号/匿名身份过滤，客户端不跨身份合并缓存。
  Future<void> loadHistory({bool restoreLatestActive = false}) async {
    try {
      final history = await api.listSessions();
      _replace(
        _state.copyWith(
          // 上一次历史请求失败后，成功重试应先退出 failed，页面才能继续加载章节。
          status: _state.snapshot == null
              ? (_state.chapter == null
                    ? RemoteExplorationStatus.idle
                    : RemoteExplorationStatus.ready)
              : _state.status,
          history: List<RemoteLearningSessionSummary>.unmodifiable(history),
          clearError: true,
          canRetry: false,
        ),
      );
      if (!restoreLatestActive) return;

      // 服务端已经按最近活动时间排序；这里只恢复首个仍可继续的记录。
      for (final summary in history) {
        if (!summary.canContinue) continue;
        await _acceptSnapshot(await api.restoreSession(summary));
        return;
      }
    } catch (error) {
      _fail(error, () => loadHistory(restoreLatestActive: restoreLatestActive));
    }
  }

  Future<void> openHistorySession(String sessionId) async {
    final summary = _state.history
        .where((item) => item.id == sessionId)
        .firstOrNull;
    if (summary == null) throw StateError('历史预习会话不存在');

    Future<void> operation() async {
      _submitting();
      try {
        await _acceptSnapshot(await api.restoreSession(summary));
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  /// 返回预习总览时仅清除当前视图，不删除服务端会话或历史记录。
  void leaveSession() {
    _retryOperation = null;
    _modeMenuOptionsOverride = null;
    _pendingTeachingModeSkill = null;
    _replace(
      _state.copyWith(
        status: _state.chapter == null
            ? RemoteExplorationStatus.idle
            : RemoteExplorationStatus.ready,
        clearSnapshot: true,
        clearInspectedNode: true,
        composerMode: RemoteComposerMode.currentPath,
        clearError: true,
        canRetry: false,
      ),
    );
  }

  /// 选中节点只改变本地检查视图，绝不触发支线、回溯或服务端写入。
  void inspectNode(String nodeId) {
    if (_state.snapshot?.nodeById(nodeId) == null) return;
    _replace(
      _state.copyWith(
        inspectedNodeId: nodeId,
        composerMode: RemoteComposerMode.currentPath,
        clearError: true,
      ),
    );
  }

  void prepareContinueFromInspected() {
    _requireMutableSnapshot();
    _requireInspectedNode();
    _replace(
      _state.copyWith(composerMode: RemoteComposerMode.continueFromNode),
    );
  }

  void prepareBranchFromInspected() {
    _requireMutableSnapshot();
    _requireInspectedNode();
    _replace(_state.copyWith(composerMode: RemoteComposerMode.branchFromNode));
  }

  void cancelPreparedAction() {
    _replace(_state.copyWith(composerMode: RemoteComposerMode.currentPath));
  }

  Future<void> submitQuestion(String question, {bool force = false}) async {
    final normalized = question.trim();
    if (normalized.isEmpty) return;
    final snapshot = _requireMutableSnapshot();
    if (!force &&
        snapshot.capabilities != null &&
        !snapshot.capabilities!.canSubmitText) {
      throw StateError('服务端当前不允许提交文字');
    }
    final mode = _state.composerMode;
    final parentId = mode == RemoteComposerMode.currentPath
        ? null
        : _requireInspectedNode().id;
    final key = _traceId(
      mode == RemoteComposerMode.branchFromNode ? 'branch' : 'turn',
    );
    Future<void> operation() async {
      _submitting();
      try {
        final updated = mode == RemoteComposerMode.branchFromNode
            ? await api.createBranch(
                sessionId: snapshot.session.id,
                parentNodeId: parentId!,
                question: normalized,
                idempotencyKey: key,
              )
            : await api.submitTurn(
                sessionId: snapshot.session.id,
                question: normalized,
                parentNodeId: parentId,
                idempotencyKey: key,
              );
        await _acceptSnapshot(updated);
        await _applyPendingTeachingModeIfReady(_state.snapshot!);
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> _applyPendingTeachingModeIfReady(
    RemoteLearningSessionSnapshot snapshot,
  ) async {
    final pendingSkill = _pendingTeachingModeSkill;
    final procState = snapshot.processSchedulerState;
    if (pendingSkill == null ||
        procState?.currentPhase != RemoteTeachingPhase.modeSelection) {
      return;
    }
    final offered =
        procState?.modeMenuOptions?.any(
          (option) => option.skill == pendingSkill,
        ) ??
        false;
    if (!offered) {
      _pendingTeachingModeSkill = null;
      return;
    }
    await selectTeachingMode(pendingSkill);
    _pendingTeachingModeSkill = null;
  }

  /// 素材事件的事件 ID 与发生时间在首次提交前生成，网络重试复用同一事件，
  /// 防止服务端把一次学生操作累计成多份证据。
  Future<void> submitMaterialEvent({
    required String materialUsageId,
    required String eventType,
    Map<String, Object?> payload = const {},
  }) async {
    final snapshot = _requireMutableSnapshot();
    final normalizedMaterialId = materialUsageId.trim();
    final normalizedEventType = eventType.trim();
    if (normalizedMaterialId.isEmpty || normalizedEventType.isEmpty) {
      throw ArgumentError('素材 ID 与事件类型不能为空');
    }
    final canSubmit = normalizedEventType == 'MATERIAL_SKIPPED'
        ? snapshot.capabilities?.canSkipMaterial
        : snapshot.capabilities?.canSubmitMaterial;
    if (snapshot.capabilities != null && canSubmit != true) {
      throw StateError('服务端当前不允许该素材操作');
    }
    final eventId = _traceId('asset-event');
    final key = _traceId('material-event');
    final event = RemoteAssetEvent(
      schemaVersion: 1,
      eventId: eventId,
      eventType: normalizedEventType,
      occurredAt: DateTime.now().toUtc().toIso8601String(),
      payload: Map<String, Object?>.unmodifiable(payload),
    );

    Future<void> operation() async {
      _submitting();
      try {
        await _acceptSnapshot(
          await api.submitMaterialEvent(
            sessionId: snapshot.session.id,
            materialUsageId: normalizedMaterialId,
            event: event,
            idempotencyKey: key,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  /// 学生在模式菜单选择教学技能；只校验该技能仍在当前快照允许的选项内，
  /// 避免用户在服务端刷新阶段后误提交过期选项。真正的白名单以服务端返回为准。
  Future<void> selectTeachingMode(String skillWireCode) async {
    final snapshot = _requireMutableSnapshot();
    if (snapshot.capabilities != null &&
        !snapshot.capabilities!.canSelectMode &&
        !shouldShowModeSelection(snapshot)) {
      throw StateError('服务端当前不允许选择教学模式');
    }
    final options = resolvedModeMenuOptions(snapshot);
    if (options.isEmpty) {
      throw StateError('服务端尚未提供可选教学模式');
    }
    final procState = snapshot.processSchedulerState;
    if (procState != null &&
        procState.currentPhase != RemoteTeachingPhase.modeSelection &&
        !shouldShowModeSelection(snapshot)) {
      throw StateError('当前教学阶段不接受模式选择');
    }
    final normalized = skillWireCode.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('教学模式技能不能为空');
    }
    final offered = options.any((option) => option.skill == normalized);
    if (!offered) {
      throw ArgumentError('该模式不在当前目标的可选范围内');
    }
    final key = _traceId('teaching-mode');

    Future<void> operation() async {
      _submitting();
      try {
        await _acceptSnapshot(
          await api.selectTeachingMode(
            sessionId: snapshot.session.id,
            skill: normalized,
            idempotencyKey: key,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  /// 迁移情境由服务端当前教师动作指定，客户端只提交学生作答，
  /// 不在本地推导题目或证据是否达标。
  Future<void> submitGuidedPractice({
    required String reasoning,
    required String answer,
  }) async {
    final snapshot = _requireMutableSnapshot();
    final flow = snapshot.teachingFlow;
    if (snapshot.capabilities != null &&
        !snapshot.capabilities!.canSubmitPractice) {
      throw StateError('服务端当前不允许提交练习');
    }
    // V2 的题目可能在补救后轮换；只能使用当前快照，避免旧 action 指向过期题目。
    final practiceId = flow?.activePractice?.id.trim() ?? '';
    if (flow?.stage != RemoteTeachingStage.focus || practiceId.isEmpty) {
      throw StateError('当前教学步骤没有可提交的迁移情境');
    }
    final normalizedReasoning = reasoning.trim();
    final normalizedAnswer = answer.trim();
    if (normalizedReasoning.isEmpty || normalizedAnswer.isEmpty) {
      throw ArgumentError('推理过程与答案不能为空');
    }
    final key = _traceId('guided-practice');

    Future<void> operation() async {
      _submitting();
      try {
        await _acceptSnapshot(
          await api.submitPracticeAttempt(
            sessionId: snapshot.session.id,
            practiceId: practiceId,
            reasoning: normalizedReasoning,
            answer: normalizedAnswer,
            idempotencyKey: key,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> backtrackToInspected() async {
    final snapshot = _requireMutableSnapshot();
    final target = _requireInspectedNode();
    final key = _traceId('backtrack');
    Future<void> operation() async {
      _submitting();
      try {
        await _acceptSnapshot(
          await api.backtrack(
            sessionId: snapshot.session.id,
            targetNodeId: target.id,
            idempotencyKey: key,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> convertInspectedToMemory() async {
    final snapshot = _requireMutableSnapshot();
    final node = _requireInspectedNode();
    final key = _traceId('memory');
    Future<void> operation() async {
      _submitting();
      try {
        await api.createMemoryCandidate(
          sessionId: snapshot.session.id,
          nodeId: node.id,
          idempotencyKey: key,
        );
        _retryOperation = null;
        _replace(
          _state.copyWith(
            status: RemoteExplorationStatus.active,
            memoryCandidateNodeIds: {..._state.memoryCandidateNodeIds, node.id},
            canRetry: false,
            clearError: true,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> complete(String reflection) async {
    final normalized = reflection.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(reflection, 'reflection', '复述不能为空');
    }
    final snapshot = _requireMutableSnapshot();
    final key = _traceId('complete');
    Future<void> operation() async {
      _submitting();
      try {
        await _acceptSnapshot(
          await api.complete(
            sessionId: snapshot.session.id,
            reflection: normalized,
            idempotencyKey: key,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<String> exportTree() => api.exportTree(_requireSnapshot().session.id);

  Future<void> retry() async {
    final operation = _retryOperation;
    if (operation != null) await operation();
  }

  RemoteLearningNode _requireInspectedNode() {
    return _state.snapshot?.nodeById(_state.inspectedNodeId) ??
        (throw StateError('请先选择一个思维树节点'));
  }

  RemoteLearningSessionSnapshot _requireSnapshot() {
    return _state.snapshot ?? (throw StateError('学习会话尚未开始'));
  }

  RemoteLearningSessionSnapshot _requireMutableSnapshot() {
    final snapshot = _requireSnapshot();
    if (_state.isReadOnly) {
      throw StateError('历史预习会话为只读状态');
    }
    return snapshot;
  }

  void _submitting() {
    _submitWatchdog?.cancel();
    _submitWatchdog = Timer(const Duration(seconds: 75), () {
      if (_isDisposed || _state.status != RemoteExplorationStatus.submitting) {
        return;
      }
      _replace(
        _state.copyWith(
          status: RemoteExplorationStatus.failed,
          errorMessage: '请求等待时间过长，请刷新课堂后重试。',
          canRetry: _retryOperation != null,
        ),
      );
    });
    _replace(
      _state.copyWith(
        status: RemoteExplorationStatus.submitting,
        clearError: true,
      ),
    );
  }

  Future<void> _acceptSnapshot(RemoteLearningSessionSnapshot snapshot) async {
    _submitWatchdog?.cancel();
    _retryOperation = null;
    _replace(
      _state.copyWith(
        status: snapshot.session.status == 'COMPLETED'
            ? RemoteExplorationStatus.completed
            : RemoteExplorationStatus.active,
        snapshot: snapshot,
        clearInspectedNode: true,
        composerMode: RemoteComposerMode.currentPath,
        clearError: true,
        canRetry: false,
      ),
    );
    await _syncTeachingModeIfNeeded();
  }

  void _fail(Object error, Future<void> Function() retryOperation) {
    _submitWatchdog?.cancel();
    _retryOperation = retryOperation;
    _replace(
      _state.copyWith(
        status: RemoteExplorationStatus.failed,
        errorMessage: error is RemoteExplorationException
            ? error.message
            : '操作失败，请重试。',
        canRetry: true,
      ),
    );
  }

  void _replace(RemoteExplorationState next) {
    _state = next;
    if (!_isDisposed) notifyListeners();
  }

  static const _preStudyScenarioId = 'prestudy';

  static String _traceId(String prefix) {
    final entropy = math.Random().nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$entropy';
  }

  @override
  void dispose() {
    _submitWatchdog?.cancel();
    _isDisposed = true;
    super.dispose();
  }
}

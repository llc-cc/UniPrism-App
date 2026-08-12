import 'dart:async';

import 'package:flutter/foundation.dart';

import '../adapters/practice_event_recorder.dart';
import '../core/practice_models.dart';
import '../core/practice_ports.dart';

/// 练习会话的异步状态。
enum PracticeSessionStatus {
  idle,
  loading,
  ready,
  submitting,
  failure,
  completed,
}

/// 练习页面只读状态快照；草稿和结果均按题目 ID 隔离保存。
final class PracticeSessionState {
  PracticeSessionState({
    required this.status,
    required this.paper,
    required this.currentIndex,
    required Map<String, PracticeDraft> drafts,
    required Map<String, AttemptAssessment> results,
    required this.errorMessage,
    required this.sessionId,
    required this.connectionMode,
    required this.assessorMode,
  }) : drafts = Map.unmodifiable(drafts),
       results = Map.unmodifiable(results);

  factory PracticeSessionState.idle() => PracticeSessionState(
    status: PracticeSessionStatus.idle,
    paper: null,
    currentIndex: 0,
    drafts: const {},
    results: const {},
    errorMessage: null,
    sessionId: null,
    connectionMode: null,
    assessorMode: null,
  );

  final PracticeSessionStatus status;
  final PracticePaper? paper;
  final int currentIndex;
  final Map<String, PracticeDraft> drafts;
  final Map<String, AttemptAssessment> results;
  final String? errorMessage;
  final String? sessionId;
  final PracticeConnectionMode? connectionMode;
  final String? assessorMode;

  PracticeQuestion? get currentQuestion {
    final items = paper?.questions;
    if (items == null || items.isEmpty || currentIndex >= items.length) {
      return null;
    }
    return items[currentIndex];
  }

  PracticeDraft get currentDraft {
    final id = currentQuestion?.id;
    return id == null
        ? const PracticeDraft()
        : drafts[id] ?? const PracticeDraft();
  }

  AttemptAssessment? get resultForCurrent {
    final id = currentQuestion?.id;
    return id == null ? null : results[id];
  }

  int get completedCount => results.length;
}

/// 编排整卷加载、分题草稿、提交重试和完成约束，不在客户端推导长期能力。
final class PracticeSessionController extends ChangeNotifier {
  PracticeSessionController({
    required this.repository,
    DateTime Function()? now,
    this.draftSaveDebounce = const Duration(milliseconds: 600),
  }) : _now = now ?? DateTime.now;

  final PracticeRepository repository;
  final DateTime Function() _now;
  final Duration draftSaveDebounce;

  PracticeSessionState _state = PracticeSessionState.idle();
  final Map<String, int> _submissionCounts = {};
  final Map<String, bool> _editedAfterResult = {};
  final Set<String> _dirtyQuestionIds = {};
  Timer? _draftSaveTimer;
  Future<void> _draftSaveChain = Future<void>.value();
  DateTime? _openedAt;
  PracticeEventRecorder? _eventRecorder;
  bool _isDisposed = false;
  int _operationGeneration = 0;

  PracticeSessionState get state => _state;

  /// 加载当前基准卷；较早的异步结果不得覆盖更新的一次加载。
  Future<void> load() async {
    final generation = ++_operationGeneration;
    _openedAt = _now();
    _emit(
      PracticeSessionState(
        status: PracticeSessionStatus.loading,
        paper: _state.paper,
        currentIndex: 0,
        drafts: _state.drafts,
        results: _state.results,
        errorMessage: null,
        sessionId: _state.sessionId,
        connectionMode: _state.connectionMode,
        assessorMode: _state.assessorMode,
      ),
    );
    try {
      final snapshot = await repository.loadOrCreateSession();
      if (_isDisposed || generation != _operationGeneration) return;
      _eventRecorder?.dispose();
      _dirtyQuestionIds.clear();
      _eventRecorder = PracticeEventRecorder(
        sendBatch: (events) => repository.recordEvents(
          sessionId: snapshot.sessionId,
          events: events,
        ),
        // Mock 不需要后台刷新；避免演示页与 Widget 测试持有无意义定时器。
        scheduleFlush:
            repository.connectionMode == PracticeConnectionMode.remote,
      );
      final index = (snapshot.currentQuestionNumber - 1)
          .clamp(0, snapshot.paper.questions.length - 1)
          .toInt();
      _emit(
        PracticeSessionState(
          status: snapshot.status == PracticeRemoteSessionStatus.completed
              ? PracticeSessionStatus.completed
              : PracticeSessionStatus.ready,
          paper: snapshot.paper,
          currentIndex: index,
          drafts: snapshot.drafts,
          results: snapshot.results,
          errorMessage: null,
          sessionId: snapshot.sessionId,
          connectionMode: repository.connectionMode,
          assessorMode: snapshot.assessorMode,
        ),
      );
      _recordCurrent(PracticeEventType.questionViewed);
    } catch (error) {
      if (_isDisposed || generation != _operationGeneration) return;
      _emit(
        _copy(status: PracticeSessionStatus.failure, errorMessage: '$error'),
      );
    }
  }

  void updateAnswer(String answer) {
    _updateDraft((draft) => draft.copyWith(answer: answer));
    _recordCurrent(
      PracticeEventType.answerChanged,
      payload: {'lengthBand': _lengthBand(answer.length)},
    );
  }

  void updateReasoning(String reasoning) {
    _updateDraft((draft) => draft.copyWith(reasoning: reasoning));
    _recordCurrent(
      PracticeEventType.reasoningChanged,
      payload: {'lengthBand': _lengthBand(reasoning.length)},
    );
  }

  void toggleOption(String option) {
    final question = _state.currentQuestion;
    if (question == null) return;
    final normalized = option.trim().toUpperCase();
    if (question.type == PracticeQuestionType.singleChoice) {
      updateAnswer(normalized);
      return;
    }
    if (question.type != PracticeQuestionType.multipleChoice) return;
    final selected = _state.currentDraft.answer
        .toUpperCase()
        .split('')
        .where((item) => const {'A', 'B', 'C', 'D'}.contains(item))
        .toSet();
    selected.contains(normalized)
        ? selected.remove(normalized)
        : selected.add(normalized);
    final ordered = selected.toList()..sort();
    updateAnswer(ordered.join());
  }

  void selectQuestion(int index) {
    final paper = _state.paper;
    if (paper == null ||
        index < 0 ||
        index >= paper.questions.length ||
        _state.status == PracticeSessionStatus.submitting) {
      return;
    }
    final previousQuestionId = _state.currentQuestion?.id;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    _emit(_copy(currentIndex: index, errorMessage: null));
    _recordCurrent(PracticeEventType.questionViewed);
    if (previousQuestionId != null &&
        _dirtyQuestionIds.contains(previousQuestionId)) {
      _startBackgroundDraftSave(<String>{previousQuestionId});
    }
  }

  void previousQuestion() => selectQuestion(_state.currentIndex - 1);

  void nextQuestion() => selectQuestion(_state.currentIndex + 1);

  /// 提交失败只改变错误状态，草稿继续保留给同一次显式重试。
  Future<void> submitCurrent() async {
    if (_state.status == PracticeSessionStatus.submitting) return;
    final question = _state.currentQuestion;
    final sessionId = _state.sessionId;
    if (question == null || sessionId == null) return;
    final draft = _state.currentDraft;
    if (draft.answer.trim().isEmpty) {
      _emit(
        _copy(status: PracticeSessionStatus.failure, errorMessage: '请先填写答案。'),
      );
      return;
    }

    final generation = ++_operationGeneration;
    final nextSubmissionCount = (_submissionCounts[question.id] ?? 0) + 1;
    _submissionCounts[question.id] = nextSubmissionCount;
    _emit(_copy(status: PracticeSessionStatus.submitting, errorMessage: null));
    try {
      // 提交必须等待自动保存链，确保幂等键引用的是服务端确认的最新草稿版本。
      _draftSaveTimer?.cancel();
      _draftSaveTimer = null;
      await _queueDraftSave(<String>{question.id});
      if (_isDisposed || generation != _operationGeneration) return;
      final savedDraft = _state.drafts[question.id] ?? draft;
      _recordCurrent(PracticeEventType.attemptSubmitted);
      await _eventRecorder?.flush();
      final assessment = await repository.submitAttempt(
        sessionId: sessionId,
        question: question,
        draft: savedDraft,
        facts: PracticeAttemptFacts(
          hintCount: 0,
          submissionCount: nextSubmissionCount,
          durationSeconds: _elapsedSeconds,
        ),
      );
      // 页面被销毁或新操作已经开始时，旧请求不能再回写状态。
      if (_isDisposed || generation != _operationGeneration) return;
      final results = Map<String, AttemptAssessment>.of(_state.results)
        ..[question.id] = assessment;
      _editedAfterResult[question.id] = false;
      _emit(
        _copy(
          status: PracticeSessionStatus.ready,
          results: results,
          errorMessage: null,
        ),
      );
    } catch (error) {
      if (_isDisposed || generation != _operationGeneration) return;
      _emit(
        _copy(
          status: PracticeSessionStatus.failure,
          errorMessage: '提交失败：$error',
        ),
      );
    }
  }

  Future<void> retrySubmission() => submitCurrent();

  /// 页面退到后台或准备销毁时，调用方可等待草稿与粗粒度事件完成刷新。
  Future<void> flushPending() async {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    await _queueDraftSave(Set<String>.of(_dirtyQuestionIds));
    await _eventRecorder?.flush();
  }

  Future<void> bindToSignedInAccount() async {
    final sessionId = _state.sessionId;
    if (sessionId == null) throw StateError('练习会话尚未加载');
    await flushPending();
    await repository.bindCurrentSession(sessionId);
  }

  Future<List<PracticeAbilityProfileSummary>> loadAbilityProfile() =>
      repository.loadAbilityProfile();

  Future<void> complete() async {
    final paper = _state.paper;
    if (paper == null || _state.results.length != paper.questions.length) {
      throw StateError('完成整卷前必须提交全部题目');
    }
    final sessionId = _state.sessionId;
    if (sessionId != null) {
      await flushPending();
      await repository.completeSession(sessionId);
    }
    _emit(_copy(status: PracticeSessionStatus.completed, errorMessage: null));
  }

  int get _elapsedSeconds {
    final openedAt = _openedAt;
    if (openedAt == null) return 0;
    return _now().difference(openedAt).inSeconds.clamp(0, 24 * 60 * 60);
  }

  void _updateDraft(PracticeDraft Function(PracticeDraft) update) {
    final question = _state.currentQuestion;
    if (question == null || _state.status == PracticeSessionStatus.submitting) {
      return;
    }
    var next = update(_state.currentDraft);
    if (_state.results.containsKey(question.id) &&
        _editedAfterResult[question.id] != true) {
      next = next.copyWith(revisionCount: next.revisionCount + 1);
      _editedAfterResult[question.id] = true;
    }
    final drafts = Map<String, PracticeDraft>.of(_state.drafts)
      ..[question.id] = next;
    _dirtyQuestionIds.add(question.id);
    _emit(_copy(drafts: drafts, errorMessage: null));
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    if (repository.connectionMode != PracticeConnectionMode.remote) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(draftSaveDebounce, () {
      _draftSaveTimer = null;
      _startBackgroundDraftSave(Set<String>.of(_dirtyQuestionIds));
    });
  }

  void _startBackgroundDraftSave(Set<String> questionIds) {
    unawaited(
      _queueDraftSave(questionIds).catchError((Object error) {
        if (!_isDisposed) {
          _emit(
            _copy(
              status: PracticeSessionStatus.failure,
              errorMessage: '草稿保存失败：$error',
            ),
          );
        }
      }),
    );
  }

  Future<void> _queueDraftSave(Set<String> questionIds) {
    if (questionIds.isEmpty ||
        repository.connectionMode != PracticeConnectionMode.remote) {
      return _draftSaveChain;
    }
    final prior = _draftSaveChain.catchError((Object _) {});
    final operation = prior.then((_) async {
      for (final questionId in questionIds) {
        await _persistLatestDraft(questionId);
      }
    });
    _draftSaveChain = operation;
    return operation;
  }

  Future<void> _persistLatestDraft(String questionId) async {
    while (_dirtyQuestionIds.contains(questionId)) {
      final sessionId = _state.sessionId;
      final paper = _state.paper;
      final draft = _state.drafts[questionId];
      if (sessionId == null || paper == null || draft == null) return;
      final question = paper.questions.firstWhere(
        (item) => item.id == questionId,
      );
      final saved = await repository.saveDraft(
        sessionId: sessionId,
        question: question,
        draft: draft,
        currentQuestionNumber:
            _state.currentQuestion?.number ?? question.number,
      );
      final latest = _state.drafts[questionId];
      if (latest == null) return;
      final drafts = Map<String, PracticeDraft>.of(_state.drafts);
      if (identical(latest, draft)) {
        drafts[questionId] = saved;
        _dirtyQuestionIds.remove(questionId);
      } else {
        // 保存期间若继续输入，只吸收服务端版本并再次循环，不能覆盖较新的本地文本。
        drafts[questionId] = latest.copyWith(
          serverVersion: saved.serverVersion,
        );
      }
      _emit(_copy(drafts: drafts));
    }
  }

  PracticeSessionState _copy({
    PracticeSessionStatus? status,
    PracticePaper? paper,
    int? currentIndex,
    Map<String, PracticeDraft>? drafts,
    Map<String, AttemptAssessment>? results,
    String? errorMessage,
    String? sessionId,
    PracticeConnectionMode? connectionMode,
    String? assessorMode,
  }) {
    return PracticeSessionState(
      status: status ?? _state.status,
      paper: paper ?? _state.paper,
      currentIndex: currentIndex ?? _state.currentIndex,
      drafts: drafts ?? _state.drafts,
      results: results ?? _state.results,
      errorMessage: errorMessage,
      sessionId: sessionId ?? _state.sessionId,
      connectionMode: connectionMode ?? _state.connectionMode,
      assessorMode: assessorMode ?? _state.assessorMode,
    );
  }

  void _emit(PracticeSessionState next) {
    if (_isDisposed) return;
    _state = next;
    notifyListeners();
  }

  void _recordCurrent(
    PracticeEventType type, {
    Map<String, Object?> payload = const {},
  }) {
    final questionId = _state.currentQuestion?.id;
    if (questionId == null) return;
    _eventRecorder?.record(
      questionId: questionId,
      eventType: type,
      payload: payload,
    );
  }

  String _lengthBand(int length) {
    if (length == 0) return '0';
    if (length <= 20) return '1-20';
    if (length <= 100) return '21-100';
    if (length <= 500) return '101-500';
    return '501+';
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    // ChangeNotifier.dispose 无法等待异步；此处发起尽力刷新，页面生命周期会优先 await 同一入口。
    unawaited(flushPending().catchError((Object _) {}));
    _isDisposed = true;
    _operationGeneration += 1;
    _eventRecorder?.dispose();
    super.dispose();
  }
}

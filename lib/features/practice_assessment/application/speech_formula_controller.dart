import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/spoken_formula.dart';

enum SpeechFormulaStatus {
  idle,
  requestingPermission,
  listening,
  transcribing,
  resolving,
  resolved,
  choosingCandidate,
  clarifying,
  infrastructureError,
}

/// 语音公式 UI 的不可变状态；语义结果和基础设施错误使用不同字段承载。
final class SpeechFormulaState {
  const SpeechFormulaState({
    this.status = SpeechFormulaStatus.idle,
    this.transcript = '',
    this.resolution,
    this.selectedCandidateId,
    this.errorMessage,
    this.isSupported = true,
  });

  final SpeechFormulaStatus status;
  final String transcript;
  final SpokenFormulaResolution? resolution;
  final String? selectedCandidateId;

  /// 仅 `infrastructureError` 使用，候选和澄清不得借此伪装成失败。
  final String? errorMessage;
  final bool isSupported;

  SpokenFormulaCandidate? get selectedCandidate {
    final id = selectedCandidateId;
    if (id == null) return null;
    for (final candidate
        in resolution?.candidates ?? const <SpokenFormulaCandidate>[]) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  String? get selectedLatex => selectedCandidate?.latex;
}

/// 串联权限、ASR 和 V2 公式解析；操作序号隔离取消或确认后的迟到结果。
final class SpeechFormulaController extends ChangeNotifier {
  SpeechFormulaController({
    required this.recognizer,
    required this.repository,
    this.sourceLabel = '浏览器语音',
    this.totalDeadline = const Duration(seconds: 5),
  });

  static const _deadlineMessage = '公式解析超过 5 秒，请重新录音或使用键盘输入。';

  final SpeechFormulaRecognizer recognizer;
  final SpokenFormulaResolutionRepository repository;
  final String sourceLabel;
  final Duration totalDeadline;

  SpeechFormulaState _state = const SpeechFormulaState();
  SpeechFormulaState get state => _state;

  int _operationId = 0;
  bool _initialized = false;
  bool _disposed = false;
  Timer? _deadlineWatchdog;
  int? _deadlineOperationId;
  Future<void>? _pendingCancel;

  Future<void> startListening() async {
    final previousStatus = _state.status;
    final operationId = ++_operationId;
    _cancelDeadlineWatchdog();
    _setState(
      const SpeechFormulaState(
        status: SpeechFormulaStatus.requestingPermission,
      ),
    );
    try {
      Future<void>? cleanup = _pendingCancel;
      if (previousStatus != SpeechFormulaStatus.idle) {
        // 新录音先使旧 operation 失效，再释放旧会话，迟到 Future 无权覆盖新状态。
        cleanup = _ensureRecognizerCancelled();
      }
      // confirm 虽已同步回到 idle，其 fire-and-forget 清理仍是新会话的前置屏障。
      await cleanup;
      if (!_isCurrent(operationId)) return;
      if (!_initialized) {
        final available = await recognizer.initialize();
        if (!_isCurrent(operationId)) return;
        if (!available) {
          _showInfrastructureError(
            recognizer.initializationError?.message ?? '语音识别暂时不可用，请稍后重试。',
            '',
            false,
          );
          return;
        }
        _initialized = true;
      }
      if (!_isCurrent(operationId)) return;
      _setState(
        const SpeechFormulaState(status: SpeechFormulaStatus.listening),
      );
      await recognizer.listen(
        onResult: (words, {required isFinal, processingElapsed}) {
          _handleRecognition(
            operationId,
            words,
            isFinal: isFinal,
            processingElapsed: processingElapsed,
          );
        },
        onError: (error) {
          _handleRecognitionError(operationId, error);
        },
        onFinalizationStarted: () {
          _handleFinalizationStarted(operationId);
        },
      );
    } catch (_) {
      if (!_isCurrent(operationId)) return;
      _showInfrastructureError('无法启动麦克风，请检查浏览器权限后重试。');
    }
  }

  Future<void> stopListening() async {
    final operationId = _operationId;
    if (!_isCurrent(operationId) ||
        _state.status != SpeechFormulaStatus.listening) {
      return;
    }
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.transcribing,
        transcript: _state.transcript,
      ),
    );
    // 主动 stop 从 finalization 发起点占用总预算，不能等待 recognizer 自己返回后才计时。
    _armDeadlineWatchdog(operationId, totalDeadline, _state.transcript.trim());
    try {
      await recognizer.stop();
    } catch (_) {
      if (_isCurrent(operationId) &&
          _state.status == SpeechFormulaStatus.transcribing) {
        _showInfrastructureError('无法结束语音识别，请重新说一次。', _state.transcript.trim());
      }
      return;
    }
    if (!_isCurrent(operationId) ||
        _state.status != SpeechFormulaStatus.transcribing) {
      return;
    }
    // 只有 recognizer 的 final 回调能进入解析；partial 不可冒充完整结果。
    _showInfrastructureError('没有识别到语音，请靠近麦克风后重试。', _state.transcript.trim());
  }

  Future<void> retryResolution() async {
    // resolving 会在首个 await 前同步写入；同帧重复点击必须复用该入口门闩，避免重复请求。
    if (_state.status == SpeechFormulaStatus.resolving) return;
    final transcript = _state.transcript.trim();
    if (transcript.isEmpty) {
      await startListening();
      return;
    }
    final operationId = ++_operationId;
    _cancelDeadlineWatchdog();
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.resolving,
        transcript: transcript,
      ),
    );
    _armDeadlineWatchdog(operationId, totalDeadline, transcript);
    await _resolve(operationId, transcript, totalDeadline);
  }

  void selectCandidate(String candidateId) {
    final resolution = _state.resolution;
    if (resolution == null ||
        _state.status != SpeechFormulaStatus.choosingCandidate ||
        !_containsCandidate(resolution, candidateId)) {
      return;
    }
    ++_operationId;
    _cancelDeadlineWatchdog();
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.choosingCandidate,
        transcript: _state.transcript,
        resolution: resolution,
        selectedCandidateId: candidateId,
      ),
    );
  }

  Future<void> answerClarification(
    SpokenFormulaClarificationOption option,
  ) async {
    final resolution = _state.resolution;
    final clarification = resolution?.clarification;
    if (resolution == null ||
        clarification == null ||
        _state.status != SpeechFormulaStatus.clarifying) {
      return;
    }
    SpokenFormulaClarificationOption? currentOption;
    for (final candidateOption in clarification.options) {
      if (candidateOption.id == option.id) {
        currentOption = candidateOption;
        break;
      }
    }
    if (currentOption == null) return;

    switch (currentOption.action) {
      case SpokenFormulaClarificationAction.selectCandidate:
        final candidateId = currentOption.candidateId;
        if (candidateId == null ||
            !_containsCandidate(resolution, candidateId)) {
          return;
        }
        ++_operationId;
        _cancelDeadlineWatchdog();
        _setState(
          SpeechFormulaState(
            status: SpeechFormulaStatus.resolved,
            transcript: _state.transcript,
            resolution: resolution,
            selectedCandidateId: candidateId,
          ),
        );
        return;
      case SpokenFormulaClarificationAction.retryRecording:
        final operationId = ++_operationId;
        _cancelDeadlineWatchdog();
        await _ensureRecognizerCancelled();
        if (!_isCurrent(operationId)) return;
        _setState(const SpeechFormulaState());
        await startListening();
        return;
      case SpokenFormulaClarificationAction.useKeyboard:
        final operationId = ++_operationId;
        _cancelDeadlineWatchdog();
        await _ensureRecognizerCancelled();
        if (_isCurrent(operationId)) {
          _setState(const SpeechFormulaState());
        }
        return;
    }
  }

  /// 返回用户显式确认的公式，并立即失效旧 ASR/解析回调。
  String? confirmSelectedCandidate() {
    final latex = _state.selectedCandidate?.latex;
    if (latex == null) return null;
    ++_operationId;
    _cancelDeadlineWatchdog();
    unawaited(_ensureRecognizerCancelled());
    _setState(const SpeechFormulaState());
    return latex;
  }

  Future<void> reset() async {
    final operationId = ++_operationId;
    _cancelDeadlineWatchdog();
    try {
      await _ensureRecognizerCancelled();
    } finally {
      if (_isCurrent(operationId)) _setState(const SpeechFormulaState());
    }
  }

  void _handleRecognition(
    int operationId,
    String words, {
    required bool isFinal,
    Duration? processingElapsed,
  }) {
    if (!_isCurrent(operationId) ||
        (_state.status != SpeechFormulaStatus.listening &&
            _state.status != SpeechFormulaStatus.transcribing)) {
      return;
    }
    final transcript = words.trim();
    if (!isFinal) {
      _setState(
        SpeechFormulaState(status: _state.status, transcript: transcript),
      );
      return;
    }
    if (transcript.isEmpty) {
      _showInfrastructureError('没有识别到语音，请靠近麦克风后重试。');
      return;
    }
    // final 先切到 resolving，浏览器或插件重复回调便无法触发第二次解析。
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.resolving,
        transcript: transcript,
      ),
    );
    final remaining = totalDeadline - (processingElapsed ?? Duration.zero);
    if (processingElapsed == null) {
      // Browser 没有可信 stop-origin metadata，按 ledger 从 final transcript 重新计时。
      _armDeadlineWatchdog(operationId, totalDeadline, transcript);
    } else if (_deadlineOperationId != operationId) {
      // Local 自动停止没有经过 controller.stop，需从已报告耗时恢复同一总预算。
      _armDeadlineWatchdog(operationId, remaining, transcript);
    }
    unawaited(_resolve(operationId, transcript, remaining));
  }

  void _handleRecognitionError(
    int operationId,
    SpokenFormulaRecognitionException error,
  ) {
    if (!_isCurrent(operationId) ||
        (_state.status != SpeechFormulaStatus.listening &&
            _state.status != SpeechFormulaStatus.transcribing)) {
      return;
    }
    _showInfrastructureError(error.message, _state.transcript.trim());
  }

  void _handleFinalizationStarted(int operationId) {
    if (!_isCurrent(operationId) ||
        _state.status != SpeechFormulaStatus.listening) {
      return;
    }
    // Local 自动停止必须与手动 stop 共用同一 finalization 起点和绝对预算。
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.transcribing,
        transcript: _state.transcript,
      ),
    );
    _armDeadlineWatchdog(operationId, totalDeadline, _state.transcript.trim());
  }

  Future<void> _resolve(
    int operationId,
    String transcript,
    Duration remaining,
  ) async {
    if (remaining <= Duration.zero) {
      _expireOperation(operationId, transcript);
      return;
    }
    try {
      // caller timeout 传给传输层，本地 timeout 再约束不遵守超时契约的实现。
      final resolution = await repository
          .resolve(text: transcript, timeout: remaining)
          .timeout(remaining);
      if (!_isCurrent(operationId)) return;
      _cancelDeadlineWatchdog();
      final status = switch (resolution.outcome) {
        SpokenFormulaOutcome.resolved => SpeechFormulaStatus.resolved,
        SpokenFormulaOutcome.candidates =>
          SpeechFormulaStatus.choosingCandidate,
        SpokenFormulaOutcome.clarification => SpeechFormulaStatus.clarifying,
      };
      _setState(
        SpeechFormulaState(
          status: status,
          transcript: transcript,
          resolution: resolution,
          selectedCandidateId:
              resolution.outcome == SpokenFormulaOutcome.resolved
              ? resolution.candidates.single.id
              : null,
        ),
      );
    } on TimeoutException {
      _expireOperation(operationId, transcript);
    } on SpokenFormulaResolutionException catch (error) {
      if (_isCurrent(operationId)) {
        _showInfrastructureError(error.message, transcript);
      }
    } catch (_) {
      if (_isCurrent(operationId)) {
        _showInfrastructureError('公式解析暂时不可用，请稍后重试。', transcript);
      }
    }
  }

  void _showInfrastructureError(
    String message, [
    String transcript = '',
    bool isSupported = true,
  ]) {
    _cancelDeadlineWatchdog();
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.infrastructureError,
        transcript: transcript,
        errorMessage: message,
        isSupported: isSupported,
      ),
    );
  }

  void _armDeadlineWatchdog(
    int operationId,
    Duration remaining,
    String transcript,
  ) {
    _cancelDeadlineWatchdog();
    if (remaining <= Duration.zero) {
      _expireOperation(operationId, transcript);
      return;
    }
    _deadlineOperationId = operationId;
    _deadlineWatchdog = Timer(remaining, () {
      if (_deadlineOperationId != operationId) return;
      _deadlineWatchdog = null;
      _deadlineOperationId = null;
      _expireOperation(operationId, transcript);
    });
  }

  void _cancelDeadlineWatchdog() {
    _deadlineWatchdog?.cancel();
    _deadlineWatchdog = null;
    _deadlineOperationId = null;
  }

  void _expireOperation(int operationId, String transcript) {
    if (!_isCurrent(operationId)) return;
    // deadline 是终态边界：先失效回调并展示错误，再异步收尾，UI 不等待插件释放。
    ++_operationId;
    _cancelDeadlineWatchdog();
    _showInfrastructureError(_deadlineMessage, transcript);
    unawaited(_ensureRecognizerCancelled());
  }

  Future<void> _ensureRecognizerCancelled() {
    final existing = _pendingCancel;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _cancelRecognizerSafely().whenComplete(() {
      if (identical(_pendingCancel, operation)) _pendingCancel = null;
    });
    _pendingCancel = operation;
    return operation;
  }

  Future<void> _cancelRecognizerSafely() async {
    try {
      await recognizer.cancel();
    } catch (_) {
      // operation 已先失效；插件清理错误不得覆盖安全 UI 状态或启动并发清理。
    }
  }

  Future<void> _disposeRecognizerAfterCleanup(
    Future<void>? pendingCleanup,
  ) async {
    try {
      await pendingCleanup;
      await recognizer.dispose();
    } catch (_) {
      // 同步 dispose 无法回传异步插件错误，且页面已无安全展示目标。
    }
  }

  bool _containsCandidate(
    SpokenFormulaResolution resolution,
    String candidateId,
  ) {
    for (final candidate in resolution.candidates) {
      if (candidate.id == candidateId) return true;
    }
    return false;
  }

  bool _isCurrent(int operationId) => !_disposed && operationId == _operationId;

  void _setState(SpeechFormulaState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_operationId;
    _cancelDeadlineWatchdog();
    // dispose 与 pending cancel 串行，避免底层 capture 的迟到释放触碰下一生命周期。
    unawaited(_disposeRecognizerAfterCleanup(_pendingCancel));
    super.dispose();
  }
}

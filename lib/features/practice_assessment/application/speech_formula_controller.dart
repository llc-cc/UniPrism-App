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

  Future<void> startListening() async {
    final previousStatus = _state.status;
    final operationId = ++_operationId;
    _setState(
      const SpeechFormulaState(
        status: SpeechFormulaStatus.requestingPermission,
      ),
    );
    try {
      if (previousStatus != SpeechFormulaStatus.idle) {
        // 新录音先使旧 operation 失效，再释放旧会话，迟到 Future 无权覆盖新状态。
        await recognizer.cancel();
        if (!_isCurrent(operationId)) return;
      }
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
    final transcript = _state.transcript.trim();
    if (transcript.isEmpty) {
      await startListening();
      return;
    }
    final operationId = ++_operationId;
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.resolving,
        transcript: transcript,
      ),
    );
    await _resolve(operationId, transcript, Duration.zero);
  }

  void selectCandidate(String candidateId) {
    final resolution = _state.resolution;
    if (resolution == null ||
        _state.status != SpeechFormulaStatus.choosingCandidate ||
        !_containsCandidate(resolution, candidateId)) {
      return;
    }
    ++_operationId;
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
        await reset();
        await startListening();
        return;
      case SpokenFormulaClarificationAction.useKeyboard:
        await reset();
        return;
    }
  }

  /// 返回用户显式确认的公式，并立即失效旧 ASR/解析回调。
  String? confirmSelectedCandidate() {
    final latex = _state.selectedCandidate?.latex;
    if (latex == null) return null;
    ++_operationId;
    unawaited(recognizer.cancel().catchError((Object _) {}));
    _setState(const SpeechFormulaState());
    return latex;
  }

  Future<void> reset() async {
    ++_operationId;
    try {
      await recognizer.cancel();
    } finally {
      if (!_disposed) _setState(const SpeechFormulaState());
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
    unawaited(
      _resolve(operationId, transcript, processingElapsed ?? Duration.zero),
    );
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

  Future<void> _resolve(
    int operationId,
    String transcript,
    Duration processingElapsed,
  ) async {
    final remaining = totalDeadline - processingElapsed;
    if (remaining <= Duration.zero) {
      if (_isCurrent(operationId)) {
        _showInfrastructureError(_deadlineMessage, transcript);
      }
      return;
    }
    try {
      // caller timeout 传给传输层，本地 timeout 再约束不遵守超时契约的实现。
      final resolution = await repository
          .resolve(text: transcript, timeout: remaining)
          .timeout(remaining);
      if (!_isCurrent(operationId)) return;
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
      if (_isCurrent(operationId)) {
        _showInfrastructureError(_deadlineMessage, transcript);
      }
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
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.infrastructureError,
        transcript: transcript,
        errorMessage: message,
        isSupported: isSupported,
      ),
    );
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
    // controller 持有 recognizer；同步生命周期无法 await，因此在此收敛异步释放错误。
    unawaited(recognizer.dispose().catchError((Object _) {}));
    super.dispose();
  }
}

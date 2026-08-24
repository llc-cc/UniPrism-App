import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/spoken_formula.dart';

enum SpeechFormulaStatus {
  idle,
  requestingPermission,
  listening,
  converting,
  preview,
  error,
}

/// 语音公式 UI 的不可变状态，答案写入仍由公式输入框负责。
final class SpeechFormulaState {
  const SpeechFormulaState({
    this.status = SpeechFormulaStatus.idle,
    this.transcript = '',
    this.conversion,
    this.selectedCandidateIndex = 0,
    this.errorMessage,
    this.isSupported = true,
  });

  final SpeechFormulaStatus status;
  final String transcript;
  final SpokenFormulaConversion? conversion;
  final int selectedCandidateIndex;
  final String? errorMessage;
  final bool isSupported;

  String? get selectedLatex {
    final value = conversion;
    if (value == null) return null;
    final candidates = value.candidates;
    if (selectedCandidateIndex < 0 ||
        selectedCandidateIndex >= candidates.length) {
      return null;
    }
    return candidates[selectedCandidateIndex];
  }
}

/// 串联权限、短句识别和公式转换；操作序号用于丢弃取消后的迟到回调。
final class SpeechFormulaController extends ChangeNotifier {
  SpeechFormulaController({required this.recognizer, required this.repository});

  final SpeechFormulaRecognizer recognizer;
  final SpokenFormulaRepository repository;

  SpeechFormulaState _state = const SpeechFormulaState();
  SpeechFormulaState get state => _state;

  int _operationId = 0;
  bool _initialized = false;
  bool _disposed = false;

  Future<void> startListening() async {
    final operationId = ++_operationId;
    _setState(
      const SpeechFormulaState(
        status: SpeechFormulaStatus.requestingPermission,
      ),
    );
    try {
      if (!_initialized) {
        final available = await recognizer.initialize();
        if (!_isCurrent(operationId)) return;
        if (!available) {
          _setState(
            const SpeechFormulaState(
              status: SpeechFormulaStatus.error,
              isSupported: false,
              errorMessage: '当前浏览器无法使用语音识别，请改用最新版 Chrome 或 Edge。',
            ),
          );
          return;
        }
        _initialized = true;
      }
      _setState(
        const SpeechFormulaState(status: SpeechFormulaStatus.listening),
      );
      await recognizer.listen(
        onResult: (words, {required isFinal}) {
          _handleRecognition(operationId, words, isFinal: isFinal);
        },
      );
    } catch (_) {
      if (!_isCurrent(operationId)) return;
      _showError('无法启动麦克风，请检查浏览器权限后重试。');
    }
  }

  Future<void> stopListening() async {
    final operationId = _operationId;
    await recognizer.stop();
    if (!_isCurrent(operationId) ||
        _state.status != SpeechFormulaStatus.listening) {
      return;
    }
    final transcript = _state.transcript.trim();
    if (transcript.isEmpty) {
      _showError('没有识别到语音，请靠近麦克风后重试。');
      return;
    }
    await _convert(operationId, transcript);
  }

  Future<void> retryConversion() async {
    final transcript = _state.transcript.trim();
    if (transcript.isEmpty) {
      await startListening();
      return;
    }
    final operationId = ++_operationId;
    await _convert(operationId, transcript);
  }

  void selectCandidate(int index) {
    final conversion = _state.conversion;
    if (conversion == null ||
        index < 0 ||
        index >= conversion.candidates.length) {
      return;
    }
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.preview,
        transcript: _state.transcript,
        conversion: conversion,
        selectedCandidateIndex: index,
      ),
    );
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
  }) {
    if (!_isCurrent(operationId) ||
        _state.status != SpeechFormulaStatus.listening) {
      return;
    }
    final transcript = words.trim();
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.listening,
        transcript: transcript,
      ),
    );
    if (!isFinal) return;
    if (transcript.isEmpty) {
      _showError('没有识别到语音，请靠近麦克风后重试。');
      return;
    }
    // 浏览器停止监听时可能重复回送最终结果；先切换状态以保证只转换一次。
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.converting,
        transcript: transcript,
      ),
    );
    unawaited(_finishFinalRecognition(operationId, transcript));
  }

  Future<void> _finishFinalRecognition(
    int operationId,
    String transcript,
  ) async {
    await recognizer.stop();
    if (!_isCurrent(operationId)) return;
    await _convert(operationId, transcript);
  }

  Future<void> _convert(int operationId, String transcript) async {
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.converting,
        transcript: transcript,
      ),
    );
    try {
      final conversion = await repository.convert(text: transcript);
      if (!_isCurrent(operationId)) return;
      _setState(
        SpeechFormulaState(
          status: SpeechFormulaStatus.preview,
          transcript: transcript,
          conversion: conversion,
        ),
      );
    } on SpokenFormulaConversionException catch (error) {
      if (_isCurrent(operationId)) _showError(error.message, transcript);
    } catch (_) {
      if (_isCurrent(operationId)) {
        _showError('公式转换暂时不可用，请稍后重试。', transcript);
      }
    }
  }

  void _showError(String message, [String transcript = '']) {
    _setState(
      SpeechFormulaState(
        status: SpeechFormulaStatus.error,
        transcript: transcript,
        errorMessage: message,
      ),
    );
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
    unawaited(recognizer.cancel());
    super.dispose();
  }
}

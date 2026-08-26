import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import '../core/spoken_formula.dart';
import 'local_sensevoice_speech_formula_recognizer.dart';
import 'record_speech_audio_capture.dart';
import 'sensevoice_asr_client.dart';

typedef WebSpeechResultCallback =
    void Function(String words, {required bool isFinal});
typedef WebSpeechDriverErrorCallback = void Function(Object error);
typedef WebSpeechDriverStatusCallback = void Function(String status);

/// 浏览器语音插件的最小生产边界，使会话代际和 final fallback 可独立验证。
abstract interface class WebSpeechRecognitionDriver {
  Future<bool> initialize({
    required WebSpeechDriverErrorCallback onError,
    required WebSpeechDriverStatusCallback onStatus,
  });

  Future<void> listen({required WebSpeechResultCallback onResult});

  Future<void> stop();

  Future<void> cancel();
}

/// 根据开发期编译配置显式选择 Web 语音识别链路；非法值不得回退到浏览器能力。
SpeechFormulaRecognizer createPlatformSpeechFormulaRecognizer({
  required String mode,
  required String senseVoiceBaseUrl,
}) => switch (mode) {
  'browser' => WebSpeechFormulaRecognizer(),
  'sensevoiceLocal' => LocalSenseVoiceSpeechFormulaRecognizer(
    RecordSpeechAudioCapture(),
    SenseVoiceAsrClient(baseUrl: senseVoiceBaseUrl),
  ),
  _ => throw ArgumentError.value(
    mode,
    'mode',
    '仅支持 browser 或 sensevoiceLocal',
  ),
};

/// Chrome/Edge 短句识别适配器；只向上层暴露普通文本、最终态和安全错误。
final class WebSpeechFormulaRecognizer implements SpeechFormulaRecognizer {
  WebSpeechFormulaRecognizer({WebSpeechRecognitionDriver? driver})
    : _driver = driver ?? _SpeechToTextDriver();

  final WebSpeechRecognitionDriver _driver;
  bool _initialized = false;
  _WebSpeechSessionState _state = _WebSpeechSessionState.idle;
  int _generation = 0;
  String _lastPartialWords = '';
  bool _hasTerminalCallback = false;
  SpeechFormulaResultCallback? _onResult;
  SpeechFormulaErrorCallback? _onError;
  Completer<void>? _terminalStatus;
  Future<void>? _finishingFuture;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _driver.initialize(
      onError: _handleDriverError,
      onStatus: _handleDriverStatus,
    );
    return _initialized;
  }

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
  }) async {
    if (!_initialized) {
      throw StateError('语音识别器尚未初始化');
    }
    if (_state != _WebSpeechSessionState.idle) {
      throw StateError('上一轮浏览器语音识别仍在收尾');
    }
    final generation = ++_generation;
    _state = _WebSpeechSessionState.listening;
    _lastPartialWords = '';
    _hasTerminalCallback = false;
    _onResult = onResult;
    _onError = onError;
    _terminalStatus = Completer<void>();
    try {
      await _driver.listen(
        onResult: (words, {required isFinal}) {
          if (generation != _generation || _hasTerminalCallback) return;
          final normalized = words.trim();
          if (isFinal) {
            _hasTerminalCallback = true;
          } else if (normalized.isNotEmpty) {
            _lastPartialWords = normalized;
          }
          _invokeResultSafely(onResult, words, isFinal: isFinal);
        },
      );
    } catch (_) {
      if (generation != _generation) return;
      final finishing = _finishingFuture;
      if (finishing != null) {
        await finishing;
        return;
      }
      _hasTerminalCallback = true;
      final rollbackGeneration = ++_generation;
      _state = _WebSpeechSessionState.stopping;
      final rollback = _beginFinishing(
        () => _rollbackFailedListen(rollbackGeneration),
      );
      _invokeErrorSafely();
      await rollback;
    }
  }

  Future<void> _rollbackFailedListen(int generation) async {
    // Web driver 只有 SpeechRecognition.start() 返回后才算启动成功；throw 时先失效闭包并排空事件即可释放。
    await Future<void>.delayed(Duration.zero);
    _releaseSession(generation);
  }

  @override
  Future<void> stop() {
    if (!_initialized || _state == _WebSpeechSessionState.idle) {
      return Future<void>.value();
    }
    final finishing = _finishingFuture;
    if (finishing != null) return finishing;
    final generation = _generation;
    _state = _WebSpeechSessionState.stopping;
    return _beginFinishing(() => _stopSession(generation));
  }

  Future<void> _stopSession(int generation) async {
    await _driver.stop();
    await _awaitTerminalDrain();
    if (generation == _generation && !_hasTerminalCallback) {
      final fallback = _lastPartialWords.trim();
      if (fallback.isNotEmpty) {
        // speech_to_text 的 stop 在部分浏览器不会给 final；只提升本轮最后一个非空 partial。
        _hasTerminalCallback = true;
        final onResult = _onResult;
        if (onResult != null) {
          _invokeResultSafely(onResult, fallback, isFinal: true);
        }
      }
    }
    _releaseSession(generation);
  }

  @override
  Future<void> cancel() {
    if (!_initialized || _state == _WebSpeechSessionState.idle) {
      return Future<void>.value();
    }
    final finishing = _finishingFuture;
    if (finishing != null) return finishing;
    // 先隔离旧闭包，避免插件 cancel 期间到达的 partial 被提升为 final。
    final generation = ++_generation;
    _state = _WebSpeechSessionState.cancelling;
    _lastPartialWords = '';
    _hasTerminalCallback = false;
    _onResult = null;
    _onError = null;
    return _beginFinishing(() => _cancelSession(generation));
  }

  Future<void> _cancelSession(int generation) async {
    await _driver.cancel();
    await _awaitTerminalDrain();
    _releaseSession(generation);
  }

  Future<void> _beginFinishing(Future<void> Function() finish) {
    final completer = Completer<void>();
    _finishingFuture = completer.future;
    () async {
      try {
        await finish();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _finishingFuture = null;
      }
    }();
    return completer.future;
  }

  Future<void> _awaitTerminalDrain() async {
    final terminalStatus = _terminalStatus;
    if (terminalStatus == null) return;
    // stop/cancel Future 仅代表命令已发出；done 才表示插件已交付完本轮结果。
    await terminalStatus.future;
    // 给 done 同一事件栈派生的微任务一次排空机会，再允许替换当前会话。
    await Future<void>.delayed(Duration.zero);
  }

  void _handleDriverStatus(String status) {
    if (status != SpeechToText.doneStatus) return;
    final terminalStatus = _terminalStatus;
    if (terminalStatus != null && !terminalStatus.isCompleted) {
      terminalStatus.complete();
    }
  }

  void _handleDriverError(Object _) {
    if (_state == _WebSpeechSessionState.idle ||
        _state == _WebSpeechSessionState.cancelling ||
        _hasTerminalCallback) {
      return;
    }
    _hasTerminalCallback = true;
    if (_finishingFuture == null) {
      final generation = _generation;
      _state = _WebSpeechSessionState.stopping;
      final draining = _beginFinishing(() async {
        await _awaitTerminalDrain();
        _releaseSession(generation);
      });
      // Web onerror 紧接着发送 done；内部 drain 无外部 I/O，但仍收敛 fire-and-forget Future。
      unawaited(draining.catchError((Object _) {}));
    }
    _invokeErrorSafely();
  }

  void _invokeErrorSafely() {
    try {
      _onError?.call(
        const SpokenFormulaRecognitionException('浏览器语音识别暂时不可用，请重新说一次。'),
      );
    } catch (_) {
      // 插件事件栈不能被消费方异常打断；terminal guard 已保证不会再次回调。
    }
  }

  void _releaseSession(int generation) {
    if (generation != _generation) return;
    _state = _WebSpeechSessionState.idle;
    _lastPartialWords = '';
    _hasTerminalCallback = false;
    _onResult = null;
    _onError = null;
    _terminalStatus = null;
  }

  void _invokeResultSafely(
    SpeechFormulaResultCallback onResult,
    String words, {
    required bool isFinal,
  }) {
    try {
      onResult(words, isFinal: isFinal);
    } catch (_) {
      // 消费方异常不得破坏插件会话收尾或 terminal 去重。
    }
  }
}

final class _SpeechToTextDriver implements WebSpeechRecognitionDriver {
  final SpeechToText _speech = SpeechToText();

  @override
  Future<bool> initialize({
    required WebSpeechDriverErrorCallback onError,
    required WebSpeechDriverStatusCallback onStatus,
  }) => _speech.initialize(onError: onError, onStatus: onStatus);

  @override
  Future<void> listen({required WebSpeechResultCallback onResult}) async {
    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, isFinal: result.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: 'zh-CN',
        listenMode: ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 20),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

enum _WebSpeechSessionState { idle, listening, stopping, cancelling }

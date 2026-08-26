import 'package:speech_to_text/speech_to_text.dart';

import '../core/spoken_formula.dart';

typedef WebSpeechResultCallback =
    void Function(String words, {required bool isFinal});
typedef WebSpeechDriverErrorCallback = void Function(Object error);

/// 浏览器语音插件的最小生产边界，使会话代际和 final fallback 可独立验证。
abstract interface class WebSpeechRecognitionDriver {
  Future<bool> initialize();

  Future<void> listen({
    required WebSpeechResultCallback onResult,
    required WebSpeechDriverErrorCallback onError,
  });

  Future<void> stop();

  Future<void> cancel();
}

SpeechFormulaRecognizer createPlatformSpeechFormulaRecognizer() =>
    WebSpeechFormulaRecognizer();

/// Chrome/Edge 短句识别适配器；只向上层暴露普通文本、最终态和安全错误。
final class WebSpeechFormulaRecognizer implements SpeechFormulaRecognizer {
  WebSpeechFormulaRecognizer({WebSpeechRecognitionDriver? driver})
    : _driver = driver ?? _SpeechToTextDriver();

  final WebSpeechRecognitionDriver _driver;
  bool _initialized = false;
  int _generation = 0;
  String _lastPartialWords = '';
  bool _hasTerminalCallback = false;
  SpeechFormulaResultCallback? _onResult;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _driver.initialize();
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
    final generation = ++_generation;
    _lastPartialWords = '';
    _hasTerminalCallback = false;
    _onResult = onResult;
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
      onError: (_) {
        if (generation != _generation || _hasTerminalCallback) return;
        _hasTerminalCallback = true;
        try {
          onError?.call(
            const SpokenFormulaRecognitionException('浏览器语音识别暂时不可用，请重新说一次。'),
          );
        } catch (_) {
          // 插件事件栈不能被消费方异常打断；terminal guard 已保证不会再次回调。
        }
      },
    );
  }

  @override
  Future<void> stop() async {
    if (!_initialized) return;
    final generation = _generation;
    await _driver.stop();
    if (generation != _generation || _hasTerminalCallback) return;
    final fallback = _lastPartialWords.trim();
    if (fallback.isEmpty) return;
    // speech_to_text 的 stop 在部分浏览器不会给 final；只提升本轮最后一个非空 partial。
    _hasTerminalCallback = true;
    final onResult = _onResult;
    if (onResult != null) {
      _invokeResultSafely(onResult, fallback, isFinal: true);
    }
  }

  @override
  Future<void> cancel() async {
    // 先隔离旧闭包，避免插件 cancel 期间到达的 partial 被提升为 final。
    ++_generation;
    _lastPartialWords = '';
    _hasTerminalCallback = false;
    _onResult = null;
    if (_initialized) await _driver.cancel();
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
  Future<bool> initialize() => _speech.initialize();

  @override
  Future<void> listen({
    required WebSpeechResultCallback onResult,
    required WebSpeechDriverErrorCallback onError,
  }) async {
    // initialize 成功后再次调用会直接返回，必须在每轮 listen 前更新公开 listener。
    _speech.errorListener = onError;
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

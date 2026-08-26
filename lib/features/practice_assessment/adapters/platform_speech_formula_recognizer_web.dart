import 'package:speech_to_text/speech_to_text.dart';

import '../core/spoken_formula.dart';

typedef WebSpeechResultCallback =
    void Function(String words, {required bool isFinal});
typedef WebSpeechDriverErrorCallback = void Function(Object error);

/// 浏览器语音插件的最小生产边界，使会话代际和 final fallback 可独立验证。
abstract interface class WebSpeechRecognitionDriver {
  Future<bool> initialize({required WebSpeechDriverErrorCallback onError});

  Future<void> listen({required WebSpeechResultCallback onResult});

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
  SpeechFormulaErrorCallback? _onError;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _driver.initialize(onError: _handleDriverError);
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
    _onError = onError;
    await _driver.listen(
      onResult: (words, {required isFinal}) {
        if (generation != _generation || _hasTerminalCallback) return;
        final normalized = words.trim();
        if (isFinal) {
          _hasTerminalCallback = true;
        } else if (normalized.isNotEmpty) {
          _lastPartialWords = normalized;
        }
        onResult(words, isFinal: isFinal);
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
    _onResult?.call(fallback, isFinal: true);
  }

  @override
  Future<void> cancel() async {
    // 先隔离旧闭包，避免插件 cancel 期间到达的 partial 被提升为 final。
    ++_generation;
    _lastPartialWords = '';
    _hasTerminalCallback = false;
    _onResult = null;
    _onError = null;
    if (_initialized) await _driver.cancel();
  }

  void _handleDriverError(Object _) {
    if (_onError == null || _hasTerminalCallback) return;
    _hasTerminalCallback = true;
    _onError?.call(
      const SpokenFormulaRecognitionException('浏览器语音识别暂时不可用，请重新说一次。'),
    );
  }
}

final class _SpeechToTextDriver implements WebSpeechRecognitionDriver {
  final SpeechToText _speech = SpeechToText();

  @override
  Future<bool> initialize({required WebSpeechDriverErrorCallback onError}) =>
      _speech.initialize(onError: onError);

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

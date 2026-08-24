import 'package:speech_to_text/speech_to_text.dart';

import '../core/spoken_formula.dart';

SpeechFormulaRecognizer createPlatformSpeechFormulaRecognizer() =>
    WebSpeechFormulaRecognizer();

/// Chrome/Edge 短句识别适配器；只向上层暴露普通文本和最终态。
final class WebSpeechFormulaRecognizer implements SpeechFormulaRecognizer {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize();
    return _initialized;
  }

  @override
  Future<void> listen({required SpeechFormulaResultCallback onResult}) async {
    if (!_initialized) {
      throw StateError('语音识别器尚未初始化');
    }
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
  Future<void> stop() async {
    if (_initialized) await _speech.stop();
  }

  @override
  Future<void> cancel() async {
    if (_initialized) await _speech.cancel();
  }
}

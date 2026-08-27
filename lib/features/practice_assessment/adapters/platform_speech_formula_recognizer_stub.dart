import '../core/spoken_formula.dart';

/// 非 Web 平台不装配浏览器或本机实验链路，但仍严格校验编译配置。
SpeechFormulaRecognizer createPlatformSpeechFormulaRecognizer({
  required String mode,
  required String senseVoiceBaseUrl,
}) => switch (mode) {
  'browser' || 'sensevoiceLocal' => _UnsupportedSpeechFormulaRecognizer(),
  _ => throw ArgumentError.value(mode, 'mode', '仅支持 browser 或 sensevoiceLocal'),
};

/// 初版非 Web 平台明确报告不支持，不能误触发原生权限流程。
final class _UnsupportedSpeechFormulaRecognizer
    implements SpeechFormulaRecognizer {
  @override
  SpokenFormulaRecognitionException? get initializationError =>
      const SpokenFormulaRecognitionException('当前平台暂不支持语音识别。');

  @override
  Future<bool> initialize() async => false;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
    SpeechFormulaFinalizationStartedCallback? onFinalizationStarted,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

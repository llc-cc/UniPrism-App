import '../core/spoken_formula.dart';

SpeechFormulaRecognizer createPlatformSpeechFormulaRecognizer() =>
    _UnsupportedSpeechFormulaRecognizer();

/// 初版非 Web 平台明确报告不支持，不能误触发原生权限流程。
final class _UnsupportedSpeechFormulaRecognizer
    implements SpeechFormulaRecognizer {
  @override
  Future<bool> initialize() async => false;

  @override
  Future<void> listen({required SpeechFormulaResultCallback onResult}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

/// 浏览器语音识别结果回调；`isFinal` 为真时才允许进入公式转换。
typedef SpeechFormulaResultCallback =
    void Function(String words, {required bool isFinal});

/// 语音识别端口，隔离浏览器权限与平台插件细节。
abstract interface class SpeechFormulaRecognizer {
  Future<bool> initialize();

  Future<void> listen({required SpeechFormulaResultCallback onResult});

  Future<void> stop();

  Future<void> cancel();
}

/// 数学口语转 LaTeX 的结果；候选仅用于明确的结构歧义。
final class SpokenFormulaConversion {
  const SpokenFormulaConversion({
    required this.recognizedText,
    required this.normalizedText,
    required this.latex,
    required this.alternatives,
    required this.warnings,
  });

  final String recognizedText;
  final String normalizedText;
  final String latex;
  final List<String> alternatives;
  final List<String> warnings;

  List<String> get candidates => <String>[latex, ...alternatives];
}

/// 数学口语转换端口；远程和本地演示实现必须保持同一返回协议。
abstract interface class SpokenFormulaRepository {
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  });
}

/// 可安全展示给学生的转换失败。
final class SpokenFormulaConversionException implements Exception {
  const SpokenFormulaConversionException(this.message);

  final String message;

  @override
  String toString() => message;
}

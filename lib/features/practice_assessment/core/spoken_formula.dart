/// 浏览器语音识别结果回调；`isFinal` 为真时才允许进入公式转换。
typedef SpeechFormulaResultCallback =
    void Function(String words, {required bool isFinal});

/// 识别适配器仅通过此回调向 UI 暴露已清洗、可安全展示的错误。
typedef SpeechFormulaErrorCallback =
    void Function(SpokenFormulaRecognitionException error);

/// 语音识别端口，隔离浏览器权限与平台插件细节。
abstract interface class SpeechFormulaRecognizer {
  /// 最近一次 `initialize` 返回 false 的安全原因；成功后必须清空。
  SpokenFormulaRecognitionException? get initializationError;

  Future<bool> initialize();

  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
  });

  Future<void> stop();

  Future<void> cancel();

  /// 取消活动会话并释放识别器持有的资源；实现必须幂等。
  Future<void> dispose();
}

/// 可安全展示给学生的语音识别失败，不携带插件、网络或服务端内部信息。
final class SpokenFormulaRecognitionException implements Exception {
  const SpokenFormulaRecognitionException(this.message);

  final String message;

  @override
  String toString() => message;
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

/// 韧性公式解析的三类成功结果；数学歧义不会被折叠为基础设施错误。
enum SpokenFormulaOutcome { resolved, candidates, clarification }

/// 澄清选项允许 UI 执行的有限动作集合。
enum SpokenFormulaClarificationAction {
  selectCandidate,
  retryRecording,
  useKeyboard,
}

/// 服务端已审核的公式候选；客户端只展示和选择，不重建 AST。
final class SpokenFormulaCandidate {
  const SpokenFormulaCandidate({
    required this.id,
    required this.latex,
    required this.spokenBack,
  });

  final String id;
  final String latex;
  final String spokenBack;
}

/// 澄清问题中的可点击选项；只有选择候选动作会携带候选 ID。
final class SpokenFormulaClarificationOption {
  const SpokenFormulaClarificationOption({
    required this.id,
    required this.label,
    required this.action,
    this.candidateId,
  });

  final String id;
  final String label;
  final SpokenFormulaClarificationAction action;
  final String? candidateId;
}

/// 公式解析无法唯一确定时返回的具体问题和恢复动作。
final class SpokenFormulaClarification {
  SpokenFormulaClarification({
    required this.question,
    required this.focusText,
    required List<SpokenFormulaClarificationOption> options,
  }) : options = List<SpokenFormulaClarificationOption>.unmodifiable(options);

  final String question;
  final String focusText;
  final List<SpokenFormulaClarificationOption> options;
}

/// 版本化公式解析结果；字段与服务端公开契约一一对应，不暴露 AST 或置信度。
final class SpokenFormulaResolution {
  SpokenFormulaResolution({
    required this.resolutionId,
    required this.recognizedText,
    required this.normalizedText,
    required this.outcome,
    required List<SpokenFormulaCandidate> candidates,
    required this.clarification,
    required List<String> warnings,
  }) : candidates = List<SpokenFormulaCandidate>.unmodifiable(candidates),
       warnings = List<String>.unmodifiable(warnings);

  final String resolutionId;
  final String recognizedText;
  final String normalizedText;
  final SpokenFormulaOutcome outcome;
  final List<SpokenFormulaCandidate> candidates;
  final SpokenFormulaClarification? clarification;
  final List<String> warnings;
}

/// V2 公式解析端口；调用方必须显式给出覆盖整次解析的截止时间。
///
/// Task 7 会让控制器迁移到此端口；当前独立接口避免中间提交破坏旧控制器编译。
abstract interface class SpokenFormulaResolutionRepository {
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  });
}

/// 服务端解析结果违反公开契约时向 UI 暴露的安全错误。
final class SpokenFormulaResolutionException implements Exception {
  const SpokenFormulaResolutionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 可安全展示给学生的转换失败。
final class SpokenFormulaConversionException implements Exception {
  const SpokenFormulaConversionException(this.message);

  final String message;

  @override
  String toString() => message;
}

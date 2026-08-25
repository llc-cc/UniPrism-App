import '../core/spoken_formula.dart';
import 'practice_api_client.dart';

/// 通过练习 API 转换数学口语；客户端只映射学生可见字段。
final class RemoteSpokenFormulaRepository implements SpokenFormulaRepository {
  const RemoteSpokenFormulaRepository(this.api);

  final PracticeApiClient api;

  @override
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  }) async {
    final data = await api.request(
      'POST',
      '/api/practice/formulas/from-spoken-text',
      body: <String, Object?>{'text': text, 'locale': locale},
      // 后端最多执行两次 30 秒模型尝试，额外预算用于 HTTP 往返和响应解析。
      requestTimeout: const Duration(seconds: 70),
    );
    final recognizedText = _requiredString(data, 'recognizedText');
    final normalizedText = _requiredString(data, 'normalizedText');
    final latex = _requiredString(data, 'latex');
    return SpokenFormulaConversion(
      recognizedText: recognizedText,
      normalizedText: normalizedText,
      latex: latex,
      alternatives: _stringList(data['alternatives']).take(2).toList(),
      warnings: _stringList(data['warnings']).toList(),
    );
  }
}

String _requiredString(Map<String, Object?> data, String key) {
  final value = data[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw const SpokenFormulaConversionException('公式服务返回的数据不完整，请重新说一次。');
  }
  return value;
}

Iterable<String> _stringList(Object? value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is String && item.trim().isNotEmpty) yield item.trim();
  }
}

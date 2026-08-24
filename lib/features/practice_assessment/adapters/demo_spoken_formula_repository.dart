import '../core/spoken_formula.dart';

/// Mock 实验室的受控口语转换器，只覆盖验收样例，不代替正式模型服务。
final class DemoSpokenFormulaRepository implements SpokenFormulaRepository {
  const DemoSpokenFormulaRepository();

  static const Map<String, String> _exact = <String, String>{
    'x的平方': 'x^2',
    'x的平方加二x加一': 'x^2+2x+1',
    'x的平方加2x加1': 'x^2+2x+1',
    '根号下x加一': r'\sqrt{x+1}',
    '二分之一乘以mv的平方': r'\frac{1}{2}mv^2',
    '从零到一积分x的平方dx': r'\int_0^1x^2\,dx',
    'x加x': 'x+x',
    '当x趋近于无穷': r'x\to\infty',
    'x趋近于无穷': r'x\to\infty',
  };

  @override
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  }) async {
    if (locale != 'zh-CN') {
      throw const SpokenFormulaConversionException('初版仅支持中文普通话。');
    }
    final recognizedText = text.trim();
    final normalized = _normalize(recognizedText);
    if (normalized == '负二的平方') {
      return SpokenFormulaConversion(
        recognizedText: recognizedText,
        normalizedText: '负二的平方',
        latex: r'(-2)^2',
        alternatives: const <String>[r'-2^2'],
        warnings: const <String>['括号作用范围存在歧义，请选择符合原意的公式。'],
      );
    }
    final latex = _exact[normalized];
    if (latex == null) {
      throw const SpokenFormulaConversionException(
        '演示版暂未覆盖这条表达，请使用下方公式键盘或换一种说法。',
      );
    }
    return SpokenFormulaConversion(
      recognizedText: recognizedText,
      normalizedText: normalized,
      latex: latex,
      alternatives: const <String>[],
      warnings: const <String>[],
    );
  }
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s，。、“”‘’：:；;！？!?]'), '')
    .replaceAll('×', '乘以');

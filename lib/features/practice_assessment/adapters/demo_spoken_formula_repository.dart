import '../core/spoken_formula.dart';

/// Mock 实验室的受控口语解析器，只覆盖验收样例，不代替正式模型服务。
final class DemoSpokenFormulaRepository
    implements SpokenFormulaResolutionRepository {
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
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async {
    final recognizedText = text.trim();
    final normalized = _normalize(recognizedText);
    if (recognizedText.isEmpty || normalized.isEmpty) {
      throw const SpokenFormulaResolutionException('没有识别到有效的公式内容，请重新说一次。');
    }
    if (locale != 'zh-CN') {
      return _clarificationResolution(
        recognizedText: recognizedText,
        normalizedText: normalized,
        question: '演示解析仅支持中文普通话，请选择下一步。',
      );
    }
    if (normalized == '负二的平方') {
      return SpokenFormulaResolution(
        resolutionId: 'demo-resolution',
        recognizedText: recognizedText,
        normalizedText: normalized,
        outcome: SpokenFormulaOutcome.candidates,
        candidates: const <SpokenFormulaCandidate>[
          SpokenFormulaCandidate(
            id: 'demo-candidate-1',
            latex: r'(-2)^2',
            spokenBack: '负二整体的平方',
          ),
          SpokenFormulaCandidate(
            id: 'demo-candidate-2',
            latex: r'-2^2',
            spokenBack: '二的平方前面加负号',
          ),
        ],
        clarification: null,
        warnings: const <String>['括号作用范围存在歧义，请选择符合原意的公式。'],
      );
    }
    final latex = _exact[normalized];
    if (latex == null) {
      // 未覆盖表达仍是可恢复的数学不确定性，不能退化为通用转换异常。
      return _clarificationResolution(
        recognizedText: recognizedText,
        normalizedText: normalized,
        question: '演示解析还不能确定这段表达，请选择下一步。',
      );
    }
    return SpokenFormulaResolution(
      resolutionId: 'demo-resolution',
      recognizedText: recognizedText,
      normalizedText: normalized,
      outcome: SpokenFormulaOutcome.resolved,
      candidates: <SpokenFormulaCandidate>[
        SpokenFormulaCandidate(
          id: 'demo-candidate-1',
          latex: latex,
          spokenBack: recognizedText,
        ),
      ],
      clarification: null,
      warnings: const <String>[],
    );
  }

  SpokenFormulaResolution _clarificationResolution({
    required String recognizedText,
    required String normalizedText,
    required String question,
  }) => SpokenFormulaResolution(
    resolutionId: 'demo-resolution',
    recognizedText: recognizedText,
    normalizedText: normalizedText,
    outcome: SpokenFormulaOutcome.clarification,
    candidates: const <SpokenFormulaCandidate>[],
    clarification: SpokenFormulaClarification(
      question: question,
      focusText: recognizedText,
      options: const <SpokenFormulaClarificationOption>[
        SpokenFormulaClarificationOption(
          id: 'retry-recording',
          label: '重新录音',
          action: SpokenFormulaClarificationAction.retryRecording,
        ),
        SpokenFormulaClarificationOption(
          id: 'use-keyboard',
          label: '保留识别文字并使用公式键盘',
          action: SpokenFormulaClarificationAction.useKeyboard,
        ),
      ],
    ),
    warnings: const <String>[],
  );
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s，。、“”‘’：:；;！？!?]'), '')
    .replaceAll('×', '乘以');

import '../core/spoken_formula.dart';
import 'practice_api_client.dart';

/// 通过练习 API 解析数学口语；JSON 只在此适配器内转换为安全领域值。
final class RemoteSpokenFormulaRepository
    implements SpokenFormulaRepository, SpokenFormulaResolutionRepository {
  const RemoteSpokenFormulaRepository(this.api);

  static const _malformedResolution = SpokenFormulaResolutionException(
    '公式服务返回的数据不完整，请重新说一次。',
  );

  final PracticeApiClient api;

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async {
    final data = await api.request(
      'POST',
      '/api/practice/formulas/resolve-spoken-text',
      body: <String, Object?>{'text': text, 'locale': locale},
      requestTimeout: timeout,
    );
    return _parseResolution(data);
  }

  @override
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  }) async {
    // Task 7 迁移控制器前保留旧端口；新代码不得调用此桥或旧接口。
    final data = await api.request(
      'POST',
      '/api/practice/formulas/from-spoken-text',
      body: <String, Object?>{'text': text, 'locale': locale},
    );
    final recognizedText = _requiredLegacyString(data, 'recognizedText');
    final normalizedText = _requiredLegacyString(data, 'normalizedText');
    final latex = _requiredLegacyString(data, 'latex');
    return SpokenFormulaConversion(
      recognizedText: recognizedText,
      normalizedText: normalizedText,
      latex: latex,
      alternatives: _legacyStringList(data['alternatives']).take(2).toList(),
      warnings: _legacyStringList(data['warnings']).toList(),
    );
  }

  SpokenFormulaResolution _parseResolution(Map<String, Object?> data) {
    try {
      final outcome = _parseOutcome(data['outcome']);
      final candidates = _parseCandidates(data['candidates']);
      final clarification = data['clarification'] == null
          ? null
          : _parseClarification(data['clarification']);
      final warnings = _parseStringList(data['warnings'], maximum: 3);
      _validateResolution(outcome, candidates, clarification);
      return SpokenFormulaResolution(
        resolutionId: _parseId(data['resolutionId']),
        recognizedText: _parseText(data['recognizedText']),
        normalizedText: _parseText(data['normalizedText']),
        outcome: outcome,
        candidates: List<SpokenFormulaCandidate>.unmodifiable(candidates),
        clarification: clarification,
        warnings: List<String>.unmodifiable(warnings),
      );
    } on SpokenFormulaResolutionException {
      rethrow;
    } catch (_) {
      throw _malformedResolution;
    }
  }

  SpokenFormulaOutcome _parseOutcome(Object? value) => switch (value) {
    'resolved' => SpokenFormulaOutcome.resolved,
    'candidates' => SpokenFormulaOutcome.candidates,
    'clarification' => SpokenFormulaOutcome.clarification,
    _ => throw _malformedResolution,
  };

  List<SpokenFormulaCandidate> _parseCandidates(Object? value) {
    final items = _parseList(value, maximum: 3);
    final candidates = <SpokenFormulaCandidate>[];
    final ids = <String>{};
    for (final item in items) {
      final data = _parseObject(item);
      final id = _parseId(data['id']);
      if (!ids.add(id)) throw _malformedResolution;
      candidates.add(
        SpokenFormulaCandidate(
          id: id,
          latex: _parseText(data['latex'], maximum: 512),
          spokenBack: _parseText(data['spokenBack']),
        ),
      );
    }
    return candidates;
  }

  SpokenFormulaClarification _parseClarification(Object? value) {
    final data = _parseObject(value);
    final optionItems = _parseList(data['options'], minimum: 2, maximum: 3);
    final options = <SpokenFormulaClarificationOption>[];
    final ids = <String>{};
    for (final item in optionItems) {
      final option = _parseObject(item);
      final id = _parseId(option['id']);
      if (!ids.add(id)) throw _malformedResolution;
      final action = _parseAction(option['action']);
      final hasCandidateId = option.containsKey('candidateId');
      final candidateId = hasCandidateId
          ? _parseId(option['candidateId'])
          : null;
      options.add(
        SpokenFormulaClarificationOption(
          id: id,
          label: _parseText(option['label']),
          action: action,
          candidateId: candidateId,
        ),
      );
    }
    return SpokenFormulaClarification(
      question: _parseText(data['question']),
      focusText: _parseText(data['focusText']),
      options: List<SpokenFormulaClarificationOption>.unmodifiable(options),
    );
  }

  SpokenFormulaClarificationAction _parseAction(Object? value) =>
      switch (value) {
        'selectCandidate' => SpokenFormulaClarificationAction.selectCandidate,
        'retryRecording' => SpokenFormulaClarificationAction.retryRecording,
        'useKeyboard' => SpokenFormulaClarificationAction.useKeyboard,
        _ => throw _malformedResolution,
      };

  void _validateResolution(
    SpokenFormulaOutcome outcome,
    List<SpokenFormulaCandidate> candidates,
    SpokenFormulaClarification? clarification,
  ) {
    final hasValidCardinality = switch (outcome) {
      SpokenFormulaOutcome.resolved =>
        candidates.length == 1 && clarification == null,
      SpokenFormulaOutcome.candidates =>
        candidates.length >= 2 &&
            candidates.length <= 3 &&
            clarification == null,
      SpokenFormulaOutcome.clarification => clarification != null,
    };
    if (!hasValidCardinality) throw _malformedResolution;
    if (clarification == null) return;

    final candidateIds = candidates.map((candidate) => candidate.id).toSet();
    for (final option in clarification.options) {
      if (option.action == SpokenFormulaClarificationAction.selectCandidate) {
        if (!candidateIds.contains(option.candidateId)) {
          throw _malformedResolution;
        }
      } else if (option.candidateId != null) {
        throw _malformedResolution;
      }
    }
  }

  Map<String, Object?> _parseObject(Object? value) {
    if (value is! Map) throw _malformedResolution;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  List<Object?> _parseList(
    Object? value, {
    int minimum = 0,
    required int maximum,
  }) {
    if (value is! List || value.length < minimum || value.length > maximum) {
      throw _malformedResolution;
    }
    return List<Object?>.from(value);
  }

  List<String> _parseStringList(Object? value, {required int maximum}) {
    final items = _parseList(value, maximum: maximum);
    return items.map(_parseText).toList();
  }

  String _parseId(Object? value) {
    final id = _parseText(value, maximum: 80);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw _malformedResolution;
    }
    return id;
  }

  String _parseText(Object? value, {int maximum = 512}) {
    if (value is! String || value.trim().isEmpty || value.length > maximum) {
      throw _malformedResolution;
    }
    return value;
  }
}

String _requiredLegacyString(Map<String, Object?> data, String key) {
  final value = data[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw const SpokenFormulaConversionException('公式服务返回的数据不完整，请重新说一次。');
  }
  return value;
}

Iterable<String> _legacyStringList(Object? value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is String && item.trim().isNotEmpty) yield item.trim();
  }
}

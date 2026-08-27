import '../core/spoken_formula.dart';
import 'practice_api_client.dart';

/// 通过练习 API 解析数学口语；JSON 只在此适配器内转换为安全领域值。
final class RemoteSpokenFormulaRepository
    implements SpokenFormulaResolutionRepository {
  const RemoteSpokenFormulaRepository(this.api);

  static const _malformedResolution = SpokenFormulaResolutionException(
    '公式服务返回的数据不完整，请重新说一次。',
  );
  static const _resolutionKeys = <String>{
    'resolutionId',
    'recognizedText',
    'normalizedText',
    'outcome',
    'candidates',
    'clarification',
    'warnings',
  };
  static const _candidateKeys = <String>{'id', 'latex', 'spokenBack'};
  static const _clarificationKeys = <String>{
    'question',
    'focusText',
    'options',
  };
  static const _optionRequiredKeys = <String>{'id', 'label', 'action'};
  static const _optionOptionalKeys = <String>{'candidateId'};
  // Dart VM 与 Web 对 Unicode property escape 的支持可能不同，因此显式固化
  // 后端 Node v22（Unicode 16）`Script=Han` 的完整闭区间，避免两端安全边界漂移。
  static const _hanScriptRangeBounds = <int>[
    0x2E80,
    0x2E99,
    0x2E9B,
    0x2EF3,
    0x2F00,
    0x2FD5,
    0x3005,
    0x3005,
    0x3007,
    0x3007,
    0x3021,
    0x3029,
    0x3038,
    0x303B,
    0x3400,
    0x4DBF,
    0x4E00,
    0x9FFF,
    0xF900,
    0xFA6D,
    0xFA70,
    0xFAD9,
    0x16FE2,
    0x16FE3,
    0x16FF0,
    0x16FF1,
    0x20000,
    0x2A6DF,
    0x2A700,
    0x2B739,
    0x2B740,
    0x2B81D,
    0x2B820,
    0x2CEA1,
    0x2CEB0,
    0x2EBE0,
    0x2EBF0,
    0x2EE5D,
    0x2F800,
    0x2FA1D,
    0x30000,
    0x3134A,
    0x31350,
    0x323AF,
  ];

  // 与后端 strictModelTextSchema 保持同一拒绝面，避免响应绕过纯文本 UI 边界。
  static final List<RegExp>
  _prohibitedDisplayTextPatterns = List<RegExp>.unmodifiable(<RegExp>[
    RegExp(r'\\|\$'),
    RegExp(r'</?[A-Za-z][A-Za-z0-9:-]*(?:\s+[^<>]*?)?\s*/?>|<!--'),
    RegExp(r'`|!?\[[^\]\r\n]+\]\([^)\r\n]+\)|^\s*#{1,6}\s', multiLine: true),
    RegExp(
      r'\*\*[^*\r\n]+\*\*|__[^_\r\n]+__|~~[^~\r\n]+~~|(?:^|[\s（(])(?:\*[^*\r\n]+\*|_[^_\r\n]+_)(?=$|[\s，。！？；：、）)])',
      multiLine: true,
    ),
    RegExp(
      r'\b(?:https?|ftp|mailto|data|javascript|file):|\bwww\.|//[A-Za-z0-9]',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:^|[^A-Za-z0-9_-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,62})?\.)+[A-Za-z]{2,63}(?::\d{1,5})?(?:[/?#][^\s，。！？；：、）]*)?',
      caseSensitive: false,
    ),
  ]);

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
      // 服务端只能缩短该剩余预算，不能另起一轮完整超时。
      body: <String, Object?>{
        'text': text,
        'locale': locale,
        'budgetMs': timeout.inMilliseconds,
      },
      requestTimeout: timeout,
    );
    return _parseResolution(data);
  }

  SpokenFormulaResolution _parseResolution(Map<String, Object?> data) {
    try {
      _parseStrictObject(data, requiredKeys: _resolutionKeys);
      final outcome = _parseOutcome(data['outcome']);
      final candidates = _parseCandidates(data['candidates']);
      final clarification = data['clarification'] == null
          ? null
          : _parseClarification(data['clarification']);
      final warnings = _parseList(
        data['warnings'],
        maximum: 3,
      ).map((item) => _parseDisplayText(item, maximum: 160)).toList();
      _validateResolution(outcome, candidates, clarification);
      return SpokenFormulaResolution(
        resolutionId: _parseId(data['resolutionId']),
        recognizedText: _parsePlainText(data['recognizedText'], maximum: 300),
        normalizedText: _parsePlainText(data['normalizedText'], maximum: 300),
        outcome: outcome,
        candidates: candidates,
        clarification: clarification,
        warnings: warnings,
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
      final data = _parseStrictObject(item, requiredKeys: _candidateKeys);
      final id = _parseId(data['id']);
      if (!ids.add(id)) throw _malformedResolution;
      candidates.add(
        SpokenFormulaCandidate(
          id: id,
          latex: _parsePlainText(data['latex'], maximum: 512),
          spokenBack: _parseDisplayText(data['spokenBack'], maximum: 240),
        ),
      );
    }
    return candidates;
  }

  SpokenFormulaClarification _parseClarification(Object? value) {
    final data = _parseStrictObject(value, requiredKeys: _clarificationKeys);
    final optionItems = _parseList(data['options'], minimum: 2, maximum: 3);
    final options = <SpokenFormulaClarificationOption>[];
    final ids = <String>{};
    for (final item in optionItems) {
      final option = _parseStrictObject(
        item,
        requiredKeys: _optionRequiredKeys,
        optionalKeys: _optionOptionalKeys,
      );
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
          label: _parseDisplayText(option['label'], maximum: 120),
          action: action,
          candidateId: candidateId,
        ),
      );
    }
    return SpokenFormulaClarification(
      question: _parseDisplayText(data['question'], maximum: 240),
      focusText: _parseDisplayText(data['focusText'], maximum: 120),
      options: options,
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

  Map<String, Object?> _parseStrictObject(
    Object? value, {
    required Set<String> requiredKeys,
    Set<String> optionalKeys = const <String>{},
  }) {
    if (value is! Map) throw _malformedResolution;
    final data = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) throw _malformedResolution;
      data[entry.key as String] = entry.value;
    }
    final allowedKeys = <String>{...requiredKeys, ...optionalKeys};
    if (!data.keys.toSet().containsAll(requiredKeys) ||
        data.keys.any((key) => !allowedKeys.contains(key))) {
      throw _malformedResolution;
    }
    return data;
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

  String _parseId(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 80 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw _malformedResolution;
    }
    return value;
  }

  String _parsePlainText(Object? value, {required int maximum}) {
    if (value is! String) throw _malformedResolution;
    final text = value.trim();
    if (text.isEmpty || text.length > maximum) {
      throw _malformedResolution;
    }
    return text;
  }

  String _parseDisplayText(Object? value, {required int maximum}) {
    final text = _parsePlainText(value, maximum: maximum);
    if (_prohibitedDisplayTextPatterns.any(
          (pattern) => pattern.hasMatch(text),
        ) ||
        _hasHanAdjacentEmphasis(text)) {
      throw _malformedResolution;
    }
    return text;
  }

  bool _hasHanAdjacentEmphasis(String text) {
    final emphasisPattern = RegExp(r'\*[^*\r\n]+\*|_[^_\r\n]+_');
    const closingCharacters = <int>{
      0xFF0C,
      0x3002,
      0xFF01,
      0xFF1F,
      0xFF1B,
      0xFF1A,
      0x3001,
      0xFF09,
    };
    for (final match in emphasisPattern.allMatches(text)) {
      if (match.start == 0) continue;
      final precedingRunes = text.substring(0, match.start).runes;
      if (precedingRunes.isEmpty || !_isHan(precedingRunes.last)) continue;
      if (match.end == text.length) return true;
      final followingRune = text.substring(match.end).runes.first;
      if (_isHan(followingRune) || closingCharacters.contains(followingRune)) {
        return true;
      }
    }
    return false;
  }

  bool _isHan(int rune) {
    var lower = 0;
    var upper = _hanScriptRangeBounds.length ~/ 2 - 1;
    while (lower <= upper) {
      final middle = (lower + upper) >> 1;
      final start = _hanScriptRangeBounds[middle * 2];
      final end = _hanScriptRangeBounds[middle * 2 + 1];
      if (rune < start) {
        upper = middle - 1;
      } else if (rune > end) {
        lower = middle + 1;
      } else {
        return true;
      }
    }
    return false;
  }
}

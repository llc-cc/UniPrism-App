import '../core/spoken_formula.dart';
import 'practice_api_client.dart';

typedef _ParsedCandidates = ({
  List<SpokenFormulaCandidate> candidates,
  Set<String> rejectedIds,
  int rejectedCount,
});
typedef _ReconciledResolutionShape = ({
  SpokenFormulaOutcome outcome,
  List<SpokenFormulaCandidate> candidates,
  SpokenFormulaClarification? clarification,
});

/// 通过练习 API 解析数学口语；JSON 只在此适配器内转换为安全领域值。
final class RemoteSpokenFormulaRepository
    implements SpokenFormulaResolutionRepository {
  const RemoteSpokenFormulaRepository(this.api);

  static const _malformedResolution = SpokenFormulaResolutionException(
    '公式服务返回的数据不完整，请重新说一次。',
  );
  static const _deadlineExhausted = SpokenFormulaResolutionException(
    '公式解析剩余时间不足，请重新录音或使用公式键盘。',
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
  static const _candidateOptionalKeys = <String>{'matchKind'};
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
    final remainingMs = timeout.inMilliseconds;
    // 协议只发送完整毫秒；截断后不足 1ms 即视为耗尽，不能反向延长到 1ms。
    if (remainingMs <= 0) throw _deadlineExhausted;
    final budgetMs = remainingMs.clamp(1, 5000);
    final data = await api.request(
      'POST',
      '/api/practice/formulas/resolve-spoken-text',
      // 服务端只能缩短该剩余预算，不能另起一轮完整超时。
      body: <String, Object?>{
        'text': text,
        'locale': locale,
        'budgetMs': budgetMs,
        'candidateMetadataVersion': 1,
      },
      requestTimeout: timeout,
    );
    return _parseResolution(data);
  }

  SpokenFormulaResolution _parseResolution(Map<String, Object?> data) {
    try {
      _parseStrictObject(data, requiredKeys: _resolutionKeys);
      final requestedOutcome = _parseOutcome(data['outcome']);
      final recognizedText = _parsePlainText(
        data['recognizedText'],
        maximum: 300,
      );
      final normalizedText = _parsePlainText(
        data['normalizedText'],
        maximum: 300,
      );
      final parsedCandidates = _parseCandidates(data['candidates']);
      // 候选隔离只用于保住可信兄弟项；如果全部候选都损坏，继续按成功响应展示会掩盖协议或安全错误。
      if (parsedCandidates.rejectedCount > 0 &&
          parsedCandidates.candidates.isEmpty) {
        throw _malformedResolution;
      }
      final parsedClarification = data['clarification'] == null
          ? null
          : parsedCandidates.rejectedCount > 0
              // 候选被淘汰后不再信任服务端选择引用；只按最终存活候选重建，坏 ID 无法拖垮兄弟项。
              ? _candidateRecoveryClarification(
                  parsedCandidates.candidates,
                )
              : _parseClarification(data['clarification']);
      final warnings = _parseList(
        data['warnings'],
        maximum: 3,
      ).map((item) => _parseDisplayText(item, maximum: 160)).toList();
      final shape = _reconcileResolutionShape(
        requestedOutcome,
        parsedCandidates.candidates,
        parsedCandidates.rejectedIds,
        parsedCandidates.rejectedCount,
        parsedClarification,
      );
      _validateResolution(shape.outcome, shape.candidates, shape.clarification);
      return SpokenFormulaResolution(
        resolutionId: _parseId(data['resolutionId']),
        recognizedText: recognizedText,
        normalizedText: normalizedText,
        outcome: shape.outcome,
        candidates: shape.candidates,
        clarification: shape.clarification,
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

  _ParsedCandidates _parseCandidates(Object? value) {
    final items = _parseList(value, maximum: 3);
    final candidates = <SpokenFormulaCandidate>[];
    final observedIds = <String>{};
    final rejectedIds = <String>{};
    var rejectedCount = 0;
    for (final item in items) {
      final observedId = _tryParseCandidateId(item);
      // 即使其中一个重复项本身损坏，重复 ID 仍会破坏选择引用的唯一性，不能静默修复。
      if (observedId != null && !observedIds.add(observedId)) {
        throw _malformedResolution;
      }
      try {
        final data = _parseStrictObject(
          item,
          requiredKeys: _candidateKeys,
          optionalKeys: _candidateOptionalKeys,
        );
        final id = _parseId(data['id']);
        candidates.add(
          SpokenFormulaCandidate(
            id: id,
            latex: _parsePlainText(data['latex'], maximum: 512),
            spokenBack: _parseDisplayText(data['spokenBack'], maximum: 240),
            matchKind: _parseMatchKind(data['matchKind']),
          ),
        );
      } on SpokenFormulaResolutionException {
        // 候选之间互不信任；单项坏数据只淘汰该项，后续再按剩余基数重建结果。
        rejectedCount += 1;
        if (observedId != null) rejectedIds.add(observedId);
      }
    }
    return (
      candidates: candidates,
      rejectedIds: rejectedIds,
      rejectedCount: rejectedCount,
    );
  }

  String? _tryParseCandidateId(Object? value) {
    if (value is! Map) return null;
    Object? rawId;
    for (final entry in value.entries) {
      if (entry.key == 'id') rawId = entry.value;
    }
    try {
      return _parseId(rawId);
    } on SpokenFormulaResolutionException {
      return null;
    }
  }

  SpokenFormulaMatchKind _parseMatchKind(Object? value) => switch (value) {
    null || 'complete' => SpokenFormulaMatchKind.complete,
    'partial' => SpokenFormulaMatchKind.partial,
    _ => throw _malformedResolution,
  };

  SpokenFormulaClarification _parseClarification(Object? value) {
    final data = _parseStrictObject(value, requiredKeys: _clarificationKeys);
    // 部分公式澄清最多包含 3 个候选选择，加上续录与键盘两个恢复动作。
    // 上限在客户端同步执行，避免服务端异常响应把不可操作的长列表带进 UI。
    final optionItems = _parseList(data['options'], minimum: 2, maximum: 5);
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
        'continueRecording' =>
          SpokenFormulaClarificationAction.continueRecording,
        'retryRecording' => SpokenFormulaClarificationAction.retryRecording,
        'useKeyboard' => SpokenFormulaClarificationAction.useKeyboard,
        _ => throw _malformedResolution,
      };

  _ReconciledResolutionShape _reconcileResolutionShape(
    SpokenFormulaOutcome requestedOutcome,
    List<SpokenFormulaCandidate> candidates,
    Set<String> rejectedCandidateIds,
    int rejectedCandidateCount,
    SpokenFormulaClarification? clarification,
  ) {
    final reconciledClarification = clarification == null
        ? null
        : _withoutRejectedCandidateOptions(clarification, rejectedCandidateIds);
    if (requestedOutcome == SpokenFormulaOutcome.resolved) {
      if (rejectedCandidateCount > 0) {
        return (
          outcome: SpokenFormulaOutcome.clarification,
          candidates: candidates,
          clarification: _candidateRecoveryClarification(candidates),
        );
      }
      if (candidates.length != 1 || reconciledClarification != null) {
        throw _malformedResolution;
      }
      return (
        outcome: SpokenFormulaOutcome.resolved,
        candidates: candidates,
        clarification: null,
      );
    }
    if (requestedOutcome == SpokenFormulaOutcome.candidates) {
      if (reconciledClarification != null || candidates.isEmpty) {
        throw _malformedResolution;
      }
      if (candidates.length >= 2) {
        return (
          outcome: SpokenFormulaOutcome.candidates,
          candidates: candidates,
          clarification: null,
        );
      }
      if (rejectedCandidateCount == 0) throw _malformedResolution;
      // 多候选响应隔离坏项后只剩一个时，不自动插入，降级为显式选择和恢复动作。
      return (
        outcome: SpokenFormulaOutcome.clarification,
        candidates: candidates,
        clarification: _candidateRecoveryClarification(candidates),
      );
    }
    if (reconciledClarification == null) throw _malformedResolution;
    return (
      outcome: SpokenFormulaOutcome.clarification,
      candidates: candidates,
      clarification: reconciledClarification,
    );
  }

  SpokenFormulaClarification _withoutRejectedCandidateOptions(
    SpokenFormulaClarification clarification,
    Set<String> rejectedCandidateIds,
  ) {
    if (rejectedCandidateIds.isEmpty) return clarification;
    final options = clarification.options.where((option) {
      return option.action !=
              SpokenFormulaClarificationAction.selectCandidate ||
          !rejectedCandidateIds.contains(option.candidateId);
    }).toList();
    _ensureRecoveryOptions(options);
    return SpokenFormulaClarification(
      question: clarification.question,
      focusText: clarification.focusText,
      options: options,
    );
  }

  SpokenFormulaClarification _candidateRecoveryClarification(
    List<SpokenFormulaCandidate> candidates,
  ) {
    final options = <SpokenFormulaClarificationOption>[
      for (final (index, candidate) in candidates.indexed)
        SpokenFormulaClarificationOption(
          id: 'client-select-candidate-${index + 1}',
          label: '选择候选 ${index + 1}',
          action: SpokenFormulaClarificationAction.selectCandidate,
          candidateId: candidate.id,
        ),
    ];
    _ensureRecoveryOptions(options, requireBoth: true);
    return SpokenFormulaClarification(
      question: '已保留可信公式，请选择要插入的内容或继续补充。',
      focusText: '当前识别内容',
      options: options,
    );
  }

  void _ensureRecoveryOptions(
    List<SpokenFormulaClarificationOption> options, {
    bool requireBoth = false,
  }) {
    final actions = options.map((option) => option.action).toSet();
    if ((requireBoth || options.length < 2) &&
        !actions.contains(SpokenFormulaClarificationAction.continueRecording)) {
      options.add(
        const SpokenFormulaClarificationOption(
          id: 'client-continue-recording',
          label: '继续补充语音',
          action: SpokenFormulaClarificationAction.continueRecording,
        ),
      );
      actions.add(SpokenFormulaClarificationAction.continueRecording);
    }
    if ((requireBoth || options.length < 2) &&
        !actions.contains(SpokenFormulaClarificationAction.useKeyboard)) {
      options.add(
        const SpokenFormulaClarificationOption(
          id: 'client-use-keyboard',
          label: '使用公式键盘',
          action: SpokenFormulaClarificationAction.useKeyboard,
        ),
      );
    }
  }

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
    final selectedCandidateIds = <String>{};
    final recoveryActions = <SpokenFormulaClarificationAction>{};
    for (final option in clarification.options) {
      if (option.action == SpokenFormulaClarificationAction.selectCandidate) {
        final candidateId = option.candidateId;
        // 一个候选只能对应一个选择动作，避免重复按钮造成选择语义不唯一。
        if (!candidateIds.contains(candidateId) ||
            !selectedCandidateIds.add(candidateId!)) {
          throw _malformedResolution;
        }
      } else if (option.candidateId != null) {
        throw _malformedResolution;
      } else if (!recoveryActions.add(option.action)) {
        // 续录、重录和键盘均是全局恢复动作，重复下发只会制造歧义。
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

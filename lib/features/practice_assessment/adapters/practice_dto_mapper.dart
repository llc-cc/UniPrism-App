import '../core/practice_models.dart';

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

String _string(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

double _double(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

PracticeQuestionType _questionType(Object? value) => switch ('$value') {
  'SINGLE_CHOICE' => PracticeQuestionType.singleChoice,
  'MULTIPLE_CHOICE' => PracticeQuestionType.multipleChoice,
  'FILL_BLANK' => PracticeQuestionType.fillBlank,
  'SOLUTION' => PracticeQuestionType.solution,
  _ => throw FormatException('未知练习题型：$value'),
};

AbilityDimension _dimension(Object? value) => switch ('$value') {
  'READING' => AbilityDimension.reading,
  'UNDERSTANDING' => AbilityDimension.understanding,
  'CALCULATION' => AbilityDimension.calculation,
  'REASONING' => AbilityDimension.reasoning,
  'TECHNIQUE' => AbilityDimension.technique,
  'SELF_CORRECTION' => AbilityDimension.selfCorrection,
  'EXPRESSION' => AbilityDimension.expression,
  _ => throw FormatException('未知能力维度：$value'),
};

PracticePaper mapStudentPaper(Object? value) {
  final json = _map(value);
  return PracticePaper(
    id: _string(json['id']),
    title: _string(json['title']),
    subtitle: _string(json['subtitle']),
    source: json['source'] == 'AUTHORIZED'
        ? PracticeContentSource.authorized
        : PracticeContentSource.demonstration,
    contentVersion: _string(json['contentVersion']),
    questions: _list(json['questions']).map((raw) {
      final question = _map(raw);
      final difficulty = _map(question['difficulty']);
      return PracticeQuestion(
        id: _string(question['id']),
        number: _int(question['number']),
        type: _questionType(question['type']),
        prompt: _string(question['prompt']),
        options: _map(question['options']).map(
          (key, item) => MapEntry(key, _string(item)),
        ),
        knowledgePoints: _list(question['knowledgePoints'])
            .map(_string)
            .toList(growable: false),
        difficulty: QuestionDifficultyProfile(
          knowledgeLoad: _int(difficulty['knowledgeLoad']),
          readingLoad: _int(difficulty['readingLoad']),
          reasoningLoad: _int(difficulty['reasoningLoad']),
          calculationLoad: _int(difficulty['calculationLoad']),
          techniqueDependency: _int(difficulty['techniqueDependency']),
          stepDepth: _int(difficulty['stepDepth']),
        ),
      );
    }).toList(growable: false),
  );
}

AttemptAssessment mapStudentAttempt(Object? value) {
  final json = _map(value);
  final observations = <AbilityDimension, AbilityObservation>{};
  for (final raw in _list(json['observations'])) {
    final observation = _map(raw);
    final dimension = _dimension(observation['dimension']);
    final status = switch (_string(observation['status'])) {
      'OBSERVED' => AbilityEvidenceStatus.observed,
      'INSUFFICIENT_EVIDENCE' => AbilityEvidenceStatus.insufficientEvidence,
      _ => AbilityEvidenceStatus.notApplicable,
    };
    observations[dimension] = AbilityObservation(
      dimension: dimension,
      status: status,
      band: status == AbilityEvidenceStatus.observed
          ? _int(observation['band'])
          : null,
      confidence: _double(observation['confidence'], 1),
      evidenceStepIds: _list(observation['evidenceStepIds']).map(_string).toList(),
      factCodes: _list(observation['factCodes']).map(_string).toList(),
      errorTags: _list(observation['errorTags']).map(_string).toList(),
    );
  }
  final outcome = switch (_string(json['outcome'])) {
    'CORRECT' => AttemptOutcome.correct,
    'PARTIALLY_CORRECT' => AttemptOutcome.partiallyCorrect,
    _ => AttemptOutcome.incorrect,
  };
  return AttemptAssessment(
    questionId: _string(json['questionId']),
    outcome: outcome,
    feedback: switch (outcome) {
      AttemptOutcome.correct => '答案正确，能力维度按本次可见证据更新。',
      AttemptOutcome.partiallyCorrect => '部分步骤有效，请结合证据继续完善。',
      AttemptOutcome.incorrect => '答案需要修正；证据不足的维度不会记为低能力。',
    },
    matchedStepIds: observations.values
        .expand((item) => item.evidenceStepIds)
        .toSet()
        .toList(),
    observations: observations,
    assessorVersion: _string(json['assessorVersion']),
    rubricVersion: _string(json['rubricVersion']),
  );
}

PracticeSessionSnapshot mapSessionSnapshot(Object? value) {
  final json = _map(value);
  final progresses = <String, PracticeDraft>{};
  for (final raw in _list(json['progresses'])) {
    final progress = _map(raw);
    progresses[_string(progress['questionId'])] = PracticeDraft(
      answer: _string(progress['answer']),
      reasoning: _string(progress['reasoning']),
      serverVersion: _int(progress['draftVersion']),
    );
  }
  final attempts = <String, AttemptAssessment>{};
  var assessorMode = 'RULES';
  for (final raw in _list(json['attempts'])) {
    final attemptJson = _map(raw);
    final attempt = mapStudentAttempt(attemptJson);
    attempts[attempt.questionId] = attempt;
    assessorMode = _string(attemptJson['assessorMode'], assessorMode);
  }
  return PracticeSessionSnapshot(
    sessionId: _string(json['id']),
    status: switch (_string(json['status'])) {
      'COMPLETED' => PracticeRemoteSessionStatus.completed,
      'EXPIRED' => PracticeRemoteSessionStatus.expired,
      _ => PracticeRemoteSessionStatus.active,
    },
    revision: _int(json['revision']),
    currentQuestionNumber: _int(json['currentQuestionNumber'], 1),
    paper: mapStudentPaper(json['paper']),
    drafts: progresses,
    results: attempts,
    assessorMode: assessorMode,
  );
}

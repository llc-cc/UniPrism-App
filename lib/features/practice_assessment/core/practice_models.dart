/// 练习题型；V1 对应新高考数学卷的四类作答结构。
enum PracticeQuestionType { singleChoice, multipleChoice, fillBlank, solution }

/// 单次作答可观察的能力维度，不等同于学生的长期能力结论。
enum AbilityDimension {
  reading,
  understanding,
  calculation,
  reasoning,
  technique,
  selfCorrection,
  expression,
}

/// 能力证据状态；证据不足必须与低分严格区分。
enum AbilityEvidenceStatus { observed, insufficientEvidence, notApplicable }

/// 确定性判题结果。
enum AttemptOutcome { correct, partiallyCorrect, incorrect }

/// 题目内容来源；演示题不得伪装成官方真题。
enum PracticeContentSource { authorized, demonstration }

/// 题目自身的六维难度画像，所有等级都使用 0..4 的有序量表。
final class QuestionDifficultyProfile {
  const QuestionDifficultyProfile({
    required this.knowledgeLoad,
    required this.readingLoad,
    required this.reasoningLoad,
    required this.calculationLoad,
    required this.techniqueDependency,
    required this.stepDepth,
  }) : assert(knowledgeLoad >= 0 && knowledgeLoad <= 4),
       assert(readingLoad >= 0 && readingLoad <= 4),
       assert(reasoningLoad >= 0 && reasoningLoad <= 4),
       assert(calculationLoad >= 0 && calculationLoad <= 4),
       assert(techniqueDependency >= 0 && techniqueDependency <= 4),
       assert(stepDepth >= 0 && stepDepth <= 4);

  final int knowledgeLoad;
  final int readingLoad;
  final int reasoningLoad;
  final int calculationLoad;
  final int techniqueDependency;
  final int stepDepth;

  /// V1 总档位由子维度稳定派生，避免出现总分与维度互相矛盾。
  int get overallBand {
    final weighted =
        knowledgeLoad * 2 +
        readingLoad +
        reasoningLoad * 2 +
        calculationLoad +
        techniqueDependency * 2 +
        stepDepth;
    return (weighted / 9).round().clamp(0, 4);
  }
}

/// 一条可识别的解题步骤，关键词只用于 V1 规则评分的保守命中。
final class RubricStep {
  RubricStep({
    required this.id,
    required this.description,
    required List<String> keywords,
    required Set<AbilityDimension> dimensions,
  }) : keywords = List.unmodifiable(keywords),
       dimensions = Set.unmodifiable(dimensions);

  final String id;
  final String description;
  final List<String> keywords;
  final Set<AbilityDimension> dimensions;
}

/// 题目版本绑定的评分规则；历史作答始终引用提交时的规则版本。
final class QuestionRubric {
  QuestionRubric({
    required this.version,
    required List<String> expectedAnswers,
    required List<RubricStep> steps,
    required Set<AbilityDimension> observableDimensions,
    List<String> errorTags = const [],
  }) : expectedAnswers = List.unmodifiable(expectedAnswers),
       steps = List.unmodifiable(steps),
       observableDimensions = Set.unmodifiable(observableDimensions),
       errorTags = List.unmodifiable(errorTags) {
    if (version.trim().isEmpty) {
      throw ArgumentError.value(version, 'version', '评分规则版本不能为空');
    }
    if (this.expectedAnswers.isEmpty) {
      throw ArgumentError.value(expectedAnswers, 'expectedAnswers', '必须提供答案');
    }
    if (this.steps.isEmpty) {
      throw ArgumentError.value(steps, 'steps', '必须提供至少一个关键步骤');
    }
  }

  final String version;
  final List<String> expectedAnswers;
  final List<RubricStep> steps;
  final Set<AbilityDimension> observableDimensions;
  final List<String> errorTags;
}

/// 一道不可变的版本化练习题。
final class PracticeQuestion {
  PracticeQuestion({
    required this.id,
    required this.number,
    required this.type,
    required this.prompt,
    required Map<String, String> options,
    required List<String> knowledgePoints,
    required this.difficulty,
    this.rubric,
  }) : options = Map.unmodifiable(options),
       knowledgePoints = List.unmodifiable(knowledgePoints) {
    if (id.trim().isEmpty || number <= 0 || prompt.trim().isEmpty) {
      throw ArgumentError('题目 ID、序号和题干必须有效');
    }
    final needsOptions =
        type == PracticeQuestionType.singleChoice ||
        type == PracticeQuestionType.multipleChoice;
    if (needsOptions && this.options.isEmpty) {
      throw ArgumentError.value(options, 'options', '选择题必须提供选项');
    }
  }

  final String id;
  final int number;
  final PracticeQuestionType type;
  final String prompt;
  final Map<String, String> options;
  final List<String> knowledgePoints;
  final QuestionDifficultyProfile difficulty;

  /// 远程学生端不会收到服务端答案与 rubric；仅 Mock 规则评分持有此字段。
  final QuestionRubric? rubric;
}

/// 一套版本化练习卷；来源授权状态必须在 UI 中如实展示。
final class PracticePaper {
  PracticePaper({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.source,
    required this.contentVersion,
    required List<PracticeQuestion> questions,
  }) : questions = List.unmodifiable(questions) {
    if (id.trim().isEmpty || contentVersion.trim().isEmpty) {
      throw ArgumentError('试卷 ID 和内容版本不能为空');
    }
  }

  final String id;
  final String title;
  final String subtitle;
  final PracticeContentSource source;
  final String contentVersion;
  final List<PracticeQuestion> questions;

  bool get isAuthorizedOfficialContent =>
      source == PracticeContentSource.authorized;
}

/// 学生在一道题上的本地草稿；答案和过程分开保存以支持证据不足状态。
final class PracticeDraft {
  const PracticeDraft({
    this.answer = '',
    this.reasoning = '',
    this.revisionCount = 0,
    this.serverVersion = 0,
  });

  final String answer;
  final String reasoning;
  final int revisionCount;
  final int serverVersion;

  PracticeDraft copyWith({
    String? answer,
    String? reasoning,
    int? revisionCount,
    int? serverVersion,
  }) {
    return PracticeDraft(
      answer: answer ?? this.answer,
      reasoning: reasoning ?? this.reasoning,
      revisionCount: revisionCount ?? this.revisionCount,
      serverVersion: serverVersion ?? this.serverVersion,
    );
  }
}

enum PracticeConnectionMode { mock, remote }

enum PracticeRemoteSessionStatus { active, completed, expired }

/// 后端会话快照包含可恢复草稿和学生可见结果，不包含标准答案与 rubric。
final class PracticeSessionSnapshot {
  PracticeSessionSnapshot({
    required this.sessionId,
    required this.status,
    required this.revision,
    required this.currentQuestionNumber,
    required this.paper,
    required Map<String, PracticeDraft> drafts,
    required Map<String, AttemptAssessment> results,
    required this.assessorMode,
  }) : drafts = Map.unmodifiable(drafts),
       results = Map.unmodifiable(results);

  final String sessionId;
  final PracticeRemoteSessionStatus status;
  final int revision;
  final int currentQuestionNumber;
  final PracticePaper paper;
  final Map<String, PracticeDraft> drafts;
  final Map<String, AttemptAssessment> results;
  final String assessorMode;
}

enum PracticeEventType {
  questionViewed,
  answerStarted,
  answerChanged,
  reasoningStarted,
  reasoningChanged,
  hintRequested,
  questionRevisited,
  attemptSubmitted,
}

final class PracticeEvent {
  PracticeEvent({
    required this.clientEventId,
    required this.questionId,
    required this.eventType,
    required Map<String, Object?> payload,
    required this.clientOccurredAt,
  }) : payload = Map.unmodifiable(payload);

  final String clientEventId;
  final String questionId;
  final PracticeEventType eventType;
  final Map<String, Object?> payload;
  final DateTime clientOccurredAt;
}

/// 一次提交时由服务端或会话控制器派生的确定事实。
final class PracticeAttemptFacts {
  const PracticeAttemptFacts({
    required this.hintCount,
    required this.submissionCount,
    required this.durationSeconds,
  });

  final int hintCount;
  final int submissionCount;
  final int durationSeconds;
}

/// 单个能力维度的可追溯观察结果。
final class AbilityObservation {
  AbilityObservation({
    required this.dimension,
    required this.status,
    this.band,
    required this.confidence,
    required List<String> evidenceStepIds,
    required List<String> factCodes,
    required List<String> errorTags,
  }) : evidenceStepIds = List.unmodifiable(evidenceStepIds),
       factCodes = List.unmodifiable(factCodes),
       errorTags = List.unmodifiable(errorTags) {
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', '置信度必须在 0..1');
    }
    // 没有证据不是能力低；因此非 observed 状态禁止携带任何数值等级。
    if (status != AbilityEvidenceStatus.observed && band != null) {
      throw ArgumentError.value(band, 'band', '证据不足或不适用时不能给分');
    }
    if (status == AbilityEvidenceStatus.observed &&
        (band == null || band! < 0 || band! > 4)) {
      throw ArgumentError.value(band, 'band', '已观察等级必须在 0..4');
    }
  }

  final AbilityDimension dimension;
  final AbilityEvidenceStatus status;
  final int? band;
  final double confidence;
  final List<String> evidenceStepIds;
  final List<String> factCodes;
  final List<String> errorTags;
}

/// 学生端只保存可导航字段和公开说明，不接收后端内部能力、分数或风险。
final class PracticeNextRecommendation {
  PracticeNextRecommendation({
    required this.questionId,
    required this.questionNumber,
    required this.prompt,
    required List<String> knowledgePoints,
    required this.publicReason,
    required this.ruleVersion,
  }) : knowledgePoints = List.unmodifiable(knowledgePoints);

  final String questionId;
  final int questionNumber;
  final String prompt;
  final List<String> knowledgePoints;
  final String publicReason;
  final String ruleVersion;
}

/// 一次作答的确定性结果与七维能力证据。
final class AttemptAssessment {
  AttemptAssessment({
    required this.questionId,
    required this.outcome,
    required this.feedback,
    required List<String> matchedStepIds,
    required Map<AbilityDimension, AbilityObservation> observations,
    required this.assessorVersion,
    required this.rubricVersion,
    this.nextRecommendation,
  }) : matchedStepIds = List.unmodifiable(matchedStepIds),
       observations = Map.unmodifiable(observations);

  final String questionId;
  final AttemptOutcome outcome;
  final String feedback;
  final List<String> matchedStepIds;
  final Map<AbilityDimension, AbilityObservation> observations;
  final String assessorVersion;
  final String rubricVersion;
  final PracticeNextRecommendation? nextRecommendation;

  AbilityObservation observationFor(AbilityDimension dimension) =>
      observations[dimension] ??
      AbilityObservation(
        dimension: dimension,
        status: AbilityEvidenceStatus.notApplicable,
        confidence: 1,
        evidenceStepIds: const [],
        factCodes: const [],
        errorTags: const [],
      );
}

/// 后端长期画像的学生可见摘要；不包含内部置信度或训练标签。
final class PracticeAbilityProfileSummary {
  const PracticeAbilityProfileSummary({
    required this.dimension,
    required this.displayBand,
    required this.maturity,
    required this.evidenceCount,
  });

  final AbilityDimension dimension;
  final int? displayBand;
  final String maturity;
  final int evidenceCount;
}

/// 去标识化的小模型训练样本；只保留题目、过程事实和监督标签。
final class TrainingExampleV1 {
  TrainingExampleV1({
    required this.questionId,
    required this.questionType,
    required this.answer,
    required this.reasoning,
    required Map<String, Object?> facts,
    required Map<String, Object?> labels,
    required this.assessorVersion,
    required this.rubricVersion,
  }) : facts = Map.unmodifiable(facts),
       labels = Map.unmodifiable(labels);

  final String questionId;
  final PracticeQuestionType questionType;
  final String answer;
  final String reasoning;
  final Map<String, Object?> facts;
  final Map<String, Object?> labels;
  final String assessorVersion;
  final String rubricVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'questionId': questionId,
    'questionType': questionType.name,
    'answer': answer,
    'reasoning': reasoning,
    'facts': facts,
    'labels': labels,
    'assessorVersion': assessorVersion,
    'rubricVersion': rubricVersion,
  };
}

import 'practice_models.dart';

/// 练习数据端口；正式 HTTP 与首版内存实现共享同一调用边界。
abstract interface class PracticeRepository {
  PracticeConnectionMode get connectionMode;

  Future<PracticeSessionSnapshot> loadOrCreateSession();

  Future<PracticePaper> loadPaper();

  Future<PracticeDraft> saveDraft({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required int currentQuestionNumber,
  });

  Future<void> recordEvents({
    required String sessionId,
    required List<PracticeEvent> events,
  });

  Future<AttemptAssessment> submitAttempt({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  });

  Future<void> completeSession(String sessionId);

  Future<void> bindCurrentSession(String sessionId);

  Future<List<PracticeAbilityProfileSummary>> loadAbilityProfile();
}

/// 单次作答评分端口，后续可替换为远程大模型或本地小模型。
abstract interface class AttemptAssessor {
  AttemptAssessment assess({
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  });
}

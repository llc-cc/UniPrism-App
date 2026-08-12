import 'practice_models.dart';

/// 练习数据端口；正式 HTTP 与首版内存实现共享同一调用边界。
abstract interface class PracticeRepository {
  Future<PracticePaper> loadPaper();

  Future<AttemptAssessment> submitAttempt({
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  });
}

/// 单次作答评分端口，后续可替换为远程大模型或本地小模型。
abstract interface class AttemptAssessor {
  AttemptAssessment assess({
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  });
}

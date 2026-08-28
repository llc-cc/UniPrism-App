import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/practice_assessment.dart';

void main() {
  late MockGaokaoMathRepository repository;
  late PracticeSessionController controller;

  setUp(() {
    repository = MockGaokaoMathRepository();
    controller = PracticeSessionController(repository: repository);
  });

  tearDown(() => controller.dispose());

  test('load exposes 19 questions and starts from question one', () async {
    await controller.load();

    expect(controller.state.status, PracticeSessionStatus.ready);
    expect(controller.state.paper!.questions, hasLength(19));
    expect(controller.state.currentQuestion!.number, 1);
  });

  test('每道题分别保存答案和解题过程草稿', () async {
    await controller.load();
    controller.updateAnswer('B');
    controller.updateReasoning('先排序');
    controller.selectQuestion(1);
    controller.updateAnswer('A');
    controller.selectQuestion(0);

    expect(controller.state.currentDraft.answer, 'B');
    expect(controller.state.currentDraft.reasoning, '先排序');
  });

  test('多选切换保持去重和稳定顺序', () async {
    await controller.load();
    controller.selectQuestion(8);

    controller.toggleOption('C');
    controller.toggleOption('A');
    expect(controller.state.currentDraft.answer, 'AC');
    controller.toggleOption('C');
    expect(controller.state.currentDraft.answer, 'A');
  });

  test('failed submission keeps the draft and supports retry', () async {
    await controller.load();
    controller.updateAnswer('B');
    repository.failNextSubmission = true;

    await controller.submitCurrent();

    expect(controller.state.status, PracticeSessionStatus.failure);
    expect(controller.state.currentDraft.answer, 'B');
    expect(controller.state.errorMessage, isNotEmpty);

    await controller.retrySubmission();

    expect(controller.state.status, PracticeSessionStatus.ready);
    expect(controller.state.resultForCurrent, isNotNull);
    expect(controller.state.errorMessage, isNull);
  });

  test('前后导航不会越过试卷边界', () async {
    await controller.load();

    controller.previousQuestion();
    expect(controller.state.currentIndex, 0);
    controller.selectQuestion(18);
    controller.nextQuestion();
    expect(controller.state.currentIndex, 18);
  });

  test('提交后保留当前题，学生点击推荐才跳转到后端指定题目', () async {
    await controller.load();
    controller.updateAnswer('B');

    await controller.submitCurrent();

    expect(controller.state.currentIndex, 0);
    expect(controller.state.resultForCurrent?.nextRecommendation, isNotNull);
    controller.openCurrentRecommendation();
    expect(controller.state.currentIndex, 1);
  });

  test('推荐题 ID 不在当前试卷时留在原题并返回失败', () async {
    final remote = _RecordingRepository(
      paper: await repository.loadPaper(),
      nextRecommendation: PracticeNextRecommendation(
        questionId: 'missing-question',
        questionNumber: 999,
        prompt: '不存在的题目',
        knowledgePoints: const ['测试'],
        publicReason: '测试失效引用',
        ruleVersion: 'adaptive-rule-v1',
      ),
    );
    final remoteController = PracticeSessionController(repository: remote);
    addTearDown(remoteController.dispose);
    await remoteController.load();
    remoteController.updateAnswer('B');
    await remoteController.submitCurrent();

    expect(remoteController.openCurrentRecommendation(), isFalse);
    expect(remoteController.state.currentIndex, 0);
  });

  test('Mock 最后一题推荐回绕到第一题', () async {
    await controller.load();
    controller.selectQuestion(18);
    controller.updateAnswer('证明完成');
    await controller.submitCurrent();

    expect(
      controller.state.resultForCurrent?.nextRecommendation?.questionNumber,
      1,
    );
  });

  test('提交过程中忽略重复提交', () async {
    final blockingRepository = _BlockingRepository(
      paper: await repository.loadPaper(),
    );
    final blockingController = PracticeSessionController(
      repository: blockingRepository,
    );
    addTearDown(blockingController.dispose);
    await blockingController.load();
    blockingController.updateAnswer('B');

    final first = blockingController.submitCurrent();
    final second = blockingController.submitCurrent();
    await Future<void>.delayed(Duration.zero);

    expect(blockingRepository.submissionCount, 1);
    blockingRepository.release();
    await Future.wait(<Future<void>>[first, second]);
  });

  test('只有 19 题都有结果后才能完成整卷', () async {
    await controller.load();
    expect(controller.complete, throwsStateError);

    final questions = controller.state.paper!.questions;
    for (var index = 0; index < questions.length; index++) {
      controller.selectQuestion(index);
      controller.updateAnswer(questions[index].rubric!.expectedAnswers.first);
      await controller.submitCurrent();
    }

    await controller.complete();
    expect(controller.state.status, PracticeSessionStatus.completed);
  });

  test('远程加载恢复服务端当前题号和草稿版本', () async {
    final paper = await repository.loadPaper();
    final remote = _RecordingRepository(
      paper: paper,
      currentQuestionNumber: 5,
      drafts: {
        paper.questions[4].id: const PracticeDraft(
          answer: 'B',
          reasoning: '标准方程',
          serverVersion: 3,
        ),
      },
    );
    final remoteController = PracticeSessionController(repository: remote);
    addTearDown(remoteController.dispose);

    await remoteController.load();

    expect(remoteController.state.sessionId, 'remote-session');
    expect(remoteController.state.currentIndex, 4);
    expect(remoteController.state.currentDraft.answer, 'B');
    expect(remoteController.state.currentDraft.serverVersion, 3);
  });

  test('提交前依次保存最新草稿、刷新事件再创建正式提交', () async {
    final remote = _RecordingRepository(paper: await repository.loadPaper());
    final remoteController = PracticeSessionController(repository: remote);
    addTearDown(remoteController.dispose);
    await remoteController.load();
    remoteController.updateAnswer('B');

    await remoteController.submitCurrent();

    expect(remote.calls.take(3), [
      'saveDraft',
      'recordEvents',
      'submitAttempt',
    ]);
  });

  test('远程作答将答案、过程和提交事实批量写入同一事件记录链', () async {
    final remote = _RecordingRepository(paper: await repository.loadPaper());
    final remoteController = PracticeSessionController(repository: remote);
    addTearDown(remoteController.dispose);
    await remoteController.load();

    remoteController.updateAnswer('B');
    remoteController.updateReasoning('先列出已知条件，再代入计算。');
    await remoteController.submitCurrent();

    final events = remote.recordedEventBatches.single;
    expect(events.map((event) => event.eventType), [
      PracticeEventType.questionViewed,
      PracticeEventType.answerChanged,
      PracticeEventType.reasoningChanged,
      PracticeEventType.attemptSubmitted,
    ]);
    expect(events.map((event) => event.questionId).toSet(), {
      remote.paper.questions.first.id,
    });
    expect(events[1].payload, {'lengthBand': '1-20'});
    expect(events[2].payload, {'lengthBand': '1-20'});
    expect(events[1].payload.values, isNot(contains('B')));
    expect(events[2].payload.values, isNot(contains('先列出已知条件，再代入计算。')));
  });

  test('提交响应丢失后重试沿用已保存草稿和同一服务端版本', () async {
    final remote = _RecordingRepository(
      paper: await repository.loadPaper(),
      failNextAttempt: true,
    );
    final remoteController = PracticeSessionController(repository: remote);
    addTearDown(remoteController.dispose);
    await remoteController.load();
    remoteController.updateAnswer('B');

    await remoteController.submitCurrent();
    expect(remoteController.state.status, PracticeSessionStatus.failure);
    expect(remote.savedDraftVersions, [1]);

    await remoteController.retrySubmission();

    expect(remote.savedDraftVersions, [1, 1]);
    expect(remote.calls.where((call) => call == 'saveDraft'), hasLength(1));
  });

  test('切题前刷新未保存草稿并把服务端当前位置更新为目标题', () async {
    final paper = await repository.loadPaper();
    final remote = _RecordingRepository(paper: paper);
    final remoteController = PracticeSessionController(
      repository: remote,
      draftSaveDebounce: const Duration(hours: 1),
    );
    addTearDown(remoteController.dispose);
    await remoteController.load();
    remoteController.updateAnswer('B');

    remoteController.selectQuestion(1);
    await remoteController.flushPending();

    expect(remote.savedQuestionIds, [paper.questions.first.id]);
    expect(remote.savedCurrentQuestionNumbers, [2]);
    expect(
      remoteController.state.drafts[paper.questions.first.id]!.serverVersion,
      1,
    );
  });

  test('远程输入停止后自动防抖保存草稿', () async {
    final remote = _RecordingRepository(paper: await repository.loadPaper());
    final remoteController = PracticeSessionController(
      repository: remote,
      draftSaveDebounce: Duration.zero,
    );
    addTearDown(remoteController.dispose);
    await remoteController.load();

    remoteController.updateReasoning('先列出条件，再代入计算');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await remoteController.flushPending();

    expect(remote.calls.where((call) => call == 'saveDraft'), hasLength(1));
    expect(remoteController.state.currentDraft.serverVersion, 1);
  });
}

final class _RecordingRepository implements PracticeRepository {
  _RecordingRepository({
    required this.paper,
    this.currentQuestionNumber = 1,
    this.drafts = const {},
    this.failNextAttempt = false,
    this.nextRecommendation,
  });

  final PracticePaper paper;
  final int currentQuestionNumber;
  final Map<String, PracticeDraft> drafts;
  bool failNextAttempt;
  final PracticeNextRecommendation? nextRecommendation;
  final List<String> calls = [];
  final List<List<PracticeEvent>> recordedEventBatches = [];
  final List<int> savedDraftVersions = [];
  final List<String> savedQuestionIds = [];
  final List<int> savedCurrentQuestionNumbers = [];

  @override
  PracticeConnectionMode get connectionMode => PracticeConnectionMode.remote;

  @override
  Future<PracticeSessionSnapshot> loadOrCreateSession() async =>
      PracticeSessionSnapshot(
        sessionId: 'remote-session',
        status: PracticeRemoteSessionStatus.active,
        revision: 1,
        currentQuestionNumber: currentQuestionNumber,
        paper: paper,
        drafts: drafts,
        results: const {},
        assessorMode: 'RULES',
      );

  @override
  Future<PracticePaper> loadPaper() async => paper;

  @override
  Future<PracticeDraft> saveDraft({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required int currentQuestionNumber,
  }) async {
    calls.add('saveDraft');
    savedQuestionIds.add(question.id);
    savedCurrentQuestionNumbers.add(currentQuestionNumber);
    return draft.copyWith(serverVersion: draft.serverVersion + 1);
  }

  @override
  Future<void> recordEvents({
    required String sessionId,
    required List<PracticeEvent> events,
  }) async {
    calls.add('recordEvents');
    recordedEventBatches.add(List<PracticeEvent>.of(events));
  }

  @override
  Future<AttemptAssessment> submitAttempt({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  }) async {
    calls.add('submitAttempt');
    savedDraftVersions.add(draft.serverVersion);
    if (failNextAttempt) {
      failNextAttempt = false;
      throw StateError('response lost');
    }
    final assessed = const RuleBasedAttemptAssessor().assess(
      question: question,
      draft: draft,
      facts: facts,
    );
    if (nextRecommendation == null) return assessed;
    return AttemptAssessment(
      questionId: assessed.questionId,
      outcome: assessed.outcome,
      feedback: assessed.feedback,
      matchedStepIds: assessed.matchedStepIds,
      observations: assessed.observations,
      assessorVersion: assessed.assessorVersion,
      rubricVersion: assessed.rubricVersion,
      nextRecommendation: nextRecommendation,
    );
  }

  @override
  Future<void> completeSession(String sessionId) async => calls.add('complete');

  @override
  Future<void> bindCurrentSession(String sessionId) async => calls.add('bind');

  @override
  Future<List<PracticeAbilityProfileSummary>> loadAbilityProfile() async =>
      const [];
}

final class _BlockingRepository implements PracticeRepository {
  _BlockingRepository({required this.paper});

  final PracticePaper paper;
  final Completer<void> _gate = Completer<void>();
  int submissionCount = 0;

  @override
  PracticeConnectionMode get connectionMode => PracticeConnectionMode.mock;

  void release() => _gate.complete();

  @override
  Future<PracticePaper> loadPaper() async => paper;

  @override
  Future<PracticeSessionSnapshot> loadOrCreateSession() async =>
      PracticeSessionSnapshot(
        sessionId: 'blocking-session',
        status: PracticeRemoteSessionStatus.active,
        revision: 0,
        currentQuestionNumber: 1,
        paper: paper,
        drafts: const {},
        results: const {},
        assessorMode: 'RULES',
      );

  @override
  Future<PracticeDraft> saveDraft({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required int currentQuestionNumber,
  }) async => draft.copyWith(serverVersion: draft.serverVersion + 1);

  @override
  Future<void> recordEvents({
    required String sessionId,
    required List<PracticeEvent> events,
  }) async {}

  @override
  Future<AttemptAssessment> submitAttempt({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  }) async {
    submissionCount += 1;
    await _gate.future;
    return const RuleBasedAttemptAssessor().assess(
      question: question,
      draft: draft,
      facts: facts,
    );
  }

  @override
  Future<void> completeSession(String sessionId) async {}

  @override
  Future<void> bindCurrentSession(String sessionId) async {}

  @override
  Future<List<PracticeAbilityProfileSummary>> loadAbilityProfile() async =>
      const [];
}

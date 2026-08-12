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

    expect(remote.calls.take(3), ['saveDraft', 'recordEvents', 'submitAttempt']);
  });
}

final class _RecordingRepository implements PracticeRepository {
  _RecordingRepository({
    required this.paper,
    this.currentQuestionNumber = 1,
    this.drafts = const {},
  });

  final PracticePaper paper;
  final int currentQuestionNumber;
  final Map<String, PracticeDraft> drafts;
  final List<String> calls = [];

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
    return draft.copyWith(serverVersion: draft.serverVersion + 1);
  }

  @override
  Future<void> recordEvents({
    required String sessionId,
    required List<PracticeEvent> events,
  }) async => calls.add('recordEvents');

  @override
  Future<AttemptAssessment> submitAttempt({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  }) async {
    calls.add('submitAttempt');
    return const RuleBasedAttemptAssessor().assess(
      question: question,
      draft: draft,
      facts: facts,
    );
  }

  @override
  Future<void> completeSession(String sessionId) async => calls.add('complete');
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
}

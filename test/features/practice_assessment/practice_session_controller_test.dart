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
      controller.updateAnswer(questions[index].rubric.expectedAnswers.first);
      await controller.submitCurrent();
    }

    controller.complete();
    expect(controller.state.status, PracticeSessionStatus.completed);
  });
}

final class _BlockingRepository implements PracticeRepository {
  _BlockingRepository({required this.paper});

  final PracticePaper paper;
  final Completer<void> _gate = Completer<void>();
  int submissionCount = 0;

  void release() => _gate.complete();

  @override
  Future<PracticePaper> loadPaper() async => paper;

  @override
  Future<AttemptAssessment> submitAttempt({
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
}

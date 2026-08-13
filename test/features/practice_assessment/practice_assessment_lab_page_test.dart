import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/practice_assessment.dart';

void main() {
  testWidgets('实验室显示加载状态和非官方演示内容声明', (tester) async {
    final source = MockGaokaoMathRepository();
    final repository = _DelayedLoadRepository(await source.loadPaper());
    final controller = PracticeSessionController(repository: repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.release();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('practice-paper-disclaimer')),
      findsOneWidget,
    );
    expect(find.textContaining('自造演示题'), findsWidgets);
    expect(find.byKey(const ValueKey('practice-question-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-reasoning-input')),
      findsOneWidget,
    );
  });

  testWidgets('客观题可不填过程提交并明确显示证据不足', (tester) async {
    final controller = PracticeSessionController(
      repository: MockGaokaoMathRepository(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('practice-option-B')));
    final submit = find.byKey(const ValueKey('practice-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.textContaining('答案正确'), findsWidgets);
    expect(find.text('过程证据不足'), findsOneWidget);
  });

  testWidgets('提交后显示推荐下一题卡片，点击后才进入推荐题', (tester) async {
    final controller = PracticeSessionController(
      repository: MockGaokaoMathRepository(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('practice-option-B')));
    final submit = find.byKey(const ValueKey('practice-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(controller.state.currentIndex, 0);
    final recommendation = find.byKey(
      const ValueKey('practice-next-recommendation'),
    );
    expect(recommendation, findsOneWidget);
    final open = find.byKey(const ValueKey('practice-open-recommendation'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();

    expect(controller.state.currentIndex, 1);
    expect(controller.state.currentQuestion?.number, 2);
  });

  testWidgets('多选题使用独立选项控件并保存多个选择', (tester) async {
    final controller = PracticeSessionController(
      repository: MockGaokaoMathRepository(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    controller.selectQuestion(8);
    await tester.pump();
    final optionC = find.byKey(const ValueKey('practice-option-C'));
    await tester.ensureVisible(optionC);
    await tester.tap(optionC);
    await tester.tap(find.byKey(const ValueKey('practice-option-A')));

    expect(controller.state.currentDraft.answer, 'AC');
  });

  testWidgets('提交失败保留页面与草稿并可重试', (tester) async {
    final repository = MockGaokaoMathRepository()..failNextSubmission = true;
    final controller = PracticeSessionController(repository: repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('practice-option-B')));
    final submit = find.byKey(const ValueKey('practice-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('practice-retry')), findsOneWidget);
    expect(controller.state.currentDraft.answer, 'B');
    final retry = find.byKey(const ValueKey('practice-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.textContaining('答案正确'), findsWidgets);
  });

  testWidgets('解答题长内容可滚动且提供答案和过程输入', (tester) async {
    final controller = PracticeSessionController(
      repository: MockGaokaoMathRepository(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    controller.selectQuestion(18);
    await tester.pump();

    expect(find.byKey(const ValueKey('practice-answer-input')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-reasoning-input')),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('远程模式明确显示后端连接、会话与评分模式', (tester) async {
    final source = MockGaokaoMathRepository();
    final repository = _DelayedLoadRepository(
      await source.loadPaper(),
      mode: PracticeConnectionMode.remote,
    );
    final controller = PracticeSessionController(repository: repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    repository.release();
    await tester.pumpAndSettle();

    expect(find.textContaining('后端已连接'), findsOneWidget);
    expect(find.textContaining('delayed-session'), findsOneWidget);
    expect(find.textContaining('RULES'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('应用退到后台时立即刷新远程草稿', (tester) async {
    final source = MockGaokaoMathRepository();
    final repository = _DelayedLoadRepository(
      await source.loadPaper(),
      mode: PracticeConnectionMode.remote,
    );
    final controller = PracticeSessionController(
      repository: repository,
      draftSaveDebounce: const Duration(hours: 1),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    repository.release();
    await tester.pumpAndSettle();
    controller.updateAnswer('B');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(repository.saveDraftCount, 1);
  });

  testWidgets('只有填空题使用数学公式输入框', (tester) async {
    final controller = PracticeSessionController(
      repository: MockGaokaoMathRepository(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    controller.selectQuestion(11);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-math-answer-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('practice-answer-input')), findsNothing);

    controller.selectQuestion(18);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-math-answer-field')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('practice-answer-input')), findsOneWidget);
  });

  testWidgets('填空公式草稿切题后仍按题目隔离恢复', (tester) async {
    final controller = PracticeSessionController(
      repository: MockGaokaoMathRepository(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    controller.selectQuestion(11);
    controller.updateAnswer(r'\frac{3}{2}');
    controller.selectQuestion(12);
    controller.selectQuestion(11);
    await tester.pump();

    expect(controller.state.currentDraft.answer, r'\frac{3}{2}');
    expect(
      find.byKey(const ValueKey('practice-math-answer-field')),
      findsOneWidget,
    );
  });
}

Widget _app(PracticeSessionController controller) {
  return MaterialApp(home: PracticeAssessmentLabPage(controller: controller));
}

final class _DelayedLoadRepository implements PracticeRepository {
  _DelayedLoadRepository(this.paper, {this.mode = PracticeConnectionMode.mock});

  final PracticePaper paper;
  final PracticeConnectionMode mode;
  final Completer<void> _gate = Completer<void>();
  int saveDraftCount = 0;

  @override
  PracticeConnectionMode get connectionMode => mode;

  void release() => _gate.complete();

  @override
  Future<PracticePaper> loadPaper() async {
    await _gate.future;
    return paper;
  }

  @override
  Future<PracticeSessionSnapshot> loadOrCreateSession() async {
    await _gate.future;
    return PracticeSessionSnapshot(
      sessionId: 'delayed-session',
      status: PracticeRemoteSessionStatus.active,
      revision: 0,
      currentQuestionNumber: 1,
      paper: paper,
      drafts: const {},
      results: const {},
      assessorMode: 'RULES',
    );
  }

  @override
  Future<PracticeDraft> saveDraft({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required int currentQuestionNumber,
  }) async {
    saveDraftCount += 1;
    return draft.copyWith(serverVersion: draft.serverVersion + 1);
  }

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

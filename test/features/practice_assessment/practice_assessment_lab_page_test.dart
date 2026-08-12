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

  testWidgets('多选题使用独立选项控件并保存多个选择', (tester) async {
    final controller = PracticeSessionController(
      repository: MockGaokaoMathRepository(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    controller.selectQuestion(8);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-option-C')));
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
}

Widget _app(PracticeSessionController controller) {
  return MaterialApp(home: PracticeAssessmentLabPage(controller: controller));
}

final class _DelayedLoadRepository implements PracticeRepository {
  _DelayedLoadRepository(this.paper);

  final PracticePaper paper;
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<PracticePaper> loadPaper() async {
    await _gate.future;
    return paper;
  }

  @override
  Future<AttemptAssessment> submitAttempt({
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
}

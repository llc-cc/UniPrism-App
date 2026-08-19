import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/classroom_remediation_panel.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/guided_practice_dialog.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/inline_practice_panel.dart';

void main() {
  testWidgets('free text practice submits distinct reasoning and answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    GuidedPracticeDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlinePracticeAnswerPanel(
            practice: const RemoteGuidedPractice(
              id: 'set-determinacy-v1',
              title: '确定性辨析',
              prompt: '“我班高个子男生”能否构成集合？为什么？',
              reasoningLabel: '说明判断依据',
              answerLabel: '写出结论',
            ),
            isConsolidation: true,
            onSubmit: (draft) async {
              submitted = draft;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('inline-practice-reasoning-input')),
      '“高个子”标准不明确，违反集合元素的确定性。',
    );
    await tester.enterText(
      find.byKey(const ValueKey('inline-practice-answer-input')),
      '不能构成集合',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('inline-practice-submit-button')),
    );
    await tester.pump();

    expect(submitted?.reasoning, '“高个子”标准不明确，违反集合元素的确定性。');
    expect(submitted?.answer, '不能构成集合');
  });

  testWidgets('repair explanation advances before showing formal practice', (
    tester,
  ) async {
    var continueCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClassroomRemediationPanel(
            topic: '无序性',
            feedback: '需要补充无序性的判断依据。',
            repairFocus: '元素完全相同，排列顺序不影响集合。',
            onContinue: () async {
              continueCalls += 1;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('remediation-quick-yes')), findsNothing);
    expect(find.byKey(const ValueKey('remediation-next-step')), findsOneWidget);
    expect(find.text('下一步怎么做'), findsOneWidget);
    expect(find.text('我明白了，继续这道练习'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('remediation-start-consolidation')),
    );
    await tester.pump();

    expect(continueCalls, 1);
  });
}

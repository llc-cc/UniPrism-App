import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_assessment_lab_page.dart';

void main() {
  testWidgets('Mock 练习页面为填空题装配真实语音入口', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: PracticeAssessmentLabPage.mock()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('practice-question-12')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-formula-voice-start')),
      findsOneWidget,
    );
  });
}

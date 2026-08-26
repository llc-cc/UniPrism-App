import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_assessment_lab_page.dart';

void main() {
  test('Mock 题目可单独注入远程语音公式仓库', () {
    final repository = _FakeSpokenFormulaRepository();

    final page = PracticeAssessmentLabPage.mock(
      spokenFormulaRepository: repository,
    );

    expect(page.speechFormulaController?.repository, same(repository));
    page.speechFormulaController?.dispose();
    page.controller.dispose();
  });

  test('Mock 页面保留显式注入的识别器与来源标签', () {
    final recognizer = _FakeRecognizer();

    final page = PracticeAssessmentLabPage.mock(
      speechFormulaRecognizer: recognizer,
      speechFormulaSourceLabel: '本机 SenseVoice',
    );

    expect(page.speechFormulaController?.recognizer, same(recognizer));
    expect(page.speechFormulaController?.sourceLabel, '本机 SenseVoice');
    page.speechFormulaController?.dispose();
    page.controller.dispose();
  });

  test('Remote 页面保留显式注入的识别器与来源标签', () {
    final recognizer = _FakeRecognizer();

    final page = PracticeAssessmentLabPage.remote(
      baseUrl: 'https://example.invalid',
      speechFormulaRecognizer: recognizer,
      speechFormulaSourceLabel: '本机 SenseVoice',
    );

    expect(page.speechFormulaController?.recognizer, same(recognizer));
    expect(page.speechFormulaController?.sourceLabel, '本机 SenseVoice');
    page.speechFormulaController?.dispose();
    page.controller.dispose();
  });

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

final class _FakeRecognizer implements SpeechFormulaRecognizer {
  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

final class _FakeSpokenFormulaRepository implements SpokenFormulaRepository {
  @override
  Future<SpokenFormulaConversion> convert({
    required String text,
    String locale = 'zh-CN',
  }) async => SpokenFormulaConversion(
    recognizedText: text,
    normalizedText: text,
    latex: 'x^2',
    alternatives: const <String>[],
    warnings: const <String>[],
  );
}

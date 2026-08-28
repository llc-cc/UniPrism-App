import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_assessment_lab_page.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/math_answer_field.dart';

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

  test('Mock 默认仓库只暴露 V2 解析端口', () {
    final page = PracticeAssessmentLabPage.mock();

    final repository = page.speechFormulaController?.repository;
    expect(repository, isA<SpokenFormulaResolutionRepository>());
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

  testWidgets('375x812 实际练习页复用外层纵滚且长候选可滚到内容', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recognizer = _FakeRecognizer();

    await tester.pumpWidget(
      MaterialApp(
        home: PracticeAssessmentLabPage.mock(
          speechFormulaRecognizer: recognizer,
          spokenFormulaRepository: const _LongCandidateRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final question = find.byKey(const ValueKey('practice-question-12'));
    await tester.ensureVisible(question);
    await tester.pumpAndSettle();
    await tester.tap(question);
    await tester.pump();

    final input = find.byKey(const ValueKey('practice-math-answer-input'));
    await tester.ensureVisible(input);
    await tester.pump();
    await tester.tap(input);
    await tester.pump();
    final start = find.byKey(const ValueKey('practice-formula-voice-start'));
    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
    await tester.pump();
    recognizer.emit('实际页面三个长候选', isFinal: true);
    for (var index = 0; index < 5; index++) {
      await tester.pump();
    }

    final mathAnswerField = find.byType(MathAnswerField);
    final localVerticalScrolls = find.descendant(
      of: mathAnswerField,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.vertical,
      ),
    );
    expect(localVerticalScrolls, findsNothing);
    final pageVerticalScroll = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.vertical,
    );
    expect(pageVerticalScroll, findsOneWidget);
    final pageScrollable = find.descendant(
      of: pageVerticalScroll,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    final pagePosition = tester
        .state<ScrollableState>(pageScrollable.first)
        .position;
    expect(pagePosition.maxScrollExtent, greaterThan(pagePosition.pixels));
    final pixelsBefore = pagePosition.pixels;
    final lastCandidate = find.byKey(
      const ValueKey('practice-formula-voice-candidate-page-c'),
    );
    expect(lastCandidate, findsOneWidget);
    final lastSpokenBack = find.byKey(
      const ValueKey('practice-formula-voice-spoken-back-page-c'),
    );
    await tester.ensureVisible(lastSpokenBack);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(pagePosition.pixels, greaterThan(pixelsBefore));
    final viewportRect = tester.getRect(pageScrollable.first);
    final spokenBackRect = tester.getRect(lastSpokenBack);
    expect(spokenBackRect.top, lessThan(viewportRect.bottom));
    expect(spokenBackRect.bottom, greaterThan(viewportRect.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('页面销毁只释放注入 recognizer 一次', (tester) async {
    final recognizer = _FakeRecognizer();

    await tester.pumpWidget(
      MaterialApp(
        home: PracticeAssessmentLabPage.mock(
          speechFormulaRecognizer: recognizer,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(recognizer.disposeCount, 1);
  });
}

final class _FakeRecognizer implements SpeechFormulaRecognizer {
  SpeechFormulaResultCallback? _onResult;
  int disposeCount = 0;

  @override
  SpokenFormulaRecognitionException? get initializationError => null;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
    SpeechFormulaFinalizationStartedCallback? onFinalizationStarted,
  }) async {
    _onResult = onResult;
  }

  void emit(String words, {required bool isFinal}) =>
      _onResult?.call(words, isFinal: isFinal);

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class _FakeSpokenFormulaRepository
    implements SpokenFormulaResolutionRepository {
  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async => SpokenFormulaResolution(
    resolutionId: 'composition-resolution',
    recognizedText: text,
    normalizedText: text,
    outcome: SpokenFormulaOutcome.resolved,
    candidates: const <SpokenFormulaCandidate>[
      SpokenFormulaCandidate(
        id: 'candidate-a',
        latex: 'x^2',
        spokenBack: 'x 的平方',
      ),
    ],
    clarification: null,
    warnings: const <String>[],
  );
}

final class _LongCandidateRepository
    implements SpokenFormulaResolutionRepository {
  const _LongCandidateRepository();

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async => SpokenFormulaResolution(
    resolutionId: 'composition-long-candidates',
    recognizedText: text,
    normalizedText: text,
    outcome: SpokenFormulaOutcome.candidates,
    candidates: const <SpokenFormulaCandidate>[
      SpokenFormulaCandidate(
        id: 'page-a',
        latex:
            r'\frac{x_1^2+x_2^2+x_3^2+x_4^2+x_5^2+x_6^2+x_7^2+x_8^2}{\sqrt{a_1^2+a_2^2+a_3^2+a_4^2+a_5^2+a_6^2}}',
        spokenBack:
            '第一个页面候选的分子是从 x 一的平方一直加到 x 八的平方，分母是从 a 一到 a 六各自平方之和的算术平方根，分母结束，请确认全部作用域',
      ),
      SpokenFormulaCandidate(
        id: 'page-b',
        latex:
            r'\sum_{k=1}^{50}\frac{k^5+3k^4+5k^3+7k^2+9k+11}{(k+1)(k+2)(k+3)(k+4)}',
        spokenBack:
            '第二个页面候选从 k 等于一到五十求和，主体为五次多项式整体除以四个连续因子的乘积，分母结束，求和主体结束，请确认求和上下限',
      ),
      SpokenFormulaCandidate(
        id: 'page-c',
        latex:
            r'\int_{0}^{\pi}\frac{\sin^4x+\cos^4x+2\sin^2x\cos^2x}{\sqrt{1+x^2+x^4+x^6}}\,\mathrm{d}x',
        spokenBack:
            '第三个页面候选是从零到圆周率的定积分，分子包含正弦和余弦的四次方以及乘积项，整体除以根号内一加 x 的二次方四次方六次方，积分主体结束',
      ),
    ],
    clarification: null,
    warnings: const <String>['三个页面候选都需要显式选择后才能插入'],
  );
}

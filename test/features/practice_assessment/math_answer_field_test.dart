import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/application/speech_formula_controller.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/math_answer_field.dart';

void main() {
  testWidgets('填空题把公式输入框嵌入题干占位符而不保留下划线', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          prompt: '双曲线的离心率为______。',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('practice-fill-blank-prompt-before')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-math-answer-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-fill-blank-prompt-after')),
      findsOneWidget,
    );
    expect(find.textContaining('______'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await _selectFormulaSection(tester, 'commonTemplates');
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-fraction')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-3')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-2')));
    await tester.pump();

    expect(changes.last, r'\frac{3}{2}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('公式草稿初始化为排版值且不回传伪造的编辑事件', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          value: r'\frac{3}{2}',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    expect(
      controller.currentEditingValue(placeholderWhenEmpty: false),
      r'(\frac{3}{2})',
    );
    expect(changes, isEmpty);
    expect(
      find.byKey(const ValueKey('practice-math-answer-field')),
      findsOneWidget,
    );
  });

  testWidgets('服务端恢复的新草稿同步到公式框但不会触发保存回环', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    Widget field(String value) => _app(
      MathAnswerField(
        questionId: 'q12',
        value: value,
        enabled: true,
        controller: controller,
        onChanged: changes.add,
      ),
    );

    await tester.pumpWidget(field('1'));
    await tester.pumpWidget(field(r'\sqrt{2}'));

    expect(
      controller.currentEditingValue(placeholderWhenEmpty: false),
      r'\sqrt{2}',
    );
    expect(changes, isEmpty);
  });

  testWidgets('目录生成的复杂公式可由新控制器恢复并继续编辑', (tester) async {
    const values = <String>[
      r'5\,\mathrm{m}/\mathrm{s}^{2}',
      r'\alpha\in\mathbb{R}',
      r'P\left(A\mid B\right)',
      r'\begin{cases}{x}\\{-x}\end{cases}',
      r'{}_{6}^{14}C',
      r'\left\lvert x\right\rvert',
    ];

    for (final value in values) {
      final controller = MathFieldEditingController();
      final changes = <String>[];
      await tester.pumpWidget(
        _app(
          MathAnswerField(
            questionId: 'q-restore-$value',
            value: value,
            enabled: true,
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('practice-math-answer-error')),
        findsNothing,
      );
      expect(
        controller.currentEditingValue(placeholderWhenEmpty: false),
        value,
      );
      await tester.tap(
        find.byKey(const ValueKey('practice-math-answer-input')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('practice-formula-key-plus')));
      await tester.pump();
      expect(changes.last, '$value+');

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('恢复后的目录公式可进入内部结构逐项修改', (tester) async {
    Future<void> verifyInternalEdit({
      required String questionId,
      required String value,
      required String expected,
      required void Function(MathFieldEditingController controller) edit,
    }) async {
      final controller = MathFieldEditingController();
      await tester.pumpWidget(
        _app(
          MathAnswerField(
            questionId: questionId,
            value: value,
            enabled: true,
            controller: controller,
            onChanged: (_) {},
          ),
        ),
      );

      edit(controller);
      await tester.pump();
      expect(
        controller.currentEditingValue(placeholderWhenEmpty: false),
        expected,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }

    await verifyInternalEdit(
      questionId: 'q-edit-unit',
      value: r'5\,\mathrm{m}/\mathrm{s}^{2}',
      expected: r'5\,\mathrm{m}/\mathrm{s}^{3}',
      edit: (controller) {
        controller
          ..goBack()
          ..goBack(deleteMode: true)
          ..addLeaf('3');
      },
    );
    await verifyInternalEdit(
      questionId: 'q-edit-set',
      value: r'\alpha\in\mathbb{R}',
      expected: r'\alpha\in\mathbb{C}',
      edit: (controller) {
        controller
          ..goBack()
          ..goBack(deleteMode: true)
          ..addLeaf('C');
      },
    );
    await verifyInternalEdit(
      questionId: 'q-edit-conditional',
      value: r'P\left(A\mid B\right)',
      expected: r'P\left(A\mid C\right)',
      edit: (controller) {
        controller
          ..goBack()
          ..goBack(deleteMode: true)
          ..addLeaf('C');
      },
    );
    await verifyInternalEdit(
      questionId: 'q-edit-cases',
      value: r'\begin{cases}{x}\\{-x}\end{cases}',
      expected: r'\begin{cases}{x}\\{-y}\end{cases}',
      edit: (controller) {
        controller
          ..goBack()
          ..goBack()
          ..goBack(deleteMode: true)
          ..addLeaf('y');
      },
    );
    await verifyInternalEdit(
      questionId: 'q-edit-nucleus',
      value: r'{}_{6}^{14}C',
      expected: r'{}_{6}^{14}N',
      edit: (controller) {
        controller
          ..goBack(deleteMode: true)
          ..addLeaf('N');
      },
    );
    await verifyInternalEdit(
      questionId: 'q-edit-pair',
      value: r'\left\lvert x\right\rvert',
      expected: r'\left\lvert y\right\rvert',
      edit: (controller) {
        controller
          ..goBack()
          ..goBack(deleteMode: true)
          ..addLeaf('y');
      },
    );
  });

  testWidgets('学生编辑公式时只上报一次不带定界符的 LaTeX', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    controller.addLeaf('2');
    await tester.pump();

    expect(changes, ['2']);
  });

  testWidgets('点击公式框打开 UniPrism 浅色键盘并可输入分式', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-formula-keyboard')),
      findsOneWidget,
    );
    await _selectFormulaSection(tester, 'commonTemplates');
    expect(
      find.byKey(const ValueKey('practice-formula-key-fraction')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-fraction')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-3')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-2')));
    await tester.pump();

    expect(changes.last, r'\frac{3}{2}');
  });

  testWidgets('科学记数法模板通过真实公式框输出可编辑槽位', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-scientific',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await _selectFormulaSection(tester, 'commonTemplates');
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-scientific-notation')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-3')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-8')));
    await tester.pump();

    expect(changes.last, r'3\times10^{8}');
  });

  testWidgets('条件概率模板通过真实公式框按条件两侧填写', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-conditional-probability',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-primary-mathematics')),
    );
    await tester.pump();
    await _selectFormulaSection(tester, 'mathTemplates');
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-conditional-prob')),
    );
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-more-shortcut')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-uppercase')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-letter-a')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-letter-b')),
    );
    await tester.pump();

    expect(changes.last, r'P\left(A\mid B\right)');
  });

  testWidgets('核素模板通过真实公式框按质量数原子序数元素填写', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-nucleus',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-primary-physics')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-nucleus')),
    );
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-1')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-4')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-6')));
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-next')));
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-more-shortcut')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-uppercase')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-letter-c')),
    );
    await tester.pump();

    expect(changes.last, r'{}_{6}^{14}C');
  });

  testWidgets('复合单位通过真实公式框保留数值间距和直立体', (tester) async {
    final controller = MathFieldEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-compound-unit',
          value: '',
          enabled: true,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-formula-key-5')));
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-primary-physics')),
    );
    await tester.pump();
    await _selectFormulaSection(tester, 'physicsUnits');
    await tester.tap(find.byKey(const ValueKey('practice-formula-page-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-formula-page-next')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-key-unit-m-per-s2')),
    );
    await tester.pump();

    expect(changes.last, r'5\,\mathrm{m}/\mathrm{s}^{2}');
  });

  testWidgets('关系符号页覆盖高中数学填空题常用符号且窄屏不溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q12',
          value: '',
          enabled: true,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    await _selectFormulaSection(tester, 'commonSymbols');

    expect(
      find.byKey(const ValueKey('practice-formula-key-less-equal')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-primary-mathematics')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('practice-formula-key-infinity')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('语音候选确认后插入当前光标并进入原有 onChanged', (tester) async {
    final mathController = MathFieldEditingController();
    final recognizer = _VoiceTestRecognizer();
    final speechController = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _VoiceTestRepository(),
    );
    final changes = <String>[];
    addTearDown(mathController.dispose);
    addTearDown(speechController.dispose);

    await tester.pumpWidget(
      _app(
        MathAnswerField(
          questionId: 'q-voice',
          value: 'ab',
          enabled: true,
          controller: mathController,
          speechFormulaController: speechController,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('practice-math-answer-input')));
    await tester.pump();
    mathController.goBack();
    final changesBeforeVoice = List<String>.of(changes);
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-start')),
    );
    await tester.pump();
    recognizer.emit('x 的平方', isFinal: true);
    for (var index = 0; index < 5; index++) {
      await tester.pump();
    }

    expect(changes, changesBeforeVoice);
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-insert')),
    );
    await tester.pump();

    expect(changes.last, r'ax^2b');
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MathKeyboardViewInsets(child: Scaffold(body: child)),
  );
}

Future<void> _selectFormulaSection(
  WidgetTester tester,
  String sectionName,
) async {
  final section = find.byKey(
    ValueKey<String>('practice-formula-section-$sectionName'),
  );
  await tester.ensureVisible(section);
  await tester.tap(section);
  await tester.pump();
}

final class _VoiceTestRecognizer implements SpeechFormulaRecognizer {
  SpeechFormulaResultCallback? _onResult;

  @override
  SpokenFormulaRecognitionException? get initializationError => null;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
  }) async {
    _onResult = onResult;
  }

  void emit(String words, {required bool isFinal}) =>
      _onResult?.call(words, isFinal: isFinal);

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stop() async {}
}

final class _VoiceTestRepository implements SpokenFormulaRepository {
  const _VoiceTestRepository();

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

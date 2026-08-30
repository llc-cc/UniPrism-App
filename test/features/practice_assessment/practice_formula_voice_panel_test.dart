import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/application/speech_formula_controller.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_voice_panel.dart';

void main() {
  testWidgets('空闲状态显示语音入口并进入监听状态', (tester) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _Repository(_Outcome.resolved),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));
    expect(find.text('识别方式：浏览器语音'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-start')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-formula-voice-stop')),
      findsOneWidget,
    );
    expect(find.textContaining('识别方式：'), findsNothing);
  });

  testWidgets('375 窄屏空闲状态显示本机 SenseVoice 来源且不溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SpeechFormulaController(
      recognizer: _FakeRecognizer(),
      repository: const _Repository(_Outcome.resolved),
      sourceLabel: '本机 SenseVoice',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));

    expect(find.text('识别方式：本机 SenseVoice'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-start')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resolved 只预览公式和反向朗读，显式插入后同步 reset 且只回调一次', (tester) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _Repository(_Outcome.resolved),
    );
    final inserted = <String>[];
    final statusAtInsert = <SpeechFormulaStatus>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(controller, (latex) {
        inserted.add(latex);
        statusAtInsert.add(controller.state.status);
      }),
    );
    await _resolve(tester, controller, recognizer, 'x 的平方');

    final resolved = find.byKey(
      const ValueKey('practice-formula-voice-resolved'),
    );
    expect(resolved, findsOneWidget);
    expect(
      find.descendant(of: resolved, matching: find.byType(Math)),
      findsOneWidget,
    );
    expect(find.text('反向朗读：x 的平方'), findsOneWidget);
    expect(inserted, isEmpty);

    final insert = find.byKey(const ValueKey('practice-formula-voice-insert'));
    await tester.tap(insert);
    await tester.tap(insert);
    await tester.pump();

    expect(inserted, <String>[r'x^2']);
    expect(statusAtInsert, <SpeechFormulaStatus>[SpeechFormulaStatus.idle]);
    recognizer.emit('迟到公式', isFinal: true, listenIndex: 0);
    await _pumpAsync(tester);
    expect(controller.state.status, SpeechFormulaStatus.idle);
    expect(inserted, hasLength(1));
  });

  testWidgets('choosingCandidate 展示每张公式卡和反向朗读，显式选择前禁用插入', (tester) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _Repository(_Outcome.candidates),
    );
    final inserted = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, inserted.add));
    await _resolve(tester, controller, recognizer, '负二的平方');

    expect(controller.state.status, SpeechFormulaStatus.choosingCandidate);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-candidates')),
      findsOneWidget,
    );
    for (final entry in <String, String>{
      'candidate-a': r'(-2)^2',
      'candidate-b': r'-2^2',
    }.entries) {
      final card = find.byKey(
        ValueKey<String>('practice-formula-voice-candidate-${entry.key}'),
      );
      expect(card, findsOneWidget);
      final mathFinder = find.descendant(of: card, matching: find.byType(Math));
      expect(mathFinder, findsOneWidget);
      final rendered = tester.widget<Math>(mathFinder);
      final expected = Math.tex(entry.value);
      expect(
        TexEncoder().convert(rendered.ast!.greenRoot),
        TexEncoder().convert(expected.ast!.greenRoot),
      );
    }
    expect(
      find.byKey(
        const ValueKey('practice-formula-voice-spoken-back-candidate-a'),
      ),
      findsOneWidget,
    );
    expect(find.text('反向朗读：负二整体的平方'), findsOneWidget);
    expect(find.text('反向朗读：二的平方再取负'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('practice-formula-voice-insert')),
          )
          .onPressed,
      isNull,
    );
    expect(inserted, isEmpty);

    await tester.tap(
      find.byKey(
        const ValueKey('practice-formula-voice-candidate-candidate-b'),
      ),
    );
    await tester.pump();
    expect(controller.state.selectedCandidate?.id, 'candidate-b');
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('practice-formula-voice-insert')),
          )
          .onPressed,
      isNotNull,
    );

    final insert = find.byKey(const ValueKey('practice-formula-voice-insert'));
    await tester.tap(insert);
    await tester.tap(insert);
    await tester.pump();

    expect(inserted, <String>[r'-2^2']);
    expect(controller.state.status, SpeechFormulaStatus.idle);
  });

  testWidgets('clarifying 显示具体问题和 focus，紫色 action 直接委托 controller', (
    tester,
  ) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _Repository(_Outcome.clarification),
    );
    final inserted = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, inserted.add));
    await _resolve(tester, controller, recognizer, '负二的平方');

    final promptFinder = find.byKey(
      const ValueKey('practice-formula-voice-clarification'),
    );
    expect(promptFinder, findsOneWidget);
    expect(
      find.descendant(of: promptFinder, matching: find.text('负号是否在平方范围内？')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: promptFinder, matching: find.text('需要确认：负二的平方')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('practice-formula-voice-spoken-back-candidate-b'),
      ),
      findsOneWidget,
    );
    expect(inserted, isEmpty);
    expect(
      find.descendant(of: promptFinder, matching: find.textContaining('换一种说法')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: promptFinder,
        matching: find.textContaining('语音输入失败'),
      ),
      findsNothing,
    );
    final decoration =
        tester.widget<Container>(promptFinder).decoration! as BoxDecoration;
    expect(_looksErrorRed(decoration.color), isFalse);
    expect(_looksErrorRed(decoration.border!.top.color), isFalse);
    for (final element
        in find
            .descendant(of: promptFinder, matching: find.byType(Text))
            .evaluate()) {
      expect(_looksErrorRed((element.widget as Text).style?.color), isFalse);
    }
    for (final element
        in find
            .descendant(
              of: promptFinder,
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            )
            .evaluate()) {
      final button = element.widget as ButtonStyleButton;
      expect(
        _looksErrorRed(button.style?.foregroundColor?.resolve(<WidgetState>{})),
        isFalse,
      );
      expect(
        _looksErrorRed(button.style?.backgroundColor?.resolve(<WidgetState>{})),
        isFalse,
      );
      expect(
        _looksErrorRed(button.style?.side?.resolve(<WidgetState>{})?.color),
        isFalse,
      );
    }

    for (final id in <String>['select-negative-outside', 'keyboard']) {
      expect(
        find.byKey(
          ValueKey<String>('practice-formula-voice-clarification-$id'),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('practice-formula-voice-continue-recording')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey(
          'practice-formula-voice-clarification-select-negative-outside',
        ),
      ),
    );
    await tester.pump();

    expect(controller.state.status, SpeechFormulaStatus.resolved);
    expect(controller.state.selectedCandidate?.id, 'candidate-b');
    expect(inserted, isEmpty);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-resolved')),
      findsOneWidget,
    );
  });

  testWidgets('部分公式澄清展示可信片段，选择仍需显式插入', (tester) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _Repository(_Outcome.partialClarification),
    );
    final inserted = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, inserted.add));
    await _resolve(tester, controller, recognizer, '已知 x 大于零，求最小值');

    final prompt = find.byKey(
      const ValueKey('practice-formula-voice-clarification'),
    );
    expect(
      find.descendant(of: prompt, matching: find.text('已识别出以下公式片段，完整作用范围仍需确认')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: prompt, matching: find.text('识别到公式片段')),
      findsNWidgets(3),
    );
    for (final candidateId in <String>[
      'fragment-function',
      'fragment-condition',
      'fragment-target',
    ]) {
      expect(
        find.byKey(
          ValueKey<String>('practice-formula-voice-spoken-back-$candidateId'),
        ),
        findsOneWidget,
      );
    }
    for (final optionId in <String>[
      'select-function',
      'select-condition',
      'select-target',
      'use-keyboard',
    ]) {
      expect(
        find.byKey(
          ValueKey<String>('practice-formula-voice-clarification-$optionId'),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('practice-formula-voice-continue-recording')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('practice-formula-voice-clarification-select-function'),
      ),
    );
    await tester.pump();

    expect(controller.state.selectedCandidate?.id, 'fragment-function');
    expect(inserted, isEmpty);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-insert')),
      findsOneWidget,
    );
  });

  testWidgets('部分公式澄清的每个候选选择都精确定位且不自动插入', (tester) async {
    for (final entry in <String, String>{
      'select-function': 'fragment-function',
      'select-condition': 'fragment-condition',
      'select-target': 'fragment-target',
    }.entries) {
      final recognizer = _FakeRecognizer();
      final controller = SpeechFormulaController(
        recognizer: recognizer,
        repository: const _Repository(_Outcome.partialClarification),
      );
      final inserted = <String>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(controller, inserted.add));
      await _resolve(tester, controller, recognizer, '已知 x 大于零，求最小值');
      await tester.tap(
        find.byKey(
          ValueKey<String>('practice-formula-voice-clarification-${entry.key}'),
        ),
      );
      await tester.pump();

      expect(controller.state.status, SpeechFormulaStatus.resolved);
      expect(controller.state.selectedCandidate?.id, entry.value);
      expect(inserted, isEmpty);
    }
  });

  testWidgets('375px 部分公式澄清的三个候选和五个动作均可达且不溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _Repository(_Outcome.partialClarification),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));
    await _resolve(tester, controller, recognizer, '已知 x 大于零，求 y 的最小值');

    for (final candidateId in <String>[
      'fragment-function',
      'fragment-condition',
      'fragment-target',
    ]) {
      expect(
        find
            .byKey(
              ValueKey<String>(
                'practice-formula-voice-spoken-back-$candidateId',
              ),
            )
            .hitTestable(),
        findsOneWidget,
      );
    }
    for (final optionId in <String>[
      'select-function',
      'select-condition',
      'select-target',
      'use-keyboard',
    ]) {
      expect(
        find
            .byKey(
              ValueKey<String>(
                'practice-formula-voice-clarification-$optionId',
              ),
            )
            .hitTestable(),
        findsOneWidget,
      );
    }
    expect(
      find
          .byKey(const ValueKey('practice-formula-voice-continue-recording'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clarification 显示续录入口并保留文字合并重新解析', (tester) async {
    final recognizer = _FakeRecognizer();
    final repository = _SequencedRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(_partialClarification('二阶行列式')),
      Future<SpokenFormulaResolution>.value(_resolved('二阶行列式，第一行 x 加一')),
    ]);
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    final inserted = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, inserted.add));
    await _resolve(tester, controller, recognizer, '二阶行列式');

    final continueButton = find.byKey(
      const ValueKey('practice-formula-voice-continue-recording'),
    );
    expect(continueButton, findsOneWidget);
    expect(find.text('继续补充语音'), findsOneWidget);
    await tester.tap(continueButton);
    await _pumpAsync(tester);

    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-transcript')),
      findsOneWidget,
    );
    expect(find.text('二阶行列式'), findsOneWidget);
    recognizer.emit('第一行 x 加一', isFinal: true, listenIndex: 1);
    await _pumpAsync(tester);

    expect(repository.texts, <String>['二阶行列式', '二阶行列式，第一行 x 加一']);
    expect(controller.state.status, SpeechFormulaStatus.resolved);
    expect(inserted, isEmpty);
  });

  testWidgets('续录解析失败后保留上一轮安全候选并允许明确选择', (tester) async {
    final recognizer = _FakeRecognizer();
    final repository = _SuccessThenFailRepository(_clarification('负二的平方'));
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    final inserted = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, inserted.add));
    await _resolve(tester, controller, recognizer, '负二的平方');

    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-continue-recording')),
    );
    await _pumpAsync(tester);
    recognizer.emit('我指的是平方后再取负', isFinal: true, listenIndex: 1);
    await _pumpAsync(tester);

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-retained-resolution')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('practice-formula-voice-spoken-back-candidate-b'),
      ),
      findsOneWidget,
    );
    expect(inserted, isEmpty);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'practice-formula-voice-retained-select-select-negative-outside',
        ),
      ),
    );
    await tester.pump();
    expect(controller.state.status, SpeechFormulaStatus.resolved);
    expect(controller.state.selectedCandidate?.id, 'candidate-b');
    expect(inserted, isEmpty);
  });

  testWidgets('无候选的续录解析失败后仍恢复上一轮澄清焦点', (tester) async {
    final recognizer = _FakeRecognizer();
    final repository = _SuccessThenFailRepository(
      _clarificationWithContinue('二阶行列式'),
    );
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, (_) {}));
    await _resolve(tester, controller, recognizer, '二阶行列式');

    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-continue-recording')),
    );
    await _pumpAsync(tester);
    recognizer.emit('第一行还没说完', isFinal: true, listenIndex: 1);
    await _pumpAsync(tester);

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-retained-resolution')),
      findsOneWidget,
    );
    expect(find.text('需要确认：二阶行列式'), findsOneWidget);
  });

  testWidgets('infrastructureError 有 transcript 可续录，无 transcript 的权限错误不显示', (
    tester,
  ) async {
    final recognizer = _FakeRecognizer();
    final repository = _FailOnceRepository(_resolved('主体，补充'));
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, (_) {}));
    await _resolve(tester, controller, recognizer, '主体');

    final continueButton = find.byKey(
      const ValueKey('practice-formula-voice-continue-recording'),
    );
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(continueButton, findsOneWidget);
    await tester.tap(continueButton);
    await _pumpAsync(tester);
    recognizer.emit('补充', isFinal: true, listenIndex: 1);
    await _pumpAsync(tester);
    expect(repository.texts, <String>['主体', '主体，补充']);

    final permissionController = SpeechFormulaController(
      recognizer: _FakeRecognizer(
        isAvailable: false,
        initializationError: const SpokenFormulaRecognitionException(
          '麦克风权限不可用',
        ),
      ),
      repository: const _Repository(_Outcome.resolved),
    );
    addTearDown(permissionController.dispose);
    await tester.pumpWidget(_app(permissionController, (_) {}));
    await permissionController.startListening();
    await _pumpAsync(tester);

    expect(
      find.byKey(const ValueKey('practice-formula-voice-continue-recording')),
      findsNothing,
    );
  });

  testWidgets('三轮续录耗尽后改为整段重录且新转写不拼接旧上下文', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recognizer = _FakeRecognizer();
    final repository = _SequencedRepository(<Future<SpokenFormulaResolution>>[
      for (var index = 0; index < 4; index += 1)
        Future<SpokenFormulaResolution>.value(_clarification('澄清 $index')),
      Future<SpokenFormulaResolution>.value(_resolved('全新公式')),
    ]);
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, (_) {}));
    await _resolve(tester, controller, recognizer, '主体');

    for (var turn = 1; turn <= 3; turn += 1) {
      expect(
        find
            .byKey(const ValueKey('practice-formula-voice-continue-recording'))
            .hitTestable(),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('practice-formula-voice-continue-recording')),
      );
      await _pumpAsync(tester);
      recognizer.emit('补充 $turn', isFinal: true, listenIndex: turn);
      await _pumpAsync(tester);
    }

    expect(controller.state.continuationTurn, 3);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-continue-recording')),
      findsNothing,
    );
    final restart = find.byKey(
      const ValueKey('practice-formula-voice-restart-recording'),
    );
    expect(restart.hitTestable(), findsOneWidget);
    expect(find.text('整段重录'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(restart);
    await _pumpAsync(tester);
    recognizer.emit('全新公式', isFinal: true, listenIndex: 4);
    await _pumpAsync(tester);

    expect(repository.texts.last, '全新公式');
    expect(controller.state.continuationTurn, 0);
    expect(controller.state.status, SpeechFormulaStatus.resolved);
  });

  testWidgets('clarification 重录和监听取消都隔离旧 operation 的迟到 final', (tester) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _Repository(_Outcome.retryClarification),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));
    await _resolve(tester, controller, recognizer, '待澄清公式');
    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-clarification-retry')),
    );
    await _pumpAsync(tester);

    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(recognizer.listenCount, 2);
    recognizer.emit('旧轮次迟到结果', isFinal: true, listenIndex: 0);
    await _pumpAsync(tester);
    expect(controller.state.status, SpeechFormulaStatus.listening);

    await tester.tap(
      find.byKey(const ValueKey('practice-formula-voice-cancel')),
    );
    await _pumpAsync(tester);
    recognizer.emit('取消后迟到结果', isFinal: true, listenIndex: 1);
    await _pumpAsync(tester);

    expect(controller.state.status, SpeechFormulaStatus.idle);
    expect(controller.state.resolution, isNull);
  });

  testWidgets('375px 下长 LaTeX 可横向滚动且长反向朗读换行不溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: const _Repository(_Outcome.longCandidates),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));
    await _resolve(tester, controller, recognizer, '一个很长的公式');

    for (final id in <String>['long-a', 'long-b']) {
      final card = find.byKey(
        ValueKey<String>('practice-formula-voice-candidate-$id'),
      );
      final horizontalScrolls = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(horizontalScrolls, findsOneWidget);
      final spoken = tester.widget<Text>(
        find.byKey(ValueKey<String>('practice-formula-voice-spoken-back-$id')),
      );
      expect(spoken.maxLines, isNull);
      expect(spoken.softWrap, isNot(false));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('infrastructureError 保留真实转写并只显示基础设施错误态', (tester) async {
    final recognizer = _FakeRecognizer();
    final controller = SpeechFormulaController(
      recognizer: recognizer,
      repository: _FailingRepository(),
      sourceLabel: '本机 SenseVoice',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, (_) {}));
    await _resolve(tester, controller, recognizer, '把 y 乘以它自己再减五倍 y');

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(
      find.byKey(const ValueKey('practice-formula-voice-infrastructure-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-formula-voice-error-transcript')),
      findsOneWidget,
    );
    expect(find.textContaining('把 y 乘以它自己再减五倍 y'), findsOneWidget);
  });
}

bool _looksErrorRed(Color? color) {
  if (color == null || color.a == 0) return false;
  final hsv = HSVColor.fromColor(color);
  return hsv.saturation > 0.35 && (hsv.hue < 25 || hsv.hue > 335);
}

Widget _app(
  SpeechFormulaController controller,
  ValueChanged<String> onInsert,
) => MaterialApp(
  home: Scaffold(
    body: PracticeFormulaVoicePanel(controller: controller, onInsert: onInsert),
  ),
);

Future<void> _resolve(
  WidgetTester tester,
  SpeechFormulaController controller,
  _FakeRecognizer recognizer,
  String transcript,
) async {
  await controller.startListening();
  recognizer.emit(transcript, isFinal: true);
  await _pumpAsync(tester);
}

Future<void> _pumpAsync(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump();
  }
}

final class _FakeRecognizer implements SpeechFormulaRecognizer {
  _FakeRecognizer({this.isAvailable = true, this.initializationError});

  final bool isAvailable;
  @override
  final SpokenFormulaRecognitionException? initializationError;
  final List<SpeechFormulaResultCallback> _onResults =
      <SpeechFormulaResultCallback>[];
  int listenCount = 0;

  @override
  Future<bool> initialize() async => isAvailable;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
    SpeechFormulaFinalizationStartedCallback? onFinalizationStarted,
  }) async {
    listenCount += 1;
    _onResults.add(onResult);
  }

  void emit(String words, {required bool isFinal, int? listenIndex}) =>
      _onResults[listenIndex ?? _onResults.length - 1](words, isFinal: isFinal);

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stop() async {}
}

enum _Outcome {
  resolved,
  candidates,
  clarification,
  partialClarification,
  retryClarification,
  longCandidates,
}

final class _Repository implements SpokenFormulaResolutionRepository {
  const _Repository(this.outcome);

  final _Outcome outcome;

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async => switch (outcome) {
    _Outcome.resolved => _resolved(text),
    _Outcome.candidates => _candidates(text),
    _Outcome.clarification => _clarification(text),
    _Outcome.partialClarification => _partialClarification(text),
    _Outcome.retryClarification => _retryClarification(text),
    _Outcome.longCandidates => _longCandidates(text),
  };
}

final class _SequencedRepository implements SpokenFormulaResolutionRepository {
  _SequencedRepository(this._responses);

  final List<Future<SpokenFormulaResolution>> _responses;
  final List<String> texts = <String>[];
  int _callCount = 0;

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) {
    texts.add(text);
    final response = _responses[_callCount];
    _callCount += 1;
    return response;
  }
}

final class _FailOnceRepository implements SpokenFormulaResolutionRepository {
  _FailOnceRepository(this._success);

  final SpokenFormulaResolution _success;
  final List<String> texts = <String>[];
  var _callCount = 0;

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async {
    texts.add(text);
    if (_callCount++ == 0) throw StateError('network internals');
    return _success;
  }
}

final class _SuccessThenFailRepository
    implements SpokenFormulaResolutionRepository {
  _SuccessThenFailRepository(this._firstResponse);

  final SpokenFormulaResolution _firstResponse;
  var _callCount = 0;

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async {
    if (_callCount++ == 0) return _firstResponse;
    throw StateError('network internals');
  }
}

SpokenFormulaResolution _resolved(String text) => SpokenFormulaResolution(
  resolutionId: 'voice-panel-resolved',
  recognizedText: text,
  normalizedText: text,
  outcome: SpokenFormulaOutcome.resolved,
  candidates: const <SpokenFormulaCandidate>[
    SpokenFormulaCandidate(
      id: 'candidate-a',
      latex: r'x^2',
      spokenBack: 'x 的平方',
    ),
  ],
  clarification: null,
  warnings: const <String>[],
);

SpokenFormulaResolution _candidates(String text) => SpokenFormulaResolution(
  resolutionId: 'voice-panel-candidates',
  recognizedText: text,
  normalizedText: text,
  outcome: SpokenFormulaOutcome.candidates,
  candidates: const <SpokenFormulaCandidate>[
    SpokenFormulaCandidate(
      id: 'candidate-a',
      latex: r'(-2)^2',
      spokenBack: '负二整体的平方',
    ),
    SpokenFormulaCandidate(
      id: 'candidate-b',
      latex: r'-2^2',
      spokenBack: '二的平方再取负',
    ),
  ],
  clarification: null,
  warnings: const <String>['括号作用范围存在歧义'],
);

SpokenFormulaResolution _clarification(String text) => SpokenFormulaResolution(
  resolutionId: 'voice-panel-clarification',
  recognizedText: text,
  normalizedText: text,
  outcome: SpokenFormulaOutcome.clarification,
  candidates: const <SpokenFormulaCandidate>[
    SpokenFormulaCandidate(
      id: 'candidate-b',
      latex: r'-2^2',
      spokenBack: '二的平方再取负',
    ),
  ],
  clarification: SpokenFormulaClarification(
    question: '负号是否在平方范围内？',
    focusText: '负二的平方',
    options: const <SpokenFormulaClarificationOption>[
      SpokenFormulaClarificationOption(
        id: 'select-negative-outside',
        label: '平方后再取负',
        action: SpokenFormulaClarificationAction.selectCandidate,
        candidateId: 'candidate-b',
      ),
      SpokenFormulaClarificationOption(
        id: 'continue',
        label: '继续补充语音',
        action: SpokenFormulaClarificationAction.continueRecording,
      ),
      SpokenFormulaClarificationOption(
        id: 'keyboard',
        label: '使用键盘',
        action: SpokenFormulaClarificationAction.useKeyboard,
      ),
    ],
  ),
  warnings: const <String>[],
);

SpokenFormulaResolution _retryClarification(String text) =>
    SpokenFormulaResolution(
      resolutionId: 'voice-panel-retry-clarification',
      recognizedText: text,
      normalizedText: text,
      outcome: SpokenFormulaOutcome.clarification,
      candidates: const <SpokenFormulaCandidate>[],
      clarification: SpokenFormulaClarification(
        question: '请重新完整表达公式。',
        focusText: text,
        options: const <SpokenFormulaClarificationOption>[
          SpokenFormulaClarificationOption(
            id: 'retry',
            label: '重新说',
            action: SpokenFormulaClarificationAction.retryRecording,
          ),
          SpokenFormulaClarificationOption(
            id: 'keyboard',
            label: '使用键盘',
            action: SpokenFormulaClarificationAction.useKeyboard,
          ),
        ],
      ),
      warnings: const <String>[],
    );

SpokenFormulaResolution _partialClarification(String text) =>
    SpokenFormulaResolution(
      resolutionId: 'voice-panel-partial-clarification',
      recognizedText: text,
      normalizedText: text,
      outcome: SpokenFormulaOutcome.clarification,
      candidates: const <SpokenFormulaCandidate>[
        SpokenFormulaCandidate(
          id: 'fragment-function',
          latex: r'y=x+\frac{4}{x}',
          spokenBack: 'y 等于 x 加四除以 x',
          matchKind: SpokenFormulaMatchKind.partial,
        ),
        SpokenFormulaCandidate(
          id: 'fragment-condition',
          latex: r'x>0',
          spokenBack: 'x 大于零',
          matchKind: SpokenFormulaMatchKind.partial,
        ),
        SpokenFormulaCandidate(
          id: 'fragment-target',
          latex: r'\min y',
          spokenBack: '求 y 的最小值',
          matchKind: SpokenFormulaMatchKind.partial,
        ),
      ],
      clarification: SpokenFormulaClarification(
        question: '请确认下一步。',
        focusText: '完整作用范围',
        options: const <SpokenFormulaClarificationOption>[
          SpokenFormulaClarificationOption(
            id: 'select-function',
            label: '选择函数片段',
            action: SpokenFormulaClarificationAction.selectCandidate,
            candidateId: 'fragment-function',
          ),
          SpokenFormulaClarificationOption(
            id: 'select-condition',
            label: '选择条件片段',
            action: SpokenFormulaClarificationAction.selectCandidate,
            candidateId: 'fragment-condition',
          ),
          SpokenFormulaClarificationOption(
            id: 'select-target',
            label: '选择最值片段',
            action: SpokenFormulaClarificationAction.selectCandidate,
            candidateId: 'fragment-target',
          ),
          SpokenFormulaClarificationOption(
            id: 'continue-recording',
            label: '继续补充语音',
            action: SpokenFormulaClarificationAction.continueRecording,
          ),
          SpokenFormulaClarificationOption(
            id: 'use-keyboard',
            label: '使用公式键盘',
            action: SpokenFormulaClarificationAction.useKeyboard,
          ),
        ],
      ),
      warnings: const <String>[],
    );

SpokenFormulaResolution _clarificationWithContinue(String text) =>
    SpokenFormulaResolution(
      resolutionId: 'voice-panel-continuation',
      recognizedText: text,
      normalizedText: text,
      outcome: SpokenFormulaOutcome.clarification,
      candidates: const <SpokenFormulaCandidate>[],
      clarification: SpokenFormulaClarification(
        question: '请继续补充每一行的元素。',
        focusText: text,
        options: const <SpokenFormulaClarificationOption>[
          SpokenFormulaClarificationOption(
            id: 'continue',
            label: '继续补充语音',
            action: SpokenFormulaClarificationAction.continueRecording,
          ),
          SpokenFormulaClarificationOption(
            id: 'keyboard',
            label: '使用键盘',
            action: SpokenFormulaClarificationAction.useKeyboard,
          ),
        ],
      ),
      warnings: const <String>[],
    );

SpokenFormulaResolution _longCandidates(String text) => SpokenFormulaResolution(
  resolutionId: 'voice-panel-long-candidates',
  recognizedText: text,
  normalizedText: text,
  outcome: SpokenFormulaOutcome.candidates,
  candidates: const <SpokenFormulaCandidate>[
    SpokenFormulaCandidate(
      id: 'long-a',
      latex:
          r'\frac{x_1^2+x_2^2+x_3^2+x_4^2+x_5^2+x_6^2}{\sqrt{a_1^2+a_2^2+a_3^2+a_4^2}}',
      spokenBack: '分子是从 x 一的平方一直加到 x 六的平方，分母是括号 a 一到 a 四各自平方之和的算术平方根，分母结束',
    ),
    SpokenFormulaCandidate(
      id: 'long-b',
      latex: r'\sum_{k=1}^{20}\frac{k^3+2k^2+k+1}{(k+1)(k+2)(k+3)}',
      spokenBack: '从 k 等于一到二十求和，主体是 k 的三次方加二倍 k 的平方加 k 加一，整体除以三个连续因子的乘积，主体结束',
    ),
  ],
  clarification: null,
  warnings: const <String>[],
);

final class _FailingRepository implements SpokenFormulaResolutionRepository {
  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) => throw StateError('network internals');
}

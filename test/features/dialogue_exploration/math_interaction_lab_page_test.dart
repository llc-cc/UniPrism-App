import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/math_interaction_lab_page.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/teaching_mode_selection_stage.dart';

void main() {
  testWidgets('功能区 A 展示资料库并切换三种独立数学实验', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: MathInteractionLabPage()));
    await tester.pumpAndSettle();

    expect(find.text('数学交互实验区'), findsOneWidget);
    expect(find.text('2,539'), findsOneWidget);
    expect(find.text('公式推导工坊'), findsOneWidget);
    final reverse = find.byKey(const ValueKey('reverse-sequence'));
    await tester.ensureVisible(reverse);
    await tester.tap(reverse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('formula-token-n')));
    await tester.tap(find.byKey(const ValueKey('formula-token-(a₁ + aₙ)')));
    await tester.pump();
    final validateIdentity = find.byKey(
      const ValueKey('validate-formula-identity'),
    );
    await tester.ensureVisible(validateIdentity);
    await tester.tap(validateIdentity);
    await tester.pump();
    final divideBoth = find.byKey(const ValueKey('formula-operation-两边同时除以 2'));
    await tester.ensureVisible(divideBoth);
    await tester.tap(divideBoth);
    await tester.pump();
    final transfer = find.byKey(const ValueKey('formula-transfer-answer'));
    await tester.ensureVisible(transfer);
    await tester.enterText(transfer, '54');
    await tester.tap(find.byKey(const ValueKey('validate-formula-transfer')));
    await tester.pump();
    expect(find.textContaining('迁移通过'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('math-lab-derivative')));
    await tester.pumpAndSettle();
    expect(find.text('切线追踪协议'), findsOneWidget);
    expect(find.byKey(const ValueKey('tangent-graph')), findsOneWidget);
    final graphRect = tester.getRect(
      find.byKey(const ValueKey('tangent-graph')),
    );
    final zeroX = graphRect.left + 48 + (graphRect.width - 68) * .5;
    await tester.tapAt(Offset(zeroX, graphRect.center.dy));
    await tester.tap(find.byKey(const ValueKey('lock-tangent')));
    await tester.pump();
    expect(find.text('切线锁定成功'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('math-lab-probability')));
    await tester.pumpAndSettle();
    expect(find.text('样本空间引擎'), findsOneWidget);
    expect(find.text('EVENT MATRIX'), findsOneWidget);

    for (final index in [7, 8, 9]) {
      await tester.tap(find.byKey(ValueKey('probability-outcome-$index')));
      await tester.pump();
    }
    final validate = find.byKey(const ValueKey('validate-probability-event'));
    await tester.ensureVisible(validate);
    await tester.tap(validate);
    await tester.pump();
    expect(find.textContaining('P(A)=3/10'), findsOneWidget);

    final simulate = find.byKey(const ValueKey('simulate-probability-100'));
    await tester.ensureVisible(simulate);
    await tester.tap(simulate);
    await tester.pump();
    expect(find.textContaining('命中'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('math-lab-setModeling')));
    await tester.pumpAndSettle();
    expect(find.text('集合约束建模'), findsOneWidget);
    final intersectionControl = find.byKey(
      const ValueKey('intersection-control'),
    );
    expect(intersectionControl, findsOneWidget);
    final controlRect = tester.getRect(intersectionControl);
    await tester.tapAt(
      Offset(
        controlRect.left + controlRect.width * 5 / 11,
        controlRect.center.dy,
      ),
    );
    final lockModel = find.byKey(const ValueKey('validate-set-constraint'));
    await tester.ensureVisible(lockModel);
    await tester.tap(lockModel);
    await tester.pump();
    expect(find.textContaining('阶段 2'), findsOneWidget);

    for (final region in ['onlyRunning', 'intersection', 'onlyJumping']) {
      final chip = find.byKey(ValueKey('venn-region-$region'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
    }
    final validateRegions = find.byKey(const ValueKey('validate-set-regions'));
    await tester.ensureVisible(validateRegions);
    await tester.tap(validateRegions);
    await tester.pump();
    expect(find.textContaining('共 26 人'), findsOneWidget);
  });

  testWidgets('侧边栏的数学实验入口调用页面层回调', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModeSelectionSidebar(
            entries: const [],
            mobile: false,
            onFunctionAreaATap: () => opened = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('功能区A · 数学实验'));
    expect(opened, isTrue);
  });
}

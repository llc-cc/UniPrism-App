import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  late TeachingSessionController controller;

  setUp(() {
    controller = TeachingSessionController(
      strategy: TeachingExplorationStrategy(
        gateway: MockExplorationGateway(delay: Duration.zero),
      ),
      traceRepository: InMemoryExplorationTraceRepository(),
      memoryCandidateSink: InMemoryMemoryCandidateSink(),
      nowUtc: () => DateTime.utc(2026, 8, 5, 12),
    );
  });

  tearDown(() => controller.dispose());

  test(
    'one session records automatic strategy changes on real turns',
    () async {
      final content = MockExplorationContentRepository();
      final scenario = (await content.loadScenarios()).singleWhere(
        (item) => item.id == 'teaching-quadratic',
      );
      final mastery = (await MockStudentMasteryRepository().availableProfiles(
        scenario.atomId,
      )).singleWhere((item) => item.level == StudentMasteryLevel.developing);

      await controller.start(
        scenario: scenario,
        mastery: mastery,
        question: '二次函数的顶点为什么在这里？',
      );
      await controller.submitQuestion('平方项在这里等于零');
      await controller.submitQuestion('还是太抽象了，我不知道有什么用');
      await controller.submitQuestion('所以负负还是负数');
      await controller.submitQuestion('我来总结');

      expect(controller.state.strategyHistory.map((item) => item.mode), [
        TeachingDialogueMode.problemChain,
        TeachingDialogueMode.socratic,
        TeachingDialogueMode.analogyTransfer,
        TeachingDialogueMode.errorTracing,
        TeachingDialogueMode.selfExplanation,
      ]);
      expect(
        controller.state.activeDecision!.mode,
        TeachingDialogueMode.selfExplanation,
      );
      expect(
        controller.state.tree!.activeLeaf!.strategyMode,
        'selfExplanation',
      );
      expect(controller.state.tree!.activeLeaf!.strategyReason, isNotEmpty);
      expect(controller.state.tree!.activeLeaf!.text, contains('请用一句话'));
      expect(controller.state.tree!.activeLeaf!.text, isNot(contains('你觉得呢')));
    },
  );
}

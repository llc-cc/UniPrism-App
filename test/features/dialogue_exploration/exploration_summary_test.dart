import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  test(
    'summary reports only evidence observed in the completed session',
    () async {
      final content = MockExplorationContentRepository();
      final scenario = (await content.loadScenarios()).singleWhere(
        (item) => item.id == 'teaching-negative-multiplication',
      );
      final mastery = (await MockStudentMasteryRepository().availableProfiles(
        scenario.atomId,
      )).singleWhere((item) => item.level == StudentMasteryLevel.developing);
      final controller = TeachingSessionController(
        strategy: TeachingExplorationStrategy(
          gateway: MockExplorationGateway(delay: Duration.zero),
        ),
        traceRepository: InMemoryExplorationTraceRepository(),
        memoryCandidateSink: InMemoryMemoryCandidateSink(),
        nowUtc: () => DateTime.utc(2026, 8, 5, 13),
      );
      addTearDown(controller.dispose);

      await controller.start(
        scenario: scenario,
        mastery: mastery,
        question: scenario.openingPrompt,
      );
      await controller.submitQuestion('负号表示相反方向');
      await controller.submitQuestion('还是太抽象了');
      await controller.submitQuestion('所以负负还是负数');
      await controller.submitQuestion('我来总结');
      final record = await controller.saveTrace(
        reflection: '乘以负数表示取相反数，两次取相反数回到原方向。',
      );

      final summary = ExplorationSessionSummary.fromEvidence(
        tree: record.tree,
        strategyHistory: controller.state.strategyHistory,
        reflection: record.reflection,
      );

      expect(summary.thinkingTree, contains('${record.tree.nodes.length} 个节点'));
      expect(summary.understandingDepth, contains('完成自我解释'));
      expect(summary.errorModel, contains('错误思路'));
      expect(summary.interestDirection, contains('没有足够支线证据'));
      expect(summary.reviewCard, record.reflection);
      expect(
        controller.state.tree!.activeLeaf!.kind,
        ExplorationNodeKind.reflection,
      );
      expect(controller.state.status, TeachingSessionStatus.saved);
    },
  );
}

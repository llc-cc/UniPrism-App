import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  late ExplorationScenario scenario;
  late StudentMasterySnapshot mastery;
  late InMemoryMasteryEvidenceSink evidenceSink;
  late ExplorationController controller;

  setUp(() async {
    final contentRepository = MockExplorationContentRepository();
    scenario = (await contentRepository.loadScenarios()).singleWhere(
      (item) => item.id == 'practice-inequality',
    );
    mastery = (await MockStudentMasteryRepository().availableProfiles(
      scenario.atomId,
    )).singleWhere((item) => item.level == StudentMasteryLevel.developing);
    evidenceSink = InMemoryMasteryEvidenceSink();
    controller = ExplorationController(
      practiceStrategy: const PracticeExplorationStrategy(),
      masteryEvidenceSink: evidenceSink,
      nowUtc: () => DateTime.utc(2026, 8, 5, 10),
    );
  });

  tearDown(() => controller.dispose());

  test('system diagnosis stays pending until the student confirms it', () async {
    controller.startPractice(scenario: scenario, mastery: mastery);
    controller.submitHypothesis('直接使用柯西不等式');

    await controller.validateActiveStep();

    expect(controller.state.pendingDiagnosis, isNotNull);
    expect(
      controller.state.pendingDiagnosis!.suggestedKind,
      DifficultyDiagnosisKind.conditionGap,
    );
    expect(controller.state.status, ExplorationControllerStatus.awaitingDiagnosis);
    expect(evidenceSink.items, isEmpty);
  });

  test('student can modify the diagnosis before it becomes mastery evidence', () async {
    controller.startPractice(scenario: scenario, mastery: mastery);
    controller.submitHypothesis('直接使用柯西不等式');
    await controller.validateActiveStep();

    await controller.confirmDiagnosis(DifficultyDiagnosisKind.methodSelection);

    expect(controller.state.pendingDiagnosis, isNull);
    expect(evidenceSink.items, hasLength(1));
    expect(
      evidenceSink.items.single.diagnosisKind,
      DifficultyDiagnosisKind.methodSelection,
    );
    expect(
      evidenceSink.items.single.source,
      MasteryEvidenceSource.confirmedByStudent,
    );
    expect(
      controller.state.tree!.activeLeaf!.kind,
      ExplorationNodeKind.diagnosis,
    );
  });

  test('keeps the wrong path, backtracks, and completes a new valid branch', () async {
    controller.startPractice(scenario: scenario, mastery: mastery);
    final rootId = controller.state.tree!.activeLeafId;

    controller.submitHypothesis('直接使用柯西不等式');
    await controller.validateActiveStep();
    final contradictedId = controller.state.tree!.activeLeafId;
    await controller.confirmDiagnosis(DifficultyDiagnosisKind.conditionGap);
    controller.backtrack(targetNodeId: rootId);

    expect(
      controller.state.tree!.nodeById(contradictedId)!.status,
      ExplorationNodeStatus.contradicted,
    );
    expect(
      controller.state.tree!.activeLeaf!.backtrackTargetNodeId,
      rootId,
    );

    controller.submitHypothesis('令 a=x、b=1/x，使用基本不等式');
    final secondHypothesisId = controller.state.tree!.activeLeafId;
    await controller.validateActiveStep();
    controller.saveReflection('关键是先检查 x>0，才能使用基本不等式。');

    final tree = controller.state.tree!;
    expect(tree.nodeById(contradictedId), isNotNull);
    expect(tree.nodeById(secondHypothesisId)!.isSideBranch, isTrue);
    expect(tree.activeLeaf!.kind, ExplorationNodeKind.reflection);
    expect(tree.activeLeaf!.status, ExplorationNodeStatus.completed);
    expect(
      evidenceSink.items.map((item) => item.source),
      contains(MasteryEvidenceSource.verifiedByStep),
    );
  });

  test('rejects diagnosis confirmation when there is no pending suggestion', () async {
    controller.startPractice(scenario: scenario, mastery: mastery);

    expect(
      () => controller.confirmDiagnosis(DifficultyDiagnosisKind.uncertain),
      throwsStateError,
    );
    expect(evidenceSink.items, isEmpty);
  });

  test('requires a non-empty reflection', () {
    controller.startPractice(scenario: scenario, mastery: mastery);

    expect(() => controller.saveReflection('   '), throwsArgumentError);
  });
}

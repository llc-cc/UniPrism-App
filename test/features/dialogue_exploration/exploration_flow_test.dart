import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  late MockExplorationContentRepository contentRepository;
  late MockStudentMasteryRepository masteryRepository;
  late InMemoryExplorationTraceRepository traceRepository;
  late InMemoryMemoryCandidateSink memoryCandidateSink;
  late TeachingSessionController controller;

  setUp(() {
    contentRepository = MockExplorationContentRepository();
    masteryRepository = MockStudentMasteryRepository();
    traceRepository = InMemoryExplorationTraceRepository();
    memoryCandidateSink = InMemoryMemoryCandidateSink();
    controller = TeachingSessionController(
      strategy: TeachingExplorationStrategy(
        gateway: MockExplorationGateway(delay: Duration.zero),
      ),
      traceRepository: traceRepository,
      memoryCandidateSink: memoryCandidateSink,
      nowUtc: () => DateTime.utc(2026, 8, 5, 11),
    );
  });

  tearDown(() => controller.dispose());

  test('starts teaching from a question and stores a structured tutor node', () async {
    final scenario = await _scenario(contentRepository, 'teaching-quadratic');
    final mastery = await _mastery(
      masteryRepository,
      scenario.atomId,
      StudentMasteryLevel.weak,
    );

    await controller.start(
      scenario: scenario,
      mastery: mastery,
      question: scenario.openingPrompt,
    );

    final tree = controller.state.tree!;
    expect(tree.nodes, hasLength(2));
    expect(tree.activeLeaf!.kind, ExplorationNodeKind.tutorResponse);
    expect(tree.activeLeaf!.materialIds, contains('quadratic-interactive'));
    expect(tree.activeLeaf!.text, contains('反问：'));
  });

  test('inappropriate input does not add nodes', () async {
    final scenario = await _scenario(contentRepository, 'teaching-quadratic');
    final mastery = await _mastery(
      masteryRepository,
      scenario.atomId,
      StudentMasteryLevel.developing,
    );
    await controller.start(
      scenario: scenario,
      mastery: mastery,
      question: scenario.openingPrompt,
    );
    final before = controller.state.tree!.nodes.length;

    await expectLater(
      controller.submitQuestion(MockExplorationGateway.inappropriateTestInput),
      throwsA(isA<ExplorationInputRejectedException>()),
    );

    expect(controller.state.tree!.nodes, hasLength(before));
  });

  test('business demo reaches depth, branches, and three material kinds', () async {
    final scenario = await _scenario(
      contentRepository,
      'demo-coffee-business-model',
    );
    final mastery = await _mastery(
      masteryRepository,
      scenario.atomId,
      StudentMasteryLevel.developing,
    );
    await controller.start(
      scenario: scenario,
      mastery: mastery,
      question: scenario.openingPrompt,
    );
    final branchAnchorId = controller.state.tree!.activeLeafId;

    await controller.submitQuestion('收入从哪里来？');
    await controller.submitQuestion('怎样计算单位经济模型？');
    await controller.submitQuestion(
      '最大的成本是什么？',
      branchFromNodeId: branchAnchorId,
    );
    await controller.submitQuestion(
      '护城河可能是什么？',
      branchFromNodeId: branchAnchorId,
    );

    final tree = controller.state.tree!;
    final materialIds = tree.nodes
        .where((node) => node.kind == ExplorationNodeKind.tutorResponse)
        .expand((node) => node.materialIds)
        .toSet();
    final materials = await contentRepository.loadMaterials(materialIds);
    expect(tree.maxPathDepth, greaterThanOrEqualTo(6));
    expect(tree.sideBranchCount, 2);
    expect(materials.map((item) => item.kind).toSet().length, greaterThanOrEqualTo(3));
    expect(
      tree.nodes
          .where((node) => node.kind == ExplorationNodeKind.tutorResponse)
          .every((node) => !node.text.contains('你觉得呢')),
      isTrue,
    );
  });

  test('saves a versioned trace and converts a node idempotently', () async {
    final scenario = await _scenario(contentRepository, 'teaching-quadratic');
    final mastery = await _mastery(
      masteryRepository,
      scenario.atomId,
      StudentMasteryLevel.developing,
    );
    await controller.start(
      scenario: scenario,
      mastery: mastery,
      question: scenario.openingPrompt,
    );
    final tutorNodeId = controller.state.tree!.activeLeafId;

    final firstId = await controller.convertNodeToMemory(tutorNodeId);
    final secondId = await controller.convertNodeToMemory(tutorNodeId);
    final record = await controller.saveTrace(reflection: '顶点来自平方项的边界值。');
    final exported = ExplorationTraceExporter.toVersionedJson(record);

    expect(firstId, secondId);
    expect(memoryCandidateSink.items, hasLength(1));
    expect(traceRepository.items, hasLength(1));
    expect(exported['schemaVersion'], 1);
    expect(exported['reflection'], '顶点来自平方项的边界值。');
    expect(exported['nodes'], isNotEmpty);
  });
}

Future<ExplorationScenario> _scenario(
  MockExplorationContentRepository repository,
  String id,
) async {
  return (await repository.loadScenarios()).singleWhere((item) => item.id == id);
}

Future<StudentMasterySnapshot> _mastery(
  MockStudentMasteryRepository repository,
  String atomId,
  StudentMasteryLevel level,
) async {
  return (await repository.availableProfiles(atomId)).singleWhere(
    (item) => item.level == level,
  );
}

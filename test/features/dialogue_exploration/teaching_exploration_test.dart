import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  late MockExplorationContentRepository contentRepository;
  late MockStudentMasteryRepository masteryRepository;
  late TeachingExplorationStrategy strategy;
  late ExplorationScenario scenario;

  setUp(() async {
    contentRepository = MockExplorationContentRepository();
    masteryRepository = MockStudentMasteryRepository();
    strategy = TeachingExplorationStrategy(
      gateway: MockExplorationGateway(delay: Duration.zero),
    );
    scenario = (await contentRepository.loadScenarios()).singleWhere(
      (item) => item.id == 'teaching-quadratic',
    );
  });

  test('weak mastery repairs prerequisites with figure and interaction', () async {
    final profile = await _profile(
      masteryRepository,
      StudentMasteryLevel.weak,
    );

    final response = await strategy.respond(
      scenario: scenario,
      mastery: profile,
      question: '二次函数的顶点为什么在这里？',
      ancestorTexts: const [],
    );

    expect(response.intent, ExplorationIntent.repairPrerequisite);
    expect(response.materialIds, {
      'quadratic-figure',
      'quadratic-interactive',
    });
    expect(response.answer, contains('先把顶点看成'));
    expect(response.followUpQuestion, contains('条件'));
  });

  test('strong mastery extends the derivation without repeating definition', () async {
    final profile = await _profile(
      masteryRepository,
      StudentMasteryLevel.strong,
    );

    final response = await strategy.respond(
      scenario: scenario,
      mastery: profile,
      question: '二次函数的顶点为什么在这里？',
      ancestorTexts: const [],
    );

    expect(response.intent, ExplorationIntent.extendReasoning);
    expect(response.materialIds, contains('quadratic-formula'));
    expect(response.answer, isNot(contains('二次函数是')));
    expect(response.followUpQuestion, contains('成立'));
  });

  test('unknown mastery probes prior knowledge instead of assuming a level', () async {
    final profile = await _profile(
      masteryRepository,
      StudentMasteryLevel.unknown,
    );

    final response = await strategy.respond(
      scenario: scenario,
      mastery: profile,
      question: '二次函数的顶点为什么在这里？',
      ancestorTexts: const [],
    );

    expect(response.intent, ExplorationIntent.probePriorKnowledge);
    expect(response.answer, contains('先不假设你已经掌握'));
  });

  test('never selects more than two or out-of-bound materials', () async {
    final profile = await _profile(
      masteryRepository,
      StudentMasteryLevel.developing,
    );

    final response = await strategy.respond(
      scenario: scenario,
      mastery: profile,
      question: '参数 a 改变时图像会怎样？',
      ancestorTexts: const [],
    );

    expect(response.materialIds.length, lessThanOrEqualTo(2));
    expect(
      response.materialIds.difference(scenario.allowedMaterialIds),
      isEmpty,
    );
  });

  test('distinguishes above-stage and unrelated questions', () async {
    final profile = await _profile(
      masteryRepository,
      StudentMasteryLevel.developing,
    );

    final aboveStage = await strategy.respond(
      scenario: scenario,
      mastery: profile,
      question: '能用泛函分析解释这个顶点吗？',
      ancestorTexts: const [],
    );
    final unrelated = await strategy.respond(
      scenario: scenario,
      mastery: profile,
      question: '今天天气怎么样？',
      ancestorTexts: const [],
    );

    expect(aboveStage.boundary, ExplorationInputBoundary.aboveStage);
    expect(aboveStage.answer, contains('超出当前学段'));
    expect(unrelated.boundary, ExplorationInputBoundary.unrelated);
    expect(unrelated.isSideBranchSuggested, isTrue);
  });

  test('rejects inappropriate input without producing a response', () async {
    final profile = await _profile(
      masteryRepository,
      StudentMasteryLevel.developing,
    );

    expect(
      () => strategy.respond(
        scenario: scenario,
        mastery: profile,
        question: MockExplorationGateway.inappropriateTestInput,
        ancestorTexts: const [],
      ),
      throwsA(isA<ExplorationInputRejectedException>()),
    );
  });

  test('question scaffolds provide templates and never auto-generate answers', () {
    expect(TeachingExplorationStrategy.questionScaffolds, const [
      '是什么',
      '为什么会这样',
      '如果……会怎样',
      '这和 X 有什么关系',
      '这有什么用',
    ]);
  });

  test('every successful response asks a principle or condition question', () async {
    final profile = await _profile(
      masteryRepository,
      StudentMasteryLevel.developing,
    );

    for (final question in scenario.seedQuestions) {
      final response = await strategy.respond(
        scenario: scenario,
        mastery: profile,
        question: question,
        ancestorTexts: const [],
      );
      expect(response.followUpQuestion.trim(), isNotEmpty);
      expect(response.followUpQuestion, isNot(contains('你觉得呢')));
      expect(
        response.followUpQuestion.contains('条件') ||
            response.followUpQuestion.contains('依据') ||
            response.followUpQuestion.contains('为什么') ||
            response.followUpQuestion.contains('变化'),
        isTrue,
      );
    }
  });
}

Future<StudentMasterySnapshot> _profile(
  MockStudentMasteryRepository repository,
  StudentMasteryLevel level,
) async {
  final profiles = await repository.availableProfiles('quadratic-vertex');
  return profiles.singleWhere((profile) => profile.level == level);
}

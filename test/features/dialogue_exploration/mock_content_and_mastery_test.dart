import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  group('Mock exploration content', () {
    test('covers teaching, practice, and public demo scenarios', () async {
      final repository = MockExplorationContentRepository();

      final scenarios = await repository.loadScenarios();

      expect(
        scenarios.map((scenario) => scenario.id),
        containsAll(<String>[
          'teaching-quadratic',
          'practice-inequality',
          'demo-coffee-business-model',
        ]),
      );
      expect(
        scenarios.map((scenario) => scenario.kind).toSet(),
        <ExplorationScenarioKind>{
          ExplorationScenarioKind.teaching,
          ExplorationScenarioKind.practice,
          ExplorationScenarioKind.publicDemo,
        },
      );
    });

    test('keeps material references complete and within each scenario', () async {
      final repository = MockExplorationContentRepository();
      final scenarios = await repository.loadScenarios();
      final referencedIds = scenarios
          .expand((scenario) => scenario.allowedMaterialIds)
          .toSet();

      final materials = await repository.loadMaterials(referencedIds);

      expect(await repository.validateFixtures(), isEmpty);
      expect(materials.map((material) => material.kind).toSet(), {
        ExplorationMaterialKind.figure,
        ExplorationMaterialKind.video,
        ExplorationMaterialKind.interactive,
        ExplorationMaterialKind.formula,
      });
      expect(materials.map((material) => material.id).toSet(), referencedIds);
    });

    test('returns unmodifiable scenario collections', () async {
      final repository = MockExplorationContentRepository();
      final scenarios = await repository.loadScenarios();

      expect(
        () => scenarios.first.allowedMaterialIds.add('outside-material'),
        throwsUnsupportedError,
      );
      expect(
        () => scenarios.first.seedQuestions.add('outside-question'),
        throwsUnsupportedError,
      );
    });
  });

  group('Mock student mastery', () {
    test('provides unknown, weak, developing, and strong profiles', () async {
      final repository = MockStudentMasteryRepository();

      final profiles = await repository.availableProfiles('quadratic-vertex');

      expect(profiles.map((profile) => profile.level).toSet(), {
        StudentMasteryLevel.unknown,
        StudentMasteryLevel.weak,
        StudentMasteryLevel.developing,
        StudentMasteryLevel.strong,
      });
      expect(
        profiles.every((profile) => profile.atomId == 'quadratic-vertex'),
        isTrue,
      );
      expect(profiles.every((profile) => profile.source.isNotEmpty), isTrue);
    });

    test('does not claim evidence for the unknown profile', () async {
      final repository = MockStudentMasteryRepository();
      final profiles = await repository.availableProfiles('quadratic-vertex');
      final unknown = profiles.singleWhere(
        (profile) => profile.level == StudentMasteryLevel.unknown,
      );

      expect(unknown.recentEvidence, isEmpty);
      expect(unknown.misconceptionTags, isEmpty);
      expect(unknown.source, 'mock:no-history');
    });
  });
}

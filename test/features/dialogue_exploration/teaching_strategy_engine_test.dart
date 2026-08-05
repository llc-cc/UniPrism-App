import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  final mastery = StudentMasterySnapshot(
    atomId: 'negative-multiplication',
    level: StudentMasteryLevel.developing,
    recentEvidence: const [],
    misconceptionTags: const [],
    preferredMaterialKinds: const [],
    observedAt: DateTime.utc(2026, 8, 5),
    source: 'test',
  );
  const engine = TeachingStrategyEngine();

  test('a new exploration starts with a problem chain', () {
    final decision = engine.decide(
      turnIndex: 0,
      studentText: '为什么负负得正？',
      consecutiveErrors: 0,
      isClosing: false,
      mastery: mastery,
    );

    expect(decision.mode, TeachingDialogueMode.problemChain);
    expect(decision.goal, TeachingStrategyGoal.mapQuestion);
  });

  test('an abstract or stuck signal switches to analogy transfer', () {
    final decision = engine.decide(
      turnIndex: 2,
      studentText: '太抽象了，我还是不懂有什么用',
      consecutiveErrors: 0,
      isClosing: false,
      mastery: mastery,
    );

    expect(decision.mode, TeachingDialogueMode.analogyTransfer);
    expect(decision.reason, contains('抽象'));
  });

  test('verified error evidence has priority over other teaching modes', () {
    final decision = engine.decide(
      turnIndex: 2,
      studentText: '这也太抽象了，所以负负还是负数',
      consecutiveErrors: 1,
      isClosing: false,
      mastery: mastery,
    );

    expect(decision.mode, TeachingDialogueMode.errorTracing);
    expect(decision.goal, TeachingStrategyGoal.repairMisconception);
  });

  test('closing always asks the student for self explanation', () {
    final decision = engine.decide(
      turnIndex: 5,
      studentText: '我来总结',
      consecutiveErrors: 0,
      isClosing: true,
      mastery: mastery,
    );

    expect(decision.mode, TeachingDialogueMode.selfExplanation);
    expect(decision.allowMaterial, isFalse);
  });

  test('a normal concept turn uses a principle-directed Socratic prompt', () {
    final decision = engine.decide(
      turnIndex: 2,
      studentText: '负号可以表示相反方向',
      consecutiveErrors: 0,
      isClosing: false,
      mastery: mastery,
    );

    expect(decision.mode, TeachingDialogueMode.socratic);
    expect(decision.depth, 3);
  });
}

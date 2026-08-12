import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/student_learning_narrative.dart';

void main() {
  group('student learning narrative', () {
    test(
      'keeps the third-round demonstration focused on a new independent question',
      () {
        expect(
          StudentLearningNarrative.supportMessage(3),
          '我们先完整走一遍例子，再换一道新题由你独立完成。',
        );
      },
    );

    test('turns technical teaching stages into student actions', () {
      expect(
        StudentLearningNarrative.stageTitle(RemoteTeachingStage.dialogue),
        '先说说你的猜想',
      );
      expect(
        StudentLearningNarrative.stageTitle(RemoteTeachingStage.asset),
        '我们验证一下',
      );
      expect(
        StudentLearningNarrative.stageLabel(RemoteTeachingStage.focus),
        '迁移应用',
      );
      expect(
        StudentLearningNarrative.stageLabel(RemoteTeachingStage.reflect),
        '整理收获',
      );
    });

    test('turns exploration acts into the dialogue-first learning journey', () {
      expect(
        StudentLearningNarrative.explorationTitle(
          RemoteGuidedExplorationAct.probeReason,
        ),
        '说说为什么会这样想',
      );
      expect(
        StudentLearningNarrative.explorationTitle(
          RemoteGuidedExplorationAct.postAssetObservation,
        ),
        '从现象里找证据',
      );
      expect(StudentLearningNarrative.explorationJourney, [
        '明确问题',
        '说出理由',
        '换种情况',
        '动手验证',
        '观察深挖',
        '形成发现',
        '迁移应用',
      ]);
      expect(
        StudentLearningNarrative.explorationTitle(
          RemoteGuidedExplorationAct.readyForCheck,
        ),
        '换个情况试试',
      );
      expect(
        StudentLearningNarrative.explorationTitle(
          RemoteGuidedExplorationAct.transferRevisit,
        ),
        '回到发现，修正薄弱点',
      );
    });

    test('describes missing evidence as another student verification', () {
      const evidence = RemoteEvidenceState(
        schemaVersion: 1,
        requiredCodes: ['observed-operation', 'independent-explanation'],
        items: [],
        missingCodes: ['observed-operation', 'independent-explanation'],
        isReadyForMicroCheck: false,
      );

      expect(
        StudentLearningNarrative.verificationMessage(evidence),
        '还需要 2 次验证，确认你的想法',
      );
    });

    test('keeps model provenance quiet and turns fallback into a hint', () {
      expect(
        StudentLearningNarrative.answerContextLabel('SAFE_FALLBACK'),
        '当前提示',
      );
      expect(
        StudentLearningNarrative.answerContextLabel('MODEL_PRIOR'),
        isNull,
      );
      expect(
        StudentLearningNarrative.answerContextLabel('KNOWLEDGE_BASE'),
        isNull,
      );
    });

    test('turns chapter phases and statuses into a learning journey', () {
      expect(StudentLearningNarrative.chapterPhaseTitle('LEARNING'), '先发现规律');
      expect(StudentLearningNarrative.chapterPhaseTitle('PRACTICE'), '动手试一试');
      expect(StudentLearningNarrative.chapterPhaseTitle('REVIEW'), '回看我的发现');
      expect(
        StudentLearningNarrative.chapterPhaseStatus('IN_PROGRESS'),
        '正在这里',
      );
      expect(StudentLearningNarrative.chapterPhaseStatus('LOCKED'), '完成前面后开启');
    });
  });
}

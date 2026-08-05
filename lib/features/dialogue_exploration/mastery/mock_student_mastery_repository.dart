import '../core/exploration_models.dart';
import 'student_mastery.dart';

/// 供开发实验室切换的四档掌握快照，不写入正式学生画像。
final class MockStudentMasteryRepository implements StudentMasteryRepository {
  static final DateTime _observedAt = DateTime.utc(2026, 8, 5, 8);

  @override
  Future<List<StudentMasterySnapshot>> availableProfiles(String atomId) async {
    return List.unmodifiable(<StudentMasterySnapshot>[
      StudentMasterySnapshot(
        atomId: atomId,
        level: StudentMasteryLevel.unknown,
        recentEvidence: const [],
        misconceptionTags: const [],
        preferredMaterialKinds: const [],
        observedAt: _observedAt,
        source: 'mock:no-history',
      ),
      StudentMasterySnapshot(
        atomId: atomId,
        level: StudentMasteryLevel.weak,
        recentEvidence: const ['最近两次无法解释顶点含义'],
        misconceptionTags: const ['把顶点与零点混淆'],
        preferredMaterialKinds: const [
          ExplorationMaterialKind.figure,
          ExplorationMaterialKind.interactive,
        ],
        observedAt: _observedAt,
        source: 'mock:weak-profile',
      ),
      StudentMasterySnapshot(
        atomId: atomId,
        level: StudentMasteryLevel.developing,
        recentEvidence: const ['能识别顶点，但配方过程需要提示'],
        misconceptionTags: const ['参数 h 的符号方向不稳定'],
        preferredMaterialKinds: const [
          ExplorationMaterialKind.formula,
          ExplorationMaterialKind.interactive,
        ],
        observedAt: _observedAt,
        source: 'mock:developing-profile',
      ),
      StudentMasterySnapshot(
        atomId: atomId,
        level: StudentMasteryLevel.strong,
        recentEvidence: const ['无提示完成一般式到顶点式转换'],
        misconceptionTags: const [],
        preferredMaterialKinds: const [
          ExplorationMaterialKind.formula,
          ExplorationMaterialKind.figure,
        ],
        observedAt: _observedAt,
        source: 'mock:strong-profile',
      ),
    ]);
  }
}
